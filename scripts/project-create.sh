#!/bin/bash

# Create a new project served by the automatic nginx vhost

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
DOMAIN_SUFFIX="dev.local"

read_env_value() {
    local key="$1"
    sed -n "s/^${key}=//p" "${INFRA_DIR}/.env" | tail -n 1
}

if [ -f "${INFRA_DIR}/.env" ]; then
    WWW_PATH="${WWW_PATH:-$(read_env_value WWW_PATH)}"
fi

resolve_host_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "${INFRA_DIR}/${1#./}" ;;
    esac
}

WWW_PATH="$(resolve_host_path "${WWW_PATH:-./www}")"

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
    echo "Creates a new project directory served by the automatic nginx vhost."
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
WWW_DIR="${WWW_PATH}/${FULL_DOMAIN}"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Creating Project: ${FULL_DOMAIN}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

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

print_success "Automatic nginx vhost: ${FULL_DOMAIN}"

# Check if hosts entry exists
if grep -q "${FULL_DOMAIN}" /etc/hosts 2>/dev/null; then
    print_success "Hosts entry already exists"
else
    print_warning "Add to /etc/hosts (requires sudo):"
    echo "    echo '127.0.0.1 ${FULL_DOMAIN}' | sudo tee -a /etc/hosts"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Project Created Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Project URL: http://${FULL_DOMAIN}"
echo "Document root: ${WWW_DIR}/public"
echo ""
