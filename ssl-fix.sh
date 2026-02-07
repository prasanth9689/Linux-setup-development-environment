#!/bin/bash

# --- COLORS ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' 

START_TIME=$(date +%s)

# --- CONFIGURATION ---
USERNAME="prasanth"
USER_PASSWORD="prasanth"
FILE_BROWSER_PASS="Prasanth968@@"
PHP_VER="8.5"
PRIMARY_DOMAIN="skyblue.co.in"
SUBDOMAINS=("mail" "contacts" "admin" "grocery" "phpmyadmin" "vs" "files" "jenkins")
EMAIL="admin@$PRIMARY_DOMAIN"
# ---------------------

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Please run as root${NC}"; exit 1; fi

print_status() { echo -e "${YELLOW}[WORKING] $1...${NC}"; }
print_skip() { echo -e "${GREEN}[SKIP] $1 already configured.${NC}"; }
print_ok() { echo -e "${GREEN}[OK] $1 is active.${NC}"; }

# 1. SMART FIREWALL CHECK (Skip if already enabled)
if ufw status | grep -q "Status: active"; then
    print_skip "UFW Firewall"
else
    print_status "Enabling Firewall"
    ufw allow 22,80,443,587,465,143,993,110,995/tcp
    echo "y" | ufw enable
fi

# 2. INSTALL CORE DEPENDENCIES
PACKAGES=(nginx mariadb-server certbot python3-certbot-nginx wget unzip curl net-tools fail2ban)
for pkg in "${PACKAGES[@]}"; do
    if dpkg -l "$pkg" &> /dev/null; then print_skip "$pkg"; else apt install -y "$pkg"; fi
done

# 3. NGINX CLEAN REBUILD (Port 80 Base)
print_status "Rebuilding Nginx Configs (HTTP Base)"
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

# Reverse Proxies (Files, VS, Jenkins)
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

# Restart Nginx to verify Port 80 works
nginx -t && systemctl restart nginx
print_ok "Nginx Port 80 is live"

# 4. SSL AUTOMATION (The Fix)
print_status "Attempting to secure all domains with SSL"

# Construct Domain String for Certbot
DOMAIN_ARGS="-d $PRIMARY_DOMAIN -d www.$PRIMARY_DOMAIN"
for sub in "${SUBDOMAINS[@]}"; do
    DOMAIN_ARGS="$DOMAIN_ARGS -d $sub.$PRIMARY_DOMAIN"
done

# Run Certbot - This will update the Nginx files automatically
certbot --nginx --expand $DOMAIN_ARGS --non-interactive --agree-tos -m $EMAIL --redirect --keep-until-expiring

# 5. POST-SSL VERIFICATION & REPAIR
if [ ! -d "/etc/letsencrypt/live/$PRIMARY_DOMAIN" ]; then
    echo -e "${RED}[ERROR] Certbot failed to generate certificates.${NC}"
    echo "Check if your DNS A-records are pointing to this IP for all subdomains."
else
    print_ok "SSL Certificates generated successfully"
    # Force a restart to load SSL configs
    systemctl restart nginx
fi

# 6. FINAL HEALTH CHECK
print_status "Final Port Check"
for port in 80 443; do
    if netstat -tuln | grep ":$port " > /dev/null; then
        print_ok "Port $port"
    else
        echo -e "${RED}[ERROR] Port $port is NOT LISTENING.${NC}"
    fi
done

END_TIME=$(date +%s)
echo -e "--------------------------------------------------------"
echo -e "${GREEN}REPAIR COMPLETE in $((END_TIME - START_TIME)) seconds!${NC}"
echo -e "If SSL is still failing, run 'nginx -t' to find the error.${NC}"
echo -e "--------------------------------------------------------"