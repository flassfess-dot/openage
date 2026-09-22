[CmdletBinding()]
param(
    [switch]$RefreshBaseline
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projectRoot = Join-Path $repositoryRoot "prototype"
$qaRoot = Join-Path $projectRoot "qa\dev-scripts"
$smokeRoot = Join-Path $projectRoot "qa\performance-smoke"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Join-Path $smokeRoot "runs\$timestamp"
$runResourceRoot = "res://qa/performance-smoke/runs/$timestamp"
$baselinePath = Join-Path $smokeRoot "baseline.json"
$logPath = Join-Path $qaRoot "performance-smoke-$timestamp.log"
$reportPath = Join-Path $qaRoot "performance-smoke-$timestamp.json"
$godotApplication = Join-Path $repositoryRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"

New-Item -ItemType Directory -Force -Path $qaRoot, $runRoot | Out-Null

function Write-LogLine {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $logPath -Append | Write-Host
}

function Write-Status {
    param(
        [int]$Percent,
        [string]$Status
    )
    Write-Progress -Activity "Rise of Rome performance smoke" -Status $Status -PercentComplete $Percent
    Write-LogLine ("PROGRESS {0,3}% | {1}" -f $Percent, $Status)
}

function Join-ProcessArguments {
    param([string[]]$ArgumentList)
    return (($ArgumentList | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        }
        else {
            $_
        }
    }) -join " ")
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Get-ActionableErrors {
    param([string[]]$Paths)
    $result = @()
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        foreach ($lineValue in Get-Content -LiteralPath $path) {
            $line = [string]$lineValue
            $trimmed = $line.TrimStart()
            if ($line -match 'SCRIPT ERROR:' -or ($trimmed.StartsWith('ERROR:') -and -not $line.Contains('Failed to read the root certificate store'))) {
                $result += $line
            }
        }
    }
    return $result
}

function Invoke-GodotCase {
    param(
        [string]$Id,
        [string]$Script,
        [bool]$Headless,
        [string[]]$UserArguments = @()
    )
    $slug = $Id -replace '[^A-Za-z0-9_.-]', '-'
    $stdoutPath = Join-Path $runRoot "$slug.stdout.log"
    $stderrPath = Join-Path $runRoot "$slug.stderr.log"
    $engineLogPath = Join-Path $runRoot "$slug.godot.log"
    $arguments = @()
    if ($Headless) {
        $arguments += "--headless"
    }
    $arguments += @(
        "--log-file", $engineLogPath,
        "--path", $projectRoot,
        "--script", $Script
    )
    if ($UserArguments.Count -gt 0) {
        $arguments += "--"
        $arguments += $UserArguments
    }
    Write-LogLine ("START {0} | {1}" -f $Id, $Script)
    $started = Get-Date
    $process = Start-Process `
        -FilePath $godotApplication `
        -ArgumentList (Join-ProcessArguments $arguments) `
        -WorkingDirectory $repositoryRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru `
        -Wait
    $exitCode = if ($null -eq $process.ExitCode) { -1 } else { [int]$process.ExitCode }
    $duration = ((Get-Date) - $started).TotalSeconds
    foreach ($stream in @($stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $stream) {
            Get-Content -LiteralPath $stream | ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace([string]$_)) {
                    Write-LogLine ("{0}: {1}" -f $Id, [string]$_)
                }
            }
        }
    }
    $errors = @(Get-ActionableErrors @($stdoutPath, $stderrPath, $engineLogPath))
    Write-LogLine ("END {0} | exit={1} | duration={2:N1}s | engine_errors={3}" -f $Id, $exitCode, $duration, $errors.Count)
    return [pscustomobject]@{
        Id = $Id
        ExitCode = $exitCode
        DurationSeconds = [math]::Round($duration, 3)
        Errors = $errors
        StdOut = $stdoutPath
        StdErr = $stderrPath
        EngineLog = $engineLogPath
    }
}

function Get-NestedValue {
    param(
        [object]$Object,
        [string]$Path
    )
    $current = $Object
    foreach ($segment in $Path.Split('/')) {
        if ($null -eq $current) {
            return $null
        }
        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) {
            return $null
        }
        $current = $property.Value
    }
    return $current
}

