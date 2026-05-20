# Laravel Ubuntu Setup Script

Interactive Bash installer to prepare an Ubuntu server for Laravel.

Tested target:
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

Script file:
- ubuntu_laravel.sh

## What This Script Installs

- PHP 8.1, 8.2, or 8.3 with common Laravel extensions
- Composer
- Web server: Nginx or Apache
- Database: MySQL, PostgreSQL, or skip
- Redis (optional)
- Node.js 18 or 20 (optional)
- Supervisor for queue workers
- Certbot SSL (optional)
- UFW firewall
- phpMyAdmin (optional), available at /phpmyadmin

## Recommended Project Location

For production-like server setup, use:
- /var/www/your-project

This follows Linux web server conventions and works cleanly with Nginx/Apache + PHP-FPM permissions.

## Before You Run

1. Copy your Laravel project to the server (if you already have one).
2. Place it under /var/www (recommended), for example:
	 - /var/www/laravel
	 - /var/www/myapp
3. Make script executable:

```bash
chmod +x ubuntu_laravel.sh
```

## Run

Run as root (or with sudo):

```bash
sudo bash ubuntu_laravel.sh
```

Or run directly via curl (without cloning the repository):

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/hussampw/setup_laravel_on_linux/main/ubuntu_laravel.sh)"
```

Tip: downloading first is safer because you can review the script before executing it as root.

The script is interactive and will ask for:
- PHP version
- Web server
- Database details
- Redis and Node.js options
- Domain and SSL options
- Whether to install phpMyAdmin
- Whether to create a new Laravel project

## Existing Project vs New Project

If you already uploaded a Laravel project:
- Leave New Laravel project name blank
- Set Web root base directory to your parent folder (default is /var/www)

Resulting path logic in the script:
- project path = WEB_ROOT + /laravel when project name is left blank

If you want a different folder name for an existing project (example /var/www/myapp), either:
- temporarily rename your folder to /var/www/laravel before running, or
- edit the script variable logic to point directly to your existing directory.

## phpMyAdmin Access

When you choose to install phpMyAdmin:
- URL: http://your-domain/phpmyadmin
- Or with SSL: https://your-domain/phpmyadmin

Notes:
- phpMyAdmin is most useful with MySQL/MariaDB.
- Restrict access in production (IP allowlist, auth layer, VPN, or disable when not needed).

## After Setup (Typical Laravel Commands)

Inside your project directory:

```bash
php artisan migrate
php artisan storage:link
php artisan optimize
```

If Node.js was installed:

```bash
npm install
npm run build
```

## Troubleshooting

- Check web server config:
	- Nginx: nginx -t
	- Apache: apache2ctl configtest
- Restart services:
	- systemctl restart nginx
	- systemctl restart apache2
	- systemctl restart php8.x-fpm
- Check Laravel permissions:
	- storage and bootstrap/cache should be writable by www-data

## Security Tips

- Use SSH keys and disable password login where possible.
- Keep packages updated regularly.
- Use SSL in production.
- If phpMyAdmin is enabled, protect or remove it when not required.
