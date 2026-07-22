#!/bin/bash

# Install PHP (multiple versions + switcher), Composer, WP-CLI and Node on the host.
#
#   sudo ./install.sh                          # 7.4 - 8.4, default 8.3
#   sudo ./install.sh --versions 8.2 8.3 8.4   # only these (also: --versions=8.2,8.3)
#   sudo ./install.sh --default 8.2            # pick the default CLI version
#   sudo ./install.sh --no-composer --no-wp    # skip the extras
#   sudo ./install.sh --no-node                # skip Node/nvm
#   sudo ./install.sh --node-version 20        # install this Node major (default: --lts)
#   sudo ./install.sh --no-claude              # skip the Claude Code CLI
#   sudo ./install.sh --no-mcp                 # skip registering Claude MCP servers
#   sudo ./install.sh --no-plugins             # skip installing Claude plugins
#
# Afterwards "phpsw" switches the active CLI/FPM version and "nvm" switches Node:
#
#   phpsw          # list installed PHP versions
#   phpsw 8.2      # make 8.2 the default
#   nvm ls         # list installed Node versions
#   nvm use 20     # switch the active Node version

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

PHP_VERSIONS="7.4 8.0 8.1 8.2 8.3 8.4"
DEFAULT_VERSION="8.3"
INSTALL_COMPOSER=1
INSTALL_WPCLI=1
INSTALL_NODE=1
NODE_VERSION="--lts"
INSTALL_CLAUDE=1
INSTALL_MCP=1
INSTALL_PLUGINS=1

# --versions takes one or more versions: "--versions 8.2 8.3", --versions=8.2,8.3
# and --versions "8.2 8.3" all mean the same thing.
picked_versions=""
add_versions() {
    local v
    for v in $(printf '%s' "$1" | tr ',' ' '); do
        picked_versions="$picked_versions $v"
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --versions|-V)      add_versions "$2"; shift ;;
        --versions=*)       add_versions "${1#*=}" ;;
        --default|-d)       DEFAULT_VERSION="$2"; shift ;;
        --default=*)        DEFAULT_VERSION="${1#*=}" ;;
        --no-composer)      INSTALL_COMPOSER=0 ;;
        --no-wp|--no-wpcli) INSTALL_WPCLI=0 ;;
        --no-node)          INSTALL_NODE=0 ;;
        --node-version)     NODE_VERSION="$2"; shift ;;
        --node-version=*)   NODE_VERSION="${1#*=}" ;;
        --no-claude)        INSTALL_CLAUDE=0 ;;
        --no-mcp)           INSTALL_MCP=0 ;;
        --no-plugins)       INSTALL_PLUGINS=0 ;;
        -h|--help)
            sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        # Bare version numbers extend the list: "--versions 8.2 8.3 8.4"
        [0-9].[0-9]|[0-9].[0-9][0-9]) add_versions "$1" ;;
        *) print_error "unknown option: $1"; exit 1 ;;
    esac
    shift
done

if [ -n "$picked_versions" ]; then
    PHP_VERSIONS="${picked_versions# }"
fi

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run with sudo"
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    print_error "This installer targets Debian/Ubuntu (apt-get not found)"
    exit 1
fi

case " $PHP_VERSIONS " in
    *" $DEFAULT_VERSION "*) ;;
    *)  # Fall back to the newest version actually being installed
        for v in $PHP_VERSIONS; do DEFAULT_VERSION="$v"; done ;;
esac

export DEBIAN_FRONTEND=noninteractive

print_info "PHP versions: ${PHP_VERSIONS} (default ${DEFAULT_VERSION})"

