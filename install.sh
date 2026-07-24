#!/bin/bash

# Install PHP (multiple versions + switcher), Composer, WP-CLI and Node on the host.
#
#   sudo ./install.sh                          # everything: PHP 8.3, default 8.3
#   sudo ./install.sh --versions 8.2 8.3 8.4   # only these (also: --versions=8.2,8.3)
#   sudo ./install.sh --default 8.2            # pick the default CLI version
#   sudo ./install.sh --no-composer --no-wp    # skip the extras
#   sudo ./install.sh --no-node                # skip Node/nvm
#   sudo ./install.sh --node-version 20        # install this Node major (default: --lts)
#   sudo ./install.sh --no-claude              # skip Claude Code, its MCPs and plugins
#   sudo ./install.sh --no-mcp                 # skip registering Claude MCP servers
#   sudo ./install.sh --no-plugins             # skip installing Claude plugins
#
# Component selectors: --php --composer --wp --node --claude --mcp --plugins
#
# On their own they install ONLY what they name, and reinstall it if it is
# already there. After --uninstall they remove only what they name.
#
#   sudo ./install.sh --claude                 # (re)install just the Claude CLI
#   sudo ./install.sh --mcp --plugins          # re-register MCPs, reinstall plugins
#   sudo ./install.sh --php 8.2 8.3            # only these PHP versions
#   sudo ./install.sh --uninstall --php 8.1 8.2 # uninstall selected PHP versions
#   sudo ./install.sh --uninstall --claude      # uninstall only Claude Code
#   sudo ./install.sh --uninstall               # uninstall everything managed here
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

PHP_VERSIONS="8.3"
DEFAULT_VERSION="8.3"
INSTALL_PHP=1
INSTALL_COMPOSER=1
INSTALL_WPCLI=1
INSTALL_NODE=1
NODE_VERSION="--lts"
INSTALL_CLAUDE=1
INSTALL_MCP=1
INSTALL_PLUGINS=1
UNINSTALL_PHP=0
UNINSTALL_COMPOSER=0
UNINSTALL_WPCLI=0
UNINSTALL_NODE=0
UNINSTALL_CLAUDE=0
UNINSTALL_MCP=0
UNINSTALL_PLUGINS=0
UNINSTALL_ALL=0

# Component selectors (--php, --claude, ...) mean "only these": which side they
# apply to depends on whether --uninstall came along.
SEL_PHP=0
SEL_COMPOSER=0
SEL_WPCLI=0
SEL_NODE=0
SEL_CLAUDE=0
SEL_MCP=0
SEL_PLUGINS=0
selector=0
# Picking a component explicitly means "(re)do this one", so the install steps
# that normally skip an already-present tool run anyway.
FORCE_REINSTALL=0

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
        --uninstall)        UNINSTALL_MODE=1 ;;
        --php)              SEL_PHP=1; selector=1 ;;
        --composer)         SEL_COMPOSER=1; selector=1 ;;
        --wp|--wpcli)       SEL_WPCLI=1; selector=1 ;;
        --node)             SEL_NODE=1; selector=1 ;;
        --claude)           SEL_CLAUDE=1; selector=1 ;;
        --mcp)              SEL_MCP=1; selector=1 ;;
        --plugins)          SEL_PLUGINS=1; selector=1 ;;
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
            # The header comment is the help text: everything from line 3 up to
            # the first non-comment line, so it can't drift out of range.
            awk 'NR > 2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
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

UNINSTALL_MODE="${UNINSTALL_MODE:-0}"

if [ "$UNINSTALL_MODE" -eq 1 ]; then
    if [ "$selector" -eq 0 ]; then
        # Bare --uninstall means everything this script manages
        UNINSTALL_ALL=1
        SEL_PHP=1; SEL_COMPOSER=1; SEL_WPCLI=1
        SEL_NODE=1; SEL_CLAUDE=1; SEL_MCP=1; SEL_PLUGINS=1
    fi
    UNINSTALL_PHP=$SEL_PHP
    UNINSTALL_COMPOSER=$SEL_COMPOSER
    UNINSTALL_WPCLI=$SEL_WPCLI
    UNINSTALL_NODE=$SEL_NODE
    UNINSTALL_CLAUDE=$SEL_CLAUDE
    UNINSTALL_MCP=$SEL_MCP
    UNINSTALL_PLUGINS=$SEL_PLUGINS
