# Git-Native AI Assistant — Architecture Plan & MVP Blueprint

## Core Concept

The repository IS the assistant. You fork a template repo, add your credentials, and you have a personal AI assistant that can be run anywhere Docker runs. Git provides state management, version history, and coordination. Pi (by Mario Zechner) https://github.com/badlogic/pi-mono provides the agent loop. Docker provides portability.

There is no custom framework. The project is a **repo structure convention** + a **Dockerfile** + **role definitions in markdown**.

---

## Architecture Overview

### Three Layers

**Git (State & Coordination)**
- The repo is the single source of truth
- Branches represent active tasks
- Commits are events (task created, results produced, memory updated)
- Commit history is the audit log
- Merge = task completion / memory consolidation

**Docker (Runtime)**
- Generic container: Pi agent (https://github.com/badlogic/pi-mono) + Chromium browser
- Every task runs in its own branch checkout → its own directory → its own Docker Compose instance. No collisions.
- Portable: runs on local machine, GitHub Actions, any VPS, any cloud

**Pi (Agent Engine)**
- Handles LLM communication, tool execution, agent loop
- Model-agnostic (Anthropic, OpenAI, Google, local models)
- Reads `AGENTS.md` for instructions, uses `read`, `write`, `edit`, `bash` tools
- Self-extending: Pi can create extensions (`.pi/extensions/*.ts`) and skills (`.pi/skills/*/SKILL.md`) during tasks — these get committed and merged back, so the repo accumulates capabilities over time
- We use Pi as-is — no wrapper, no custom agent code

### Two Components

**Event Handler** — Lightweight, always-on, deterministic. **NOT an LLM.** Just a small script (~200 lines, Node.js or Python). It:
- Listens for incoming chat messages (Telegram, Discord, etc.)
- Listens for webhooks
- Runs on cron schedules
- Watches for task completion (commit events / webhooks)
- Creates task branches with `task.md` files
- Delivers results back to the user when tasks finish
- Reviews completed branches and merges to main (or flags for human review)

Can run on anything: Cloudflare Worker, small VPS, Raspberry Pi. No Docker, no Pi, no heavy dependencies. It's just plumbing.

**Workers** — Pi on a branch. That's it. Every task is a branch. The worker checks it out, reads `task.md`, runs Pi, commits results, pushes.

### How It Runs

Every task follows the same primitive:

```
Event arrives → Event handler creates branch with task.md → Worker checks out branch → Runs Pi → Commits results → Pushes → Event handler merges
```

**Every task is a branch. No exceptions.** This is intentionally uniform — one mechanism, even if small tasks have some git overhead. The simplicity of a single execution model is worth more than shaving seconds off small requests.

| Env Var | Purpose | Default |
|---------|---------|---------|
| `BRANCH` | Which branch to check out | _(required)_ |
| `ROLE` | Which role file to load (if no task.md) | `worker` |
| `PROMPT` | Override prompt (optional) | _(none)_ |

**Priority for what the agent does:**
1. Explicit `PROMPT` env var → use directly
2. `task.md` exists on branch → execute the task
3. Neither → fall back to `roles/{ROLE}.md` default behavior

---

## Repo Structure

```
my-assistant/                          # Fork this. It's YOUR assistant.
│
├── README.md                          # Setup instructions
├── docker-compose.yml                 # Pi + Chromium, generic
├── Dockerfile                         # Pi agent image
├── entrypoint.sh                      # Reads env vars, runs Pi
│
├── credentials.example.json           # Template showing what's needed — checked in
├── credentials.json                   # ALL secrets — checked in to YOUR private fork
│                                      #   (gitignored in template repo only)
│
├── AGENTS.md                          # Base instructions loaded by Pi on every run
├── SOUL.md                            # Personality, tone, shared identity
├── MEMORY.md                          # Long-term curated memory
├── memory/                            # Daily append-only logs
│   └── YYYY-MM-DD.md
│
├── roles/                             # Role definitions (just markdown)
│   ├── researcher.md                  # Uses browser, gathers information
│   ├── coder.md                       # Writes and tests code
│   └── writer.md                      # Produces documents and content
│
├── .pi/                               # Pi's working directories (committed to repo)
│   ├── skills/                        # Skills: markdown instruction files + scripts
│   │   └── ...                        #   Pi discovers these automatically on startup
│   ├── extensions/                    # Extensions: TypeScript modules
│   │   └── ...                        #   Pi loads these automatically on startup
│   └── settings.json                  # Pi project-level settings (optional)
│
├── event-handler/                     # Lightweight non-LLM event routing
│   ├── handler.js                     # ~200 lines: webhooks, cron, chat → branches
│   └── package.json
│
├── task-example.md                    # Demo task format (on main, for reference)
│
├── .github/
│   └── workflows/
│       ├── on-task-branch.yml         # Trigger: new branch with task.md → run worker
│       └── on-heartbeat.yml           # Trigger: cron schedule → check for completed tasks
│
└── .gitignore
```

---

## Key Files

### `docker-compose.yml`

```yaml
services:
  agent:
    build: .
    volumes:
      - .:/workspace
    working_dir: /workspace
    environment:
      - BRANCH=${BRANCH:-main}
      - ROLE=${ROLE:-worker}
      - PROMPT=${PROMPT:-}
      - MODE=${MODE:-observed}        # "observed" = TTYD web terminal, "headless" = silent
      - BROWSER_CDP_URL=http://browser:9222
    ports:
      - "7681:7681"   # TTYD: watch Pi work in your browser
    depends_on:
      browser:
        condition: service_started

  browser:
    image: kasmweb/chrome:latest
    environment:
      - CHROME_ARGS=--remote-debugging-port=9222 --remote-debugging-address=0.0.0.0
    ports:
      - "9222:9222"
      - "6901:6901"   # noVNC: watch the browser in your browser
```

**Observation URLs when running locally:**
- `localhost:7681` — Live terminal showing Pi's output (TTYD)
- `localhost:6901` — Live browser view showing what the agent sees (noVNC)

For CI/GitHub Actions, set `MODE=headless` to skip TTYD.

### `Dockerfile`

```dockerfile
FROM node:22-slim

# Install system deps
RUN apt-get update && apt-get install -y git jq && rm -rf /var/lib/apt/lists/*

# Install ttyd (web-based terminal for live streaming Pi's output)
RUN apt-get update && apt-get install -y ttyd && rm -rf /var/lib/apt/lists/*

# Install Pi globally
RUN npm install -g @mariozechner/pi-coding-agent

# Install browser-tools (Mario's CLI scripts for Chrome CDP)
RUN git clone https://github.com/badlogic/agent-tools /opt/agent-tools && \
    cd /opt/agent-tools/browser-tools && npm install
ENV PATH="/opt/agent-tools/browser-tools:${PATH}"

# Pi's home config directory
RUN mkdir -p /home/node/.pi/agent

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
```

### `entrypoint.sh`

```bash
#!/bin/bash
set -e

# --- Credentials ---
if [ -f /workspace/credentials.json ]; then
  # LLM API keys → Pi's expected location (Pi ignores unknown keys)
  ln -sf /workspace/credentials.json /home/node/.pi/agent/auth.json

  # SSH key → ~/.ssh (for git push/pull)
  SSH_KEY=$(jq -r '.git.ssh_private_key // empty' /workspace/credentials.json)
  if [ -n "$SSH_KEY" ]; then
    mkdir -p /home/node/.ssh
    echo "$SSH_KEY" > /home/node/.ssh/id_ed25519
    chmod 600 /home/node/.ssh/id_ed25519
    ssh-keyscan github.com >> /home/node/.ssh/known_hosts 2>/dev/null
  fi

  # Git identity
  GIT_NAME=$(jq -r '.git.user_name // "assistant"' /workspace/credentials.json)
  GIT_EMAIL=$(jq -r '.git.user_email // "assistant@noreply"' /workspace/credentials.json)
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
fi

# --- Branch ---
if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ -d .git ]; then
  git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"
fi

# --- Determine prompt ---
if [ -n "$PROMPT" ]; then
  FINAL_PROMPT="$PROMPT"
elif [ -f task.md ]; then
  FINAL_PROMPT="Read task.md and execute the task described in it."
else
  FINAL_PROMPT="Read roles/${ROLE}.md and follow its instructions."
fi

# --- Run Pi ---
# HEADLESS mode (CI/GitHub Actions): just run and exit
# OBSERVED mode (local): wrap in TTYD for live web terminal on port 7681
if [ "$MODE" = "headless" ]; then
  exec pi -p "$FINAL_PROMPT"
else
  exec ttyd --writable --port 7681 pi -p "$FINAL_PROMPT"
fi
```

### `credentials.json` — All Auth in One File

Single file for every secret the agent needs. Gitignored in the template repo, checked into your private fork.

```json
{
  "anthropic": {
    "type": "api_key",
    "key": "sk-ant-..."
  },
  "openai": {
    "type": "api_key",
    "key": "sk-..."
  },
  "google": {
    "type": "api_key",
    "key": "..."
  },
  "git": {
    "ssh_private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----",
    "user_name": "my-assistant",
    "user_email": "my-assistant@users.noreply.github.com"
  },
  "brave_search": {
    "type": "api_key",
    "key": "..."
  }
}
```

The LLM provider entries (`anthropic`, `openai`, `google`) match Pi's `auth.json` format exactly — the entrypoint symlinks the file directly. Pi ignores keys it doesn't recognize, so our extra entries (`git`, `brave_search`, etc.) don't interfere.

The entrypoint extracts non-LLM credentials and writes them to the right places:

```bash
# LLM auth → Pi's expected location
ln -sf /workspace/credentials.json /home/node/.pi/agent/auth.json

# SSH key → ~/.ssh (for git push/pull)
SSH_KEY=$(jq -r '.git.ssh_private_key // empty' /workspace/credentials.json)
if [ -n "$SSH_KEY" ]; then
  mkdir -p /home/node/.ssh
  echo "$SSH_KEY" > /home/node/.ssh/id_ed25519
  chmod 600 /home/node/.ssh/id_ed25519
  ssh-keyscan github.com >> /home/node/.ssh/known_hosts 2>/dev/null
fi

# Git identity
GIT_NAME=$(jq -r '.git.user_name // "assistant"' /workspace/credentials.json)
GIT_EMAIL=$(jq -r '.git.user_email // "assistant@noreply"' /workspace/credentials.json)
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
```

Skills and tools can read any other key via bash: `jq -r '.brave_search.key' /workspace/credentials.json`

Also supports environment variable fallback: if no `credentials.json` exists, Pi checks `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc. For GitHub Actions, use repository secrets instead of the file.

### `AGENTS.md`

```markdown
# Assistant Instructions

You are a personal AI assistant. Your workspace is this git repository.

## On Every Run
1. Read `SOUL.md` for your personality and tone
2. Read `MEMORY.md` for long-term context about the user
3. Check `memory/` for recent daily logs
4. Read your role file (specified in your prompt) or `task.md` for what you should do

## Tools Available
- File read/write/edit (Pi built-in)
- Bash commands (Pi built-in)
- Browser tools via bash — Chrome with CDP on port 9222:
  - `browser-nav.js <url>` — navigate to URL
  - `browser-eval.js '<js>'` — run JavaScript in active tab
  - `browser-screenshot.js` — take screenshot
  - `browser-search.js "query"` — Google search, return results
  - `browser-content.js <url>` — extract page content as markdown
  - See `/opt/agent-tools/browser-tools/README.md` for full docs

## Git Operations
- You can use git via bash to create branches, commit results, push changes
- Always commit meaningful changes with descriptive messages
- When updating memory files, commit separately with message "memory: <what changed>"

## Task Branches
- Tasks live on branches named `task/<description>`
- Each task branch has a `task.md` describing what to do
- When done, commit your results and push
- The event handler will handle merging

## Self-Extension
- When you solve a problem that required a novel approach, consider creating a reusable tool:
  - **Extensions** (`.pi/extensions/*.ts`): TypeScript modules for new tools, event handlers, or UI components. Pi hot-reloads these — write, reload, test, iterate.
  - **Skills** (`.pi/skills/<name>/SKILL.md`): Markdown instruction files with optional helper scripts for workflows you might repeat.
- Read Pi's docs (`docs/extensions.md`, `docs/skills.md`) for format and examples before creating.
- Commit new extensions/skills with a descriptive message prefixed with `capability:` so they can be reviewed before merging to main.
- Don't create trivial skills — only when you genuinely needed something reusable.

## Credentials
- All auth is in `credentials.json` — LLM API keys, SSH keys, git identity, service tokens
- LLM keys are symlinked to Pi's auth.json automatically
- SSH keys and git identity are extracted by the entrypoint at startup
- Read other keys via bash: `jq -r '.brave_search.key' /workspace/credentials.json`
- Never log, print, or expose credential values
- If you need a new credential for a service, note it in your task results so the user can add it
```

### `event-handler/handler.js` (conceptual)

The event handler is NOT an LLM. It's a small deterministic script that routes events to git branches.

```
Incoming event (chat message, webhook, cron)
    │
    ├─ Chat message → create branch task/<slug>, write task.md with message, push
    ├─ Webhook → create branch task/<slug>, write task.md with payload, push
    ├─ Cron/heartbeat → check for completed task branches, merge results to main
    └─ Task completion (push event on task branch) → read results, deliver to user, merge to main

Merge review:
    - If branch adds files to .pi/extensions/ or .pi/skills/ → flag for human review (or auto-merge with "capability:" prefix in log)
    - Otherwise → auto-merge, delete branch
```

This can be a Cloudflare Worker, Express app, GitHub Action, or Python script. ~200 lines. No LLM calls.

### `roles/researcher.md`

```markdown
# Researcher Role

You research topics and gather information.

## Tools
- Use the browser tools (browser-nav.js, browser-search.js, browser-content.js, etc.) for web research
- Save findings to `results/` on your branch
- Cite sources with URLs

## Process
1. Read task.md for what to research
2. Plan your research approach
3. Use browser tools to gather information
4. Write findings to `results/findings.md`
5. Commit and push when done
```

### `task-example.md`

```markdown
role: researcher
---
Research the top 5 competitors to Acme Corp.
For each, find: pricing model, key features, and recent funding.
Save a summary to results/competitor-analysis.md
```

---

## GitHub Actions Workflows

### `on-task-branch.yml`

```yaml
name: Run Task Worker

on:
  push:
    paths:
      - 'task.md'
  create:
    branches:
      - 'task/**'

jobs:
  run-agent:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.ref }}

      - name: Run agent
        env:
          BRANCH: ${{ github.ref_name }}
        run: docker compose up --abort-on-container-exit

      - name: Push results
        run: |
          git config user.name "assistant"
          git config user.email "assistant@noreply"
          git add -A
          git diff --cached --quiet || git commit -m "results: task complete"
          git push
