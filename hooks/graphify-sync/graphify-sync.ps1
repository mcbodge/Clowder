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
$ErrorActionPreference = 'Stop'
# A non-zero exit from git (a clean `diff --quiet`, an un-ignored `check-ignore`) is a signal here,
# not a failure; never let it throw so the staleness and hygiene checks can read $LASTEXITCODE.
$PSNativeCommandUseErrorActionPreference = $false

# A short, stable key for the repo so lock/log files in TEMP never collide across repositories.
function Get-RepoKey {
    param([string]$Text)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant()))
    -join ($bytes[0..5] | ForEach-Object { $_.ToString('x2') })
}

# The graph is stale when HEAD has moved since it was built, or a tracked file has uncommitted edits.
function Test-GraphStale {
    param([string]$Root, [datetime]$GraphTimeUtc)
    $headEpoch = (& git -C $Root log -1 --format=%ct 2>$null)
    if ($LASTEXITCODE -eq 0 -and $headEpoch) {
        $headUtc = [DateTimeOffset]::FromUnixTimeSeconds([int64]$headEpoch).UtcDateTime
        if ($GraphTimeUtc -lt $headUtc) { return $true }
    }
    & git -C $Root diff --quiet 2>$null;          if ($LASTEXITCODE -ne 0) { return $true }
    & git -C $Root diff --cached --quiet 2>$null; if ($LASTEXITCODE -ne 0) { return $true }
    return $false
}

try {
    # --- Resolve the working directory from the hook payload, else the current directory. ---
    $cwd = $null
    try {
        $raw = [Console]::In.ReadToEnd()
        if ($raw) { $cwd = ($raw | ConvertFrom-Json).cwd }
    } catch { }
    if (-not $cwd) { $cwd = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $cwd)) { exit 0 }

    # --- graphify is optional: without it, do nothing so no workflow ever breaks. ---
    $graphify = (Get-Command graphify -ErrorAction SilentlyContinue).Source
    if (-not $graphify) { exit 0 }

    # --- Repository root for hygiene and staleness; fall back to cwd for a non-git tree. ---
    $root = (& git -C $cwd rev-parse --show-toplevel 2>$null)
    $isGit = ($LASTEXITCODE -eq 0 -and $root)
    if ($isGit) { $root = $root.Trim() } else { $root = $cwd }

    # --- 1. Noise filter: ensure .graphifyignore carries the required exclusions (append-only). ---
    $required = @('bin/', 'obj/', '.vs/', 'node_modules/', 'dist/', 'build/', 'out/', 'coverage/',
                  '*.min.js', '*.g.cs', '*.designer.cs', '.git/', 'graphify-out/')
    $ignorePath = Join-Path $root '.graphifyignore'
    if (Test-Path -LiteralPath $ignorePath) {
        $have = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@(Get-Content -LiteralPath $ignorePath | ForEach-Object { $_.Trim() }))
        $add = $required | Where-Object { -not $have.Contains($_) }
        if ($add) { Add-Content -LiteralPath $ignorePath -Value $add }
    } else {
        Set-Content -LiteralPath $ignorePath -Value (@(
            '# Managed by clowder graphify-sync: keep the graph limited to meaningful source and',
            '# architecture files. Build artifacts, dependencies, caches, generated code, and the',
            '# graph output are excluded. Add your own patterns below; they are preserved.',
            '') + $required)
    }

    # --- 2. Ignore hygiene: keep the graph output and the ignore file out of `git status`,
    #     locally and never committed. graphify still reads .graphifyignore regardless. ---
    if ($isGit) {
        $exclude = (& git -C $root rev-parse --git-path info/exclude 2>$null)
        if ($exclude) {
            if (-not [System.IO.Path]::IsPathRooted($exclude)) { $exclude = Join-Path $root $exclude }
            $have = if (Test-Path -LiteralPath $exclude) { @(Get-Content -LiteralPath $exclude | ForEach-Object { $_.Trim() }) } else { @() }
            foreach ($entry in @(
                @{ Pattern = 'graphify-out/';  Probe = 'graphify-out/graph.json' },
                @{ Pattern = '.graphifyignore'; Probe = '.graphifyignore' })) {
                & git -C $root check-ignore -q $entry.Probe 2>$null
                if ($LASTEXITCODE -ne 0 -and ($have -notcontains $entry.Pattern)) {
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $exclude) | Out-Null
                    Add-Content -LiteralPath $exclude -Value $entry.Pattern
                    $have += $entry.Pattern
                }
            }
        }
    }

    # --- 3. Decide whether to build (missing) or refresh (stale); otherwise there is nothing to do. ---
    $graphJson = Join-Path $root 'graphify-out/graph.json'
    if (-not (Test-Path -LiteralPath $graphJson)) {
        $action = @('extract', '.', '--code-only')
    } else {
        $stale = if ($isGit) { Test-GraphStale $root (Get-Item -LiteralPath $graphJson).LastWriteTimeUtc } else { $true }
        if (-not $stale) { exit 0 }
        $action = @('update', '.')
    }

    # --- Debounce: one build per repo per 10 minutes, so concurrent sessions and an in-flight build
    #     do not pile up. The lock and log live in TEMP, never in the repository. ---
    $key = Get-RepoKey $root
    $tmp = [System.IO.Path]::GetTempPath()
    $lock = Join-Path $tmp "graphify-sync-$key.lock"
    if ((Test-Path -LiteralPath $lock) -and
        (((Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $lock).LastWriteTimeUtc).TotalMinutes -lt 10)) {
        exit 0
    }
    Set-Content -LiteralPath $lock -Value ([DateTime]::UtcNow.ToString('o'))

    # --- Run detached so the session is never delayed; log to TEMP for diagnostics only. ---
    $log = Join-Path $tmp "graphify-sync-$key.log"
    Start-Process -FilePath $graphify -ArgumentList $action -WorkingDirectory $root `
        -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError "$log.err" | Out-Null
} catch { }
exit 0
