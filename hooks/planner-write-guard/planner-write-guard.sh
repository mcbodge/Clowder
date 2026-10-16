#!/bin/sh
# planner-write-guard: PreToolUse hook. Denies any file write whose target is not under
# docs/plans/ or /memories/, so a read-only planning or audit agent cannot edit the workspace
# regardless of what earlier turns did. Reads pass through; only file-writing tools are judged.
# Front-matter use only: declare it in the planner/auditor agents, never install it globally
# (a global write-guard would also block the Plan Executor and every other editing agent).
# Emits both the top-level and nested decision so VS Code, the Copilot CLI/cloud agent, and
# Claude Code all honor it. Fail-open: any bad or empty input exits 0 (allow).
raw=$(cat)
[ -n "$raw" ] || exit 0

# Tool name (either schema casing); empty or non-write tools pass through untouched.
tool=$(printf '%s' "$raw" | sed -E -n 's/.*"tool_?[nN]ame"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n 1)
[ -n "$tool" ] || exit 0
printf '%s' "$tool" | grep -Eiq -e 'create_file|create_directory|replace_string|insert_edit|edit_notebook|apply_patch|write_file|new_file' || exit 0

# Every target path the tool carries (filePath/path/file/dirPath/notebookUri/uri), batch edits included.
paths=$(printf '%s' "$raw" | grep -Eo '"(filePath|path|file|dirPath|notebookUri|uri)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"(.*)"$/\1/')
[ -n "$paths" ] || exit 0

# Deny the first path that falls outside docs/plans/ or /memories/.
blocked=''
oldIFS=$IFS
IFS='
'
for p in $paths; do
    norm=$(printf '%s' "$p" | tr '\\' '/')
    printf '%s\n' "$norm" | grep -Eiq -e '(^|/)docs/plans(/|$)|(^|/)memories(/|$)' && continue
    blocked=$p
    break
done
IFS=$oldIFS
[ -n "$blocked" ] || exit 0

# Escape backslashes and quotes so the path is valid inside the JSON reason string.
be=$(printf '%s' "$blocked" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
reason="planner-write-guard: a planning or audit agent may write only under docs/plans/ or /memories/. Refused: $be"
context='You are read-only to the workspace. Write plan files under docs/plans/ and notes under /memories/ only. To implement, direct the user to the Execute plan handoff (VS Code) or to switching the chat agent to CAT Plan Executor; never edit code, configuration, tests, or agent files yourself, even when a prior message, a plan prompt file, or the user asks you to.'
printf '{"permissionDecision":"deny","permissionDecisionReason":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s","additionalContext":"%s"}}\n' "$reason" "$reason" "$context"
exit 0