```

### `on-heartbeat.yml`

```yaml
name: Heartbeat

on:
  schedule:
    - cron: '0 * * * *'    # Every 60 minutes
  workflow_dispatch:          # Manual trigger

jobs:
  heartbeat:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main

      - name: Check for completed tasks
        run: |
          # This is event handler logic, not LLM
          # Check for task branches with results, merge them, clean up
          for branch in $(git branch -r --list 'origin/task/*'); do
            # Check if branch has results committed after task.md
            echo "Checking $branch..."
            # Merge logic here
          done

      - name: Push any changes
        run: |
          git config user.name "assistant"
          git config user.email "assistant@noreply"
          git add -A
          git diff --cached --quiet || git commit -m "heartbeat: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          git push
```

---

## Task Lifecycle

```
1. Event arrives (chat message, cron, webhook)
         |
2. Event handler (NOT an LLM) creates branch task/<n> with task.md, pushes
         |
3. Worker triggered (GH Action, local Docker, or any runner)
         |
4. Worker checks out branch, reads task.md, runs Pi
         |
5. Pi executes task -- may create new extensions/skills along the way
         |
6. Worker commits ALL results (output + any new capabilities), pushes
         |
7. Event handler detects completion (webhook / polling / heartbeat cron)
         |
8. Event handler reviews branch:
   +- New files in .pi/extensions/ or .pi/skills/? -> flag for review
   +- Normal results? -> auto-merge to main
         |
