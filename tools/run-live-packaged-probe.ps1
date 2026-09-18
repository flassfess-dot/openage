[CmdletBinding()]
param(
    [string]$Match = "prototype_skirmish",
    [ValidatePattern('^\d+x\d+$')]
    [string]$Size = "1280x720",
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$distributionRoot = Join-Path $repositoryRoot "dist\Rise of Rome Prototype"
$application = Join-Path $distributionRoot "Rise of Rome Prototype.exe"
$package = Join-Path $distributionRoot "Rise of Rome Prototype.pck"
if (-not (Test-Path -LiteralPath $application) -or -not (Test-Path -LiteralPath $package)) {
    throw "The packaged build is missing. Run tools\build-game.ps1 first."
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repositoryRoot "prototype\qa\live-packaged-probe"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$report = Join-Path $OutputRoot "report.json"

$arguments = @(
    "--audio-driver",
    "Dummy",
    "--script",
    "res://tests/manual/live_packaged_game_probe.gd",
    "--",
    "--size=$Size",
    "--output=$($report.Replace('\', '/'))",
    "--match=$Match"
)
$quotedArguments = $arguments | ForEach-Object {
    if ($_ -match '[\s"]') {
        '"' + ($_ -replace '"', '\"') + '"'
    }
    else {
        $_
    }
}

$process = Start-Process `
    -FilePath $application `
    -WorkingDirectory $distributionRoot `
    -ArgumentList $quotedArguments `
    -Wait `
    -PassThru
if ($process.ExitCode -ne 0) {
    throw "Live packaged probe failed with exit code $($process.ExitCode)."
}
if (-not (Test-Path -LiteralPath $report)) {
    throw "Live packaged probe did not create $report."
}

$result = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
Write-Host "Live packaged probe complete: $report"
foreach ($stageName in @("idle", "movement", "pan")) {
    $stage = $result.stages.$stageName
    Write-Host ("{0}: frame p50={1:N3} ms, p95={2:N3} ms, max={3:N3} ms, draw calls p95={4}" -f `
        $stageName,
        ([double]$stage.frame_wall_microseconds.p50 / 1000.0),
        ([double]$stage.frame_wall_microseconds.p95 / 1000.0),
        ([double]$stage.frame_wall_microseconds.max / 1000.0),
        $stage.draw_calls.p95)
}

