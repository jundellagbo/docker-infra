# Docker Development Environment

A complete local development stack with Nginx, Apache, PHP, MySQL, PostgreSQL, Redis, Adminer, and MailHog.

## Features

- **Nginx** - Reverse proxy with wildcard SSL for `*.dev.local` (ports 80/443)
- **Apache** - Backend web server (ports 8080/8443)
- **PHP 7.4-8.4** - FPM with Composer, WP-CLI, and all WordPress extensions (version switchable)
- **MySQL 8.0** - Database server (port 3306)
- **PostgreSQL 16** - Database server (port 5432)
- **Redis 7** - Cache server (port 6379)
- **Adminer** - Database management UI (port 8081)
- **MailHog** - Email testing (SMTP 1025, Web 8025)
- **Config Watcher** - Auto-reload Nginx on config changes

## Quick Start

### 1. Uninstall Local Services (if needed)

If you have Apache, Nginx, MySQL, or PostgreSQL installed locally:

```bash
sudo ./scripts/uninstall-local-services.sh
```

### 2. Generate Wildcard SSL Certificates

```bash
./scripts/generate-ssl.sh
```

This generates a wildcard SSL certificate for `*.dev.local` that works for any subdomain.

**Important:** Install the CA certificate in Windows (see instructions printed by the script).

### 3. Start Services

```bash
docker compose up -d
```

### 4. Add Host Entries

Add your projects to the Windows hosts file (`C:\Windows\System32\drivers\etc\hosts`):

```
127.0.0.1 dev.local
127.0.0.1 mysite.dev.local
127.0.0.1 api.dev.local
```

### 5. Create a Project

Create a project folder and Nginx config manually:

```bash
# Create project directory
mkdir -p www/mysite/public
echo '<?php phpinfo();' > www/mysite/public/index.php

# Create Nginx config (copy from www/default as template)
cp nginx/default.conf nginx/mysite.conf
# Edit nginx/mysite.conf to set server_name and root path
```

Visit https://mysite.dev.local

## Database Credentials

| Database   | User | Password    | Port |
|------------|------|-------------|------|
| MySQL      | root | artisan7530 | 3306 |
| PostgreSQL | root | artisan7530 | 5432 |

### MySQL Connection

```bash
# From host
mysql -h 127.0.0.1 -u root -partisan7530

# From container
docker compose exec mysql mysql -u root -partisan7530
```

### PostgreSQL Connection

```bash
# From host
psql -h 127.0.0.1 -U root -d postgres

# From container
docker compose exec postgresql psql -U root -d postgres
```

### Adminer (Web UI)

- MySQL: http://localhost:8081 (Server: `mysql`, User: `root`, Password: `artisan7530`)
- PostgreSQL: http://localhost:8081?driver=pgsql (Server: `postgresql`, User: `root`, Password: `artisan7530`)

## Switching PHP Version

To switch PHP versions (7.4, 8.0, 8.1, 8.2, 8.3, 8.4):

1. Edit `.env` and change `PHP_VERSION`:
   ```bash
   PHP_VERSION=8.2
   ```

2. Rebuild and restart the PHP container:
   ```bash
   docker compose build php && docker compose up -d php
   ```

3. Verify the version:
   ```bash
   docker compose exec php php -v
   ```

### Installed PHP Extensions

The PHP container includes all WordPress recommended extensions:

**WordPress Required/Recommended:**
- mysqli, curl, dom, exif, fileinfo, intl, mbstring, xml, zip, gd (with WebP), opcache, bcmath, filter, iconv, sodium, imagick

**Caching:**
- opcache, redis, apcu, memcached, igbinary

**Database:**
- pdo, pdo_mysql, pdo_pgsql, mysqli, pgsql

**Additional:**
- soap, pcntl, sockets, bz2, xsl, gettext, gmp, tidy, calendar

## Docker Commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f
docker compose logs -f nginx

# Restart a service
docker compose restart nginx

# Run Composer
docker compose exec php composer install

# Run WP-CLI
docker compose exec php wp --path=/var/www/mysite/public plugin list

