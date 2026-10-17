# AI and autosave frame pacing — 2026-10-17

Scenario: the existing `11212` Mediterranean save, 400×400 map, starting tick
64185. The original named file is read-only throughout verification. Hardware:
Core i7-7700 (4 cores / 8 threads), 16 GB RAM, RTX 3080 Ti; Godot 4.7.2.

## Changes

- Navigation loading prepares initial AI build-search topology. A bounded
  per-page revision map survives short cell-journal expiry. Native publication
  updates only dirty 16×16 pages; typed immutable leaves protect retained inputs.
- Spatial-only AI enrichment retains previously frozen actor arrays. The owner
  renews certificates for its validated immutable publications immediately before
  capture. Native detachment freezes the dispatch envelope once; sealing an
  already certified root does not recursively traverse it again.
- Minimap exploration fog is rasterized natively, with byte-for-byte reference
  parity, including transparent pixels, fractional geometry and unknown cells.
- Corridor widths and exact swept-footprint checks use the existing native
  walkability mask. Domain, terrain restrictions, radius, corner/tangent rules,
  ordering and fallback behavior are preserved. Rendered catch-up work yields
  after a 16 ms budget at every selected speed while retaining
  whole fixed ticks and bounded time debt.
- Native direct traces and nearest-cell ring searches preserve reference tie
  ordering. AI recovery candidates and movement segment validation use the same
  native geometry, rather than repeating the GDScript footprint scans.
- Connectivity changes are partitioned into bounded local clusters. Opening
  cells can merge existing components without another full flood. Closing a
  component's identifying root invalidates its labels, preventing false joins
  if that root is later reopened as an isolated cell. Complex changes retain
  the full-rebuild fallback, and retained worker contexts remain isolated.
- Full component floods use four cardinal edges. A legal diagonal already has
  a cardinal two-edge connection, so partitions and row-major IDs are unchanged.
  A* and direct traces reuse the proven centred-footprint passability labels;
  installed labels are checked against the mask before reuse. One raw A* result
  (at most 128 KiB) is retained per kernel for immediate corridor smoothing,
  keyed by start, goal, exact radius and walkability generation.
- AI capture separates actor portions, navigation, resources, command options,
  spatial queries, build-site capture and final publication. Build-site bases
  are detached/frozen natively once and shared among requests.
- Producer combat estimates, research relevance and owned-unit counts share
  one bounded cache per pinned observer generation. No cache is carried into
  the next decision. Navigation can yield between cells, bucket publication
  and regions, avoiding a combined last-portion overrun.
- Autosave recovery yields between fixed steps in addition to its low OS
  thread priority, and also yields while preparing initial navigation. Its
  checkpoint constructor skips throwaway default terrain/vertex maps. Loading
  retains durable fog/resource memory, skips unused AI build-site prewarming,
  and releases the AI navigation views after initializing observation memory.
  The recovery world remains isolated from the
  gameplay worker pool, with one task in flight and no accumulating queue.
  Its cooperative yield is 8 ms after a 2 ms work slice (whole ticks remain
  indivisible). Short preparation waits can recover wall time up to 0.5 s,
  with the existing 0.35 s simulation-debt cap and four-tick frame cap.
- Construction audio variants and gate leaf textures are made resident behind
  loading. Audio reuse is bounded by 128 streams and 32 MiB of sample data;
  warming does not consume selection seeds or category cooldowns. Small gates
  no longer load the medium-wall graphic for a height calculation discarded
  by their fixed-height rule. AI production option catalogs are also warmed
  during navigation loading.

## Evidence and limits

The original rendered Release autosave report recorded a 216.90 ms maximum
frame and three frames above 100 ms during its background job. The source A/B
probe located a 185.90/235.99 ms whole-map publication on the same simulation
tick with autosave disabled/enabled. A longer source run also exposed formation
commands taking 87–120 ms: corridor work 57–64 ms and member-route publication
27–46 ms. These are distinct costs, not additive nested metrics.

