[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$SavePath,
 [string]$Application='',
 [ValidateRange(5,7200)][int]$Seconds=120,
 [ValidatePattern('^\d+x\d+$')][string]$Size='1280x720',
 [string]$OutputRoot='',
 [switch]$Pan,
 [switch]$ProfileStages,
 [switch]$OwnerStages,
 [switch]$FineOwnerStages,
 [switch]$NoAutosave,
 [switch]$NoAI,
 [switch]$RequireProcessAutosave,
 [ValidateRange(0,240)][int]$FrameLimit=0,
 [switch]$DefaultFrameLimit,
 [switch]$VisualHold
)
$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Application)) {
    . (Join-Path $PSScriptRoot "ror-build-common.ps1")
    $Application = Join-Path (Get-RoRReleaseDirectory $repositoryRoot) "Rise of Rome Prototype.exe"
}
$application=[IO.Path]::GetFullPath($Application)
$save=(Resolve-Path -LiteralPath $SavePath).Path
if(-not (Test-Path -LiteralPath $application)){throw 'Build the Release first with tools/build-game.ps1'}
if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=Join-Path $repositoryRoot ('prototype/qa/saved-frames-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
$outputFolder=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $outputFolder){throw 'Frame-probe output directory already exists'}
New-Item -ItemType Directory -Path $outputFolder|Out-Null
$output=Join-Path $outputFolder 'report.json'
$artifactPaths=@($application,[IO.Path]::ChangeExtension($application,'.pck'),(Join-Path (Split-Path -Parent $application) 'bin\ror_pathfinding.windows.template_release.x86_64.dll'))
$artifactHashes=[ordered]@{}
foreach($artifact in $artifactPaths){$artifactHashes[$artifact]=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()}
$invocation=[ordered]@{application=$application;artifacts=$artifactHashes;save=$save;save_sha256=(Get-FileHash -LiteralPath $save -Algorithm SHA256).Hash.ToLowerInvariant();seconds=$Seconds;size=$Size;ai_enabled=(-not $NoAI);profile_stages=[bool]$ProfileStages;pan=[bool]$Pan;autosave=(-not $NoAutosave);default_frame_limit=[bool]$DefaultFrameLimit;frame_limit=$FrameLimit;started_utc=[DateTime]::UtcNow.ToString('o')}
$invocation|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $outputFolder 'invocation.json') -Encoding utf8
$arguments=@('--audio-driver','Dummy','--log-file',(Join-Path $outputFolder 'runtime.log'),'--','--profile-saved-match-frames',('--save='+$save),('--output='+$output),('--seconds='+$Seconds),('--size='+$Size))
if($DefaultFrameLimit){$arguments+='--default-frame-limit'}elseif($FrameLimit -eq 0){$arguments+='--uncapped'}else{$arguments+=('--frame-limit='+$FrameLimit)}
if(-not $ProfileStages){$arguments+='--no-probe'}
if($OwnerStages -or $FineOwnerStages){
    $invocation['owner_stages']=$true
    $invocation['owner_fine_stages']=[bool]($FineOwnerStages -or $ProfileStages)
    # Fine per-actor probes replace the normal native span with script calls.
    # Ordinary owner timing preserves the code path being measured.
    $arguments += $(if($FineOwnerStages -or $ProfileStages){'--owner-stages'}else{'--owner-system-stages'})
}
if($Pan){$arguments+='--pan'}
if($VisualHold){$arguments+='--visual-hold'}
if($NoAutosave){$arguments+='--no-autosave'}
if($NoAI){$arguments+='--no-ai'}
$quoted=$arguments|ForEach-Object{'"'+($_ -replace '"','\"')+'"'}
$process=Start-Process -FilePath $application -WorkingDirectory (Split-Path -Parent $application) -ArgumentList $quoted -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $outputFolder 'stdout.log') -RedirectStandardError (Join-Path $outputFolder 'stderr.log')
$handle=$process.Handle
$deadline=[DateTime]::UtcNow.AddSeconds($Seconds+300)
$memory=@()
$childCpuSeen=@{}
$invocation['game_pid']=$process.Id
$invocation['visual_hold']=[bool]$VisualHold
$invocation['wrapper_sha256']=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
$nextMemory=[DateTime]::UtcNow
while(-not $process.WaitForExit(1000)){
 if([DateTime]::UtcNow -gt $deadline){Stop-Process -Id $process.Id;throw 'Saved-match graphical probe timed out'}
 if([DateTime]::UtcNow -ge $nextMemory){
  $process.Refresh()
  $children=@()
  $childWorking=0L
  $childPrivate=0L
  foreach($child in @(Get-CimInstance Win32_Process -Filter ("ParentProcessId="+$process.Id))){
   if($child.ExecutablePath -ne $application){continue}
   $childCpu=([double]$child.UserModeTime+[double]$child.KernelModeTime)/10000000.0
   $childCpuSeen[[string]$child.ProcessId]=$childCpu
   $childWorking+=[long]$child.WorkingSetSize
   $childPrivate+=[long]$child.PrivatePageCount
   $children+=[pscustomobject]@{pid=$child.ProcessId;cpu_seconds=$childCpu;working_set_bytes=[long]$child.WorkingSetSize;private_bytes=[long]$child.PrivatePageCount}
  }
  $childCpuTotal=0.0
  foreach($used in $childCpuSeen.Values){$childCpuTotal+=[double]$used}
  $memory+=[pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');working_set_bytes=$process.WorkingSet64;private_bytes=$process.PrivateMemorySize64;main_cpu_seconds=$process.TotalProcessorTime.TotalSeconds;children=$children;total_working_set_bytes=($process.WorkingSet64+$childWorking);total_private_bytes=($process.PrivateMemorySize64+$childPrivate);total_cpu_seconds=($process.TotalProcessorTime.TotalSeconds+$childCpuTotal)}
  $memory|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $outputFolder 'memory.json') -Encoding utf8
  $nextMemory=[DateTime]::UtcNow.AddSeconds(5)
 }
}
$process.WaitForExit()
$errors=Select-String -LiteralPath (Join-Path $outputFolder 'stdout.log'),(Join-Path $outputFolder 'stderr.log'),(Join-Path $outputFolder 'runtime.log') -Pattern 'SCRIPT ERROR:|ERROR:'
if($process.ExitCode -ne 0 -or $errors -or -not (Test-Path -LiteralPath $output)){throw ('Saved-match probe failed: '+$outputFolder)}
$report=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json
if(-not $report.release -or $report.final_tick -le $report.initial_tick -or $report.steady_frame_us.count -le 0){throw 'Saved-match probe did not measure an advancing Release match'}
if($RequireProcessAutosave -and ($report.saved_tick -lt 0 -or -not $report.autosave_process_isolated)){throw 'No completed isolated autosave was measured'}
if($report.autosave_error){throw ('Autosave failed: '+$report.autosave_error)}
if(-not $ProfileStages -and -not $report.simulation_owner_started){throw 'Saved-match probe did not exercise the graphical simulation owner'}
if(-not $report.native_terrain_chunks -or -not $report.native_resource_bounds){throw 'Saved-match probe did not load the current terrain/resource kernels'}
if($DefaultFrameLimit -and (-not $report.default_frame_limit -or $report.frame_limit -le 0)){throw 'Saved-match probe did not retain the normal game frame limit'}
foreach($artifact in $artifactPaths){if((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant() -ne $artifactHashes[$artifact]){throw ('Release artifact changed during the measurement: '+$artifact)}}
$invocation['completed_utc']=[DateTime]::UtcNow.ToString('o')
$invocation['report_sha256']=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
$invocation|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $outputFolder 'invocation.json') -Encoding utf8
[pscustomobject]@{output=$output;steady_frame_us=$report.steady_frame_us;ticks=($report.final_tick-$report.initial_tick);saved_tick=$report.saved_tick}|ConvertTo-Json -Depth 4
