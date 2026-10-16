#!/usr/bin/env bash
# Install or update the Clowder and its external companion tools.
#
# Clones this repository if it isn't present yet, otherwise pulls the latest, then copies the
# agents, instructions, skills, and hooks into your user profile, and updates playwright-cli, the
# azure-devops-cli skill, and graphify when their CLIs are installed. Run it from anywhere,
# even outside a clone: it reuses the clone it runs from, or clones to
# $HOME/.copilot/.cache/clowder. Override with CLOWDER_DIR / _URL.
# Pass --project <repo> to install into that repository's .github folder instead of your user
# profile (one method per run; ~/.copilot, editor prompts, and companion tools are left alone).
set -euo pipefail

COPILOT="$HOME/.copilot"
URL="${CLOWDER_URL:-https://github.com/mcbodge/clowder.git}"
REPO="${CLOWDER_DIR:-}"
PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project=*) PROJECT="${1#*=}" ;;
    --project) shift; PROJECT="${1:-}" ;;
  esac
  shift || true
done

# Create the destination (unless the p flag) and copy sources into it.
# Usage: install_set <dest> <flags: r=recurse, p=only-if-present> <source>...
install_set() {
  local dest="$1" flags="$2"; shift 2
  if [[ "$flags" == *p* ]] && [ ! -e "$dest" ]; then return 0; fi
  if [[ "$flags" != *p* ]]; then mkdir -p "$dest"; fi
  if [[ "$flags" == *r* ]]; then cp -R "$@" "$dest"; else cp "$@" "$dest"; fi
}

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

# Project mode: install into a repository's .github folder only, then stop (one method per run).
if [ -n "$PROJECT" ]; then
  [ -d "$PROJECT" ] || { echo "--project '$PROJECT' not found." >&2; exit 1; }
  GH="$PROJECT/.github"
  install_set "$GH/agents" "" "$REPO"/agents/*.agent.md
  install_set "$GH/instructions" "" "$REPO"/instructions/*.instructions.md
  install_set "$GH/skills" "r" "$REPO"/skills/*
  echo "==> Installed into $GH (agents, instructions, skills)."
  exit 0
fi

# 3. Copy this repo's pieces into the user profile.
install_set "$COPILOT/agents" "" "$REPO"/agents/*.agent.md
install_set "$COPILOT/skills" "r" "$REPO"/skills/*
install_set "$COPILOT/hooks" "" "$REPO"/hooks/git-guard/git-guard.ps1 "$REPO"/hooks/git-guard/git-guard.sh "$REPO"/hooks/env-guard/env-guard.ps1 "$REPO"/hooks/env-guard/env-guard.sh "$REPO"/hooks/planner-write-guard/planner-write-guard.ps1 "$REPO"/hooks/planner-write-guard/planner-write-guard.sh
chmod +x "$COPILOT/hooks/git-guard.sh" "$COPILOT/hooks/env-guard.sh" "$COPILOT/hooks/planner-write-guard.sh"
install_set "$COPILOT/instructions" "" "$REPO"/instructions/*.instructions.md
# Refresh the global git-guard and env-guard hooks only if you opted into them.
install_set "$COPILOT/hooks/git-guard.json" "p" "$REPO/hooks/git-guard/hooks.json"
install_set "$COPILOT/hooks/env-guard.json" "p" "$REPO/hooks/env-guard/hooks.json"

# VS Code / Insiders user prompts (instructions with applyTo).
case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support" ;;
  *)      BASE="$HOME/.config" ;;
esac
for dir in "$BASE/Code/User/prompts" "$BASE/Code - Insiders/User/prompts"; do
  install_set "$dir" "p" "$REPO"/instructions/*.instructions.md
done

# 4. Update external companion tools when their CLIs are present (best effort).
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