# Extensions every Laravel app needs, plus the WordPress/dev extras.
# Laravel requires ctype, curl, dom, fileinfo, filter, hash, mbstring, openssl,
# pcre, pdo, session and tokenizer - those ship inside -cli/-common/-xml.
PHP_EXTENSIONS="
bcmath
bz2
cli
common
curl
dev
fpm
gd
gmp
igbinary
imagick
imap
intl
ldap
mbstring
memcached
msgpack
mysql
opcache
pgsql
readline
redis
soap
sqlite3
tidy
xdebug
xml
xsl
zip
"

# ---------------------------------------------------------------- repositories

print_info "Installing prerequisites..."
apt-get update -qq
apt-get install -y -qq \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    lsb-release \
    gnupg \
    curl \
    unzip \
    git >/dev/null
print_success "Prerequisites installed"

if grep -rqs "ondrej/php" /etc/apt/sources.list.d/ 2>/dev/null; then
    print_info "ondrej/php repository already present"
else
    print_info "Adding the ondrej/php repository..."
    add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || {
        print_error "Failed to add ppa:ondrej/php"
        exit 1
    }
    print_success "Repository added"
fi

apt-get update -qq

# ------------------------------------------------------------------ php builds

# Not every extension exists for every version, so filter against the real
# package index instead of letting one missing package fail the whole install.
packages_for() {
    local version="$1" ext pkg available=""
    for ext in $PHP_EXTENSIONS; do
        pkg="php${version}-${ext}"
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            available="$available $pkg"
        else
            print_warning "skipping $pkg (not available)" >&2
        fi
    done
    printf '%s\n' "$available"
}

for version in $PHP_VERSIONS; do
    print_info "Installing PHP ${version}..."
    pkgs="$(packages_for "$version")"
    if [ -z "$pkgs" ]; then
        print_error "No packages found for PHP ${version} - skipping"
        continue
    fi
    # shellcheck disable=SC2086
    apt-get install -y -qq $pkgs >/dev/null || {
        print_error "PHP ${version} installation failed"
        exit 1
    }
    # Xdebug is installed but left off - "phpenmod -v <version> xdebug" turns it on
    if command -v phpdismod >/dev/null 2>&1; then
        phpdismod -v "$version" xdebug >/dev/null 2>&1 || true
    fi
    print_success "PHP ${version} installed"
done

# ---------------------------------------------------------------- php switcher

print_info "Installing the phpsw version switcher..."
cat > /usr/local/bin/phpsw << 'SWITCHER'
#!/bin/bash
#
# Switch the default PHP version (CLI + FPM).
#
#   phpsw          list installed versions
#   phpsw 8.2      switch to PHP 8.2

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

installed_versions() {
    ls -1 /usr/bin/php[0-9].[0-9] 2>/dev/null | sed 's#.*/php##' | sort -V
}

if [ -z "$1" ]; then
    current="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)"
    echo "installed PHP versions:"
    for v in $(installed_versions); do
        if [ "$v" = "$current" ]; then
            echo -e "  ${GREEN}* ${v}${NC}"
        else
            echo "    ${v}"
        fi
    done
    echo ""
    echo "usage: phpsw <version>"
    exit 0
fi

version="$1"
if [ ! -x "/usr/bin/php${version}" ]; then
    echo -e "${RED}✗ PHP ${version} is not installed${NC}" >&2
    echo "installed: $(installed_versions | tr '\n' ' ')" >&2
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

for binary in php phar phar.phar php-config phpize; do
    [ -x "/usr/bin/${binary}${version}" ] || continue
    update-alternatives --set "$binary" "/usr/bin/${binary}${version}" >/dev/null 2>&1 ||
        update-alternatives --install "/usr/bin/${binary}" "$binary" \
            "/usr/bin/${binary}${version}" 100 >/dev/null 2>&1 || true
done

# Keep only the selected FPM pool running so the socket path is predictable
if command -v systemctl >/dev/null 2>&1; then
    for v in $(installed_versions); do
        service="php${v}-fpm.service"
        systemctl list-unit-files "$service" >/dev/null 2>&1 || continue
        if [ "$v" = "$version" ]; then
            systemctl enable --now "$service" >/dev/null 2>&1 || true
            systemctl restart "$service" >/dev/null 2>&1 || true
        else
            systemctl disable --now "$service" >/dev/null 2>&1 || true
        fi
    done
