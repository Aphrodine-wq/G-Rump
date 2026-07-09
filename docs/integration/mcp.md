# MCP Integration

G-Rump ships with roughly 60 pre-configured Model Context Protocol (MCP) servers.

## Overview

MCP servers extend the agent's capabilities by providing specialized tools and data sources. Each server runs as a subprocess and communicates via JSON-RPC over stdio.

## Configuration

MCP servers are defined in `MCPServerConfig.swift` and managed by `MCPService`. Each server has:
- **Name** — Display identifier
- **Command** — Executable path
- **Arguments** — CLI arguments
- **Environment** — Environment variables (API keys, etc.)
- **Credentials** — Stored in Keychain via credential vault

## Credential Vault

API keys for MCP servers are stored securely in macOS Keychain, not in config files. The vault provides:
- Keychain-backed storage
- Per-server credential isolation
- Credential rotation support

Configure in **Settings → Workspace → MCP Servers**.

## Pre-configured Servers

Categories include:
- **Database** — PostgreSQL, MySQL, SQLite, MongoDB
- **Cloud** — AWS, GCP, Azure, Cloudflare
- **Dev Tools** — GitHub, GitLab, Jira, Linear
- **Search** — Brave Search, Tavily, Exa
- **Communication** — Slack, Discord
- **File** — Filesystem, Google Drive, S3
- **AI** — Additional model providers

## Adding a Custom Server

1. Go to **Settings → Workspace → MCP Servers**
2. Click "Add Server"
3. Provide command, arguments, and any required credentials
4. The server will appear in the available tools list

## Server Lifecycle

- Servers start on-demand when their tools are first called
- Idle servers are stopped after a timeout
- Server health is monitored; crashed servers are restarted automatically
