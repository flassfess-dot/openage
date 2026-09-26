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
    'res://tests/unit/test_ror_skirmish_settings.gd',
    'res://tests/unit/test_full_tech_tree_rules.gd',
    'res://tests/unit/test_ror_random_map_profiles.gd',
    'res://tests/unit/test_random_map_profiles.gd',
    'res://tests/golden/test_ror_map_profile_contract.gd',
    'res://tests/unit/test_ror_gigantic_generation_budget.gd',
    'res://tests/unit/test_skirmish_settings.gd',
    'res://tests/unit/test_random_map_generator.gd',
    'res://tests/unit/test_technology_and_ages.gd',
    'res://tests/unit/test_production_availability.gd',
    'res://tests/unit/test_match_definition.gd',
    'res://tests/integration/test_generated_alliance_victory.gd',
    'res://tests/scenarios/test_generated_naval_ai_acceptance.gd'
)

if ($FromTest -and $FromStage -ne 'impact') {
    throw 'FromTest is valid only for the impact stage.'
}
if ($FromTest) {
    $startIndex = [Array]::IndexOf($impactTests, $FromTest)
    if ($startIndex -lt 0) {
        throw "Impact test is not in the P09 list: $FromTest"
    }
    $impactTests = @($impactTests | Select-Object -Skip $startIndex)
}
foreach ($runner in @($targetedRunner, $fullRunner)) {
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Required runner is missing: $runner"
    }
}

if ($FromStage -eq 'impact') {
    Write-Host "P09 IMPACT: $($impactTests.Count) tests"
    foreach ($test in $impactTests) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetedRunner -TestScript $test
        if ($LASTEXITCODE -ne 0) {
            throw "P09 impact test failed: $test. Resume with -FromTest '$test' after fixing it."
        }
    }
}

Write-Host 'P09 FULL SUITE: unit, integration, scenario and golden tests'
if ($FullStartAt) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner -StartAt $FullStartAt
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner
}
if ($LASTEXITCODE -ne 0) {
    throw 'P09 full suite failed. Resume with -FromStage full -FullStartAt <test path> after fixing it.'
}

Write-Host 'P09 validation passed. Source UI calibration and P14 performance optimization remain separate gates.'
exit 0