After the first geometry change, source corridor/member-route costs were about
1.50/5.00 ms in one observed command; later commands remained more expensive.
A controlled 30-second source run
completed an autosave at tick 64272, retained a 1.003 simulation/wall-time ratio,
and measured a 16.70 ms median, 46.48 ms p95 and 81.49 ms maximum frame, with no
frames above 100 ms. Foreground autosave preparation was 3.54 ms. This is an
editor-runtime result and does not certify the packaged Release.

Longer source trials exposed remaining outliers (including formation commands
and initial event/render work); they were retained in the reports and prompted
the later native direct/nearest, connectivity and capture-staging changes.
The latest 60-second source trial before the recovery-memory/geometry follow-up
still failed the strict smoothness gate: p95 52.27 ms, maximum 112.70 ms,
two frames above 100 ms, and AI capture maximum 30.67 ms. It is not a successful
final Release result. The subsequent recovery change passed complete checkpoint
equality on the original 400x400 save (tick 64222, foreground 3.14 ms).

Early graphical probes allowed ordinary physical mouse/keyboard input; a
window-edge hover could move the camera and invalidate a claimed fixed-camera
comparison. The final harness sets the temporary scroll multiplier to zero,
disables unhandled input, and records starting/ending camera offsets. Its
optional sinusoidal pan is explicit. Actual simulation and rendering continue.

Regression checks cover journal expiry, retained snapshots, skipped publications,
bulk resets, map edges, native/reference geometry, land/water/unknown terrain,
formation routes, minimap pixels, AI command/state equality, pending-plan save
continuation, and preparation-wait time debt. Logs and full frame/stage reports
are under `prototype/qa/ai-smoothness-20261017/` (excluded from export).
The source verification set contains 39 regression logs with no script/parse
errors; the movement/recovery and checkpoint tests were repeated after their
respective follow-up changes. The large autosave equality diagnostic writes
only to the QA directory, never to the user's named save.
The pending-plan fixture was also repaired to await initial/restored navigation
while paused; its isolated rerun passed after one concurrent-run timeout.

Release validation uses the actual EXE/PCK/native libraries: complete checkpoint
equality and load/lifecycle probes, then 120 seconds with repeated autosaving and
60 seconds at speed ×2 with controlled camera movement. The Release manifest
records frozen source hashes, artifact hashes and the unchanged original save.
Results are pending until those packaged-runtime checks finish.

The intermediate rendered Release (PCK 23:19 on October 17) passed complete
checkpoint/load checks and two autosaves, but failed smoothness: p95 43.02 ms,
maximum 127.14 ms, three frames above 100 ms. The x2 run retained only 65% of
the selected simulation speed. These failures prompted the later route reuse,
capture cache and resource warming; they are not final acceptance results.

The latest source normal-speed run before audio/gate warming retained a 0.999
speed ratio, completed an autosave, and measured p50 16.68 ms, p95 39.28 ms,
maximum 154.12 ms. Its one >100 ms frame at tick 64708 consisted largely of
first construction-audio loading (66.10 ms) and gate preparation in the depth
index (50.50 ms). The follow-up warming targets those measured costs.

Source x2 experiments remain unsuccessful and are preserved. Increasing
catch-up batches worsened frame times without improving throughput, so that
adaptive batch experiment was removed. A matched source A/B with detailed
stage profiling enabled/disabled gave speed ratios 0.579/0.583 and mean frames
24.06/24.09 ms: profiler overhead does not explain that throughput limitation.
The optional frame-only harness reports AI capture as unmeasured (null), never
as a measured zero; final stage-profiled acceptance still retains its criteria.

