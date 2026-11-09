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
$godotRoot = Join-Path $repositoryRoot ".tools\godot-4.7.2"
$godotApplication = Join-Path $godotRoot "Godot_v4.7.2-stable_win64.exe"
$godotHeadless = $godotApplication
$releaseTemplate = Join-Path $godotRoot "windows_release_x86_64.exe"
$nativeBuildScript = Join-Path $repositoryRoot "tools\build_native_pathfinding.ps1"
$nativeLibrary = Join-Path $projectRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll"

function Invoke-GodotBuildStep {
    param([string[]]$Arguments, [string]$Description, [string]$GodotLogPath)
    if (Test-Path -LiteralPath $GodotLogPath) { Remove-Item -LiteralPath $GodotLogPath -Force }
    $fullArguments = @("--log-file", $GodotLogPath) + $Arguments
    $process = Start-Process -FilePath $godotHeadless -ArgumentList (Join-ProcessArguments $fullArguments) -PassThru -WindowStyle Hidden
    # Retain the handle before waiting, including in Windows PowerShell 5.1.
    $processHandle = $process.Handle
    try {
        $process.WaitForExit()
        Assert-RoRGodotStep -Name $Description -ExitCode $process.ExitCode -LogPath $GodotLogPath
    }
    finally { $process.Dispose() }
}

$releaseBuild = Start-RoRReleaseBuild $repositoryRoot
try {
    $distributionRoot = $releaseBuild.Directory
    $application = Join-Path $distributionRoot "Rise of Rome Prototype.exe"
    $package = Join-Path $distributionRoot "Rise of Rome Prototype.pck"
    Assert-RoRGeneratedInputs -GeneratedRoot $generatedRoot -RecoveryHint "Run tools\import-assets.ps1 and tools\validate-cache.ps1 first."
    Initialize-RoRReleaseTemplate -GodotApplication $godotApplication -ReleaseTemplate $releaseTemplate
    & (Join-Path $PSScriptRoot "prepare-godot-project.ps1")
    New-Item -ItemType Directory -Force -Path $distributionRoot | Out-Null

    & $nativeBuildScript
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $nativeLibrary)) {
        throw "Native pathfinding build did not produce $nativeLibrary"
    }

    $qaRoot = Join-Path $projectRoot "qa\dev-scripts"
    New-Item -ItemType Directory -Force -Path $qaRoot | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $provenanceState = Join-Path $qaRoot "build-source-$timestamp.json"
    & python (Join-Path $PSScriptRoot "ai_build_manifest.py") begin --state $provenanceState
    if ($LASTEXITCODE -ne 0) { throw "Unable to freeze Release source manifest" }
    Invoke-GodotBuildStep -Arguments @("--headless", "--path", $projectRoot, "--import") -Description "Godot resource import" -GodotLogPath (Join-Path $qaRoot "build-godot-import-$timestamp.log")
    Assert-ApplicationNotRunning -Application $application
    Invoke-GodotBuildStep -Arguments @("--headless", "--path", $projectRoot, "--export-release", "Windows Desktop", $application) -Description "Godot package export" -GodotLogPath (Join-Path $qaRoot "build-godot-export-$timestamp.log")

    Assert-ApplicationNotRunning -Application $application
    Copy-RoRReleaseRuntime -RepositoryRoot $repositoryRoot -ProjectRoot $projectRoot -DistributionRoot $distributionRoot -NativeLibrary $nativeLibrary
    Get-RoRReleaseArtifacts -Application $application -Package $package -NativeLibrary (Join-Path $distributionRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll") -GodotApplication $godotApplication | Out-Null
    & python (Join-Path $PSScriptRoot "ai_build_manifest.py") finish --state $provenanceState --directory $distributionRoot
    if ($LASTEXITCODE -ne 0) { throw "Release source verification failed" }
    Write-Host "Release artifacts exported and copied: $application"
    if ($VerifyStartup) {
        try {
            & (Join-Path $PSScriptRoot "verify-packaged-startup.ps1") -Application $application
        }
        catch {
            throw "Release artifacts were exported, but startup verification failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Packaged startup verification was not requested. Use -VerifyStartup or tools\verify-packaged-startup.ps1 to run it."
    }
    Publish-RoRReleaseBuild $releaseBuild
    Write-Host "Build complete: $application"
} finally {
    $releaseBuild.Lock.Dispose()
}
