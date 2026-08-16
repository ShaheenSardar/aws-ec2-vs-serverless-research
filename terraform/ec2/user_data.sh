#!/bin/bash
set -euxo pipefail

apt-get update -y
apt-get install -y python3-venv nginx

mkdir -p /opt/research-app

echo "${app_py_b64}" | base64 -d > /opt/research-app/app.py
echo "${compute_py_b64}" | base64 -d > /opt/research-app/compute_logic.py

python3 -m venv /opt/research-app/venv

/opt/research-app/venv/bin/pip install --upgrade pip
/opt/research-app/venv/bin/pip install "Flask>=3,<4" "gunicorn>=23,<24"

cat > /etc/systemd/system/research-app.service <<'EOF'
[Unit]
Description=EC2 vs Serverless Research Application
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/research-app
ExecStart=/opt/research-app/venv/bin/gunicorn \
    --workers 3 \
    --bind 127.0.0.1:8000 \
    app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

chown -R www-data:www-data /opt/research-app

systemctl daemon-reload
systemctl enable research-app
systemctl start research-app

cat > /etc/nginx/sites-available/research-app <<'EOF'
server {
    listen 80 default_server;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

ln -sf /etc/nginx/sites-available/research-app \
       /etc/nginx/sites-enabled/research-app

rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx