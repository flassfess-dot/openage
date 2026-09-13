[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$distributionRoot = Join-Path $repositoryRoot "dist\Rise of Rome Prototype"
$application = Join-Path $distributionRoot "Rise of Rome Prototype.exe"
$package = Join-Path $distributionRoot "Rise of Rome Prototype.pck"

if (-not (Test-Path -LiteralPath $application) -or -not (Test-Path -LiteralPath $package)) {
    throw "The ready build is missing. Run tools\build-game.ps1 once."
}

Start-Process -FilePath $application -WorkingDirectory $distributionRoot
