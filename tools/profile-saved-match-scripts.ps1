[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Save,
    [string]$OutputDirectory = "",
    [string]$ProjectPath = "",
    [ValidateRange(40,3600)][int]$Seconds=60
)
$ErrorActionPreference='Stop'
$rorRepository=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rorGodot=Join-Path $rorRepository '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe'
$rorProject=if($ProjectPath) {(Resolve-Path -LiteralPath $ProjectPath).Path} else {Join-Path $rorRepository 'prototype'}
$Save=(Resolve-Path -LiteralPath $Save).Path
$rorOutput=if($OutputDirectory) {[IO.Path]::GetFullPath($OutputDirectory)} else {Join-Path $rorRepository ('prototype/qa/script-profile-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
if(Test-Path -LiteralPath $rorOutput) {throw 'Choose a fresh diagnostic output directory'}
New-Item -ItemType Directory -Path $rorOutput | Out-Null
$rorCollectorProject=Join-Path $rorOutput 'collector-project'
New-Item -ItemType Directory -Path $rorCollectorProject | Out-Null
$rorCollectorConfig=@'
config_version=5
[application]
config/name="RoR diagnostic profiler collector"
[rendering]
renderer/rendering_method="gl_compatibility"
'@
[IO.File]::WriteAllText((Join-Path $rorCollectorProject 'project.godot'),$rorCollectorConfig,[Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'collect-gdscript-profile.gd') -Destination (Join-Path $rorCollectorProject 'collect_script_profile.gd')
$rorProfile=Join-Path $rorOutput 'script-functions.json'
$rorCollectorLog=Join-Path $rorOutput 'collector.log'
$rorCollectorArgs=@('--headless','--path',$rorCollectorProject,'--script',(Join-Path $rorCollectorProject 'collect_script_profile.gd'),'--log-file',$rorCollectorLog,'--',('--output='+$rorProfile))
$rorCollector=Start-Process -FilePath $rorGodot -ArgumentList ($rorCollectorArgs | ForEach-Object {'"'+$_+'"'}) -WindowStyle Hidden -PassThru
$null=$rorCollector.Handle
Write-Output ('Collector PID='+$rorCollector.Id)
$rorGame=$null
try {
    $rorListenDeadline=(Get-Date).AddSeconds(20)
    while(-not (Test-Path -LiteralPath ($rorProfile+'.ready'))) {
        if($rorCollector.WaitForExit(100) -or (Get-Date) -gt $rorListenDeadline) {
            Get-Content -LiteralPath $rorCollectorLog -ErrorAction SilentlyContinue
            throw 'Profiler collector did not start'
        }
    }
    $rorLog=Join-Path $rorOutput 'runtime.log'
    $rorReport=Join-Path $rorOutput 'report.json'
    $rorArgs=@('--path',$rorProject,'--remote-debug','tcp://127.0.0.1:26071','--ignore-error-breaks','--audio-driver','Dummy','--log-file',$rorLog,'--','--profile-saved-match-frames',('--save='+$Save),('--output='+$rorReport),('--seconds='+$Seconds),'--size=2560x1080','--default-frame-limit','--move-human-group','--no-autosave','--no-probe')
    $rorGame=Start-Process -FilePath $rorGodot -ArgumentList ($rorArgs | ForEach-Object {'"'+$_+'"'}) -WindowStyle Hidden -PassThru
    $null=$rorGame.Handle
    Write-Output ('Gameplay PID='+$rorGame.Id)
    $rorDeadline=(Get-Date).AddSeconds($Seconds+650)
    while(-not $rorGame.WaitForExit(5000)) {
        if($rorCollector.HasExited) {Get-Content -LiteralPath $rorCollectorLog; throw 'Profiler collector exited before gameplay'}
        if((Get-Date) -gt $rorDeadline) {throw 'Own profiler diagnostic deadline exceeded'}
        if(Test-Path -LiteralPath $rorCollectorLog) {
            $rorErrors=Select-String -LiteralPath $rorCollectorLog -Pattern 'SCRIPT ERROR|^ERROR:'
            if($rorErrors) {throw ($rorErrors | Out-String)}
        }
    }
    if(-not $rorCollector.WaitForExit(10000)) {throw 'Profiler collector did not exit after gameplay'}
    Get-Content -LiteralPath $rorCollectorLog -Tail 8
    Get-Content -LiteralPath $rorLog -Tail 5
    Write-Output ('game_exit='+$rorGame.ExitCode+' collector_exit='+$rorCollector.ExitCode)
    if($rorGame.ExitCode -ne 0 -or $rorCollector.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $rorProfile) -or -not (Test-Path -LiteralPath $rorReport)) {throw 'Native script profiling did not complete'}
    $rorProfileResult=Get-Content -Raw -LiteralPath $rorProfile | ConvertFrom-Json
    if($rorProfileResult.error -or $rorProfileResult.runtime_error_count -ne 0) {throw 'Gameplay profiler captured an error; inspect script-functions.json'}
}
finally {
    if($rorGame -and -not $rorGame.HasExited) {Stop-Process -Id $rorGame.Id}
    if(-not $rorCollector.HasExited) {Stop-Process -Id $rorCollector.Id}
}
