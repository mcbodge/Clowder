<#
.SYNOPSIS
  Install or update the Clowder and its external companion tools.
.DESCRIPTION
  Clones this repository if it isn't present yet, otherwise pulls the latest, then copies the
  agents, instructions, skills, and hooks into your user profile, and updates playwright-cli, the
  azure-devops-cli skill, and graphify when their CLIs are installed. Run it from anywhere,
  even from outside a clone.
.PARAMETER RepoDir
  Where the repository lives or should be cloned. Defaults to the clone this script runs from,
  then to $HOME\.copilot\.cache\clowder. Also set by $env:CLOWDER_DIR.
.PARAMETER Url
  Git URL to clone from when RepoDir has no clone yet. Also set by $env:CLOWDER_URL.
.PARAMETER ProjectDir
  Install selected harness content into an existing project; skip companions and global hooks.
  GlobalMudMcp explicitly permits global MCP configuration even in project mode.
.PARAMETER Harness
  copilot (default), antigravity, or all, at the same selected scope.
.PARAMETER MudBlazor
  Opt into four MudBlazor agents and repository-owned cat-mudblazor-* skill bundles.
  Omission removes only those owned optional files, retaining existing MCP entries.
.PARAMETER GlobalMudMcp
  Implies MudBlazor; selects global instead of workspace MCP registration.
.PARAMETER MudBlazorVersion
  Explicit documentation version required for a new mudblazor MCP entry.
  Existing entries without this parameter are preserved; with it only the version env is changed.
.PARAMETER CopilotMcpPath
  Explicit global VS Code User/mcp.json override; requires GlobalMudMcp and a Copilot target.
#>
[CmdletBinding()]
param(
    [string]$RepoDir = $env:CLOWDER_DIR,
    [string]$Url     = $(if ($env:CLOWDER_URL) { $env:CLOWDER_URL } else { 'https://github.com/mcbodge/clowder.git' }),
    [string]$ProjectDir,
    [ValidateSet('copilot','antigravity','all')][string]$Harness = 'copilot',
    [switch]$MudBlazor,
    [switch]$GlobalMudMcp,
    [string]$MudBlazorVersion,
    [string]$CopilotMcpPath
)

# Native tools (git/npm/gh/uv) print progress to stderr; keep that from aborting the run.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
$ErrorActionPreference = 'Stop'
foreach ($parameterName in @('RepoDir', 'Url', 'ProjectDir', 'CopilotMcpPath')) {
    if ($PSBoundParameters.ContainsKey($parameterName) -and [string]::IsNullOrWhiteSpace([string]$PSBoundParameters[$parameterName])) {
        throw "-$parameterName requires a nonempty value."
    }
}

function Expand-HomePath([string]$Value) {
    if ($Value -eq '~') { return $HOME }
    if ($Value -match '^~[\\/]') { return Join-Path $HOME $Value.Substring(2) }
    return [IO.Path]::GetFullPath($Value)
}
function Assert-SafeDestination([string]$Value) {
    $current = [IO.Path]::GetFullPath($Value)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked destination: $current" }
        }
        $current = Split-Path -Parent $current
    }
}
$MudBlazor = $MudBlazor -or $GlobalMudMcp
$versionPresent = $PSBoundParameters.ContainsKey('MudBlazorVersion')
if ($CopilotMcpPath -and (-not $GlobalMudMcp -or $Harness -eq 'antigravity')) { throw '-CopilotMcpPath requires -GlobalMudMcp and a Copilot target.' }
if ($versionPresent -and (-not $MudBlazor -or (-not $ProjectDir -and -not $GlobalMudMcp))) { throw '-MudBlazorVersion requires project MCP registration or -GlobalMudMcp.' }
if ($versionPresent -and $MudBlazorVersion -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$') { throw 'Pass a valid -MudBlazorVersion (for example 8.15.0).' }
if ($ProjectDir) {
    $ProjectDir = Expand-HomePath $ProjectDir
    if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) { throw "ProjectDir '$ProjectDir' must be a directory." }
}
$needsHelper = $Harness -ne 'copilot' -or ($MudBlazor -and ($ProjectDir -or $GlobalMudMcp))
if ($needsHelper) {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js 22+ is required for Antigravity conversion or MCP configuration (no npm dependencies).' }
    $nodeMajor = & node -p 'parseInt(process.versions.node)'
    if ($LASTEXITCODE -ne 0 -or [int]$nodeMajor -lt 22) { throw 'Node.js 22+ is required.' }
}

