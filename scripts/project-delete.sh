#!/bin/bash

# Delete a project and its nginx vhost

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
    NGINX_PATH="${NGINX_PATH:-$(read_env_value NGINX_PATH)}"
fi

resolve_host_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "${INFRA_DIR}/${1#./}" ;;
    esac
}

WWW_PATH="$(resolve_host_path "${WWW_PATH:-./www}")"
NGINX_PATH="$(resolve_host_path "${NGINX_PATH:-./nginx}")"

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
    echo "Usage: $0 <project-name> [--keep-files]"
    echo ""
    echo "Deletes a project's nginx configuration and optionally its files."
    echo ""
    echo "Options:"
    echo "  --keep-files    Keep the www directory (only remove nginx config)"
    echo ""
    echo "Example:"
    echo "  $0 myapp"
    echo "  $0 myapp --keep-files"
    echo ""
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

PROJECT_NAME="$1"
KEEP_FILES=false

if [ "$2" = "--keep-files" ]; then
    KEEP_FILES=true
fi

FULL_DOMAIN="${PROJECT_NAME}.${DOMAIN_SUFFIX}"
NGINX_CONF="${NGINX_PATH}/${FULL_DOMAIN}.conf"
WWW_DIR="${WWW_PATH}/${FULL_DOMAIN}"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Deleting Project: ${FULL_DOMAIN}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if project exists
if [ ! -f "$NGINX_CONF" ] && [ ! -d "$WWW_DIR" ]; then
    print_error "Project not found: ${FULL_DOMAIN}"
    exit 1
fi

# Confirm deletion
echo -e "${YELLOW}This will delete:${NC}"
[ -f "$NGINX_CONF" ] && echo "  - $NGINX_CONF"
if [ "$KEEP_FILES" = false ] && [ -d "$WWW_DIR" ]; then
    echo "  - $WWW_DIR (and all contents)"
fi
echo ""
read -p "Are you sure? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Cancelled"
    exit 0
fi

# Remove nginx configuration
if [ -f "$NGINX_CONF" ]; then
    print_info "Removing nginx configuration..."
    rm -f "$NGINX_CONF"
    print_success "Removed ${NGINX_CONF}"
fi

# Remove www directory
if [ "$KEEP_FILES" = false ] && [ -d "$WWW_DIR" ]; then
    print_info "Removing www directory..."
    rm -rf "$WWW_DIR"
    print_success "Removed ${WWW_DIR}"
elif [ -d "$WWW_DIR" ]; then
    print_warning "Keeping www directory: ${WWW_DIR}"
fi

# Check if hosts entry exists
if grep -q "${FULL_DOMAIN}" /etc/hosts 2>/dev/null; then
    print_warning "Remove from /etc/hosts (requires sudo):"
    echo "    sudo sed -i '/${FULL_DOMAIN}/d' /etc/hosts"
fi

# Reload nginx if running
print_info "Reloading nginx..."
if docker exec infra-nginx nginx -t 2>/dev/null; then
    docker exec infra-nginx nginx -s reload 2>/dev/null && print_success "Nginx reloaded" || print_warning "Could not reload nginx"
else
    print_warning "Nginx not running or configuration issue"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Project Deleted Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
