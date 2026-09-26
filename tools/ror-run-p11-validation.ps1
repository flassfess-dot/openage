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
    'res://tests/unit/test_game_save_archive.gd',
    'res://tests/unit/test_sound_cue_history.gd',
    'res://tests/unit/test_match_instruction_summary.gd',
    'res://tests/unit/test_deterministic_replay.gd',
    'res://tests/unit/test_fog_of_war.gd',
    'res://tests/unit/test_ror_production_queue_semantics.gd',
    'res://tests/integration/test_game_save_load_pipeline.gd',
    'res://tests/integration/test_game_save_state_matrix.gd',
    'res://tests/integration/test_main_hud_scene.gd',
    'res://tests/unit/test_timed_victory_replay.gd'
)

if ($FromTest -and $FromStage -ne 'impact') {
    throw 'FromTest is valid only for the impact stage.'
}
if ($FromTest) {
    $startIndex = [Array]::IndexOf($impactTests, $FromTest)
    if ($startIndex -lt 0) {
        throw "Impact test is not in the P11 list: $FromTest"
    }
    $impactTests = @($impactTests | Select-Object -Skip $startIndex)
}
foreach ($runner in @($targetedRunner, $fullRunner)) {
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Required runner is missing: $runner"
    }
}

if ($FromStage -eq 'impact') {
    Write-Host "P11 IMPACT: $($impactTests.Count) tests"
    foreach ($test in $impactTests) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetedRunner -TestScript $test
        if ($LASTEXITCODE -ne 0) {
            throw "P11 impact test failed: $test. Resume with -FromTest '$test' after fixing it."
        }
    }
}

Write-Host 'P11 FULL SUITE: unit, integration, scenario and golden tests'
if ($FullStartAt) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner -StartAt $FullStartAt
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner
}
if ($LASTEXITCODE -ne 0) {
    throw 'P11 full suite failed. Resume with -FromStage full -FullStartAt <test path> after fixing it.'
}

Write-Host 'P11 validation passed. P12 multiplayer and P14 performance gates remain separate.'
exit 0
