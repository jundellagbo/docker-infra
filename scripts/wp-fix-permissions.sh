#!/bin/bash

# Fix file permissions for WordPress projects in the infra Docker environment
#
# Ownership:  www:www-data (uid 1000:gid 82)
#   - www (uid 1000) maps to the host user, so files are editable in Cursor/IDE
#   - www-data (gid 82) is the PHP-FPM process group, so WordPress can write
#
# Permissions:
#   Directories ........... 2775 (setgid: new files inherit the www-data group)
#   Files ................. 664  (owner+group rw, world-readable)
#   wp-config.php ......... 660  (owner+group rw, not world-readable)
#
# Incoming / newly created files:
#   Default ACLs are applied on the host side of the bind mount so that any
#   NEW file — created by PHP-FPM (www-data), docker exec as root, or the
#   host user in a terminal — is automatically rw for uid 1000 and gid 82,
#   regardless of the creator's umask. Requires `setfacl` on the host.
#
# WordPress config:
#   FS_METHOD ............. 'direct'  (bypass FTP prompt for plugin/theme uploads)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
CONTAINER="infra-php"
WEB_ROOT="/var/www"

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
    echo "Usage: $0 [project-name]"
    echo ""
    echo "Fix file permissions for WordPress projects."
    echo ""
    echo "Options:"
    echo "  project-name    Fix a specific project (e.g. mysite.dev.local)"
    echo "                  If omitted, all WordPress projects are fixed."
    echo ""
    echo "Examples:"
    echo "  $0                          # Fix all WordPress projects"
    echo "  $0 gogogarage.dev.local     # Fix a specific project"
    echo ""
    exit 1
}

# Show help
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

# Verify the PHP container is running
if ! docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q "true"; then
    print_error "Container '$CONTAINER' is not running. Start it with: docker compose up -d"
    exit 1
fi

# Resolve the host-side path of the /var/www bind mount (used for ACLs, since
# the Alpine container has no setfacl — ACLs set on the host apply in-container)
HOST_WEB_ROOT=$(docker inspect "$CONTAINER" \
    --format "{{range .Mounts}}{{if eq .Destination \"${WEB_ROOT}\"}}{{.Source}}{{end}}{{end}}" 2>/dev/null)

