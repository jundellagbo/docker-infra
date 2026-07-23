# Docker Development Environment

A complete local development stack with Nginx, Apache, PHP, MySQL, PostgreSQL, Redis, Adminer, and MailHog.

## Features

- **Nginx** - Reverse proxy with wildcard SSL for `*.dev.local` (ports 80/443)
- **Automatic virtual hosts** - `<name>.dev.local` maps to `www/<name>.dev.local/public`
- **Wildcard Docker DNS** - All `*.dev.local` names resolve to Nginx inside the stack
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

Optionally change the host directories in `.env` before starting:

```dotenv
WWW_PATH=./www
NGINX_PATH=./nginx
```

Both relative paths (resolved from the repository directory) and absolute paths are supported.

```bash
docker compose up -d
```

### 4. Configure Host DNS

Every container in this Compose stack resolves `*.dev.local` automatically. Host
applications such as browsers still need host-level DNS configuration.

On Linux hosts with systemd-resolved, install the persistent wildcard resolver:

```bash
sudo ./scripts/setup-host-dns.sh
```

This configures `*.dev.local` to resolve to `127.0.0.1` after restarts, so new
automatic virtual hosts do not need individual hosts-file entries.

If you are using another host OS, individual entries can be used as a fallback
because hosts files do not support wildcards:

```
127.0.0.1 dev.local
127.0.0.1 mysite.dev.local
127.0.0.1 api.dev.local
```

### 5. Create a Project

Create a project with the helper:

```bash
./scripts/project-create.sh mysite
```

Visit https://mysite.dev.local

## Host Development Tools (`install.sh`)

On Debian or Ubuntu, `install.sh` can install multiple host PHP versions along
with Composer, WP-CLI, Node through nvm, Claude Code, and the configured Claude
MCP servers and plugins:

```bash
# Install PHP 7.4-8.4 and all tools; PHP 8.3 is the default
sudo ./install.sh

# Install only the listed PHP versions and make PHP 8.2 the default
sudo ./install.sh --versions 8.1 8.2 8.3 --default 8.2

# Comma-separated versions are also accepted
sudo ./install.sh --versions=8.2,8.3,8.4
```

Optional install flags include `--no-composer`, `--no-wp`, `--no-node`,
`--no-claude`, `--no-mcp`, and `--no-plugins`. Use `--node-version 20` to
install a specific Node major instead of the latest LTS release.

Use `phpsw` after installation to list or change the active host PHP CLI and
FPM version:

```bash
phpsw
sudo phpsw 8.2
```

### Uninstalling Host Tools

Pass one or more component selectors after `--uninstall`. PHP accepts an
optional list of versions; without versions, `--php` removes every installed
PHP version detected by the script.

```bash
# Remove selected PHP versions
sudo ./install.sh --uninstall --php 8.1 8.2

# Remove all installed PHP versions
sudo ./install.sh --uninstall --php

# Remove one or more non-PHP components
sudo ./install.sh --uninstall --claude
sudo ./install.sh --uninstall --composer --wp --node
sudo ./install.sh --uninstall --mcp --plugins

# Remove every component managed by install.sh
sudo ./install.sh --uninstall
```

Available selectors are `--php`, `--composer`, `--wp` (or `--wpcli`),
`--node`, `--claude`, `--mcp`, and `--plugins`. Selectors may be combined in a
single command. Removing Node also removes nvm and its installed Node versions
for the user who invoked `sudo`. A full uninstall additionally removes the
`phpsw` helper.

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
- SQL imports support files up to 128 MB. After changing `docker/adminer/.user.ini`, recreate Adminer with `docker compose up -d --force-recreate adminer`.

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
├── nginx/                 # Default NGINX_PATH; Nginx virtual host configs
├── www/                   # Default WWW_PATH; web projects
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

## Automatic Virtual Hosts

Any directory named `www/<name>.dev.local/public` is served automatically at
`https://<name>.dev.local`. No Nginx config or reload is required:

```bash
./scripts/project-create.sh myproject
```

Files in `NGINX_PATH` can still define explicit `server_name` virtual hosts when a
project needs custom routing. Exact server names take precedence over the automatic
wildcard virtual host.

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

## Agent / LLM Workflow (`llm.sh`)

