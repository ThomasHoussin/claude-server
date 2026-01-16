set -e

# Logging setup
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "=========================================="
echo "Starting setup at $(date)"
echo "=========================================="

# === CONFIGURATION (injected by CDK) ===
DOMAIN="__DOMAIN__"
CODE_SERVER_PASSWORD="__CODE_SERVER_PASSWORD__"
EMAIL="__EMAIL__"

# === INSTALLATION PACKAGES ===
echo "[1/6] Installing packages..."
dnf update -y
dnf install -y nginx git nodejs npm

# === CODE-SERVER ===
echo "[2/6] Installing code-server..."
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

# Service code-server
systemctl enable --now code-server@ec2-user

# === NGINX (HTTP only for certbot) ===
echo "[3/6] Configuring nginx..."
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
echo "[4/6] Setting up SSL certificate..."
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

# === ADDITIONAL SSH KEYS ===
echo "[5/6] Adding additional SSH keys..."
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
echo "[6/6] Installing Claude Code..."
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
echo "  Password: (configured in code-server)"
echo ""
echo "SSH: ssh ec2-user@${DOMAIN}"
echo ""
