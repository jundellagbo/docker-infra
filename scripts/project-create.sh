#!/bin/bash

# Create a new project with nginx vhost and www directory

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
DOMAIN_SUFFIX="dev.local"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}→ $1${NC}"; }
print_warning() { echo -e "${YELLOW}! $1${NC}"; }

usage() {
    echo "Usage: $0 <project-name>"
    echo ""
    echo "Creates a new project with nginx configuration and www directory."
    echo ""
    echo "Example:"
    echo "  $0 myapp"
    echo "  Creates: myapp.dev.local"
    echo ""
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

PROJECT_NAME="$1"
FULL_DOMAIN="${PROJECT_NAME}.${DOMAIN_SUFFIX}"
NGINX_CONF="${INFRA_DIR}/nginx/${FULL_DOMAIN}.conf"
WWW_DIR="${INFRA_DIR}/www/${FULL_DOMAIN}"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Creating Project: ${FULL_DOMAIN}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if project already exists
if [ -f "$NGINX_CONF" ]; then
    print_error "Project already exists: $NGINX_CONF"
    exit 1
fi

if [ -d "$WWW_DIR" ]; then
    print_error "Directory already exists: $WWW_DIR"
    exit 1
fi

# Create www directory
print_info "Creating www directory..."
mkdir -p "${WWW_DIR}/public"
print_success "Created ${WWW_DIR}/public"

# Create default index.php
cat > "${WWW_DIR}/public/index.php" << 'EOF'
<?php
$projectName = basename(dirname(__DIR__));
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= htmlspecialchars($projectName) ?></title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 3rem;
            border-radius: 1rem;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
            text-align: center;
            max-width: 500px;
        }
        h1 { color: #1a202c; margin-bottom: 1rem; }
        p { color: #718096; margin-bottom: 0.5rem; }
        .php-version { 
            background: #edf2f7; 
            padding: 0.5rem 1rem; 
            border-radius: 0.5rem; 
            display: inline-block;
            margin-top: 1rem;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1><?= htmlspecialchars($projectName) ?></h1>
        <p>Your project is ready!</p>
        <p class="php-version">PHP <?= PHP_VERSION ?></p>
    </div>
</body>
</html>
EOF
print_success "Created index.php"

# Create nginx configuration
print_info "Creating nginx configuration..."
cat > "$NGINX_CONF" << EOF
# ${FULL_DOMAIN} - redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${FULL_DOMAIN};

    return 301 https://\$host\$request_uri;
}

# ${FULL_DOMAIN} HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${FULL_DOMAIN};

    ssl_certificate /etc/nginx/ssl/wildcard.crt;
    ssl_certificate_key /etc/nginx/ssl/wildcard.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root /var/www/${FULL_DOMAIN}/public;
    index index.html index.htm index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass php:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTPS on;
        fastcgi_param HTTP_X_FORWARDED_PROTO https;
        include fastcgi_params;
        fastcgi_index index.php;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
print_success "Created ${NGINX_CONF}"

# Check if hosts entry exists
if grep -q "${FULL_DOMAIN}" /etc/hosts 2>/dev/null; then
    print_success "Hosts entry already exists"
else
    print_warning "Add to /etc/hosts (requires sudo):"
    echo "    echo '127.0.0.1 ${FULL_DOMAIN}' | sudo tee -a /etc/hosts"
fi

# Reload nginx if running
print_info "Reloading nginx..."
if docker exec infra-nginx nginx -t 2>/dev/null; then
    docker exec infra-nginx nginx -s reload 2>/dev/null && print_success "Nginx reloaded" || print_warning "Could not reload nginx"
else
    print_error "Nginx configuration test failed"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Project Created Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Project URL: https://${FULL_DOMAIN}"
echo "Document root: ${WWW_DIR}/public"
echo ""