`git.sh` sources `llm.sh`, which ships the shared agent workflow — plan
protocol, step-by-step stop hooks, session records, the git guard and the vexp
search guard. The hooks live **only here**, in `llm/hooks/`; a project never
gets a copy of them. `infra-llm --init` just wires that project's hook config to
call the `infra-llm` command and appends an instruction block to the project's
own `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`.

```bash
infra-llm --init           # detect the repo's LLM setups, choose, wire up
infra-llm --status         # cli, wiring, docs, active plan, git guard, sessions
infra-llm --doctor         # can this machine run it? (Linux / macOS / WSL)
infra-llm --plan <slug>    # create plans/<slug>.md and register it
infra-llm --steps          # what the stop hook thinks the next step is
infra-llm --verify         # run this repo's checks and close out the plan
infra-llm --code-review    # review brief + scope of the recent changes
infra-llm --pull-request   # PR brief + branch, commits, existing PR
infra-llm --create-release # release brief + tags, releases, commits since
infra-llm --worktrees      # every worktree with its own plan state
infra-llm --sessions       # list/print .claude/sessions records
infra-llm --skill <n>      # print a protocol skill (step-plan, llm-workflow)
infra-llm --docs           # refresh the instruction blocks after editing infra
infra-llm --uninstall      # remove the wiring and the instruction blocks
```

`--init` looks for every LLM setup it knows — Claude Code, Codex, Cursor,
Windsurf, GitHub Copilot, Gemini, Cline/Roo, Aider — pre-selects the ones the
repo already shows signs of, and still offers the rest so a repo can adopt one
it doesn't use yet. Non-interactive: `--claude --codex --cursor --windsurf
--copilot --gemini --cline --aider`, `--all`, `--yes`.

Claude and Codex are the only two with a hook API; every other agent gets the
instruction block only, written where that tool actually reads it
(`.cursor/rules/infra-llm.mdc` with `alwaysApply` frontmatter,
`.windsurf/rules/infra-llm.md` with `trigger: always_on`,
`.github/copilot-instructions.md`, `.clinerules/infra-llm.md`,
`CONVENTIONS.md`, `GEMINI.md`) — following the legacy location
(`.cursorrules`, `.windsurfrules`, `.clinerules` file) when the repo already
uses it.

What it touches in the target repo:

| Path                    | What                                                          |
| ----------------------- | ------------------------------------------------------------- |
| `.claude/settings.json` | hook entries calling `infra-llm --hook prompt/stop/session/git-guard/vexp` (merged, existing hooks kept) |
| `.claude/commands/infra-llm.md` | one generated slash command, `/infra-llm <what>` (skip with `--no-commands`) |
| `.codex/hooks.json`     | `infra-llm --hook prompt` + `--hook codex-stop`                |
| each selected agent's instruction file | protocol instructions between `<!-- infra-llm:start -->` markers |
| `plans/`                | plan files + `.active-plan` marker (git-ignored)               |
| `.claude/sessions/`     | one `<session-id>.md` per session (last 10), git-ignored       |
| `.infra-llm.env`        | the repo's settings — `VERIFY_CMD`, git-guard mode — written commented-out, git-ignored |

Skip a guard at wiring time with `--no-git-guard` or `--no-vexp`.

Hooks run in a non-interactive shell, so `--init` also installs a launcher at
`~/.local/bin/infra-llm` (override with `LLM_BIN_DIR`). Every wired command is
guarded with `command -v infra-llm` and fails open, so a checkout on a machine
without this repo is never blocked.

### Git guard, pull requests and releases

Git state is the **user's** decision. The `PreToolUse(Bash)` git guard denies
agent-run `git commit` / `push` / `merge` / `rebase` / `reset` / `tag` /
`stash` / `checkout` …; read-only git passes straight through, and non-git
commands get no decision at all, so normal permission behaviour is untouched.

Tune it per repo in `.infra-llm.env` (git-ignored, written by `--init`):

```bash
GIT_GUARD=deny              # default — "ask" prompts the user, "off" disables
GIT_GUARD_ALLOW="tag stash" # subcommands this repo lets through
```

Destructive commands (force push, `reset --hard`, `clean -fd`, history
rewriting, `branch -D`, discarding working-tree changes) stay denied in `deny`
and `ask` mode and can't be allow-listed — only `off` silences them.

For the git work the agent *should* help with, `infra-llm --pull-request` and
`infra-llm --create-release` mirror `--code-review`: a short brief plus the
repo's real state (branch vs. base, uncommitted changes, commits ahead, an
existing PR, tags, releases, where the version is declared). Both say: don't
duplicate an existing one, verify first, then prepare the message/body/notes and
hand the commands to the user — never AI attribution, never a direct push.

Releases are tagged `vMAJOR.MINOR.PATCH` — `v1.0.1` bug fix, `v1.1.0` feature,
`v2.0.0` breaking — and `--create-release` prints the three candidates computed
from the previous tag so the bump is a decision, not an invention.

### Adopting it in a repo that already has its own workflow

`plans/adopt-infra-llm.md` is a ready-to-run plan (a local, untracked file —
`plans/` is git-ignored). Copy it into the target repo's `plans/` and have that
repo's own agent work through it: inventory its hooks, commands, rules and
instruction files, decide what infra-llm already covers, and remove only that —
keeping whatever is genuinely project-specific.

### Slash commands

Claude Code only offers a project command if a file for it exists, so `--init`
writes exactly **one**: `/infra-llm <what>`. A project repo gets a single file,
not a command per feature, and everything stays reachable:

```
/infra-llm review      /infra-llm plan <slug>    /infra-llm status
/infra-llm pr          /infra-llm steps          /infra-llm sessions
/infra-llm release     /infra-llm verify         /infra-llm worktrees
                                                 /infra-llm doctor
