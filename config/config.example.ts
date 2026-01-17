/**
 * Configuration template for Claude Server
 *
 * Copy this file to config.ts and fill in your actual values.
 * config.ts is gitignored to keep your secrets safe.
 */

export interface Config {
  // AWS region for deployment (e.g., us-east-1, eu-west-1)
  region: string;

  // Your domain for code-server (e.g., dev.yourdomain.com)
  domain: string;

  // Route 53 Hosted Zone ID (optional)
  // When provided with useElasticIp: CDK creates the DNS A record automatically
  // When omitted: DNS must be configured manually
  hostedZoneId?: string;

  // Use Elastic IP for static IP address (optional, default: false)
  // When true: creates a static IP that persists across instance stops
  // When false: uses auto-assigned public IP (changes on restart)
  useElasticIp?: boolean;

  // SSM Parameter name containing the code-server password
  // Must be created manually as SecureString before deployment
  ssmPasswordParameterName: string;

  // Email for Let's Encrypt certificate notifications
  email: string;

  // EC2 Key Pair name for SSH access (must exist in AWS)
  keyPairName: string;

  // Additional SSH public keys (optional)
  // These keys are added to ~/.ssh/authorized_keys in addition to the EC2 key pair
  // Useful for YubiKeys or keys from other machines
  additionalSshPublicKeys?: string[];

  // EC2 instance type (t4g.micro or t4g.small recommended)
  instanceType: string;

  // EBS volume size in GB
  volumeSize: number;

  // Enable SSH password authentication (optional, default: false)
  // When true, uses the same password as code-server for SSH login
  enableSshPasswordAuth?: boolean;
}

export const config: Config = {
  region: 'us-east-1',
  domain: 'dev.example.com',
  hostedZoneId: 'ZXXXXXXXXXXXXX', // Optional: enables automatic DNS setup
  useElasticIp: true,
  ssmPasswordParameterName: '/claude-server/code-server-password',
  email: 'your@email.com',
  keyPairName: 'your-key-pair-name',
  additionalSshPublicKeys: [
    // 'ssh-rsa AAAAB3NzaC1... user@machine',
  ],
  instanceType: 't4g.small',
  volumeSize: 30,
  enableSshPasswordAuth: false,
};
