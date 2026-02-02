FROM node:22-alpine

# Install system dependencies
RUN apk add --no-cache \
    git \
    jq \
    curl \
    wget \
    bash \
    ca-certificates \
    tmux

# Install ttyd for web terminal (detect architecture)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then \
        wget -O /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.4/ttyd.aarch64; \
    else \
        wget -O /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/download/1.7.4/ttyd.x86_64; \
    fi && \
    chmod +x /usr/local/bin/ttyd

# Install Pi CLI globally
RUN npm install -g @mariozechner/pi-coding-agent

# Create app directory
WORKDIR /app

# Copy agent configuration files
COPY AGENTS.md SOUL.md MEMORY.md TOOLS.md HEARTBEAT.md ./
COPY roles/ ./roles/

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create workspace directory
RUN mkdir -p /workspace

EXPOSE 7681

ENTRYPOINT ["/entrypoint.sh"]
