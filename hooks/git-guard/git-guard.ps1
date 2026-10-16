# git-guard: PreToolUse hook that denies force pushes and bulk staging, and asks before commands that discard work.
$ErrorActionPreference = 'Stop'
try {
    $command = ([Console]::In.ReadToEnd() | ConvertFrom-Json).tool_input.command
} catch {
    exit 0
}
if ($command -isnot [string]) { exit 0 }

# Quoted text (commit messages, echo) can't trigger a rule.
$scan = $command -replace '"[^"]*"|''[^'']*''', ''

$git = '(?:^|[\s;&|(])git(?:\.exe)?(?:\s+(?:-C\s+\S+|-c\s+\S+|--[\w-]+(?:=\S+)?))*\s+'
$tail = '[^;&|\r\n]*?\s'
$end = '(?=[\s;&|)]|$)'
$bulk = '(?:\.[/\\]?|:/|\*)'
$rules = [ordered]@{
    deny = [ordered]@{
        "${git}push$tail(?:--force|-[a-zA-Z]*f|\+\S)"                           = 'force push rewrites shared history.'
        "${git}add$tail(?:--all|--update|-[a-zA-Z]*[Au][a-zA-Z]*|$bulk)$end"   = 'bulk staging can commit unrelated files.'
        "${git}commit$tail(?:--all|-[a-zA-Z]*a[a-zA-Z]*)$end"                   = 'git commit -a stages every tracked change.'
    }
    ask  = [ordered]@{
        "${git}reset$tail--hard$end"                  = 'git reset --hard discards uncommitted changes.'
        "${git}clean$tail(?:--force|-[a-zA-Z]*f)"     = 'git clean -f deletes untracked files.'
        "${git}(?:checkout|restore)$tail$bulk$end"    = 'this discards uncommitted changes in every file.'
        "${git}stash\s+(?:drop|clear)$end"            = 'this deletes stashed work.'
        "${git}branch$tail-[a-zA-Z]*D"                = 'git branch -D deletes a branch even if it is not merged.'
        "${git}push$tail(?:--delete|-[a-zA-Z]*d|:\S)" = 'this deletes a remote branch.'
    }
}
$context = @{
    deny = 'Stage the files you changed by explicit path (git add <path>) and push without --force. If a force push is really needed, ask the user to run it.'
    ask  = 'This can destroy work that may not be yours. Prefer a command limited to the paths or branches you created; otherwise let the user decide.'
}

foreach ($decision in $rules.Keys) {
    foreach ($rule in $rules[$decision].GetEnumerator()) {
        if ($scan -cmatch $rule.Key) {
            $message = "git-guard: $($rule.Value)"
            @{
                permissionDecision       = $decision
                permissionDecisionReason = $message
                hookSpecificOutput       = @{
                    hookEventName            = 'PreToolUse'
                    permissionDecision       = $decision
                    permissionDecisionReason = $message
                    additionalContext        = $context[$decision]
                }
            } | ConvertTo-Json -Compress -Depth 3
            exit 0
        }
    }
}
exit 0
