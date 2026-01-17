import { Stack, CfnOutput, Duration, type StackProps } from 'aws-cdk-lib';
import {
  Vpc,
  SecurityGroup,
  Peer,
  Port,
  Instance,
  InstanceType,
  InstanceClass,
  InstanceSize,
  MachineImage,
  AmazonLinuxCpuType,
  UserData,
  KeyPair,
  BlockDeviceVolume,
  EbsDeviceVolumeType,
  CfnEIP,
  CfnEIPAssociation,
} from 'aws-cdk-lib/aws-ec2';
import {
  Role,
  ServicePrincipal,
  ManagedPolicy,
} from 'aws-cdk-lib/aws-iam';
import { StringParameter } from 'aws-cdk-lib/aws-ssm';
import { HostedZone, ARecord, RecordTarget } from 'aws-cdk-lib/aws-route53';
import { Construct } from 'constructs';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { config, type Config } from '../config/config.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Validate configuration values before deployment
 */
function validateConfig(cfg: Config): void {
  // Domain validation
  if (!cfg.domain || !/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$/i.test(cfg.domain)) {
    throw new Error(`Invalid domain format: "${cfg.domain}". Expected format: subdomain.domain.tld`);
  }

  // Hosted Zone ID validation (optional, but if provided must start with Z)
  if (cfg.hostedZoneId && !cfg.hostedZoneId.startsWith('Z')) {
    throw new Error(`Invalid hostedZoneId: "${cfg.hostedZoneId}". Must start with 'Z'`);
  }

  // SSM Parameter name validation
  if (!cfg.ssmPasswordParameterName || !cfg.ssmPasswordParameterName.startsWith('/')) {
    throw new Error('ssmPasswordParameterName must start with "/" (e.g., /claude-server/code-server-password)');
  }

  // Email validation
  if (!cfg.email || !cfg.email.includes('@') || !cfg.email.includes('.')) {
    throw new Error(`Invalid email format: "${cfg.email}"`);
  }

  // Key pair name validation
  if (!cfg.keyPairName || cfg.keyPairName.trim() === '') {
    throw new Error('keyPairName is required');
  }

  // Volume size validation (AWS limits: 1-16384 GB)
  if (cfg.volumeSize < 8 || cfg.volumeSize > 16384) {
    throw new Error(`volumeSize must be between 8 and 16384 GB, got: ${cfg.volumeSize}`);
  }

  // Validate SSH public keys format
  if (cfg.additionalSshPublicKeys) {
    const sshKeyPattern = /^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp)/;
    cfg.additionalSshPublicKeys.forEach((key, index) => {
      if (!sshKeyPattern.test(key)) {
        throw new Error(
          `additionalSshPublicKeys[${index}] is not a valid SSH public key. ` +
          `Expected format: "ssh-rsa AAAA..." or "ssh-ed25519 AAAA..."`
        );
      }
    });
  }
}

/**
 * Parse and validate EC2 instance type
 */
function parseInstanceType(instanceType: string): { instanceClass: InstanceClass; instanceSize: InstanceSize } {
  const parts = instanceType.split('.');

  if (parts.length !== 2) {
    throw new Error(
      `Invalid instanceType format: "${instanceType}". Expected format: class.size (e.g., t4g.small)`
    );
  }

  const [classStr, sizeStr] = parts;
  const classKey = classStr.toUpperCase() as keyof typeof InstanceClass;
  const sizeKey = sizeStr.toUpperCase() as keyof typeof InstanceSize;

  // Validate instance class exists
  if (!(classKey in InstanceClass)) {
    throw new Error(`Unknown instance class: "${classStr}". Check AWS EC2 instance types.`);
  }

  // Validate instance size exists
  if (!(sizeKey in InstanceSize)) {
    throw new Error(`Unknown instance size: "${sizeStr}". Check AWS EC2 instance types.`);
  }

  return {
    instanceClass: InstanceClass[classKey],
    instanceSize: InstanceSize[sizeKey],
  };
}

