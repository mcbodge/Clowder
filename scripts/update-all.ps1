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
  Install into this repository's .github folder (agents, instructions, skills) instead of your
  user profile. One method per run: with ProjectDir set, nothing is written to ~/.copilot or the
  editor prompt folders, and companion tools are not touched.
#>
param(
    [string]$RepoDir = $env:CLOWDER_DIR,
    [string]$Url     = $(if ($env:CLOWDER_URL) { $env:CLOWDER_URL } else { 'https://github.com/mcbodge/clowder.git' }),
    [string]$ProjectDir
)

# Native tools (git/npm/gh/uv) print progress to stderr; keep that from aborting the run.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

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

# Create the destination (unless -OnlyIfPresent) and copy one or more source globs or files into it.
function Install-Set {
    param(
        [string[]]$Source,
        [string]$Dest,
        [switch]$Recurse,
        [switch]$OnlyIfPresent
    )
    if ($OnlyIfPresent) {
        if (-not (Test-Path $Dest)) { return }
    } else {
        New-Item -ItemType Directory -Force $Dest | Out-Null
    }
    Copy-Item $Source $Dest -Recurse:$Recurse -Force -ErrorAction Stop
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

# Project mode: install into a repository's .github folder only, then stop (one method per run).
if ($ProjectDir) {
    if (-not (Test-Path $ProjectDir)) { Write-Error "ProjectDir '$ProjectDir' not found."; exit 1 }
    $gh = Join-Path $ProjectDir '.github'
    Install-Set -Source "$repo\agents\*.agent.md" -Dest "$gh\agents"
    Install-Set -Source "$repo\instructions\*.instructions.md" -Dest "$gh\instructions"
    Install-Set -Source "$repo\skills\*" -Dest "$gh\skills" -Recurse
    Write-Host "==> Installed into $gh (agents, instructions, skills)." -ForegroundColor Green
    exit 0
}

# 3. Copy this repo's pieces into the user profile.
Install-Set -Source "$repo\agents\*.agent.md" -Dest "$copilot\agents"
Install-Set -Source "$repo\skills\*" -Dest "$copilot\skills" -Recurse
Install-Set -Source "$repo\hooks\git-guard\git-guard.ps1", "$repo\hooks\git-guard\git-guard.sh", "$repo\hooks\env-guard\env-guard.ps1", "$repo\hooks\env-guard\env-guard.sh", "$repo\hooks\planner-write-guard\planner-write-guard.ps1", "$repo\hooks\planner-write-guard\planner-write-guard.sh" -Dest "$copilot\hooks"
# Refresh the global git-guard and env-guard hooks only if you opted into them.
Install-Set -Source "$repo\hooks\git-guard\hooks.json" -Dest "$copilot\hooks\git-guard.json" -OnlyIfPresent
Install-Set -Source "$repo\hooks\env-guard\hooks.json" -Dest "$copilot\hooks\env-guard.json" -OnlyIfPresent
# Instructions: the CLI reads ~/.copilot/instructions; VS Code reads the profile's prompts folder.
Install-Set -Source "$repo\instructions\*.instructions.md" -Dest "$copilot\instructions"
Install-Set -Source "$repo\instructions\*.instructions.md" -Dest "$env:APPDATA\Code\User\prompts" -OnlyIfPresent
Install-Set -Source "$repo\instructions\*.instructions.md" -Dest "$env:APPDATA\Code - Insiders\User\prompts" -OnlyIfPresent

# 4. Update external companion tools when their CLIs are present.
if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm install -g '@playwright/cli@latest'
    if (Get-Command playwright-cli -ErrorAction SilentlyContinue) { playwright-cli install --skills }
} else { Write-Warning "npm not found; skipping playwright-cli." }

if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh skills install github/awesome-copilot azure-devops-cli
} else { Write-Warning "GitHub CLI (gh) not found; skipping the azure-devops-cli skill." }

if (Get-Command uv -ErrorAction SilentlyContinue) {
    uv tool upgrade graphifyy
    if ($LASTEXITCODE -ne 0) { uv tool install graphifyy }
} else { Write-Warning "uv not found; skipping graphify." }

Write-Host "==> Done." -ForegroundColor Green
