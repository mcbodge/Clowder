<#
.SYNOPSIS
  Guard against drift between base agents and their (MudBlazor)/(DevOps) variants.
.DESCRIPTION
  Each variant agent duplicates most of its base verbatim, with a few intentional
  deltas (frontmatter, a MudBlazor MCP step, executor selection). VS Code agents have
  no include mechanism, so a base edit must be mirrored into the variant by hand.
  This script asserts that every <section> block the two files share is byte-identical
  (line endings normalized), and lists any that drifted. Tags that are meant to differ
  are listed per pair in $Pairs[].Allow; bare HTML tags from embedded examples are
  ignored via $HtmlTags.
  Exit code: 0 in sync, 1 on drift, 2 on a missing file. Runs on Windows PowerShell
  5.1 and pwsh (Linux/macOS, CI).
.PARAMETER RepoDir
  Repository root. Defaults to the parent of this script's folder.
#>
[CmdletBinding()]
param(
    [string]$RepoDir
)

$ErrorActionPreference = 'Stop'

if (-not $RepoDir) {
    if ($PSScriptRoot) { $RepoDir = Split-Path -Parent $PSScriptRoot }
    else { $RepoDir = (Get-Location).Path }
}
$agentsDir = Join-Path $RepoDir 'agents'
if (-not (Test-Path $agentsDir)) { Write-Error "agents folder not found under $RepoDir"; exit 2 }

# base -> variant pairs. Allow lists the <section> tags whose difference is intentional
# (the MudBlazor/DevOps deltas: a MudBlazor MCP step, executor selection, agent-value checks).
# Frontmatter and prose outside <section> tags are never compared.
# shortcut: Allow skips a whole section, so drift inside an intentionally-differing section
# (e.g. the single agent line in <template>) is not caught; add a line-level normalizer if that bites.
$Pairs = @(
    @{ Base = 'cat-planner.agent.md';        Variant = 'cat-planner-mudblazor.agent.md';        Allow = @('workflow','template','validation') }
    @{ Base = 'cat-planner-devops.agent.md'; Variant = 'cat-planner-devops-mudblazor.agent.md'; Allow = @('tool_usage','workflow','validation','review_summary','template') }
    @{ Base = 'cat-plan-executor.agent.md';  Variant = 'cat-plan-executor-mudblazor.agent.md';  Allow = @('hard_rules') }
)

# Bare block/inline HTML tags appear inside fenced examples; they are not agent sections.
$HtmlTags = @('div','p','ul','ol','li','strong','em','a','img','code','pre','span',
              'b','i','br','hr','h1','h2','h3','h4','h5','h6','table','thead','tbody',
              'tr','td','th','blockquote')

function Get-Sections {
    param([string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw
    $map = [ordered]@{}
    foreach ($m in [regex]::Matches($text, '(?s)<([a-z0-9_]+)>(.*?)</\1>')) {
        $tag = $m.Groups[1].Value
        if ($HtmlTags -contains $tag) { continue }
        if (-not $map.Contains($tag)) { $map[$tag] = ($m.Groups[2].Value -replace "`r", '') }
    }
    return $map
}

$drift = @()
$gateReference = $null
foreach ($name in @('cat-planner', 'cat-planner-mudblazor', 'cat-planner-devops', 'cat-planner-devops-mudblazor', 'cat-auditor')) {
    $file = Join-Path $agentsDir ($name + '.agent.md')
    $text = (Get-Content -LiteralPath $file -Raw) -replace "`r", ''
    $gate = [regex]::Match($text, '(?ms)^<clarification_gate>\n(.*?)^</clarification_gate>').Groups[1].Value
    if (-not $gateReference) { $gateReference = $gate }
    $clauses = @('bounded read-only discovery pass first', 'immediately invoke', 'one call batching independent',
        'before any long recap, plan draft or final response', 'actual native tool limit or answer-dependent',
        'no equivalent native interactive tool genuinely exists', '<=3 blocking questions',
        'Tool failure, deferred discovery, inconvenience or a missing response is not unavailability')
    if (-not $gate -or $gate -ne $gateReference) { throw "Missing or divergent clarification gate: $name" }
    foreach ($clause in $clauses) { if (-not $gate.Contains($clause)) { throw "Missing protocol clause '$clause': $name" } }
    $front = ($text -split '---', 3)[1]
    if ($front -notmatch '(?m)^tools:.*vscode/askQuestions') { throw "Missing native clarification tool: $name" }
    if ($text -match 'batch at most 3|Intent-only questions .*go straight to the user|Ask questions only via') {
        throw "Contradictory legacy clarification rule: $name"
    }
}
Write-Host '  Five planning agents share the discovery-complete clarification protocol (static check only).'
foreach ($pair in $Pairs) {
    $basePath = Join-Path $agentsDir $pair.Base
    $varPath  = Join-Path $agentsDir $pair.Variant
    foreach ($p in @($basePath, $varPath)) {
        if (-not (Test-Path $p)) { Write-Error "missing agent file: $p"; exit 2 }
    }
    $baseSecs = Get-Sections $basePath
    $varSecs  = Get-Sections $varPath
    $compared = 0
    foreach ($tag in $baseSecs.Keys) {
        if (-not $varSecs.Contains($tag)) { continue }
        if ($pair.Allow -contains $tag) { continue }
        $compared++
        if ($baseSecs[$tag] -ne $varSecs[$tag]) {
            $drift += [pscustomobject]@{ Pair = "$($pair.Base) -> $($pair.Variant)"; Section = "<$tag>" }
        }
    }
    Write-Host ("  {0,-55} {1} shared sections checked" -f $pair.Variant, $compared)
}

if ($drift.Count -eq 0) {
    Write-Host "OK: every shared agent section is in sync." -ForegroundColor Green
    exit 0
}
Write-Host ""
Write-Host "DRIFT: a base agent and its variant disagree on a shared section:" -ForegroundColor Red
foreach ($d in $drift) { Write-Host ("  {0,-16} in  {1}" -f $d.Section, $d.Pair) -ForegroundColor Red }
Write-Host "Mirror the base edit into the variant, or add the tag to that pair's Allow list if the difference is intentional." -ForegroundColor Yellow
exit 1