elif [ "$selector" -eq 1 ]; then
    # Install mode with selectors: only the named components, and they are
    # (re)installed rather than skipped as already-present. --no-* is redundant
    # here - anything not selected is off already.
    INSTALL_PHP=$SEL_PHP
    INSTALL_COMPOSER=$SEL_COMPOSER
    INSTALL_WPCLI=$SEL_WPCLI
    INSTALL_NODE=$SEL_NODE
    INSTALL_CLAUDE=$SEL_CLAUDE
    INSTALL_MCP=$SEL_MCP
    INSTALL_PLUGINS=$SEL_PLUGINS
    FORCE_REINSTALL=1
else
    # --no-claude means nothing Claude-related, MCP servers and plugins included
    if [ "$INSTALL_CLAUDE" -eq 0 ]; then
        INSTALL_MCP=0
        INSTALL_PLUGINS=0
    fi
fi

if [ -n "$picked_versions" ] && [ "$selector" -eq 1 ] && [ "$SEL_PHP" -eq 0 ]; then
    print_error "PHP versions require the --php selector"
    exit 1
fi

for version in $PHP_VERSIONS; do
    case "$version" in
        [0-9].[0-9]|[0-9].[0-9][0-9]) ;;
        *) print_error "invalid PHP version: $version"; exit 1 ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run with sudo"
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    print_error "This installer targets Debian/Ubuntu (apt-get not found)"
    exit 1
fi

TOOL_USER="${SUDO_USER:-root}"
TOOL_HOME="$(getent passwd "$TOOL_USER" | cut -d: -f6)"
TOOL_HOME="${TOOL_HOME:-$HOME}"
run_as_user() { su - "$TOOL_USER" -c "$1"; }

# --------------------------------------------------------------- uninstall PHP

if [ "$UNINSTALL_MODE" -eq 1 ]; then
    if [ "$UNINSTALL_PLUGINS" -eq 1 ]; then
        print_info "Uninstalling Claude plugins..."
        for id in \
            figma@claude-plugins-official \
            skill-creator@claude-plugins-official \
            chrome-devtools-mcp@chrome-devtools-plugins \
            impeccable@impeccable; do
            run_as_user "claude plugin uninstall '$id' >/dev/null 2>&1" || true
        done
        print_success "Claude plugins uninstalled"
    fi

    if [ "$UNINSTALL_MCP" -eq 1 ]; then
        print_info "Unregistering Claude MCP servers..."
        run_as_user "claude mcp remove -s user figma >/dev/null 2>&1" || true
        run_as_user "claude mcp remove -s user chrome-devtools >/dev/null 2>&1" || true
        print_success "Claude MCP servers unregistered"
    fi

    if [ "$UNINSTALL_PHP" -eq 1 ]; then
        if [ -z "$picked_versions" ]; then
            PHP_VERSIONS="$(dpkg-query -W -f='${Package}\n' 'php[0-9].[0-9]-cli' 2>/dev/null \
                | sed -n 's/^php\([0-9][0-9]*\.[0-9][0-9]*\)-cli$/\1/p' | sort -Vu)"
        fi

        if [ -z "$PHP_VERSIONS" ]; then
            print_warning "No PHP versions are installed"
        fi

    for version in $PHP_VERSIONS; do
        print_info "Uninstalling PHP ${version}..."
        pkgs="$(dpkg-query -W -f='${Package}\n' 2>/dev/null | awk -v prefix="php${version}" '
            $0 == prefix || index($0, prefix "-") == 1
        ')"

        if [ -z "$pkgs" ]; then
            print_warning "PHP ${version} is not installed - skipping"
            continue
        fi

        # shellcheck disable=SC2086
        apt-get purge -y -qq $pkgs >/dev/null
        print_success "PHP ${version} uninstalled"
    done

    remaining="$(ls -1 /usr/bin/php[0-9].[0-9] 2>/dev/null | sed 's#.*/php##' | sort -V)"
    if [ -n "$remaining" ]; then
        fallback="$(printf '%s\n' "$remaining" | tail -1)"
        if [ -x /usr/local/bin/phpsw ]; then
            print_info "Switching the default to remaining PHP ${fallback}..."
            /usr/local/bin/phpsw "$fallback"
        fi
        print_info "Remaining PHP versions: $(printf '%s\n' "$remaining" | tr '\n' ' ')"
    else
        print_warning "No PHP versions remain installed"
    fi
    fi

    if [ "$UNINSTALL_COMPOSER" -eq 1 ]; then
        print_info "Uninstalling Composer..."
        rm -f /usr/local/bin/composer /etc/profile.d/composer.sh
        print_success "Composer uninstalled"
    fi

    if [ "$UNINSTALL_WPCLI" -eq 1 ]; then
        print_info "Uninstalling WP-CLI..."
        rm -f /usr/local/bin/wp /usr/local/bin/wp-cli.phar
        print_success "WP-CLI uninstalled"
    fi

    if [ "$UNINSTALL_NODE" -eq 1 ]; then
        print_info "Uninstalling Node and nvm for ${TOOL_USER}..."
        rm -rf "${TOOL_HOME}/.nvm"
        print_success "Node and nvm uninstalled"
    fi

    if [ "$UNINSTALL_CLAUDE" -eq 1 ]; then
        print_info "Uninstalling Claude Code for ${TOOL_USER}..."
        if run_as_user 'command -v claude >/dev/null 2>&1'; then
            run_as_user 'claude uninstall >/dev/null 2>&1' || print_warning "Claude uninstall command failed"
        else
            print_warning "Claude Code is not installed"
        fi
        print_success "Claude Code uninstall finished"
    fi

    if [ "$UNINSTALL_ALL" -eq 1 ]; then
        rm -f /usr/local/bin/phpsw
        print_success "phpsw uninstalled"
    fi

    print_success "Uninstall complete"
    exit 0
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

