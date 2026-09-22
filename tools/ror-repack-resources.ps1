[CmdletBinding()]
param(
    [string]$GamePath = "D:\Games\Age of Empires 1 - Rise of Rome",
    [string]$GameVersion = "1.1",
    [int]$Civilization = 13
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projectRoot = Join-Path $repositoryRoot "prototype"
$qaRoot = Join-Path $projectRoot "qa\dev-scripts"
$generatedRoot = Join-Path $projectRoot "assets\generated"
$godotApplication = Join-Path $repositoryRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $qaRoot "repack-resources-$timestamp.log"
$godotImportLog = Join-Path $qaRoot "repack-resources-godot-import-$timestamp.log"

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
    Write-Progress -Activity "Rise of Rome resources" -Status $Status -PercentComplete $Percent
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

function Invoke-LoggedCommand {
    param(
        [string]$Name,
        [int]$StartPercent,
        [int]$EndPercent,
        [string]$FilePath,
        [string[]]$Arguments
    )
    Write-Status $StartPercent "$Name started"
    Write-LogLine ("COMMAND: {0} {1}" -f $FilePath, ($Arguments -join " "))
    $previousErrorActionPreference = $ErrorActionPreference
    $exitCode = -1
    try {
        # Windows PowerShell 5.1 wraps native stderr as ErrorRecord objects.
        # Build tools such as Cargo use stderr for normal progress, so the
        # process exit code is the authoritative success signal here.
        $ErrorActionPreference = "Continue"
        & $FilePath @Arguments 2>&1 | ForEach-Object {
            Write-LogLine ("{0}: {1}" -f $Name, $_.ToString())
        }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode"
    }
    Write-Status $EndPercent "$Name complete"
}

function Invoke-GodotLogged {
    param(
        [string]$Name,
        [int]$StartPercent,
        [int]$EndPercent,
        [string[]]$Arguments,
        [string]$GodotLogPath
    )
    if (Test-Path -LiteralPath $GodotLogPath) {
        Remove-Item -LiteralPath $GodotLogPath -Force
    }
    $fullArguments = @("--log-file", $GodotLogPath) + $Arguments
    Write-Status $StartPercent "$Name started"
    Write-LogLine ("COMMAND: {0} {1}" -f $godotApplication, ($fullArguments -join " "))
    $process = Start-Process -FilePath $godotApplication -ArgumentList (Join-ProcessArguments $fullArguments) -PassThru -WindowStyle Hidden
    $seenLines = 0
    while (-not $process.HasExited) {
        if (Test-Path -LiteralPath $GodotLogPath) {
            $lines = @(Get-Content -LiteralPath $GodotLogPath)
            for ($i = $seenLines; $i -lt $lines.Count; $i++) {
                $text = [string]$lines[$i]
                Write-LogLine ("{0}: {1}" -f $Name, $text)
                if ($text -match '\[\s*(\d+)%\s*\]') {
                    $inner = [int]$Matches[1]
                    $mapped = $StartPercent + [int](($EndPercent - $StartPercent) * $inner / 100)
                    Write-Progress -Activity "Rise of Rome resources" -Status $text -PercentComplete $mapped
                }
            }
            $seenLines = $lines.Count
        }
        Start-Sleep -Seconds 2
    }
    if (Test-Path -LiteralPath $GodotLogPath) {
        $lines = @(Get-Content -LiteralPath $GodotLogPath)
        for ($i = $seenLines; $i -lt $lines.Count; $i++) {
            Write-LogLine ("{0}: {1}" -f $Name, [string]$lines[$i])
        }
    }
    if ($process.ExitCode -ne 0) {
        throw "$Name failed with exit code $($process.ExitCode)"
    }
    Write-Status $EndPercent "$Name complete"
}

try {
    Write-LogLine "Rise of Rome resource repack started"
    Write-LogLine "Repository: $repositoryRoot"
    Write-LogLine "Game path: $GamePath"
    Write-Status 0 "checking tools and source data"

    if (-not (Test-Path -LiteralPath (Join-Path $GamePath "data2\empires.dat"))) {
        throw "Missing source game data: $GamePath\data2\empires.dat"
    }
    if (-not (Test-Path -LiteralPath $godotApplication)) {
        throw "Missing Godot executable: $godotApplication"
    }

    Invoke-LoggedCommand `
        -Name "source asset import" `
        -StartPercent 5 `
        -EndPercent 70 `
        -FilePath "powershell.exe" `
        -Arguments @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", (Join-Path $repositoryRoot "tools\import-assets.ps1"),
            "-GamePath", $GamePath,
            "-GameVersion", $GameVersion,
            "-Civilization", [string]$Civilization
        )

    Invoke-LoggedCommand `
        -Name "cache validation" `
        -StartPercent 70 `
        -EndPercent 85 `
        -FilePath "powershell.exe" `
        -Arguments @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", (Join-Path $repositoryRoot "tools\validate-cache.ps1")
        )

    Invoke-GodotLogged `
        -Name "godot resource import" `
        -StartPercent 85 `
        -EndPercent 98 `
        -Arguments @("--headless", "--path", $projectRoot, "--import") `
        -GodotLogPath $godotImportLog

    $validationReport = Join-Path $generatedRoot "validation-report.json"
    if (-not (Test-Path -LiteralPath $validationReport)) {
        throw "Validation report was not created: $validationReport"
    }

    Write-Status 100 "resource repack complete"
    Write-LogLine "Validation report: $validationReport"
    Write-LogLine "Log complete: $logPath"
    Write-Progress -Activity "Rise of Rome resources" -Completed
    exit 0
}
catch {
    Write-LogLine ("FAILED: {0}" -f $_.Exception.Message)
    Write-Progress -Activity "Rise of Rome resources" -Completed
    exit 1
}
