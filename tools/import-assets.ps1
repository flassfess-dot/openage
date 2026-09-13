[CmdletBinding()]
param(
    [string]$GamePath = "D:\Games\Age of Empires 1 - Rise of Rome",
    [string]$GameVersion = "1.1",
    [int]$Civilization = 13
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$gameRoot = (Resolve-Path -LiteralPath $GamePath).Path
$importerRoot = Join-Path $repositoryRoot "tools\ror_import"
$generatedRoot = Join-Path $repositoryRoot "prototype\assets\generated"
$audioRoot = Join-Path $repositoryRoot "prototype\assets\audio"

function Invoke-ExternalStep {
    param(
        [string]$Name,
        [string]$Executable,
        [string[]]$Arguments
    )
    Write-Host "[$Name]"
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $gameRoot "data2\empires.dat"))) {
    throw "Rise of Rome data2\empires.dat was not found under $gameRoot"
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js is required for SLP/WAV extraction."
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "Python launcher is required for catalog extraction."
}

New-Item -ItemType Directory -Force -Path $generatedRoot, $audioRoot | Out-Null

Invoke-ExternalStep "prototype assets" "node" @(
    (Join-Path $importerRoot "import_assets.js"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--selection", (Join-Path $importerRoot "prototype-selection.json"),
    "--interface-inventory", (Join-Path $generatedRoot "interface-source-inventory.json"),
    "--output", $generatedRoot
)
Invoke-ExternalStep "interface reference" "node" @(
    (Join-Path $importerRoot "import_assets.js"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--selection", (Join-Path $importerRoot "interface-selection.json"),
    "--output", (Join-Path $generatedRoot "interface")
)
Invoke-ExternalStep "palette reference" "node" @(
    (Join-Path $importerRoot "import_assets.js"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--selection", (Join-Path $importerRoot "palette-probe-selection.json"),
    "--output", (Join-Path $generatedRoot "palette-probe")
)

$python = "py"
Invoke-ExternalStep "prototype game specification" $python @(
    "-3", (Join-Path $importerRoot "extract_gamespec.py"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--civ", [string]$Civilization,
    "--output", (Join-Path $generatedRoot "gamespec-prototype.json")
)
Invoke-ExternalStep "graphics catalog" $python @(
    "-3", (Join-Path $importerRoot "extract_graphics_catalog.py"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--output", (Join-Path $generatedRoot "graphics-catalog.json")
)
Invoke-ExternalStep "object catalog" $python @(
    "-3", (Join-Path $importerRoot "extract_object_catalog.py"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--output", (Join-Path $generatedRoot "objects-catalog.json")
)
Invoke-ExternalStep "terrain catalog" $python @(
    "-3", (Join-Path $importerRoot "extract_terrain_catalog.py"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--output", (Join-Path $generatedRoot "terrain-catalog.json")
)
Invoke-ExternalStep "localization catalog" $python @(
    "-3", (Join-Path $importerRoot "extract_localization.py"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--objects", (Join-Path $generatedRoot "objects-catalog.json"),
    "--output", (Join-Path $generatedRoot "localization-catalog.json")
)
Invoke-ExternalStep "sound catalog" $python @(
    "-3", (Join-Path $importerRoot "extract_sound_catalog.py"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--objects", (Join-Path $generatedRoot "objects-catalog.json"),
    "--graphics", (Join-Path $generatedRoot "graphics-catalog.json"),
    "--output", (Join-Path $generatedRoot "sound-catalog.json")
)
Invoke-ExternalStep "scenario and campaign catalog" $python @(
    "-3", (Join-Path $importerRoot "extract_scenario_catalog.py"),
    "--game", $gameRoot,
    "--game-version", $GameVersion,
    "--output", (Join-Path $generatedRoot "scenario-catalog.json")
)
Invoke-ExternalStep "Birth of Rome campaign match" "powershell" @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $importerRoot "convert_birth_of_rome.ps1"),
    "-GamePath", $gameRoot,
    "-ScenarioCatalog", (Join-Path $generatedRoot "scenario-catalog.json"),
    "-ObjectCatalog", (Join-Path $generatedRoot "objects-catalog.json"),
    "-Output", (Join-Path $generatedRoot "matches\birth-of-rome.json")
)
Invoke-ExternalStep "normalized runtime catalog" $python @(
    "-3", (Join-Path $importerRoot "build_runtime_catalog.py"),
    "--manifest", (Join-Path $importerRoot "runtime-archetypes.json"),
    "--objects", (Join-Path $generatedRoot "objects-catalog.json"),
    "--graphics", (Join-Path $generatedRoot "graphics-catalog.json"),
    "--sounds", (Join-Path $generatedRoot "sound-catalog.json"),
    "--localization", (Join-Path $generatedRoot "localization-catalog.json"),
    "--output", (Join-Path $generatedRoot "runtime-catalog.json")
)

$musicSource = Join-Path $gameRoot "sound\xmusic1.mp3"
if (Test-Path -LiteralPath $musicSource) {
    Copy-Item -LiteralPath $musicSource -Destination (Join-Path $audioRoot "xmusic1.mp3") -Force
}

Write-Host "Import complete. Generated data is ready for validation and building."