$functionalTests = @(
    @{ Id = "performance-observability"; Script = "res://tests/unit/test_performance_observability.gd" },
    @{ Id = "resource-loading-policy"; Script = "res://tests/unit/test_resource_loading_policy.gd" },
    @{ Id = "entity-lookup-index"; Script = "res://tests/unit/test_entity_lookup_index.gd" },
    @{ Id = "spatial-hash"; Script = "res://tests/unit/test_spatial_hash_queries.gd" },
    @{ Id = "navigation-grid"; Script = "res://tests/unit/test_navigation_grid.gd" },
    @{ Id = "navigation-service"; Script = "res://tests/unit/test_navigation_service.gd" },
    @{ Id = "pathfinder"; Script = "res://tests/unit/test_pathfinder.gd" },
    @{ Id = "local-movement"; Script = "res://tests/unit/test_local_movement.gd" },
    @{ Id = "destination-reservations"; Script = "res://tests/unit/test_destination_reservations.gd" },
    @{ Id = "simulation-tick"; Script = "res://tests/unit/test_simulation_tick_pipeline.gd" },
    @{ Id = "simulation-snapshot"; Script = "res://tests/unit/test_simulation_snapshot.gd" },
    @{ Id = "deterministic-replay"; Script = "res://tests/unit/test_deterministic_replay.gd" },
    @{ Id = "wildlife-behavior"; Script = "res://tests/unit/test_wildlife_behavior.gd" },
    @{ Id = "render-items"; Script = "res://tests/unit/test_render_items.gd" },
    @{ Id = "viewport-culling"; Script = "res://tests/unit/test_viewport_culling.gd" },
    @{ Id = "fog-terrain-boundary"; Script = "res://tests/unit/test_fog_terrain_boundary.gd" },
    @{ Id = "terrain-tiles"; Script = "res://tests/unit/test_terrain_tiles.gd" },
    @{ Id = "resources"; Script = "res://tests/unit/test_resources.gd" },
    @{ Id = "navigation-command"; Script = "res://tests/integration/test_navigation_command_pipeline.gd" },
    @{ Id = "shared-formation-motion"; Script = "res://tests/integration/test_shared_formation_motion.gd" },
    @{ Id = "panned-static-projection"; Script = "res://tests/integration/test_panned_static_projection.gd" },
    @{ Id = "navigation-stress"; Script = "res://tests/scenarios/test_navigation_stress.gd" }
)

