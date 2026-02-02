# PopeBot Available Tools

## Credentials

Your API credentials for external services are at `/app/secrets.json`.
Read this file when you need tokens for GitHub, Gmail, Slack, etc.

```bash
# Example: Get GitHub token
jq -r '.github.token' /app/secrets.json

# Example: See all available services
jq 'keys' /app/secrets.json
```

## Browser Automation

A Chrome browser is running in a separate container and accessible for automation tasks.

### Browser Connection

- **Host**: `browser` (internal Docker network)
- **CDP Port**: `9222` (Chrome DevTools Protocol)
- **VNC Desktop**: `https://localhost:6901` (password: `popebot`) - for manual viewing/debugging

### Capabilities

- Navigate to URLs
- Click elements
- Fill forms
- Take screenshots
- Extract page content
- Execute JavaScript

### Usage with Puppeteer

```javascript
const puppeteer = require('puppeteer');

const browser = await puppeteer.connect({
  browserURL: 'http://browser:9222'
});

const page = await browser.newPage();
await page.goto('https://example.com');
// ... perform actions
await browser.disconnect();
```

## Command Line Tools

### Git
Full git CLI available for version control operations.

### Node.js (v22)
Latest Node.js runtime with npm for running JavaScript/TypeScript.

### jq
JSON processor for parsing and manipulating JSON data.

```bash
# Parse JSON file
cat data.json | jq '.field'

# Extract from API response
curl -s api.example.com | jq '.results[]'
```

### curl/wget
HTTP clients for making API requests.

## File Operations

Standard Unix file operations are available:
- `cat`, `head`, `tail` - Read files
- `grep`, `find` - Search files
- `sed`, `awk` - Process text
- `mkdir`, `cp`, `mv`, `rm` - Manage files

## Environment Variables

Access configuration through environment variables:
- `$BRANCH` - Current working branch
- `$TASK_FILE` - Path to current task file
- `$ROLE` - Agent role (worker/orchestrator)
- `$REPO_URL` - Repository URL
