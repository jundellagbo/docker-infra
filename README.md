# Development Infrastructure

**A planning harness for Claude Code and other agent LLMs** — plus the local
infrastructure it runs against.

Point an agent at a task and it starts typing. This makes it write the plan
first: every discrete item as a checkbox in a file you can read and correct,
then one step per turn, ticked off as it goes. You review the plan while it is
still a paragraph, not after it has become a diff. Wire it once and it applies
to every repository on the machine — nothing is checked into your projects.

```
you:    "add rate limiting to the API"
agent:  writes infra-llm/plans/rate-limiting.md — 6 checkboxes
you:    "drop 4, the cache already handles that"
agent:  implements step 1, ticks it, stops. The stop hook feeds it step 2…
```

It also stops an agent from committing your work, records what each session was
asked to do, and ships the skills that make Claude Code follow all of it.

Three parts, independent of each other — use one, two, or all three:

| Part | What it is | Entry point |
| ---- | ---------- | ----------- |
| **Docker stack** | Nginx, Apache, PHP 7.4-8.4, MySQL, PostgreSQL, Redis, Adminer, MailHog, wildcard SSL and DNS for `*.dev.local` | `docker compose up -d` |
| **Host tooling** | Multiple host PHP versions + switcher, Composer, WP-CLI, Node via nvm, Claude Code, its MCP servers and plugins | `sudo ./install.sh` |
| **Agent workflow** | The planning harness: plan protocol, one-step-per-turn stop hooks, verification gate, session records, git and search guards, and the Claude Code skills that drive them | `infra-llm --global` |

```bash
source /path/to/infra/commands.sh   # shell helpers: git shortcuts + infra-llm
infra-llm --global                  # wire the planning harness, machine-wide
docker compose up -d                # start the stack
```

Use it for: agent-driven development in any language, keeping a long task on
track across sessions, reviewing an agent's intent before its output, and
running a PHP/WordPress stack locally without installing any of it on the host.

## Contents