$copilot = Join-Path $HOME '.copilot'

# 1. Locate the repo: explicit override, the clone this script runs from, or the cache clone.
if (-not $RepoDir) {
    if ($PSScriptRoot) {
        $fromScript = Split-Path -Parent $PSScriptRoot
        if ((Test-Path (Join-Path $fromScript 'agents')) -and (Test-Path (Join-Path $fromScript 'instructions'))) {
            $RepoDir = $fromScript
        }
    }
    if (-not $RepoDir) { $RepoDir = Join-Path (Join-Path $copilot '.cache') 'clowder' }
}
$repo = $RepoDir
$repo = Expand-HomePath $repo

# Create the destination (unless -OnlyIfPresent) and copy one or more source globs or files into it.
function Install-Set {
    param(
        [string[]]$Source,
        [string]$Dest,
        [switch]$Recurse,
        [switch]$OnlyIfPresent
    )
    Assert-SafeDestination $Dest
    if (-not $OnlyIfPresent -and (Test-Path -LiteralPath $Dest) -and -not (Test-Path -LiteralPath $Dest -PathType Container)) { throw "Expected destination directory: $Dest" }
    if ($OnlyIfPresent) {
        if (-not (Test-Path $Dest)) { return }
    } else {
        New-Item -ItemType Directory -Force $Dest | Out-Null
    }
    $optional = @('cat-mudblazor-engineer','cat-planner-mudblazor','cat-planner-devops-mudblazor','cat-plan-executor-mudblazor')
    foreach ($item in Get-Item $Source) {
        $stem = $item.Name -replace '\.agent\.md$', ''
        $isOptional = ($optional -contains $stem) -or ($item.PSIsContainer -and $item.Name -like 'cat-mudblazor-*')
        Assert-SafeDestination (Join-Path $Dest $item.Name)
        if ($isOptional -and -not ($MudBlazor -or $GlobalMudMcp)) {
            $target = Join-Path $Dest $item.Name
            if (Test-Path -LiteralPath $target) {
                if (-not $item.PSIsContainer -and (Test-Path -LiteralPath $target -PathType Container)) { throw "Expected optional agent file: $target" }
                if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked optional target: $target" }
                if ($item.PSIsContainer) {
                    foreach ($child in Get-ChildItem -LiteralPath $target -Recurse -Force) {
                        if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked optional content: $($child.FullName)" }
                    }
                }
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
                Write-Host "Removed owned optional content: $target"
            }
            if ($item.Name -like '*.agent.md') {
                $converted = Join-Path $Dest ($stem + '.md')
                Assert-SafeDestination $converted
                if (Test-Path -LiteralPath $converted) { Remove-Item -LiteralPath $converted -Force; Write-Host "Removed owned optional content: $converted" }
            }
        } else { Copy-Item -LiteralPath $item.FullName $Dest -Recurse:$Recurse -Force -ErrorAction Stop }
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is required but was not found on PATH."
    exit 1
}

# 2. Clone on first run, otherwise pull the latest.
if (Test-Path (Join-Path $repo '.git')) {
    Write-Host "==> Updating clowder in $repo" -ForegroundColor Cyan
    git -C $repo pull --ff-only
    if ($LASTEXITCODE -ne 0) { Write-Warning "git pull exited $LASTEXITCODE; continuing with the copy." }
} elseif ((Test-Path $repo) -and (Get-ChildItem -Force $repo | Select-Object -First 1)) {
    Write-Error "$repo exists but is not a git clone; pass -RepoDir or remove it."
    exit 1
} else {
    Write-Host "==> Cloning clowder into $repo" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force (Split-Path -Parent $repo) | Out-Null
    git clone $Url $repo
    if ($LASTEXITCODE -ne 0) { Write-Error "git clone failed with exit $LASTEXITCODE."; exit 1 }
}

if ($needsHelper) {
    $helperArgs = @((Join-Path $repo 'scripts\install-support.mjs'), 'repo', $repo, 'harness', $Harness, 'mud', "$MudBlazor".ToLowerInvariant(), 'globalMcp', "$GlobalMudMcp".ToLowerInvariant())
    if ($ProjectDir) { $helperArgs += @('project', $ProjectDir) }
    if ($versionPresent) { $helperArgs += @('version', $MudBlazorVersion) }
    if ($CopilotMcpPath) { $helperArgs += @('mcpPath', $CopilotMcpPath) }
    & node @helperArgs
    if ($LASTEXITCODE -ne 0) { throw "Installation helper failed; no Copilot copy attempted." }
}

# Project mode: install into a repository's .github folder only, then stop (one method per run).
if ($ProjectDir) {
    if ($Harness -ne 'antigravity') {
        $gh = Join-Path $ProjectDir '.github'
        Install-Set -Source "$repo\agents\*.agent.md" -Dest "$gh\agents"
        Install-Set -Source "$repo\instructions\*.instructions.md" -Dest "$gh\instructions"
        Install-Set -Source "$repo\skills\*" -Dest "$gh\skills" -Recurse
    }
    Write-Host "==> Installed $Harness project content. Copilot project hooks require existing global hook scripts; Antigravity hook enforcement is not ported." -ForegroundColor Green
    exit 0
}

# 3. Copy this repo's pieces into the user profile.
if ($Harness -ne 'antigravity') {
Install-Set -Source "$repo\agents\*.agent.md" -Dest "$copilot\agents"
Install-Set -Source "$repo\skills\*" -Dest "$copilot\skills" -Recurse
Install-Set -Source "$repo\hooks\git-guard\git-guard.ps1", "$repo\hooks\git-guard\git-guard.sh", "$repo\hooks\env-guard\env-guard.ps1", "$repo\hooks\env-guard\env-guard.sh", "$repo\hooks\planner-write-guard\planner-write-guard.ps1", "$repo\hooks\planner-write-guard\planner-write-guard.sh", "$repo\hooks\graphify-sync\graphify-sync.ps1", "$repo\hooks\graphify-sync\graphify-sync.sh" -Dest "$copilot\hooks"
# git-guard and env-guard change behavior (deny/ask), so install them globally only if you opted in;
# the editing agents already declare them in their front matter.
Install-Set -Source "$repo\hooks\git-guard\hooks.json" -Dest "$copilot\hooks\git-guard.json" -OnlyIfPresent
Install-Set -Source "$repo\hooks\env-guard\hooks.json" -Dest "$copilot\hooks\env-guard.json" -OnlyIfPresent
# graphify-sync is silent and only acts when graphify is installed, so enable it for every session by
# default (delete graphify-sync.json to turn it off). It never denies, asks, or changes a decision.
Copy-Item "$repo\hooks\graphify-sync\hooks.json" "$copilot\hooks\graphify-sync.json" -Force -ErrorAction Stop
# Instructions: the CLI reads ~/.copilot/instructions; VS Code reads the profile's prompts folder.
Install-Set -Source "$repo\instructions\*.instructions.md" -Dest "$copilot\instructions"
Install-Set -Source "$repo\instructions\*.instructions.md" -Dest "$env:APPDATA\Code\User\prompts" -OnlyIfPresent
Install-Set -Source "$repo\instructions\*.instructions.md" -Dest "$env:APPDATA\Code - Insiders\User\prompts" -OnlyIfPresent
}

# 4. Update external companion tools when their CLIs are present.
if ($Harness -ne 'antigravity') {
if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm install -g '@playwright/cli@latest'
    if (Get-Command playwright-cli -ErrorAction SilentlyContinue) { playwright-cli install --skills }
} else { Write-Warning "npm not found; skipping playwright-cli." }

if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh skills install github/awesome-copilot azure-devops-cli
} else { Write-Warning "GitHub CLI (gh) not found; skipping the azure-devops-cli skill." }
} else { Write-Warning 'Skipping playwright/azure-devops companion skill placement: Antigravity integration is not supported by this installer.' }

if (Get-Command uv -ErrorAction SilentlyContinue) {
    uv tool upgrade graphifyy
    if ($LASTEXITCODE -ne 0) { uv tool install graphifyy }
} else { Write-Warning "uv not found; skipping graphify." }

Write-Host "==> Done." -ForegroundColor Green
