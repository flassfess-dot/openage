[CmdletBinding()]
param(
    [string]$AoE2Path = 'D:\Games\Age of Empires II',
    [switch]$Reimport,
    [switch]$Capture,
    [switch]$TestOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskProject = Join-Path $taskRoot 'prototype'
$taskNode = Join-Path $taskRoot '.tools\nodejs\node.exe'
$taskGodot = Join-Path $taskRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
$taskDefinition = Join-Path $taskProject 'data\environment\aoe2_temperate.json'
$taskManifest = Join-Path $taskProject 'assets\generated\environment\aoe2_temperate\manifest.json'
$taskQa = Join-Path $taskProject 'qa\environment-pack'
New-Item -ItemType Directory -Force -Path $taskQa | Out-Null
if (-not (Test-Path -LiteralPath $taskGodot)) { throw 'The project Godot runtime is missing from .tools.' }
$taskNeedsImport = $Reimport -or -not (Test-Path -LiteralPath $taskManifest)
if (-not $taskNeedsImport) {
    $taskPack = Get-Content -LiteralPath $taskManifest -Raw | ConvertFrom-Json
    $taskHash = (Get-FileHash -LiteralPath $taskDefinition -Algorithm SHA256).Hash.ToLowerInvariant()
    $taskNeedsImport = $taskPack.definition_sha256 -ne $taskHash
    $taskAssetRoot = Split-Path -Parent $taskManifest
    function Test-EnvironmentImage {
        param($Record)
        $taskImagePath = Join-Path $taskAssetRoot $Record.file
        if (-not (Test-Path -LiteralPath $taskImagePath)) { return $false }
        return (Get-FileHash -LiteralPath $taskImagePath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Record.sha256
    }
    foreach ($taskMaterial in $taskPack.materials.PSObject.Properties) {
        $taskNeedsImport = $taskNeedsImport -or -not (Test-EnvironmentImage $taskMaterial.Value)
    }
    foreach ($taskObject in $taskPack.objects.PSObject.Properties) {
        foreach ($taskFrame in $taskObject.Value.frames) {
            $taskNeedsImport = $taskNeedsImport -or -not (Test-EnvironmentImage $taskFrame)
        }
    }
}
if ($taskNeedsImport) {
    if (-not (Test-Path -LiteralPath $taskNode)) { throw 'The project Node runtime is missing from .tools.' }
    & $taskNode (Join-Path $PSScriptRoot 'ror_import\import_environment.js') --game $AoE2Path
    if ($LASTEXITCODE -ne 0) { throw 'AoE2 environment import failed.' }
}

function Invoke-EnvironmentGodot {
    param([string[]]$Arguments, [string]$LogName, [switch]$Interactive)
    $taskLog = Join-Path $taskQa $LogName
    $taskArgs = @('--path', ('"' + $taskProject + '"'), '--log-file', ('"' + $taskLog + '"')) + $Arguments
    if ($Interactive) {
        # The requested interactive review window must remain visible to the user.
        Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WorkingDirectory $taskRoot -WindowStyle Normal | Out-Null
        return
    }
    $taskRun = Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru -Wait
    $taskLogText = if (Test-Path -LiteralPath $taskLog) { Get-Content -LiteralPath $taskLog -Raw } else { '' }
    if ($taskRun.ExitCode -ne 0 -or $taskLogText -match '(?m)^(SCRIPT ERROR|ERROR):') {
        throw "Environment validation failed. See $taskLog"
    }
}

# A first checkout and newly added art need Godot's normal resource import.
$taskImportMarker = Join-Path $taskProject 'assets\generated\environment\aoe2_temperate\earth.png.import'
if ($taskNeedsImport -or -not (Test-Path -LiteralPath $taskImportMarker) -or -not (Test-Path -LiteralPath (Join-Path $taskProject '.godot\imported'))) {
    Invoke-EnvironmentGodot -Arguments @('--headless', '--editor', '--import', '--quit') -LogName 'import.log'
}
if ($TestOnly) {
    Invoke-EnvironmentGodot -Arguments @('--headless', '--script', 'res://tests/unit/test_environment_pack.gd', '--', '--require-pack') -LogName 'tests.log'
    Write-Output 'Environment pack tests passed.'
} elseif ($Capture) {
    Invoke-EnvironmentGodot -Arguments @('--script', 'res://tests/manual/capture_environment_pack.gd', '--resolution', '1440x960') -LogName 'capture.log'
    Write-Output "Saved landscape.png, objects.png and surfaces.png in $taskQa"
} else {
    Invoke-EnvironmentGodot -Arguments @('res://environment_preview.tscn', '--resolution', '1440x960') -LogName 'preview.log' -Interactive
}
