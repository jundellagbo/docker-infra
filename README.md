# Development Infrastructure

**A planning harness for Claude Code and other agent LLMs** — plus the local
infrastructure it runs against.

Point an agent at a task and it starts typing. This makes it write the plan
first: every discrete item as a checkbox in a file you can read and correct, then
one step per turn, ticked off as it goes. You review the plan while it is still a
paragraph, not after it has become a diff. Wire it once and it applies to every
repository on the machine.

```
you:    "add rate limiting to the API"
agent:  writes infra-llm/plans/rate-limiting.md — 6 checkboxes
you:    "drop 4, the cache already handles that"
agent:  implements step 1, ticks it, stops. The stop hook feeds it step 2…
```

It also stops an agent committing your work, records what each session was asked
to do, and ships the skills that make Claude Code follow all of it.

Three independent parts — use one, two, or all three:

| Part | What it is | Entry point |
| ---- | ---------- | ----------- |
| **Docker stack** | Nginx, Apache, PHP 7.4-8.4, MySQL, PostgreSQL, Redis, Adminer, MailHog, wildcard SSL and DNS for `*.dev.local` | `docker compose up -d` |
| **Host tooling** | Host PHP versions + switcher, Composer, WP-CLI, Node via nvm, Claude Code, its MCP servers and plugins | `sudo ./install.sh` |
| **Agent workflow** | The planning harness: plan protocol, one-step-per-turn stop hooks, verification gate, session records, git and search guards, and the Claude Code skills that drive them | `infra-llm --global` |

```bash
source /path/to/infra/commands.sh   # shell helpers: git shortcuts + infra-llm
infra-llm --global                  # wire the planning harness, machine-wide
infra-llm --init                    # per repo: state dirs + instruction block
docker compose up -d                # start the stack
```

---

## The Docker stack

**Quick start.** If Apache, Nginx, MySQL or PostgreSQL are installed on the host,
clear them out first with `sudo ./scripts/uninstall-local-services.sh`. Then
generate the wildcard certificate (`./scripts/generate-ssl.sh` — it prints how to
trust the CA, which Windows needs), optionally point `WWW_PATH` / `NGINX_PATH` in
`.env` somewhere else (relative paths resolve from the repo), and start it with
`docker compose up -d`. Create a site with `./scripts/project-create.sh mysite`
and visit `https://mysite.dev.local`.

**Host DNS.** Containers resolve `*.dev.local` themselves; your browser does not.
On Linux with systemd-resolved, `sudo ./scripts/setup-host-dns.sh` installs a
persistent wildcard resolver pointing at `127.0.0.1`, so new virtual hosts need
no hosts-file entry. Elsewhere, add one hosts line per site — hosts files don't
support wildcards.

**Automatic virtual hosts.** Any directory named `www/<name>.dev.local/public` is
served at `https://<name>.dev.local` with no Nginx config and no reload. Files in
`NGINX_PATH` can still define explicit `server_name` hosts when a project needs
custom routing, and an exact name beats the wildcard host. The `nginx/` folder is
watched by the `config-watcher` container, so adding, changing or deleting a
config reloads Nginx automatically.

**Services and credentials.** MySQL and PostgreSQL both use `root` /
`artisan7530`, on 3306 and 5432. Adminer is at http://localhost:8081 (add
`?driver=pgsql` for Postgres; SQL imports up to 128 MB — after editing
`docker/adminer/.user.ini`, run `docker compose up -d --force-recreate adminer`).
All PHP mail goes to MailHog: SMTP `mailhog:1025` from containers, web UI at
http://localhost:8025. The default site is https://dev.local and Apache is
reachable directly at http://localhost:8080.

```bash
mysql -h 127.0.0.1 -u root -partisan7530          # from the host
docker compose exec mysql mysql -u root -partisan7530
psql -h 127.0.0.1 -U root -d postgres
docker compose exec postgresql psql -U root -d postgres
```

**Everyday commands.**

```bash
docker compose up -d                  # start        docker compose down    # stop
docker compose logs -f [service]      # logs         docker compose restart nginx
docker compose exec php composer install
docker compose exec php wp --path=/var/www/mysite/public plugin list
docker compose exec php bash
```