$benchmarks = @(
    [ordered]@{
        Id = "movement"
        Name = "sustained formation movement"
        Script = "res://tests/manual/benchmark_e6_runtime.gd"
        Headless = $true
        ReportPath = Join-Path $runRoot "movement.json"
        Arguments = @(
            "--case=performance_smoke_movement",
            "--workload=formation_march",
            "--players=2",
            "--units-per-player=96",
            "--map-side=128",
            "--warmup-ticks=8",
            "--sample-ticks=40",
            "--output=$runResourceRoot/movement.json"
        )
        Metrics = @(
            @{ Name = "fixed_tick_p95_us"; Path = "probe/metrics_microseconds/controller.fixed_tick/p95"; AbsoluteMax = 250000; NoiseFloor = 5000; Tolerance = 0.35; Positive = $true },
            @{ Name = "unit_orders_p95_us"; Path = "probe/metrics_microseconds/simulation.system.unit_orders/p95"; AbsoluteMax = 180000; NoiseFloor = 4000; Tolerance = 0.35; Positive = $true },
            @{ Name = "command_wall_us"; Path = "command_phase/wall_microseconds"; AbsoluteMax = 6000000; NoiseFloor = 100000; Tolerance = 0.35; Positive = $true },
            @{ Name = "memory_static_bytes"; Path = "process/memory_static_bytes"; AbsoluteMax = 1342177280; NoiseFloor = 67108864; Tolerance = 0.25; Positive = $true }
        )
    },
    [ordered]@{
        Id = "mixed"
        Name = "mixed moving economy and combat"
        Script = "res://tests/manual/benchmark_e6_runtime.gd"
        Headless = $true
        ReportPath = Join-Path $runRoot "mixed.json"
        Arguments = @(
            "--case=performance_smoke_mixed",
            "--workload=mixed_match",
            "--players=2",
            "--units-per-player=80",
            "--map-side=128",
            "--warmup-ticks=8",
            "--sample-ticks=40",
            "--output=$runResourceRoot/mixed.json"
        )
        Metrics = @(
            @{ Name = "fixed_tick_p95_us"; Path = "probe/metrics_microseconds/controller.fixed_tick/p95"; AbsoluteMax = 300000; NoiseFloor = 5000; Tolerance = 0.35; Positive = $true },
            @{ Name = "world_advance_p95_us"; Path = "probe/metrics_microseconds/controller.world_advance/p95"; AbsoluteMax = 250000; NoiseFloor = 4000; Tolerance = 0.35; Positive = $true },
            @{ Name = "command_wall_us"; Path = "command_phase/wall_microseconds"; AbsoluteMax = 6000000; NoiseFloor = 100000; Tolerance = 0.35; Positive = $true },
            @{ Name = "memory_static_bytes"; Path = "process/memory_static_bytes"; AbsoluteMax = 1610612736; NoiseFloor = 67108864; Tolerance = 0.25; Positive = $true }
        )
    },
    [ordered]@{
        Id = "visible"
        Name = "visible scene, pan and active frames"
        Script = "res://tests/manual/benchmark_e6_visible.gd"
        Headless = $false
        ReportPath = Join-Path $runRoot "visible.json"
        Arguments = @(
            "--case=performance_smoke_visible",
            "--size=1024x768",
            "--units-per-player=80",
            "--visible-per-team=50",
            "--warmup-frames=8",
            "--sample-frames=24",
            "--preparation-samples=6",
            "--output=$runResourceRoot/visible.json"
        )
        Metrics = @(
            @{ Name = "snapshot_p95_us"; Path = "snapshot_microseconds/p95"; AbsoluteMax = 400000; NoiseFloor = 8000; Tolerance = 0.35; Positive = $true },
            @{ Name = "drawable_build_p95_us"; Path = "drawable_build_microseconds/p95"; AbsoluteMax = 75000; NoiseFloor = 3000; Tolerance = 0.35; Positive = $true },
            @{ Name = "render_frame_p95_us"; Path = "render_frame_microseconds/p95"; AbsoluteMax = 500000; NoiseFloor = 10000; Tolerance = 0.35; Positive = $true },
            @{ Name = "pan_frame_p95_us"; Path = "pan_frame_microseconds/p95"; AbsoluteMax = 500000; NoiseFloor = 10000; Tolerance = 0.35; Positive = $true },
            @{ Name = "active_frame_p95_us"; Path = "active_frame_microseconds/p95"; AbsoluteMax = 650000; NoiseFloor = 12000; Tolerance = 0.35; Positive = $true },
            @{ Name = "memory_static_bytes"; Path = "process/memory_static_bytes"; AbsoluteMax = 2684354560; NoiseFloor = 134217728; Tolerance = 0.25; Positive = $true }
        )
    }
)

$startedAt = Get-Date
$failures = @()
$functionalResults = @()
$benchmarkResults = @()
$baseline = $null
$baselineAvailable = (Test-Path -LiteralPath $baselinePath) -and -not $RefreshBaseline

