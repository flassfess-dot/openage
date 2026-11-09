param(
    [string]$GodotCppPath = "",
    [string]$BuildType = "Release",
    [switch]$Reconfigure
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "ror-build-common.ps1")
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot "native\ror_pathfinding"
$buildPath = Join-Path $projectRoot ".tools\ror-pathfinding-build"
$cmakePath = "D:\Develop\CMake\bin\cmake.exe"
$compilerPath = "D:\Develop\Qt\Tools\mingw730_64\bin\g++.exe"
$makePath = "D:\Develop\Qt\Tools\mingw730_64\bin\mingw32-make.exe"
$godotCppRevision = "507ed9d840c01a3c5b2a39af8bb4000bfac30bf5"

if ([string]::IsNullOrWhiteSpace($GodotCppPath)) {
    $GodotCppPath = Join-Path $projectRoot ".tools\godot-cpp"
}
if (-not (Test-Path -LiteralPath $GodotCppPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $GodotCppPath) | Out-Null
    & git clone --depth 1 --branch "10.0.0-stable" "https://github.com/godotengine/godot-cpp.git" $GodotCppPath
    if ($LASTEXITCODE -ne 0) {
        throw "godot-cpp 10.0.0-stable could not be acquired"
    }
}
$actualGodotCppRevision = (& git -C $GodotCppPath rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualGodotCppRevision -ne $godotCppRevision) {
    throw "godot-cpp must be pinned to $godotCppRevision (10.0.0-stable); found $actualGodotCppRevision"
}

$arguments = @(
    "-S", $sourcePath,
    "-B", $buildPath,
    "-G", "MinGW Makefiles",
    "-DCMAKE_CXX_COMPILER=$($compilerPath.Replace('\', '/'))",
    "-DCMAKE_MAKE_PROGRAM=$($makePath.Replace('\', '/'))",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DGODOT_CPP_PATH=$($GodotCppPath.Replace('\', '/'))"
)

# Configure on every invocation so changed build rules cannot leave stale outputs.
& $cmakePath @arguments
if ($LASTEXITCODE -ne 0) { throw "Native pathfinding configuration failed with exit code $LASTEXITCODE" }

# Backups can restore an older mtime together with changed header contents.
# A mixed set of C++ object layouts can link successfully and crash in Godot.
# Trust a content receipt, then invalidate this project's objects on any change.
# The much larger, pinned godot-cpp library keeps its incremental build cache.
$libraryName = "ror_pathfinding.windows.template_release.x86_64.dll"
$builtLibrary = Join-Path $buildPath "bin\$libraryName"
$inputFiles = @(Get-ChildItem -LiteralPath (Join-Path $sourcePath "src") -File | Where-Object { $_.Extension -in @(".cpp", ".hpp", ".inc") })
$inputFiles += @(Get-Item -LiteralPath (Join-Path $sourcePath "CMakeLists.txt"), (Join-Path $sourcePath "godot-cpp-profile.json"))
$inputHashes = [ordered]@{}
foreach ($inputFile in $inputFiles | Sort-Object FullName) {
    $relativeName = $inputFile.FullName.Substring($sourcePath.Length).TrimStart('\', '/')
    $inputHashes[$relativeName] = Get-ArtifactSha256 $inputFile.FullName
}
$inputState = [ordered]@{ build_type = $BuildType; godot_cpp = $actualGodotCppRevision; inputs = $inputHashes }
$inputSignature = $inputState | ConvertTo-Json -Depth 4 -Compress
$receiptPath = Join-Path $buildPath "native-project-content-receipt.json"
$previousReceipt = $null
if (Test-Path -LiteralPath $receiptPath) {
    try { $previousReceipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json } catch { $previousReceipt = $null }
}
$contentMatches = $previousReceipt -and $previousReceipt.signature -eq $inputSignature -and (Test-Path -LiteralPath $builtLibrary)
if ($contentMatches) { $contentMatches = $previousReceipt.library_sha256 -eq (Get-ArtifactSha256 $builtLibrary) }
if (-not $contentMatches) {
    $resolvedBuildRoot = [IO.Path]::GetFullPath($buildPath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $objectRoot = [IO.Path]::GetFullPath((Join-Path $buildPath "CMakeFiles\ror_pathfinding.dir"))
    if (-not $objectRoot.StartsWith($resolvedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Native object directory escaped the build root" }
    if (Test-Path -LiteralPath $objectRoot) {
        foreach ($objectFile in Get-ChildItem -LiteralPath $objectRoot -File -Recurse -Filter "*.obj") {
            if (-not $objectFile.FullName.StartsWith($objectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Native object escaped its target directory" }
            Remove-Item -LiteralPath $objectFile.FullName -Force
        }
    }
    Write-Host "Native project content changed; recompiling all module objects"
}

& $cmakePath --build $buildPath --config $BuildType --parallel 8
if ($LASTEXITCODE -ne 0) {
    throw "Native pathfinding build failed with exit code $LASTEXITCODE"
}

$targetLibrary = Join-Path $projectRoot "prototype\bin\$libraryName"
if (-not (Test-Path -LiteralPath $builtLibrary)) { throw "Native build output missing: $builtLibrary" }
foreach ($inputFile in $inputFiles) {
    $relativeName = $inputFile.FullName.Substring($sourcePath.Length).TrimStart('\', '/')
    if ((Get-ArtifactSha256 $inputFile.FullName) -ne $inputHashes[$relativeName]) { throw "Native source changed during the build: $relativeName" }
}
[ordered]@{ signature = $inputSignature; state = $inputState; library_sha256 = (Get-ArtifactSha256 $builtLibrary) } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
# Stage before replacing: a running preview may still map the previous DLL.
$previousLibrary = $null
$stagedLibrary = "$targetLibrary.new"
Copy-Item -LiteralPath $builtLibrary -Destination $stagedLibrary -Force
if (Test-Path -LiteralPath $targetLibrary) {
    $previousLibrary = "$targetLibrary.previous.$([Guid]::NewGuid().ToString('N'))"
    Move-Item -LiteralPath $targetLibrary -Destination $previousLibrary
}
try { Move-Item -LiteralPath $stagedLibrary -Destination $targetLibrary }
catch {
    if ($previousLibrary -and (Test-Path -LiteralPath $previousLibrary)) { Move-Item -LiteralPath $previousLibrary -Destination $targetLibrary }
    throw
}
if ($previousLibrary) { Remove-Item -LiteralPath $previousLibrary -Force -ErrorAction SilentlyContinue }
Write-Host "Built $targetLibrary"
