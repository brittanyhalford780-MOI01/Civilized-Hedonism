#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — Server Bootstrap Script
#
# PURPOSE:
#   One-shot initialization & OS hardening of a fresh Ubuntu 24.04 server.
#
# USAGE:
#   chmod +x scripts/server-init.sh
#   sudo bash scripts/server-init.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "  MOI01.VIP — Server Bootstrap & OS Hardening"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "═══════════════════════════════════════════════════════════════"

if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "▸ Repository root: $REPO_ROOT"

# 1. System Update
echo "▸ [1/12] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# 2. Node.js 20 LTS
echo "▸ [2/12] Installing Node.js 20 LTS..."
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -qq nodejs
fi

# 3. Nginx
echo "▸ [3/12] Installing Nginx..."
apt-get install -y -qq nginx
systemctl enable nginx

# 4. Certbot
echo "▸ [4/12] Installing Certbot..."
apt-get install -y -qq certbot python3-certbot-nginx iotop

# 5. UFW Firewall
echo "▸ [5/12] Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable

# 5b. SSH Daemon Hardening (Key-Only Auth, Disable Passwords & Root Login)
echo "▸ Hardening SSH daemon (Disabling Password Auth & Root Login)..."
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-hardened.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
MaxAuthTries 3
EOF
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

# 6. Disable Swap (RAM-Only Guarantee)
echo "▸ [6/12] Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
if ! grep -q "vm.swappiness=0" /etc/sysctl.conf; then
    echo "vm.swappiness=0" >> /etc/sysctl.conf
fi

# 7. Disable Core Dumps
echo "▸ [7/12] Disabling core dumps..."
if ! grep -q "hard core 0" /etc/security/limits.conf; then
    echo "* hard core 0" >> /etc/security/limits.conf
fi
if ! grep -q "fs.suid_dumpable=0" /etc/sysctl.conf; then
    echo "fs.suid_dumpable=0" >> /etc/sysctl.conf
fi

# 8. Volatile Journald (RAM-Only System Logs)
echo "▸ [8/12] Configuring volatile journald..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/volatile.conf <<EOF
[Journal]
Storage=volatile
RuntimeMaxUse=50M
EOF
systemctl restart systemd-journald

# 9. Apply Kernel Sysctl Parameters
echo "▸ [9/12] Applying kernel sysctl parameters..."
sysctl -p

DOMAIN="${DOMAIN:-yourdomain.com}"
echo "▸ Target Domain: $DOMAIN"

# 10. Application Directories
echo "▸ [10/12] Creating application directories..."
mkdir -p /var/www/moi01.vip
mkdir -p /etc/myapp

# 11. Install Nginx Config & Domain Setup
echo "▸ [11/12] Installing Nginx configuration for domain '$DOMAIN'..."
cp "$REPO_ROOT/app/config/nginx.conf" /etc/nginx/sites-available/moi01.vip
sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" /etc/nginx/sites-available/moi01.vip
ln -sf /etc/nginx/sites-available/moi01.vip /etc/nginx/sites-enabled/moi01.vip
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# 11b. Automated Let's Encrypt TLS/SSL Certificate Issuance
if command -v certbot &>/dev/null && [ -n "$DOMAIN" ]; then
    echo "▸ Attempting Automated Let's Encrypt TLS/SSL Certificate Issuance for $DOMAIN..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" 2>/dev/null || echo "ℹ Note: Certbot SSL setup skipped until DNS for $DOMAIN resolves to this server."
fi

# 12. Install systemd Service Unit & Start Application
echo "▸ [12/12] Installing systemd service & starting vault..."
cp "$REPO_ROOT/app/config/moi01.service" /etc/systemd/system/moi01.service
systemctl daemon-reload
systemctl enable moi01.service

WEBHOOK_URL="${WEBHOOK_URL:-}"
API_KEY="${API_KEY:-}"

mkdir -p /etc/myapp
cat > /etc/myapp/config.env <<EOF
PORT=3000
WEBHOOK_URL=$WEBHOOK_URL
API_KEY=$API_KEY
EOF
chown root:root /etc/myapp/config.env
chmod 600 /etc/myapp/config.env

if [ -d "$REPO_ROOT/app" ]; then
    echo "▸ Installing Node.js production dependencies..."
    cd "$REPO_ROOT/app"
    npm install --production --no-audit --no-fund 2>/dev/null || npm install --production
    systemctl restart moi01.service || true
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Server bootstrap, OS hardening & Vault launch complete!"
echo "═══════════════════════════════════════════════════════════════"
