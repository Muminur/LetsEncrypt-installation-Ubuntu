#!/bin/bash
set -e

DOMAIN="alternativechoice.org"
EMAIL="mentorpid@gmail.com"
WEBROOT="/var/www/circuit-dashboard"
SSL_CONF="/etc/letsencrypt/options-ssl-apache.conf"
SSL_SITE_CONF="/etc/apache2/sites-available/${DOMAIN}-ssl.conf"

echo "📦 Updating and installing dependencies"
apt update
apt install -y certbot python3-certbot-apache

echo "🔧 Preparing webroot for ACME challenge"
mkdir -p "${WEBROOT}/.well-known/acme-challenge"
chmod -R 755 "${WEBROOT}/.well-known"

echo "🔐 Obtaining SSL certificate"
certbot certonly --webroot \
  --webroot-path "${WEBROOT}" \
  --non-interactive \
  --agree-tos \
  --no-eff-email \
  -m "${EMAIL}" \
  -d "${DOMAIN}"

echo "🔄 Downloading strong SSL configuration"
curl -L -o "${SSL_CONF}" \
  https://raw.githubusercontent.com/certbot/certbot/master/certbot-apache/certbot_apache/_internal/tls_configs/current-options-ssl-apache.conf

echo "🧩 Enabling Apache SSL and configuring HTTPS VirtualHost"
a2enmod ssl
tee "${SSL_SITE_CONF}" > /dev/null <<EOF
<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerName ${DOMAIN}
    DocumentRoot ${WEBROOT}

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${DOMAIN}/privkey.pem
    Include ${SSL_CONF}

    <Directory "${WEBROOT}">
      Options Indexes FollowSymLinks
      AllowOverride All
      Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
</IfModule>
EOF

echo "🌐 Enabling HTTPS site and setting HTTP → HTTPS redirect"
a2ensite "${DOMAIN}-ssl.conf"
sed -i "/<VirtualHost \*:80>/a \    Redirect permanent / https://${DOMAIN}/" \
    /etc/apache2/sites-available/circuit-dashboard.conf

echo "🔍 Checking Apache config"
apachectl configtest

echo "✅ Restarting Apache"
systemctl reload apache2

echo "🎯 SSL installed successfully! Visit https://${DOMAIN}"

# 🔁 Setup monthly auto-renewal using systemd timer
echo "⏰ Setting up monthly cert renewal systemd timer..."

tee /etc/systemd/system/certbot-renew.service > /dev/null <<EOF
[Unit]
Description=Renew Let's Encrypt certificate

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --deploy-hook "systemctl reload apache2"
EOF

tee /etc/systemd/system/certbot-renew.timer > /dev/null <<EOF
[Unit]
Description=Monthly renewal timer for Let's Encrypt

[Timer]
OnCalendar=monthly
RandomizedDelaySec=86400
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now certbot-renew.timer

echo "✅ Timer enabled. Next run:"
systemctl list-timers | grep certbot-renew

echo "🧪 Testing auto-renewal..."
certbot renew --dry-run

echo "🎉 All set! Your certificates will auto-renew monthly, with Apache reloaded afterwards."
