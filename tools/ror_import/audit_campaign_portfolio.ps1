[CmdletBinding()]
param(
    [string]$GamePath = "D:\Games\Age of Empires 1 - Rise of Rome",
    [ValidateRange(1, 16)]
    [int]$Workers = 4,
    [string]$Output,
    [string]$PythonExecutable
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$generatedRoot = Join-Path $repositoryRoot "prototype\assets\generated"
$manifest = Join-Path $repositoryRoot "prototype\data\campaigns\source_campaign_portfolio.json"
$scenarioCatalog = Join-Path $generatedRoot "scenario-catalog.json"
$objectCatalog = Join-Path $generatedRoot "objects-catalog.json"
$runtimeCatalog = Join-Path $generatedRoot "runtime-catalog.json"
$archetypes = Join-Path $PSScriptRoot "runtime-archetypes.json"
$converter = Join-Path $PSScriptRoot "scenario_converter\target\release\ror-scenario-converter.exe"
$manifestBuilder = Join-Path $PSScriptRoot "build_campaign_portfolio_manifest.py"
$matchBuilder = Join-Path $PSScriptRoot "build_scenario_match.py"
$matrixBuilder = Join-Path $PSScriptRoot "build_campaign_portfolio_gap_matrix.py"
$auditor = Join-Path $PSScriptRoot "audit_campaign_portfolio.py"
$publishedManifests = @(
    (Join-Path $repositoryRoot "prototype\data\campaigns\rise_of_rome.json"),
    (Join-Path $repositoryRoot "prototype\data\campaigns\first_punic_war.json")
)
if (-not $Output) {
    $Output = Join-Path $repositoryRoot "prototype\data\content_waves\source_campaign_portfolio.json"
}
$pythonCommand = "py"
$pythonPrefix = @("-3")
if ($PythonExecutable) {
    $pythonCommand = (Resolve-Path -LiteralPath $PythonExecutable).Path
    $pythonPrefix = @()
}

if (-not (Test-Path -LiteralPath $converter -PathType Leaf)) {
    $cargoManifest = Join-Path $PSScriptRoot "scenario_converter\Cargo.toml"
    & cargo +stable-x86_64-pc-windows-gnu build --manifest-path $cargoManifest --release
    if ($LASTEXITCODE -ne 0) {
        throw "Scenario converter build failed with exit code $LASTEXITCODE"
    }
}

& $pythonCommand @pythonPrefix $manifestBuilder --catalog $scenarioCatalog --output $manifest
if ($LASTEXITCODE -ne 0) {
    throw "Portfolio manifest generation failed with exit code $LASTEXITCODE"
}

& $pythonCommand @pythonPrefix $auditor `
    --game-path $GamePath `
    --manifest $manifest `
    --catalog $scenarioCatalog `
    --objects $objectCatalog `
    --runtime-catalog $runtimeCatalog `
    --assets-root $generatedRoot `
    --archetypes $archetypes `
    --converter $converter `
    --match-builder $matchBuilder `
    --matrix-builder $matrixBuilder `
    --published-manifest $publishedManifests[0] `
    --published-manifest $publishedManifests[1] `
    --output $Output `
    --workers $Workers
if ($LASTEXITCODE -ne 0) {
    throw "Portfolio audit failed with exit code $LASTEXITCODE"
}
