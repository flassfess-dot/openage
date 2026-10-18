[CmdletBinding()]
param(
    [ValidateSet('small_islands', 'islands', 'coastal', 'grasslands', 'highlands', 'continental', 'mediterranean', 'hill_country', 'narrows')][string]$MapType = 'continental',
    [ValidateSet('compact', 'standard', 'large', 'huge', 'giant', 'supergiant')][string]$MapSize = 'supergiant',
    [ValidateRange(1, 2147483647)][int]$Seed = 41721
)
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskGodot = Join-Path $taskRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
$taskProject = Join-Path $taskRoot 'prototype'
$taskArgs = @('--path', ('"' + $taskProject + '"'), '--resolution', '1440x960', 'res://random_map_preview.tscn', '--', '--watershed-world', ('--map-type=' + $MapType), ('--map-size=' + $MapSize), ('--seed=' + $Seed))
Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WorkingDirectory $taskRoot -WindowStyle Hidden | Out-Null
