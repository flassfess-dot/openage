[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projectRoot = Join-Path $repositoryRoot "prototype"
$generatedRoot = Join-Path $projectRoot "assets\generated"
$distributionRoot = Join-Path $repositoryRoot "dist\Rise of Rome Prototype"
$godotRoot = Join-Path $repositoryRoot ".tools\godot-4.7.2"
$godotApplication = Join-Path $godotRoot "Godot_v4.7.2-stable_win64.exe"
$godotHeadless = $godotApplication
$application = Join-Path $distributionRoot "Rise of Rome Prototype.exe"
$package = Join-Path $distributionRoot "Rise of Rome Prototype.pck"

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
    "matches\birth-of-rome.json",
    "matches\pyrrhus-of-epirus.json",
    "matches\syracuse.json",
    "matches\metaurus.json",
    "matches\zama.json",
    "matches\mithridates.json",
    "validation-report.json"
)
foreach ($file in $requiredGeneratedFiles) {
    $path = Join-Path $generatedRoot $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Generated input is missing: $path. Run tools\import-assets.ps1 and tools\validate-cache.ps1 first."
    }
}
if (-not (Test-Path -LiteralPath $godotApplication)) {
    throw "Godot 4.7.2 was not found under $godotRoot"
}

New-Item -ItemType Directory -Force -Path $distributionRoot | Out-Null

function Invoke-GodotBuildStep {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $quotedArguments = $Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        }
        else {
            $_
        }
    }
    $process = Start-Process -FilePath $godotHeadless -ArgumentList $quotedArguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "$Description failed with exit code $($process.ExitCode)"
    }
}

Invoke-GodotBuildStep -Arguments @("--headless", "--path", $projectRoot, "--import") -Description "Godot resource import"
Invoke-GodotBuildStep -Arguments @("--headless", "--path", $projectRoot, "--export-pack", "Windows Desktop", $package) -Description "Godot package export"

Copy-Item -LiteralPath $godotApplication -Destination $application -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "README.md") -Destination (Join-Path $distributionRoot "README.md") -Force
Write-Host "Build complete: $application"
