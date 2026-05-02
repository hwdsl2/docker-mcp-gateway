#!/bin/bash
#
# Docker script to configure and start an MCP Gateway server
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC! THIS IS ONLY MEANT TO BE RUN
# IN A CONTAINER!
#
# This file is part of MCP Gateway Docker image, available at:
# https://github.com/hwdsl2/docker-mcp-gateway
#
# Copyright (C) 2026 Lin Song <linsongui@gmail.com>
#
# This work is licensed under the MIT License
# See: https://opensource.org/licenses/MIT

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exiterr()  { echo "Error: $1" >&2; exit 1; }
nospaces() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
noquotes() { printf '%s' "$1" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"; }

check_port() {
  printf '%s' "$1" | tr -d '\n' | grep -Eq '^[0-9]+$' \
  && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

check_ip() {
  IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

check_dns_name() {
  FQDN_REGEX='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
  printf '%s' "$1" | tr -d '\n' | grep -Eq "$FQDN_REGEX"
}

# Source bind-mounted env file if present (takes precedence over --env-file)
if [ -f /mcp.env ]; then
  # shellcheck disable=SC1091
  . /mcp.env
fi

if [ ! -f "/.dockerenv" ] && [ ! -f "/run/.containerenv" ] \
  && [ -z "$KUBERNETES_SERVICE_HOST" ] \
  && ! head -n 1 /proc/1/sched 2>/dev/null | grep -q '^run\.sh '; then
  exiterr "This script ONLY runs in a container (e.g. Docker, Podman)."
fi

# Read and sanitize environment variables
MCP_API_KEY=$(nospaces "$MCP_API_KEY")
MCP_API_KEY=$(noquotes "$MCP_API_KEY")
MCP_PORT=$(nospaces "$MCP_PORT")
MCP_PORT=$(noquotes "$MCP_PORT")
MCP_HOST=$(nospaces "$MCP_HOST")
MCP_HOST=$(noquotes "$MCP_HOST")
MCP_SERVERS=$(nospaces "$MCP_SERVERS")
MCP_SERVERS=$(noquotes "$MCP_SERVERS")

MCP_FILESYSTEM_DIRS=$(nospaces "$MCP_FILESYSTEM_DIRS")
MCP_FILESYSTEM_DIRS=$(noquotes "$MCP_FILESYSTEM_DIRS")
MCP_GITHUB_TOKEN=$(nospaces "$MCP_GITHUB_TOKEN")
MCP_GITHUB_TOKEN=$(noquotes "$MCP_GITHUB_TOKEN")
MCP_BRAVE_API_KEY=$(nospaces "$MCP_BRAVE_API_KEY")
MCP_BRAVE_API_KEY=$(noquotes "$MCP_BRAVE_API_KEY")
MCP_POSTGRES_URL=$(nospaces "$MCP_POSTGRES_URL")
MCP_POSTGRES_URL=$(noquotes "$MCP_POSTGRES_URL")
MCP_GIT_REPO=$(nospaces "$MCP_GIT_REPO")
MCP_GIT_REPO=$(noquotes "$MCP_GIT_REPO")
MCP_ADMIN_PASSWORD=$(nospaces "$MCP_ADMIN_PASSWORD")
MCP_ADMIN_PASSWORD=$(noquotes "$MCP_ADMIN_PASSWORD")

# Apply defaults
[ -z "$MCP_PORT" ] && MCP_PORT=3000

# Internal port for MCPHub (Caddy proxies the user-facing port to this)
MCP_INTERNAL_PORT=3001

# Validate port
if ! check_port "$MCP_PORT"; then
  exiterr "MCP_PORT must be an integer between 1 and 65535."
fi

if [ "$MCP_PORT" = "$MCP_INTERNAL_PORT" ]; then
  exiterr "Port $MCP_INTERNAL_PORT is reserved for internal use. Please choose a different MCP_PORT."
fi

# Validate server hostname/IP
if [ -n "$MCP_HOST" ]; then
  if ! check_dns_name "$MCP_HOST" && ! check_ip "$MCP_HOST"; then
    exiterr "MCP_HOST '$MCP_HOST' is not a valid hostname or IP address."
  fi
fi

# Ensure data directory exists
mkdir -p /var/lib/mcp
chmod 700 /var/lib/mcp

API_KEY_FILE="/var/lib/mcp/.api_key"
PORT_FILE="/var/lib/mcp/.port"
SERVER_ADDR_FILE="/var/lib/mcp/.server_addr"
INITIALIZED_MARKER="/var/lib/mcp/.initialized"
MCPHUB_CONFIG="/var/lib/mcp/mcp_settings.json"

# Generate or load API key
if [ -n "$MCP_API_KEY" ]; then
  api_key="$MCP_API_KEY"
  printf '%s' "$api_key" > "$API_KEY_FILE"
  chmod 600 "$API_KEY_FILE"
else
  if [ -f "$API_KEY_FILE" ]; then
    api_key=$(cat "$API_KEY_FILE")
  else
    api_key="mcp-$(head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' | head -c 48)"
    printf '%s' "$api_key" > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
  fi
fi

# Save port for use by mcp_manage
printf '%s' "$MCP_PORT" > "$PORT_FILE"

# Determine server address for display
if [ -n "$MCP_HOST" ]; then
  server_addr="$MCP_HOST"
else
  public_ip=$(curl -sf --max-time 10 http://ipv4.icanhazip.com 2>/dev/null)
  check_ip "$public_ip" || public_ip=$(curl -sf --max-time 10 http://ip1.dynupdate.no-ip.com 2>/dev/null)
  if check_ip "$public_ip"; then
    server_addr="$public_ip"
  else
    server_addr="<server ip>"
  fi
fi
printf '%s' "$server_addr" > "$SERVER_ADDR_FILE"

echo
echo "MCP Gateway Docker - https://github.com/hwdsl2/docker-mcp-gateway"

if ! grep -q " /var/lib/mcp " /proc/mounts 2>/dev/null; then
  echo
  echo "Note: /var/lib/mcp is not mounted. Configuration and the API key"
  echo "      will be lost on container removal."
  echo "      Mount a Docker volume at /var/lib/mcp to persist data."
fi

# Detect first run
first_run=false
[ ! -f "$INITIALIZED_MARKER" ] && first_run=true

if $first_run; then
  echo
  echo "Starting MCP Gateway first-run setup..."
  echo "Port: $MCP_PORT"
  echo
fi

# -----------------------------------------------------------------------
# Generate MCPHub mcp_settings.json from environment variables
# -----------------------------------------------------------------------

generate_mcphub_config() {
  local config='{"mcpServers":{'
  local first_server=true
  local server_list=""

  if [ -n "$MCP_SERVERS" ]; then
    server_list="$MCP_SERVERS"
  fi

  if [ -z "$server_list" ]; then
    # No servers configured — generate minimal config with fetch as default
    config="${config}"'"fetch":{"command":"uvx","args":["mcp-server-fetch"]}'
    echo
    echo "Note: MCP_SERVERS not set. Enabling 'fetch' server as default."
    echo "      Set MCP_SERVERS in your env file to configure servers."
  else
    _IFS_ORIG="$IFS"
    IFS=','
    for _server in $server_list; do
      IFS="$_IFS_ORIG"
      _server=$(printf '%s' "$_server" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      [ -z "$_server" ] && continue

      _first_server_before="$first_server"
      if ! $first_server; then
        config="${config},"
      fi
      first_server=false

      case "$_server" in
        filesystem)
          if [ -z "$MCP_FILESYSTEM_DIRS" ]; then
            echo "Warning: 'filesystem' server enabled but MCP_FILESYSTEM_DIRS not set." >&2
            echo "         Using /data as default. Bind-mount directories into /data/." >&2
            MCP_FILESYSTEM_DIRS="/data"
          fi
          # Build args array: command + directories
          local fs_args='"npx","@modelcontextprotocol/server-filesystem"'
          _IFS2="$IFS"
          IFS=','
          for _dir in $MCP_FILESYSTEM_DIRS; do
            IFS="$_IFS2"
            _dir=$(printf '%s' "$_dir" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            [ -z "$_dir" ] && continue
            fs_args="${fs_args},\"${_dir}\""
          done
          IFS="$_IFS2"
          config="${config}\"filesystem\":{\"command\":\"npx\",\"args\":[${fs_args}]}"
          ;;
        fetch)
          config="${config}\"fetch\":{\"command\":\"uvx\",\"args\":[\"mcp-server-fetch\"]}"
          ;;
        github)
          if [ -z "$MCP_GITHUB_TOKEN" ]; then
            echo "Warning: 'github' server enabled but MCP_GITHUB_TOKEN not set." >&2
            echo "         The server may not function correctly." >&2
          fi
          config="${config}\"github\":{\"command\":\"npx\",\"args\":[\"@modelcontextprotocol/server-github\"],\"env\":{\"GITHUB_PERSONAL_ACCESS_TOKEN\":\"${MCP_GITHUB_TOKEN}\"}}"
          ;;
        brave-search)
          if [ -z "$MCP_BRAVE_API_KEY" ]; then
            echo "Warning: 'brave-search' server enabled but MCP_BRAVE_API_KEY not set." >&2
            echo "         The server will not function correctly." >&2
          fi
          config="${config}\"brave-search\":{\"command\":\"npx\",\"args\":[\"@modelcontextprotocol/server-brave-search\"],\"env\":{\"BRAVE_API_KEY\":\"${MCP_BRAVE_API_KEY}\"}}"
          ;;
        git)
          if [ -z "$MCP_GIT_REPO" ]; then
            echo "Warning: 'git' server enabled but MCP_GIT_REPO not set." >&2
            echo "         Using /repo as default. Bind-mount your repository into /repo." >&2
            MCP_GIT_REPO="/repo"
          fi
          config="${config}\"git\":{\"command\":\"uvx\",\"args\":[\"mcp-server-git\",\"--repository\",\"${MCP_GIT_REPO}\"]}"
          ;;
        postgres)
          if [ -z "$MCP_POSTGRES_URL" ]; then
            exiterr "'postgres' server enabled but MCP_POSTGRES_URL not set."
          fi
          config="${config}\"postgres\":{\"command\":\"npx\",\"args\":[\"@modelcontextprotocol/server-postgres\",\"${MCP_POSTGRES_URL}\"]}"
          ;;
        memory)
          config="${config}\"memory\":{\"command\":\"npx\",\"args\":[\"@modelcontextprotocol/server-memory\"]}"
          ;;
        sequential-thinking)
          config="${config}\"sequential-thinking\":{\"command\":\"npx\",\"args\":[\"@modelcontextprotocol/server-sequential-thinking\"]}"
          ;;
        *)
          echo "Warning: Unknown MCP server '$_server'. Skipping." >&2
          # Remove the comma that was speculatively added, and restore first_server
          config="${config%,}"
          first_server="$_first_server_before"
          ;;
      esac
      IFS=','
    done
    IFS="$_IFS_ORIG"
  fi

  # Close mcpServers object (single brace — root stays open)
  config="${config}}"

  # Disable MCPHub's own bearer auth — Caddy handles auth externally
  config="${config},\"systemConfig\":{\"routing\":{\"enableBearerAuth\":false}}"

  # Close root object
  config="${config}}"

  printf '%s' "$config" > "$MCPHUB_CONFIG"
  chmod 600 "$MCPHUB_CONFIG"
}

