#!/bin/bash
# =============================================================================
#  Laravel Ubuntu Setup Script
#  Tested on: Ubuntu 22.04 / 24.04 LTS
#  Usage: sudo bash laravel-setup.sh
# =============================================================================

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[✔]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $1"; }
error()   { echo -e "${RED}[✘]${RESET} $1"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $1${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}\n"; }

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script as root: sudo bash $0"

# Keep apt/dpkg non-interactive while preserving this script's own prompts.
export DEBIAN_FRONTEND=noninteractive

# =============================================================================
#  INTERACTIVE CONFIGURATION
# =============================================================================
header "Laravel Server Setup — Configuration"

# PHP version
echo -e "${BOLD}PHP version:${RESET}"
select PHP_VERSION in "8.3" "8.2" "8.1"; do
    [[ -n "$PHP_VERSION" ]] && break
done
success "PHP $PHP_VERSION selected"

# Web server
echo -e "\n${BOLD}Web server:${RESET}"
select WEB_SERVER in "nginx" "apache2"; do
    [[ -n "$WEB_SERVER" ]] && break
done
success "$WEB_SERVER selected"

# Database
echo -e "\n${BOLD}Database:${RESET}"
select DB_ENGINE in "mysql" "postgresql" "none"; do
    [[ -n "$DB_ENGINE" ]] && break
done

if [[ "$DB_ENGINE" != "none" ]]; then
    read -rp "  DB name     : " DB_NAME
    read -rp "  DB user     : " DB_USER
    read -rsp "  DB password : " DB_PASS; echo
    success "$DB_ENGINE selected (db=$DB_NAME, user=$DB_USER)"
fi

# Redis
read -rp $'\n'"Install Redis? [Y/n]: " INSTALL_REDIS
INSTALL_REDIS=${INSTALL_REDIS:-Y}

# phpMyAdmin
if [[ "$DB_ENGINE" == "mysql" ]]; then
    read -rp "Install phpMyAdmin? [Y/n]: " INSTALL_PHPMYADMIN
    INSTALL_PHPMYADMIN=${INSTALL_PHPMYADMIN:-Y}
else
    read -rp "Install phpMyAdmin (best with MySQL)? [y/N]: " INSTALL_PHPMYADMIN
    INSTALL_PHPMYADMIN=${INSTALL_PHPMYADMIN:-N}
fi

# Node.js
echo -e "\n${BOLD}Node.js version (for Vite/npm):${RESET}"
select NODE_VERSION in "20" "18" "skip"; do
    [[ -n "$NODE_VERSION" ]] && break
done

# Laravel project
read -rp $'\n'"New Laravel project name (leave blank to skip): " LARAVEL_PROJECT
read -rp "Web root base directory [/var/www]: " WEB_ROOT
WEB_ROOT=${WEB_ROOT:-/var/www}

# Domain (for Nginx/Apache vhost)
read -rp "Primary domain (e.g. example.com or server IP): " DOMAIN

# www redirect
IS_REAL_DOMAIN=false
if [[ "$DOMAIN" =~ \. ]] && [[ ! "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IS_REAL_DOMAIN=true
    read -rp "Also link www.${DOMAIN} → ${DOMAIN}? [Y/n]: " LINK_WWW
    LINK_WWW=${LINK_WWW:-Y}
    read -rp "Any extra subdomains to link? (comma-separated, leave blank for none): " EXTRA_DOMAINS
fi

# SSL
if $IS_REAL_DOMAIN; then
    read -rp "Install SSL via Certbot? [Y/n]: " INSTALL_SSL
    INSTALL_SSL=${INSTALL_SSL:-Y}
    if [[ "${INSTALL_SSL^^}" == "Y" ]]; then
        read -rp "Email for Certbot: " CERTBOT_EMAIL
    fi
fi

echo ""
warn "Review your choices above. Starting in 5 seconds… (Ctrl+C to abort)"
sleep 5

# Detect this server's public IP early (used later in DNS check + summary)
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
         || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
         || hostname -I | awk '{print $1}')

# =============================================================================
#  RESUME SUPPORT
# =============================================================================
STATE_FILE="/var/tmp/laravel_setup_step.state"
START_STEP=1
CURRENT_STEP=0

if [[ -f "$STATE_FILE" ]]; then
    PREV_STEP=$(cat "$STATE_FILE" 2>/dev/null || true)
    if [[ "$PREV_STEP" =~ ^([1-9]|10|11)$ ]]; then
        read -rp "Detected an incomplete previous run at step ${PREV_STEP}. Resume from this step? [Y/n]: " RESUME_FROM_STATE
        RESUME_FROM_STATE=${RESUME_FROM_STATE:-Y}
        if [[ "${RESUME_FROM_STATE^^}" == "Y" ]]; then
            START_STEP="$PREV_STEP"
        fi
    fi
fi

read -rp "Start from step [1-11] (default: ${START_STEP}): " START_STEP_INPUT
if [[ -n "$START_STEP_INPUT" ]]; then
    if [[ "$START_STEP_INPUT" =~ ^([1-9]|10|11)$ ]]; then
        START_STEP="$START_STEP_INPUT"
    else
        warn "Invalid step '${START_STEP_INPUT}', using step ${START_STEP}"
    fi
fi

on_step_error() {
    local rc=$?
    trap - ERR
    if [[ "$CURRENT_STEP" -ge 1 && "$CURRENT_STEP" -le 11 ]]; then
        echo "$CURRENT_STEP" > "$STATE_FILE"
        echo ""
        warn "Step ${CURRENT_STEP} failed."
        warn "Fix the issue, rerun the script, and resume from step ${CURRENT_STEP}."
    fi
    exit "$rc"
}

trap 'on_step_error' ERR

# =============================================================================
#  STEP 1 — System update
# =============================================================================
if (( START_STEP <= 1 )); then
    CURRENT_STEP=1
    header "Step 1 — System Update"
    apt-get update -qq && apt-get upgrade -y -qq
    apt-get install -y -qq \
        curl wget git unzip zip software-properties-common \
        ca-certificates gnupg lsb-release apt-transport-https
    success "System updated"
fi

# =============================================================================
#  STEP 2 — PHP + extensions
# =============================================================================
if (( START_STEP <= 2 )); then
    CURRENT_STEP=2
    header "Step 2 — PHP $PHP_VERSION"
    add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
    apt-get update -qq

PHP_EXTENSIONS=(
    "php${PHP_VERSION}"
    "php${PHP_VERSION}-cli"
    "php${PHP_VERSION}-fpm"
    "php${PHP_VERSION}-common"
    "php${PHP_VERSION}-mysql"
    "php${PHP_VERSION}-pgsql"
    "php${PHP_VERSION}-sqlite3"
    "php${PHP_VERSION}-mbstring"
    "php${PHP_VERSION}-xml"
    "php${PHP_VERSION}-bcmath"
    "php${PHP_VERSION}-curl"
    "php${PHP_VERSION}-zip"
    "php${PHP_VERSION}-gd"
    "php${PHP_VERSION}-intl"
    "php${PHP_VERSION}-redis"
    "php${PHP_VERSION}-imagick"
)

    apt-get install -y -qq "${PHP_EXTENSIONS[@]}"
    success "PHP $PHP_VERSION + extensions installed"

# Tune php.ini for web
    PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
    sed -i 's/^upload_max_filesize.*/upload_max_filesize = 100M/' "$PHP_INI"
    sed -i 's/^post_max_size.*/post_max_size = 100M/'             "$PHP_INI"
    sed -i 's/^memory_limit.*/memory_limit = 256M/'               "$PHP_INI"
    sed -i 's/^max_execution_time.*/max_execution_time = 120/'    "$PHP_INI"
    success "php.ini tuned (upload=100M, memory=256M, timeout=120s)"

    systemctl enable "php${PHP_VERSION}-fpm" --quiet
    systemctl restart "php${PHP_VERSION}-fpm"
fi

# =============================================================================
#  STEP 3 — Composer
# =============================================================================
if (( START_STEP <= 3 )); then
    CURRENT_STEP=3
    header "Step 3 — Composer"
    EXPECTED_CHECKSUM="$(curl -s https://composer.github.io/installer.sig)"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
        rm composer-setup.php
        error "Composer installer checksum mismatch — aborting."
    fi

    php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    success "Composer $(composer --version --no-ansi | awk '{print $3}') installed"
fi

# =============================================================================
#  STEP 3.5 — phpMyAdmin (optional)
# =============================================================================
if (( START_STEP <= 4 )) && [[ "${INSTALL_PHPMYADMIN^^}" == "Y" ]]; then
    CURRENT_STEP=4
    header "Step 3.5 — phpMyAdmin"

    # Avoid interactive debconf prompts during automated setup.
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean false" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq phpmyadmin

    if [[ "$DB_ENGINE" != "mysql" ]]; then
        warn "phpMyAdmin installed without MySQL selection; configure DB access manually if needed"
    fi

    success "phpMyAdmin installed"
fi

# =============================================================================
#  STEP 4 — Web server
# =============================================================================
if (( START_STEP <= 4 )); then
    CURRENT_STEP=4
    header "Step 4 — $WEB_SERVER"
    apt-get install -y -qq "$WEB_SERVER"

    if [[ "$WEB_SERVER" == "nginx" ]]; then
        systemctl stop apache2 > /dev/null 2>&1 || true
        systemctl disable apache2 > /dev/null 2>&1 || true
    else
        systemctl stop nginx > /dev/null 2>&1 || true
        systemctl disable nginx > /dev/null 2>&1 || true
    fi

    systemctl enable "$WEB_SERVER" --quiet

PROJECT_PATH="${WEB_ROOT}/${LARAVEL_PROJECT:-laravel}"

# Build server_name list
ALL_DOMAINS="$DOMAIN"
WWW_DOMAIN="www.${DOMAIN}"
if [[ -n "$EXTRA_DOMAINS" ]]; then
    EXTRA_CLEAN=$(echo "$EXTRA_DOMAINS" | tr ',' ' ' | xargs)
    ALL_DOMAINS="$ALL_DOMAINS $EXTRA_CLEAN"
fi

NGINX_PHPMYADMIN_BLOCK=""
if [[ "${INSTALL_PHPMYADMIN^^}" == "Y" ]]; then
    NGINX_PHPMYADMIN_BLOCK="
    location = /phpmyadmin {
        return 301 /phpmyadmin/;
    }

    location ^~ /phpmyadmin/ {
        alias /usr/share/phpmyadmin/;
        index index.php index.html;
        try_files \$uri \$uri/ =404;
    }

    location ~ ^/phpmyadmin/(.+\\.php)\$ {
        alias /usr/share/phpmyadmin/\$1;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$request_filename;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_hide_header X-Powered-By;
    }
"
fi

APACHE_PHPMYADMIN_BLOCK=""
if [[ "${INSTALL_PHPMYADMIN^^}" == "Y" ]]; then
    APACHE_PHPMYADMIN_BLOCK="
    Alias /phpmyadmin /usr/share/phpmyadmin
    <Directory /usr/share/phpmyadmin>
        Options SymLinksIfOwnerMatch
        DirectoryIndex index.php
        AllowOverride All
        Require all granted
    </Directory>
"
fi

if [[ "$WEB_SERVER" == "nginx" ]]; then

    # www → non-www redirect block (only if real domain)
    WWW_REDIRECT_BLOCK=""
    if [[ "${LINK_WWW^^}" == "Y" ]] && $IS_REAL_DOMAIN; then
        WWW_REDIRECT_BLOCK="
# Redirect www → non-www
server {
    listen 80;
    server_name ${WWW_DOMAIN};
    return 301 \$scheme://${DOMAIN}\$request_uri;
}
"
    fi

    cat > /etc/nginx/sites-available/laravel <<NGINX
${WWW_REDIRECT_BLOCK}
server {
    listen 80;
    server_name ${ALL_DOMAINS};
    root ${PROJECT_PATH}/public;
    index index.php;
    charset utf-8;

    # Logs
    access_log /var/log/nginx/${DOMAIN}-access.log;
    error_log  /var/log/nginx/${DOMAIN}-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

${NGINX_PHPMYADMIN_BLOCK}

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
}
NGINX

    ln -sf /etc/nginx/sites-available/laravel /etc/nginx/sites-enabled/laravel
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl restart nginx
    success "Nginx configured → /etc/nginx/sites-available/laravel"
    success "Domains: ${ALL_DOMAINS}"

else
    # Apache
    a2enmod rewrite proxy_fcgi setenvif > /dev/null
    a2enconf "php${PHP_VERSION}-fpm" > /dev/null 2>&1 || true

    # Build ServerAlias line
    ALIAS_LINE=""
    if [[ "${LINK_WWW^^}" == "Y" ]] && $IS_REAL_DOMAIN; then
        ALIAS_LINE="    ServerAlias ${WWW_DOMAIN}"
    fi
    if [[ -n "$EXTRA_DOMAINS" ]]; then
        ALIAS_LINE="${ALIAS_LINE}
    ServerAlias ${EXTRA_CLEAN}"
    fi

    cat > /etc/apache2/sites-available/laravel.conf <<APACHE
# Redirect www → non-www
<VirtualHost *:80>
    ServerName ${WWW_DOMAIN}
    Redirect permanent / http://${DOMAIN}/
</VirtualHost>

<VirtualHost *:80>
    ServerName ${DOMAIN}
${ALIAS_LINE}
    DocumentRoot ${PROJECT_PATH}/public

    <Directory ${PROJECT_PATH}/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

${APACHE_PHPMYADMIN_BLOCK}

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined
</VirtualHost>
APACHE

    a2ensite laravel.conf > /dev/null
    a2dissite 000-default.conf > /dev/null 2>&1 || true
    apache2ctl configtest && systemctl restart apache2
    success "Apache configured → /etc/apache2/sites-available/laravel.conf"
    success "Domains: ${ALL_DOMAINS}"
fi
fi

# =============================================================================
#  STEP 5 — Database
# =============================================================================
if (( START_STEP <= 5 )); then
header "Step 5 — Database ($DB_ENGINE)"
CURRENT_STEP=5
if [[ "$DB_ENGINE" == "mysql" ]]; then
    apt-get install -y -qq mysql-server
    systemctl enable mysql --quiet
    systemctl start mysql

    mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    success "MySQL: database '${DB_NAME}' + user '${DB_USER}' created"

elif [[ "$DB_ENGINE" == "postgresql" ]]; then
    apt-get install -y -qq postgresql postgresql-contrib
    systemctl enable postgresql --quiet
    systemctl start postgresql

    sudo -u postgres psql <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
  END IF;
END \$\$;
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL
    success "PostgreSQL: database '${DB_NAME}' + user '${DB_USER}' created"

else
    warn "Database skipped"
fi
fi

# =============================================================================
#  STEP 6 — Redis
# =============================================================================
if (( START_STEP <= 6 )) && [[ "${INSTALL_REDIS^^}" == "Y" ]]; then
    CURRENT_STEP=6
    header "Step 6 — Redis"
    apt-get install -y -qq redis-server
    sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
    systemctl enable redis-server --quiet
    systemctl restart redis-server
    success "Redis installed and running"
fi

# =============================================================================
#  STEP 7 — Node.js
# =============================================================================
if (( START_STEP <= 7 )) && [[ "$NODE_VERSION" != "skip" ]]; then
    CURRENT_STEP=7
    header "Step 7 — Node.js $NODE_VERSION"
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs
    success "Node $(node -v) + npm $(npm -v) installed"
fi

# =============================================================================
#  STEP 8 — Supervisor (queue workers)
# =============================================================================
if (( START_STEP <= 8 )); then
    CURRENT_STEP=8
    header "Step 8 — Supervisor"
    apt-get install -y -qq supervisor
    systemctl enable supervisor --quiet
    systemctl start supervisor

if [[ -f "${PROJECT_PATH}/artisan" ]]; then
cat > /etc/supervisor/conf.d/laravel-worker.conf <<SUPERVISOR
[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${PROJECT_PATH}/artisan queue:work --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=2
redirect_stderr=true
stdout_logfile=${PROJECT_PATH}/storage/logs/worker.log
stopwaitsecs=3600
SUPERVISOR

    supervisorctl reread > /dev/null 2>&1
    supervisorctl update > /dev/null 2>&1
    success "Supervisor configured (2 queue workers)"
else
    rm -f /etc/supervisor/conf.d/laravel-worker.conf
    supervisorctl reread > /dev/null 2>&1 || true
    supervisorctl update > /dev/null 2>&1 || true
    warn "Supervisor installed, but queue worker was skipped (artisan not found at ${PROJECT_PATH})"
    warn "After project is ready, rerun from step 8 or add worker config manually"
fi
fi

# =============================================================================
#  STEP 9 — New Laravel Project (optional)
# =============================================================================
if (( START_STEP <= 9 )) && [[ -n "$LARAVEL_PROJECT" ]]; then
    CURRENT_STEP=9
    header "Step 9 — Laravel Project: $LARAVEL_PROJECT"
    mkdir -p "$WEB_ROOT"
    cd "$WEB_ROOT"

    composer create-project laravel/laravel "$LARAVEL_PROJECT" --prefer-dist --quiet
    cd "$LARAVEL_PROJECT"

    # Permissions
    chown -R www-data:www-data "$PROJECT_PATH"
    chmod -R 755 "$PROJECT_PATH"
    chmod -R 775 "$PROJECT_PATH/storage" "$PROJECT_PATH/bootstrap/cache"

    # .env setup
    cp .env.example .env
    php artisan key:generate --quiet

    # Patch .env with DB credentials
    if [[ "$DB_ENGINE" == "mysql" ]]; then
        DB_CONNECTION_VALUE="mysql"
    elif [[ "$DB_ENGINE" == "postgresql" ]]; then
        DB_CONNECTION_VALUE="pgsql"
        sed -i 's/^DB_PORT=3306/DB_PORT=5432/' .env
    fi

    if [[ "$DB_ENGINE" != "none" ]]; then
        sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=${DB_CONNECTION_VALUE}/" .env
        sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/"                .env
        sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/"                .env
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/"                .env
    fi

    # Redis cache/queue
    if [[ "${INSTALL_REDIS^^}" == "Y" ]]; then
        sed -i 's/^CACHE_DRIVER=.*/CACHE_DRIVER=redis/'   .env
        sed -i 's/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=redis/' .env
        sed -i 's/^SESSION_DRIVER=.*/SESSION_DRIVER=redis/' .env
    fi

    # Node deps
    if [[ "$NODE_VERSION" != "skip" ]]; then
        npm install --silent
    fi

    supervisorctl restart laravel-worker:* > /dev/null 2>&1 || true
    success "Laravel project created at ${PROJECT_PATH}"
fi

# =============================================================================
#  STEP 10 — SSL via Certbot
# =============================================================================
if (( START_STEP <= 10 )) && [[ "${INSTALL_SSL^^}" == "Y" ]] && [[ -n "$CERTBOT_EMAIL" ]]; then
    CURRENT_STEP=10
    header "Step 10 — SSL (Let's Encrypt)"
    apt-get install -y -qq certbot

    # Build -d flags for all domains
    CERTBOT_DOMAINS="-d ${DOMAIN}"
    if [[ "${LINK_WWW^^}" == "Y" ]] && $IS_REAL_DOMAIN; then
        CERTBOT_DOMAINS="${CERTBOT_DOMAINS} -d ${WWW_DOMAIN}"
    fi
    if [[ -n "$EXTRA_DOMAINS" ]]; then
        for EXTRA in $(echo "$EXTRA_DOMAINS" | tr ',' ' '); do
            CERTBOT_DOMAINS="${CERTBOT_DOMAINS} -d ${EXTRA// /}"
        done
    fi

    info "Requesting certificate for: ${CERTBOT_DOMAINS//-d /}"

    # Check DNS resolves to this server before attempting cert
    SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
    DNS_IP=$(dig +short "$DOMAIN" 2>/dev/null | tail -n1)

    if [[ "$DNS_IP" != "$SERVER_IP" ]]; then
        warn "DNS check: ${DOMAIN} resolves to ${DNS_IP:-'(not found)'} but this server is ${SERVER_IP}"
        warn "Certbot may fail if DNS hasn't propagated yet. Attempting anyway…"
    else
        success "DNS check passed: ${DOMAIN} → ${SERVER_IP}"
    fi

    if [[ "$WEB_SERVER" == "nginx" ]]; then
        apt-get install -y -qq python3-certbot-nginx
        certbot --nginx $CERTBOT_DOMAINS --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --redirect
    else
        apt-get install -y -qq python3-certbot-apache
        certbot --apache $CERTBOT_DOMAINS --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --redirect
    fi

    success "SSL certificate installed (auto-renew via cron/systemd timer)"
fi

# =============================================================================
#  STEP 11 — Firewall (UFW)
# =============================================================================
if (( START_STEP <= 11 )); then
    CURRENT_STEP=11
    header "Step 11 — Firewall (UFW)"
    apt-get install -y -qq ufw > /dev/null
    ufw --force reset > /dev/null
    ufw default deny incoming > /dev/null
    ufw default allow outgoing > /dev/null
    ufw allow ssh > /dev/null
    ufw allow 'Nginx Full' > /dev/null 2>&1 || ufw allow 'Apache Full' > /dev/null 2>&1 || true
    ufw --force enable > /dev/null
    success "UFW firewall enabled (SSH + HTTP/HTTPS allowed)"
fi

# =============================================================================
#  DONE — Summary
# =============================================================================
header "Setup Complete 🎉"
echo -e "${BOLD}Installed:${RESET}"
echo -e "  ${GREEN}✔${RESET} PHP          $PHP_VERSION"
echo -e "  ${GREEN}✔${RESET} Composer     $(composer --version --no-ansi 2>/dev/null | awk '{print $3}')"
echo -e "  ${GREEN}✔${RESET} Web server   $WEB_SERVER"
[[ "$DB_ENGINE" != "none" ]] && echo -e "  ${GREEN}✔${RESET} Database     $DB_ENGINE ($DB_NAME)"
[[ "${INSTALL_REDIS^^}" == "Y" ]] && echo -e "  ${GREEN}✔${RESET} Redis"
[[ "${INSTALL_PHPMYADMIN^^}" == "Y" ]] && echo -e "  ${GREEN}✔${RESET} phpMyAdmin   /phpmyadmin"
[[ "$NODE_VERSION" != "skip" ]] && echo -e "  ${GREEN}✔${RESET} Node.js      $(node -v 2>/dev/null)"
echo -e "  ${GREEN}✔${RESET} Supervisor   (queue workers)"
[[ "${INSTALL_SSL^^}" == "Y" ]] && echo -e "  ${GREEN}✔${RESET} SSL          Let's Encrypt (auto-renew)"
echo -e "  ${GREEN}✔${RESET} Firewall     UFW"

echo ""
[[ -n "$LARAVEL_PROJECT" ]] && echo -e "${BOLD}Project path:${RESET}  ${PROJECT_PATH}"
PROTO="http"; [[ "${INSTALL_SSL^^}" == "Y" ]] && PROTO="https"
echo -e "${BOLD}Visit:${RESET}         ${PROTO}://${DOMAIN}"
[[ "${INSTALL_PHPMYADMIN^^}" == "Y" ]] && echo -e "${BOLD}phpMyAdmin:${RESET}    ${PROTO}://${DOMAIN}/phpmyadmin"
echo ""

# ── DNS record instructions ──────────────────────────────────────────────────
if $IS_REAL_DOMAIN; then
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${YELLOW}  DNS Records to add in your domain registrar${RESET}"
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e ""
    echo -e "  ${BOLD}Type   Host              Value          TTL${RESET}"
    echo -e "  ──────────────────────────────────────────────"
    echo -e "  A      ${DOMAIN}.     ${SERVER_IP}   300"
    if [[ "${LINK_WWW^^}" == "Y" ]]; then
        echo -e "  A      www.${DOMAIN}.  ${SERVER_IP}   300"
        echo -e "  ${CYAN}(or)${RESET}"
        echo -e "  CNAME  www               ${DOMAIN}.          300"
    fi
    if [[ -n "$EXTRA_DOMAINS" ]]; then
        for EXTRA in $(echo "$EXTRA_DOMAINS" | tr ',' ' '); do
            EXTRA="${EXTRA// /}"
            echo -e "  A      ${EXTRA}.    ${SERVER_IP}   300"
        done
    fi
    echo ""

    # Live DNS propagation check
    echo -e "${BOLD}DNS propagation check:${RESET}"
    apt-get install -y -qq dnsutils > /dev/null 2>&1 || true
    for CHECK_DOMAIN in $DOMAIN ${LINK_WWW:+$WWW_DOMAIN}; do
        RESOLVED=$(dig +short "$CHECK_DOMAIN" 2>/dev/null | tail -n1)
        if [[ "$RESOLVED" == "$SERVER_IP" ]]; then
            echo -e "  ${GREEN}✔${RESET} ${CHECK_DOMAIN} → ${RESOLVED} (matches this server)"
        elif [[ -z "$RESOLVED" ]]; then
            echo -e "  ${YELLOW}?${RESET} ${CHECK_DOMAIN} → not resolving yet (DNS not propagated)"
        else
            echo -e "  ${RED}✘${RESET} ${CHECK_DOMAIN} → ${RESOLVED} (expected ${SERVER_IP})"
        fi
    done
    echo ""
    echo -e "  ${CYAN}Tip:${RESET} DNS can take up to 48h to propagate worldwide."
    echo -e "       Run ${BOLD}dig +short ${DOMAIN}${RESET} anytime to check."
    echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
fi

if [[ -n "$LARAVEL_PROJECT" ]]; then
    echo -e "${YELLOW}Next steps:${RESET}"
    echo -e "  cd ${PROJECT_PATH}"
    echo -e "  php artisan migrate"
    echo -e "  php artisan storage:link"
    echo -e "  php artisan optimize"
fi

rm -f "$STATE_FILE"
trap - ERR
echo ""