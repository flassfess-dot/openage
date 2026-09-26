[CmdletBinding()]
param(
    [ValidateSet('impact', 'full')]
    [string]$FromStage = 'impact',
    [string]$FromTest = '',
    [string]$FullStartAt = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$targetedRunner = Join-Path $PSScriptRoot 'ror-run-p00-targeted-tests.ps1'
$fullRunner = Join-Path $PSScriptRoot 'ror-run-tests.ps1'
$impactTests = @(
    'res://tests/unit/test_ai_ror_rule_adaptation.gd',
    'res://tests/unit/test_ai_player.gd',
    'res://tests/unit/test_logistics_population.gd',
    'res://tests/integration/test_ai_command_pipeline.gd',
    'res://tests/integration/test_transport_allied_cargo.gd',
    'res://tests/integration/test_transport_artifact.gd',
    'res://tests/scenarios/test_generated_skirmish_ai_acceptance.gd',
    'res://tests/scenarios/test_generated_naval_ai_acceptance.gd',
    'res://tests/scenarios/test_mixed_domain_ai_match.gd',
    'res://tests/scenarios/test_generated_skirmish_deterministic_outcome.gd'
)

if ($FromTest -and $FromStage -ne 'impact') {
    throw 'FromTest is valid only for the impact stage.'
}
if ($FromTest) {
    $startIndex = [Array]::IndexOf($impactTests, $FromTest)
    if ($startIndex -lt 0) {
        throw "Impact test is not in the P10 list: $FromTest"
    }
    $impactTests = @($impactTests | Select-Object -Skip $startIndex)
}
foreach ($runner in @($targetedRunner, $fullRunner)) {
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Required runner is missing: $runner"
    }
}

if ($FromStage -eq 'impact') {
    Write-Host "P10 IMPACT: $($impactTests.Count) tests"
    foreach ($test in $impactTests) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetedRunner -TestScript $test
        if ($LASTEXITCODE -ne 0) {
            throw "P10 impact test failed: $test. Resume with -FromTest '$test' after fixing it."
        }
    }
}

Write-Host 'P10 FULL SUITE: unit, integration, scenario and golden tests'
if ($FullStartAt) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner -StartAt $FullStartAt
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner
}
if ($LASTEXITCODE -ne 0) {
    throw 'P10 full suite failed. Resume with -FromStage full -FullStartAt <test path> after fixing it.'
}

Write-Host 'P10 validation passed. Source behavior review and P14 performance gate remain separate.'
exit 0
