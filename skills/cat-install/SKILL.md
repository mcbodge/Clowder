---
name: cat-install
description: 'Install or update Clowder for Copilot, Antigravity, or both, globally or in a project, with optional MudBlazor and safe MCP registration. Use when asked to "install clowder", "update clowder", "update the agents", "sync clowder", or "install into this project".'
---

# Install or update the Clowder

Delegate to the repository's `update-all` script — the single source of truth for what goes where — and report what it did. Never reimplement the copy steps by hand.

1. **Resolve the request**: default harness `copilot`; choose `antigravity` or `all` only when requested. Default scope is the user profile; a named project uses project scope. Ask only for unresolved choices, not defaults. MudBlazor is opt-in on every run; `GlobalMudMcp` implies it. Do not infer a stored preference.
2. **MCP**: project + MudBlazor registers workspace MCP, unless global registration is explicitly selected. Global MudBlazor alone installs content only. A new `mudblazor` entry requires the user's explicit documentation version; ask for it only when needed. Preserve an existing entry byte-for-byte without a supplied version. Never detect a package version or invent a default. A Copilot profile override is valid only with global MCP and a Copilot target.
3. **Locate and run**: use `scripts/update-all.ps1` on Windows or `scripts/update-all.sh` on macOS/Linux. Pass `-Harness` / `--harness`, `-ProjectDir` / `--project`, `-MudBlazor` / `--mudblazor`, `-GlobalMudMcp` / `--global-mud-mcp`, `-MudBlazorVersion` / `--mudblazor-version`, and `-CopilotMcpPath` / `--copilot-mcp-path` as selected. Keep RepoDir/Url or CLOWDER_DIR/CLOWDER_URL overrides. The script clones/pulls first and can be rerun. Never duplicate its installation logic.
4. **Bootstrap with parameters** when no clone is available (these commands trust remote code):

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/mcbodge/clowder/main/scripts/update-all.ps1))) -Harness all -ProjectDir 'C:\src\app'
   ```

   ```bash
   curl -fsSL https://raw.githubusercontent.com/mcbodge/clowder/main/scripts/update-all.sh | bash -s -- --harness all --project "$HOME/src/app"
   ```

5. **Prerequisites and report**: plain Copilot copy-only needs no Node. Antigravity/MCP needs Node.js 22+ with no npm parser setup. Canonical new MudMCP registration requires .NET 10 SDK and `dnx`, but installation never starts the server or installs a runtime. Report exact destinations, optional removals, MCP preservation/version-only updates, and failures without exposing credentials. Opt-out removes only four owned optional agents and owned `cat-mudblazor-*` skill bundles, leaving unrelated files and MCP entries alone.
6. **Scope limitations**: project mode skips companions and global hooks, except the explicit reported global-MCP exception. Copilot project agents still require existing global hook scripts. Antigravity gets converted agents/scoped rules and native skill paths, not Copilot hooks; planner boundaries are prompt-only and notes stay under `docs/plans/.clowder-notes/` with local git exclusion. Global companion updates run once; Antigravity-only skips unsupported playwright/DevOps skill placement. Configuration success is not connectivity: ask the user to trust/start the configured server in the editor and verify an actual `mudblazor` tool response.