# Only generate config when it does not already exist.
# On subsequent starts MCPHub reloads the existing file, which preserves
# properly bcrypt-hashed user passwords written by MCPHub on first run.
# To apply a new MCP_SERVERS list, remove /var/lib/mcp/mcp_settings.json.
if [ ! -f "$MCPHUB_CONFIG" ]; then
  generate_mcphub_config
fi

# Save enabled servers list for manage.sh
if [ -n "$MCP_SERVERS" ]; then
  printf '%s' "$MCP_SERVERS" > "/var/lib/mcp/.servers"
else
  printf '%s' "fetch" > "/var/lib/mcp/.servers"
fi

if $first_run; then
  touch "$INITIALIZED_MARKER"
fi

# Graceful shutdown handler
cleanup() {
  echo
  echo "Stopping MCP Gateway..."
  kill "${CADDY_PID:-}" 2>/dev/null
  kill "${MCPHUB_PID:-}" 2>/dev/null
  wait "${CADDY_PID:-}" 2>/dev/null
  wait "${MCPHUB_PID:-}" 2>/dev/null
  exit 0
}
trap cleanup INT TERM

# Start MCPHub (always bound to localhost on internal port)
export PORT="$MCP_INTERNAL_PORT"
export NODE_ENV="production"
export MCPHUB_SETTING_PATH="$MCPHUB_CONFIG"
# Pass admin password to MCPHub's initializeDefaultUser (used on first run only)
[ -n "$MCP_ADMIN_PASSWORD" ] && export ADMIN_PASSWORD="$MCP_ADMIN_PASSWORD"

