#!/bin/sh
# graphify-sync: SessionStart hook. Keeps the codebase graph warm so the planners, Plan Executor
# variants, Auditor, and Debugger consume a ready-made graph instead of building it themselves.
# Silent and fail-open: if graphify is not installed, if nothing changed, or on any error, it does
# nothing and exits 0. It never writes to the session (no additionalContext) and never blocks the
# session — the build runs detached in the background, exactly as graphify's own git hooks do.
#
# When graphify is on PATH it does three things, all idempotent:
#   1. Ensures .graphifyignore excludes build artifacts, dependencies, caches, generated code, and
#      the graph output, so the graph holds only meaningful source and architecture files.
#   2. Keeps graphify-out/ out of `git status` via .git/info/exclude (local, never committed).
#   3. Builds graphify-out/graph.json when missing (graphify extract . --code-only: local AST, no
#      API key, no network), or refreshes it when stale (graphify update .: incremental, no LLM).

# File modification time in epoch seconds, portable across GNU (Linux) and BSD (macOS) stat.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# Read the hook payload and pull out cwd; fall back to the current directory.
raw=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$raw" | sed -E -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1)
cwd=$(printf '%s' "$cwd" | sed -e 's/\\\//\//g' -e 's/\\\\/\\/g')   # decode \/ and \\ in the JSON path
[ -n "$cwd" ] || cwd=$(pwd)
[ -d "$cwd" ] || exit 0

# graphify is optional: without it, do nothing so no workflow ever breaks.
command -v graphify >/dev/null 2>&1 || exit 0

# Repository root for hygiene and staleness; fall back to cwd for a non-git tree.
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
is_git=1
[ -n "$root" ] || { root=$cwd; is_git=0; }

# 1. Noise filter: ensure .graphifyignore carries the required exclusions (append-only).
ignore="$root/.graphifyignore"
required='bin/
obj/
.vs/
node_modules/
dist/
build/
out/
coverage/
*.min.js
*.g.cs
*.designer.cs
.git/
graphify-out/'
if [ -f "$ignore" ]; then
  printf '%s\n' "$required" | while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    grep -qxF "$pat" "$ignore" 2>/dev/null || printf '%s\n' "$pat" >> "$ignore"
  done
else
  {
    printf '%s\n' '# Managed by clowder graphify-sync: keep the graph limited to meaningful source and'
    printf '%s\n' '# architecture files. Build artifacts, dependencies, caches, generated code, and the'
    printf '%s\n' '# graph output are excluded. Add your own patterns below; they are preserved.'
    printf '\n'
    printf '%s\n' "$required"
  } > "$ignore"
fi

# 2. Ignore hygiene: keep the graph output and the ignore file out of `git status`, locally and
# never committed. graphify still reads .graphifyignore regardless of git's view.
if [ "$is_git" = 1 ]; then
  exclude=$(git -C "$root" rev-parse --git-path info/exclude 2>/dev/null || true)
  if [ -n "$exclude" ]; then
    case "$exclude" in /*) : ;; *) exclude="$root/$exclude" ;; esac
    mkdir -p "$(dirname "$exclude")" 2>/dev/null || true
    for pair in 'graphify-out/:graphify-out/graph.json' '.graphifyignore:.graphifyignore'; do
      pat=${pair%%:*}; probe=${pair#*:}
      git -C "$root" check-ignore -q "$probe" 2>/dev/null && continue
      grep -qxF "$pat" "$exclude" 2>/dev/null || printf '%s\n' "$pat" >> "$exclude"
    done
  fi
fi

# 3. Decide whether to build (missing) or refresh (stale); otherwise there is nothing to do.
graph_json="$root/graphify-out/graph.json"
if [ ! -f "$graph_json" ]; then
  set -- extract . --code-only
else
  stale=1
  if [ "$is_git" = 1 ]; then
    stale=0
    graph_epoch=$(mtime "$graph_json")
    head_epoch=$(git -C "$root" log -1 --format=%ct 2>/dev/null || true)
    [ -n "$head_epoch" ] && [ -n "$graph_epoch" ] && [ "$graph_epoch" -lt "$head_epoch" ] && stale=1
    [ "$stale" = 0 ] && ! git -C "$root" diff --quiet 2>/dev/null && stale=1
    [ "$stale" = 0 ] && ! git -C "$root" diff --cached --quiet 2>/dev/null && stale=1
  fi
  [ "$stale" = 1 ] || exit 0
  set -- update .
fi

# Debounce: one build per repo per 10 minutes, so concurrent sessions and an in-flight build do not
# pile up. The lock and log live in TEMP, never in the repository.
key=$(printf '%s' "$root" | { md5sum 2>/dev/null || md5 2>/dev/null; } | cut -c1-12)
tmp=${TMPDIR:-/tmp}
lock="$tmp/graphify-sync-$key.lock"
log="$tmp/graphify-sync-$key.log"
if [ -f "$lock" ]; then
  now=$(date +%s); locked=$(mtime "$lock")
  [ -n "$locked" ] && [ "$((now - locked))" -lt 600 ] && exit 0
fi
: > "$lock" 2>/dev/null || true

# Run detached so the session is never delayed; log to TEMP for diagnostics only.
cd "$root" 2>/dev/null || exit 0
if command -v setsid >/dev/null 2>&1; then
  setsid graphify "$@" >"$log" 2>&1 </dev/null &
else
  nohup graphify "$@" >"$log" 2>&1 </dev/null &
fi
exit 0
