[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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

function Get-ArtifactSha256 {
    param([string]$Path)
    # Also works in child PowerShell sessions with restricted module discovery.
    $stream = [System.IO.File]::OpenRead($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.BitConverter]::ToString($sha.ComputeHash($stream)) }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Assert-ApplicationNotRunning {
    # WMI/CIM process inspection is denied in some managed Windows sessions.
    # The packaged executable has a unique process name, so the ordinary
    # process API provides the same overwrite guard without elevated access.
    $running = @(Get-Process -Name "Rise of Rome Prototype" -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) {
        return
    }
    $processDetails = ($running | ForEach-Object {
        $processPath = ""
        try {
            $processPath = [string]$_.Path
        }
        catch {
            $processPath = "path unavailable"
        }
        "PID {0}: {1}" -f $_.Id, $processPath
    }) -join "; "
    throw "A process is using the packaged executable: $processDetails. Close the visible game or stop the headless test, then run the full build again."
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
                    Write-Progress -Activity "Rise of Rome build" -Status $text -PercentComplete $mapped
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
    # Import/export can return zero even after a script fails to compile.
    if (Test-Path -LiteralPath $GodotLogPath) {
        $scriptErrors = @(Select-String -LiteralPath $GodotLogPath -Pattern 'SCRIPT ERROR:|Parse Error:|Failed to load script')
        if ($scriptErrors.Count -gt 0) { throw "$Name contains script compilation errors; see $GodotLogPath" }
    }
    Write-Status $EndPercent "$Name complete"
}

try {
    Write-LogLine "Rise of Rome full build started"
    Write-LogLine "Repository: $repositoryRoot"
    Write-Status 0 "checking generated inputs"

    $requiredGeneratedFiles = @(
        "assets.json",
        "gamespec-prototype.json",
        "graphics-catalog.json",
        "objects-catalog.json",
        "terrain-catalog.json",
        "localization-catalog.json",
        "sound-catalog.json",
        "scenario-catalog.json",
        "interface-source-inventory.json",
        "interface_panel_0.png",
        "interface_panel_1.png",
        "interface_panel_2.png",
        "interface_panel_3.png",
        "interface\interface_50103.png",
        "interface\interface_50109.png",
        "interface\interface_50115.png",
        "interface\interface_50145.png",
        "hud_shell_640_4_00.png",
        "hud_shell_640_4_01.png",
        "hud_shell_800_4_00.png",
        "hud_shell_800_4_01.png",
        "hud_shell_1024_4_00.png",
        "hud_shell_1024_4_01.png",
        "hud_control_53007_00.png",
        "hud_control_53007_01.png",
        "hud_control_53008_00.png",
        "hud_control_53008_01.png",
        "hud_control_53009_00.png",
        "hud_control_53009_01.png",
        "hud_control_53009_02.png",
        "hud_control_53009_03.png",
        "hud_control_53304_00.png",
        "hud_control_53304_01.png",
        "hud_control_53304_02.png",
        "hud_control_53304_03.png",
        "ror_cursor_00.png",
        "ror_cursor_01.png",
        "ror_cursor_02.png",
        "ror_cursor_03.png",
        "ror_cursor_04.png",
        "ror_cursor_05.png",
        "ror_cursor_06.png",
        "ror_command_marker_01.png",
        "ror_command_marker_02.png",
        "ror_command_marker_03.png",
        "ror_command_marker_04.png",
        "ror_command_marker_05.png",
        "ror_command_marker_06.png",
        "matches\birth-of-rome.json",
        "matches\pyrrhus-of-epirus.json",
        "matches\syracuse.json",
        "matches\metaurus.json",
        "matches\zama.json",
        "matches\mithridates.json",
        "matches\struggle-for-sicily.json",
        "matches\battle-of-mylae.json",
        "matches\battle-of-tunes.json",
        "validation-report.json"
    )
    foreach ($file in $requiredGeneratedFiles) {
        $path = Join-Path $generatedRoot $file
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Generated input is missing: $path. Run tools\ror-repack-resources.ps1 first."
        }
    }
    if (-not (Test-Path -LiteralPath $godotApplication)) {
        throw "Missing Godot executable: $godotApplication"
    }
    if (-not (Test-Path -LiteralPath $releaseTemplate)) {
        $templateArchive = Join-Path (Split-Path -Parent $releaseTemplate) "Godot_v4.7.2-stable_export_templates.tpz"
        if (-not (Test-Path -LiteralPath $templateArchive)) { throw "Missing Windows Release template: $releaseTemplate" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($templateArchive)
        try {
            $entry = $archive.GetEntry("templates/windows_release_x86_64.exe")
            if ($null -eq $entry) { throw "Windows Release template missing from $templateArchive" }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $releaseTemplate, $true)
        } finally { $archive.Dispose() }
    }
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
    New-Item -ItemType Directory -Force -Path (Join-Path $distributionRoot "bin") | Out-Null
    Copy-Item -LiteralPath $nativeLibrary -Destination (Join-Path $distributionRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll") -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $distributionRoot "legal\MIT") | Out-Null
    Copy-Item -LiteralPath (Join-Path $repositoryRoot "legal\MIT\godot-cpp.md") -Destination (Join-Path $distributionRoot "legal\MIT\godot-cpp.md") -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot "README.md") -Destination (Join-Path $distributionRoot "README.md") -Force

    Write-Status 98 "verifying Release build artifacts"
    if ((Get-ArtifactSha256 $application) -eq (Get-ArtifactSha256 $godotApplication)) { throw "Release executable was replaced by the Godot editor" }
    foreach ($artifact in @($application, $package, (Join-Path $distributionRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll"))) {
        if (-not (Test-Path -LiteralPath $artifact)) {
            throw "Build artifact is missing: $artifact"
        }
        $item = Get-Item -LiteralPath $artifact
        Write-LogLine ("ARTIFACT: {0} | {1} bytes | {2}" -f $item.FullName, $item.Length, $item.LastWriteTime)
    }

    Write-Status 99 "verifying packaged random map and save loading"
    & (Join-Path $PSScriptRoot "verify-packaged-startup.ps1")

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
