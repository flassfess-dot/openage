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
    'res://tests/unit/test_ror_selection_shortcuts.gd',
    'res://tests/unit/test_input_adapter.gd',
    'res://tests/unit/test_hud_controls.gd',
    'res://tests/unit/test_hud_view_model.gd',
    'res://tests/unit/test_population_timer_overlay.gd',
    'res://tests/unit/test_sound_cue_history.gd',
    'res://tests/unit/test_match_instruction_summary.gd',
    'res://tests/unit/test_interface_layout.gd',
    'res://tests/unit/test_simulation_snapshot.gd',
    'res://tests/unit/test_presentation_audio_router.gd',
    'res://tests/integration/test_hud_command_pipeline.gd',
    'res://tests/integration/test_player_unit_order_controls.gd',
    'res://tests/integration/test_game_save_state_matrix.gd'
)

if ($FromTest -and $FromStage -ne 'impact') {
    throw 'FromTest is valid only for the impact stage.'
}
if ($FromTest) {
    $startIndex = [Array]::IndexOf($impactTests, $FromTest)
    if ($startIndex -lt 0) {
        throw "Impact test is not in the P08 list: $FromTest"
    }
    $impactTests = @($impactTests | Select-Object -Skip $startIndex)
}
foreach ($runner in @($targetedRunner, $fullRunner)) {
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Required runner is missing: $runner"
    }
}

if ($FromStage -eq 'impact') {
    Write-Host "P08 IMPACT: $($impactTests.Count) tests"
    foreach ($test in $impactTests) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetedRunner -TestScript $test
        if ($LASTEXITCODE -ne 0) {
            throw "P08 impact test failed: $test. Resume with -FromTest '$test' after fixing it."
        }
    }
}

Write-Host 'P08 FULL SUITE: unit, integration, scenario and golden tests'
if ($FullStartAt) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner -StartAt $FullStartAt
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner
}
if ($LASTEXITCODE -ne 0) {
    throw 'P08 full suite failed. Resume with -FromStage full -FullStartAt <test path> after fixing it.'
}

Write-Host 'P08 validation passed. Performance optimization remains deferred to P14.'
exit 0
