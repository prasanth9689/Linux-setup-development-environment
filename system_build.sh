# 12
# Extra filter added

#!/bin/bash

# --- CONFIGURATION ---
ROOT_PASSWORD="YourStrongPassword"
USERNAME="YourUserName"
USER_PASSWORD="YourStrongPassword"
DB_ROOT_PASSWORD="YourStrongPassword"
VS_CODE_PASS="YourStrongPassword"
FILE_BROWSER_PASS="YourStrongPassword" # Must be 12+ chars
PHP_VER="8.5"
PRIMARY_DOMAIN="skyblue.co.in"
SUBDOMAINS=("mail" "contacts" "admin" "grocery" "phpmyadmin" "vs" "files" "jenkins")
NEW_HOSTNAME="skyblue"
EMAIL="admin@$PRIMARY_DOMAIN"
# ---------------------

if [ "$EUID" -ne 0 ]; then echo "Please run as root"; exit 1; fi

# 1. System Setup & Tools
hostnamectl set-hostname "$NEW_HOSTNAME"
apt update && apt install -y nginx mariadb-server software-properties-common certbot python3-certbot-nginx \
opendkim opendkim-tools wget unzip apache2-utils curl build-essential net-tools mailutils postfix \
fontconfig gnupg2 fail2ban

# 2. JENKINS INSTALLATION
echo "Installing Jenkins..."
mkdir -p /etc/apt/keyrings
rm -f /etc/apt/keyrings/jenkins-keyring.asc /etc/apt/sources.list.d/jenkins.list
wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt update && apt install -y openjdk-21-jre jenkins
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JAVA_OPTS=-Xmx512m -Xms256m"
EOF
systemctl daemon-reload && systemctl enable --now jenkins

# 3. PHP 8.5 & User Setup
add-apt-repository ppa:ondrej/php -y
apt update && apt install -y php$PHP_VER-fpm php$PHP_VER-mysql php$PHP_VER-curl php$PHP_VER-zip php$PHP_VER-mbstring php$PHP_VER-xml
systemctl stop postfix && systemctl disable postfix
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
fi