fi

echo -e "${GREEN}✓ now using $(php -v | head -1)${NC}"
echo -e "${BLUE}→ fpm socket: /run/php/php${version}-fpm.sock${NC}"
SWITCHER
chmod +x /usr/local/bin/phpsw
print_success "phpsw installed"

print_info "Setting PHP ${DEFAULT_VERSION} as the default..."
/usr/local/bin/phpsw "$DEFAULT_VERSION"

# -------------------------------------------------------------------- composer

if [ $INSTALL_COMPOSER -eq 1 ]; then
    print_info "Installing Composer..."
    expected="$(curl -fsSL https://composer.github.io/installer.sig)"
    tmp="$(mktemp -d)"
    curl -fsSL https://getcomposer.org/installer -o "${tmp}/composer-setup.php"
    actual="$(php -r "echo hash_file('sha384', '${tmp}/composer-setup.php');")"
    if [ "$expected" != "$actual" ]; then
        rm -rf "$tmp"
        print_error "Composer installer checksum mismatch - aborting"
        exit 1
    fi
    php "${tmp}/composer-setup.php" --quiet --install-dir=/usr/local/bin --filename=composer
    rm -rf "$tmp"

    # Composer refuses to run plugins/scripts as root without this; dev box, so allow it
    cat > /etc/profile.d/composer.sh << 'EOF'
export COMPOSER_ALLOW_SUPERUSER=1
export PATH="$PATH:$HOME/.config/composer/vendor/bin:$HOME/.composer/vendor/bin"
EOF
    chmod 644 /etc/profile.d/composer.sh
    print_success "Composer installed"
fi

# ---------------------------------------------------------------------- wp-cli

if [ $INSTALL_WPCLI -eq 1 ]; then
    print_info "Installing WP-CLI..."
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -o /usr/local/bin/wp-cli.phar
    chmod +x /usr/local/bin/wp-cli.phar

    # Wrapper so root doesn't have to remember --allow-root every single time
    cat > /usr/local/bin/wp << 'EOF'
#!/bin/bash
if [ "$EUID" -eq 0 ]; then
    case " $* " in
        *" --allow-root "*) ;;
        *) set -- --allow-root "$@" ;;
    esac
fi
exec /usr/local/bin/wp-cli.phar "$@"
EOF
    chmod +x /usr/local/bin/wp
    print_success "WP-CLI installed"
fi

# -------------------------------------------------------------- per-user tools

# nvm, the Claude CLI and its plugins are per-user tools: they install into a
# home directory and run from a login shell, so target the user who invoked
# sudo (not root) - that's whose shell will actually use them.
TOOL_USER="${SUDO_USER:-root}"
TOOL_HOME="$(getent passwd "$TOOL_USER" | cut -d: -f6)"
TOOL_HOME="${TOOL_HOME:-$HOME}"
run_as_user() { su - "$TOOL_USER" -c "$1"; }

# ------------------------------------------------------------------ node / nvm

if [ $INSTALL_NODE -eq 1 ]; then
    print_info "Installing Node via nvm..."

    # "20" and "--lts" both mean an install target; only "--lts" needs the
    # lts/* alias for a persistent default.
    if [ "$NODE_VERSION" = "--lts" ]; then
        node_default="lts/*"
    else
        node_default="$NODE_VERSION"
    fi

    if [ -s "$TOOL_HOME/.nvm/nvm.sh" ]; then
        print_info "nvm already present for ${TOOL_USER}"
    else
        run_as_user 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash >/dev/null 2>&1' \
            && print_success "nvm installed for ${TOOL_USER}" \
            || print_warning "nvm install failed for ${TOOL_USER} - skipping Node"
    fi

    if [ -s "$TOOL_HOME/.nvm/nvm.sh" ]; then
        run_as_user "export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; nvm install ${NODE_VERSION} && nvm alias default '${node_default}'" >/dev/null 2>&1 \
            && print_success "Node ${NODE_VERSION} installed (default: ${node_default})" \
            || print_warning "Node ${NODE_VERSION} installation failed"
    fi
