#!/bin/bash
set -e

# Logging setup
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "=========================================="
echo "Starting setup at $(date)"
echo "=========================================="

# === CONFIGURATION (injected by CDK) ===
DOMAIN="__DOMAIN__"
EMAIL="__EMAIL__"
AWS_REGION="__AWS_REGION__"
SSM_PASSWORD_PARAMETER="__SSM_PASSWORD_PARAMETER__"
ENABLE_SSH_PASSWORD_AUTH="__ENABLE_SSH_PASSWORD_AUTH__"

# === INSTALLATION PACKAGES ===
echo "[1/8] Installing packages..."
dnf update -y
dnf install -y nginx git nodejs22 nodejs22-npm tmux screen

# === GITHUB CLI ===
echo "[1b/8] Installing GitHub CLI..."
dnf install -y 'dnf-command(config-manager)'
dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
dnf install -y gh --repo gh-cli

# === RETRIEVE PASSWORD FROM SSM ===
echo "[2/8] Retrieving code-server password from SSM..."

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
  echo "ERROR: AWS CLI is not installed or not in PATH"
  exit 1
fi

# Retrieve password with explicit error handling
set +e  # Temporarily disable exit on error to capture the error message
SSM_OUTPUT=$(aws ssm get-parameter \
  --name "${SSM_PASSWORD_PARAMETER}" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "${AWS_REGION}" 2>&1)
SSM_EXIT_CODE=$?
set -e  # Re-enable exit on error

if [ $SSM_EXIT_CODE -ne 0 ]; then
  echo "ERROR: Failed to retrieve password from SSM Parameter Store"
  echo "Details: ${SSM_OUTPUT}"
  echo "Check: 1) Parameter exists, 2) IAM permissions, 3) Parameter name is correct"
  exit 1
fi

CODE_SERVER_PASSWORD="${SSM_OUTPUT}"

if [ -z "$CODE_SERVER_PASSWORD" ]; then
  echo "ERROR: Retrieved empty password from SSM Parameter Store (${SSM_PASSWORD_PARAMETER})"
  exit 1
fi
echo "Password retrieved successfully from SSM"

# === CODE-SERVER ===
echo "[3/8] Installing code-server..."
export HOME=/root
if ! command -v code-server &> /dev/null; then
  curl -fsSL https://code-server.dev/install.sh | sh
else
  echo "code-server already installed, skipping"
fi

# Config code-server
mkdir -p /home/ec2-user/.config/code-server
cat > /home/ec2-user/.config/code-server/config.yaml << EOF
bind-addr: 127.0.0.1:8080
auth: password
password: ${CODE_SERVER_PASSWORD}
cert: false
EOF

chown -R ec2-user:ec2-user /home/ec2-user/.config
chmod 600 /home/ec2-user/.config/code-server/config.yaml

# Service code-server
systemctl enable --now code-server@ec2-user

# === NGINX (HTTP only for certbot) ===
echo "[4/8] Configuring nginx..."
mkdir -p /var/www/html

cat > /etc/nginx/conf.d/code-server.conf << 'NGINX_EOF'
server {
    listen 80;
    server_name __DOMAIN__;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
NGINX_EOF

systemctl enable nginx
systemctl restart nginx

# === CERTBOT ===
echo "[5/8] Setting up SSL certificate..."
dnf install -y certbot

if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
  echo "SSL certificate already exists, skipping certbot"
else
  # Use webroot mode (no nginx plugin conflict)
  certbot certonly --webroot -w /var/www/html \
    -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}"
fi

# === NGINX SSL CONFIG ===
# Write the full SSL config (cert must exist at this point)
cat > /etc/nginx/conf.d/code-server.conf << 'NGINX_EOF'
# WebSocket upgrade mapping
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    server_name __DOMAIN__;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name __DOMAIN__;

    # SSL certificates
    ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;

    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Accept-Encoding gzip;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
NGINX_EOF

nginx -t && systemctl restart nginx

# === SSH PASSWORD AUTH (optional) ===
if [ "$ENABLE_SSH_PASSWORD_AUTH" = "true" ]; then
  echo "[6/8] Enabling SSH password authentication..."

  # Set ec2-user password (same as code-server)
  chpasswd <<< "ec2-user:${CODE_SERVER_PASSWORD}"

  # Enable password authentication in sshd_config (handles both commented and uncommented)
  sed -i -E 's/^#?PasswordAuthentication (yes|no)/PasswordAuthentication yes/' /etc/ssh/sshd_config

  # Validate sshd config before restart
  if ! sshd -t 2>/dev/null; then
    echo "ERROR: Invalid sshd configuration after enabling password auth"
    exit 1
  fi

  # Restart SSH service
  if ! systemctl restart sshd; then
    echo "ERROR: Failed to restart sshd service"
    exit 1
  fi

  echo "SSH password authentication enabled"
else
  echo "[6/8] SSH password authentication disabled (key-based only)"
fi

# === ADDITIONAL SSH KEYS ===
echo "[7/8] Adding additional SSH keys..."
ADDITIONAL_KEYS="__ADDITIONAL_SSH_KEYS__"

# Check if keys were provided (starts with ssh- means valid key, not empty placeholder)
if echo "$ADDITIONAL_KEYS" | grep -q "^ssh-"; then
  echo "$ADDITIONAL_KEYS" | while IFS= read -r key; do
    if [ -n "$key" ] && ! grep -qF "$key" /home/ec2-user/.ssh/authorized_keys 2>/dev/null; then
      echo "$key" >> /home/ec2-user/.ssh/authorized_keys
      echo "Added SSH key"
    fi
  done
  chmod 600 /home/ec2-user/.ssh/authorized_keys
  chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
else
  echo "No additional SSH keys configured"
fi

# === CLAUDE CODE ===
echo "[8/8] Installing Claude Code..."
if ! command -v claude &> /dev/null; then
  npm install -g @anthropic-ai/claude-code
else
  echo "Claude Code already installed, skipping"
fi

# === FINALISATION ===
echo "=========================================="
echo "Setup completed at $(date)"
echo "=========================================="
echo ""
echo "Access your dev environment:"
echo "  URL: https://${DOMAIN}"
echo "  Password: stored in SSM Parameter Store (${SSM_PASSWORD_PARAMETER})"
echo ""
echo "SSH: ssh ec2-user@${DOMAIN}"
echo ""
