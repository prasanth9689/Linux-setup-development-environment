#!/bin/bash

# --- COLORS ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Start Timer
START_TIME=$(date +%s)

# --- CONFIGURATION ---
ROOT_PASSWORD="prasanth"
USERNAME="prasanth"
USER_PASSWORD="prasanth"
DB_ROOT_PASSWORD="prasanth"
VS_CODE_PASS="prasanth"
FILE_BROWSER_PASS="Prasanth968@@"
PHP_VER="8.5"
PRIMARY_DOMAIN="skyblue.co.in"
SUBDOMAINS=("mail" "contacts" "admin" "grocery" "phpmyadmin" "vs" "files" "jenkins")
NEW_HOSTNAME="skyblue"
EMAIL="admin@$PRIMARY_DOMAIN"
MAIL_RELAY_IP="144.91.84.196"
# ---------------------

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Helper Functions
print_status() { echo -e "${YELLOW}[INSTALLING] $1...${NC}"; }
print_skip() { echo -e "${GREEN}[✓ INSTALLED] $1${NC}"; }
print_ok() { echo -e "${GREEN}[✓ OK] $1${NC}"; }
print_error() { echo -e "${RED}[✗ ERROR] $1${NC}"; }

# 1. Set Hostname
hostnamectl set-hostname "$NEW_HOSTNAME"
echo -e "${GREEN}[✓] Hostname set to $NEW_HOSTNAME${NC}"

# 2. Update System
echo -e "${YELLOW}[WORKING] Updating package lists...${NC}"
apt update -qq
echo -e "${GREEN}[✓] Package lists updated${NC}"

# 3. Install Core Packages
echo -e "\n${YELLOW}=== INSTALLING CORE PACKAGES ===${NC}"
PACKAGES=(nginx mariadb-server software-properties-common certbot python3-certbot-nginx \
opendkim opendkim-tools wget unzip apache2-utils curl build-essential net-tools \
mailutils postfix fontconfig gnupg2 fail2ban)

for pkg in "${PACKAGES[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        print_skip "$pkg"
    else
        print_status "$pkg"
        apt install -y "$pkg" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ $pkg installed successfully${NC}"
        else
            print_error "$pkg installation failed"
        fi
    fi
done

# Disable Postfix
systemctl stop postfix &>/dev/null
systemctl disable postfix &>/dev/null
echo -e "${GREEN}[✓] Postfix disabled${NC}"

# 4. JENKINS INSTALLATION
echo -e "\n${YELLOW}=== JENKINS SETUP ===${NC}"
if [ -f "/usr/share/java/jenkins.war" ] || command -v jenkins &>/dev/null; then
    print_skip "Jenkins"
else
    print_status "Jenkins"
    mkdir -p /etc/apt/keyrings
    rm -f /etc/apt/keyrings/jenkins-keyring.asc /etc/apt/sources.list.d/jenkins.list
    wget -q -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
    echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | \
    tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    apt update -qq && apt install -y openjdk-21-jre jenkins > /dev/null 2>&1
    
    mkdir -p /etc/systemd/system/jenkins.service.d
    cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JAVA_OPTS=-Xmx512m -Xms256m"
EOF
    systemctl daemon-reload && systemctl enable --now jenkins
    print_ok "Jenkins installed and running"
fi

# 5. PHP 8.5 Installation
echo -e "\n${YELLOW}=== PHP SETUP ===${NC}"
if dpkg -l "php$PHP_VER-fpm" 2>/dev/null | grep -q "^ii"; then
    print_skip "PHP $PHP_VER"
else
    print_status "PHP $PHP_VER"
    add-apt-repository ppa:ondrej/php -y > /dev/null 2>&1
    apt update -qq
    apt install -y php$PHP_VER-fpm php$PHP_VER-mysql php$PHP_VER-curl \
    php$PHP_VER-zip php$PHP_VER-mbstring php$PHP_VER-xml > /dev/null 2>&1
    print_ok "PHP $PHP_VER installed"
fi

# 6. User Setup
echo -e "\n${YELLOW}=== USER SETUP ===${NC}"
if id "$USERNAME" &>/dev/null; then
    print_skip "User $USERNAME"
else
    print_status "Creating user $USERNAME"
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
    print_ok "User $USERNAME created"
fi

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd
echo -e "${GREEN}[✓] Root password configured${NC}"

# 7. phpMyAdmin Installation
echo -e "\n${YELLOW}=== PHPMYADMIN SETUP ===${NC}"
if [ -d "/var/www/phpmyadmin.$PRIMARY_DOMAIN" ] && [ -f "/var/www/phpmyadmin.$PRIMARY_DOMAIN/index.php" ]; then
    print_skip "phpMyAdmin"