# MCPHub expects to run from /app
cd /app || exiterr "MCPHub app directory /app not found."

echo "Starting MCPHub server..."
node dist/index.js &
MCPHUB_PID=$!

# Wait for MCPHub to become ready (up to 30 seconds)
wait_for_mcphub() {
  local i=0
  while [ "$i" -lt 30 ]; do
    if ! kill -0 "$MCPHUB_PID" 2>/dev/null; then
      return 1
    fi
    if curl -sf "http://127.0.0.1:${MCP_INTERNAL_PORT}/health" >/dev/null 2>&1 \
       || curl -sf "http://127.0.0.1:${MCP_INTERNAL_PORT}/" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

if ! wait_for_mcphub; then
  if ! kill -0 "$MCPHUB_PID" 2>/dev/null; then
    exiterr "MCPHub failed to start. Check the container logs for details."
  else
    exiterr "MCPHub did not become ready after 30 seconds."
  fi
fi

# Start Caddy auth proxy (always enabled)
CADDY_CONFIG_FILE="/var/lib/mcp/.Caddyfile"
cat > "$CADDY_CONFIG_FILE" << CADDYEOF
:${MCP_PORT} {
  @unauthed {
    not header Authorization "Bearer ${api_key}"
    not path /health
  }
  respond @unauthed "Unauthorized" 401
  reverse_proxy 127.0.0.1:${MCP_INTERNAL_PORT}
}
CADDYEOF
caddy fmt --overwrite "$CADDY_CONFIG_FILE" 2>/dev/null || true
caddy run --config "$CADDY_CONFIG_FILE" --adapter caddyfile &
CADDY_PID=$!
# Wait up to 5 seconds for Caddy to start
_i=0
while [ "$_i" -lt 5 ]; do
  kill -0 "$CADDY_PID" 2>/dev/null || break
  curl -sf --max-time 1 "http://127.0.0.1:${MCP_PORT}/health" >/dev/null 2>&1 && break
  sleep 1
  _i=$((_i + 1))
done
if ! kill -0 "$CADDY_PID" 2>/dev/null; then
  exiterr "Caddy auth proxy failed to start."
fi

# Display connection info
echo
echo "==========================================================="
echo " MCP Gateway API key"
echo "==========================================================="
echo " ${api_key}"
echo "==========================================================="
echo
echo "Gateway endpoint: http://${server_addr}:${MCP_PORT}"
echo
echo "MCP endpoints:"
echo "  All servers:      http://${server_addr}:${MCP_PORT}/mcp"
echo "  Specific server:  http://${server_addr}:${MCP_PORT}/mcp/<server-name>"
echo "  Dashboard:        http://${server_addr}:${MCP_PORT}/"
echo
echo "To set up HTTPS, see: Using a reverse proxy"
echo "  https://github.com/hwdsl2/docker-mcp-gateway#using-a-reverse-proxy"
echo
echo "Test with:"
echo "  curl http://${server_addr}:${MCP_PORT}/mcp \\"
echo "    -H \"Authorization: Bearer ${api_key}\""

# Show enabled servers
echo
if [ -n "$MCP_SERVERS" ]; then
  echo "Enabled MCP servers: $MCP_SERVERS"
else
  echo "Enabled MCP servers: fetch (default)"
fi
echo
echo "Manage servers: docker exec <container> mcp_manage --help"
echo
echo "Setup complete."
echo

# Wait for main process
wait "$MCPHUB_PID"