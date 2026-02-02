#!/bin/bash
set -e

# Validate Pi auth.json is mounted
if [ ! -f /root/.pi/agent/auth.json ]; then
    echo "ERROR: auth.json not mounted at /root/.pi/agent/auth.json"
    exit 1
fi

# Validate anthropic key exists in auth.json
if ! jq -e '.anthropic.key' /root/.pi/agent/auth.json > /dev/null 2>&1; then
    echo "ERROR: anthropic.key not found in auth.json"
    exit 1
fi

# Set up git credentials from secrets.json
if [ -f /app/secrets.json ]; then
    GITHUB_TOKEN=$(jq -r '.github.token // empty' /app/secrets.json 2>/dev/null)
    if [ -n "${GITHUB_TOKEN}" ]; then
        git config --global credential.helper store
        echo "https://${GITHUB_TOKEN}@github.com" > ~/.git-credentials
        chmod 600 ~/.git-credentials
    fi
fi

# Configure git
git config --global user.name "${GIT_USER_NAME:-popebot}"
git config --global user.email "${GIT_USER_EMAIL:-popebot@example.com}"

# Clone/checkout repo
if [ -n "${REPO_URL}" ]; then
    cd /workspace
    [ -d ".git" ] && git fetch origin || git clone "${REPO_URL}" .
    git checkout "${BRANCH:-main}" 2>/dev/null || git checkout -b "${BRANCH:-main}"
    git pull origin "${BRANCH:-main}" 2>/dev/null || true
fi

# Build prompt from markdown files
PROMPT=$(cat /app/AGENTS.md /app/SOUL.md /app/MEMORY.md /app/TOOLS.md /app/HEARTBEAT.md "/app/roles/${ROLE:-worker}.md" 2>/dev/null)

# Append task if exists
[ -f "/workspace/${TASK_FILE:-task.md}" ] && PROMPT="${PROMPT}

## Current Task

$(cat /workspace/${TASK_FILE:-task.md})"

# Write prompt to file (avoids command line issues with multi-line strings)
echo "${PROMPT}" > /tmp/prompt.txt

# Create runner script for tmux (avoids quoting issues)
cat > /tmp/run-pi.sh << 'RUNNER'
#!/bin/bash
cd /workspace
pi -p "$(cat /tmp/prompt.txt)"
echo ""
echo "=== Pi finished. Container will exit. ==="
RUNNER
chmod +x /tmp/run-pi.sh

# Start tmux with bash, then run pi (so output is visible in terminal)
cd /workspace
tmux new-session -d -s popebot bash
tmux send-keys -t popebot '/tmp/run-pi.sh; exit' Enter

# Start ttyd for observation (background)
ttyd -p 7681 -W tmux attach-session -t popebot &

# Wait for Pi to finish, then exit
while tmux has-session -t popebot 2>/dev/null; do
    sleep 1
done
