#!/bin/bash

# Fix file permissions for WordPress projects in the infra Docker environment
#
# Ownership:  www:www-data (uid 1000:gid 82)
#   - www (uid 1000) maps to the host user, so files are editable in Cursor/IDE
#   - www-data (gid 82) is the PHP-FPM process group, so WordPress can write
#
# Permissions:
#   Directories ........... 755  (wp-content writable dirs: 775)
#   Files ................. 644  (wp-content writable dirs: 664)
#   wp-config.php ......... 640  (owner rw, group read-only)
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

# Fix permissions for a single WordPress project
fix_project() {
    local project_path="$1"
    local project_name
    project_name=$(basename "$project_path")

    echo ""
    echo -e "${BLUE}────────────────────────────────────────${NC}"
    echo -e "${BLUE}  Fixing: ${project_name}${NC}"
    echo -e "${BLUE}────────────────────────────────────────${NC}"

    # Determine the WP root (could be project_path itself or project_path/public)
    local wp_root=""
    if docker exec "$CONTAINER" test -f "${project_path}/wp-includes/version.php" 2>/dev/null; then
        wp_root="$project_path"
    elif docker exec "$CONTAINER" test -f "${project_path}/public/wp-includes/version.php" 2>/dev/null; then
        wp_root="${project_path}/public"
    else
        print_warning "Skipping ${project_name} — not a WordPress project"
        return 0
    fi

    print_info "WordPress root: ${wp_root}"

    # ── 1. Set ownership: www:www-data (uid 1000:gid 82) ──
    print_info "Setting ownership to www:www-data..."
    docker exec -u root "$CONTAINER" chown -R www:www-data "$wp_root"

    # Also fix the project directory and wp-config.php above public/ if applicable
    if [ "$wp_root" != "$project_path" ]; then
        docker exec -u root "$CONTAINER" chown www:www-data "$project_path"
        if docker exec "$CONTAINER" test -f "${project_path}/wp-config.php" 2>/dev/null; then
            docker exec -u root "$CONTAINER" chown www:www-data "${project_path}/wp-config.php"
        fi
    fi
    print_success "Ownership set"

    # ── 2. Base permissions: 755 dirs, 644 files ──
    print_info "Setting base permissions (dirs: 755, files: 644)..."
    docker exec -u root "$CONTAINER" find "$wp_root" -type d -exec chmod 755 {} +
    docker exec -u root "$CONTAINER" find "$wp_root" -type f -exec chmod 644 {} +
    print_success "Base permissions set"

    # ── 3. wp-content writable: 775 dirs, 664 files ──
    if docker exec "$CONTAINER" test -d "${wp_root}/wp-content" 2>/dev/null; then
        print_info "Setting wp-content writable permissions (dirs: 775, files: 664)..."
        docker exec -u root "$CONTAINER" find "${wp_root}/wp-content" -type d -exec chmod 775 {} +
        docker exec -u root "$CONTAINER" find "${wp_root}/wp-content" -type f -exec chmod 664 {} +
        print_success "wp-content permissions set"
    fi

    # ── 4. Secure wp-config.php (640) ──
    for config_path in "${wp_root}/wp-config.php" "${project_path}/wp-config.php"; do
        if docker exec "$CONTAINER" test -f "$config_path" 2>/dev/null; then
            print_info "Securing wp-config.php (640)..."
            docker exec -u root "$CONTAINER" chmod 640 "$config_path"
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
                # Verify it was added
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
        docker exec -u root "$CONTAINER" chmod 775 "${wp_root}/wp-content/uploads"
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
echo "  Owner: www (uid 1000) — editable in your IDE"
echo "  Group: www-data (gid 82) — writable by PHP-FPM"
echo ""