# Execute command in PHP container
docker compose exec php bash
```

## Directory Structure

```
infra/
├── docker-compose.yml      # Main Docker configuration
├── .env                    # Environment variables
├── docker/
│   ├── php/               # PHP Dockerfile
│   └── apache/            # Apache Dockerfile & vhosts
├── nginx/                 # Nginx virtual host configs (auto-synced)
├── www/                   # Web projects
│   ├── default/           # Default landing page
│   └── <project>/         # Your projects
├── ssl/                   # SSL certificates (wildcard for *.dev.local)
├── mysql/                 # MySQL init scripts
├── postgresql/            # PostgreSQL init scripts
└── scripts/               # Utility scripts
```

## Wildcard SSL Certificate

The SSL certificate covers:
- `*.dev.local` - Any subdomain (mysite.dev.local, api.dev.local, etc.)
- `dev.local` - Base domain
- `localhost`

### Installing CA Certificate in Windows

1. Open Windows File Explorer
2. Navigate to `\\wsl$\Ubuntu\home\jundell\infra\ssl` (adjust path if needed)
3. Double-click `ca.crt`
4. Click "Install Certificate..."
5. Select "Local Machine" → Next
6. Select "Place all certificates in the following store"
7. Click "Browse" → Select "Trusted Root Certification Authorities"
8. Click Next → Finish
9. Restart your browser

**PowerShell (Run as Administrator):**
```powershell
Import-Certificate -FilePath "\\wsl$\Ubuntu\home\jundell\infra\ssl\ca.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

## Creating a New Project

1. Create the project directory:
   ```bash
   mkdir -p www/myproject/public
   ```

2. Create an Nginx config file `nginx/myproject.conf`:
   ```nginx
   server {
       listen 80;
       listen [::]:80;
       server_name myproject.dev.local;
       
       root /var/www/myproject/public;
       index index.php index.html;
       
       location / {
           try_files $uri $uri/ /index.php?$query_string;
       }
       
       location ~ \.php$ {
           fastcgi_pass php:9000;
           fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
           include fastcgi_params;
       }
   }

   server {
       listen 443 ssl http2;
       listen [::]:443 ssl http2;
       server_name myproject.dev.local;
       
       ssl_certificate /etc/nginx/ssl/wildcard.crt;
       ssl_certificate_key /etc/nginx/ssl/wildcard.key;
       
       root /var/www/myproject/public;
       index index.php index.html;
       
       location / {
           try_files $uri $uri/ /index.php?$query_string;
       }
       
       location ~ \.php$ {
           fastcgi_pass php:9000;
           fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
           include fastcgi_params;
       }
   }
   ```

3. Add to Windows hosts file (`C:\Windows\System32\drivers\etc\hosts`):
   ```
   127.0.0.1 myproject.dev.local
   ```

4. Nginx reloads automatically when config changes (via config-watcher)

5. Visit https://myproject.dev.local

## Nginx Config Auto-Sync

The `nginx/` folder is watched for changes. When you:

- **Add** a config file → Nginx reloads automatically
- **Modify** a config file → Nginx reloads automatically
- **Delete** a config file → Nginx reloads automatically

This is handled by the `config-watcher` container using inotify.

## Email Testing

All PHP mail is routed to MailHog:

- SMTP: `mailhog:1025` (from containers)
- Web UI: http://localhost:8025

## Service URLs

| Service | URL |
|---------|-----|
| Default Site | https://dev.local |
| Adminer | http://localhost:8081 |
| MailHog | http://localhost:8025 |
| Apache Direct | http://localhost:8080 |

## Working with WordPress

```bash
# Create project directory
mkdir -p www/myblog/public

# Download WordPress
docker compose exec php sh -c "cd /var/www/myblog/public && wp core download --allow-root"

# Create database
docker compose exec mysql mysql -u root -partisan7530 -e "CREATE DATABASE myblog;"

# Install WordPress
docker compose exec php wp --path=/var/www/myblog/public core install \
  --url=https://myblog.dev.local \
  --title="My Blog" \
  --admin_user=admin \
  --admin_password=password \
  --admin_email=admin@example.com \
  --allow-root
```

## Troubleshooting

### Port already in use
```bash
# Check what's using the port
sudo lsof -i :80
# Stop the process or change ports in docker-compose.yml
```

### Permission issues
```bash
# Fix www folder permissions
sudo chown -R $USER:$USER www/
```

### Nginx config errors
```bash
# Test nginx config
docker compose exec nginx nginx -t
# View nginx logs
docker compose logs -f nginx
```

### Database connection issues
```bash
# Check if MySQL is ready
docker compose exec mysql mysqladmin ping -h localhost -u root -partisan7530

# Check if PostgreSQL is ready
docker compose exec postgresql pg_isready -U root
```

### SSL certificate not trusted
Make sure you installed the CA certificate in Windows (see "Installing CA Certificate in Windows" section above).
