# Claude Server - Instructions for Claude Code

## Context

CDK project deploying a remote development environment on AWS: EC2 (ARM64) + code-server (VS Code browser) + Claude Code CLI.

## Key Files

- `lib/claude-server-stack.ts` - Main CDK stack (VPC, SG, EC2, optional Elastic IP, optional DNS)
- `config/config.ts` - Sensitive configuration (gitignored) - copy from `config.example.ts`
- `scripts/init.sh` - EC2 user-data script (installs nginx, code-server, certbot, Claude CLI)
- `bin/claude-server.ts` - CDK entry point

## Important Rules

1. **NEVER commit `config/config.ts`** - contains secrets (passwords, domain)
2. SSH open to 0.0.0.0/0 - intentional for flexibility with Termius
3. DNS managed by CDK (not by the EC2 instance) - if `useElasticIp: true` + `hostedZoneId` provided
4. The instance only has SSM permissions, not Route 53
5. **All documentation and comments must be in English**

## Configuration

Options in `config/config.ts`:
- `region` - AWS Region
- `domain` - Domain for code-server
- `hostedZoneId` - Route 53 zone (optional, for auto DNS)
- `useElasticIp` - Use a static IP (optional, default: false)
- `ssmPasswordParameterName` - SSM Parameter name for code-server password (SecureString)
- `email` - Let's Encrypt email
- `keyPairName` - EC2 key pair
- `additionalSshPublicKeys` - Additional SSH public keys (optional, for YubiKeys etc.)
- `instanceType` - Instance type (default: t4g.small)
- `volumeSize` - EBS volume size in GB
- `enableSshPasswordAuth` - Enable SSH password login (optional, default: false)

## SSM Password Setup (Required before deploy)

Create the password parameter manually as SecureString:

```bash
aws ssm put-parameter \
  --name "/claude-server/code-server-password" \
  --type SecureString \
  --value "your-strong-password" \
  --region us-east-1
```

## Commands

```bash
cdk synth    # Generate CloudFormation (validates SSM parameter)
cdk deploy   # Deploy (validates SSM parameter first)
cdk diff     # See changes
cdk destroy  # Destroy
npm test     # Tests
```

## Debugging

- User-data logs: `/var/log/user-data.log`
- code-server logs: `journalctl -u code-server@ec2-user`
- nginx logs: `/var/log/nginx/error.log`