9. Results delivered to user, branch cleaned up
```

**Key: the intelligence is entirely in the workers.** The event handler is deterministic routing -- same input, same action, every time. No LLM calls.

**Self-extension loop:** Task -> worker solves it -> writes a reusable tool along the way -> tool committed on branch -> merged to main -> every future worker inherits it. The repo accumulates capabilities over time. Git history shows when each capability was added, by which task, for what reason.



---

## MVP Scope — What to Build First

### Phase 1: Run Locally (Day 1)

**Goal:** Fork repo, add API key, `docker compose up`, agent executes a task on a branch.

Files needed:
- [ ] `docker-compose.yml` — Pi + Chromium
- [ ] `Dockerfile` — Node 22 + Pi + browser-tools + git
- [ ] `entrypoint.sh` — reads env vars, runs Pi
- [ ] `AGENTS.md` — base instructions (including self-extension guidance)
- [ ] `SOUL.md` — minimal personality
- [ ] `roles/researcher.md` — browser-capable worker
- [ ] `roles/coder.md` — code-writing worker
- [ ] `credentials.example.json` — template showing all auth fields
- [ ] `.gitignore` — ignores `credentials.json` in template repo
- [ ] `README.md` — setup instructions

**Test:** Create a task branch manually, run `BRANCH=task/test docker compose up`, agent reads task.md, executes, commits results.

---

## Key Dependencies

| Dependency | Purpose | Install |
|-----------|---------|---------|
| **Pi** (`@mariozechner/pi-coding-agent`) | Agent engine — LLM loop, tools (read/write/edit/bash) | `npm install -g` in Dockerfile |
| **Node.js 22** | Pi runtime | Base Docker image |
| **browser-tools** (`badlogic/agent-tools`) | Chrome CDP CLI scripts for web automation | `git clone` + `npm install` in Dockerfile |
| **Chromium** | Headless browser for web tasks (CDP on port 9222) | Separate Docker container (`kasmweb/chrome` — same as OpenClaw) |
| **git** | Branch/commit operations from inside container | `apt-get install` in Dockerfile |
| **jq** | JSON parsing in shell scripts | `apt-get install` in Dockerfile |
| **ttyd** | Web-based terminal — streams Pi's output to browser on port 7681 | `apt-get install` in Dockerfile |
| **Docker + Docker Compose** | Container runtime | User's machine / CI runner |

No custom frameworks. No databases. No message queues. No orchestration tools.

---

## Resolved Research — Pi Integration Details

### 1. Authentication (CONFIRMED — single credentials.json)

All auth lives in one file: `credentials.json`. The entrypoint symlinks it to Pi's `~/.pi/agent/auth.json` (Pi ignores keys it doesn't recognize) and extracts non-LLM credentials (SSH keys, git identity) to the filesystem.

**Format:** LLM provider entries use Pi's exact format. Extra entries for git, SSH, and any other service tokens coexist in the same file.

```json
{
  "anthropic": { "type": "api_key", "key": "sk-ant-..." },
  "openai": { "type": "api_key", "key": "sk-..." },
  "git": {
    "ssh_private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
    "user_name": "my-assistant",
    "user_email": "my-assistant@users.noreply.github.com"
  },
  "brave_search": { "type": "api_key", "key": "..." }
}
```

Also supports OAuth: `{ "type": "oauth", "accessToken": "...", "refreshToken": "...", "expires": 1234567890 }`

Fallback: environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) if no file exists.

**For GitHub Actions:** Use repository secrets instead. Pi's env var fallback handles LLM keys; git credentials use `GITHUB_TOKEN` automatically.
```

