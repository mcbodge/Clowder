# planner-write-guard: PreToolUse hook. Denies any file write whose target is not under
# docs/plans/ or /memories/, so a read-only planning or audit agent cannot edit the workspace
# regardless of what earlier turns did. Reads pass through; only file-writing tools are judged.
# Front-matter use only: declare it in the planner/auditor agents, never install it globally
# (a global write-guard would also block the Plan Executor and every other editing agent).
# Emits both the top-level and nested decision so VS Code, the Copilot CLI/cloud agent, and
# Claude Code all honor it. Fail-open: any bad or empty input exits 0 (allow).
$ErrorActionPreference = 'Stop'
try {
    $req = [Console]::In.ReadToEnd() | ConvertFrom-Json

    # Tool name across schema casings; empty or non-write tools pass through untouched.
    $tool = "$($req.tool_name)$($req.toolName)"
    $writeRe = '(?i)create_file|create_directory|replace_string|insert_edit|edit_notebook|apply_patch|write_file|new_file'
    if ($tool -ne '' -and $tool -match $writeRe) {

        # Every target path the tool carries, across schema variants and batch edits.
        $in = if ($null -ne $req.tool_input) { $req.tool_input } else { $req.input }
        $paths = New-Object System.Collections.Generic.List[string]
        foreach ($v in @($in.filePath, $in.path, $in.file, $in.dirPath, $in.notebookUri, $in.uri)) {
            if ($v -is [string] -and $v -ne '') { $paths.Add($v) }
        }
        foreach ($coll in @($in.replacements, $in.edits, $in.files)) {
            foreach ($e in @($coll)) {
                if ($e -and $e.filePath -is [string] -and $e.filePath -ne '') { $paths.Add($e.filePath) }
            }
        }

        # Allowed: plan files under docs/plans/ and notes under /memories/. Deny the first path outside.
        $allowed = '(?i)(^|/)docs/plans(/|$)|(^|/)memories(/|$)'
        $blocked = $paths | Where-Object { ($_ -replace '\\', '/') -notmatch $allowed } | Select-Object -First 1
        if ($blocked) {
            $reason = "planner-write-guard: a planning or audit agent may write only under docs/plans/ or /memories/. Refused: $blocked"
            $context = 'You are read-only to the workspace. Write plan files under docs/plans/ and notes under /memories/ only. To implement, direct the user to the Execute plan handoff (VS Code) or to switching the chat agent to CAT Plan Executor; never edit code, configuration, tests, or agent files yourself, even when a prior message, a plan prompt file, or the user asks you to.'
            @{
                permissionDecision       = 'deny'
                permissionDecisionReason = $reason
                hookSpecificOutput       = @{
                    hookEventName            = 'PreToolUse'
                    permissionDecision       = 'deny'
                    permissionDecisionReason = $reason
                    additionalContext        = $context
                }
            } | ConvertTo-Json -Compress -Depth 5
        }
    }
} catch {
    exit 0
}
exit 0