```

The file only points at the CLI — the briefs stay in the infra checkout, so
there is nothing to keep in sync. `infra-llm --init --no-commands` generates
nothing at all for repos that would rather use the CLI directly; a command file
the repo wrote itself is never overwritten; `--uninstall` removes only the
generated one. The same words work bare in a terminal: `infra-llm pr`,
`infra-llm review`, `infra-llm doctor`.

If a terminal reports `unknown command`, the shell is running an `infra-llm`
function it sourced before that command existed — `source <infra>/git.sh` (or a
new shell) fixes it, and `infra-llm --doctor` detects it.

### Environments

Linux, macOS and Windows via WSL are all supported. Every script is pinned to
`#!/bin/bash`, which exists on all three, so the interpreter is predictable —
and because that is bash 3.2 on macOS, nothing here uses bash 4 syntax. The
scripts also stay inside what a stock BSD userland provides: no `md5sum`, no
argument-less `mktemp`, no GNU-only flags. `.gitattributes` forces LF endings
so a Windows checkout can't hand the hooks a `\r` in the shebang, and the hooks
strip carriage returns from the settings and plan files anyway.

`infra-llm --doctor` checks a machine in one command: OS and bash version, every
tool the hooks shell out to, the version of `/bin/bash` the shebangs point at,
whether the launcher is on PATH, CRLF or syntax damage in the hook scripts, and
a live run of each hook in a scratch directory.
It exits non-zero when something is actually broken.

Only `git` and the usual POSIX text tools are required. `jq` is optional (no
session records without it, and the guards fall back to plain text matching);
`gh` is optional (PR and release commands can't see existing PRs/releases).

### Worktrees

Wiring is tracked, so every worktree of a wired repo is wired. State is not:
each worktree keeps its own `plans/`, `.active-plan` and `.claude/sessions/`, so
one agent per worktree can run in parallel without colliding. `gwtadd` prepares
a new worktree automatically (creates the state dirs, carries `.infra-llm.env`
over from the main checkout); `infra-llm --worktrees` shows what each worktree
is working on:

```
WORKTREE                 BRANCH                 PLAN                               SESSIONS
*infra                   master                 2 left: wire up the status table   3
 feature-login           feature/login          verify pending                     1
```

Short aliases when the shell has sourced `git.sh`: `llminit`, `llmdocs`,
`llmstatus`, `llmplan`, `llmsteps`, `llmverify`, `llmreview`, `llmpr`,
`llmrelease`, `llmsessions`, `llmskill`, `llmwt`, and
`claude_session` (runs `claude` after making sure session recording is wired up
in the current directory).
