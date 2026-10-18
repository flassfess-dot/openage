[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$SavePath,
 [ValidateRange(5,7200)][int]$Seconds=120,
 [ValidatePattern('^\d+x\d+$')][string]$Size='1280x720',
 [string]$OutputRoot='',
 [switch]$Pan,
 [switch]$ProfileStages,
 [switch]$NoAutosave,
 [ValidateRange(0,240)][int]$FrameLimit=0,
 [switch]$DefaultFrameLimit
)
$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path -Parent $PSScriptRoot
$application=Join-Path $repositoryRoot 'dist\Rise of Rome Prototype\Rise of Rome Prototype.exe'
$save=(Resolve-Path -LiteralPath $SavePath).Path
if(-not (Test-Path -LiteralPath $application)){throw 'Build the Release first with tools/build-game.ps1'}
if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=Join-Path $repositoryRoot ('prototype/qa/saved-frames-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))}
$outputFolder=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $outputFolder){throw 'Frame-probe output directory already exists'}
New-Item -ItemType Directory -Path $outputFolder|Out-Null
$output=Join-Path $outputFolder 'report.json'
$arguments=@('--audio-driver','Dummy','--log-file',(Join-Path $outputFolder 'runtime.log'),'--','--profile-saved-match-frames',('--save='+$save),('--output='+$output),('--seconds='+$Seconds),('--size='+$Size))
if($DefaultFrameLimit){$arguments+='--default-frame-limit'}elseif($FrameLimit -eq 0){$arguments+='--uncapped'}else{$arguments+=('--frame-limit='+$FrameLimit)}
if(-not $ProfileStages){$arguments+='--no-probe'}
if($Pan){$arguments+='--pan'}
if($NoAutosave){$arguments+='--no-autosave'}
$quoted=$arguments|ForEach-Object{'"'+($_ -replace '"','\"')+'"'}
$process=Start-Process -FilePath $application -WorkingDirectory (Split-Path -Parent $application) -ArgumentList $quoted -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $outputFolder 'stdout.log') -RedirectStandardError (Join-Path $outputFolder 'stderr.log')
$handle=$process.Handle
$deadline=[DateTime]::UtcNow.AddSeconds($Seconds+300)
$memory=@()
$nextMemory=[DateTime]::UtcNow
while(-not $process.WaitForExit(1000)){
 if([DateTime]::UtcNow -gt $deadline){Stop-Process -Id $process.Id;throw 'Saved-match graphical probe timed out'}
 if([DateTime]::UtcNow -ge $nextMemory){
  $process.Refresh()
  $memory+=[pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');working_set_bytes=$process.WorkingSet64;private_bytes=$process.PrivateMemorySize64}
  $memory|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $outputFolder 'memory.json') -Encoding utf8
  $nextMemory=[DateTime]::UtcNow.AddSeconds(5)
 }
}
$process.WaitForExit()
$errors=Select-String -LiteralPath (Join-Path $outputFolder 'stdout.log'),(Join-Path $outputFolder 'stderr.log'),(Join-Path $outputFolder 'runtime.log') -Pattern 'SCRIPT ERROR:|ERROR:'
if($process.ExitCode -ne 0 -or $errors -or -not (Test-Path -LiteralPath $output)){throw ('Saved-match probe failed: '+$outputFolder)}
$report=Get-Content -LiteralPath $output -Raw|ConvertFrom-Json
if(-not $report.release -or $report.final_tick -le $report.initial_tick -or $report.steady_frame_us.count -le 0){throw 'Saved-match probe did not measure an advancing Release match'}
if($report.autosave_error){throw ('Autosave failed: '+$report.autosave_error)}
if(-not $ProfileStages -and -not $report.simulation_owner_started){throw 'Saved-match probe did not exercise the graphical simulation owner'}
if(-not $report.native_terrain_chunks -or -not $report.native_resource_bounds){throw 'Saved-match probe did not load the current terrain/resource kernels'}
if($DefaultFrameLimit -and (-not $report.default_frame_limit -or $report.frame_limit -le 0)){throw 'Saved-match probe did not retain the normal game frame limit'}
[pscustomobject]@{output=$output;steady_frame_us=$report.steady_frame_us;ticks=($report.final_tick-$report.initial_tick);saved_tick=$report.saved_tick}|ConvertTo-Json -Depth 4
