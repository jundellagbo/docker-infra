#!/bin/bash

# Configure persistent host DNS for *.dev.local on Linux.

set -euo pipefail

DOMAIN_SUFFIX="dev.local"
SERVICE_NAME="infra-dev-local-dns.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}→ $1${NC}"; }
print_warning() { echo -e "${YELLOW}! $1${NC}"; }

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "Missing required command: $1"
        exit 1
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    print_error "Run this script with sudo:"
    echo "    sudo $0"
    exit 1
fi

require_command dnsmasq
require_command resolvectl
require_command systemctl

print_info "Installing ${SERVICE_NAME}..."
cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=Infra wildcard DNS for *.${DOMAIN_SUFFIX}
Documentation=file://${INFRA_DIR}/README.md
After=systemd-resolved.service
Requires=systemd-resolved.service

[Service]
Type=simple
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --no-resolv --no-hosts --listen-address=127.0.0.1 --bind-interfaces --address=/${DOMAIN_SUFFIX}/127.0.0.1 --address=/.${DOMAIN_SUFFIX}/127.0.0.1
ExecStartPost=/usr/bin/resolvectl dns lo 127.0.0.1
ExecStartPost=/usr/bin/resolvectl domain lo ~${DOMAIN_SUFFIX}
ExecStartPost=/usr/bin/resolvectl default-route lo false
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"

print_info "Verifying wildcard host DNS..."
if getent hosts "health.${DOMAIN_SUFFIX}" | grep -q "127.0.0.1"; then
    print_success "*.dev.local resolves to 127.0.0.1"
else
    print_warning "Could not verify wildcard DNS through getent"
    print_warning "Check with: resolvectl query health.${DOMAIN_SUFFIX}"
fi

print_success "Host DNS setup complete"
