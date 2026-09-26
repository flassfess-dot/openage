[CmdletBinding()]
param([string]$StartAt = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projectRoot = Join-Path $repositoryRoot "prototype"
$qaRoot = Join-Path $projectRoot "qa\dev-scripts"
$godotApplication = Join-Path $repositoryRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $qaRoot "test-run-$timestamp.log"
$godotLog = Join-Path $qaRoot "test-run-godot-$timestamp.log"

New-Item -ItemType Directory -Force -Path $qaRoot | Out-Null

function Write-LogLine {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $logPath -Append
}

function Write-Status {
    param(
        [int]$Percent,
        [string]$Status
    )
    Write-Progress -Activity "Rise of Rome tests" -Status $Status -PercentComplete $Percent
    Write-LogLine ("PROGRESS {0,3}% | {1}" -f $Percent, $Status)
}

function Get-TestScripts {
    $directories = @("unit", "integration", "scenarios", "golden")
    $result = @()
    foreach ($directory in $directories) {
        $path = Join-Path $projectRoot ("tests\{0}" -f $directory)
        if (Test-Path -LiteralPath $path) {
            $result += Get-ChildItem -LiteralPath $path -Filter "test_*.gd" -File | Sort-Object FullName
        }
    }
    return $result
}

try {
    Write-LogLine "Rise of Rome test run started"
    Write-LogLine "Repository: $repositoryRoot"
    Write-LogLine ("Category: {0}" -f $(if ($StartAt) { "from $StartAt" } else { "all" }))
    Write-Status 0 "checking test runner"

    if (-not (Test-Path -LiteralPath $godotApplication)) {
        throw "Missing Godot executable: $godotApplication"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "tests\test_suite.gd"))) {
        throw "Missing test suite runner: prototype\tests\test_suite.gd"
    }

    $testScripts = @(Get-TestScripts)
    if ($testScripts.Count -eq 0) {
        throw "No tests found"
    }
    $startScript = $StartAt.Trim().Replace('\', '/')
    if ($startScript.StartsWith('res://')) {
        $startScript = $startScript.Substring(6)
    }
    $testCount = $testScripts.Count
    if ($startScript) {
        $orderedScripts = @($testScripts | ForEach-Object { $_.FullName.Substring($projectRoot.Length + 1).Replace('\', '/') } | Sort-Object)
        $startIndex = [Array]::IndexOf($orderedScripts, $startScript)
        if ($startIndex -lt 0) {
            throw "Cannot resume: test not found: $startScript"
        }
        $testCount = $orderedScripts.Count - $startIndex
    }
    Write-Status 5 ("found {0} test scripts to run" -f $testCount)

    if (Test-Path -LiteralPath $godotLog) {
        Remove-Item -LiteralPath $godotLog -Force
    }

    $arguments = @(
        "--headless",
        "--log-file", $godotLog,
        "--path", $projectRoot,
        "--script", "res://tests/test_suite.gd"
    )
    if ($startScript) {
        $arguments += @("--", "--start-at=$startScript")
    }
    Write-LogLine ("COMMAND: {0} {1}" -f $godotApplication, ($arguments -join " "))
    $passed = 0
    $failed = 0
    & $godotApplication @arguments 2>&1 | ForEach-Object {
        $text = $_.ToString()
        Write-LogLine ("test-suite: {0}" -f $text)
        if ($text -match '^PASSED ') {
            $passed += 1
            $percent = 5 + [int](90 * (($passed + $failed) / [double]$testCount))
            Write-Progress -Activity "Rise of Rome tests" -Status ("passed {0}/{1}" -f $passed, $testCount) -PercentComplete $percent
        }
        elseif ($text -match '^FAILED ') {
            $failed += 1
            $percent = 5 + [int](90 * (($passed + $failed) / [double]$testCount))
            Write-Progress -Activity "Rise of Rome tests" -Status ("failed {0}, passed {1}" -f $failed, $passed) -PercentComplete $percent
        }
    }
    $exitCode = $LASTEXITCODE

    if (Test-Path -LiteralPath $godotLog) {
        Write-LogLine "Godot engine log: $godotLog"
        Select-String -LiteralPath $godotLog -Pattern "SCRIPT ERROR|ERROR:|FAILED|A-006 suite" | ForEach-Object {
            Write-LogLine ("godot-summary: {0}" -f $_.Line)
        }
    }

    if ($exitCode -ne 0) {
        throw "Test suite failed with exit code $exitCode. Passed: $passed. Failed: $failed."
    }

    Write-Status 100 ("tests complete: {0} passed, {1} failed" -f $passed, $failed)
    Write-LogLine "Log complete: $logPath"
    Write-Progress -Activity "Rise of Rome tests" -Completed
    exit 0
}
catch {
    Write-LogLine ("FAILED: {0}" -f $_.Exception.Message)
    Write-Progress -Activity "Rise of Rome tests" -Completed
    exit 1
}