# The full prerequisite set is only needed by the apt-installed components.
# Selecting just a per-user tool (--claude, --node, ...) shouldn't drag an apt
# update along - those installers only need curl.
if [ $INSTALL_PHP -eq 1 ] || [ $INSTALL_COMPOSER -eq 1 ] || [ $INSTALL_WPCLI -eq 1 ]; then
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
elif ! command -v curl >/dev/null 2>&1; then
    print_info "Installing curl..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl >/dev/null
    print_success "curl installed"
fi

if [ $INSTALL_PHP -eq 1 ]; then
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
fi

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

if [ $INSTALL_PHP -eq 1 ]; then
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
fi

# ---------------------------------------------------------------- php switcher

# phpsw only makes sense next to the PHP builds, so it follows the same gate.
# The heredoc below is left unindented on purpose - it is the script's source.
if [ $INSTALL_PHP -eq 1 ]; then

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

fi

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
    # Asked for --claude explicitly? Run the installer over the top - it updates
    # in place, and "already present" is not what was asked for.
    if [ $FORCE_REINSTALL -eq 0 ] && run_as_user 'command -v claude >/dev/null 2>&1'; then
        print_info "Claude CLI already present for ${TOOL_USER}"
    else
        run_as_user 'curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1' \
            && print_success "Claude CLI installed for ${TOOL_USER}" \
            || print_warning "Claude CLI install failed for ${TOOL_USER}"
    fi
fi

# ------------------------------------------------------------------ claude mcps

if [ $INSTALL_MCP -eq 1 ]; then
    if run_as_user 'command -v claude >/dev/null 2>&1'; then
        print_info "Registering Claude MCP servers..."

        # $1 = server name (idempotency check + message), $2 = `claude mcp add`
        # argument string, $3 = flag the registration must already carry. User
        # scope so the servers are available in every repo. An older
        # registration missing $3 is replaced instead of left as it is - that is
        # the only way the flag reaches a machine installed before it existed.
        claude_mcp_add() {
            local name="$1" args="$2" want="$3"
            if run_as_user "claude mcp get '$name' >/dev/null 2>&1"; then
                if [ $FORCE_REINSTALL -eq 1 ]; then
                    print_info "re-registering MCP ${name}"
                elif [ -z "$want" ] || run_as_user "claude mcp get '$name' 2>/dev/null | grep -qF -- '$want'"; then
                    print_info "MCP ${name} already registered"
                    return 0
                else
                    print_info "MCP ${name} registered without ${want} - re-registering"
                fi
                run_as_user "claude mcp remove -s user '$name' >/dev/null 2>&1" || true
            fi
            if run_as_user "claude mcp add ${args} >/dev/null 2>&1"; then
                print_success "MCP ${name} registered"
            else
                print_warning "MCP ${name} registration failed"
            fi
        }

        claude_mcp_add figma "-s user --transport http figma https://mcp.figma.com/mcp"
        # --autoConnect attaches to the Chrome the user already has open (needs
        # Chrome 144+) instead of launching a second, empty profile with none of
        # their logins. Chrome side is a one-time toggle:
        # chrome://inspect/#remote-debugging.
        claude_mcp_add chrome-devtools \
            "-s user chrome-devtools -- npx chrome-devtools-mcp@latest --autoConnect" \
            "--autoConnect"
    else
        print_warning "Claude CLI not available - skipping MCP registration"
    fi
