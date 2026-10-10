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
- right mouse: move, attack an enemy, gather a resource, or board a friendly transport
- `U` / Unload button, then left click a coast: sail to the chosen landing point and unload; `Shift` queues the landing, right click or `Esc` cancels targeting
- a boarding selection may exceed transport capacity: everyone approaches, free seats fill, and the rest wait on shore
- `Ctrl+1`-`Ctrl+9`: assign a control group
- `1`-`9`: recall a group; press again to center, use `Shift` to add it
- `F5`-`F10`: line, protective box, column, wedge, staggered, and split flank formations
- `T`: train a clubman for 50 food
- `WASD` / arrows: move camera
- mouse wheel: zoom
- `M`: toggle music
- `Space`: pause/resume simulation
- `,` / `.`: slower/faster game speed (1.0x, 1.5x, 2.0x)
- `F3`: toggle diagnostics (IDs, footprints, grid, paths, slots, velocities, facing and render keys)
- `Ctrl+F10`: open the eight-direction animation calibration scene
- `B`: open construction choices for selected villagers
- `R`: choose a repair target for selected villagers; restart when no villager is selected or the battle has ended
- `Del`: delete selected own objects
- `Esc`: cancel targeting or return from construction; quit when no command or submenu is active

Each group remembers its own formation. Selecting another group only updates the
highlighted formation button; a mixed selection keeps each group's layout when
moving. Short moves preserve the current front, and right-button dragging sets
an explicit facing. Groups share the slowest member's march speed, narrow their
ranks through chokepoints, and keep surviving units' slots after casualties.
`Shift` + right click appends a waypoint for the group.

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

The compact in-game HUD now uses all five original civilization interface families.
The top strip uses Arial, a square population glyph from the locally owned AoE DE
UI, and a screen-centered age name without a match clock. The bottom panel keeps
its 126-pixel desktop height and shows the current production item, progress,
remaining time, an explicit cancel button, and grouped waiting orders. Shift-click
queues up to five affordable units; Shift-click a waiting unit group cancels up to
five. Research and unit orders share one paid FIFO queue, with refunds on explicit
cancellation. The small production overview selects the corresponding building.
Command buttons retain their 50-pixel size as buildings and technologies unlock.
The grid reserves up to ten columns and two rows independently of the current
selection. The production recess is left-aligned beside it and capped at 360 pixels.
It uses the native selection-window frame and appears only when a building is
selected, showing its unit production or research queue.
Smaller windows page commands instead of shrinking them; construction keeps Back
accessible on every page. Narrow windows reflow the HUD without stretching the
original minimap frame.

Terrain now prepares the next full-quality view on a worker before scrolling
exits the current mesh. Numeric terrain/height/variant samples are retained only
for the current window and invalidated by terrain revisions. Scenery queries
reuse unchanged render records, resolve only entering or changed objects, and
merge their depth order without rebuilding all decorations. Effects-only draws
preserve the scene cache. Regression tests cover cache bounds, camera projection,
terrain prefetch and exact geometry; the default map size and artwork are unchanged.
Worker and inspection behavior
------------------------------
The villager action layer has Build on the first plain-hammer button and Repair
on the second original icon, with
formations beside ordinary actions. Build replaces this layer with building icons;
the red cross returns to actions. Repair targets damaged own or allied buildings
and ships explicitly, including Transports without boarding them. The root red
cross deletes selected objects.
Workers can resume an existing owned foundation through the same context build
command without reserving its cost again. Farm placement uses its native 3x3
obstruction footprint rather than the larger selection outline. A manual cargo
deposit finishes the current order; automatic gathering trips resume harvesting.
Trees consume their original HP before a short fall, then yield wood from the
fallen trunk and leave a visible, passable stump after depletion. Only actively
falling trees are updated by the animation lifecycle, regardless of forest size.
Visible neutral and foreign objects can be inspected individually; their command
palettes and private production/research queues are never exposed.
Generated highlands now support seven elevation levels. Native RoR brown cliff
strips reserve connected footprints before resource and route placement.

Corpse and siege presentation
-----------------------------
Animals retain their facing when becoming food resources and use the original
corpse animation for both hunted and non-hunted deaths. Corpse frames advance
with simulation age, independently of entity ID and harvested food. The age and
facing survive saves; older carcasses without an age start at the fresh stage.
Pending corpse clips hold the final death frame during background loading.
Projectile impacts resolve the original projectile death graphic, including the
catapult/ballista explosion and its dust layer. Ordinary arrows have no explosion
in the source DAT. Heavy Catapult and Juggernaught blasts destroy trees according
to the original blast offence level, immediately releasing their navigation
footprints and updating the forest surface. Use Attack Ground to clear forest.

### Обновление ресурсов окружения и сборка

После изменений импортера деревьев выполните из корня репозитория:

```powershell
.\tools\ror-repack-resources.ps1
.\tools\ror-full-build.ps1
```

Первая команда заново импортирует ресурсы RoR и окружение AoE2, включая отдельные
исходные тени всех восьми вариантов дубов и сосен, проверяет кеш и обновляет импорт
Godot. При другом расположении AoE2 передайте `-AoE2GamePath "путь к игре"`.
Вторая собирает релиз в `dist/Rise of Rome Prototype`; перед ней закройте игру.
Эти команды выполняются последовательно, только после успешного завершения предыдущей.

`ror-full-build.ps1` и `build-game.ps1` по умолчанию выполняют сборку и экспорт
без запуска игры для проверки. Для проверки старта случайной карты и загрузки
нового сохранения передайте `-VerifyStartup` или запустите её отдельно:

```powershell
.\tools\ror-full-build.ps1 -VerifyStartup
# Либо проверка уже собранного пакета:
.\tools\verify-packaged-startup.ps1
```

Ошибка этой проверки сообщается отдельно от завершившегося экспорта.
Общий журнал полной сборки показывает этапы и изменения процента; полный вывод
Godot сохраняется в указанных в нём отдельных логах импорта и экспорта.

Серийное размещение зданий: **Shift + щелчок**, как в оригинальном руководстве
[Age of Empires](https://www.bestoldgames.net/download/games/age-of-empires/age-of-empires-win-manual.pdf).
Пальмы появляются в сухих прибрежных рощах новых случайных карт; ранее созданные
карты сохраняют состав деревьев из сохранения.
