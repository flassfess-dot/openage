[CmdletBinding()]
param(
    [string]$SavePath = "",
    [string]$MapSize = "compact",
    [string]$OutputRoot = "",
    [switch]$Rendered
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$taskRepositoryRoot = Split-Path -Parent $PSScriptRoot
$taskDistributionRoot = Join-Path $taskRepositoryRoot "dist\Rise of Rome Prototype"
$taskApplication = Join-Path $taskDistributionRoot "Rise of Rome Prototype.exe"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $taskRepositoryRoot ("prototype\qa\packaged-startup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$taskReport = Join-Path $OutputRoot "report.json"
$taskLog = Join-Path $OutputRoot "runtime.log"
$taskStdout = Join-Path $OutputRoot "stdout.log"
$taskStderr = Join-Path $OutputRoot "stderr.log"
if (Test-Path -LiteralPath $taskReport) { Remove-Item -LiteralPath $taskReport -Force }
$taskArguments = @("--log-file", $taskLog)
if ($Rendered) { $taskArguments += @("--audio-driver", "Dummy", "--resolution", "1280x720") }
else { $taskArguments += "--headless" }
$taskArguments += @("--", "--verify-packaged-startup", "--require-release", "--output=$taskReport", "--map-size=$MapSize")
if ($SavePath) { $taskArguments += "--save=$SavePath" }
$taskQuotedArguments = $taskArguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }
Write-Host "Verifying the exported game: random map and save loading..."
$taskProcess = Start-Process -FilePath $taskApplication -WorkingDirectory $taskDistributionRoot -ArgumentList $taskQuotedArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr
# Windows PowerShell 5.1 must retain the process handle before waiting;
# otherwise redirected GUI processes may expose a null ExitCode after exit.
$taskProcessHandle = $taskProcess.Handle
$taskDeadline = [DateTime]::UtcNow.AddSeconds(300)
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
if (-not $taskResult.passed -or -not $taskResult.release -or $taskResult.stages.Count -ne 2) {
    throw "Exported game failed startup verification. See $taskReport"
}
Write-Host "Exported game passed random-map and save-load verification: $taskReport"
