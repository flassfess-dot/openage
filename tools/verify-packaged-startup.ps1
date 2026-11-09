[CmdletBinding()]
param(
    [string]$Application = "",
    [string]$SavePath = "",
    [string]$MapSize = "compact",
    [string]$MapType = "grasslands",
    [string]$OutputRoot = "",
    [switch]$Rendered,
    [switch]$Competitive,
    [switch]$CombatFixture,
    [switch]$NavalFixture,
    [switch]$RenderedLoadFixture
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if ($RenderedLoadFixture -and (-not $Rendered -or $CombatFixture -or $NavalFixture -or $SavePath)) {
    throw "RenderedLoadFixture requires Rendered and a new dedicated match without combat/naval/save fixtures."
}
if ($SavePath -and -not $SavePath.StartsWith('user://') -and -not $SavePath.StartsWith('res://')) {
    $SavePath = [System.IO.Path]::GetFullPath($SavePath)
}
$taskRepositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "ror-build-common.ps1")
$taskDistributionRoot = Get-RoRReleaseDirectory $taskRepositoryRoot
$taskApplication = Join-Path $taskDistributionRoot "Rise of Rome Prototype.exe"
if ($Application) {
    $taskApplication = [System.IO.Path]::GetFullPath($Application)
    $taskDistributionRoot = Split-Path -Parent $taskApplication
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $taskRepositoryRoot ("prototype\qa\packaged-startup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$taskReport = Join-Path $OutputRoot "report.json"
$taskLog = Join-Path $OutputRoot "runtime.log"
$taskStdout = Join-Path $OutputRoot "stdout.log"
$taskStderr = Join-Path $OutputRoot "stderr.log"
$taskReceipt = Join-Path $OutputRoot "verified-artifacts.json"
if (Test-Path -LiteralPath $taskReport) { Remove-Item -LiteralPath $taskReport -Force }
if (Test-Path -LiteralPath $taskReceipt) { Remove-Item -LiteralPath $taskReceipt -Force }
$taskArtifactNames = @((Split-Path -Leaf $taskApplication), [System.IO.Path]::GetFileName([System.IO.Path]::ChangeExtension($taskApplication, ".pck")), "bin/ror_pathfinding.windows.template_release.x86_64.dll")
$taskArtifactHashes = [ordered]@{}
foreach ($taskArtifactName in $taskArtifactNames) {
    $taskArtifactHashes[$taskArtifactName] = (Get-ArtifactSha256 (Join-Path $taskDistributionRoot $taskArtifactName)).Replace("-", "").ToLowerInvariant()
}
$taskArguments = @("--log-file", $taskLog)
if ($Rendered) { $taskArguments += @("--audio-driver", "Dummy", "--resolution", "1280x720") }
else { $taskArguments += "--headless" }
$taskArguments += @("--", "--verify-packaged-startup", "--require-release", "--output=$taskReport", "--map-size=$MapSize", "--map-type=$MapType")
if ($Rendered) { $taskArguments += "--capture-rendered-startup" }
if ($Competitive) { $taskArguments += "--competitive-ai" }
if ($CombatFixture) { $taskArguments += "--combat-fixture" }
if ($NavalFixture) { $taskArguments += "--naval-fixture" }
if ($RenderedLoadFixture) { $taskArguments += "--rendered-load-fixture" }
if ($SavePath) { $taskArguments += "--save=$SavePath" }
$taskQuotedArguments = $taskArguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }
Write-Host "Verifying the exported game: random map and save loading..."
$taskProcess = Start-Process -FilePath $taskApplication -WorkingDirectory $taskDistributionRoot -ArgumentList $taskQuotedArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr
# Windows PowerShell 5.1 must retain the process handle before waiting;
# otherwise redirected GUI processes may expose a null ExitCode after exit.
$taskProcessHandle = $taskProcess.Handle
$taskDeadline = [DateTime]::UtcNow.AddSeconds($(if ($RenderedLoadFixture) { 600 } else { 300 }))
while (-not $taskProcess.WaitForExit(1000)) {
    if ([DateTime]::UtcNow -ge $taskDeadline) {
        Stop-Process -Id $taskProcess.Id -Force -ErrorAction SilentlyContinue
        throw "Packaged startup verification timed out. See $OutputRoot"
    }
    if ((Test-Path -LiteralPath $taskLog) -and (Select-String -LiteralPath $taskLog -Pattern 'SCRIPT ERROR:|ERROR:|Parse Error:|Failed to load script' -Quiet)) {
        Stop-Process -Id $taskProcess.Id -Force -ErrorAction SilentlyContinue
        throw "Packaged startup verification contains runtime errors. See $taskLog"
    }
}
$taskProcess.WaitForExit()
if ($taskProcess.ExitCode -ne 0) { throw "Packaged startup verification exited with $($taskProcess.ExitCode). See $OutputRoot" }
foreach ($taskLogFile in @($taskLog, $taskStdout, $taskStderr)) {
    if ((Test-Path -LiteralPath $taskLogFile) -and (Select-String -LiteralPath $taskLogFile -Pattern 'SCRIPT ERROR:|ERROR:|Parse Error:|Failed to load script' -Quiet)) {
        throw "Packaged startup verification contains runtime errors. See $taskLogFile"
    }
}
if (-not (Test-Path -LiteralPath $taskReport)) { throw "Exported game did not produce a startup verification report. See $OutputRoot" }
$taskResult = Get-Content -LiteralPath $taskReport -Raw | ConvertFrom-Json
$taskExpectedStages = if ($RenderedLoadFixture) { 1 } elseif ($Competitive) { 3 } else { 2 }
if (-not $taskResult.passed -or -not $taskResult.release -or $taskResult.stages.Count -ne $taskExpectedStages) {
    throw "Exported game failed startup verification. See $taskReport"
}
if ($RenderedLoadFixture) {
    $taskLoad = $taskResult.rendered_load
    if ($taskLoad.initial_units_by_team.'1' -ne 500 -or $taskLoad.initial_units_by_team.'2' -ne 500 -or $taskLoad.frames -lt 30 -or $taskLoad.fixed_ticks -le 0 -or $taskLoad.owner_started_samples -le 0 -or $taskLoad.sample_seconds -lt 20) {
        throw "Rendered load did not verify the required 2x500 workload, ordinary owner and simulation progress. See $taskReport"
    }
}
foreach ($taskArtifactName in $taskArtifactNames) {
    if ((Get-ArtifactSha256 (Join-Path $taskDistributionRoot $taskArtifactName)).Replace("-", "").ToLowerInvariant() -ne $taskArtifactHashes[$taskArtifactName]) {
        throw "Packaged artifact changed during startup verification: $taskArtifactName"
    }
}
$taskVerifiedArtifacts = [ordered]@{
    schema_version = 1
    application = $taskApplication
    artifacts = $taskArtifactHashes
    passed = $true
    rendered = [bool]$Rendered
    competitive = [bool]$Competitive
    map_type = $MapType
    rendered_load_fixture = [bool]$RenderedLoadFixture
    completed_utc = [DateTime]::UtcNow.ToString("o")
}
[System.IO.File]::WriteAllText($taskReceipt + ".pending", ($taskVerifiedArtifacts | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Move-Item -LiteralPath ($taskReceipt + ".pending") -Destination $taskReceipt
if ($RenderedLoadFixture) { Write-Host "Exported game passed rendered 2x500 workload verification: $taskReport" }
else { Write-Host "Exported game passed random-map and save-load verification: $taskReport" }
