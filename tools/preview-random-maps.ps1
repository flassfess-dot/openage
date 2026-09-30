[CmdletBinding()]
param([switch]$Capture, [ValidateSet("small_islands", "islands", "coastal", "grasslands", "highlands", "continental", "mediterranean", "hill_country", "narrows")][string]$MapType = "grasslands", [ValidateRange(1, 2147483647)][int]$Seed = 41721)
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskGodot = Join-Path $taskRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
$taskProject = Join-Path $taskRoot 'prototype'
$taskQa = Join-Path $taskProject 'qa\landscape-v2'
New-Item -ItemType Directory -Force -Path $taskQa | Out-Null
$taskArgs = @('--path', ('"' + $taskProject + '"'), '--log-file', ('"' + (Join-Path $taskQa 'preview.log') + '"'), '--resolution', '1440x960')
if ($Capture) {
    $taskArgs += @('--script', 'res://tests/manual/capture_random_map_landscape.gd')
    $taskProcess = Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WorkingDirectory $taskRoot -WindowStyle Hidden -Wait -PassThru
    if ($taskProcess.ExitCode -ne 0) { throw 'Map preview capture failed.' }
} else {
    $taskArgs += @('res://random_map_preview.tscn', '--', ('--map-type=' + $MapType), ('--seed=' + $Seed))
    Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WorkingDirectory $taskRoot | Out-Null
}