**PHP version.** Set `PHP_VERSION` in `.env` (7.4, 8.0-8.4), then
`docker compose build php && docker compose up -d php` and check with
`docker compose exec php php -v`. The image carries every extension WordPress
wants — mysqli, curl, dom, exif, fileinfo, intl, mbstring, xml, zip, gd (WebP),
bcmath, filter, iconv, sodium, imagick — plus caching (opcache, redis, apcu,
memcached, igbinary), database drivers (pdo, pdo_mysql, pdo_pgsql, pgsql) and
soap, pcntl, sockets, bz2, xsl, gettext, gmp, tidy, calendar.

**WordPress** in one project:

```bash
mkdir -p www/myblog/public
docker compose exec php sh -c "cd /var/www/myblog/public && wp core download --allow-root"
docker compose exec mysql mysql -u root -partisan7530 -e "CREATE DATABASE myblog;"
docker compose exec php wp --path=/var/www/myblog/public core install \
  --url=https://myblog.dev.local --title="My Blog" --admin_user=admin \
  --admin_password=password --admin_email=admin@example.com --allow-root
```

**Layout.** `docker/` holds the PHP and Apache images and vhosts, `nginx/` the
virtual host configs (default `NGINX_PATH`), `www/` the projects (default
`WWW_PATH`), `ssl/` the wildcard certificates, `mysql/` and `postgresql/` their
init scripts, and `scripts/` the helpers.

**SSL.** The certificate covers `*.dev.local`, `dev.local` and `localhost`. On
Windows, open `\\wsl$\Ubuntu\home\<you>\infra\ssl`, double-click `ca.crt` →
Install Certificate → Local Machine → Trusted Root Certification Authorities,
then restart the browser. Or in an elevated PowerShell:

```powershell
Import-Certificate -FilePath "\\wsl$\Ubuntu\home\<you>\infra\ssl\ca.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

**Troubleshooting.** A port already in use: `sudo lsof -i :80`, then stop that
process or change the port in `docker-compose.yml`. Permission trouble in the
project tree: `sudo chown -R $USER:$USER www/`. Nginx refusing a config:
`docker compose exec nginx nginx -t` and `docker compose logs -f nginx`. Database
not answering: `docker compose exec mysql mysqladmin ping -h localhost -u root
-partisan7530` or `docker compose exec postgresql pg_isready -U root`. A browser
warning on `https://*.dev.local` means the CA certificate isn't trusted yet.

---

## Host tooling (`install.sh`)

On Debian or Ubuntu, `install.sh` installs host PHP versions with a switcher,
Composer, WP-CLI, Node through nvm, the Claude Code CLI, and the MCP servers and
plugins that go with it.

```bash
sudo ./install.sh                                # everything; PHP 8.3 default
sudo ./install.sh --versions 8.1 8.2 8.3 --default 8.2
sudo ./install.sh --versions=8.2,8.3,8.4         # comma-separated works too
```

`--no-composer`, `--no-wp`, `--no-node`, `--no-claude`, `--no-mcp` and
`--no-plugins` skip a part; `--node-version 20` pins a Node major instead of the
latest LTS. The component selectors — `--php`, `--composer`, `--wp`, `--node`,
`--claude`, `--mcp`, `--plugins` — install **only** what they name and reinstall
something already present, which is how you refresh one tool without touching the
rest (a Claude-only run does no `apt-get update` at all). PHP versions always
need the `--php` selector, so `--claude 8.2` is rejected rather than quietly
ignored.

```bash
sudo ./install.sh --claude              # reinstall just the CLI
sudo ./install.sh --mcp --plugins       # re-register MCPs, reinstall plugins
sudo ./install.sh --php 8.2 8.3         # add these PHP versions
```

The same selectors work after `--uninstall`; `--php` without versions removes
every PHP version the script can find, removing Node also removes nvm and its
Node versions for the invoking user, and a bare `sudo ./install.sh --uninstall`
takes out everything it manages, `phpsw` included. Afterwards `phpsw` lists the
installed host versions and `sudo phpsw 8.2` switches the CLI and FPM default.

### MCP servers

`install.sh --mcp` registers three servers at user scope, so they are available
in every repo.

**`chrome-devtools`** is registered with `--autoConnect` so agents drive the
Chrome you already have open, with your logged-in profile, instead of launching a
second empty one; a server registered by an earlier install without the flag is
re-registered. **This needs one manual step** (Chrome 144+): open
`chrome://inspect/#remote-debugging`, enable remote debugging, restart Chrome,
then restart the agent session. `--autoConnect` attaches through the
`DevToolsActivePort` file Chrome writes into its user data dir, and Chrome only
writes it while debugging is on — with it off the server can't attach and quietly
opens an empty profile instead, the tell being an agent that sees a blank browser
rather than your tabs.

