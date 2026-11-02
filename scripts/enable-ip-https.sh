#!/usr/bin/env bash
# Run on the SINGLE server after collecting Task 4 evidence.
# Keep public TCP 80 open for HTTP-01 renewals and TCP 443 for HTTPS.
set -euo pipefail
if [[ $# -ne 2 ]]; then echo "Usage: sudo bash $0 STATIC_IPV4 YOUR_EMAIL"; exit 2; fi
[[ $EUID -eq 0 ]] || { echo 'Run using sudo.'; exit 2; }
LAB_IP=$1
LAB_EMAIL=$2
python3 - "$LAB_IP" <<'PY'
import ipaddress, sys
address = ipaddress.IPv4Address(sys.argv[1])
assert address.is_global, 'Use the public static IPv4 address'
PY
apt-get update
apt-get install -y snapd
systemctl enable --now snapd.socket
if snap list core >/dev/null 2>&1; then snap refresh core; else snap install core; fi
if snap list certbot >/dev/null 2>&1; then snap refresh certbot; else snap install --classic certbot; fi
/snap/bin/certbot --version
python3 - <<'PY'
import re, subprocess
text = subprocess.check_output(['/snap/bin/certbot', '--version'], text=True)
version = tuple(map(int, re.search(r'(\d+)\.(\d+)', text).groups()))
assert version >= (5, 4), 'Certbot 5.4 or newer is required for IP webroot support'
PY
install -d -m 755 /var/www/acme
# Validate first against staging in separate directories so staging artifacts
# cannot become the certificate used by the public Nginx HTTPS listener.
/snap/bin/certbot certonly --staging --non-interactive --agree-tos \
  --email "$LAB_EMAIL" --preferred-profile shortlived \
  --webroot --webroot-path /var/www/acme --ip-address "$LAB_IP" \
  --cert-name lab6-staging --config-dir /etc/letsencrypt-staging \
  --work-dir /var/lib/letsencrypt-staging --logs-dir /var/log/letsencrypt-staging
/snap/bin/certbot certonly --non-interactive --agree-tos \
  --email "$LAB_EMAIL" --preferred-profile shortlived \
  --webroot --webroot-path /var/www/acme --ip-address "$LAB_IP" \
  --cert-name lab6-ip
cat > /etc/nginx/sites-available/lab6 <<NGINX
server {
    listen 80 default_server;
    server_name _;
    location ^~ /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://$LAB_IP\$request_uri; }
}
server {
    listen 443 ssl default_server;
    server_name $LAB_IP;
    ssl_certificate /etc/letsencrypt/live/lab6-ip/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/lab6-ip/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
}
NGINX
nginx -t
systemctl reload nginx
install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/20-reload-nginx <<'HOOK'
#!/bin/sh
set -eu
/usr/sbin/nginx -t
/usr/bin/systemctl reload nginx
HOOK
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/20-reload-nginx
# Explicit timer: checks twice a day; Certbot renews only when a renewal is due.
cat > /etc/systemd/system/lab6-certbot-renew.service <<'UNIT'
[Unit]
Description=Renew Lab 6 IP certificate
[Service]
Type=oneshot
ExecStart=/snap/bin/certbot renew --quiet
UNIT
cat > /etc/systemd/system/lab6-certbot-renew.timer <<'UNIT'
[Unit]
Description=Check certificate renewal twice daily
[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=1800
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
# Prefer this explicitly documented timer to a duplicate snap renewal timer.
if systemctl list-unit-files snap.certbot.renew.timer --no-legend | grep -q snap.certbot; then
  systemctl disable --now snap.certbot.renew.timer
fi
systemctl enable --now lab6-certbot-renew.timer
cd /opt/website
sed -i 's/^COOKIE_SECURE=.*/COOKIE_SECURE=true/' .env
docker compose up -d web
/snap/bin/certbot renew --cert-name lab6-ip --dry-run --run-deploy-hooks
systemctl list-timers lab6-certbot-renew.timer --all --no-pager
openssl x509 -in /etc/letsencrypt/live/lab6-ip/fullchain.pem -noout -issuer -dates -ext subjectAltName
echo "Open https://$LAB_IP and sign in again."
