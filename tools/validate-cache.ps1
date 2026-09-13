[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$generatedRoot = Join-Path $repositoryRoot "prototype\assets\generated"
$validator = Join-Path $repositoryRoot "tools\ror_import\validate_cache.py"
$jsonReport = Join-Path $generatedRoot "validation-report.json"
$markdownReport = Join-Path $repositoryRoot "doc\ror-modern\CACHE_VALIDATION_REPORT.md"

& py -3 $validator `
    --cache-dir $generatedRoot `
    --json-output $jsonReport `
    --markdown-output $markdownReport
if ($LASTEXITCODE -ne 0) {
    throw "Cache validation failed with exit code $LASTEXITCODE"
}

Write-Host "Validation complete: $markdownReport"
