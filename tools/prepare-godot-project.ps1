[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$taskProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "prototype"
$taskDiagnosticRoot = Join-Path $taskProjectRoot "qa"
New-Item -ItemType Directory -Force -Path $taskDiagnosticRoot | Out-Null
$taskIgnoreFile = Join-Path $taskDiagnosticRoot ".gdignore"
if (-not (Test-Path -LiteralPath $taskIgnoreFile)) {
    Set-Content -LiteralPath $taskIgnoreFile -Value "# Diagnostic files must not register project classes." -Encoding UTF8
}
# Repair the generated registry left by earlier builds that scanned backups.
# Keep the imported textures and other costly generated caches intact.
$taskClassCache = Join-Path $taskProjectRoot ".godot\global_script_class_cache.cfg"
if ((Test-Path -LiteralPath $taskClassCache) -and (Select-String -LiteralPath $taskClassCache -SimpleMatch "res://qa/" -Quiet)) {
    Remove-Item -LiteralPath $taskClassCache -Force
    Write-Host "Discarded diagnostic class registrations; Godot will regenerate its class registry."
}
