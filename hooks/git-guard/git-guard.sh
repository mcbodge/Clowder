#!/bin/sh
# git-guard: PreToolUse hook that denies force pushes and bulk staging, and asks before commands that discard work.
cmd=$(sed -E -n 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1)
[ -n "$cmd" ] || exit 0

# Quoted text (commit messages, echo) can't trigger a rule; JSON-escaped newlines separate commands.
cmd=$(printf '%s' "$cmd" | sed -e 's/\\"[^"]*\\"//g' -e "s/'[^']*'//g" -e 's/\\n/;/g')

git='(^|[[:space:];&|(])git(\.exe)?([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--[[:alnum:]-]+(=[^[:space:]]+)?))*[[:space:]]+'
tail='[^;&|]*[[:space:]]'
end='([[:space:];&|)]|$)'
bulk='(\./?|:/|\*)'

decide() {
  if [ "$1" = deny ]; then
    context='Stage the files you changed by explicit path (git add <path>) and push without --force. If a force push is really needed, ask the user to run it.'
  else
    context='This can destroy work that may not be yours. Prefer a command limited to the paths or branches you created; otherwise let the user decide.'
  fi
  printf '{"permissionDecision":"%s","permissionDecisionReason":"git-guard: %s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"git-guard: %s","additionalContext":"%s"}}\n' "$1" "$2" "$1" "$2" "$context"
  exit 0
}

matches() { printf '%s\n' "$cmd" | grep -Eq "$1"; }

matches "${git}push${tail}(--force|-[[:alpha:]]*f|\\+[^[:space:]])" && decide deny 'force push rewrites shared history.'
matches "${git}add${tail}(--all|--update|-[[:alpha:]]*[Au][[:alpha:]]*|${bulk})${end}" && decide deny 'bulk staging can commit unrelated files.'
matches "${git}commit${tail}(--all|-[[:alpha:]]*a[[:alpha:]]*)${end}" && decide deny 'git commit -a stages every tracked change.'
matches "${git}reset${tail}--hard${end}" && decide ask 'git reset --hard discards uncommitted changes.'
matches "${git}clean${tail}(--force|-[[:alpha:]]*f)" && decide ask 'git clean -f deletes untracked files.'
matches "${git}(checkout|restore)${tail}${bulk}${end}" && decide ask 'this discards uncommitted changes in every file.'
matches "${git}stash[[:space:]]+(drop|clear)${end}" && decide ask 'this deletes stashed work.'
matches "${git}branch${tail}-[[:alpha:]]*D" && decide ask 'git branch -D deletes a branch even if it is not merged.'
matches "${git}push${tail}(--delete|-[[:alpha:]]*d|:[^[:space:]])" && decide ask 'this deletes a remote branch.'
exit 0
