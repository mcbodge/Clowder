#!/usr/bin/env bash
# Install or update the Clowder and its external companion tools.
#
# Clones this repository if it isn't present yet, otherwise pulls the latest, then copies the
# agents, instructions, skills, and hooks into your user profile, and updates playwright-cli, the
# azure-devops-cli skill, and graphify when their CLIs are installed. Run it from anywhere,
# even outside a clone: it reuses the clone it runs from, or clones to
# $HOME/.copilot/.cache/clowder. Override with CLOWDER_DIR / _URL.
# --harness selects copilot (default), antigravity, or all; --mudblazor opts into extra content.
# --project selects workspace content; npm global CLI updates and --global-mud-mcp are exceptions.
set -euo pipefail

COPILOT="$HOME/.copilot"
URL="${CLOWDER_URL:-https://github.com/mcbodge/clowder.git}"
REPO="${CLOWDER_DIR:-}"
PROJECT=""
HARNESS=copilot
MUDBLAZOR=false
GLOBAL_MUD_MCP=false
MUD_VERSION=""
MCP_PATH=""
VERSION_PRESENT=false
while [ $# -gt 0 ]; do
  case "$1" in
    --harness=*|--mudblazor-version=*|--copilot-mcp-path=*)
      key="${1%%=*}"; value="${1#*=}"
      [ -n "$value" ] || { echo "Missing value for $key" >&2; exit 1; }
      case "$key" in --harness) HARNESS="$value";; --mudblazor-version) MUD_VERSION="$value"; VERSION_PRESENT=true;; --copilot-mcp-path) MCP_PATH="$value";; esac ;;
    --harness|--mudblazor-version|--copilot-mcp-path)
      key="$1"; shift
      [ $# -gt 0 ] && [ -n "$1" ] && [[ "$1" != --* ]] || { echo "Missing value for $key" >&2; exit 1; }
      case "$key" in --harness) HARNESS="$1";; --mudblazor-version) MUD_VERSION="$1"; VERSION_PRESENT=true;; --copilot-mcp-path) MCP_PATH="$1";; esac ;;
    --mudblazor) MUDBLAZOR=true ;;
    --global-mud-mcp) GLOBAL_MUD_MCP=true; MUDBLAZOR=true ;;
    --help|-h) echo "Usage: update-all.sh [--project DIR] [--harness copilot|antigravity|all] [--mudblazor] [--global-mud-mcp] [--mudblazor-version VERSION] [--copilot-mcp-path FILE]"; exit 0 ;;
    --project=*) PROJECT="${1#*=}"; [ -n "$PROJECT" ] || { echo "Missing --project value" >&2; exit 1; } ;;
    --project) shift; [ $# -gt 0 ] && [ -n "$1" ] && [[ "$1" != --* ]] || { echo "Missing --project value" >&2; exit 1; }; PROJECT="$1" ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift || true
done
case "$HARNESS" in copilot|antigravity|all) ;; *) echo "Invalid --harness: $HARNESS" >&2; exit 1;; esac
expand_home() { case "$1" in '~') printf '%s\n' "$HOME";; '~/'*|'~\'*) printf '%s/%s\n' "$HOME" "${1:2}";; *) printf '%s\n' "$1";; esac; }
[ -z "$PROJECT" ] || PROJECT="$(expand_home "$PROJECT")"
[ -z "$REPO" ] || REPO="$(expand_home "$REPO")"
if [ -n "$PROJECT" ] && [ ! -d "$PROJECT" ]; then echo "--project must name a directory." >&2; exit 1; fi
[ -z "$PROJECT" ] || PROJECT="$(cd "$PROJECT" && pwd)"
if [ -n "$MCP_PATH" ] && { [ "$GLOBAL_MUD_MCP" != true ] || [ "$HARNESS" = antigravity ]; }; then echo "--copilot-mcp-path requires --global-mud-mcp and a Copilot target." >&2; exit 1; fi
if [ "$VERSION_PRESENT" = true ]; then
  if [ "$MUDBLAZOR" != true ] || { [ -z "$PROJECT" ] && [ "$GLOBAL_MUD_MCP" != true ]; }; then echo "--mudblazor-version requires project MCP registration or --global-mud-mcp." >&2; exit 1; fi
  [[ "$MUD_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]] || { echo "Pass a valid --mudblazor-version (for example 8.15.0)." >&2; exit 1; }
fi
NEEDS_HELPER=false
if [ "$HARNESS" != copilot ] || { [ "$MUDBLAZOR" = true ] && { [ -n "$PROJECT" ] || [ "$GLOBAL_MUD_MCP" = true ]; }; }; then
  NEEDS_HELPER=true
  command -v node >/dev/null 2>&1 || { echo "Node.js 22+ is required for Antigravity/MCP (no npm dependencies)." >&2; exit 1; }
  [ "$(node -p 'process.versions.node.split(`.`)[0]')" -ge 22 ] || { echo "Node.js 22+ is required." >&2; exit 1; }
fi

assert_safe_destination() {
  local current="${1//\\//}" parent
  while [ "$current" != "." ] && [ "$current" != "/" ] && [ -n "$current" ]; do
    [ ! -L "$current" ] || { echo "Refusing linked destination: $current" >&2; exit 1; }
    parent="${current%/*}"
    [ "$parent" != "$current" ] || break
    current="$parent"
  done
}

# Create the destination (unless the p flag) and copy sources into it.
# Usage: install_set <dest> <flags: r=recurse, p=only-if-present> <source>...
install_set() {
  local dest="$1" flags="$2"; shift 2
  assert_safe_destination "$dest"
  [[ "$flags" == *p* ]] || [ ! -e "$dest" ] || [ -d "$dest" ] || { echo "Expected directory: $dest" >&2; exit 1; }
  if [[ "$flags" == *p* ]] && [ ! -e "$dest" ]; then return 0; fi
  if [[ "$flags" != *p* ]]; then mkdir -p "$dest"; fi
  local source name optional
  for source in "$@"; do
    name="${source##*/}"
    assert_safe_destination "$dest/$name"
    optional=false
    case "$name" in
      cat-mudblazor-engineer.agent.md|cat-planner-mudblazor.agent.md|cat-planner-devops-mudblazor.agent.md|cat-plan-executor-mudblazor.agent.md) optional=true ;;
      cat-mudblazor-*) if [ -d "$source" ]; then optional=true; fi ;;
    esac
    if [ "$optional" = true ] && [ "$MUDBLAZOR" = false ]; then
          [ ! -L "$dest" ] && [ ! -L "$dest/$name" ] || { echo "Refusing linked optional target" >&2; exit 1; }
          [ -d "$source" ] || [ ! -d "$dest/$name" ] || { echo "Expected optional agent file: $dest/$name" >&2; exit 1; }
          rm -rf -- "$dest/$name"
          case "$name" in *.agent.md) assert_safe_destination "$dest/${name%.agent.md}.md"; rm -f -- "$dest/${name%.agent.md}.md";; esac
          echo "Omitted owned optional content: $name"
          continue
    fi
    if [[ "$flags" == *r* ]]; then cp -R "$source" "$dest"; else cp "$source" "$dest"; fi
  done
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
if [ -e "$REPO/.git" ]; then
  echo "==> Updating clowder in $REPO"
  git -C "$REPO" pull --ff-only || echo "git pull failed; continuing with the copy." >&2
