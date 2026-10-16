---
name: cat-install
description: 'Installs or updates the Clowder — the CAT agents, instructions, skills, and hooks — and its companion tools, into your user profile or a project .github folder. Use when asked to "install clowder", "update clowder", "update the agents", "sync clowder", or "install into this project".'
---

# Install or update the Clowder

Delegate to the repository's `update-all` script — the single source of truth for what goes where — and report what it did. Never reimplement the copy steps by hand.

1. **Target**: the user profile by default. When the user names a repository or says "into this project", use project mode (its `.github/`). Each run targets one location only — the user profile or one project, never both.
2. **Script**: pick by OS — `scripts/update-all.ps1` on Windows (PowerShell), `scripts/update-all.sh` on macOS and Linux (bash).
3. **Locate**: if the workspace is a Clowder clone (it has `scripts/update-all.*`), run that copy. Otherwise bootstrap from the remote: `irm https://raw.githubusercontent.com/mcbodge/clowder/main/scripts/update-all.ps1 | iex` (PowerShell) or `curl -fsSL https://raw.githubusercontent.com/mcbodge/clowder/main/scripts/update-all.sh | bash`.
4. **Run**: user profile — `powershell -ExecutionPolicy Bypass -File scripts/update-all.ps1` or `bash scripts/update-all.sh`. Project mode — add `-ProjectDir <repo>` (PowerShell) or `--project <repo>` (bash). The script clones or pulls first and is safe to re-run.
5. **Report**: say what was installed or updated and which companion tools (playwright-cli, the azure-devops-cli skill, graphify) were skipped because their CLI was absent. In user-profile mode the script also updates those companions; in project mode it copies only agents, instructions, and skills.