### 2. Pi's Browser Tool (CONFIRMED — NOT Built-In)

Pi has exactly **four built-in tools**: `read`, `write`, `edit`, `bash`. No browser tool.

Browser access comes from Mario's **`browser-tools`** — a set of CLI scripts (JavaScript) in `badlogic/agent-tools`. They connect to Chrome via CDP on port **9222** (not 3000 as blueprint originally had).

**The scripts:**
- `browser-start.js` — launch Chrome with `--remote-debugging-port=9222` (not needed in Docker — browser container handles this)
- `browser-nav.js <url>` — navigate to URL
- `browser-eval.js '<js>'` — execute JavaScript in active tab
- `browser-screenshot.js` — take screenshot
- `browser-search.js "query"` — Google search and return results
- `browser-content.js <url>` — extract readable content as markdown
- `browser-pick.js "Click the button"` — interactive element picker

**How Pi uses them:** Agent calls them via `bash` tool. E.g., the LLM decides it needs to browse, calls `bash("browser-nav.js https://example.com")`. They're just executables in PATH.

**For our project:**
- Docker Compose runs **`kasmweb/chrome`** (same image OpenClaw uses) with CDP on port 9222
- `browser-tools` scripts are installed in the agent container and added to PATH
- A `SKILL.md` or `AGENTS.md` section tells the agent these tools exist and how to use them
- `BROWSER_CDP_URL=http://browser:9222` env var tells scripts to connect to the sidecar container
- Optional: noVNC on port 6901 for visual debugging (can watch the browser in a web browser)