elif [ -d "$REPO" ] && [ -n "$(ls -A "$REPO" 2>/dev/null)" ]; then
  echo "$REPO exists but is not a git clone; set CLOWDER_DIR or remove it." >&2; exit 1
else
  echo "==> Cloning clowder into $REPO"
  mkdir -p "$(dirname "$REPO")"
  git clone "$URL" "$REPO"
fi

if [ "$NEEDS_HELPER" = true ]; then
  helper_args=(repo "$REPO" harness "$HARNESS" mud "$MUDBLAZOR" globalMcp "$GLOBAL_MUD_MCP")
  [ -z "$PROJECT" ] || helper_args+=(project "$PROJECT")
  [ "$VERSION_PRESENT" != true ] || helper_args+=(version "$MUD_VERSION")
  [ -z "$MCP_PATH" ] || helper_args+=(mcpPath "$MCP_PATH")
  node "$REPO/scripts/install-support.mjs" "${helper_args[@]}"
fi

install_companions() (
  [ -z "$PROJECT" ] || echo "WARNING: Project scope exception: npm install -g updates the global Playwright CLI; companion skills stay in the selected project." >&2
  stage="$(cd "$REPO" && pwd)/.clowder-companions-$$-$RANDOM"
  mkdir "$stage" || { echo "WARNING: Cannot stage companions; continuing Clowder installation." >&2; return; }
  trap 'rm -rf -- "$stage"' EXIT
  cd "$stage" || { echo "WARNING: Cannot enter companion staging directory." >&2; return; }
  if command -v npm >/dev/null 2>&1; then
    npm install -g @playwright/cli@latest || echo "WARNING: playwright-cli update failed; trying the installed CLI." >&2
  else
    echo "WARNING: npm not found; install Node.js/npm to update playwright-cli." >&2
  fi
  if command -v playwright-cli >/dev/null 2>&1; then
    if ! playwright-cli install --skills agents; then
      echo "WARNING: playwright-cli skill installation failed; continuing Clowder installation." >&2
      rm -rf -- "$stage/.agents/skills/playwright-cli"
    fi
  else
    echo "WARNING: playwright-cli not found; install npm and run npm install -g @playwright/cli@latest." >&2
  fi
  if command -v gh >/dev/null 2>&1; then
    if ! gh skill install github/awesome-copilot azure-devops-cli --dir "$stage/.agents/skills" --force; then
      echo "WARNING: azure-devops-cli installation failed. Install/upgrade GitHub CLI from https://cli.github.com/ with gh skill support (gh skills may be unavailable); see https://cli.github.com/manual/gh_skill_install. Continuing Clowder installation." >&2
      rm -rf -- "$stage/.agents/skills/azure-devops-cli"
    fi
  else
    echo "WARNING: GitHub CLI (gh) not found; install/upgrade from https://cli.github.com/ with gh skill support for azure-devops-cli." >&2
  fi
  targets=()
  if [ "$HARNESS" != antigravity ]; then targets+=("${PROJECT:-$HOME}/$([ -n "$PROJECT" ] && echo .github || echo .copilot)/skills"); fi
  if [ "$HARNESS" != copilot ]; then targets+=("${PROJECT:-$HOME}/$([ -n "$PROJECT" ] && echo .agents || echo .gemini/config)/skills"); fi
  for name in playwright-cli azure-devops-cli; do
    source="$stage/.agents/skills/$name"
    if [ ! -f "$source/SKILL.md" ]; then
      echo "WARNING: $name did not produce SKILL.md; companion skill was NOT installed/updated." >&2
      continue
    fi
    for target in "${targets[@]}"; do
      if ( assert_safe_destination "$target/$name"
           [ ! -e "$target/$name" ] || [ -d "$target/$name" ] || { echo "Expected companion directory" >&2; exit 1; }
           if [ -d "$target/$name" ] && [ -n "$(find "$target/$name" -type l -print -quit)" ]; then echo "Refusing linked companion content" >&2; exit 1; fi
           install_set "$target" r "$source" ); then
        echo "Installed companion skill: $target/$name"
      else
        echo "WARNING: $name placement failed; continuing Clowder installation." >&2
      fi
    done
  done
)

