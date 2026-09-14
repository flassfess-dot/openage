[CmdletBinding()]
param(
    [string]$GamePath = "D:\Games\Age of Empires 1 - Rise of Rome",
    [string]$ScenarioCatalog,
    [string]$ObjectCatalog,
    [string]$RuntimeCatalog,
    [string]$AssetsRoot,
    [string]$Output,
    [string]$PythonExecutable
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$generatedRoot = Join-Path $repositoryRoot "prototype\assets\generated"
$manifestPath = Join-Path $repositoryRoot "prototype\data\campaigns\first_punic_war.json"
$converter = Join-Path $PSScriptRoot "convert_campaign_scenario.ps1"
$auditor = Join-Path $PSScriptRoot "build_campaign_gap_matrix.py"
if (-not $ScenarioCatalog) { $ScenarioCatalog = Join-Path $generatedRoot "scenario-catalog.json" }
if (-not $ObjectCatalog) { $ObjectCatalog = Join-Path $generatedRoot "objects-catalog.json" }
if (-not $RuntimeCatalog) { $RuntimeCatalog = Join-Path $generatedRoot "runtime-catalog.json" }
if (-not $AssetsRoot) { $AssetsRoot = $generatedRoot }
if (-not $Output) { $Output = Join-Path $repositoryRoot "prototype\data\content_waves\first_punic_war_campaign.json" }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ("ror-first-punic-audit-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
try {
    foreach ($mission in $manifest.missions) {
        $temporaryMatch = Join-Path $temporaryDirectory ("{0}.json" -f [int]$mission.scenario_index)
        & $converter `
            -GamePath $GamePath `
            -CampaignFilename ([string]$manifest.campaign_filename) `
            -ScenarioIndex ([int]$mission.scenario_index) `
            -MatchId ([string]$mission.match_id) `
            -ScenarioCatalog $ScenarioCatalog `
            -ObjectCatalog $ObjectCatalog `
            -Output $temporaryMatch `
            -PythonExecutable $PythonExecutable
        if ($LASTEXITCODE -ne 0) {
            throw "Mission conversion failed for scenario $($mission.scenario_index)."
        }
    }
    $pythonCommand = "py"
    $pythonPrefix = @("-3")
    if ($PythonExecutable) {
        $pythonCommand = (Resolve-Path -LiteralPath $PythonExecutable).Path
        $pythonPrefix = @()
    }
    & $pythonCommand @pythonPrefix $auditor `
        --manifest $manifestPath `
        --catalog $ScenarioCatalog `
        --runtime-catalog $RuntimeCatalog `
        --assets-root $AssetsRoot `
        --matches-directory $temporaryDirectory `
        --output $Output
    if ($LASTEXITCODE -ne 0) {
        throw "Campaign gap matrix audit failed with exit code $LASTEXITCODE"
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