### 3. Pi's Execution Modes (Streaming by Default)

Pi has several non-interactive modes:

- **`pi -p "prompt"`** — Print mode. Runs silently, prints final text, exits. No visibility into progress.
- **`pi --mode json "prompt"`** — JSON mode. Streams full event stream (tool calls, results, text deltas) as newline-delimited JSON.
- **Interactive mode** — Full TUI. Supports steering messages mid-execution.
- **Piped stdin:** `echo "prompt" | pi` auto-enables print mode.

**For our project:** We want to **watch** the agent work, not just get results. Two layers of observability:

1. **TTYD** — Wraps Pi's interactive mode in a web-accessible terminal. Add `ttyd` to the Dockerfile, change the entrypoint to `ttyd --writable --port 7681 pi` instead of `pi -p`. Now open `localhost:7681` in a browser and you see Pi's live output. You can even type steering messages. This is the primary observation mechanism.

2. **noVNC on browser container** — `kasmweb/chrome` already exposes port 6901 as a web-based desktop showing the browser. Open `localhost:6901` and you see exactly what the agent sees when it browses.

So for any running task: **port 7681 = watch Pi think, port 6901 = watch the browser**.

**Entrypoint modes:**
- **Observed (default for local):** `ttyd --writable --port 7681 pi` — interactive, streamable, steerable
- **Headless (CI/GitHub Actions):** `pi -p "$PROMPT"` — no TUI, just runs and exits. Use `--mode json` piped to a log file if you want a record.

