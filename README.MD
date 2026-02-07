Skyblue Server Build Script (2026 Edition)

This repository contains a comprehensive automation script to provision a high-performance, secure, and developer-friendly web server. It is specifically optimized for the skyblue.co.in ecosystem.
🚀 Overview

The script automates the installation and configuration of a full-stack environment including PHP 8.5, Node.js 20, Jenkins, and custom mail security filters.
🛠 Features
1. Web & Development Stack

    Web Server: Nginx with automated Subdomain VHost generation.

    PHP Engine: PHP 8.5-FPM (Fixed: No more automatic downloads of .php files).

    Runtime: Node.js 20 (LTS) with PM2 installed globally for process management.

    Database: MariaDB (MySQL) with phpMyAdmin pre-configured.

2. Specialized Tools

    VS Code (Code-Server): Access your IDE via https://vs.skyblue.co.in.

    Jenkins: Automation server for CI/CD via https://jenkins.skyblue.co.in.

    File Browser: Web-based file management via https://files.skyblue.co.in.

3. Hardened Security

    Firewall (UFW): Strict ruleset for Web, SSH, and Mail (Port 25 blocked, specific outgoing IP bypass).

    Fail2Ban: Custom jails for Dovecot, Postfix, and SSH to block brute-force attacks.

        Custom Filters: dovecot-empty-user, postfix-sasl-custom, and postfix-auth.

    SSL: Automated Let's Encrypt certificates for the primary domain and all 8 subdomains.

    Permissions: Fixed EACCES issues by syncing the prasanth user with the www-data group.

📋 Subdomain Map
Subdomain	Service	URL
primary	Main Website	https://skyblue.co.in
mail	Mail Web Interface	https://mail.skyblue.co.in
phpmyadmin	Database Admin	https://phpmyadmin.skyblue.co.in
vs	VS Code Web IDE	https://vs.skyblue.co.in
files	File Manager	https://files.skyblue.co.in
jenkins	CI/CD Server	https://jenkins.skyblue.co.in
⚙️ Post-Installation Instructions
Managing Node Processes

To run a Node.js app and keep it alive:
Bash

pm2 start app.js --name "my-app"
pm2 save
pm2 startup

Checking Security Status

To see currently banned IPs:
Bash

fail2ban-client status postfix-auth
fail2ban-client status dovecot-empty-user

To check firewall status:
Bash

ufw status numbered

📂 Directory Structure

    Web Root: /var/www/ (Owned by prasanth:www-data)

    Nginx Configs: /etc/nginx/sites-available/

    Fail2Ban Filters: /etc/fail2ban/filter.d/

    Certificates: /etc/letsencrypt/live/

⚠️ Requirements

    OS: Ubuntu 22.04 LTS or newer.

    User: Must be run as root.

    Domain: DNS A-Records must point to the server IP for all subdomains before running.