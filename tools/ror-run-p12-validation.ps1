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
    'res://tests/unit/test_lockstep_session.gd',
    'res://tests/unit/test_multiplayer_lobby.gd',
    'res://tests/integration/test_lockstep_tcp_relay.gd',
    'res://tests/integration/test_lockstep_tcp_match.gd',
    'res://tests/integration/test_multiplayer_main_scene.gd',
    'res://tests/scenarios/test_lockstep_mixed_domain_match.gd',
    'res://tests/unit/test_deterministic_replay.gd',
    'res://tests/unit/test_match_definition.gd',
    'res://tests/unit/test_ror_skirmish_settings.gd',
    'res://tests/unit/test_skirmish_settings.gd',
    'res://tests/integration/test_launcher_scene.gd',
    'res://tests/integration/test_generated_skirmish_main_scene.gd',
    'res://tests/integration/test_hud_command_pipeline.gd',
    'res://tests/unit/test_logistics_population.gd',
    'res://tests/integration/test_game_save_state_matrix.gd'
)

if ($FromTest -and $FromStage -ne 'impact') {
    throw 'FromTest is valid only for the impact stage.'
}
if ($FromTest) {
    $startIndex = [Array]::IndexOf($impactTests, $FromTest)
    if ($startIndex -lt 0) {
        throw "Impact test is not in the P12 list: $FromTest"
    }
    $impactTests = @($impactTests | Select-Object -Skip $startIndex)
}
foreach ($runner in @($targetedRunner, $fullRunner)) {
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "Required runner is missing: $runner"
    }
}

if ($FromStage -eq 'impact') {
    Write-Host "P12 IMPACT: $($impactTests.Count) tests"
    foreach ($test in $impactTests) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetedRunner -TestScript $test
        if ($LASTEXITCODE -ne 0) {
            throw "P12 impact test failed: $test. Resume with -FromTest '$test' after fixing it."
        }
    }
}

Write-Host 'P12 FULL SUITE: unit, integration, scenario and golden tests'
if ($FullStartAt) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner -StartAt $FullStartAt
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fullRunner
}
if ($LASTEXITCODE -ne 0) {
    throw 'P12 full suite failed. Resume with -FromStage full -FullStartAt <test path> after fixing it.'
}

Write-Host 'P12 validation passed. P14 release and performance gates remain separate.'
exit 0
