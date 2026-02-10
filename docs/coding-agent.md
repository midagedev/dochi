# Coding Agent Integration (Claude Code)

This MVP adds convenience tools to launch Claude, open your IDE, and prepare a succinct task brief you can paste into Claude Code.

Available tools (enable via tools registry if necessary):

- coding.open_claude
  - Opens `https://claude.ai` (or a provided URL) in the default browser.
  - Args: `{ url?: string }`

- coding.open_ide
  - Opens VS Code or Xcode, optionally at a specific path.
  - Args: `{ ide: "vscode"|"xcode", path?: string }`

- coding.copy_task_context
  - Composes a brief with the task, basic project info, and (optionally) minimal git metadata, then copies it to clipboard for pasting into Claude Code.
  - Args: `{ task: string, project_path?: string, include_git?: boolean }`

Example (in conversation):

1. Enable category: `tools.enable_categories { "categories": ["coding"] }`
2. Prepare context: `coding.copy_task_context { "task": "Add user search to settings page", "project_path": "/path/to/repo" }`
3. Launch: `coding.open_claude {}` and paste the clipboard contents into a new Claude Code session.

- claude_code.list_projects
  - Lists project directories detected under `~/.claude/projects`. Returns JSON array with names.

- claude_code.list_sessions
  - Lists recent sessions (id, summary, lastActivity, cwd) for a project. Args: `{ project: string, limit?: number, offset?: number }`

- claude_code.open_project
  - Opens the selected project folder in Finder. Args: `{ project: string }`

Claude Code UI server integration (API-only):

- claude_ui.configure
  - Set `enabled`, `base_url`, and `token` (Keychain stored).
- claude_ui.health / claude_ui.auth_status
  - Ping server health and auth status.
- claude_ui.mcp_list / claude_ui.mcp_add_json / claude_ui.mcp_remove
  - Manage Claude CLI MCP servers via claudecodeui’s CLI wrapper routes.
- claude_ui.install / claude_ui.pm2
  - Install `@siteboon/claude-code-ui` (and optionally `pm2`) and manage background process.
  - Example: `claude_ui.install { "confirm": true, "method": "npm", "install_pm2": true, "port": 3001 }`

Notes:
- This is a non-invasive MVP: no IDE plugins or deep browser automation required.
- For deeper automation later, use `device.run_applescript` (with confirm=true) or Shortcuts to script flows safely.
