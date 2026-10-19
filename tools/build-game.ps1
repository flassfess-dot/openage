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
$godotRoot = Join-Path $repositoryRoot ".tools\godot-4.7.2"
$godotApplication = Join-Path $godotRoot "Godot_v4.7.2-stable_win64.exe"
$godotHeadless = $godotApplication
$releaseTemplate = Join-Path $godotRoot "windows_release_x86_64.exe"
$application = Join-Path $distributionRoot "Rise of Rome Prototype.exe"
$package = Join-Path $distributionRoot "Rise of Rome Prototype.pck"
$nativeBuildScript = Join-Path $repositoryRoot "tools\build_native_pathfinding.ps1"
$nativeLibrary = Join-Path $projectRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll"

Assert-RoRGeneratedInputs -GeneratedRoot $generatedRoot -RecoveryHint "Run tools\import-assets.ps1 and tools\validate-cache.ps1 first."
Initialize-RoRReleaseTemplate -GodotApplication $godotApplication -ReleaseTemplate $releaseTemplate
& (Join-Path $PSScriptRoot "prepare-godot-project.ps1")
Assert-ApplicationNotRunning
New-Item -ItemType Directory -Force -Path $distributionRoot | Out-Null

& $nativeBuildScript
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $nativeLibrary)) {
    throw "Native pathfinding build did not produce $nativeLibrary"
}

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

$qaRoot = Join-Path $projectRoot "qa\dev-scripts"
New-Item -ItemType Directory -Force -Path $qaRoot | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Invoke-GodotBuildStep -Arguments @("--headless", "--path", $projectRoot, "--import") -Description "Godot resource import" -GodotLogPath (Join-Path $qaRoot "build-godot-import-$timestamp.log")
Invoke-GodotBuildStep -Arguments @("--headless", "--path", $projectRoot, "--export-release", "Windows Desktop", $application) -Description "Godot package export" -GodotLogPath (Join-Path $qaRoot "build-godot-export-$timestamp.log")

Assert-ApplicationNotRunning
Copy-RoRReleaseRuntime -RepositoryRoot $repositoryRoot -ProjectRoot $projectRoot -DistributionRoot $distributionRoot -NativeLibrary $nativeLibrary
Get-RoRReleaseArtifacts -Application $application -Package $package -NativeLibrary (Join-Path $distributionRoot "bin\ror_pathfinding.windows.template_release.x86_64.dll") -GodotApplication $godotApplication | Out-Null
Write-Host "Release artifacts exported and copied: $application"
if ($VerifyStartup) {
    try {
        & (Join-Path $PSScriptRoot "verify-packaged-startup.ps1")
    }
    catch {
        throw "Release artifacts were exported, but startup verification failed: $($_.Exception.Message)"
    }
}
else {
    Write-Host "Packaged startup verification was not requested. Use -VerifyStartup or tools\verify-packaged-startup.ps1 to run it."
}
Write-Host "Build complete: $application"
