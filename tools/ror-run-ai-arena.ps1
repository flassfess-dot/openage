[CmdletBinding()]
param(
    [ValidateSet('smoke','dev','validation','holdout','challenge_holdout')][string]$Suite='smoke',
    [string]$Subject='competitive_v2',
    [ValidateSet('baseline_v1')][string]$Opponent='baseline_v1',
    [int]$Jobs=3,
    [int]$Limit=0,
    [switch]$Resume
)
$ErrorActionPreference='Stop'
$taskRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $taskRoot
try {
    & py -3 tools/ai_competitive.py manifests
    if ($LASTEXITCODE -ne 0) { throw 'Arena manifest preparation failed' }
    & py -3 tools/ai_competitive.py arena --suite $Suite --subject $Subject --jobs $Jobs --limit $Limit
    if ($LASTEXITCODE -ne 0) { throw 'Arena execution failed' }
} finally { Pop-Location }