else
    print_status "phpMyAdmin"
    mkdir -p /var/www/phpmyadmin.$PRIMARY_DOMAIN
    cd /tmp
    wget -q https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip
    unzip -oq phpMyAdmin-5.2.1-all-languages.zip
    cp -pr phpMyAdmin-5.2.1-all-languages/* /var/www/phpmyadmin.$PRIMARY_DOMAIN/
    rm -rf phpMyAdmin-5.2.1-all-languages*
    print_ok "phpMyAdmin installed"
fi

# 8. VS CODE Server Setup
echo -e "\n${YELLOW}=== VS CODE SERVER SETUP ===${NC}"
if command -v code-server &>/dev/null; then
    print_skip "VS Code Server"
else
    print_status "VS Code Server"
    curl -fsSL https://code-server.dev/install.sh | sh > /dev/null 2>&1
    systemctl enable --now code-server@$USERNAME
    print_ok "VS Code Server installed"
fi

mkdir -p /home/$USERNAME/.config/code-server
cat > /home/$USERNAME/.config/code-server/config.yaml <<EOF
bind-addr: 127.0.0.1:8082
auth: password
password: $VS_CODE_PASS
cert: false
EOF
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
echo -e "${GREEN}[✓] VS Code Server configured${NC}"

# 9. FILE BROWSER Setup
echo -e "\n${YELLOW}=== FILE BROWSER SETUP ===${NC}"
if [ -f "/usr/local/bin/filebrowser" ]; then
    print_skip "File Browser binary"
else
    print_status "File Browser"
    curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash > /dev/null 2>&1
    print_ok "File Browser installed"
fi

mkdir -p /etc/filebrowser
if [ ! -f "/etc/filebrowser/filebrowser.db" ]; then
    filebrowser config init --database=/etc/filebrowser/filebrowser.db
    filebrowser config set --database=/etc/filebrowser/filebrowser.db --root=/var/www --port=8081 --address=127.0.0.1
    filebrowser users add admin "$FILE_BROWSER_PASS" --perm.admin=true --database=/etc/filebrowser/filebrowser.db > /dev/null 2>&1
    echo -e "${GREEN}[✓] File Browser database configured${NC}"
else
    print_skip "File Browser database"
fi

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
echo -e "${GREEN}[✓] File Browser service enabled${NC}"

# 10. Nginx Configuration
echo -e "\n${YELLOW}=== NGINX CONFIGURATION ===${NC}"
print_status "Configuring Nginx VHosts"
rm -f /etc/nginx/sites-enabled/*

# Standard PHP Sites
for DOM_NAME in "mail" "contacts" "admin" "grocery" "phpmyadmin" "primary"; do
    FILE_NAME=$([[ "$DOM_NAME" == "primary" ]] && echo "primary" || echo "$DOM_NAME")
    S_NAME=$([[ "$DOM_NAME" == "primary" ]] && echo "$PRIMARY_DOMAIN www.$PRIMARY_DOMAIN" || echo "$DOM_NAME.$PRIMARY_DOMAIN")
    R_PATH=$([[ "$DOM_NAME" == "primary" ]] && echo "/var/www/$PRIMARY_DOMAIN" || echo "/var/www/$DOM_NAME.$PRIMARY_DOMAIN")
    mkdir -p "$R_PATH"
    
    cat > "/etc/nginx/sites-available/$FILE_NAME" <<EOF
server {
    listen 80;
    server_name $S_NAME;
    root $R_PATH;
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

# Reverse Proxies (HTTP first for SSL generation)
declare -A PROXIES=( ["files"]="8081" ["vs"]="8082" ["jenkins"]="8080" )
for key in "${!PROXIES[@]}"; do
    cat > "/etc/nginx/sites-available/$key" <<EOF
server {
    listen 80;
    server_name $key.$PRIMARY_DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:${PROXIES[$key]};
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    ln -sf "/etc/nginx/sites-available/$key" "/etc/nginx/sites-enabled/"
done

if nginx -t &>/dev/null; then
    systemctl restart nginx
    print_ok "Nginx configured and restarted"
else
    print_error "Nginx configuration test failed"
    nginx -t
fi

# 11. SSL Generation
echo -e "\n${YELLOW}=== SSL CERTIFICATE SETUP ===${NC}"
if [ -d "/etc/letsencrypt/live/$PRIMARY_DOMAIN" ]; then
    print_skip "SSL Certificates"
else
    print_status "Generating SSL Certificates"
    
    DOMAIN_ARGS="-d $PRIMARY_DOMAIN -d www.$PRIMARY_DOMAIN"
    for sub in "${SUBDOMAINS[@]}"; do
        DOMAIN_ARGS="$DOMAIN_ARGS -d $sub.$PRIMARY_DOMAIN"
    done
    
    if certbot --nginx --expand $DOMAIN_ARGS \
      --non-interactive --agree-tos -m $EMAIL --redirect; then
        print_ok "SSL Certificates generated"
    else
        print_error "SSL generation failed - Check DNS records"
    fi
fi

# 12. FAIL2BAN Configuration
echo -e "\n${YELLOW}=== FAIL2BAN SETUP ===${NC}"
print_status "Configuring Fail2Ban filters"

cat > /etc/fail2ban/filter.d/dovecot-empty-user.conf <<EOF
[Definition]
failregex = ^.* dovecot: (?:imap-login|pop3-login): Disconnected:.*Aborted login.*user=<>,.*rip=<HOST>
ignoreregex =
EOF

cat > /etc/fail2ban/filter.d/postfix-sasl-custom.conf <<EOF
[Definition]
failregex = postfix/smtpd.*: warning: unknown\[<HOST>\]: SASL (?:LOGIN|PLAIN|XOAUTH2) authentication failed: .*
ignoreregex =
EOF

cat > /etc/fail2ban/filter.d/postfix-auth.conf <<EOF
[Definition]
failregex = postfix/smtpd.*: warning: unknown\[<HOST>\]: SASL (?:LOGIN|PLAIN|XOAUTH2) authentication failed: .*
ignoreregex =
EOF

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
print_ok "Fail2Ban configured and running"

# 13. FIREWALL (UFW)
echo -e "\n${YELLOW}=== FIREWALL SETUP ===${NC}"
if ufw status | grep -q "Status: active"; then
    print_skip "UFW Firewall"
else
    print_status "Configuring UFW Firewall"
    ufw --force reset > /dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22,80,443,587,465,143,993,110,995/tcp
    ufw deny 25/tcp
    ufw deny 4200/tcp
    ufw allow out to $MAIL_RELAY_IP port 25 proto tcp
    ufw allow out 25/tcp
    ufw --force enable
    print_ok "Firewall configured"
fi

# 14. NODE.JS & PM2
echo -e "\n${YELLOW}=== NODE.JS & PM2 SETUP ===${NC}"
if command -v node &>/dev/null; then
    print_skip "Node.js $(node -v)"
else
    print_status "Node.js & PM2"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt install -y nodejs > /dev/null 2>&1
    npm install pm2 -g > /dev/null 2>&1
    print_ok "Node.js $(node -v) and PM2 installed"
fi

# 15. PERMISSIONS
echo -e "\n${YELLOW}=== SETTING PERMISSIONS ===${NC}"
usermod -aG www-data "$USERNAME"
chown -R "$USERNAME":www-data /var/www
find /var/www -type d -exec chmod 775 {} +
find /var/www -type f -exec chmod 664 {} +
print_ok "File permissions set"

# 16. FINAL RESTART
echo -e "\n${YELLOW}=== RESTARTING SERVICES ===${NC}"
nginx -t && systemctl restart nginx php$PHP_VER-fpm code-server@$USERNAME filebrowser
if systemctl is-active --quiet jenkins; then
    systemctl restart jenkins
fi
print_ok "All services restarted"

# 17. HEALTH CHECK
echo -e "\n${YELLOW}=== HEALTH CHECK ===${NC}"
for port in 80 443 8080 8081 8082; do
    if netstat -tuln | grep ":$port " > /dev/null; then
        print_ok "Port $port listening"
    else
        print_error "Port $port NOT listening"
    fi
done

# Calculate execution time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Final Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  SETUP COMPLETE IN ${DURATION}s${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Access your services:${NC}"
echo -e "  • Main Site:    ${GREEN}https://$PRIMARY_DOMAIN${NC}"
echo -e "  • phpMyAdmin:   ${GREEN}https://phpmyadmin.$PRIMARY_DOMAIN${NC}"
echo -e "  • Jenkins:      ${GREEN}https://jenkins.$PRIMARY_DOMAIN${NC}"
echo -e "  • VS Code:      ${GREEN}https://vs.$PRIMARY_DOMAIN${NC}"
echo -e "  • File Browser: ${GREEN}https://files.$PRIMARY_DOMAIN${NC}"
echo -e "\n${YELLOW}Initial Passwords:${NC}"
echo -e "  • Jenkins:      ${GREEN}cat /var/lib/jenkins/secrets/initialAdminPassword${NC}"
echo -e "  • File Browser: ${GREEN}admin / $FILE_BROWSER_PASS${NC}"
echo -e "${GREEN}========================================${NC}\n"