- [Quick Start](#quick-start) — the Docker stack
- [Host Development Tools](#host-development-tools-installsh) — PHP, Composer, Node, Claude Code
- [Chrome DevTools MCP](#chrome-devtools-mcp--use-your-own-browser) — agents driving your real browser
- [Database Credentials](#database-credentials) · [Docker Commands](#docker-commands) · [Service URLs](#service-urls)
- [Troubleshooting](#troubleshooting)
- **Agent / LLM workflow**
  - [Shell Entry Point (`commands.sh`)](#shell-entry-point-commandssh)
  - [How to Use with Claude Code](#how-to-use-with-claude-code) — start here
  - [Manual setup you have to do yourself](#5-manual-setup--the-parts-only-you-can-do) — Chrome debugging, DNS, certs
  - [Why plan first](#why-plan-first) — what each rule prevents
  - [Does it save tokens?](#does-it-save-tokens) — the honest accounting
  - [Agent / LLM Workflow](#agent--llm-workflow-llmsh) — what it does and why
  - [Three Commands, Three Scopes](#three-commands-three-scopes) — `--init` / `--agent` / `--global`
  - [Wire the Whole Machine Once](#wire-the-whole-machine-once---global)
  - [Git guard, pull requests and releases](#git-guard-pull-requests-and-releases)

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
- **Agent workflow** - One plan per task, one step per turn, session records, git guard

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

### Installing or Reinstalling One Component

The same component selectors work without `--uninstall`. On their own they
install **only** what they name, and a component that is already there is
reinstalled rather than skipped — so this is also how you refresh one tool
without touching PHP or the rest of the box:

```bash
# Reinstall just the Claude Code CLI
sudo ./install.sh --claude

# Re-register the MCP servers and reinstall the plugins
sudo ./install.sh --mcp --plugins

# Add PHP 8.2 and 8.3 only
sudo ./install.sh --php 8.2 8.3
```

Selectors: `--php`, `--composer`, `--wp`, `--node`, `--claude`, `--mcp`,
`--plugins`. Anything not named is skipped, apt included — a Claude-only run
does no `apt-get update` at all. PHP versions still need the `--php` selector,
so `sudo ./install.sh --claude 8.2` is rejected rather than quietly ignored.

### Chrome DevTools MCP — Use Your Own Browser

The `chrome-devtools` MCP server is registered with `--autoConnect` so agents
drive the Chrome you already have open, with your logged-in profile, instead of
launching a second empty one. A server registered by an earlier install without
the flag is re-registered on the next run.

**Enable remote debugging in Chrome once** (Chrome 144+), or none of it works:

1. Open `chrome://inspect/#remote-debugging`
2. Enable remote debugging, then restart Chrome
3. Restart the agent session so the MCP server reconnects

`--autoConnect` attaches through the `DevToolsActivePort` file Chrome writes into
its user data dir, and Chrome only writes that file when remote debugging is on.
With it off the server can't attach and quietly opens an empty profile instead —
the tell is an agent seeing a blank browser rather than your tabs.

The user data dir depends on the platform and the Chrome channel:

| Platform | Stable channel user data dir                        |
| -------- | --------------------------------------------------- |
| Linux    | `~/.config/google-chrome`                           |
| macOS    | `~/Library/Application Support/Google/Chrome`       |
| Windows  | `%LOCALAPPDATA%\Google\Chrome\User Data`            |

Other channels sit beside it — `google-chrome-beta`, `google-chrome-unstable`,
`chromium` on Linux, `Google/Chrome Beta` on macOS. `--autoConnect` follows the
stable channel unless the server is registered with `--channel beta|dev|canary`,
so enable remote debugging in whichever Chrome you actually browse with.

**Don't check for the file — check the port.** Chrome writes
`DevToolsActivePort` into the user data dir when debugging starts but leaves it
behind when you switch debugging off, so the file's presence is not evidence
that anything is listening. Ask the port instead:

```bash
port=$(head -1 ~/.config/google-chrome/DevToolsActivePort)   # Linux, stable
curl -sf "http://127.0.0.1:$port/json/version" && echo LIVE || echo OFF
```

`install.sh` runs the same probe after registering the MCP and reports which of
the three states you are in: live, stale file with nothing listening, or never
enabled.

This is a one-time setting: Chrome persists it as `devtools.remote_debugging`
in the `Local State` file of the same directory, so it survives Chrome
restarts — but it is a real toggle, and turning it off (or a Chrome that never
reopened its main window) puts you back in the stale-file state above.

There is no way to trigger the toggle from outside the browser — that is the
point of the gate. **`--remote-debugging-port` is not a way around it**: Chrome
has ignored that flag on the default user data dir since version 136, so
relaunching your own profile with it looks right and silently does nothing. A
separate `--user-data-dir` does accept the flag, but that profile has none of
your logins, which is the situation this whole setup exists to avoid.

There must be exactly one `chrome-devtools` server, which is why the
`chrome-devtools-mcp` Claude plugin is **not** installed and is removed if an
earlier run added it. The plugin hardcodes `npx chrome-devtools-mcp@1.6.0` with
no flags, so any tool call routed to its copy launches a fresh profile whatever
the registered server says. Check with:

```bash
claude mcp list | grep chrome
```

Use `phpsw` after installation to list or change the active host PHP CLI and
FPM version:

```bash
phpsw
sudo phpsw 8.2
```

### Uninstalling Host Tools

Pass the same component selectors after `--uninstall`. PHP accepts an
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

## Shell Entry Point (`commands.sh`)

`commands.sh` is the one file a shell sources. It loads `git.sh` (git
shortcuts, worktree helpers, the branch prompt) and `llm.sh` (the `infra-llm`
agent workflow), and `install.sh` writes it into `~/.bashrc`:

```bash
source /path/to/infra/commands.sh
```

**It reloads itself when the checkout changes.** Before each prompt it compares
the modification times of `git.sh` and `llm.sh`; if either moved, both are
re-sourced. Edit the checkout and the shell you are standing in is current on
the next prompt — no more shells running functions from before your last edit,
which is the stale copy `infra-llm --doctor` reports. Works in bash
(`PROMPT_COMMAND`) and zsh (`precmd`), and adds itself without displacing hooks
you already have.

`infra-reload` (alias `infrareload`) does it on demand — for a shell opened
before `commands.sh` existed, or a script where no prompt runs:

```bash
$ infra-reload
  reloaded /path/to/infra/git.sh
  reloaded /path/to/infra/llm.sh
infra-llm 2026-07-23.4
```

Sourcing `git.sh` directly still works and stays self-contained; it just misses
the reload hook.

## How to Use with Claude Code

Five minutes, once per machine. After this every repository you open in Claude
Code follows the same workflow, with nothing checked into the repo.

### 1. Load the shell helpers

```bash
source /path/to/infra/commands.sh
```

Add that line to `~/.bashrc` (or `~/.zshrc`) to make it permanent — `install.sh`
does it for you. It brings in the git shortcuts, the worktree helpers and the
`infra-llm` command, and re-sources itself whenever this checkout changes.

### 2. Wire the machine

```bash
infra-llm --global
```

Installs four things into Claude Code's own config directory
(`$CLAUDE_CONFIG_DIR`, else `~/.claude`), where they apply to **every** project:

| | |
| --- | --- |
| `CLAUDE.md` | the instruction block — how the agent is expected to work |
| `settings.json` | the hooks: step gate, verify gate, session records, git and search guards |
| `commands/infra-llm.md` | the `/infra-llm` slash command |
| `skills/` | `step-plan` and `llm-workflow`, loaded automatically when relevant |

Restart any Claude Code session that was already open — settings are read at
session start.

### 3. Prepare a repo (optional)

```bash
cd ~/code/my-project
infra-llm --init
```

Creates `infra-llm/` for plans and session records, `.infra-llm.env` for this
repo's settings, and the ignore entries that keep both out of git. Optional
because the hooks create what they need on demand — `--init` mainly buys you the
ignore rules and a place to set `VERIFY_CMD`.

### 4. Work

Ask for something with more than one step. What changes:

- the agent writes a **plan file** first — `infra-llm/plans/<slug>.md`, one
  `- [ ]` checkbox per discrete item;
- it implements **one step per turn**, ticks the box, and stops;
- the **stop hook** blocks that stop and feeds it the next step, so nothing is
  silently dropped and each turn stays small;
- when every box is ticked it runs `infra-llm --verify`, which runs this repo's
  `VERIFY_CMD` and clears the plan;
- it **cannot commit, push, merge or rebase** — the git guard denies those, and
  you decide when work gets committed;
- when the session ends, a record of what was asked lands in
  `infra-llm/sessions/`.

### 5. Manual setup — the parts only you can do

Everything else installs itself. These five need a human, and each one fails
*quietly* when skipped — do them now rather than wondering later why an agent is
screenshotting a browser you can't see.

**1. Chrome: enable remote debugging** — needed for any agent that opens,
inspects or screenshots a page.

```
chrome://inspect/#remote-debugging     →  enable, then restart Chrome
```

Chrome 144+ only. No process outside the browser can flip this — that is the
point of the gate. Skip it and the `chrome-devtools` MCP cannot attach to your
browser, so it silently opens an empty throwaway profile instead: the agent
screenshots a page you are not looking at, with none of your logins. It is a
one-time setting, persisted as `devtools.remote_debugging` in Chrome's
`Local State`, and it survives restarts. Verify:

```bash
port=$(head -1 ~/.config/google-chrome/DevToolsActivePort)   # Linux, stable channel
curl -sf "http://127.0.0.1:$port/json/version" && echo LIVE || echo OFF
```

Check the port, not the file — Chrome leaves `DevToolsActivePort` behind when
you switch debugging off. See
[Chrome DevTools MCP](#chrome-devtools-mcp--use-your-own-browser) for the
per-platform paths and why `--remote-debugging-port` is not a substitute.

**2. Restart Claude Code after `infra-llm --global`** — hooks and settings are
read at session start. A window opened beforehand keeps the old (empty) set, and
looks exactly like "the hooks don't work".

**3. The shell line in `~/.bashrc`** — `install.sh` writes it; if you skipped
the installer, add it yourself:

```bash
[ -f "$HOME/devops/infra/commands.sh" ] && source "$HOME/devops/infra/commands.sh"
```

Without it `infra-llm` still works (the launcher is on `PATH`), but you lose the
git shortcuts, the worktree helpers and reload-on-change.

**4. Trust the CA certificate** — for `https://*.dev.local` without browser
warnings. `./scripts/generate-ssl.sh` prints the instructions; on Windows see
[Installing CA Certificate](#installing-ca-certificate-in-windows).

**5. Host DNS for `*.dev.local`** — containers resolve it themselves, your
browser does not:

```bash
sudo ./scripts/setup-host-dns.sh     # Linux/systemd-resolved, survives reboots
```

On other systems add hosts-file entries per site — hosts files do not support
wildcards.

### Commands worth knowing on day one

```bash
infra-llm --status      # what's wired here, active plan, next step, git mode
infra-llm --steps       # the next unchecked step the stop hook will demand
infra-llm --plan <slug> # start a plan yourself
infra-llm --verify      # run the checks and close the plan out
infra-llm --doctor      # can this machine run it? what's installed where?
infra-llm --sessions    # what past sessions were asked to do
```

Inside Claude Code the same words work as `/infra-llm status`, `/infra-llm
review`, `/infra-llm pr`, and so on.

### If it doesn't seem to be working

| Symptom | Cause |
| ------- | ----- |
| No plan, no auto-continue | The session started before `--global`; settings load at session start, so restart it |
| Nothing happens on a one-line question | Correct — the protocol engages for multi-step work, or when a plan exists |
| `unknown command` from `infra-llm` | A shell holding an old copy: `infra-reload`, or open a new terminal |
| Auto-continue went quiet mid-plan | The stall guard hit its cap after three turns with no plan change — `infra-llm --doctor` says so, and a new session resets it |

`infra-llm --doctor` checks the lot: PATH, hook scripts, the machine-wide
install, and whether this shell is running a stale copy.

## Agent / LLM Workflow (`llm.sh`)

`git.sh` sources `llm.sh`, which ships the shared agent workflow — plan
protocol, step-by-step stop hooks, session records, the git guard and the vexp
search guard. The hooks live **only here**, in `llm/hooks/`; a project never
gets a copy of them. A project is only ever pointed at them — either through the
machine-wide install (`--global`) or through its own hook config (`--agent`),
both of which call the `infra-llm` command rather than vendoring anything. Fix a
hook here and every repo on the machine is fixed, with nothing to re-run.

### Why plan first

Each rule in the protocol exists because of a specific way agent work goes
wrong.

**The agent writes the plan before it writes code.**
*Prevents:* implementing an interpretation you never agreed to. A plan is a
list of one-line outcomes — cheap to read, cheap to argue with. Cutting a step
costs you a sentence; cutting a finished implementation costs a review, a
revert, and whatever it broke on the way.

**One step per turn.**
*Prevents:* the twelve-file reply where step 3 was wrong and everything after it
was built on step 3. Each turn is small enough to actually read, and the plan
file says exactly where it got to.

**The plan file is the state, not the conversation.**
*Prevents:* re-deriving the task from scratch every turn — the guessing that
happens when an agent has to reconstruct "what were we doing" from a long
transcript. It re-reads a checklist instead. This is also why the plan survives
a context compaction, a crash, or a session that ends at 2am.

**Steps are revised, never silently dropped.**
*Prevents:* the quiet omission. Something that turns out to be unnecessary is
marked `- [x] … (skipped: reason)`, so you find out it was skipped and why,
rather than noticing three weeks later that it never happened.

**A verification gate at the end.**
*Prevents:* "done" meaning "I stopped typing". The plan will not close until
`VERIFY_CMD` passes, so the last turn is a test run rather than a summary.

**Session records.**
*Prevents:* starting tomorrow by re-explaining yesterday. `infra-llm --sessions`
says what each session was asked to do; a new session reads the plan and picks
up mid-task.

**The git guard.**
*Prevents:* an agent committing, pushing or rebasing on your behalf. It leaves
the work in the tree and tells you what changed — you decide what lands, and
when.

### Does it save tokens?

Not directly — and it is worth being clear about that, because the honest
answer is more useful than the flattering one.

**What it costs.** Writing the plan is tokens you would not otherwise spend.
One step per turn means more turns, and each turn re-reads the plan file. On a
task the agent would have got right first time, this setup is strictly more
expensive.

**What it saves.** The expensive failure in agent work is not a long reply, it
is the *wrong* reply — an implementation built on a misread of the task, which
costs the tokens that produced it, the tokens spent reviewing it, and the
tokens spent undoing it. That is where the protocol pays:

| Without | With |
| ------- | ---- |
| Agent guesses the scope, implements 6 things, 2 were wanted | You cut 4 checkboxes before any of them are built |
| Wrong assumption surfaces in the diff, after the work | Wrong assumption surfaces in a one-line plan step, before it |
| Each turn re-derives "what are we doing" from the transcript | Each turn re-reads a checklist |
| Context compaction loses the task; you re-explain it | The plan file survives; the agent resumes from it |
| A new session starts from nothing | Session records say what the last one was asked to do |

Re-reading a short checklist is cheaper than re-deriving intent from a long
conversation, and it does not degrade as the conversation grows. That is the
mechanism, not a claim that planning is free.

**When it is not worth it.** A one-line fix, a question, a single file rename —
the protocol only engages for multi-step work, and you should not force a plan
onto something smaller. `infra-llm --plan` exists for when you want one anyway.

**What it definitely saves: your time.** A plan is reviewable in seconds. A
diff is not.

### What it actually does

Five mechanisms. Each is a hook Claude Code calls at a specific moment.

**The plan is the checklist.** Multi-step work goes into
`infra-llm/plans/<slug>.md` as `- [ ]` checkboxes — no separate progress file,
no status kept in the conversation. `infra-llm/plans/.active-plan` lists which
plan files are live. You see the file; so does the agent; they cannot disagree.

**One step per turn** (`Stop` hook). The agent implements one unchecked box,
ticks it, and stops. The hook blocks that stop and hands back the next step, so
the work advances in bounded turns instead of one sprawling reply, and a step
can't be silently dropped — an unneeded one is marked `- [x] … (skipped:
reason)`, not deleted. You see this as the agent continuing on its own, one
step at a time, until the plan is done.

**A stall guard behind it.** If three consecutive turns end with no change to
any plan file, the hook gives up and lets the session stop, so a stuck agent
can't loop forever. The counter is keyed to the session and the plan's contents:
tick a box and it resets, start a new session and it resets. `infra-llm
--doctor` reports a repo sitting at the cap.

**A verification gate** (`infra-llm --verify`). When every box is ticked, the
agent runs it; it runs this repo's `VERIFY_CMD` (from `.infra-llm.env`), checks
the container logs where relevant, and only then clears `.active-plan` so the
session may end. No `VERIFY_CMD` set means the gate still closes the plan, it
just has no project checks to run.

**Guards on the dangerous things** (`PreToolUse` hooks):

- *git guard* — the agent cannot commit, push, merge, rebase, reset, checkout,
  stash or rewrite history. It leaves work in the tree and tells you what
  changed; you decide when it lands. `--pull-request` and `--create-release`
  open a short, explicit window where committing and pushing are allowed;
  destructive commands stay denied throughout. Tune with `GIT_GUARD` in
  `.infra-llm.env`: `deny` (default), `ask`, or `off`.
- *search guard* — steers `Grep`/`Glob` toward the faster index when one is
  running, and gets out of the way when it isn't.

**Session records** (`SessionEnd` hook). Every session writes what it was asked
to do into `infra-llm/sessions/<session-id>.md`, last 10 kept. `infra-llm
--sessions` lists them — useful for "what was that other window doing?".

Instructions come from one template (`llm/templates/instructions.md`) rendered
into the machine-wide `CLAUDE.md` or each repo's own, between
`<!-- infra-llm:start -->` markers. Editing anything between those markers is
lost on the next refresh — change the template here instead, and `--global` or
`--init` updates the copies.

```bash
infra-llm --init           # this repo's state: plan dir, sessions, ignore rules
infra-llm --global         # wire every repo on this machine, once
infra-llm --agent          # wire THIS repo (hooks + instructions + command)
infra-llm --status         # cli, wiring, docs, active plan, git guard, sessions
infra-llm --doctor         # can this machine run it? (Linux / macOS / WSL)
infra-llm --plan <slug>    # create infra-llm/plans/<slug>.md and register it
infra-llm --steps          # what the stop hook thinks the next step is
infra-llm --verify         # run this repo's checks and close out the plan
infra-llm --code-review    # review brief + scope of the recent changes
infra-llm --pull-request   # PR brief + branch, commits, existing PR
infra-llm --create-release # release brief + tags, releases, commits since
infra-llm --worktrees      # every worktree with its own plan state
infra-llm --sessions       # list/print infra-llm/sessions records
infra-llm --skill <n>      # print a protocol skill (step-plan, llm-workflow)
infra-llm --docs           # refresh the instruction blocks after editing infra
infra-llm --uninstall      # remove the wiring and the instruction blocks
```

### Three Commands, Three Scopes

| Command | Scope | Installs |
| ------- | ----- | -------- |
| `--init` | this repo | `infra-llm/` (plans + sessions), `.infra-llm.env`, and the ignore entries for both |
| `--global` | this machine | hooks, instruction block, `/infra-llm`, workflow skills — every repo covered |
| `--agent` | this repo | the same wiring, but inside the repo itself |

`--init` is repo *state*, nothing more: no hooks, no instruction block, no
command. That is all a repo needs when the machine has a `--global` install —
and it is what makes the plan files and session records work in any checkout.

It also keeps that state out of everything that ships. Plan files and session
transcripts are machine-local scratch: in an image they are dead weight, and
they bust the build cache on every edit.

| File | When |
| ---- | ---- |
| `.gitignore` | created when missing — the workflow depends on it |
| `.dockerignore`, `.npmignore`, `.gcloudignore`, `.vercelignore`, `.prettierignore`, `.eslintignore` | **appended to only, never created** |

`--init` does not invent ignore files. A repo without a `.dockerignore` has
decided something by not having one, and a file it never asked for turning up
is not a fix for a problem it does not have. `.npmignore` is the one where
creating it would do real damage — npm falls back to `.gitignore` when the file
is absent, so a new `.npmignore` listing just our paths would start publishing
everything `.gitignore` was keeping out of the tarball. Write the file yourself
and the next `--init` will keep it up to date.

The `--init` summary lists which files ended up covered:

```
  ignored:  .gitignore .dockerignore .prettierignore
```

Reach for `--agent` when there is no machine-wide install, or when teammates and
CI clone the repo and must get the workflow along with it. It runs the `--init`
state prep first, so it stays a one-command setup.

`--agent` looks for every LLM setup it knows — Claude Code, Codex, Cursor,
Windsurf, GitHub Copilot, Gemini, Cline/Roo, Aider — pre-selects the ones the
repo already shows signs of, and still offers the rest so a repo can adopt one
it doesn't use yet. Non-interactive: `--claude --codex --cursor --windsurf
--copilot --gemini --cline --aider`, `--all`, `--yes`.

Re-running `--agent` after infra-llm itself changed brings the instruction block
up to date: it compares what sits between the `infra-llm` markers with the
current template and rewrites the block when they differ (`updated
instructions in <file>`), leaves it alone when they match (`current`), and never
touches the rest of the file. `--force` rewrites even a block that is already
current; `--docs` does the same for the blocks alone, without re-running the
rest of the wiring.

### Wire the Whole Machine Once (`--global`)

Running `--agent` in every repo, then again after every infra change, gets old.
`infra-llm --global` installs the entire workflow into Claude Code's own config
directory instead, where it applies to every project:

| Piece | Lands in | Effect |
| ----- | -------- | ------ |
| Instruction block | `CLAUDE.md` | the protocol, in every session |
| Hooks | `settings.json` | step gate, verify gate, session records, guards |
| `/infra-llm` command | `commands/infra-llm.md` | the slash command everywhere |
| `step-plan` skill | `skills/step-plan/SKILL.md` | loads at the start of multi-step work |
| `llm-workflow` skill | `skills/llm-workflow/SKILL.md` | loads when asked to wire a repo |

```bash
infra-llm --global                  # install or refresh all of it
infra-llm --global --designer       # ... plus the optional design-review skill
infra-llm --global --no-git-guard   # ... but leave git alone
infra-llm --global --no-hooks       # ... instructions, command and skills only
infra-llm --global --no-skill       # ... no skills at all
infra-llm --global --remove         # take all of it back out
```

`design-review` is deliberately **not** in that list. It pulls in impeccable,
the emilkowalski design skills and the chrome-devtools MCP — worth having where
you do front-end work, noise everywhere else. Install it per repo with
`infra-llm --designer`, or machine-wide with `--global --designer` if you want
it everywhere.

No repo needs `--agent` after that — just `--init` for its own state. Updating
this checkout updates every repo on the machine; the next session picks it up.

**Re-run it after every infra change; it's idempotent.** Each piece is compared
before it's touched — the block against the template, the hooks against what's
in `settings.json`, the command and skills byte-for-byte — and rewritten only
when it differs. A no-op run just prints `current` a few times, and anything you
added yourself (your own `CLAUDE.md` prose, your own hooks or skills) is left
alone. `--status` and `--doctor` name what's installed and mark anything stale.

> **Don't wire both layers.** Claude Code *merges* user-level and project-level
> hooks rather than letting one override the other, so a repo that also ran
> `--agent` fires every hook twice — two stop decisions, the protocol injected
> twice, guards reporting twice. Nothing breaks, but it's noise. `--status` and
> `--doctor` warn when they see it; `infra-llm --uninstall` in the repo drops
> back to one layer.

The config directory is `$CLAUDE_CONFIG_DIR` when set and `~/.claude` otherwise
— the same rule Claude Code follows — so this works unchanged on **Linux,
macOS, WSL and Git Bash on Windows**. (Native Windows without a bash can't run
these scripts at all; use WSL or Git Bash there.)

Three things to know before running it:

- **The hooks apply to every project you open**, not just wired ones — the git
  guard included, which means no agent can commit or push in *any* repo on the
  machine. That is usually the point, but `--no-git-guard` opts out.
- **Claude Code only.** No other agent reads a user-level instruction file, so
  Codex, Cursor, Copilot and friends still need `--agent` in the repo.
- **This machine only.** Teammates and CI cloning the repo see nothing, which is
  why `--agent` writes a repo block. Use `--global` for your own machines and
  `--agent` for anything shared — `--agent --no-docs` gives a repo the hooks
  while the instructions keep coming from the global block.

Per-repo state stays per repo: `infra-llm/` (plans and sessions) and
`.infra-llm.env` are repo state, not wiring, and are created on demand.

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
| `infra-llm/plans/`      | plan files + `.active-plan` marker (git-ignored)               |
| `infra-llm/sessions/`   | one `<session-id>.md` per session (last 10), git-ignored       |
| `.infra-llm.env`        | the repo's settings — `VERIFY_CMD`, git-guard mode — written commented-out, git-ignored |

Skip a guard at wiring time with `--no-git-guard` or `--no-vexp`.

Hooks run in a non-interactive shell, so `--global` / `--agent` also install a launcher at
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
GIT_WINDOW_SECONDS=1800     # how long a PR/release may commit and push; 0 = never
```

Destructive commands (force push, `reset --hard`, `clean -fd`, history
rewriting, `branch -D`, discarding working-tree changes) stay denied in `deny`
and `ask` mode and can't be allow-listed — only `off` silences them.

**PRs and releases commit and push on their own.** Asking for one *is* asking for
the commit and the push that make it, so `--pull-request` and `--create-release`
open a 30-minute window (`infra-llm/plans/.git-window`, git-ignored) in which
`commit`, `push`, `tag`, `branch` and `merge` are allowed, and the briefs tell
the agent to do the work and report the URL rather than hand back commands.
Nothing to edit before, nothing to revert after — the window expires by itself and is deleted on
the next guarded command. Destructive git stays denied inside it. Set
`GIT_WINDOW_SECONDS=0` to turn it off (the commands then prepare only), or a
different number of seconds to widen it.

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

`adopt-infra-llm.md` is a ready-to-run plan (a local, untracked file —
`infra-llm/` is git-ignored). Copy it into the target repo's plan dir and
have that repo's own agent work through it: inventory its hooks, commands,
rules and instruction files, decide what infra-llm already covers, and remove
only that — keeping whatever is genuinely project-specific.

### Slash commands

Claude Code only offers a project command if a file for it exists, so `--agent`
writes exactly **one**: `/infra-llm <what>`. A project repo gets a single file,
not a command per feature, and everything stays reachable:

```
/infra-llm review      /infra-llm plan <slug>    /infra-llm status
/infra-llm pr          /infra-llm steps          /infra-llm sessions
/infra-llm release     /infra-llm verify         /infra-llm worktrees
                                                 /infra-llm doctor
```

The file only points at the CLI — the briefs stay in the infra checkout, so
there is nothing to keep in sync. `infra-llm --agent --no-commands` generates
nothing at all for repos that would rather use the CLI directly; a command file
the repo wrote itself is never overwritten; `--uninstall` removes only the
generated one. The same words work bare in a terminal: `infra-llm pr`,
`infra-llm review`, `infra-llm doctor`.

If a terminal reports `unknown command`, the shell is running an `infra-llm`
function it sourced before that command existed — `infra-reload` (or a new
shell) fixes it, `infra-llm --doctor` detects it, and `commands.sh` prevents it
by re-sourcing on change.

### Tuning and extending it

Everything below is meant to be edited. Nothing else in a wired repo is.

**`.infra-llm.env` — per repo, git-ignored, written commented-out by `--init`.**
The only settings file read; a repo has exactly this or it has none:

```dotenv
VERIFY_CMD="npm test && npm run lint"   # what infra-llm --verify runs here
GIT_GUARD=deny                          # deny (default) | ask | off
GIT_GUARD_ALLOW="tag stash"             # subcommands to let through in this repo
CLAUDE_SESSIONS_KEEP=10                 # session records to keep (max 10)
```

`VERIFY_CMD` is the one worth setting first: without it the verification gate
closes the plan but runs no project checks. `GIT_GUARD=off` still denies
destructive commands — `reset --hard`, `clean -fd`, history rewriting — because
those are never what a repo means by "relaxed".

**The hooks — `llm/hooks/`, one copy for every repo.** Edit one and every wired
repo picks it up on its next run; nothing to redeploy, nothing to re-init.
`infra-llm --doctor` runs each of them in a scratch directory, so a broken edit
shows up immediately rather than at the next stop.

**The instruction block — `llm/templates/instructions.md`.** This is what agents
actually read. It is rendered between `<!-- infra-llm:start -->` markers into
the machine-wide `CLAUDE.md` (via `--global`) and into each wired repo's own
instruction file (via `--agent` / `--docs`). Editing a rendered copy is lost on
the next refresh; edit the template, then:

```bash
infra-llm --global      # refresh the machine-wide copy
infra-llm --docs        # refresh this repo's copies
```

Re-running is cheap: each piece is compared first and rewritten only when it
differs, and `--status` marks a copy that has drifted `OUT OF DATE`.

**The skills — `llm/skills/`.** `step-plan` and `llm-workflow` are the protocol
itself, installed by `--global` and loaded by Claude Code when their descriptions
match what you asked for. Add a directory with a `SKILL.md` and the next
`--global` installs it too. `design-review` is generated separately and is
opt-in: `infra-llm --designer` for one repo, `--global --designer` everywhere.

**The slash command — one file, `/infra-llm <what>`.** Generated so a project
gets a single command rather than one per feature; `--no-commands` skips it.

**The briefs — `llm/templates/`.** `code-review.md`, `pull-request.md` and
`create-release.md` are what `--code-review`, `--pull-request` and
`--create-release` print. They are instructions to an agent, so they follow the
same rule as everything else here: short, specific, imperative, and say why.

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
each worktree keeps its own `infra-llm/` — plans (with `.active-plan`) and
sessions — so one agent per worktree can run in parallel without colliding.
`gwtadd` prepares a new worktree automatically (creates the state dir, carries
`.infra-llm.env` over from the main checkout); `infra-llm --worktrees` shows
what each worktree is working on:

```
WORKTREE                 BRANCH                 PLAN                               SESSIONS
*infra                   master                 2 left: wire up the status table   3
 feature-login           feature/login          verify pending                     1
```

**A branch `gwtadd` creates is pushed to `origin` with `-u`.** Without it the
branch has no upstream, teammates and CI can't see it, and `gwtrm` has no remote
branch to delete. Only a branch it actually created is pushed — re-checking out
one that already exists locally or on `origin` pushes nothing — and `--no-push`
keeps it local:

```bash
gwtadd feature/login                 # branch off origin's default, push it
gwtadd feature/login master ../login # explicit base and path
gwtadd spike/idea --no-push          # local only
```

If the push fails — no network, no write access, a server-side hook — the
worktree is still there and ready; `gwtadd` says the branch is local only and
prints the retry command rather than pretending the whole thing failed.

`gwtrm <branch>` tears one down again: docker containers/volumes/images/networks
for that compose project, the worktree directory, the local branch, and the
branch on `origin`. Existence on the remote is checked with `git ls-remote`, not
the local tracking ref, so a branch that was pushed but never fetched back still
gets deleted, and a stale `origin/<branch>` ref is dropped afterwards. Files a
container wrote as root are removed with `sudo` when a plain `rm -rf` can't
touch them — if even that fails, `gwtrm` says which path is left and exits
non-zero instead of reporting a cleanup that didn't happen. `--keep-branch`,
`--keep-remote` and `--no-docker` opt out of each part; `-f` discards a dirty
worktree and `-y` skips the confirmation.

Short aliases when the shell has sourced `commands.sh` (or `git.sh`):
`llminit`, `llmagent`,
`llmglobal`, `llmdocs`,
`llmstatus`, `llmplan`, `llmsteps`, `llmverify`, `llmreview`, `llmpr`,
`llmrelease`, `llmsessions`, `llmskill`, `llmwt`, and
`claude_session` (runs `claude` after making sure session recording is wired up
in the current directory).
