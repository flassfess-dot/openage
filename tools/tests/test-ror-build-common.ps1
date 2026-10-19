[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\ror-build-common.ps1")
$taskRepository = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$taskFixture = Join-Path $taskRepository ("prototype\qa\build-common-tests\" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $taskFixture | Out-Null
$taskChecks = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:taskChecks += 1
}

function Assert-Rejected([scriptblock]$Action, [string]$Reason) {
    $taskFailure = ""
    try { & $Action | Out-Null } catch { $taskFailure = $_.Exception.Message }
    Assert-True ($taskFailure.Contains($Reason)) ("Expected rejection: " + $Reason + "; got: " + $taskFailure)
}

$taskLog = Join-Path $taskFixture "engine.log"
Set-Content -LiteralPath $taskLog -Value "Godot import completed" -Encoding UTF8
Assert-RoRGodotStep -Name "fixture" -ExitCode 0 -LogPath $taskLog
Assert-Rejected { Assert-RoRGodotStep -Name "fixture" -ExitCode 7 -LogPath $taskLog } "exit code 7"
Assert-Rejected { Assert-RoRGodotStep -Name "fixture" -ExitCode $null -LogPath $taskLog } "did not expose an exit code"
foreach ($taskError in @("SCRIPT ERROR: invalid dependency", "Parse Error: bad script", "Failed to load script fixture.gd")) {
    Set-Content -LiteralPath $taskLog -Value $taskError -Encoding UTF8
    Assert-Rejected { Assert-RoRGodotStep -Name "fixture" -ExitCode 0 -LogPath $taskLog } "compilation errors"
}
Assert-Rejected { Assert-RoRGodotStep -Name "fixture" -ExitCode 0 -LogPath (Join-Path $taskFixture "missing.log") } "did not produce an engine log"

$taskGenerated = Join-Path $taskFixture "generated"
New-Item -ItemType Directory -Force -Path $taskGenerated | Out-Null
foreach ($taskInput in (Get-RoRGeneratedInputFiles)) {
    $taskInputPath = Join-Path $taskGenerated $taskInput
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $taskInputPath) | Out-Null
    Set-Content -LiteralPath $taskInputPath -Value "fixture"
}
Assert-RoRGeneratedInputs -GeneratedRoot $taskGenerated -RecoveryHint "Repack resources."
Assert-Rejected { Assert-RoRGeneratedInputs -GeneratedRoot $taskGenerated -IncludeInteractionAssets -RecoveryHint "Repack resources." } "ror_cursor_00.png"

$taskEditor = Join-Path $taskFixture "editor.exe"
$taskTemplate = Join-Path $taskFixture "windows_release_x86_64.exe"
Set-Content -LiteralPath $taskEditor -Value "editor"
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$taskArchive = Join-Path $taskFixture "Godot_v4.7.2-stable_export_templates.tpz"
$taskZip = [System.IO.Compression.ZipFile]::Open($taskArchive, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $taskEntry = $taskZip.CreateEntry("templates/windows_release_x86_64.exe")
    $taskWriter = [System.IO.StreamWriter]::new($taskEntry.Open())
    try { $taskWriter.Write("release") } finally { $taskWriter.Dispose() }
} finally { $taskZip.Dispose() }
Initialize-RoRReleaseTemplate -GodotApplication $taskEditor -ReleaseTemplate $taskTemplate
Assert-True ((Get-Content -LiteralPath $taskTemplate -Raw).Trim() -eq "release") "Release template is extracted from the archive"
Initialize-RoRReleaseTemplate -GodotApplication $taskEditor -ReleaseTemplate $taskTemplate
Assert-True ((Get-Content -LiteralPath $taskTemplate -Raw).Trim() -eq "release") "Existing Release template is retained"

$taskProject = Join-Path $taskFixture "prototype"
$taskDistribution = Join-Path $taskFixture "dist"
New-Item -ItemType Directory -Force -Path $taskProject, (Join-Path $taskFixture "legal\MIT") | Out-Null
Set-Content -LiteralPath (Join-Path $taskProject "README.md") -Value "fixture readme"
Set-Content -LiteralPath (Join-Path $taskFixture "legal\MIT\godot-cpp.md") -Value "fixture license"
$taskNative = Join-Path $taskFixture "native.dll"
Set-Content -LiteralPath $taskNative -Value "native"
Copy-RoRReleaseRuntime -RepositoryRoot $taskFixture -ProjectRoot $taskProject -DistributionRoot $taskDistribution -NativeLibrary $taskNative
$taskPackagedNative = Join-Path $taskDistribution "bin\ror_pathfinding.windows.template_release.x86_64.dll"
Assert-True ((Get-ArtifactSha256 $taskNative) -eq (Get-ArtifactSha256 $taskPackagedNative)) "Packaged DLL matches the build output"
Assert-True (Test-Path -LiteralPath (Join-Path $taskDistribution "legal\MIT\godot-cpp.md")) "Runtime license is retained"
$taskApplication = Join-Path $taskDistribution "game.exe"
$taskPackage = Join-Path $taskDistribution "game.pck"
Copy-Item -LiteralPath $taskTemplate -Destination $taskApplication
Set-Content -LiteralPath $taskPackage -Value "package"
$taskArtifacts = @(Get-RoRReleaseArtifacts -Application $taskApplication -Package $taskPackage -NativeLibrary $taskPackagedNative -GodotApplication $taskEditor)
Assert-True ($taskArtifacts.Count -eq 3) "Release artifacts are verified together"
Copy-Item -LiteralPath $taskEditor -Destination $taskApplication -Force
Assert-Rejected { Get-RoRReleaseArtifacts -Application $taskApplication -Package $taskPackage -NativeLibrary $taskPackagedNative -GodotApplication $taskEditor } "replaced by the Godot editor"
Assert-Rejected { Get-RoRReleaseArtifacts -Application $taskApplication -Package (Join-Path $taskDistribution "missing.pck") -NativeLibrary $taskPackagedNative -GodotApplication $taskEditor } "Build artifact is missing"
Write-Output ("Build common: {0} checks passed" -f $taskChecks)