fi

# --------------------------------------------------------------- claude plugins

if [ $INSTALL_PLUGINS -eq 1 ]; then
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
                if [ $FORCE_REINSTALL -eq 0 ]; then
                    print_info "plugin ${id} already installed"
                    return 0
                fi
                print_info "reinstalling plugin ${id}"
                run_as_user "claude plugin uninstall '$id' >/dev/null 2>&1" || true
            fi
            if run_as_user "timeout 180 claude plugin install '$id' -s user >/dev/null 2>&1"; then
                print_success "plugin ${id} installed"
            else
                print_warning "plugin ${id} install failed"
            fi
        }

        claude_mkt_add impeccable pbakaus/impeccable

        print_info "Installing Claude plugins..."
        claude_plugin_add figma@claude-plugins-official
        claude_plugin_add skill-creator@claude-plugins-official
        claude_plugin_add impeccable@impeccable

        # Deliberately NOT chrome-devtools-mcp@chrome-devtools-plugins: the
        # plugin registers its own `chrome-devtools` server hardcoded to
        # `npx chrome-devtools-mcp@1.6.0` with no flags, so any call routed to
        # its tools launches a fresh Chrome profile and defeats the
        # --autoConnect registration above. One server, one behaviour.
        #
        # Earlier versions of this script did install it, so take it back out -
        # left alone it keeps shadowing the registered server on every upgrade.
        if run_as_user "claude plugin list 2>/dev/null | grep -qF 'chrome-devtools-mcp@chrome-devtools-plugins'"; then
            print_info "Removing the duplicate chrome-devtools-mcp plugin..."
            run_as_user "claude plugin uninstall chrome-devtools-mcp@chrome-devtools-plugins >/dev/null 2>&1" \
                && print_success "chrome-devtools-mcp plugin removed" \
                || print_warning "chrome-devtools-mcp plugin removal failed"
            run_as_user "claude plugin marketplace remove chrome-devtools-plugins >/dev/null 2>&1" || true
        fi

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
# Report only what this run touched, and only with `if` - under `set -e` a
# trailing "[ test ] && echo" that tests false ends the script right here,
# before the shell integration below ever runs.
if [ $INSTALL_PHP -eq 1 ]; then
    echo "  php       $(php -v 2>/dev/null | head -1)"
fi
if [ $INSTALL_COMPOSER -eq 1 ]; then
    echo "  composer  $(COMPOSER_ALLOW_SUPERUSER=1 composer --version --no-ansi 2>/dev/null | head -1)"
fi
if [ $INSTALL_WPCLI -eq 1 ]; then
    echo "  wp        $(wp --version 2>/dev/null | head -1)"
fi
if [ $INSTALL_NODE -eq 1 ]; then
    node_ver="$(su - "${SUDO_USER:-root}" -c 'export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh" 2>/dev/null; node --version' 2>/dev/null | tail -1)"
    if [ -n "$node_ver" ]; then
        echo "  node      ${node_ver} (via nvm)"
    fi
fi
if [ $INSTALL_CLAUDE -eq 1 ]; then
    claude_ver="$(su - "${SUDO_USER:-root}" -c 'command -v claude >/dev/null 2>&1 && claude --version' 2>/dev/null | tail -1)"
    if [ -n "$claude_ver" ]; then
        echo "  claude    ${claude_ver}"
    fi
fi
echo ""
if [ $INSTALL_PHP -eq 1 ]; then
    echo "  installed: $(ls -1 /usr/bin/php[0-9].[0-9] 2>/dev/null | sed 's#.*/php##' | sort -V | tr '\n' ' ')"
    echo "  switch:    phpsw <version>"
fi
if [ $INSTALL_NODE -eq 1 ]; then
    echo "  node:      nvm use <version>"
fi
echo ""