# Fix permissions for a single project (WordPress or not)
fix_project() {
    local project_path="$1"
    local project_name
    project_name=$(basename "$project_path")

    echo ""
    echo -e "${BLUE}────────────────────────────────────────${NC}"
    echo -e "${BLUE}  Fixing: ${project_name}${NC}"
    echo -e "${BLUE}────────────────────────────────────────${NC}"

    # Determine the web-accessible root (public/ subdirectory if present)
    local public_root=""
    if docker exec "$CONTAINER" test -d "${project_path}/public" 2>/dev/null; then
        public_root="${project_path}/public"
    else
        public_root="$project_path"
    fi

    # Determine if this is a WordPress project
    local wp_root=""
    if docker exec "$CONTAINER" test -f "${project_path}/wp-includes/version.php" 2>/dev/null; then
        wp_root="$project_path"
    elif docker exec "$CONTAINER" test -f "${project_path}/public/wp-includes/version.php" 2>/dev/null; then
        wp_root="${project_path}/public"
    fi

    if [ -n "$wp_root" ]; then
        print_info "WordPress root: ${wp_root}"
    else
        print_info "Web root: ${public_root} (not a WordPress project — fixing base permissions)"
    fi

    # ── 1. Set ownership: www:www-data (uid 1000:gid 82) ──
    print_info "Setting ownership to www:www-data..."
    docker exec -u root "$CONTAINER" chown -R www:www-data "$project_path"
    print_success "Ownership set"

    # ── 2. Default ACLs so incoming files stay accessible ──
    # Default ACLs guarantee any NEW file is rw for the host user (uid 1000)
    # and PHP-FPM (gid 82) no matter who creates it or what their umask is.
    # Applied on the host side of the bind mount (container lacks setfacl).
    # Must run BEFORE the chmod step: non-root setfacl strips setgid bits.
    local host_project_path="${HOST_WEB_ROOT}/${project_name}"
    if command -v setfacl >/dev/null 2>&1 && [ -n "$HOST_WEB_ROOT" ] && [ -d "$host_project_path" ]; then
        print_info "Applying default ACLs (new files: rw for uid 1000 + gid 82)..."
        setfacl -R -m "u:1000:rwX,g:82:rwX,o::rX" "$host_project_path"
        setfacl -R -d -m "u::rwX,g::rwX,u:1000:rwX,g:82:rwX,o::rX" "$host_project_path"
        print_success "Default ACLs applied"
    else
        print_warning "setfacl unavailable or host path not found — skipping ACLs."
        print_warning "New files created by PHP may not be writable from the host terminal."
    fi

    # ── 3. Base permissions: 2775 dirs (setgid), 664 files ──
    # setgid on directories makes every NEW file/dir inherit the www-data
    # group; group-writable files mean both the host user and PHP-FPM can
    # edit everything even where ACLs are unavailable.
    print_info "Setting base permissions (dirs: 2775 setgid, files: 664)..."
    docker exec -u root "$CONTAINER" find "$project_path" -type d -exec chmod 2775 {} +
    docker exec -u root "$CONTAINER" find "$project_path" -type f -exec chmod 664 {} +
    print_success "Base permissions set"

    # Stop here for non-WordPress projects
    if [ -z "$wp_root" ]; then
        print_success "Done: ${project_name}"
        return 0
    fi

    # ── 4. Secure wp-config.php (660: owner+group rw, not world-readable) ──
    for config_path in "${wp_root}/wp-config.php" "${project_path}/wp-config.php"; do
        if docker exec "$CONTAINER" test -f "$config_path" 2>/dev/null; then
            print_info "Securing wp-config.php (660)..."
            docker exec -u root "$CONTAINER" chmod 660 "$config_path"
            print_success "wp-config.php secured"
            break
        fi
    done

    # ── 5. Ensure FS_METHOD is set to 'direct' in wp-config.php ──
    # Without this, WordPress detects that file owner (www) ≠ PHP process user
    # (www-data) and asks for FTP credentials when installing plugins/themes.
    for config_path in "${project_path}/wp-config.php" "${wp_root}/wp-config.php"; do
        if docker exec "$CONTAINER" test -f "$config_path" 2>/dev/null; then
            if ! docker exec "$CONTAINER" grep -q "FS_METHOD" "$config_path" 2>/dev/null; then
                print_info "Adding FS_METHOD 'direct' to wp-config.php..."
                docker exec -u root "$CONTAINER" sh -c \
                    "sed -i \"/That's all, stop editing/i define('FS_METHOD', 'direct');\" '$config_path'"
                if docker exec "$CONTAINER" grep -q "FS_METHOD" "$config_path" 2>/dev/null; then
                    print_success "FS_METHOD set to 'direct'"
                else
                    print_error "Failed to add FS_METHOD — please add manually:"
                    echo "        define('FS_METHOD', 'direct');"
                fi
            else
                print_success "FS_METHOD already defined in wp-config.php"
            fi
            break
        fi
    done

    # ── 6. Ensure uploads directory exists ──
    if ! docker exec "$CONTAINER" test -d "${wp_root}/wp-content/uploads" 2>/dev/null; then
        print_info "Creating wp-content/uploads..."
        docker exec -u root "$CONTAINER" mkdir -p "${wp_root}/wp-content/uploads"
        docker exec -u root "$CONTAINER" chown www:www-data "${wp_root}/wp-content/uploads"
        docker exec -u root "$CONTAINER" chmod 2775 "${wp_root}/wp-content/uploads"
        print_success "uploads directory created"
    fi

    print_success "Done: ${project_name}"
}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  WordPress Permission Fixer${NC}"
echo -e "${BLUE}========================================${NC}"

# Collect projects to process
if [ -n "$1" ]; then
    # Specific project
    PROJECT_PATH="${WEB_ROOT}/$1"
    if ! docker exec "$CONTAINER" test -d "$PROJECT_PATH" 2>/dev/null; then
        print_error "Project not found: $1"
        echo "  Available projects in ${WEB_ROOT}:"
        docker exec "$CONTAINER" ls -1 "$WEB_ROOT" 2>/dev/null | while read -r dir; do
            echo "    - $dir"
        done
        exit 1
    fi
    fix_project "$PROJECT_PATH"
else
    # All projects
    FOUND=0
    for project in $(docker exec "$CONTAINER" ls -1 "$WEB_ROOT" 2>/dev/null); do
        fix_project "${WEB_ROOT}/${project}"
        FOUND=$((FOUND + 1))
    done

    if [ "$FOUND" -eq 0 ]; then
        print_warning "No projects found in ${WEB_ROOT}"
        exit 0
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Permissions Fixed Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Owner: www (uid 1000) — editable in your IDE/terminal"
echo "  Group: www-data (gid 82) — writable by PHP-FPM (inherited via setgid)"
echo "  New files: default ACLs keep them rw for both, regardless of umask"
echo ""
