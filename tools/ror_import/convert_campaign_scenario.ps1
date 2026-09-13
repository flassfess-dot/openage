[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GamePath,
    [Parameter(Mandatory = $true)]
    [string]$CampaignFilename,
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 255)]
    [int]$ScenarioIndex,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z][a-z0-9_]*$')]
    [string]$MatchId,
    [Parameter(Mandatory = $true)]
    [string]$ScenarioCatalog,
    [Parameter(Mandatory = $true)]
    [string]$ObjectCatalog,
    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$importerRoot = $PSScriptRoot
$campaignRoot = (Resolve-Path -LiteralPath (Join-Path $GamePath "campaign")).Path
$campaign = Join-Path $campaignRoot $CampaignFilename
$resolvedCampaign = (Resolve-Path -LiteralPath $campaign).Path
$campaignPrefix = $campaignRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedCampaign.StartsWith($campaignPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Campaign must be located under the Rise of Rome campaign directory."
}

$manifest = Join-Path $importerRoot "scenario_converter\Cargo.toml"
$archetypes = Join-Path $importerRoot "runtime-archetypes.json"
$builder = Join-Path $importerRoot "build_scenario_match.py"
$cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
$cargo = if ($cargoCommand) {
    $cargoCommand.Source
} else {
    Join-Path ([Environment]::GetFolderPath("UserProfile")) ".cargo\bin\cargo.exe"
}
if (-not (Test-Path -LiteralPath $cargo)) {
    throw "Rust/Cargo is required once to import campaign scenarios. Install Rustup first."
}

$temporary = New-TemporaryFile
try {
    $cargoArguments = @(
        "+stable-x86_64-pc-windows-gnu", "run",
        "--manifest-path", $manifest,
        "--release", "--",
        "--campaign", $resolvedCampaign,
        "--scenario-index", [string]$ScenarioIndex,
        "--output", $temporary.FullName
    )
    & $cargo @cargoArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Raw campaign scenario conversion failed with exit code $LASTEXITCODE"
    }
    $pythonArguments = @(
        "-3", $builder,
        "--raw", $temporary.FullName,
        "--catalog", $ScenarioCatalog,
        "--archetypes", $archetypes,
        "--objects", $ObjectCatalog,
        "--match-id", $MatchId,
        "--output", $Output
    )
    & py @pythonArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Campaign match conversion failed with exit code $LASTEXITCODE"
    }
}
finally {
    if (Test-Path -LiteralPath $temporary.FullName) {
        Remove-Item -LiteralPath $temporary.FullName -Force
    }
}
