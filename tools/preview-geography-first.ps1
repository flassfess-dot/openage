[CmdletBinding()]
param(
    [ValidateSet("islands", "coastal", "grasslands", "highlands")][string]$MapType = "islands",
    [ValidateRange(1, 2147483647)][int]$Seed = 41721,
    [ValidateSet("compact", "standard", "large", "huge", "giant", "supergiant")][string]$MapSize = "standard"
)
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskGodot = Join-Path $taskRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
$taskProject = Join-Path $taskRoot 'prototype'
$taskArgs = @('--path', ('"' + $taskProject + '"'), '--resolution', '1440x960', 'res://random_map_preview.tscn', '--', '--geography-first', ('--map-type=' + $MapType), ('--seed=' + $Seed), ('--map-size=' + $MapSize))
Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WorkingDirectory $taskRoot -WindowStyle Hidden | Out-Null