try {
    Write-LogLine "Rise of Rome performance smoke started"
    Write-LogLine "Repository: $repositoryRoot"
    Write-LogLine ("Mode: {0}" -f $(if ($RefreshBaseline) { "refresh baseline" } elseif ($baselineAvailable) { "compare with baseline" } else { "create baseline after a clean run" }))
    Write-Status 0 "checking smoke runner"

    if (-not (Test-Path -LiteralPath $godotApplication)) {
        throw "Missing Godot executable: $godotApplication"
    }
    foreach ($test in $functionalTests) {
        $testPath = Join-Path $projectRoot ($test.Script.Replace("res://", "").Replace("/", "\"))
        if (-not (Test-Path -LiteralPath $testPath)) {
            throw "Missing smoke test: $($test.Script)"
        }
    }
    if ($baselineAvailable) {
        $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
        if ([int]$baseline.schema_version -ne 1) {
            throw "Unsupported performance smoke baseline: $baselinePath"
        }
    }

    for ($index = 0; $index -lt $functionalTests.Count; $index++) {
        $test = $functionalTests[$index]
        $percent = 5 + [int](50 * $index / [double]$functionalTests.Count)
        Write-Status $percent ("functional {0}/{1}: {2}" -f ($index + 1), $functionalTests.Count, $test.Id)
        $result = Invoke-GodotCase -Id ("test-{0}" -f $test.Id) -Script $test.Script -Headless $true
        $passed = $result.ExitCode -eq 0 -and $result.Errors.Count -eq 0
        if (-not $passed) {
            $failures += "Functional smoke failed: $($test.Id)"
        }
        $functionalResults += [ordered]@{
            id = $test.Id
            script = $test.Script
            status = $(if ($passed) { "passed" } else { "failed" })
            exit_code = $result.ExitCode
            duration_seconds = $result.DurationSeconds
            engine_errors = $result.Errors
        }
    }

    if ($failures.Count -eq 0) {
        for ($index = 0; $index -lt $benchmarks.Count; $index++) {
            $case = $benchmarks[$index]
            $percent = 58 + [int](30 * $index / [double]$benchmarks.Count)
            Write-Status $percent ("benchmark {0}/{1}: {2}" -f ($index + 1), $benchmarks.Count, $case.Name)
            $execution = Invoke-GodotCase -Id ("benchmark-{0}" -f $case.Id) -Script $case.Script -Headless $case.Headless -UserArguments $case.Arguments
            if ($execution.ExitCode -ne 0 -or $execution.Errors.Count -gt 0) {
                $failures += "Benchmark failed: $($case.Id)"
                $benchmarkResults += [ordered]@{
                    id = $case.Id
                    status = "failed"
                    exit_code = $execution.ExitCode
                    duration_seconds = $execution.DurationSeconds
                    engine_errors = $execution.Errors
                    metrics = @()
                }
                continue
            }
            if (-not (Test-Path -LiteralPath $case.ReportPath)) {
                $failures += "Benchmark report missing: $($case.Id)"
                continue
            }
            $case.Report = Get-Content -LiteralPath $case.ReportPath -Raw | ConvertFrom-Json
            $case.Execution = $execution
        }
    }
    else {
        Write-LogLine "Benchmarks skipped because a functional smoke test failed"
    }

    Write-Status 90 "evaluating performance budgets"
    $newBaselineCases = [ordered]@{}
    foreach ($case in $benchmarks) {
        if (-not $case.Contains("Report")) {
            continue
        }
        $metricResults = @()
        $newBaselineCases[$case.Id] = [ordered]@{}
        foreach ($metric in $case.Metrics) {
            $rawValue = Get-NestedValue -Object $case.Report -Path $metric.Path
            if ($null -eq $rawValue) {
                $failures += "Missing metric $($case.Id).$($metric.Name)"
                continue
            }
            $value = [double]$rawValue
            $absoluteMax = [double]$metric.AbsoluteMax
            $status = "passed"
            $baselineValue = $null
            $relativeMax = $null
            if ($metric.Positive -and $value -le 0) {
                $status = "failed"
                $failures += "Invalid metric $($case.Id).$($metric.Name): $value"
            }
            if ($value -gt $absoluteMax) {
                $status = "failed"
                $failures += "Absolute budget exceeded: $($case.Id).$($metric.Name) = $value, max $absoluteMax"
            }
            if ($baselineAvailable) {
                $baselineValue = Get-NestedValue -Object $baseline -Path ("cases/{0}/{1}" -f $case.Id, $metric.Name)
                if ($null -eq $baselineValue) {
                    $status = "failed"
                    $failures += "Baseline metric missing: $($case.Id).$($metric.Name)"
                }
                else {
                    $relativeMax = [math]::Max(
                        [double]$baselineValue * (1.0 + [double]$metric.Tolerance),
                        [double]$baselineValue + [double]$metric.NoiseFloor
                    )
                    if ($value -gt $relativeMax) {
                        $status = "failed"
                        $failures += "Regression: $($case.Id).$($metric.Name) = $value, baseline $baselineValue, max $relativeMax"
                    }
                }
            }
            $newBaselineCases[$case.Id][$metric.Name] = $value
            $metricResults += [ordered]@{
                name = $metric.Name
                value = $value
                absolute_max = $absoluteMax
                baseline = $baselineValue
                relative_max = $relativeMax
                status = $status
            }
            Write-LogLine ("METRIC {0}.{1}={2:N0} | absolute_max={3:N0} | baseline={4}" -f $case.Id, $metric.Name, $value, $absoluteMax, $(if ($null -eq $baselineValue) { "n/a" } else { [string]$baselineValue }))
        }

        if ($case.Id -in @("movement", "mixed")) {
            $firstHalf = [double](Get-NestedValue -Object $case.Report -Path "sample_first_half_tick_wall_microseconds/p95")
            $lastHalf = [double](Get-NestedValue -Object $case.Report -Path "sample_last_half_tick_wall_microseconds/p95")
            $growthMax = [math]::Max($firstHalf * 1.60, $firstHalf + 8000.0)
            $growthStatus = "passed"
            if ($firstHalf -le 0 -or $lastHalf -le 0 -or $lastHalf -gt $growthMax) {
                $growthStatus = "failed"
                $failures += "Progressive slowdown: $($case.Id) first-half p95=$firstHalf, last-half p95=$lastHalf, max=$growthMax"
            }
            $metricResults += [ordered]@{
                name = "late_vs_early_tick_p95"
                value = $lastHalf
                baseline = $firstHalf
                relative_max = $growthMax
                status = $growthStatus
            }
            $rejected = [int](Get-NestedValue -Object $case.Report -Path "command_phase/rejected")
            if ($rejected -ne 0) {
                $failures += "Benchmark command rejection: $($case.Id) rejected $rejected entities"
            }
        }

        $caseStatus = "passed"
        if (@($metricResults | Where-Object { $_.status -ne "passed" }).Count -gt 0) {
            $caseStatus = "failed"
        }
        $benchmarkResults += [ordered]@{
            id = $case.Id
            name = $case.Name
            status = $caseStatus
            duration_seconds = $case.Execution.DurationSeconds
            report = $case.ReportPath
            metrics = $metricResults
        }
    }

    if (($RefreshBaseline -or -not $baselineAvailable) -and $failures.Count -eq 0) {
        $newBaseline = [ordered]@{
            schema_version = 1
            created_at = (Get-Date).ToString("o")
            processor = [Environment]::GetEnvironmentVariable("PROCESSOR_IDENTIFIER")
            cases = $newBaselineCases
        }
        Write-JsonFile -Path $baselinePath -Value $newBaseline
        Write-LogLine "Performance baseline written: $baselinePath"
    }

    $durationSeconds = ((Get-Date) - $startedAt).TotalSeconds
    $status = $(if ($failures.Count -eq 0) { "passed" } else { "failed" })
    $summary = [ordered]@{
        schema_version = 1
        started_at = $startedAt.ToString("o")
        completed_at = (Get-Date).ToString("o")
        duration_seconds = [math]::Round($durationSeconds, 3)
        status = $status
        baseline_path = $baselinePath
        baseline_mode = $(if ($RefreshBaseline) { "refreshed" } elseif ($baselineAvailable) { "compared" } else { "created" })
        functional = $functionalResults
        benchmarks = $benchmarkResults
        failures = $failures
        run_directory = $runRoot
        log = $logPath
    }
    Write-JsonFile -Path $reportPath -Value $summary

    if ($failures.Count -gt 0) {
        foreach ($failure in $failures) {
            Write-LogLine "FAILED: $failure"
        }
        Write-Status 100 ("smoke failed: {0} issue(s)" -f $failures.Count)
        Write-LogLine "JSON report: $reportPath"
        Write-Progress -Activity "Rise of Rome performance smoke" -Completed
        exit 1
    }

    Write-Status 100 ("smoke passed in {0:N1}s" -f $durationSeconds)
    Write-LogLine "JSON report: $reportPath"
    Write-LogLine "Log complete: $logPath"
    Write-Progress -Activity "Rise of Rome performance smoke" -Completed
    exit 0
}
catch {
    Write-LogLine ("FAILED: {0}" -f $_.Exception.Message)
    Write-Progress -Activity "Rise of Rome performance smoke" -Completed
    exit 1
}
