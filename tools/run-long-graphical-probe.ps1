[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$SavePath,
 [ValidateSet('source','release')][string]$Runtime='release',
 [ValidateRange(5,7200)][int]$Seconds=1800,
 [ValidateRange(15,7200)][int]$CheckpointEvery=600,
 [string]$OutputRoot=''
)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=Join-Path $taskRoot ('prototype/qa/long-graphics-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
$outputFolder=[IO.Path]::GetFullPath($OutputRoot)

if(Test-Path -LiteralPath $outputFolder){throw 'Probe output already exists'}
New-Item -ItemType Directory -Path $outputFolder | Out-Null
$outputPath=Join-Path $outputFolder 'report.json'
$savePath=(Resolve-Path -LiteralPath $SavePath).Path
$exe=Join-Path $taskRoot '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe'
$workingFolder=$taskRoot
$arguments=@('--path',(Join-Path $taskRoot 'prototype'))
if($Runtime -eq 'release'){
 $workingFolder=Join-Path $taskRoot 'dist/Rise of Rome Prototype'
 $exe=Join-Path $workingFolder 'Rise of Rome Prototype.exe'
 $arguments=@()
}
$stdout=Join-Path $outputFolder 'stdout.log'
$stderr=Join-Path $outputFolder 'stderr.log'
$arguments+=@('--log-file',(Join-Path $outputFolder 'runtime.log'),'--audio-driver','Dummy','--','--profile-long-graphical-match',('--seconds='+$Seconds),('--checkpoint-every='+$CheckpointEvery),('--save='+$savePath),('--output='+$outputPath))
$quotedArguments=$arguments|ForEach-Object{'"'+($_ -replace '"','\"')+'"'}
$probeProcess=Start-Process -FilePath $exe -WorkingDirectory $workingFolder -ArgumentList $quotedArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$processHandle=$probeProcess.Handle
$deadline=[DateTime]::UtcNow.AddSeconds($Seconds+420)
$nextMemory=[DateTime]::UtcNow
$rows=@()
$started=[DateTime]::UtcNow
while(-not $probeProcess.WaitForExit(1000)){
 if([DateTime]::UtcNow -ge $deadline){Stop-Process -Id $probeProcess.Id -Force;throw 'Graphical probe timeout'}
 foreach($probeLog in @($stderr,$stdout,(Join-Path $outputFolder 'runtime.log'))){
  if((Test-Path -LiteralPath $probeLog) -and (Select-String -LiteralPath $probeLog -Pattern 'SCRIPT ERROR:|ERROR:|Parse Error:' -Quiet)){Stop-Process -Id $probeProcess.Id -Force;throw ('Graphical engine error: '+$probeLog)}
 }
 if([DateTime]::UtcNow -ge $nextMemory){
  $probeProcess.Refresh()
  $rows += [pscustomobject]@{seconds=([DateTime]::UtcNow-$started).TotalSeconds;pid=$probeProcess.Id;working_set_bytes=$probeProcess.WorkingSet64;private_bytes=$probeProcess.PrivateMemorySize64}
  $rows|ConvertTo-Json -Depth 3|Set-Content -LiteralPath (Join-Path $outputFolder 'process-memory.json') -Encoding UTF8
  $nextMemory=[DateTime]::UtcNow.AddSeconds(15)
 }
}
$probeProcess.WaitForExit()
foreach($probeLog in @($stderr,$stdout,(Join-Path $outputFolder 'runtime.log'))){
 if((Test-Path -LiteralPath $probeLog) -and (Select-String -LiteralPath $probeLog -Pattern 'SCRIPT ERROR:|ERROR:|Parse Error:' -Quiet)){throw ('Graphical engine error: '+$probeLog)}
}
if($probeProcess.ExitCode -ne 0){throw ('Graphical probe failed: '+$probeProcess.ExitCode)}
if(-not (Test-Path -LiteralPath $outputPath)){throw 'Graphical probe report missing'}
$r=Get-Content -LiteralPath $outputPath -Raw|ConvertFrom-Json
if($r.canonical_failures -ne 0 -or $r.ticks_completed -le 0 -or $r.frame_us.count -le 0 -or $r.seconds_actual -lt $Seconds){throw 'Graphical probe acceptance failed'}
if($Runtime -eq 'release' -and (-not $r.release -or $r.runtime.debug -or $r.runtime.editor -or -not $r.native_classes.retained_movement -or -not $r.native_classes.ai_projection)){throw 'Graphical probe did not use the current Release/native runtime'}
if($Seconds -ge 120){
 $scenario=$r.player_scenario
 if($scenario.build_orders -lt 2 -or -not $scenario.house_completed -or -not $scenario.foundation_cancelled_with_journal -or $scenario.explored_after -le $scenario.explored_before -or @($r.actions|Where-Object {$_.type -eq 'formation_order'}).Count -eq 0){throw 'Graphical player scenario did not complete the required build, cancel, movement and exploration actions'}
}
[pscustomobject]@{release=$r.release;seconds=$r.seconds_actual;ticks=$r.ticks_completed;canonical_failures=$r.canonical_failures;frames=$r.frame_us;output=$outputPath}|ConvertTo-Json -Depth 4