Check the port, not the file: Chrome leaves `DevToolsActivePort` behind when you
switch debugging off, so its presence proves nothing.

```bash
port=$(head -1 ~/.config/google-chrome/DevToolsActivePort)   # Linux, stable
curl -sf "http://127.0.0.1:$port/json/version" && echo LIVE || echo OFF
```

`install.sh` runs that same probe after registering and reports which of the
three states you are in — live, stale file with nothing listening, or never
enabled. The user data dir is `~/.config/google-chrome` on Linux,
`~/Library/Application Support/Google/Chrome` on macOS and
`%LOCALAPPDATA%\Google\Chrome\User Data` on Windows, with other channels beside
it; `--autoConnect` follows stable unless the server is registered with
`--channel beta|dev|canary`, so enable debugging in the Chrome you actually
browse with. The toggle persists as `devtools.remote_debugging` in that
directory's `Local State`, so it survives restarts, but it is a real switch and
turning it off puts you back in the stale-file state. Nothing outside the browser
can flip it — that is the point of the gate — and
**`--remote-debugging-port` is not a way around it**: Chrome has ignored that
flag on the default user data dir since version 136, and a separate
`--user-data-dir` accepts it but has none of your logins.

There must be exactly one `chrome-devtools` server, which is why the
`chrome-devtools-mcp` Claude plugin is **not** installed and is removed if an
earlier run added it: the plugin hardcodes `npx chrome-devtools-mcp@1.6.0` with
no flags, so any call routed to its copy launches a fresh profile whatever the
registered server says. Check with `claude mcp list | grep chrome`.

**`codebase-memory-mcp`** builds a tree-sitter knowledge graph of a repository so
an agent can answer structural questions — who calls this, where is it defined,
what would this change break — off an index instead of re-reading files. It is a
single static binary installed into `~/.local/bin` (no root, no Node); index a
repo once with `index_repository`, then `search_code`, `search_graph`,
`trace_path` and `get_code_snippet` answer from the graph. The instruction block
tells agents to prefer those tools over Grep/Glob when they are available and to
fall back when they aren't.

It is deliberately installed with `--skip-config`: left to itself the installer
writes its own MCP entries, instructions, skills and lifecycle hooks into every
agent it can find — exactly the surface infra-llm owns. Taking only the binary
and registering the server here keeps one owner for the agent config.

**`figma`** is the hosted Figma MCP, registered over HTTP.

Plugins: `figma`, `skill-creator` and `impeccable` (from the `pbakaus/impeccable`
marketplace), plus emilkowalski's design skills through the `skills` CLI.

---

## Shell entry point (`commands.sh`)

`commands.sh` is the one file a shell sources. It loads `git.sh` (git shortcuts,
worktree helpers, the branch prompt) and `llm.sh` (the `infra-llm` workflow), and
`install.sh` writes it into `~/.bashrc`:

```bash
source /path/to/infra/commands.sh
```

**It reloads itself when the checkout changes.** Before each prompt it compares
the modification times of `git.sh` and `llm.sh` and re-sources both if either
moved, so the shell you are standing in is current on the next prompt instead of
running functions from before your last edit — the stale copy `infra-llm
--doctor` reports. Works in bash (`PROMPT_COMMAND`) and zsh (`precmd`), without
displacing hooks you already have. `infra-reload` (alias `infrareload`) does it
on demand, for a shell opened before `commands.sh` existed or a script where no
prompt runs. Sourcing `git.sh` directly still works; it just misses the reload
hook.

---

## The agent workflow (`llm.sh`)

The hooks live **only here**, in `llm/hooks/`; a project never gets a copy. It is
pointed at them instead — through the machine-wide install (`--global`) or its
own hook config (`--agent`), both of which call the `infra-llm` command rather
than vendoring anything. Fix a hook here and every repo on the machine is fixed,
with nothing to re-run.

### Setting it up with Claude Code

