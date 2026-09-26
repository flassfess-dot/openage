[CmdletBinding()]
param([switch]$ScenarioOnly, [switch]$InlandOnly, [switch]$P01QueueOnly, [switch]$P01PopulationOnly, [switch]$P01HudOnly, [switch]$P01HudRemaining, [switch]$P01StateOnly, [string]$TestScript = "", [string]$FromTest = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projectRoot = Join-Path $repositoryRoot "prototype"
$godotApplication = Join-Path $repositoryRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$logDirectory = Join-Path $projectRoot "qa\dev-scripts"
$tests = @(
    "res://tests/unit/test_ai_player.gd",
    "res://tests/unit/test_formation_corridor.gd",
    "res://tests/integration/test_navigation_command_pipeline.gd",
    "res://tests/scenarios/test_generated_naval_ai_acceptance.gd"
)
if ($ScenarioOnly) {
    $tests = @($tests[-1])
}
if ($InlandOnly) {
    $tests = @(
        "res://tests/unit/test_ai_player.gd",
        "res://tests/unit/test_formation_combat.gd",
        "res://tests/scenarios/test_generated_skirmish_deterministic_outcome.gd"
    )
}
if ($P01QueueOnly) {
    $tests = @(
        "res://tests/unit/test_ror_core_parity_baseline.gd",
        "res://tests/unit/test_ror_production_queue_semantics.gd",
        "res://tests/unit/test_production_queue.gd",
        "res://tests/unit/test_technology_and_ages.gd",
        "res://tests/unit/test_production_availability.gd",
        "res://tests/unit/test_population_support.gd",
        "res://tests/unit/test_simulation_economy_system.gd"
    )
}
if ($P01PopulationOnly) {
    $tests = @(
        "res://tests/unit/test_logistics_population.gd",
        "res://tests/unit/test_simulation_economy_system.gd",
        "res://tests/unit/test_death_lifecycle.gd",
        "res://tests/integration/test_transport_pipeline.gd",
        "res://tests/integration/test_temple_priest_conversion_pipeline.gd",
        "res://tests/unit/test_ai_player.gd",
        "res://tests/unit/test_source_campaign_ai_planner.gd",
        "res://tests/unit/test_game_save_archive.gd",
        "res://tests/integration/test_game_save_state_matrix.gd",
        "res://tests/unit/test_deterministic_replay.gd"
    )
}
if ($P01HudOnly) {
    $tests = @(
        "res://tests/unit/test_hud_view_model.gd",
        "res://tests/unit/test_hud_controls.gd",
        "res://tests/integration/test_hud_command_pipeline.gd",
        "res://tests/integration/test_player_unit_order_controls.gd",
        "res://tests/unit/test_ror_production_queue_semantics.gd"
    )
}
if ($P01HudRemaining) {
    $tests = @(
        "res://tests/unit/test_hud_controls.gd",
        "res://tests/integration/test_hud_command_pipeline.gd",
        "res://tests/integration/test_player_unit_order_controls.gd",
        "res://tests/unit/test_ror_production_queue_semantics.gd"
    )
}
if ($P01StateOnly) {
    $tests = @(
        "res://tests/unit/test_simulation_snapshot.gd",
        "res://tests/unit/test_deterministic_replay.gd",
        "res://tests/unit/test_game_save_archive.gd",
        "res://tests/integration/test_game_save_load_pipeline.gd",
        "res://tests/integration/test_game_save_state_matrix.gd"
    )
}
if ($TestScript) {
    $tests = @($TestScript)
}
$selectionCount = 0
if ($ScenarioOnly) { $selectionCount++ }
if ($InlandOnly) { $selectionCount++ }
if ($P01QueueOnly) { $selectionCount++ }
if ($P01PopulationOnly) { $selectionCount++ }
if ($P01HudOnly) { $selectionCount++ }
if ($P01HudRemaining) { $selectionCount++ }
if ($P01StateOnly) { $selectionCount++ }
if ($TestScript) { $selectionCount++ }
if ($selectionCount -gt 1) {
    throw "Choose only one test selection option"
}
if ($TestScript -and ($TestScript -notmatch '^res://tests/(unit|integration|scenarios|golden)/test_[A-Za-z0-9_]+\.gd$')) {
    throw "TestScript must name a test script under res://tests: $TestScript"
}
if ($FromTest) {
    $startIndex = [Array]::IndexOf($tests, $FromTest)
    if ($startIndex -lt 0) {
        throw "FromTest must name a test in the selected list: $FromTest"
    }
    $tests = @($tests | Select-Object -Skip $startIndex)
}

if (-not (Test-Path -LiteralPath $godotApplication)) {
    throw "Missing Godot executable: $godotApplication"
}

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

foreach ($test in $tests) {
    $testName = [IO.Path]::GetFileNameWithoutExtension($test)
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logPath = Join-Path $logDirectory ("p00-targeted-{0}-{1}.log" -f $testName, $timestamp)
    Write-Host ""
    Write-Host "RUN $test"
    $arguments = @(
        "--headless",
        "--log-file", ('"{0}"' -f $logPath),
        "--path", ('"{0}"' -f $projectRoot),
        "--script", $test
    )
    $process = Start-Process -FilePath $godotApplication -ArgumentList $arguments -NoNewWindow -Wait -PassThru
    $engineErrors = @()
    if (Test-Path -LiteralPath $logPath) {
        $engineErrors = @(Select-String -LiteralPath $logPath -Pattern "SCRIPT ERROR:|ERROR:" | Where-Object {
            -not $_.Line.Contains("Failed to read the root certificate store")
        })
    }
    if ($process.ExitCode -ne 0 -or $engineErrors.Count -gt 0) {
        Write-Error "FAILED $test (exit code $($process.ExitCode), engine errors $($engineErrors.Count)). Log: $logPath"
        exit 1
    }
    Write-Host "PASSED $test"
}

Write-Host ""
Write-Host ("Targeted tests complete: {0} passed, 0 failed" -f $tests.Count)
exit 0
