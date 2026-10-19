# Shared build mechanics. Dot-sourcing declares functions without running a build.

function Get-RoRGeneratedInputFiles {
    param([switch]$IncludeInteractionAssets)
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
    return $requiredGeneratedFiles | Where-Object {
        $IncludeInteractionAssets -or ($_ -notlike "ror_cursor_*" -and $_ -notlike "ror_command_marker_*")
    }
}

function Assert-RoRGeneratedInputs {
    param([string]$GeneratedRoot, [switch]$IncludeInteractionAssets, [string]$RecoveryHint)
    foreach ($file in (Get-RoRGeneratedInputFiles -IncludeInteractionAssets:$IncludeInteractionAssets)) {
        $path = Join-Path $GeneratedRoot $file
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Generated input is missing: $path. $RecoveryHint"
        }
    }
}

function Initialize-RoRReleaseTemplate {
    param([string]$GodotApplication, [string]$ReleaseTemplate)
    if (-not (Test-Path -LiteralPath $GodotApplication)) {
        throw "Missing Godot executable: $GodotApplication"
    }
    if (Test-Path -LiteralPath $ReleaseTemplate) { return }
    $templateArchive = Join-Path (Split-Path -Parent $ReleaseTemplate) "Godot_v4.7.2-stable_export_templates.tpz"
    if (-not (Test-Path -LiteralPath $templateArchive)) { throw "Missing Windows Release template: $ReleaseTemplate" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($templateArchive)
    try {
        $entry = $archive.GetEntry("templates/windows_release_x86_64.exe")
        if ($null -eq $entry) { throw "Windows Release template missing from $templateArchive" }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $ReleaseTemplate, $true)
    } finally { $archive.Dispose() }
}

function Copy-RoRReleaseRuntime {
    param([string]$RepositoryRoot, [string]$ProjectRoot, [string]$DistributionRoot, [string]$NativeLibrary)
    New-Item -ItemType Directory -Force -Path (Join-Path $DistributionRoot "bin") | Out-Null
    Copy-Item -LiteralPath $NativeLibrary -Destination (Join-Path $DistributionRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll") -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $DistributionRoot "legal\MIT") | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot "legal\MIT\godot-cpp.md") -Destination (Join-Path $DistributionRoot "legal\MIT\godot-cpp.md") -Force
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "README.md") -Destination (Join-Path $DistributionRoot "README.md") -Force
}

function Assert-RoRGodotStep {
    param([string]$Name, [object]$ExitCode, [string]$LogPath)
    if ($null -eq $ExitCode) { throw "$Name did not expose an exit code; see $LogPath" }
    if ([int]$ExitCode -ne 0) { throw "$Name failed with exit code $ExitCode; see $LogPath" }
    if (-not (Test-Path -LiteralPath $LogPath)) { throw "$Name did not produce an engine log: $LogPath" }
    # Godot can return zero even after a script fails to compile.
    if (Select-String -LiteralPath $LogPath -Pattern 'SCRIPT ERROR:|Parse Error:|Failed to load script' -Quiet) {
        throw "$Name contains script compilation errors; see $LogPath"
    }
}

function Get-RoRReleaseArtifacts {
    param([string]$Application, [string]$Package, [string]$NativeLibrary, [string]$GodotApplication)
    foreach ($artifact in @($Application, $Package, $NativeLibrary)) {
        if (-not (Test-Path -LiteralPath $artifact)) { throw "Build artifact is missing: $artifact" }
    }
    if ((Get-ArtifactSha256 $Application) -eq (Get-ArtifactSha256 $GodotApplication)) {
        throw "Release executable was replaced by the Godot editor"
    }
    return @($Application, $Package, $NativeLibrary) | ForEach-Object { Get-Item -LiteralPath $_ }
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
