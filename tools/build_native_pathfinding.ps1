param(
    [string]$GodotCppPath = "",
    [string]$BuildType = "Release",
    [switch]$Reconfigure
)

$ErrorActionPreference = "Stop"
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

if ($Reconfigure -or -not (Test-Path -LiteralPath (Join-Path $buildPath "CMakeCache.txt"))) {
    & $cmakePath @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Native pathfinding configuration failed with exit code $LASTEXITCODE"
    }
}
& $cmakePath --build $buildPath --config $BuildType --parallel 8
if ($LASTEXITCODE -ne 0) {
    throw "Native pathfinding build failed with exit code $LASTEXITCODE"
}

Write-Host "Built prototype/bin/ror_pathfinding.windows.template_release.x86_64.dll"
