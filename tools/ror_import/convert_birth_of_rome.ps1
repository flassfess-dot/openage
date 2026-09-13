[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GamePath,
    [Parameter(Mandatory = $true)]
    [string]$ScenarioCatalog,
    [Parameter(Mandatory = $true)]
    [string]$ObjectCatalog,
    [Parameter(Mandatory = $true)]
    [string]$Output
)

& (Join-Path $PSScriptRoot "convert_campaign_scenario.ps1") `
    -GamePath $GamePath `
    -CampaignFilename "Расцвет Рима.cpx" `
    -ScenarioIndex 0 `
    -MatchId "campaign_birth_of_rome" `
    -ScenarioCatalog $ScenarioCatalog `
    -ObjectCatalog $ObjectCatalog `
    -Output $Output
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
