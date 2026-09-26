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
    'res://tests/unit/test_allied_victory_setting.gd',
    'res://tests/unit/test_standard_victory_conditions.gd',
    'res://tests/unit/test_victory_presence_index.gd',
    'res://tests/unit/test_timed_victory_replay.gd',
    'res://tests/integration/test_resign_spectator.gd',
    'res://tests/unit/test_victory_modes.gd',
    'res://tests/unit/test_scenario_presentation_model.gd',
    'res://tests/integration/test_generated_alliance_victory.gd',
    'res://tests/integration/test_resign_pipeline.gd',
    'res://tests/unit/test_skirmish_settings.gd',
    'res://tests/unit/test_match_definition.gd',
    'res://tests/integration/test_artifact_capture_pipeline.gd',
    'res://tests/integration/test_defence_wonder_pipeline.gd',
    'res://tests/unit/test_simulation_snapshot.gd',
    'res://tests/unit/test_deterministic_replay.gd',
    'res://tests/integration/test_game_save_state_matrix.gd',
    'res://tests/integration/test_game_save_load_pipeline.gd',
    'res://tests/unit/test_hud_view_model.gd',
    'res://tests/unit/test_ai_player.gd',
    'res://tests/scenarios/test_generated_skirmish_deterministic_outcome.gd'
)

if ($FromTest -and $FromStage -ne 'impact') {
    throw 'FromTest is valid only for the impact stage.'
}
if ($FromTest) {
    $startIndex = [Array]::IndexOf($impactTests, $FromTest)
    if ($startIndex -lt 0) {
        throw "Impact test is not in the P07 list: $FromTest"
    }
    $impactTests = @($impactTests | Select-Object -Skip $startIndex)
}

foreach ($runner in @($targetedRunner, $fullRunner)) {
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Required runner is missing: $runner"
    }
}

if ($FromStage -eq 'impact') {
    Write-Host "P07 IMPACT: $($impactTests.Count) tests"
    foreach ($test in $impactTests) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetedRunner -TestScript $test
        if ($LASTEXITCODE -ne 0) {
            throw "P07 impact test failed: $test. Resume with -FromTest '$test' after fixing it."
        }
    }
}

Write-Host 'P07 FULL SUITE: unit, integration, scenario and golden tests'
if ($FullStartAt) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner -StartAt $FullStartAt
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner
}
if ($LASTEXITCODE -ne 0) {
    throw 'P07 full suite failed. Resume with -FromStage full -FullStartAt <test path> after fixing it.'
}

Write-Host 'P07 validation passed. Performance optimization remains deferred to P14 by user decision.'
exit 0