# Project mode: install workspace companions too; npm global update is an explicit exception.
if [ -n "$PROJECT" ]; then
  if [ "$HARNESS" != antigravity ]; then
    GH="$PROJECT/.github"
    install_set "$GH/agents" "" "$REPO"/agents/*.agent.md
    install_set "$GH/instructions" "" "$REPO"/instructions/*.instructions.md
    install_set "$GH/skills" "r" "$REPO"/skills/*
  fi
  install_companions
  echo "==> Installed $HARNESS project content. Copilot project hooks require global hook scripts; Antigravity hook enforcement is not ported."
  exit 0
fi

# 3. Copy this repo's pieces into the user profile.
if [ "$HARNESS" != antigravity ]; then
install_set "$COPILOT/agents" "" "$REPO"/agents/*.agent.md
install_set "$COPILOT/skills" "r" "$REPO"/skills/*
install_set "$COPILOT/hooks" "" "$REPO"/hooks/git-guard/git-guard.ps1 "$REPO"/hooks/git-guard/git-guard.sh "$REPO"/hooks/env-guard/env-guard.ps1 "$REPO"/hooks/env-guard/env-guard.sh "$REPO"/hooks/planner-write-guard/planner-write-guard.ps1 "$REPO"/hooks/planner-write-guard/planner-write-guard.sh "$REPO"/hooks/graphify-sync/graphify-sync.ps1 "$REPO"/hooks/graphify-sync/graphify-sync.sh
chmod +x "$COPILOT/hooks/git-guard.sh" "$COPILOT/hooks/env-guard.sh" "$COPILOT/hooks/planner-write-guard.sh" "$COPILOT/hooks/graphify-sync.sh"
install_set "$COPILOT/instructions" "" "$REPO"/instructions/*.instructions.md
# git-guard and env-guard change behavior (deny/ask), so install them globally only if you opted in;
# the editing agents already declare them in their front matter.
install_set "$COPILOT/hooks/git-guard.json" "p" "$REPO/hooks/git-guard/hooks.json"
install_set "$COPILOT/hooks/env-guard.json" "p" "$REPO/hooks/env-guard/hooks.json"
# graphify-sync is silent and only acts when graphify is installed, so enable it for every session by
# default (delete graphify-sync.json to turn it off). It never denies, asks, or changes a decision.
cp "$REPO/hooks/graphify-sync/hooks.json" "$COPILOT/hooks/graphify-sync.json"

# VS Code / Insiders user prompts (instructions with applyTo).
case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support" ;;
  MINGW*|MSYS*) BASE="${APPDATA:-$HOME/.config}" ;;
  *)      BASE="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
esac
for dir in "$BASE/Code/User/prompts" "$BASE/Code - Insiders/User/prompts"; do
  install_set "$dir" "p" "$REPO"/instructions/*.instructions.md
done
fi

# 4. Download each companion once, then place it in every selected harness.
install_companions
if command -v uv >/dev/null 2>&1; then
  uv tool upgrade graphifyy 2>/dev/null || uv tool install graphifyy || echo "graphify update failed." >&2
else
  echo "uv not found; skipping graphify." >&2
fi

echo "==> Done."