fi

# ------------------------------------------------------------------ claude cli

if [ $INSTALL_CLAUDE -eq 1 ]; then
    print_info "Installing the Claude Code CLI..."

    # The native installer drops the binary into the user's ~/.local/bin, so it
    # needs no root and no Node. Just the CLI here - skills/instructions and the
    # plugins/MCPs are wired separately.
    if run_as_user 'command -v claude >/dev/null 2>&1'; then
        print_info "Claude CLI already present for ${TOOL_USER}"
    else
        run_as_user 'curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1' \
            && print_success "Claude CLI installed for ${TOOL_USER}" \
            || print_warning "Claude CLI install failed for ${TOOL_USER}"
    fi
fi

# ------------------------------------------------------------------ claude mcps

if [ $INSTALL_CLAUDE -eq 1 ] && [ $INSTALL_MCP -eq 1 ]; then
    if run_as_user 'command -v claude >/dev/null 2>&1'; then
        print_info "Registering Claude MCP servers..."

        # $1 = server name (idempotency check + message), $2 = `claude mcp add`
        # argument string. User scope so the servers are available in every repo.
        claude_mcp_add() {
            local name="$1" args="$2"
            if run_as_user "claude mcp get '$name' >/dev/null 2>&1"; then
                print_info "MCP ${name} already registered"
            elif run_as_user "claude mcp add ${args} >/dev/null 2>&1"; then
                print_success "MCP ${name} registered"
            else
                print_warning "MCP ${name} registration failed"
            fi
        }

        claude_mcp_add figma           "-s user --transport http figma https://mcp.figma.com/mcp"
        claude_mcp_add chrome-devtools "-s user chrome-devtools -- npx chrome-devtools-mcp@latest"
    else
        print_warning "Claude CLI not available - skipping MCP registration"
    fi
fi

# --------------------------------------------------------------- claude plugins

if [ $INSTALL_CLAUDE -eq 1 ] && [ $INSTALL_PLUGINS -eq 1 ]; then
    if run_as_user 'command -v claude >/dev/null 2>&1'; then
        print_info "Adding Claude plugin marketplaces..."

        # $1 = marketplace name (idempotency check), $2 = source (owner/repo).
        # claude-plugins-official ships built-in, so only the extras are added.
        claude_mkt_add() {
            local name="$1" src="$2"
            if run_as_user "claude plugin marketplace list 2>/dev/null | grep -qw '$name'"; then
                print_info "marketplace ${name} already added"
            elif run_as_user "claude plugin marketplace add '$src' >/dev/null 2>&1"; then
                print_success "marketplace ${name} added"
            else
                print_warning "marketplace ${name} add failed"
            fi
        }

        # $1 = plugin@marketplace id. timeout guards against a hang on a
        # non-interactive trust prompt; installs at user scope (the default).
        claude_plugin_add() {
            local id="$1"
            if run_as_user "claude plugin list 2>/dev/null | grep -qF '$id'"; then
                print_info "plugin ${id} already installed"
            elif run_as_user "timeout 180 claude plugin install '$id' -s user >/dev/null 2>&1"; then
                print_success "plugin ${id} installed"
            else
                print_warning "plugin ${id} install failed"
            fi
        }

        claude_mkt_add chrome-devtools-plugins ChromeDevTools/chrome-devtools-mcp
        claude_mkt_add impeccable              pbakaus/impeccable

        print_info "Installing Claude plugins..."
        claude_plugin_add figma@claude-plugins-official
        claude_plugin_add skill-creator@claude-plugins-official
        claude_plugin_add chrome-devtools-mcp@chrome-devtools-plugins
        claude_plugin_add impeccable@impeccable

        # emilkowalski's design skills ("milkowalski/skill") ship through the
        # "skills" CLI, not a Claude marketplace - install them the documented
        # way. Needs Node/npx (installed above via nvm).
        if run_as_user 'command -v npx >/dev/null 2>&1 || { export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && command -v npx >/dev/null 2>&1; }'; then
            run_as_user 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; timeout 180 npx -y skills@latest add emilkowalski/skills >/dev/null 2>&1' \
                && print_success "skills emilkowalski/skills installed" \
                || print_warning "emilkowalski/skills install failed - run manually: npx skills@latest add emilkowalski/skills"
        else
            print_warning "npx not available - skipping emilkowalski/skills"
        fi
    else
        print_warning "Claude CLI not available - skipping plugin install"
    fi