export class ClaudeServerStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // Validate configuration at synthesis time
    validateConfig(config);

    // Parse and validate instance type
    const { instanceClass, instanceSize } = parseInstanceType(config.instanceType);

    // Use default VPC
    const vpc = Vpc.fromLookup(this, 'VPC', { isDefault: true });

    // Security Group
    const securityGroup = new SecurityGroup(this, 'DevServerSG', {
      vpc,
      description: 'Security group for remote dev server',
      allowAllOutbound: true,
    });

    // HTTPS access for code-server
    securityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(443),
      'HTTPS access for code-server'
    );

    // HTTP for certbot validation
    securityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(80),
      'HTTP for Lets Encrypt validation'
    );

    // SSH access (open to all as per user preference)
    securityGroup.addIngressRule(
      Peer.anyIpv4(),
      Port.tcp(22),
      'SSH access'
    );

    // IAM Role for the instance
    const role = new Role(this, 'DevInstanceRole', {
      assumedBy: new ServicePrincipal('ec2.amazonaws.com'),
    });

    // SSM permission for backup access via AWS Console
    role.addManagedPolicy(
      ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
    );

    // Reference existing SecureString parameter (created manually by user)
    const passwordParameter = StringParameter.fromSecureStringParameterAttributes(
      this, 'CodeServerPassword', {
        parameterName: config.ssmPasswordParameterName,
      }
    );

    // Grant read access to the instance
    passwordParameter.grantRead(role);

    // Read and configure user data script
    // Note: Password is NOT injected here - retrieved from SSM at runtime
    const additionalSshKeys = config.additionalSshPublicKeys?.join('\n') || '';
    const userDataScript = readFileSync(
      join(__dirname, '..', 'scripts', 'init.sh'),
      'utf8'
    )
      .replace(/__DOMAIN__/g, config.domain)
      .replace(/__EMAIL__/g, config.email)
      .replace(/__ADDITIONAL_SSH_KEYS__/g, additionalSshKeys)
      .replace(/__AWS_REGION__/g, config.region)
      .replace(/__SSM_PASSWORD_PARAMETER__/g, config.ssmPasswordParameterName)
      .replace(/__ENABLE_SSH_PASSWORD_AUTH__/g, config.enableSshPasswordAuth ? 'true' : 'false');

    const userData = UserData.forLinux();
    userData.addCommands(userDataScript);

    // EC2 Instance
    const instance = new Instance(this, 'DevInstance', {
      vpc,
      instanceType: InstanceType.of(instanceClass, instanceSize),
      machineImage: MachineImage.latestAmazonLinux2023({
        cpuType: AmazonLinuxCpuType.ARM_64,
      }),
      securityGroup,
      role,
      userData,
      keyPair: KeyPair.fromKeyPairName(this, 'KeyPair', config.keyPairName),
      blockDevices: [{
        deviceName: '/dev/xvda',
        volume: BlockDeviceVolume.ebs(config.volumeSize, {
          volumeType: EbsDeviceVolumeType.GP3,
        }),
      }],
    });

    // Elastic IP (optional)
    let publicIp = instance.instancePublicIp;
    let dnsAutoConfigured = false;

    if (config.useElasticIp) {
      const eip = new CfnEIP(this, 'DevServerEIP', {
        domain: 'vpc',
      });

      new CfnEIPAssociation(this, 'DevServerEIPAssociation', {
        allocationId: eip.attrAllocationId,
        instanceId: instance.instanceId,
      });

      publicIp = eip.attrPublicIp;

      // Create DNS record automatically if hostedZoneId is provided
      if (config.hostedZoneId) {
        const hostedZone = HostedZone.fromHostedZoneAttributes(this, 'HostedZone', {
          hostedZoneId: config.hostedZoneId,
          zoneName: config.domain.split('.').slice(1).join('.'), // Extract parent domain
        });

        new ARecord(this, 'DevServerDNS', {
          zone: hostedZone,
          recordName: config.domain,
          target: RecordTarget.fromIpAddresses(eip.attrPublicIp),
          ttl: Duration.minutes(5),
        });

        dnsAutoConfigured = true;
      }
    }

    // Outputs
    new CfnOutput(this, 'InstanceId', {
      value: instance.instanceId,
      description: 'EC2 Instance ID',
    });

    new CfnOutput(this, 'PublicIP', {
      value: publicIp,
      description: config.useElasticIp ? 'Elastic IP address (static)' : 'Public IP address (changes on restart)',
    });

    new CfnOutput(this, 'AccessURL', {
      value: `https://${config.domain}`,
      description: 'URL to access code-server',
    });

    new CfnOutput(this, 'SSHCommand', {
      value: `ssh ec2-user@${config.domain}`,
      description: 'SSH command to connect',
    });

    new CfnOutput(this, 'DNSSetup', {
      value: dnsAutoConfigured
        ? `DNS A record created automatically for ${config.domain}`
        : `Create A record: ${config.domain} -> <PublicIP>`,
      description: dnsAutoConfigured
        ? 'DNS configured automatically via CDK'
        : 'DNS configuration required (manual setup in Route 53)',
    });

    new CfnOutput(this, 'PasswordLocation', {
      value: `SSM Parameter Store: ${config.ssmPasswordParameterName}`,
      description: 'Password stored securely in SSM Parameter Store (SecureString)',
    });
  }
}
