# CLAUDE.md - Project Context for Claude Code

## Project Overview

This is a CDK (Cloud Development Kit) project that deploys a remote development environment on AWS. The environment provides VS Code in the browser via code-server, with Claude Code CLI pre-installed.

## Tech Stack

- **Infrastructure**: AWS CDK v2 (TypeScript)
- **Compute**: EC2 t4g.small (ARM64, Amazon Linux 2023)
- **Web Server**: nginx (reverse proxy with HTTPS)
- **SSL**: Let's Encrypt via Certbot
- **IP**: Optional Elastic IP for static addressing
- **IDE**: code-server (VS Code in browser)
- **AI Assistant**: Claude Code CLI

## Project Structure

```
claude-server/
+-- bin/claude-server.ts       # CDK app entry point
+-- lib/claude-server-stack.ts # Main CDK stack
+-- config/
|   +-- config.example.ts      # Configuration template (committed)
|   +-- config.ts              # Actual config (gitignored)
+-- scripts/
|   +-- init.sh                # EC2 user-data script
+-- test/                      # CDK tests
```

## Key Files

### config/config.ts
Contains sensitive configuration (domain, passwords, etc.). Copy from `config.example.ts` and fill in real values. This file is gitignored.

### lib/claude-server-stack.ts
Main CDK stack that creates:
- VPC (uses default)
- Security Group (ports 22, 80, 443)
- IAM Role (SSM permissions only)
- EC2 Instance with user-data
- Optional Elastic IP (if `useElasticIp: true`)

### scripts/init.sh
Runs at EC2 boot to:
1. Install nginx, code-server, certbot
2. Configure HTTPS with Let's Encrypt
3. Install Claude Code CLI

## Common Commands

```bash
# Synthesize CloudFormation
cdk synth

# Deploy stack
cdk deploy

# Show changes
cdk diff

# Destroy stack
cdk destroy

# Run tests
npm test
```

## Configuration

All configuration is in `config/config.ts`:
- `domain`: Domain for the dev server (DNS must be configured manually)
- `useElasticIp`: Use static Elastic IP (optional, default: false)
- `codeServerPassword`: Password for VS Code web access
- `email`: Email for Let's Encrypt
- `keyPairName`: EC2 key pair for SSH
- `instanceType`: EC2 instance type (t4g.small default)
- `volumeSize`: EBS volume size in GB

## Important Notes

1. **Never commit config/config.ts** - it contains secrets
2. **DNS must be configured manually** - create an A record pointing to the instance IP
3. **Region is fixed to us-east-1** - can be changed in bin/claude-server.ts
4. **SSH is open to 0.0.0.0/0** - intentional for flexibility with Termius
5. **SSM Session Manager is enabled** as backup access method

## Debugging

- User-data logs: `/var/log/user-data.log` on the EC2 instance
- code-server logs: `journalctl -u code-server@ec2-user`
- nginx logs: `/var/log/nginx/error.log`
