#!/usr/bin/env node
'use strict';

function splitCsv(value) {
  return String(value || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function warn(message) {
  console.error(`Warning: ${message}`);
}

function addFilesystemServer(mcpServers) {
  let dirs = splitCsv(process.env.MCP_FILESYSTEM_DIRS);
  if (dirs.length === 0) {
    warn("'filesystem' server enabled but MCP_FILESYSTEM_DIRS not set.");
    console.error('         Using /data as default. Bind-mount directories into /data/.');
    dirs = ['/data'];
  }

  mcpServers.filesystem = {
    command: 'npx',
    args: ['@modelcontextprotocol/server-filesystem', ...dirs],
  };
}

function addFetchServer(mcpServers) {
  mcpServers.fetch = {
    command: 'uvx',
    args: ['mcp-server-fetch'],
  };
}

function addGithubServer(mcpServers) {
  const token = process.env.MCP_GITHUB_TOKEN || '';
  if (!token) {
    warn("'github' server enabled but MCP_GITHUB_TOKEN not set.");
    console.error('         The server may not function correctly.');
  }

  mcpServers.github = {
    command: 'npx',
    args: ['@modelcontextprotocol/server-github'],
    env: {
      GITHUB_PERSONAL_ACCESS_TOKEN: token,
    },
  };
}

function addBraveSearchServer(mcpServers) {
  const apiKey = process.env.MCP_BRAVE_API_KEY || '';
  if (!apiKey) {
    warn("'brave-search' server enabled but MCP_BRAVE_API_KEY not set.");
    console.error('         The server will not function correctly.');
  }

  mcpServers['brave-search'] = {
    command: 'npx',
    args: ['@modelcontextprotocol/server-brave-search'],
    env: {
      BRAVE_API_KEY: apiKey,
    },
  };
}

function addGitServer(mcpServers) {
  let repo = process.env.MCP_GIT_REPO || '';
  if (!repo) {
    warn("'git' server enabled but MCP_GIT_REPO not set.");
    console.error('         Using /repo as default. Bind-mount your repository into /repo.');
    repo = '/repo';
  }

  mcpServers.git = {
    command: 'uvx',
    args: ['mcp-server-git', '--repository', repo],
  };
}

function addPostgresServer(mcpServers) {
  const url = process.env.MCP_POSTGRES_URL || '';
  if (!url) {
    console.error("Error: 'postgres' server enabled but MCP_POSTGRES_URL not set.");
    process.exit(1);
  }

  mcpServers.postgres = {
    command: 'npx',
    args: ['@modelcontextprotocol/server-postgres', url],
  };
}

function addMemoryServer(mcpServers) {
  mcpServers.memory = {
    command: 'npx',
    args: ['@modelcontextprotocol/server-memory'],
  };
}

function addSequentialThinkingServer(mcpServers) {
  mcpServers['sequential-thinking'] = {
    command: 'npx',
    args: ['@modelcontextprotocol/server-sequential-thinking'],
  };
}

const builders = {
  filesystem: addFilesystemServer,
  fetch: addFetchServer,
  github: addGithubServer,
  'brave-search': addBraveSearchServer,
  git: addGitServer,
  postgres: addPostgresServer,
  memory: addMemoryServer,
  'sequential-thinking': addSequentialThinkingServer,
};

function buildConfig() {
  const mcpServers = {};
  const requestedServers = splitCsv(process.env.MCP_SERVERS);

  if (requestedServers.length === 0) {
    console.error('');
    console.error("Note: MCP_SERVERS not set. Enabling 'fetch' server as default.");
    console.error('      Set MCP_SERVERS in your env file to configure servers.');
    addFetchServer(mcpServers);
  } else {
    for (const server of requestedServers) {
      const builder = builders[server];
      if (!builder) {
        warn(`Unknown MCP server '${server}'. Skipping.`);
        continue;
      }
      builder(mcpServers);
    }
  }

  return {
    mcpServers,
    systemConfig: {
      routing: {
        enableBearerAuth: false,
      },
    },
    bearerKeys: [],
  };
}

process.stdout.write(`${JSON.stringify(buildConfig(), null, 2)}\n`);
