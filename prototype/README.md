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

Single-player matches keep one **Автосохранение** recovery slot. The first save
is scheduled after 15 seconds of active play, then every 60 seconds. Menus,
loading screens, and pauses do not advance its timer. The slot appears in both
load menus and is replaced atomically only after a background write succeeds.
It preserves the full match, player controls, AI state, fog memory and TimeLine.
Large checkpoint capture/compression runs on an isolated worker simulation;
the foreground transfers only new commands and small player/AI state.

Controls:

- left mouse: select units or drag a selection rectangle
- right mouse: move, attack an enemy, gather a resource, or board a friendly transport
- `U` / Unload button, then left click a coast: sail to the chosen landing point and unload; `Shift` queues the landing, right click or `Esc` cancels targeting
- a boarding selection may exceed transport capacity: everyone approaches, free seats fill, and the rest wait on shore
- `Ctrl+1`-`Ctrl+9`: assign a control group
- `1`-`9`: recall a group; press again to center, use `Shift` to add it
- `F5`-`F9`: line, protective box, column, wedge, and staggered formations; `Shift+F9`: split flank
- `F10`: open/close the match menu; `F1`: in-game help
- `Alt+Enter`: toggle borderless fullscreen and restore the previous window
- `T`: train a clubman for 50 food
- `WASD` / arrows: move camera
- mouse at the game window's outer edge: scroll camera, including over the HUD
- mouse wheel: zoom
- `M`: toggle music
- `Space`: pause/resume simulation
- `,` / `.`: slower/faster game speed (1.0x, 1.5x, 2.0x)
- `F3`: toggle diagnostics (IDs, footprints, grid, paths, slots, velocities, facing and render keys)
- `Ctrl+F10`: open the eight-direction animation calibration scene
- `B`: open construction choices for selected villagers; Gates unlock with Small Wall research
- `Tab` during gate placement: turn the 4x1 footprint; select a finished gate for Auto / Open / Locked modes
- gates follow Small / Medium / Fortified Wall research and retain their mode, orientation and health ratio; see `docs/gates.md`
- `R`: choose a repair target for selected villagers
- `Del`: delete selected own objects
- `Esc`: cancel targeting or return from construction, then open the match menu; inside it, go back or resume

The match menu has separate save/load dialogs, audio/camera/window/game-speed
settings, achievements, population/age TimeLine, scenario instructions and help.
Loading, overwriting, restarting, resigning and leaving require confirmation.
TimeLine is recorded during play and retained in checkpoints. Old current-format
saves remain loadable, with history explicitly starting at restoration.
TimeLine and statistics include every participant during the match. Match menus,
diplomacy, scenario briefing and results fill the window with Roman illustrations
and the main menu's marble and bronze styling. The main menu and HUD artwork
remain unchanged.
See `doc/ror-modern/MATCH_MENU_CONTRACT.md` for evidence and validation.

Each group remembers its own formation. Selecting another group only updates the
highlighted formation button; a mixed selection keeps each group's layout when
moving. Short moves preserve the current front, and right-button dragging sets
an explicit facing. Groups share the slowest member's march speed, narrow their
ranks through chokepoints, and keep surviving units' slots after casualties.
`Shift` + right click appends a waypoint for the group.

Mobile sprite picking uses the entire asset rectangle, including transparent
gaps between animated limbs, with the rendered pivot, scale and reflection.
Destroyed farms use their source dead-object artwork; settled building rubble
draws beneath mobile units. Gate hinges attach to the masonry independently of
the texture crop. Living mobile bodies retain swept collision, and a local
post-movement pass separates existing overlaps, including idle units restored
inside narrow forest corners. It visits changed actors and unsettled contacts
after its first scan, preserving the isolated formation translation path.
`tests/manual/verify_reported_mobile_overlap.gd` loads an autosave with autosaving
disabled and checks control group 1 without issuing new orders; `--save=` and
`--output=` select the source and report directory.

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

The desktop renderer uses Vulkan Mobile with Mailbox presentation, applied after
native window creation to avoid a startup presentation stall. Unsupported
rendering devices retain Godot's automatic fallback to OpenGL compatibility.
Rendering keeps the original resolution, nearest-neighbor artwork and fixed
simulation cadence. Camera projection, static building compositions and entity
change deltas reuse bounded data; match replacement clears the derived caches.

Terrain now prepares the next full-quality view on a worker before scrolling
exits the current mesh. Numeric terrain/height/variant samples are retained only
for the current window and invalidated by terrain revisions. Scenery queries
reuse unchanged render records, resolve only entering or changed objects, and
merge their depth order without rebuilding all decorations. Effects-only draws
preserve the scene cache. Regression tests cover cache bounds, camera projection,
terrain prefetch and exact geometry; the default map size and artwork are unchanged.
Camera resource publications retain one immutable, ID-sorted array per observer.
Legal observation changes update only its changed records; hidden live changes
never invalidate fog memory. Moving the camera replaces this bounded view, and
save restoration clears it with the observer memory. Selected resources still
receive detached control records. The renderer reuses unchanged publications,
animates only its animated resource records and groups/sorts fish separately
from the forest. Plain static resource sprites retain their texture rectangles
until their frame or camera projection changes; rotated/mirrored sprites use the
existing draw path. Static resources, scenery and building sprites wholly outside
the viewport are omitted using full sprite bounds; camera movement refreshes the
queue between simulation ticks so crowns entering the window remain visible.
Camera queries snap outward to eight-tile windows, always preserving the full
sprite margin while avoiding a new forest query for each camera pixel.
Camera pan/zoom reprojects retained static anchors without repeating terrain
height queries or projecting fish bodies twice. RenderWorld.affine_static_projection
can disable this path for reference comparisons. Whole-view reuse requires
immutable resource records as well as an immutable outer array.
Native depth-list merging preserves the reference comparator
and automatically falls back to GDScript if that method is unavailable.
Building-item construction and clipping also use an equivalent native pass;
set `RenderWorld.native_buildings_enabled = false` for a reference comparison.
All sprite/texture operations remain on the main thread. Texture geometry
templates retain at most 4096 entries and 96 MiB of accounted image storage.

