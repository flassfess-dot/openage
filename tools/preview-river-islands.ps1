[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$taskGodot = Join-Path $taskRoot '.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe'
$taskProject = Join-Path $taskRoot 'prototype'
$taskArgs = @('--path', ('"' + $taskProject + '"'), '--resolution', '1440x960', 'res://random_map_preview.tscn', '--', '--river-islands', '--map-type=islands', '--map-size=supergiant', '--seed=41721')
$taskFixture = Join-Path $taskProject 'qa\river-islands-one-20261018\map.bin'
if (Test-Path -LiteralPath $taskFixture) { $taskArgs += '--preview-fixture=res://qa/river-islands-one-20261018/map.bin' }
Start-Process -FilePath $taskGodot -ArgumentList $taskArgs -WorkingDirectory $taskRoot -WindowStyle Hidden | Out-Null
