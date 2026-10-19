[CmdletBinding()]
param(
    [switch]$VerifyStartup
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "ror-build-common.ps1")

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projectRoot = Join-Path $repositoryRoot "prototype"
$generatedRoot = Join-Path $projectRoot "assets\generated"
$distributionRoot = Join-Path $repositoryRoot "dist\Rise of Rome Prototype"
$qaRoot = Join-Path $projectRoot "qa\dev-scripts"
$godotApplication = Join-Path $repositoryRoot ".tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
$releaseTemplate = Join-Path $repositoryRoot ".tools\godot-4.7.2\windows_release_x86_64.exe"
$application = Join-Path $distributionRoot "Rise of Rome Prototype.exe"
$package = Join-Path $distributionRoot "Rise of Rome Prototype.pck"
$nativeBuildScript = Join-Path $repositoryRoot "tools\build_native_pathfinding.ps1"
$nativeLibrary = Join-Path $projectRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $qaRoot "full-build-$timestamp.log"
$godotImportLog = Join-Path $qaRoot "full-build-godot-import-$timestamp.log"
$godotExportLog = Join-Path $qaRoot "full-build-godot-export-$timestamp.log"

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
    Write-Progress -Activity "Rise of Rome build" -Status $Status -PercentComplete $Percent
    Write-LogLine ("PROGRESS {0,3}% | {1}" -f $Percent, $Status)
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
        # Compilers commonly use stderr for successful progress messages.
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

function Read-GodotLogUpdates {
    param(
        [System.IO.StreamReader]$Reader,
        [string]$Name,
        [int]$StartPercent,
        [int]$EndPercent,
        [hashtable]$ProgressState
    )
    while (-not $Reader.EndOfStream) {
        $text = $Reader.ReadLine()
        if ($text -match '^\[\s*(\d+)%\s*\]') {
            $inner = [int]$Matches[1]
            # Godot logs each packed resource at the same percentage. Keep
            # those details in the raw Godot log and report each change once.
            if ($inner -eq $ProgressState.InnerPercent) { continue }
            $ProgressState.InnerPercent = $inner
            $mapped = $StartPercent + [int](($EndPercent - $StartPercent) * $inner / 100)
            Write-Progress -Activity "Rise of Rome build" -Status $text -PercentComplete $mapped
        }
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-LogLine ("{0}: {1}" -f $Name, $text)
        }
    }
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
    Write-LogLine ("Full Godot log: {0}" -f $GodotLogPath)
    $process = Start-Process -FilePath $godotApplication -ArgumentList (Join-ProcessArguments $fullArguments) -PassThru -WindowStyle Hidden
    # Retain the handle before waiting, including in Windows PowerShell 5.1.
    $processHandle = $process.Handle
    $reader = $null
    $progressState = @{ InnerPercent = -1 }
    try {
        while (-not $process.WaitForExit(1000)) {
            if ($null -eq $reader -and (Test-Path -LiteralPath $GodotLogPath)) {
                $stream = [System.IO.File]::Open($GodotLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
            }
            if ($null -ne $reader) {
                Read-GodotLogUpdates -Reader $reader -Name $Name -StartPercent $StartPercent -EndPercent $EndPercent -ProgressState $progressState
            }
        }
        $process.WaitForExit()
        if ($null -eq $reader -and (Test-Path -LiteralPath $GodotLogPath)) {
            $stream = [System.IO.File]::Open($GodotLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        }
        if ($null -ne $reader) {
            Read-GodotLogUpdates -Reader $reader -Name $Name -StartPercent $StartPercent -EndPercent $EndPercent -ProgressState $progressState
        }
        Assert-RoRGodotStep -Name $Name -ExitCode $process.ExitCode -LogPath $GodotLogPath
        Write-Status $EndPercent "$Name complete"
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $process.Dispose()
    }
}

try {
    Write-LogLine "Rise of Rome full build started"
    Write-LogLine "Repository: $repositoryRoot"
    Write-Status 0 "checking generated inputs"

    Assert-RoRGeneratedInputs -GeneratedRoot $generatedRoot -IncludeInteractionAssets -RecoveryHint "Run tools\ror-repack-resources.ps1 first."
    Initialize-RoRReleaseTemplate -GodotApplication $godotApplication -ReleaseTemplate $releaseTemplate
    & (Join-Path $PSScriptRoot "prepare-godot-project.ps1")
    Assert-ApplicationNotRunning
    New-Item -ItemType Directory -Force -Path $distributionRoot | Out-Null

    Invoke-LoggedCommand `
        -Name "native pathfinding build" `
        -StartPercent 5 `
        -EndPercent 25 `
        -FilePath "powershell.exe" `
        -Arguments @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", $nativeBuildScript
        )

    if (-not (Test-Path -LiteralPath $nativeLibrary)) {
        throw "Native library was not produced: $nativeLibrary"
    }

    Invoke-GodotLogged `
        -Name "godot resource import" `
        -StartPercent 25 `
        -EndPercent 40 `
        -Arguments @("--headless", "--path", $projectRoot, "--import") `
        -GodotLogPath $godotImportLog

    Invoke-GodotLogged `
        -Name "godot Release export" `
        -StartPercent 40 `
        -EndPercent 92 `
        -Arguments @("--headless", "--path", $projectRoot, "--export-release", "Windows Desktop", $application) `
        -GodotLogPath $godotExportLog

    Write-Status 93 "copying Release runtime files"
    Assert-ApplicationNotRunning
    Copy-RoRReleaseRuntime -RepositoryRoot $repositoryRoot -ProjectRoot $projectRoot -DistributionRoot $distributionRoot -NativeLibrary $nativeLibrary

    Write-Status 98 "verifying Release build artifacts"
    foreach ($item in (Get-RoRReleaseArtifacts -Application $application -Package $package -NativeLibrary (Join-Path $distributionRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll") -GodotApplication $godotApplication)) {
        Write-LogLine ("ARTIFACT: {0} | {1} bytes | {2}" -f $item.FullName, $item.Length, $item.LastWriteTime)
    }

    Write-LogLine "Release artifacts exported and copied."
    if ($VerifyStartup) {
        Write-Status 99 "verifying packaged random map and save loading"
        try {
            & (Join-Path $PSScriptRoot "verify-packaged-startup.ps1")
        }
        catch {
            throw "Release artifacts were exported, but startup verification failed: $($_.Exception.Message)"
        }
        Write-LogLine "Packaged startup verification passed."
    }
    else {
        Write-LogLine "Packaged startup verification was not requested. Use -VerifyStartup or tools\verify-packaged-startup.ps1 to run it."
    }

    Write-Status 100 "full build complete"
    Write-LogLine "Application: $application"
    Write-LogLine "Package: $package"
    Write-LogLine "Log complete: $logPath"
    Write-Progress -Activity "Rise of Rome build" -Completed
    exit 0
}
catch {
    Write-LogLine ("FAILED: {0}" -f $_.Exception.Message)
    Write-Progress -Activity "Rise of Rome build" -Completed
    exit 1
}
