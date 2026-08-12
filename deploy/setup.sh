#!/usr/bin/env bash
# One-time VPS setup. Run as a sudo-capable user on the Hostinger box.
set -euo pipefail

DOMAIN="24.namastevis.in"
DEPLOY_USER="${SUDO_USER:-$USER}"

echo "==> Installing Caddy"
sudo apt-get update -qq
sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y caddy

echo "==> Creating app user and directories"
sudo useradd -r -s /usr/sbin/nologin app24 2>/dev/null || true
sudo mkdir -p /srv/24/{client,server,data}
sudo chown -R "$DEPLOY_USER":"$DEPLOY_USER" /srv/24/client
sudo chown -R app24:app24 /srv/24/server /srv/24/data

echo "==> Installing Caddyfile"
sudo cp "$(dirname "$0")/Caddyfile" /etc/caddy/Caddyfile
sudo systemctl enable --now caddy
sudo systemctl reload caddy

echo "==> Firewall"
sudo ufw allow 22/tcp  || true
sudo ufw allow 80/tcp  || true
sudo ufw allow 443/tcp || true
sudo ufw --force enable || true

cat <<EOF

Done.

Next:
  1. Point an A record for '24' at this box's IP.
  2. Push to main — the GitHub Action rsyncs client/ to /srv/24/client.
  3. Visit https://$DOMAIN

Phase 1 (server) additionally needs:
  sudo cp deploy/24.service /etc/systemd/system/
  sudo systemctl daemon-reload && sudo systemctl enable --now 24
EOF