fi

# ------------------------------------------------------------------------ done

echo ""
print_success "Installation complete"
echo ""
echo "  php       $(php -v | head -1)"
[ $INSTALL_COMPOSER -eq 1 ] && echo "  composer  $(COMPOSER_ALLOW_SUPERUSER=1 composer --version --no-ansi 2>/dev/null | head -1)"
[ $INSTALL_WPCLI -eq 1 ] && echo "  wp        $(wp --version 2>/dev/null | head -1)"
if [ $INSTALL_NODE -eq 1 ]; then
    node_ver="$(su - "${SUDO_USER:-root}" -c 'export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh" 2>/dev/null; node --version' 2>/dev/null | tail -1)"
    [ -n "$node_ver" ] && echo "  node      ${node_ver} (via nvm)"
fi
if [ $INSTALL_CLAUDE -eq 1 ]; then
    claude_ver="$(su - "${SUDO_USER:-root}" -c 'command -v claude >/dev/null 2>&1 && claude --version' 2>/dev/null | tail -1)"
    [ -n "$claude_ver" ] && echo "  claude    ${claude_ver}"
fi
echo ""
echo "  installed: $(ls -1 /usr/bin/php[0-9].[0-9] 2>/dev/null | sed 's#.*/php##' | sort -V | tr '\n' ' ')"
echo "  switch:    phpsw <version>   |   nvm use <version>"
echo ""

# ------------------------------------------------------------ shell integration

# Make bash automatically load git.sh (which pulls in llm.sh and the infra-llm
# aliases) in future sessions. The repo is resolved from this script's own
# location, and the line is written to the invoking user's ~/.bashrc - so it
# works wherever the checkout lives and for whoever ran sudo, not a fixed path.
INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
GIT_SH="${INFRA_DIR}/git.sh"
if [ -f "$GIT_SH" ]; then
    src_line="[ -f \"$GIT_SH\" ] && source \"$GIT_SH\""
    bashrc="${TOOL_HOME}/.bashrc"
    run_as_user "touch '$bashrc'; grep -qF '$GIT_SH' '$bashrc' 2>/dev/null || printf '%s\n' '$src_line' >> '$bashrc'"
    print_success "bash will auto-load git.sh (${GIT_SH})"
else
    print_warning "git.sh not found next to install.sh - skipping shell integration"
fi

# Auto-reload bash so the new environment (and git.sh) is live right away. A
# script can't mutate its parent shell, so the closest thing is to exec a fresh
# login shell for the invoking user - it re-reads ~/.bashrc and thus sources
# git.sh. Only do this interactively so non-interactive/CI runs still return.
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != root ] && [ -t 0 ] && [ -t 1 ]; then
    print_info "Reloading bash so git.sh and the new tools are ready..."
    exec su - "$SUDO_USER"
else
    print_warning "Open a new shell (or 'source ${GIT_SH:-./git.sh}') to pick up the environment"
fi