# 4. phpMyAdmin INSTALLATION
echo "Installing phpMyAdmin..."
mkdir -p /var/www/phpmyadmin.$PRIMARY_DOMAIN
cd /tmp
wget https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip
unzip -o phpMyAdmin-5.2.1-all-languages.zip
cp -pr phpMyAdmin-5.2.1-all-languages/* /var/www/phpmyadmin.$PRIMARY_DOMAIN/
rm -rf phpMyAdmin-5.2.1-all-languages*

# 5. VS CODE Setup
curl -fsSL https://code-server.dev/install.sh | sh
systemctl enable --now code-server@$USERNAME
mkdir -p /home/$USERNAME/.config/code-server
cat > /home/$USERNAME/.config/code-server/config.yaml <<EOF
bind-addr: 127.0.0.1:8082
auth: password
password: $VS_CODE_PASS
cert: false
EOF
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

# 6. FILE BROWSER Setup
curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
mkdir -p /etc/filebrowser
filebrowser config init --database=/etc/filebrowser/filebrowser.db
filebrowser config set --database=/etc/filebrowser/filebrowser.db --root=/var/www --port=8081 --address=127.0.0.1
filebrowser users add admin "$FILE_BROWSER_PASS" --perm.admin=true --database=/etc/filebrowser/filebrowser.db

cat > /etc/systemd/system/filebrowser.service <<EOF
[Unit]
Description=File Browser
After=network.target
[Service]
User=root
ExecStart=/usr/local/bin/filebrowser -d /etc/filebrowser/filebrowser.db
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now filebrowser

# 7. Nginx Basic VHosts & SSL (PHP Fix Included)
rm -rf /etc/nginx/sites-enabled/*
rm -rf /etc/nginx/sites-available/*
for DOM_NAME in "${SUBDOMAINS[@]}" "primary"; do
    FILE_NAME=$([[ "$DOM_NAME" == "primary" ]] && echo "primary" || echo "$DOM_NAME")
    SERVER_NAMES=$([[ "$DOM_NAME" == "primary" ]] && echo "$PRIMARY_DOMAIN www.$PRIMARY_DOMAIN" || echo "$DOM_NAME.$PRIMARY_DOMAIN")
    ROOT_PATH=$([[ "$DOM_NAME" == "primary" ]] && echo "/var/www/$PRIMARY_DOMAIN" || echo "/var/www/$DOM_NAME.$PRIMARY_DOMAIN")
    mkdir -p "$ROOT_PATH"
    cat > "/etc/nginx/sites-available/$FILE_NAME" <<EOF
server {
    listen 80;
    server_name $SERVER_NAMES;
    root $ROOT_PATH;
    index index.php index.html;
    location / { try_files \$uri \$uri/ =404; }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VER-fpm.sock;
    }
}
EOF
    ln -sf "/etc/nginx/sites-available/$FILE_NAME" "/etc/nginx/sites-enabled/"
done
systemctl restart nginx

# SSL Generation
certbot --nginx --expand -d $PRIMARY_DOMAIN -d www.$PRIMARY_DOMAIN \
$(printf -- "-d %s.$PRIMARY_DOMAIN " "${SUBDOMAINS[@]}") \
--non-interactive --agree-tos -m $EMAIL --redirect

# 8. REVERSE PROXY OVERRIDES
cat > /etc/nginx/sites-available/vs <<EOF
server {
    listen 443 ssl; server_name vs.$PRIMARY_DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

cat > /etc/nginx/sites-available/files <<EOF
server {
    listen 443 ssl; server_name files.$PRIMARY_DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

cat > /etc/nginx/sites-available/jenkins <<EOF
server {
    listen 443 ssl; server_name jenkins.$PRIMARY_DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
for tool in vs files jenkins; do ln -sf /etc/nginx/sites-available/$tool /etc/nginx/sites-enabled/; done

# 9. FAIL2BAN CONFIGURATION (Filters & Jail)
echo "Configuring Fail2Ban Filters..."

# 9a. dovecot-empty-user filter
cat > /etc/fail2ban/filter.d/dovecot-empty-user.conf <<EOF
[Definition]
failregex = ^.* dovecot: (?:imap-login|pop3-login): Disconnected:.*Aborted login.*user=<>,.*rip=<HOST>
ignoreregex =
EOF

# 9b. postfix-sasl-custom filter
cat > /etc/fail2ban/filter.d/postfix-sasl-custom.conf <<EOF
[Definition]
failregex = postfix/smtpd.*: warning: unknown\[<HOST>\]: SASL (?:LOGIN|PLAIN|XOAUTH2) authentication failed: .*
ignoreregex =
EOF

# 9c. postfix-auth filter
cat > /etc/fail2ban/filter.d/postfix-auth.conf <<EOF
[Definition]
failregex = postfix/smtpd.*: warning: unknown\[<HOST>\]: SASL (?:LOGIN|PLAIN|XOAUTH2) authentication failed: .*
ignoreregex =
EOF

# 9d. jail.local
cat > /etc/fail2ban/jail.local <<EOF
[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /var/log/apache2/error.log
maxretry = 3

[postfix-sasl]
enabled = true
filter = postfix-sasl-custom
port = smtp,submission,imap,imaps,pop3,pop3s
maxretry = 3
bantime = 12h
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 5w
action = %(action_)s
logpath = /var/log/mail.log

[postfix-auth]
enabled = true
port = smtp,submission,smtps
filter = postfix-auth
logpath = /var/log/mail.log
maxretry = 5
bantime = 3600

[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps
filter = dovecot
logpath = /var/log/mail.log
maxretry = 3
findtime = 600
bantime = 86400

[dovecot-empty-user]
enabled  = true
port     = imap,imaps,pop3,pop3s
filter   = dovecot-empty-user
logpath  = /var/log/mail.log
maxretry = 1
findtime = 600
bantime  = 86400
ignoreip = 127.0.0.1/8 ::1 217.77.3.238
action   = iptables-multiport[name=dovecot-empty-user, port="imap,imaps,pop3,pop3s", protocol=tcp]

[sshd]
enabled = true
maxretry = 3
bantime = 24h
findtime = 600
EOF

systemctl enable fail2ban && systemctl restart fail2ban

# 10. FIREWALL (UFW)
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22,80,443,587,465,143,993,110,995/tcp
ufw deny 25/tcp
ufw deny 4200/tcp
ufw allow out to 144.91.84.196 port 25 proto tcp
ufw allow out 25/tcp
ufw --force enable

# 11. PERMISSIONS & RESTART
usermod -aG www-data "$USERNAME"
chown -R "$USERNAME":www-data /var/www
find /var/www -type d -exec chmod 775 {} +
find /var/www -type f -exec chmod 664 {} +
nginx -t && systemctl restart nginx jenkins php$PHP_VER-fpm code-server@$USERNAME filebrowser

# 12. NODE.JS & PM2
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install pm2 -g

echo "--------------------------------------------------------"
echo "SETUP COMPLETE"
echo "Postfix Auth & SASL Filters: Active"
echo "Mail Domain Fixed: https://mail.$PRIMARY_DOMAIN"
echo "--------------------------------------------------------"