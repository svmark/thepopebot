# PopeBot

An autonomous AI agent infrastructure using Claude Code in Docker containers.

## Quick Start

### 1. Create credentials.json

```bash
cp credentials.example.json credentials.json
# Edit credentials.json with your API keys
```

### 2. Create a Task

Create a `task.md` file in your repository:

```markdown
# Task: Add User Login

## Requirements
- Create login form component
- Add authentication API endpoint
```

### 3. Build and Run

```bash
docker compose build
BRANCH=feature/login docker compose up
```

### 4. Monitor

- **Terminal**: http://localhost:7681
- **Browser**: http://localhost:6901

## Configuration

### credentials.json

| Field | Description | Required |
|-------|-------------|----------|
| `anthropic_api_key` | Anthropic API key | Yes |
| `github_token` | GitHub access token | No |
| `repo_url` | Repository URL to clone | No |
| `git_user_name` | Git commit author name | No (default: popebot) |
| `git_user_email` | Git commit author email | No (default: popebot@example.com) |

### Environment Variables

These can be set when running docker compose:

| Variable | Description | Default |
|----------|-------------|---------|
| `BRANCH` | Git branch to work on | `main` |
| `TASK_FILE` | Path to task file | `task.md` |
| `ROLE` | Agent role (worker/orchestrator) | `worker` |

## Roles

- **worker** (default): Executes tasks, writes code, makes commits
- **orchestrator**: Manages branches, merges PRs, resolves conflicts

## Agent Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Core agent instructions |
| `SOUL.md` | Agent personality |
| `MEMORY.md` | Long-term knowledge |
| `TOOLS.md` | Available tools |
| `HEARTBEAT.md` | Periodic check instructions |
| `roles/*.md` | Role-specific behaviors |
