#!/bin/bash

# Uninstall local web services before switching to Docker

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}→ $1${NC}"; }
print_warning() { echo -e "${YELLOW}! $1${NC}"; }

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run with sudo"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Uninstalling Local Web Services${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Stop services first
print_info "Stopping services..."
systemctl stop apache2 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl stop mysql 2>/dev/null || true
systemctl stop postgresql 2>/dev/null || true
print_success "Services stopped"

# Disable services
print_info "Disabling services..."
systemctl disable apache2 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true
systemctl disable mysql 2>/dev/null || true
systemctl disable postgresql 2>/dev/null || true
print_success "Services disabled"

# Uninstall Apache
print_info "Uninstalling Apache2..."
apt-get purge -y apache2 apache2-utils apache2-bin libapache2-mod-php* 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
rm -rf /etc/apache2 2>/dev/null || true
print_success "Apache2 uninstalled"

# Uninstall Nginx
print_info "Uninstalling Nginx..."
apt-get purge -y nginx nginx-common nginx-full 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
rm -rf /etc/nginx 2>/dev/null || true
print_success "Nginx uninstalled"

# Uninstall MySQL
print_info "Uninstalling MySQL..."
apt-get purge -y mysql-server mysql-client mysql-common 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
# Keep data by default, user can remove manually
print_warning "MySQL data kept at /var/lib/mysql - remove manually if needed"
print_success "MySQL uninstalled"

# Uninstall PostgreSQL
print_info "Uninstalling PostgreSQL..."
apt-get purge -y postgresql postgresql-contrib 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
# Keep data by default
print_warning "PostgreSQL data kept at /var/lib/postgresql - remove manually if needed"
print_success "PostgreSQL uninstalled"

# Clean up
print_info "Cleaning up..."
apt-get autoclean -y 2>/dev/null || true
print_success "Cleanup complete"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Uninstallation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Freed ports:"
echo "  - 80, 443 (Nginx)"
echo "  - 8080, 8443 (Apache)"
echo "  - 3306 (MySQL)"
echo "  - 5432 (PostgreSQL)"
echo ""
echo "You can now start Docker services:"
echo "  cd $(dirname "$0")/.. && ./project-manager.sh start"
echo ""
