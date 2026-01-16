# Claude Server - Remote Dev Environment

A CDK stack that deploys a remote development environment accessible via browser, featuring:

- **code-server** (VS Code in the browser)
- **nginx** reverse proxy with HTTPS
- **Let's Encrypt** automatic SSL certificate
- **Route 53** DNS (optional, for automatic DNS management)
- **Claude Code CLI** pre-installed

## Architecture

```
+-------------+      HTTPS/443   +-----------------------------+
|   Browser   | ---------------> |  EC2 Instance               |
+-------------+                  |  +-- nginx (reverse proxy)  |
                                 |  +-- code-server (VS Code)  |
+-------------+      SSH/22      |  +-- Claude Code CLI        |
|   Termius   | ---------------> |                             |
+-------------+                  +-----------------------------+
                                           |
                                           v
                                 +-----------------------------+
                                 |  Route 53 (optional)        |
                                 |  dev.yourdomain.com -> IP   |
                                 +-----------------------------+
```

## Project Structure

```
claude-server/
├── bin/claude-server.ts       # CDK app entry point
├── lib/claude-server-stack.ts # Main CDK stack
├── config/
│   ├── config.example.ts      # Configuration template (committed)
│   └── config.ts              # Actual config (gitignored)
├── scripts/
│   └── init.sh                # EC2 user-data script
└── test/                      # CDK tests
```

## Prerequisites

1. **AWS Account** with CLI configured (`aws configure`)
2. **Node.js** 18+ installed
3. **AWS CDK** installed globally: `npm install -g aws-cdk`
4. **EC2 Key Pair** created in your target region
5. **Route 53 Hosted Zone** (optional, for automatic DNS management)

## Setup

### 1. Install dependencies

```bash
npm install
```

### 2. Create your configuration

```bash
cp config/config.example.ts config/config.ts
```

Edit `config/config.ts` with your values:

| Variable | Description | Example |
|----------|-------------|---------|
| `region` | AWS region for deployment | `us-east-1` |
| `domain` | Subdomain for code-server | `dev.mysite.com` |
| `codeServerPassword` | Password for code-server access | `MyStr0ngP@ss!` |
| `email` | Email for Let's Encrypt | `me@email.com` |
| `keyPairName` | EC2 Key Pair name | `my-key-pair` |
| `instanceType` | EC2 instance type (optional) | `t4g.small` |
| `volumeSize` | EBS volume size in GB (optional) | `30` |
| `useElasticIp` | Use static Elastic IP (optional) | `true` |
| `hostedZoneId` | Route 53 Hosted Zone ID (optional) | `Z0123456789ABC` |

**Note:** If `useElasticIp` is `true` and `hostedZoneId` is provided, DNS is managed automatically by CDK. Otherwise, create the DNS A record manually.

### 3. Bootstrap CDK (first time only)

```bash
cdk bootstrap aws://YOUR_ACCOUNT_ID/YOUR_REGION
```

### 4. Deploy

```bash
cdk deploy
```

## Usage

### Browser (code-server)

1. Open `https://dev.yourdomain.com`
2. Enter your code-server password
3. Open terminal (Ctrl+`) and run `claude`

### SSH (Termius)

1. Host: `dev.yourdomain.com`
2. User: `ec2-user`
3. Auth: Your EC2 key pair private key
4. Run `claude` in terminal

## Estimated Costs (us-east-1)

| Resource | Cost/month |
|----------|------------|
| EC2 t4g.small | ~$15 |
| Public IP | ~$3.60 |
| EBS 30GB GP3 | ~$2.40 |
| Route 53 | ~$0.50 |
| **Total** | **~$21/month** |

To reduce costs:
- Use `t4g.micro` (~$8/month total)
- Stop instance when not in use

## Commands

| Command | Description |
|---------|-------------|
| `cdk synth` | Generate CloudFormation template |
| `cdk deploy` | Deploy the stack |
| `cdk diff` | Show changes |
| `cdk destroy` | Delete the stack |

## Troubleshooting

### Check instance logs

```bash
# Via SSH
ssh ec2-user@dev.yourdomain.com
sudo cat /var/log/user-data.log

# Via AWS Console
# EC2 > Instance > Actions > Monitor > Get System Log
```

### Restart code-server

```bash
sudo systemctl restart code-server@ec2-user
```

### Renew SSL certificate

```bash
sudo certbot renew
```

## Security Notes

- SSH is open to all IPs (0.0.0.0/0). Consider restricting to your IP for better security.
- code-server is protected by password authentication.
- SSM Session Manager is enabled as a backup access method.
- Never commit `config/config.ts` to version control.

## License

MIT
