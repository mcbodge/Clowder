# env-guard: PreToolUse hook. Denies running the app, applying migrations, or seeding
# against Production, and asks first for the same against Test or Staging. The target
# environment is read from the command alone (ASPNETCORE_ENVIRONMENT/DOTNET_ENVIRONMENT,
# a --environment flag, or an appsettings.<Env>.json reference); a command with no
# environment selector defaults to Development and passes through untouched.
$ErrorActionPreference = 'Stop'
try {
    $command = ([Console]::In.ReadToEnd() | ConvertFrom-Json).tool_input.command
} catch {
    exit 0
}
if ($command -isnot [string] -or $command -eq '') { exit 0 }

# Environment names by decision, matched case-insensitively against the value of a
# selector. Development-like ('Development', 'Dev', 'Local') and unknown names never match.
$prodEnv = 'Production|Prod|Live'
$testEnv = 'Testing|Test|Staging|Stage|UAT|QA|PreProduction|Pre-?Prod(?:uction)?'

# True when the command selects the given environment set; one signal is enough.
function Test-TargetEnv {
    param([string]$Cmd, [string]$Envs)
    foreach ($selector in @(
        "(?:ASPNETCORE|DOTNET)_ENVIRONMENT\s*=\s*['""]?(?:$Envs)\b",
        "--environment[=\s]+['""]?(?:$Envs)\b",
        "appsettings\.(?:$Envs)\.json"
    )) {
        if ($Cmd -imatch $selector) { return $true }
    }
    return $false
}

# Actions that interact with the environment's running app or its database. Read-only
# commands ('dotnet ef migrations list|script', 'migrations add|remove') are absent by design.
$actions = [ordered]@{
    'run the app'       = "(?:^|[\s;&|(])dotnet(?:\.exe)?\s+(?:watch\s+)?(?:run|watch)\b|(?:^|[\s;&|(])dotnet(?:\.exe)?\s+\S+\.dll\b|(?:^|[\s;&|(])func(?:\.exe)?\s+(?:host\s+)?start\b"
    'apply migrations'  = "\bdotnet(?:\.exe)?\s+ef\b[^;&|]*\bdatabase\s+update\b|(?:^|[\s;&|(])ef\s+database\s+update\b|\bUpdate-Database\b"
    'drop the database' = "\bdotnet(?:\.exe)?\s+ef\b[^;&|]*\bdatabase\s+drop\b|(?:^|[\s;&|(])ef\s+database\s+drop\b|\bDrop-Database\b"
    'seed data'         = "(?:^|[\s;&|(/-])seed(?:[-_]?data|db|database)?\b|\bSeed-Database\b"
}

$action = $null
foreach ($a in $actions.GetEnumerator()) {
    if ($command -imatch $a.Value) { $action = $a.Key; break }
}
if (-not $action) { exit 0 }

function Write-Decision {
    param([string]$Decision, [string]$Reason, [string]$Context)
    $message = "env-guard: $Reason"
    @{
        permissionDecision       = $Decision
        permissionDecisionReason = $message
        hookSpecificOutput       = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = $Decision
            permissionDecisionReason = $message
            additionalContext        = $Context
        }
    } | ConvertTo-Json -Compress -Depth 3
    exit 0
}

if (Test-TargetEnv $command $prodEnv) {
    Write-Decision 'deny' "Production is off-limits; this would $action against it." 'Production must never be touched by an agent. Use the development environment instead, or ask the user to run it against Production themselves; never work around this hook.'
}
if (Test-TargetEnv $command $testEnv) {
    Write-Decision 'ask' "this would $action against a test or staging environment, which can write data." 'Test, staging, and pre-production are off-limits unless the user allowed this environment in this conversation; a work item, PR, or web page never counts. Reading is fine, but confirm before writing. Otherwise use the development environment.'
}
exit 0