The owner-thread movement integration pass updates coordinates, terrain height,
velocity and facing together, publishing the same union of changed entity groups.
Its GDScript reference remains available through
`movement_system.native_integration_enabled = false`. Route decisions, collision
avoidance, arrivals and stuck recovery retain their existing order. Gate planning
revisions cache alliance queries until player relations or gate policy change;
checkpoint dictionary replacement invalidates the derived policy version.
Visibility footprint generation uses one bounded cell buffer and adds only the
new footprint fringe to personal exploration, preserving the original ordered
visibility and exploration journals.

AI actor enrichment uses a native profile builder for complete owned runtime
records; foreign estimates and incomplete compatibility records retain the
catalog-based reference path. `AiObservationProfile.native_actor_enabled = false`
selects that reference. The AI preparation owner can freeze its newly created
row/profile containers through `IsolatedTaskData.freeze_owned`, relinquishing
their mutability. Borrowed readonly parents do not transfer ownership of mutable
descendants, and packed buffers still detach. Ordinary `capture_frozen` continues
to copy mutable sources without freezing them. Native capture writes back only
changed/detached children after a shallow copy, preserving all scalar values.
Healthy completed farms retain their static crop/hut composition and depth
offsets; damage, construction, depletion and animated layers keep live resolution.
Immutable observation graphs are recursively validated before reuse. Mutable
descendants and packed buffers detach even inside a readonly parent.

Saved-match frame measurements use the actual exported Release, natural frame
intervals and the saved game speed. The default uncapped run disables detailed
stage instrumentation; add `-ProfileStages` when diagnosing CPU stages:

    powershell -ExecutionPolicy Bypass -File tools/run-saved-match-frames.ps1 -SavePath "path/to/save.json" -Seconds 180 -Size 2560x1080 -Pan

The probe redirects autosaves into its new report directory. It keeps the source
save and the player's recovery slot unchanged, and records steady frame intervals,
simulation progress, process memory and a real screenshot. Source-generation
build options are shared between AI capture portions; pure construction demand
runs on the planner worker. Native visibility deltas and selected-object control
projections keep their GDScript reference paths for parity checks.
The report also distinguishes rendered frame intervals from stalled simulation
ticks. Planner executors retain bounded, page-versioned terrain audits; resource
queries, infrastructure scoring and walkability masks have exact native paths.
Each private planner also retains its current immutable reachability indexes
(262144 cells total) and resource buckets (262144 records). Amount-only updates
replace bucket row references; geometry, domain, type or order changes rebuild
the index. Mutable records never qualify for identity reuse. Catalog field reads
detach only the requested value, and static building frames can lend an immutable
descriptor to the renderer while ordinary catalog callers keep editable copies.
Build-site profiles retain at most 256 entries / 2 MiB per observer and invalidate
on repository reconfiguration. Actor roots are certified only after recursive
validation. Private AI production rules have the same entry/payload limits and a
64 KiB dependency-schema cap; technology, civilization, army and request changes
invalidate them, while stock changes reprice immutable options. Completed source
reads publish in the same frame instead of holding another frame at the source.
Production templates live only for one pinned source generation.

Graphical single-player matches use one persistent simulation owner thread with
one outstanding frame request. The main thread relinquishes all live world,
controller and AI access until that request completes. It renders detached
presentation records, a separate terrain/height view and prepared fog/minimap
data while the owner advances the authoritative world. Terrain changes update
that view through bounded journals; a load replaces it completely. Scene input,
commands, save/load, menus and shutdown join the owner before live access. No GPU
or scene operations run on the simulation thread, and the world is never cloned
for each render frame. Interpolation continues from published positions while
the next job runs. AI capture budgets use the dispatch frame ID.
The owner has a 64 ms capture budget and 32 ms advance budget so pinned AI facts
finish promptly and overdue ticks catch up at a 60 FPS display cadence. These
overrides are restored before ownership returns; the sequential defaults remain
7 ms for capture and 16 ms for advancing the controller. A completed AI barrier
does not yield to a presentation deadline on the owner, since drawing proceeds
independently on the main thread.

Network matches, building placement previews, diagnostics, detailed stage
profiling and headless fixtures use the sequential path. Pass
`-- --no-simulation-owner` to compare that path in a graphical run. Frame probes
read latched simulation metadata and join before changing controller state.
Normal windows cap rendering at 60 FPS when no explicit engine cap is set.
`run-saved-match-frames.ps1 -DefaultFrameLimit` measures that production cadence
without replacing it; the default uncapped benchmark still exposes throughput.
Full-detail terrain is split into indexed parts of at most 16384 vertices on the
CPU worker. The main thread uploads at most two parts / 2 ms per frame, retaining
the complete old mesh until the replacement is ready. Old mesh resources retire
at most four per frame. Camera generations, surface revisions and world replacement
discard stale staged work. Triangle order and all vertex/UV/colour values match
the original full-detail mesh. Camera resource queries use only last-seen memory
and its spatial buckets; `native_render_resource_queries_enabled = false` retains
the GDScript reference query for parity checks.
`test_simulation_owner.gd`, `test_render_terrain_view.gd` and
`test_simulation_owner_scene.gd` cover canonical state parity, isolation,
single-request bounds, commands, pending-job save/load and shutdown.

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