Five minutes, once per machine. **Load the shell helpers** with `source
/path/to/infra/commands.sh` (put it in `~/.bashrc` — `install.sh` does that for
you). **Wire the machine** with `infra-llm --global`, which installs the hooks
into Claude Code's config dir (`$CLAUDE_CONFIG_DIR`, else `~/.claude`) along with
the `/infra-llm` slash command and the three skills — `infra-llm-step`,
`infra-llm-workflow` and `infra-llm-design` — where they apply to every project.
Restart any Claude Code session that was already open; settings are read at
session start. Then **prepare each repo** with `infra-llm --init`, which creates
`infra-llm/` for plans and session records, `.infra-llm.env` for that repo's
settings, the ignore entries that keep both out of git, and the instruction block
in its `CLAUDE.md`.

Ask for something with more than one step and the agent writes a plan file first
— `infra-llm/plans/<slug>.md`, one `- [ ]` checkbox per discrete item —
implements one step per turn, ticks the box and stops. The stop hook blocks that
stop and feeds it the next step, so nothing is silently dropped and each turn
stays small. When every box is ticked it runs `infra-llm --verify`, which runs
this repo's `VERIFY_CMD` and clears the plan. It cannot commit, push, merge or
rebase — the git guard denies those — and when the session ends a record of what
was asked lands in `infra-llm/sessions/`.

Worth knowing on day one:

```bash
infra-llm --status      # what's wired here, active plan, next step, git mode
infra-llm --steps       # the next unchecked step the stop hook will demand
infra-llm --plan <slug> # start a plan yourself
infra-llm --verify      # run the checks and close the plan out
infra-llm --doctor      # can this machine run it? what's installed where?
infra-llm --sessions    # what past sessions were asked to do
```

Inside Claude Code the same words work as `/infra-llm status`, `/infra-llm
review`, `/infra-llm pr` and so on.

### The manual bits

Everything else installs itself. These need a human, and each fails *quietly*
when skipped.

