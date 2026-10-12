#!/usr/bin/env bash
# Install or update the Clowder and its external companion tools.
#
# Clones this repository if it isn't present yet, otherwise pulls the latest, then copies the
# agents, instructions, skills, and hooks into your user profile, removes copies a rename
# superseded so the picker never lists two of the same agent, and updates playwright-cli, the
# azure-devops-cli skill, and graphify when their CLIs are installed. Run it from anywhere,
# even outside a clone: it reuses the clone it runs from, or clones to
# $HOME/.copilot/.cache/clowder. Override with CLOWDER_DIR / _URL.
set -euo pipefail

COPILOT="$HOME/.copilot"
URL="${CLOWDER_URL:-https://github.com/mcbodge/clowder.git}"
REPO="${CLOWDER_DIR:-}"

# 1. Locate the repo: explicit override, the clone this script runs from, or the cache clone.
if [ -z "$REPO" ]; then
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    FROM_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -d "$FROM_SCRIPT/agents" ] && [ -d "$FROM_SCRIPT/instructions" ]; then REPO="$FROM_SCRIPT"; fi
  fi
  [ -z "$REPO" ] && REPO="$COPILOT/.cache/clowder"
fi

command -v git >/dev/null 2>&1 || { echo "git is required but was not found on PATH." >&2; exit 1; }

# 2. Clone on first run, otherwise pull the latest.
if [ -d "$REPO/.git" ]; then
  echo "==> Updating clowder in $REPO"
  git -C "$REPO" pull --ff-only || echo "git pull failed; continuing with the copy." >&2
elif [ -d "$REPO" ] && [ -n "$(ls -A "$REPO" 2>/dev/null)" ]; then
  echo "$REPO exists but is not a git clone; set CLOWDER_DIR or remove it." >&2; exit 1
else
  echo "==> Cloning clowder into $REPO"
  mkdir -p "$(dirname "$REPO")"
  git clone "$URL" "$REPO"
fi

# 3. Copy this repo's pieces into the user profile.
mkdir -p "$COPILOT/agents" "$COPILOT/skills" "$COPILOT/hooks" "$COPILOT/instructions"
cp "$REPO"/agents/*.agent.md "$COPILOT/agents/"
cp -R "$REPO"/skills/* "$COPILOT/skills/"
cp "$REPO"/hooks/git-guard/git-guard.ps1 "$REPO"/hooks/git-guard/git-guard.sh "$COPILOT/hooks/"
chmod +x "$COPILOT/hooks/git-guard.sh"
cp "$REPO"/instructions/*.instructions.md "$COPILOT/instructions/"
# Refresh the global git-guard hook only if you opted into it.
if [ -f "$COPILOT/hooks/git-guard.json" ]; then
  cp "$REPO/hooks/git-guard/hooks.json" "$COPILOT/hooks/git-guard.json"
fi

# VS Code / Insiders user prompts (instructions with applyTo).
case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support" ;;
  *)      BASE="$HOME/.config" ;;
esac
for dir in "$BASE/Code/User/prompts" "$BASE/Code - Insiders/User/prompts"; do
  if [ -d "$dir" ]; then cp "$REPO"/instructions/*.instructions.md "$dir/"; fi
done

# 4. Remove copies superseded by the cat- rename so the picker never lists two.
for name in code-reviewer code-simplifier csharp-engineer debugger implementation-planner \
            mudblazor-engineer plan-executor pr-feedback-resolver tdd-cycle tdd-green tdd-red \
            tdd-refactor work-item-planner \
            cat-implementation-planner cat-implementation-planner-mudblazor \
            cat-work-item-planner cat-work-item-planner-mudblazor; do
  rm -f "$COPILOT/agents/$name.agent.md"
done
rm -rf "$COPILOT/skills/release-notes"

# 5. Update external companion tools when their CLIs are present (best effort).
if command -v npm >/dev/null 2>&1; then
  npm install -g @playwright/cli@latest || echo "playwright-cli update failed." >&2
  if command -v playwright-cli >/dev/null 2>&1; then
    playwright-cli install --skills || true
  fi
else
  echo "npm not found; skipping playwright-cli." >&2
fi
if command -v gh >/dev/null 2>&1; then
  gh skills install github/awesome-copilot azure-devops-cli || echo "azure-devops-cli update failed." >&2
else
  echo "GitHub CLI (gh) not found; skipping the azure-devops-cli skill." >&2
fi
if command -v uv >/dev/null 2>&1; then
  uv tool upgrade graphifyy 2>/dev/null || uv tool install graphifyy || echo "graphify update failed." >&2
else
  echo "uv not found; skipping graphify." >&2
fi

echo "==> Done."
