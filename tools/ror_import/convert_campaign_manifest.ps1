[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GamePath,
    [Parameter(Mandatory = $true)]
    [string]$Manifest,
    [Parameter(Mandatory = $true)]
    [string]$ScenarioCatalog,
    [Parameter(Mandatory = $true)]
    [string]$ObjectCatalog,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [string]$PythonExecutable
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$manifestDefinition = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$converter = Join-Path $PSScriptRoot "convert_campaign_scenario.ps1"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

foreach ($mission in $manifestDefinition.missions) {
    $output = Join-Path $OutputDirectory ([string]$mission.output_filename)
    & $converter `
        -GamePath $GamePath `
        -CampaignFilename ([string]$manifestDefinition.campaign_filename) `
        -ScenarioIndex ([int]$mission.scenario_index) `
        -MatchId ([string]$mission.match_id) `
        -ScenarioCatalog $ScenarioCatalog `
        -ObjectCatalog $ObjectCatalog `
        -Output $output `
        -PythonExecutable $PythonExecutable
    if ($LASTEXITCODE -ne 0) {
        throw "Campaign match conversion failed for $($mission.match_id)."
    }
}