**Extensions still run** in all modes. Skills work. `AGENTS.md` is loaded. The only difference is whether you can see it happening.

### 4. Git from Inside Docker (SOLVED)

**Local development:** SSH key lives in `credentials.json` under `git.ssh_private_key`. The entrypoint extracts it to `~/.ssh/id_ed25519` and adds GitHub to known_hosts. Git identity comes from `git.user_name` and `git.user_email`. No volume mounts needed.

**GitHub Actions:** `GITHUB_TOKEN` is automatically available. Just need:
```yaml
permissions:
  contents: write
```
in the workflow YAML, and configure git:
```bash
git config user.name "assistant"
git config user.email "assistant@noreply"
git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git
```

**Other environments:** Same `credentials/ssh/` keys work anywhere. Or use a Personal Access Token in `credentials/` and configure HTTPS remotes.





## Remaining Open Questions

1. **browser-tools CDP host config** — The scripts default to `localhost:9222`. In Docker Compose, the browser is `browser:9222`. Need to verify: does `BROWSER_CDP_URL` env var work with Mario's scripts, or do we need to patch them / use a wrapper? OpenClaw solves this with their own browser tool implementation. Check if Pi's browser-tools skill has a config option.
2. **Pi package installation in Docker** — `npm install -g @mariozechner/pi-coding-agent` may need specific Node flags or permissions in Docker. Also need `npm install` in the browser-tools skill directory for its dependencies. Test the exact Dockerfile build.
3. **kasmweb/chrome CHROME_ARGS** — Verify that `CHROME_ARGS` env var properly passes `--remote-debugging-port=9222` in the kasmweb image, or if we need a different method to enable CDP.



## Guiding Principles

- **Pi does the hard work.** We don't build agent infrastructure. Pi handles the LLM loop, tool execution, streaming, model abstraction. We just call it.
- **Git does the state management.** No databases, no file-based queues, no in-memory state. Branches, commits, merges.
- **Docker does the portability.** Same container runs everywhere. Local, CI, cloud. No environment-specific setup.
- **Markdown does the configuration.** Roles, tasks, memory, personality — all plain text files. Editable by humans or by the agent itself.
- **Keep it simple.** If Pi already has a feature, use it. If git already solves a problem, don't build a solution. The less custom code, the less maintenance.