1. **Enable Chrome remote debugging** (see [MCP servers](#mcp-servers)) — without
   it an agent screenshots a browser you can't see.
2. **Restart Claude Code after `infra-llm --global`** — hooks are read at session
   start, and a window opened beforehand looks exactly like "the hooks don't
   work".
3. **The shell line in `~/.bashrc`** — `install.sh` writes it; otherwise add
   `[ -f "$HOME/devops/infra/commands.sh" ] && source "$HOME/devops/infra/commands.sh"`.
   Without it `infra-llm` still works (the launcher is on `PATH`) but you lose the
   git shortcuts, worktree helpers and reload-on-change.
4. **Trust the CA certificate** — `./scripts/generate-ssl.sh` prints how.
5. **Host DNS for `*.dev.local`** — `sudo ./scripts/setup-host-dns.sh` on
   Linux/systemd-resolved; hosts-file entries per site elsewhere.

### If it doesn't seem to be working

| Symptom | Cause |
| ------- | ----- |
| No plan, no auto-continue | The session started before `--global`; settings load at session start, so restart it |
| Nothing happens on a one-line question | Correct — the protocol engages for multi-step work, or when a plan exists |
| `unknown command` from `infra-llm` | A shell holding an old copy: `infra-reload`, or open a new terminal |
| Auto-continue went quiet mid-plan | The stall guard hit its cap after three turns with no plan change — `--doctor` says so, and a new session resets it |

`infra-llm --doctor` checks the lot: PATH, hook scripts, the machine-wide
install, and whether this shell is running a stale copy.

### Why plan first

Each rule exists because of a specific way agent work goes wrong. **The plan
comes before the code**, which prevents implementing an interpretation you never
agreed to — a list of one-line outcomes is cheap to read and cheap to argue with,
where cutting a finished implementation costs a review, a revert and whatever it
broke on the way. **One step per turn** prevents the twelve-file reply where step
3 was wrong and everything after it was built on step 3. **The plan file is the
state, not the conversation**, which prevents re-deriving the task every turn and
is why it survives a context compaction, a crash, or a session that ends at 2am.
**Steps are revised, never silently dropped** — something unnecessary is marked
`- [x] … (skipped: reason)`, so you find out. **A verification gate** stops "done"
meaning "I stopped typing". **Session records** mean tomorrow doesn't start by
re-explaining yesterday. **The git guard** keeps an agent from committing,
pushing or rebasing on your behalf: it leaves the work in the tree and tells you
what changed.

**Does it save tokens?** Not directly, and the honest answer is more useful than
the flattering one. Writing the plan is tokens you wouldn't otherwise spend, one
step per turn means more turns, and each turn re-reads the plan file — on a task
the agent would have got right first time this is strictly more expensive. What
it saves is the *wrong* reply: an implementation built on a misread of the task
costs the tokens that produced it, the tokens spent reviewing it and the tokens
spent undoing it.

| Without | With |
| ------- | ---- |
| Agent guesses the scope, implements 6 things, 2 were wanted | You cut 4 checkboxes before any of them are built |
| A wrong assumption surfaces in the diff, after the work | It surfaces in a one-line plan step, before it |
| Each turn re-derives "what are we doing" from the transcript | Each turn re-reads a checklist |
| Context compaction loses the task; you re-explain it | The plan file survives; the agent resumes from it |
| A new session starts from nothing | Session records say what the last one was asked to do |

Re-reading a short checklist is cheaper than re-deriving intent from a long
conversation, and it doesn't degrade as the conversation grows. It is not worth
forcing onto a one-line fix, a question or a single file rename — the protocol
only engages for multi-step work. And what it definitely saves is your time: a
plan is reviewable in seconds, a diff is not.

### What it actually does

Five mechanisms, each a hook Claude Code calls at a specific moment.

**The plan is the checklist.** Multi-step work goes into
`infra-llm/plans/<slug>.md` as `- [ ]` checkboxes — no separate progress file, no
status kept in the conversation — and `infra-llm/plans/.active-plan` lists which
plan files are live. You see the file; so does the agent; they cannot disagree.

**One step per turn** (`Stop` hook). The agent implements one unchecked box,
ticks it and stops; the hook blocks that stop and hands back the next step, so
work advances in bounded turns and a step can't be silently dropped. You see this
as the agent continuing on its own, one step at a time, until the plan is done.

**A stall guard behind it.** If three consecutive turns end with no change to any
plan file, the hook gives up and lets the session stop, so a stuck agent can't
loop forever. The counter is keyed to the session and the plan's contents: tick a
box and it resets, start a new session and it resets. `--doctor` reports a repo
sitting at the cap.

**A verification gate** (`infra-llm --verify`). When every box is ticked the
agent runs it; it runs this repo's `VERIFY_CMD` from `.infra-llm.env` and only
then clears `.active-plan` so the session may end. No `VERIFY_CMD` means the gate
still closes the plan, it just has no project checks to run.

**Guards on the dangerous things** (`PreToolUse`). The *git guard* denies commit,
push, merge, rebase, reset, checkout, stash and history rewriting; the agent
leaves work in the tree and tells you what changed. `--pull-request` and
`--create-release` open a short, explicit window where committing and pushing are
allowed, with destructive commands still denied. Tune with `GIT_GUARD` in
`.infra-llm.env`: `deny` (default), `ask` or `off`. The *search guard* steers
`Grep`/`Glob` toward the faster index when one is running and gets out of the way
when it isn't.

**Session records** (`SessionEnd`). Every session writes what it was asked to do
into `infra-llm/sessions/<session-id>.md`, last 10 kept — useful for "what was
that other window doing?".

```bash
infra-llm --init           # this repo: state dirs, ignores, instruction block
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
infra-llm --skill <name>   # print a protocol skill
infra-llm --docs           # refresh the instruction blocks after editing infra
infra-llm --uninstall      # remove the wiring and the instruction blocks
```

### Three commands, three scopes

| Command | Scope | Installs |
| ------- | ----- | -------- |
| `--global` | this machine | hooks, `/infra-llm`, the three skills — every repo covered |
| `--init` | this repo | `infra-llm/` (plans + sessions), `.infra-llm.env`, ignore entries, and the instruction block |
| `--agent` | this repo | the same wiring as `--global`, but inside the repo itself, and blocks for every agent it detects |

**`--global`** installs the whole workflow into Claude Code's own config
directory, where it applies to every project. Re-run it after every infra change:
it's idempotent, each piece is compared before it's touched — the hooks against
what's in `settings.json`, the command and skills byte-for-byte — and rewritten
only when it differs, so a no-op run just prints `current` a few times and
anything you added yourself is left alone.

```bash
infra-llm --global                  # install or refresh all of it
infra-llm --global --no-designer    # ... without the infra-llm-design skill
infra-llm --global --no-git-guard   # ... but leave git alone
infra-llm --global --no-hooks       # ... command and skills only
infra-llm --global --no-skill       # ... no skills at all
infra-llm --global --remove         # take all of it back out
```

Three things to know before running it. **The hooks apply to every project you
open**, not just wired ones — the git guard included, which means no agent can
commit or push in *any* repo on the machine; that is usually the point, and
`--no-git-guard` opts out. **Claude Code only** — no other agent reads a
user-level config, so Codex, Cursor, Copilot and friends still need `--agent` in
the repo. **This machine only** — teammates and CI cloning the repo see nothing.
The config directory is `$CLAUDE_CONFIG_DIR` when set and `~/.claude` otherwise,
the same rule Claude Code follows, so this works unchanged on Linux, macOS, WSL
and Git Bash on Windows. (Native Windows without a bash can't run these scripts;
use WSL or Git Bash.)

**The instruction block is not part of `--global`.** It is written per repo by
`--init`, because that is where it belongs: it travels to teammates and CI with
the clone, and a machine-wide copy applied to every project whether or not it
used the workflow. Earlier versions did install one — `--global` takes it back
out of `~/.claude/CLAUDE.md` on the next run.

**`--init`** is repo state plus that block: no hooks, no slash command. It also
keeps the state out of everything that ships, because plan files and session
transcripts are machine-local scratch that would be dead weight in an image and
bust the build cache on every edit. `.gitignore` is **created** when missing —
the workflow depends on it — while `.dockerignore`, `.npmignore`,
`.gcloudignore`, `.vercelignore`, `.prettierignore` and `.eslintignore` are
**appended to only, never created**. A repo without a `.dockerignore` decided
something by not having one, and `.npmignore` is where inventing one would do
real damage: npm falls back to `.gitignore` when it's absent, so a new one
listing just our paths would start publishing everything `.gitignore` was keeping
out of the tarball. Write the file yourself and the next `--init` keeps it up to
date; the summary lists what ended up covered (`ignored: .gitignore
.dockerignore .prettierignore`). `--no-docs` skips the instruction block.

**`--agent`** is for when there is no machine-wide install, or when teammates and
CI clone the repo and must get the workflow with it. It runs the `--init` state
prep first, looks for every LLM setup it knows — Claude Code, Codex, Cursor,
Windsurf, GitHub Copilot, Gemini, Cline/Roo, Aider — pre-selects the ones the repo
already shows signs of, and still offers the rest so a repo can adopt one it
doesn't use yet (non-interactive: `--claude --codex …`, `--all`, `--yes`).
Re-running after infra changed brings each block up to date: it compares what
sits between the `infra-llm` markers with the current template and rewrites only
when they differ, never touching the rest of the file. `--force` rewrites even a
current block; `--docs` refreshes the blocks alone.

> **Don't wire both layers.** Claude Code *merges* user-level and project-level
> hooks rather than letting one override the other, so a repo that also ran
> `--agent` fires every hook twice. Nothing breaks, but it's noise. `--status`
> and `--doctor` warn when they see it; `infra-llm --uninstall` in the repo drops
> back to one layer.

Claude and Codex are the only two with a hook API; every other agent gets the
instruction block only, written where that tool actually reads it —
`.cursor/rules/infra-llm.mdc` with `alwaysApply` frontmatter,
`.windsurf/rules/infra-llm.md` with `trigger: always_on`,
`.github/copilot-instructions.md`, `.clinerules/infra-llm.md`, `CONVENTIONS.md`,
`GEMINI.md` — following the legacy location (`.cursorrules`, `.windsurfrules`, a
`.clinerules` file) when the repo already uses it.

What `--agent` touches in a repo: `.claude/settings.json` (hook entries calling
`infra-llm --hook …`, merged, existing hooks kept), `.claude/commands/infra-llm.md`
(one generated slash command; `--no-commands` skips it), `.codex/hooks.json`,
each selected agent's instruction file, `infra-llm/plans/` and
`infra-llm/sessions/` (git-ignored), and `.infra-llm.env`. Hooks run in a
non-interactive shell, so `--global` / `--agent` also install a launcher at
`~/.local/bin/infra-llm` (override with `LLM_BIN_DIR`), and every wired command
is guarded with `command -v infra-llm` and fails open, so a checkout on a machine
without this repo is never blocked.

### Git guard, pull requests and releases

Git state is the **user's** decision. The `PreToolUse(Bash)` guard denies
agent-run `git commit` / `push` / `merge` / `rebase` / `reset` / `tag` / `stash`
/ `checkout`; read-only git passes straight through, and non-git commands get no
decision at all, so normal permission behaviour is untouched. Tune it per repo in
`.infra-llm.env`:

```bash
GIT_GUARD=deny              # default — "ask" prompts the user, "off" disables
GIT_GUARD_ALLOW="tag stash" # subcommands this repo lets through
GIT_WINDOW_SECONDS=1800     # how long a PR/release may commit and push; 0 = never
```

Destructive commands — force push, `reset --hard`, `clean -fd`, history
rewriting, `branch -D`, discarding working-tree changes — stay denied in `deny`
and `ask` mode and can't be allow-listed; only `off` silences them.

**PRs and releases commit and push on their own**, because asking for one *is*
asking for the commit and the push that make it. `--pull-request` and
`--create-release` open a 30-minute window (`infra-llm/plans/.git-window`,
git-ignored) in which commit, push, tag, branch and merge are allowed, and their
briefs tell the agent to do the work and report the URL rather than hand back
commands. Nothing to edit before, nothing to revert after — the window expires by
itself and is deleted on the next guarded command, and destructive git stays
denied inside it. `GIT_WINDOW_SECONDS=0` turns it off (the commands then prepare
only).

Both commands mirror `--code-review`: a short brief plus the repo's real state —
branch vs. base, uncommitted changes, commits ahead, an existing PR, tags,
releases, where the version is declared — and both say don't duplicate an
existing one and verify first. Releases are tagged `vMAJOR.MINOR.PATCH` (`v1.0.1`
bug fix, `v1.1.0` feature, `v2.0.0` breaking), and `--create-release` prints the
three candidates computed from the previous tag so the bump is a decision rather
than an invention. Never AI attribution, anywhere.

### Slash commands

Claude Code only offers a command if a file for it exists, so exactly **one** is
generated: `/infra-llm <what>`. A project gets a single file rather than a command
per feature, and everything stays reachable:

```
/infra-llm review      /infra-llm plan <slug>    /infra-llm status
/infra-llm pr          /infra-llm steps          /infra-llm sessions
/infra-llm release     /infra-llm verify         /infra-llm worktrees
                                                 /infra-llm doctor
```

The file only points at the CLI — the briefs stay in the infra checkout, so there
is nothing to keep in sync. `--no-commands` generates nothing at all, a command
file the repo wrote itself is never overwritten, and `--uninstall` removes only
the generated one. The same words work bare in a terminal (`infra-llm pr`). An
`unknown command` means the shell is running an `infra-llm` function it sourced
before that command existed — `infra-reload` fixes it, `--doctor` detects it, and
`commands.sh` prevents it by re-sourcing on change.

### Tuning and extending it

Everything below is meant to be edited; nothing else in a wired repo is.

**`.infra-llm.env`** — per repo, git-ignored, written commented-out by `--init`,
and the only settings file read. `VERIFY_CMD` is the one worth setting first:
without it the gate closes the plan but runs no project checks. `GIT_GUARD=off`
still denies destructive commands, because those are never what a repo means by
"relaxed".

```dotenv
VERIFY_CMD="npm test && npm run lint"   # what infra-llm --verify runs here
GIT_GUARD=deny                          # deny (default) | ask | off
GIT_GUARD_ALLOW="tag stash"             # subcommands to let through in this repo
CLAUDE_SESSIONS_KEEP=10                 # session records to keep (max 10)
```

**The hooks — `llm/hooks/`.** One copy for every repo: edit one and every wired
repo picks it up on its next run, nothing to redeploy. `--doctor` runs each of
them in a scratch directory, so a broken edit shows up immediately rather than at
the next stop.

**The instruction block — `llm/templates/instructions.md`.** This is what agents
actually read, rendered between `<!-- infra-llm:start -->` markers into each
repo's own instruction file by `--init` / `--agent` / `--docs`. Editing a
rendered copy is lost on the next refresh; edit the template, then `infra-llm
--docs` in the repos that need it. `--status` marks a copy that has drifted `OUT
OF DATE`.

**The skills — `llm/skills/`.** `infra-llm-step` and `infra-llm-workflow` are the
protocol itself, installed by `--global` and loaded by Claude Code when their
descriptions match what you asked for; add a directory with a `SKILL.md` and the
next `--global` installs it too. `infra-llm-design` is generated from `llm.sh`
rather than copied and ships with `--global` as well — it only loads when a task
is actually about UI, and `--no-designer` leaves it out. All three are prefixed
so this workflow sorts together in a config dir shared with other skills; the
pre-prefix names (`step-plan`, `llm-workflow`, `design-review`) are removed on
sight so the same protocol isn't loaded twice.

**The briefs — `llm/templates/`.** `code-review.md`, `pull-request.md` and
`create-release.md` are what those three commands print. They are instructions to
an agent, so they follow the same rule as everything else here: short, direct,
paragraph-first, and say why.

**Adopting it in a repo that already has its own workflow.** `adopt-infra-llm.md`
is a ready-to-run plan (local and untracked — `infra-llm/` is git-ignored). Copy
it into the target repo's plan dir and have that repo's own agent work through
it: inventory its hooks, commands, rules and instruction files, decide what
infra-llm already covers, and remove only that.

### Environments

Linux, macOS and Windows via WSL. Every script is pinned to `#!/bin/bash`, which
exists on all three — and because that is bash 3.2 on macOS, nothing here uses
bash 4 syntax or steps outside a stock BSD userland (no `md5sum`, no
argument-less `mktemp`, no GNU-only flags). `.gitattributes` forces LF endings so
a Windows checkout can't hand the hooks a `\r` in the shebang, and the hooks strip
carriage returns anyway. Only `git` and the usual POSIX text tools are required;
`jq` is optional (no session records without it, and the guards fall back to
plain text matching) and so is `gh` (the PR and release commands can't see
existing PRs or releases).

`infra-llm --doctor` checks a machine in one command — OS and bash version, every
tool the hooks shell out to, the `/bin/bash` the shebangs point at, the launcher
on PATH, CRLF or syntax damage in the hook scripts, and a live run of each hook in
a scratch directory — and exits non-zero when something is actually broken.

### Worktrees

Wiring is tracked, so every worktree of a wired repo is wired. State is not: each
keeps its own `infra-llm/` — plans with `.active-plan`, and sessions — so one
agent per worktree runs in parallel without colliding. `gwtadd` prepares a new
worktree (state dir, `.infra-llm.env` carried over from the main checkout) and
`infra-llm --worktrees` shows what each is working on:

```
WORKTREE                 BRANCH                 PLAN                               SESSIONS
*infra                   master                 2 left: wire up the status table   3
 feature-login           feature/login          verify pending                     1
```

**A branch `gwtadd` creates is pushed to `origin` with `-u`**, because without an
upstream teammates and CI can't see it and `gwtrm` has no remote branch to delete.
Only a branch it actually created is pushed, and `--no-push` keeps it local. If
the push fails — no network, no write access, a server-side hook — the worktree is
still there and ready; `gwtadd` says the branch is local only and prints the retry
command rather than pretending the whole thing failed.

```bash
gwtadd feature/login                 # branch off origin's default, push it
gwtadd feature/login master ../login # explicit base and path
gwtadd spike/idea --no-push          # local only
```

`gwtrm <branch>` tears one down: docker containers, volumes, images and networks
for that compose project, the worktree directory, the local branch and the branch
on `origin`. Existence on the remote is checked with `git ls-remote` rather than
the local tracking ref, so a branch pushed but never fetched back still gets
deleted and a stale `origin/<branch>` ref is dropped afterwards. Files a container
wrote as root are removed with `sudo` when a plain `rm -rf` can't touch them — and
if even that fails, `gwtrm` says which path is left and exits non-zero instead of
reporting a cleanup that didn't happen. `--keep-branch`, `--keep-remote` and
`--no-docker` opt out of each part; `-f` discards a dirty worktree and `-y` skips
the confirmation.

Short aliases once the shell has sourced `commands.sh` (or `git.sh`): `llminit`,
`llmagent`, `llmglobal`, `llmdocs`, `llmstatus`, `llmplan`, `llmsteps`,
`llmverify`, `llmreview`, `llmpr`, `llmrelease`, `llmsessions`, `llmskill`,
`llmwt`, `llmdesigner`, `llmdoctor`, and `claude_session` (runs `claude` after
making sure session recording is wired up here).
