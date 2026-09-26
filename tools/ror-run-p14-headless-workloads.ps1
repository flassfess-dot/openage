[CmdletBinding()]
param(
    [ValidateSet(2, 4, 8)]
    [int]$StartAtPlayers = 2,
    [int]$UnitsPerPlayer = 80,
    [int]$SampleTicks = 400
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($UnitsPerPlayer -lt 1 -or $SampleTicks -lt 10) {
    throw 'UnitsPerPlayer must be positive and SampleTicks must be at least 10.'
}
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$projectRoot = Join-Path $repositoryRoot 'prototype'
$godot = Join-Path $repositoryRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = Join-Path $projectRoot "qa\performance-smoke\runs\p14-$timestamp"
$logRoot = Join-Path $projectRoot 'qa\dev-scripts'
New-Item -ItemType Directory -Path $runRoot, $logRoot -Force | Out-Null

$cases = @(2, 4, 8) | Where-Object { $_ -ge $StartAtPlayers }
$results = @()
foreach ($players in $cases) {
    $caseId = "gigantic-${players}p"
    $reportPath = Join-Path $runRoot "$caseId.json"
    $stdoutPath = Join-Path $logRoot "p14-$caseId-$timestamp.stdout.log"
    $stderrPath = Join-Path $logRoot "p14-$caseId-$timestamp.stderr.log"
    $relativeOutput = "res://qa/performance-smoke/runs/p14-$timestamp/$caseId.json"
    $arguments = @(
        '--headless', '--path', '.\prototype', '--script',
        'res://tests/manual/benchmark_e6_runtime.gd', '--',
        "--case=p14-$caseId", '--workload=mixed_match',
        "--players=$players", "--units-per-player=$UnitsPerPlayer",
        '--map-side=200', '--warmup-ticks=8', "--sample-ticks=$SampleTicks",
        "--output=$relativeOutput"
    )
    Write-Host "P14 HEADLESS ${caseId}: 200x200, $UnitsPerPlayer units/player"
    $process = Start-Process -FilePath $godot -ArgumentList $arguments `
        -WorkingDirectory $repositoryRoot -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
        -PassThru -Wait
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $reportPath)) {
        throw "Benchmark $caseId failed (exit $($process.ExitCode)). See $stdoutPath and $stderrPath. Resume with -StartAtPlayers $players."
    }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $fixedP95 = [double]$report.probe.metrics_microseconds.'controller.fixed_tick'.p95
    $worldP95 = [double]$report.probe.metrics_microseconds.'controller.world_advance'.p95
    $memoryBytes = [double]$report.process.memory_static_bytes
    $firstHalfP95 = [double]$report.sample_first_half_tick_wall_microseconds.p95
    $lastHalfP95 = [double]$report.sample_last_half_tick_wall_microseconds.p95
    $rejected = [int]$report.command_phase.rejected
    if ([int]$report.players -ne $players -or [int]$report.entity_count -lt $players * $UnitsPerPlayer -or [int]$report.map_size[0] -ne 200 -or [int]$report.map_size[1] -ne 200) {
        throw "Benchmark $caseId did not run the requested Gigantic workload."
    }
    if ($fixedP95 -gt 35000 -or $worldP95 -gt 175000 -or $memoryBytes -gt 1127428915 -or $rejected -ne 0 -or $lastHalfP95 -gt $firstHalfP95 * 1.25) {
        throw "Benchmark $caseId missed the P14 headroom/quality gate: tick_p95=$fixedP95 world_p95=$worldP95 memory=$memoryBytes rejected=$rejected first_half=$firstHalfP95 last_half=$lastHalfP95. Report: $reportPath"
    }
    $results += [pscustomobject]@{
        players = $players
        entities = [int]$report.entity_count
        fixed_tick_p95_us = $fixedP95
        world_advance_p95_us = $worldP95
        memory_static_bytes = $memoryBytes
        rejected_commands = $rejected
        first_half_p95_us = $firstHalfP95
        last_half_p95_us = $lastHalfP95
        report = $reportPath
    }
    Write-Host ("PASSED {0}: tick p95={1:N0} us, world p95={2:N0} us, memory={3:N1} MiB" -f $caseId, $fixedP95, $worldP95, ($memoryBytes / 1MB))
}

$summaryPath = Join-Path $logRoot "p14-gigantic-summary-$timestamp.json"
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "P14 headless Gigantic workloads passed: $($results.Count)/$($results.Count). Summary: $summaryPath"
exit 0
