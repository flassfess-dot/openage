[CmdletBinding()]
param(
    [string]$StatePath = "doc/ror-modern/AI_COMPETITIVE_EXECUTION_STATE_2026-10-29.json",
    [switch]$Resume,
    [string[]]$Tests = @()
)
$ErrorActionPreference = "Stop"
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $taskRoot
try {
    & py -3 tools/ai_competitive.py preflight
    if ($LASTEXITCODE -ne 0) { throw 'Preflight failed' }
    $taskState = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    $taskNext = $taskState.stages.tasks | Where-Object { $_.status -ne 'passed' } | Select-Object -First 1
    Write-Output ("Next task: {0} - {1}" -f $taskNext.id, $taskNext.description)
    if ($Tests.Count -gt 0) {
        & py -3 tools/ai_competitive.py tests @Tests
        if ($LASTEXITCODE -ne 0) { throw 'Selected regression checks failed' }
    }
} finally { Pop-Location }
