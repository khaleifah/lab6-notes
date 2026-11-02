#!/usr/bin/env bash
set -euo pipefail
cd /opt/website
if [[ ! -f .env ]]; then
  umask 077
  {
    printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'SECRET_KEY=%s\n' "$(openssl rand -hex 32)"
    printf 'COOKIE_SECURE=false\n'
  } > .env
fi
sudo systemctl enable --now docker nginx
sudo docker compose build web
sudo docker compose up -d db
for attempt in $(seq 1 60); do
  if sudo docker compose exec -T db pg_isready -U labnotes -d labnotes >/dev/null; then break; fi
  sleep 2
done
sudo docker compose run --rm web flask --app app:create_app init-db
sudo docker compose up -d web
sudo install -d -m 755 /var/www/acme
sudo tee /etc/nginx/sites-available/lab6 >/dev/null <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    location ^~ /.well-known/acme-challenge/ { root /var/www/acme; }
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $remote_addr;
    }
}
NGINX
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sfn /etc/nginx/sites-available/lab6 /etc/nginx/sites-enabled/lab6
sudo nginx -t
sudo systemctl reload nginx
for attempt in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1/health; then printf '\nWebsite is ready.\n'; exit 0; fi
  sleep 2
done
echo 'Health check failed. Inspect sudo docker compose logs.' >&2
exit 1