# --autoConnect attaches through the debugging port Chrome opens when remote
# debugging is switched on. With it off the server silently opens an empty
# profile instead of the user's, so say so here - this run is the only place the
# person installing it will look.
if [ $INSTALL_MCP -eq 1 ] && run_as_user 'command -v claude >/dev/null 2>&1'; then
    # Chrome leaves DevToolsActivePort behind when debugging is switched off
    # again, so the file proves nothing on its own - read the port out of it and
    # ask whether anything is actually listening. google-chrome is only the
    # stable channel; whichever Chrome the user runs is the one that matters.
    chrome_dbg_state="none"
    chrome_dbg_where=""
    for dir in google-chrome google-chrome-beta google-chrome-unstable chromium; do
        port_file="${TOOL_HOME}/.config/${dir}/DevToolsActivePort"
        [ -f "$port_file" ] || continue
        chrome_dbg_where="~/.config/${dir}"
        port="$(head -1 "$port_file" 2>/dev/null)"
        if [ -n "$port" ] && curl -sf --max-time 3 "http://127.0.0.1:${port}/json/version" >/dev/null 2>&1; then
            chrome_dbg_state="live"
            chrome_dbg_where="${chrome_dbg_where} (port ${port})"
            break
        fi
        chrome_dbg_state="stale"
    done

    if [ "$chrome_dbg_state" = "live" ]; then
        print_success "Chrome remote debugging is on ${chrome_dbg_where} - the chrome-devtools MCP will drive your open browser"
    else
        if [ "$chrome_dbg_state" = "stale" ]; then
            print_warning "Chrome remote debugging is OFF (${chrome_dbg_where} has a stale DevToolsActivePort, nothing listening)"
        else
            print_warning "Chrome remote debugging has never been enabled for ${TOOL_USER}"
        fi
        echo "    Turn it on in Chrome, as ${TOOL_USER}:"
        echo "      1. open   chrome://inspect/#remote-debugging    (needs Chrome 144+)"
        echo "      2. enable remote debugging, then restart Chrome"
        echo "      3. restart your agent session so the MCP server reconnects"
        echo ""
        echo "    Until then the server cannot attach to your profile and opens an"
        echo "    empty one instead - your logins and tabs won't be there."
        echo "    Relaunching Chrome with --remote-debugging-port is not a way"
        echo "    around it: that flag is ignored on the default user data dir"
        echo "    since Chrome 136."
    fi
    echo ""
fi

# ------------------------------------------------------------ shell integration

# Make bash load commands.sh (git.sh + llm.sh, and the reload-on-change hook)
# in future sessions. The repo is resolved from this script's own location, and
# the line is written to the invoking user's ~/.bashrc - so it works wherever
# the checkout lives and for whoever ran sudo, not a fixed path.
INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMANDS_SH="${INFRA_DIR}/commands.sh"
GIT_SH="${INFRA_DIR}/git.sh"
if [ -f "$COMMANDS_SH" ]; then
    src_line="[ -f \"$COMMANDS_SH\" ] && source \"$COMMANDS_SH\""
    bashrc="${TOOL_HOME}/.bashrc"
    # An earlier install wrote a git.sh line. Replace it rather than leaving
    # both: sourcing git.sh as well works, but skips the reload hook and makes
    # it look like two different setups are wired.
    run_as_user "touch '$bashrc'
        if grep -qF '$COMMANDS_SH' '$bashrc' 2>/dev/null; then
            :
        elif grep -qF '$GIT_SH' '$bashrc' 2>/dev/null; then
            tmp=\$(mktemp) && grep -vF '$GIT_SH' '$bashrc' > \"\$tmp\" \
                && printf '%s\n' '$src_line' >> \"\$tmp\" && mv \"\$tmp\" '$bashrc'
        else
            printf '%s\n' '$src_line' >> '$bashrc'
        fi"
    if run_as_user "grep -qF '$GIT_SH' '$bashrc' 2>/dev/null"; then
        print_warning "a git.sh line is still in ~/.bashrc - remove it, commands.sh loads git.sh itself"
    else
        print_success "bash will auto-load commands.sh (${COMMANDS_SH})"
    fi
elif [ -f "$GIT_SH" ]; then
    src_line="[ -f \"$GIT_SH\" ] && source \"$GIT_SH\""
    bashrc="${TOOL_HOME}/.bashrc"
    run_as_user "touch '$bashrc'; grep -qF '$GIT_SH' '$bashrc' 2>/dev/null || printf '%s\n' '$src_line' >> '$bashrc'"
    print_success "bash will auto-load git.sh (${GIT_SH})"
else
    print_warning "no commands.sh or git.sh next to install.sh - skipping shell integration"
fi

# Auto-reload bash so the new environment is live right away. A script can't
# mutate its parent shell, so the closest thing is to exec a fresh login shell
# for the invoking user - it re-reads ~/.bashrc and thus sources commands.sh.
# Only do this interactively so non-interactive/CI runs still return.
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != root ] && [ -t 0 ] && [ -t 1 ]; then
    print_info "Reloading bash so the shell helpers and new tools are ready..."
    exec su - "$SUDO_USER"
else
    print_warning "Open a new shell (or 'source ${COMMANDS_SH:-./commands.sh}') to pick up the environment"
fi
