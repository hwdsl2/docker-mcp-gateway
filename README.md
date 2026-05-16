[English](README.md) | [简体中文](README-zh.md) | [繁體中文](README-zh-Hant.md) | [Русский](README-ru.md)

# MCP Gateway on Docker

[![Build Status](https://github.com/hwdsl2/docker-mcp-gateway/actions/workflows/main.yml/badge.svg)](https://github.com/hwdsl2/docker-mcp-gateway/actions/workflows/main.yml) &nbsp;[![Docker Pulls](https://raw.githubusercontent.com/hwdsl2/badges/main/img/docker-pulls-mcp-gateway.svg)](https://hub.docker.com/r/hwdsl2/mcp-gateway) &nbsp;[![License: MIT](docs/images/license.svg)](https://opensource.org/licenses/MIT)

Part of the [Docker AI Stack](https://github.com/hwdsl2/docker-ai-stack) — deploy a complete self-hosted AI stack with a single command.

Docker image to run a self-hosted [MCP](https://modelcontextprotocol.io/) (Model Context Protocol) gateway, providing authenticated access to multiple MCP tool servers over HTTP from a single endpoint. Powered by [MCPHub](https://github.com/samanhappy/mcphub) with Caddy auth proxy. Designed to be simple and secure by default.

**Features:**

- **Secure by default** — all API requests require a Bearer token (auto-generated on first start)
- Auto-generates an API key on first start, stored in the persistent volume
- Multi-server gateway — run multiple MCP tool servers behind a single HTTP endpoint
- Path-based routing — access all servers at `/mcp` or individual servers at `/mcp/<name>`
- Streamable HTTP + SSE — both MCP transport modes supported
- Dashboard — web UI at `/` for monitoring MCP server status
- Env-file configuration — simple `mcp.env` file; no JSON editing
- Built-in MCP servers: filesystem, fetch, GitHub, Brave Search, Git, PostgreSQL, memory, sequential-thinking
- Caddy reverse proxy enforces Bearer token auth on all API requests (except `/health` health check)
- Works with [LiteLLM](https://github.com/hwdsl2/docker-litellm) to give any LLM access to MCP tools
- Automatically built and published via [GitHub Actions](https://github.com/hwdsl2/docker-mcp-gateway/actions)
- Persistent configuration via a Docker volume
- Multi-arch: `linux/amd64`, `linux/arm64`

**Also available:**

- AI/Audio: [Whisper (STT)](https://github.com/hwdsl2/docker-whisper), [Kokoro (TTS)](https://github.com/hwdsl2/docker-kokoro), [Embeddings](https://github.com/hwdsl2/docker-embeddings), [LiteLLM](https://github.com/hwdsl2/docker-litellm), [Ollama (LLM)](https://github.com/hwdsl2/docker-ollama), [Docling](https://github.com/hwdsl2/docker-docling)
- VPN: [WireGuard](https://github.com/hwdsl2/docker-wireguard), [OpenVPN](https://github.com/hwdsl2/docker-openvpn), [IPsec VPN](https://github.com/hwdsl2/docker-ipsec-vpn-server), [Headscale](https://github.com/hwdsl2/docker-headscale)

**Tip:** MCP Gateway, Ollama, LiteLLM, Whisper, Kokoro, Docling, and Embeddings can be [used together](#using-with-other-ai-services) to build a complete, self-hosted AI stack on your own server — with tool access, local LLMs, voice I/O, and semantic search.

## Security note

MCP servers have no built-in authentication. Exposing them publicly without auth is the same class of problem as the ~175,000 unauthenticated Ollama servers found publicly exposed ([source](https://www.sentinelone.com/labs/silent-brothers-ollama-hosts-form-anonymous-ai-network-beyond-platform-guardrails/)). This image enforces **Bearer token authentication on all API requests** via a built-in Caddy auth proxy, so unauthorized access is blocked even if the port is accidentally exposed.

## Quick start

**Step 1.** Start the MCP Gateway:

```bash
docker run \
    --name mcp \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

On first start, an API key is auto-generated and displayed in the container logs. All API requests require this key.

**Note:** For internet-facing deployments, using a [reverse proxy](#using-a-reverse-proxy) to add HTTPS is **strongly recommended**. In that case, also replace `-p 3000:3000/tcp` with `-p 127.0.0.1:3000:3000/tcp` in the `docker run` command above, to prevent direct access to the unencrypted port.

**Step 2.** Get the API key:

```bash
# View the key in the container logs
docker logs mcp

# Or retrieve it for use in scripts
MCP_KEY=$(docker exec mcp mcp_manage --getkey)
```

The API key is displayed in a box labeled **MCP Gateway API key**. To display it again at any time:

```bash
docker exec mcp mcp_manage --showkey
```

**Step 3.** Test with the API:

```bash
MCP_KEY=$(docker exec mcp mcp_manage --getkey)

# Test the MCP endpoint (fetch server is enabled by default)
curl http://localhost:3000/mcp \
  -H "Authorization: Bearer $MCP_KEY"

# Check gateway health (no auth required)
curl http://localhost:3000/health
```

**Note:** The `docker exec` management commands (`mcp_manage`) do not require the API key.

To learn more about how to use this image, read the sections below.

## Requirements

- A Linux server (local or cloud) with Docker installed
- At least 512 MB of available RAM
- TCP port 3000 (or your configured port) accessible

## Download

Get the trusted build from the [Docker Hub registry](https://hub.docker.com/r/hwdsl2/mcp-gateway/):

```bash
docker pull hwdsl2/mcp-gateway
```

Alternatively, you may download from [Quay.io](https://quay.io/repository/hwdsl2/mcp-gateway):

```bash
docker pull quay.io/hwdsl2/mcp-gateway
docker image tag quay.io/hwdsl2/mcp-gateway hwdsl2/mcp-gateway
```

Supported platforms: `linux/amd64` and `linux/arm64`.

## Environment variables

All variables are optional. If not set, secure defaults are used automatically.

This Docker image uses the following variables, that can be declared in an `env` file (see [example](mcp.env.example)):

| Variable | Description | Default |
|---|---|---|
| `MCP_API_KEY` | API key for authenticating requests (auto-generated if not set) | Auto-generated |
| `MCP_PORT` | TCP port for the gateway (1–65535) | `3000` |
| `MCP_HOST` | Hostname or IP shown in startup info and `--showkey` output | Auto-detected |
| `MCP_SERVERS` | Comma-separated list of MCP servers to enable | `fetch` |
| `MCP_ADMIN_PASSWORD` | Password for the MCPHub dashboard admin account (auto-generated on first start if not set) | Auto-generated |

**Note:** In your `env` file, you may enclose values in single quotes, e.g. `VAR='value'`. Do not add spaces around `=`. If you change `MCP_PORT`, update the `-p` flag in the `docker run` command accordingly.

Example using an `env` file:

```bash
cp mcp.env.example mcp.env
# Edit mcp.env and set your values, then:
docker run \
    --name mcp \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -v ./mcp.env:/mcp.env:ro \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

### Available MCP servers

Enable servers by listing them in `MCP_SERVERS` (comma-separated):

| Server | Required config | Description |
|---|---|---|
| `fetch` | — | Fetch URLs and extract content |
| `filesystem` | `MCP_FILESYSTEM_DIRS` | Read/write files in allowed directories |
| `github` | `MCP_GITHUB_TOKEN` | GitHub API access (repos, issues, PRs) |
| `brave-search` | `MCP_BRAVE_API_KEY` | Web search via Brave Search API |
| `git` | `MCP_GIT_REPO` | Git repository tools (status, diff, commit, log) |
| `postgres` | `MCP_POSTGRES_URL` | Query PostgreSQL databases |
| `memory` | — | Knowledge graph / persistent memory |
| `sequential-thinking` | — | Structured thinking and reasoning |

**Example:**

```bash
# Enable filesystem, fetch, and GitHub servers
MCP_SERVERS=filesystem,fetch,github
MCP_FILESYSTEM_DIRS=/data/docs,/data/projects
MCP_GITHUB_TOKEN=ghp_your_token_here
```

For the `filesystem` server, bind-mount host directories into the container:

```bash
docker run \
    --name mcp \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -v ./mcp.env:/mcp.env:ro \
    -v /home/user/documents:/data/docs:ro \
    -v /home/user/projects:/data/projects \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

For the `git` server, bind-mount the repository into the container and set `MCP_GIT_REPO`:

```bash
MCP_SERVERS=git
MCP_GIT_REPO=/repo
```

```bash
docker run \
    --name mcp \
    --restart=always \
    -v mcp-data:/var/lib/mcp \
    -v ./mcp.env:/mcp.env:ro \
    -v /home/user/myrepo:/repo \
    -p 3000:3000/tcp \
    -d hwdsl2/mcp-gateway
```

## Managing MCP servers

Use `docker exec` to manage the gateway with the `mcp_manage` helper script.

**List enabled servers:**

```bash
docker exec mcp mcp_manage --list
```

**Test a specific server:**

```bash
docker exec mcp mcp_manage --test fetch
docker exec mcp mcp_manage --test github
```

**Show gateway status:**

```bash
docker exec mcp mcp_manage --status
```

**Show the API key:**

```bash
docker exec mcp mcp_manage --showkey
```

**Get the API key** (machine-readable, for use in scripts):

```bash
MCP_KEY=$(docker exec mcp mcp_manage --getkey)
```

**Add or remove servers at runtime:**

Use the MCPHub dashboard at `http://<server>:3000/` to add, configure, or remove MCP servers without restarting the container. Changes are saved to the persistent volume and survive restarts.

> **Note:** `MCP_SERVERS` only applies on the **first run** when `mcp_settings.json` is created. After that, the dashboard is the way to manage servers. To re-apply `MCP_SERVERS` from scratch, remove the config file and restart:
> ```bash
> docker exec mcp rm /var/lib/mcp/mcp_settings.json
> docker restart mcp
> ```

## Using the API

All API requests require a Bearer token. Retrieve the API key first:

```bash
MCP_KEY=$(docker exec mcp mcp_manage --getkey)
```

**MCP endpoint (all enabled servers):**

```bash
curl http://localhost:3000/mcp \
  -H "Authorization: Bearer $MCP_KEY"
```

**MCP endpoint (specific server):**

```bash
curl http://localhost:3000/mcp/fetch \
  -H "Authorization: Bearer $MCP_KEY"
```

**Dashboard** (web UI):

Open `http://localhost:3000/` in a browser with `Authorization: Bearer <key>`, or use a client that supports header injection.

**Health check** (no auth required):

```bash
curl http://localhost:3000/health
```

### Connecting AI clients

**Cline (VS Code)** — in Cline's MCP settings:

```json
{
  "mcpServers": {
    "gateway": {
      "url": "http://localhost:3000/mcp",
      "transport": "streamable-http",
      "headers": {
        "Authorization": "Bearer <api_key>"
      }
    }
  }
}
```

**Claude Desktop** — in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "gateway": {
      "url": "http://localhost:3000/mcp",
      "transport": "streamable-http",
      "headers": {
        "Authorization": "Bearer <api_key>"
      }
    }
  }
}
```

## Persistent data

All gateway data is stored in the Docker volume (`/var/lib/mcp` inside the container):

```
/var/lib/mcp/
├── mcp_settings.json   # Generated MCPHub configuration
├── .api_key            # API key (auto-generated, or synced from MCP_API_KEY)
├── .initialized        # First-run marker
├── .port               # Saved port (used by mcp_manage)
├── .server_addr        # Cached server address (used by mcp_manage --showkey)
├── .servers            # Enabled servers list (used by mcp_manage)
└── .Caddyfile          # Generated Caddy config (auth proxy)
```

`mcp_settings.json` is generated from `MCP_SERVERS` on first run only. Subsequent restarts reuse the existing file, preserving any changes made via the dashboard.

Back up the Docker volume to preserve your configuration and API key.

## Using docker-compose

```bash
cp mcp.env.example mcp.env
# Edit mcp.env and set your values, then:
docker compose up -d
docker logs mcp
```

Example `docker-compose.yml` (already included):

```yaml
services:
  mcp:
    image: hwdsl2/mcp-gateway
    container_name: mcp
    restart: always
    ports:
      - "3000:3000/tcp"  # For a host-based reverse proxy, change to "127.0.0.1:3000:3000/tcp"
    volumes:
      - mcp-data:/var/lib/mcp
      - ./mcp.env:/mcp.env:ro
      # Mount host directories for the filesystem MCP server (optional):
      # - /path/to/docs:/data/docs:ro
      # - /path/to/code:/data/code:ro

volumes:
  mcp-data:
    name: mcp-data
```

**Note:** For internet-facing deployments, using a [reverse proxy](#using-a-reverse-proxy) to add HTTPS is **strongly recommended**. In that case, also change `"3000:3000/tcp"` to `"127.0.0.1:3000:3000/tcp"` in `docker-compose.yml`, to prevent direct access to the unencrypted port.

## Using a reverse proxy

For internet-facing deployments, place a reverse proxy in front of MCP Gateway to handle HTTPS termination. The server works without HTTPS on a local or trusted network, but HTTPS is recommended when the API endpoint is exposed to the internet.

Use one of the following addresses to reach the MCP Gateway container from your reverse proxy:

- **`mcp:3000`** — if your reverse proxy runs as a container in the **same Docker network** as MCP Gateway (e.g. defined in the same `docker-compose.yml`).
- **`127.0.0.1:3000`** — if your reverse proxy runs **on the host** and port `3000` is published (the default `docker-compose.yml` publishes it).

**Note:** The `Authorization: Bearer` header passes through reverse proxies automatically — no special configuration needed.

**Example with [Caddy](https://caddyserver.com/docs/) ([Docker image](https://hub.docker.com/_/caddy))** (automatic TLS via Let's Encrypt, reverse proxy in the same Docker network):

`Caddyfile`:
```
mcp.example.com {
  reverse_proxy mcp:3000
}
```

**Example with nginx** (reverse proxy on the host):

```nginx
server {
    listen 443 ssl;
    server_name mcp.example.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;       # required for SSE and WebSocket
        proxy_read_timeout 300s;
        proxy_buffering    off;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
    }
}
```

After setting up a reverse proxy, set `MCP_HOST=mcp.example.com` in your `env` file so that the correct endpoint URL is shown in the startup logs and `mcp_manage --showkey` output.

## Update Docker image

To update the Docker image and container, first [download](#download) the latest version:

```bash
docker pull hwdsl2/mcp-gateway
```

If the Docker image is already up to date, you should see:

```
Status: Image is up to date for hwdsl2/mcp-gateway:latest
```

Otherwise, it will download the latest version. Remove and re-create the container:

```bash
docker rm -f mcp
# Then re-run the docker run command from Quick start with the same volume.
```

Your configuration and API key are preserved in the `mcp-data` volume.

## Using with other AI services

The MCP Gateway, Ollama (LLM), LiteLLM, Whisper (STT), Kokoro (TTS), Docling, and Embeddings images can be combined to build a complete, self-hosted AI stack on your own server — from voice I/O to RAG-powered question answering. MCP Gateway provides tools (file access, web search, GitHub, databases) to any LLM client that supports MCP. Whisper, Kokoro, Docling, and Embeddings run fully locally. Ollama runs all LLM inference locally, so no data is sent to third parties. When using LiteLLM with external providers (e.g., OpenAI, Anthropic), your data will be sent to those providers.

| Service | Role | Default port |
|---|---|---|
| **[Ollama (LLM)](https://github.com/hwdsl2/docker-ollama)** | Runs local LLM models (llama3, qwen, mistral, etc.) | `11434` |
| **[LiteLLM](https://github.com/hwdsl2/docker-litellm)** | AI gateway — routes requests to Ollama, OpenAI, Anthropic, and 100+ providers | `4000` |
| **[Embeddings](https://github.com/hwdsl2/docker-embeddings)** | Converts text to vectors for semantic search and RAG | `8000` |
| **[Whisper (STT)](https://github.com/hwdsl2/docker-whisper)** | Transcribes spoken audio to text | `9000` |
| **[Kokoro (TTS)](https://github.com/hwdsl2/docker-kokoro)** | Converts text to natural-sounding speech | `8880` |
| **[MCP Gateway](https://github.com/hwdsl2/docker-mcp-gateway)** | Provides MCP tools (filesystem, fetch, GitHub, search, databases) to AI clients | `3000` |
| **[Docling](https://github.com/hwdsl2/docker-docling)** | Converts documents (PDF, DOCX, etc.) to structured text/Markdown | `5001` |

**See also: [Docker AI Stack](https://github.com/hwdsl2/docker-ai-stack)** — deploy the full stack with a single command, with ready-made configurations and pipeline examples.

**Connect MCP Gateway to LiteLLM:**

```yaml
# In your LiteLLM config, add the MCP gateway as a tool source:
mcp_servers:
  - url: http://mcp:3000/mcp
    transport: http
    headers:
      Authorization: "Bearer <mcp_api_key>"
```

## Technical details

- Base image: `samanhappy/mcphub` (Python 3.13 + Node.js 22)
- Auth proxy: [Caddy](https://caddyserver.com) (always active, enforces Bearer token auth)
- Gateway: [MCPHub](https://github.com/samanhappy/mcphub) (multi-server MCP hub)
- MCPHub internal port: `3001` (not published; Caddy proxies from `MCP_PORT`)
- Data directory: `/var/lib/mcp` (Docker volume)
- Gateway API: `http://localhost:3000` (or your configured port)
- MCP endpoint: `http://localhost:3000/mcp`
- Multi-arch: `linux/amd64`, `linux/arm64`

## License

**Note:** The software components inside the pre-built image (such as MCPHub, Caddy, and their dependencies) are under the respective licenses chosen by their respective copyright holders. As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.

Copyright (C) 2026 Lin Song   
This work is licensed under the [MIT License](https://opensource.org/licenses/MIT).

**MCPHub** is Copyright (C) 2025 samanhappy, and is distributed under the [Apache License 2.0](https://github.com/samanhappy/mcphub/blob/main/LICENSE).

**Caddy** is Copyright (C) 2015 Matthew Holt and The Caddy Authors, and is distributed under the [Apache License 2.0](https://github.com/caddyserver/caddy/blob/master/LICENSE).

This project is an independent Docker setup for MCPHub and is not affiliated with, endorsed by, or sponsored by MCPHub.