The R2 packaged normal-speed run completed two autosaves at ticks 64272/65472
and retained the exact selected speed. Across 6552 frames it measured p50
16.67 ms, p95 33.38 ms and maximum 74.26 ms; no frame exceeded 100 ms. During
autosaving p95 was 34.58 ms versus 32.16 ms idle. Its old internal 16 ms capture
target was exceeded (maximum 19.18 ms). x2 had no >100 ms frame but retained
only 74% of selected speed, so it did not pass acceptance.

The R3 experiment raised preparation to 16 ms and the accelerated simulation
frame budget to 24 ms. Its actual packaged normal-speed run regressed to p95
62.60 ms, maximum 132.54 ms and six frames above 100 ms. The x2 run retained
79.1% of selected speed with p95 59.24 ms. Both save/load checks passed, but
these performance results were rejected; the larger budgets were reverted.
R3 reports are retained with their failed acceptance results.

R4 restores the 7 ms preparation and 16 ms simulation budgets at every speed.
An exhausted frame may yield only after an explicitly repeatable intermediate
queue poll (`can_defer`), before consuming commands or advancing the fixed tick.
The apply-tick callback commits AI state and commands exactly once and cannot
be deferred/repeated by this guard. The same deferred boundary proceeds on its
next attempt to prevent starvation. Derived scheduling state is cleared on
world/replay/timing replacement, never serialized. Checkpoint continuation and
an exactly-once committing callback are covered by the frame-budget test.
Replay/recovery fixed steps do not have a rendered-frame deadline. Native heap
ties compare the existing row-major indices directly, preserving y/x order
without integer division at each comparison.

The stage diagnostic ceiling remains explicitly recorded as 32 ms, including
an indivisible operation exceeding the cooperative budget. This is not a
whole-frame guarantee. Observable acceptance remains p95 <40 ms, no frame
>100 ms, at least 90% of selected simulation speed and completed autosaves.
R2 reports retain their original 16 ms stage target.

## R4 packaged result — 2026-10-18 01:14

The full Release build and packaged random-map/save-load startup checks passed.
Both small and original 400x400 autosave/load lifecycle probes passed complete
checkpoint equality with a private recovery worker pool. The original save's
SHA-256 remained unchanged. The large probe's foreground capture was 3.31 ms;
the worker completed its job in 8.42 s.

The 120-second rendered x1 run passed its acceptance checks: 6468 measured
frames, p50 16.67 ms, p95 34.20 ms, maximum 95.97 ms, zero frames above 100 ms
and selected-speed ratio 0.9996. Two autosaves completed at ticks 64272/65472;
foreground preparation was 3.57 ms. Autosave/idle mean frames were 18.409/18.395
ms, with p95 34.83/33.55 ms. AI capture maximum was 23.62 ms. These measurements
show improvement on the measured scenario; they do not guarantee 60 FPS on
every map, speed, camera position or machine.

The 60-second rendered x2 controlled-pan run did not pass: p50 27.51 ms,
p95 46.70 ms, maximum 124.49 ms, one frame above 100 ms and only 75.3% of
selected speed. It completed an autosave with 3.16 ms foreground preparation
and no script/runtime error. The main process/draw work consumed about
56.8 CPU-seconds in this 60-second interval; fixed simulation and AI capture
remain throughput limits on this four-core system. The overall Release
performance manifest therefore remains failed, while normal_verified is true.
Do not describe accelerated large-map play as fully fixed.

The additional 60-second x1.5 controlled-pan run completed an autosave, retained
93.3% of selected speed, and had no frame above 100 ms (maximum 91.08 ms).
Its p50/p95 were 26.87/47.23 ms, so it failed the frame-time criterion despite
passing functional progress. Foreground autosave preparation was 4.72 ms and
AI capture maximum 17.55 ms. The manifest records speed15_verified=false.

Final startup also passed with the executable's working directory set to the
source `prototype` directory, which contains `project.godot`, without `--path`.
The complete EXE/PCK package is usable from that CWD; the old missing-package
failure is not reproduced. All 285 frozen source hashes still match the export.
