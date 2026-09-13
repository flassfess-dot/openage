# Rise of Rome prototype v0.3

This Windows prototype uses a one-time, read-only conversion of locally owned
Age of Empires: Rise of Rome resources. It never writes to the original game
folder and does not convert assets during normal launches.

This iteration reads `data2/empires.dat` during the one-time build step and
bakes its small gameplay subset into the PCK. Unit health, speed, range, damage,
costs, animation timing, graphic IDs, directions, mirroring, and sprite hotspots
now come from the real Rise of Rome data rather than prototype guesses.

It also uses the correct Stone Age Town Center, berry bush and oak graphics,
full idle/move/attack animations, original player colors, original voice
responses, terrain, interface stonework, and music.

Controls:

- left mouse: select units or drag a selection rectangle
- right mouse: move, attack an enemy, or gather a resource
- `Ctrl+1`-`Ctrl+9`: assign a control group
- `1`-`9`: recall a group; press again to center, use `Shift` to add it
- `F5`-`F9`: line, rectangle, column, wedge, and staggered formations
- `T`: train a clubman for 50 food
- `WASD` / arrows: move camera
- mouse wheel: zoom
- `M`: toggle music
- `Space`: pause/resume simulation
- `,` / `.`: slower/faster game speed (1.0x, 1.5x, 2.0x)
- `F3`: toggle diagnostics (IDs, footprints, grid, paths, slots, velocities, facing and render keys)
- `F10`: open the eight-direction animation calibration scene
- `R`: restart battle
- `Esc`: quit

Generated files in `assets/generated` and copied original music are for local
use only and must not be redistributed.

The Windows workflow is deliberately split into four operations:

    powershell -ExecutionPolicy Bypass -File tools/import-assets.ps1
    powershell -ExecutionPolicy Bypass -File tools/validate-cache.ps1
    powershell -ExecutionPolicy Bypass -File tools/build-game.ps1
    powershell -ExecutionPolicy Bypass -File tools/run-game.ps1

Only the first operation reads and converts the original installation. Normal
desktop launches execute `run-game.ps1`, which only starts the already built
EXE/PCK pair and never invokes Node.js, Python, an importer, or a build step.

Run the complete headless test suite with:

    .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path prototype --script res://tests/test_suite.gd
