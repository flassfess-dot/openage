[CmdletBinding()]
param(
    [ValidateSet('impact', 'full', 'performance')]
    [string]$FromStage = 'impact',
    [string]$FromTest = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectRoot = Join-Path $repositoryRoot 'prototype'
$godotApplication = Join-Path $repositoryRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
$logDirectory = Join-Path $projectRoot 'qa\dev-scripts'
$targetedRunner = Join-Path $PSScriptRoot 'ror-run-p00-targeted-tests.ps1'
$fullRunner = Join-Path $PSScriptRoot 'ror-run-tests.ps1'
$performanceRunner = Join-Path $PSScriptRoot 'ror-performance-smoke.ps1'

$impactTests = @(
    'res://tests/unit/test_queued_orders.gd',
    'res://tests/integration/test_delete_and_martyrdom_routing.gd',
    'res://tests/unit/test_attack_ground_pipeline.gd',
    'res://tests/unit/test_ror_melee_area_damage.gd',
    'res://tests/unit/test_ror_special_damage_matrix.gd',
    'res://tests/unit/test_ballistics_speed_bands.gd',
    'res://tests/unit/test_conversion_resistance_matrix.gd',
    'res://tests/unit/test_repair_policy_matrix.gd',
    'res://tests/unit/test_multi_worker_repair.gd',
    'res://tests/unit/test_priest_auto_heal_chain.gd',
    'res://tests/integration/test_transport_allied_cargo.gd',
    'res://tests/integration/test_transport_artifact.gd',
    'res://tests/integration/test_tribute_pipeline.gd',
    'res://tests/unit/test_palmyran_economy_bonuses.gd',
    'res://tests/unit/test_ror_civilization_runtime_matrix.gd',
    'res://tests/unit/test_allied_town_center_reveal.gd',
    'res://tests/unit/test_writing_shared_vision.gd',
    'res://tests/unit/test_last_known_enemy_buildings.gd',
    'res://tests/unit/test_fog_of_war.gd',
    'res://tests/unit/test_simulation_visibility_system.gd',
    'res://tests/unit/test_simulation_snapshot.gd',
    'res://tests/integration/test_naval_trade_pipeline.gd',
    'res://tests/integration/test_all_civilization_bonus_rules.gd',
    'res://tests/integration/test_transport_pipeline.gd',
    'res://tests/integration/test_diplomacy_pipeline.gd',
    'res://tests/integration/test_game_save_load_pipeline.gd',
    'res://tests/unit/test_deterministic_replay.gd'
)

if ($FromTest -and $FromStage -ne 'impact') {
    throw 'FromTest can only be used with FromStage impact.'
}
if ($FromTest) {
    $startIndex = [Array]::IndexOf($impactTests, $FromTest)
    if ($startIndex -lt 0) {
        throw "FromTest is not in the impact list: $FromTest"
    }
    $impactTests = @($impactTests | Select-Object -Skip $startIndex)
}

foreach ($path in @($godotApplication, $targetedRunner, $fullRunner, $performanceRunner)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file is missing: $path"
    }
}
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

if ($FromStage -eq 'impact') {
    Write-Host "IMPACT: $($impactTests.Count) selected tests"
    foreach ($test in $impactTests) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetedRunner -TestScript $test
        if ($LASTEXITCODE -ne 0) {
            throw "Impact test failed: $test. Resume with -FromTest '$test' after fixing it."
        }
    }
}

if ($FromStage -in @('impact', 'full')) {
    Write-Host 'FULL SUITE: all unit, integration, scenario and golden tests'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner
    if ($LASTEXITCODE -ne 0) {
        throw "Full suite failed. Resume the suite itself with tools/ror-run-tests.ps1 -StartAt <test>, or resume this script with -FromStage full."
    }
}

Write-Host 'PERFORMANCE: compare with the existing baseline (no baseline refresh)'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $performanceRunner
if ($LASTEXITCODE -ne 0) {
    throw 'Performance smoke failed. Resume with -FromStage performance after investigation.'
}

Write-Host "P02-P06 validation complete from '$FromStage': all selected stages passed."
exit 0
