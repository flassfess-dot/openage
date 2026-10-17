# Match autosave

Single-player matches expose one `Автосохранение` entry in both load menus.
The durable path is `user://saves/autosave.json`; quicksave and named saves are
independent. The automatic name is reserved against manual impersonation.
The timer uses active real play time: first request after 15 seconds, then
60 seconds between requests. Pauses, briefing/results, modal menus, launcher
suspension and navigation loading do not advance it. Completed and network
matches do not start automatic saves. The existing network save limitation
remains in effect.

## Frame and ownership contract

The initial complete checkpoint and catalogs are detached under the loading
screen. A single low-priority `Thread` owns the recovery simulation. On demand
it advances from that checkpoint using exact recorded player/AI commands,
captures the full checkpoint, compresses, hashes, encodes and writes it.
Its internal task coordinator uses the deterministic sequential path, keeping
recovery calculations off the live match's shared worker pool.
Recovery uses recorded commands, retaining the ordinary loading contract:
preparing AI views also establishes durable fog/resource memory and must not be
skipped. Between fixed steps it yields regularly in addition to its low OS
thread priority, reducing contention with the visible match.
The foreground only transfers newly issued commands, small AI/player state and
an authoritative state anchor. It never recursively validates, copies, encodes
or writes the complete world during periodic saving, and never waits for an
unfinished task in the match loop. One job may be in flight; requests do not
accumulate. Completed large DTOs are released on the worker.

This approach uses additional CPU and memory for one private world. It does
not read a concurrently changing live world. The initial seed must detach all
mutable buffers: in particular `knowledge.*.grid.learned` needs an explicit
`duplicate()`. Its former alias allowed the seed to change after capture and
caused different routes. Gate planning revisions are also retained, with a
backward-compatible default for older checkpoints.

Autosave waits for an ordinary AI decision publication before capturing small
metadata; it does not encode a pending whole-map AI observation in a rendered
frame. AI state, pending command acknowledgments, camera/selection/control
groups, sound history, fog and complete match statistics/TimeLine retain the
existing checkpoint/restore contract. A mismatching recovery anchor fails
closed and leaves the last complete slot in place.

## Commit and lifecycle

The worker writes a private same-directory staging file. Both its replacement
and publication to the durable slot use `RoRSaveFileKernel.replace_atomic`.
On Windows this is `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`, preserving
the previous file on failure; Godot's Windows rename was verified to remove
the destination before a failing rename and must not publish this slot.
Writes check the file error after flushing. No autosave `.bak` is retained.
Only the main owner publishes a completed result. A reset, load or exit joins
and discards its worker before replacing the match; an obsolete result cannot
replace the slot. The worker world is released before a load allocates the new
world. Failed explicit loads reseed autosaving for the still-valid old match.
Abandoned staging files from exited processes are cleaned on initialization;
active process files and other matches' staging files are left alone.

The normal match loop does not scan/read the save catalog. Entering a load menu
reads it; completion patches the cached menu models directly from the small
worker result. The launcher also polls a suspended match's completed write.

## Verification

`test_autosave_archive.gd` checks atomic replacement (including Unicode paths),
an interrupted write, one visible slot, hidden staging and reserved naming.
`test_checkpoint_buffer_isolation.gd` protects the detached learned-cell buffer.
`--verify-autosave` drives the real match scene and loader, compares **every
durable checkpoint field** with the source tick while the source keeps advancing,
and checks repeated overwrite, pause/menu/suspension, control groups and load
cancellation. It uses isolated QA paths and never overwrites the user's saves.
`--verify-autosave-live` records natural rendered frames before, during and
after a save while simulation continues, and captures the actual load menu.

The packaged Release exported on 2026-10-17 passed all three diagnostic entry
points. On the existing 400×400 Mediterranean save `11212`, tick 64222 exactly
matched every durable source checkpoint field; foreground preparation took
2,709 μs. In the rendered 1280×720 run it took 3,249 μs while the live simulation
advanced from tick 64185 to 64690. The small rendered lifecycle run took 257 μs.
All three reports confirm that the recovery world does not use the live
match's worker pool. The original named save's SHA-256 remained unchanged.

The rendered Release run measured a median frame of 16.67 ms before, during
and after saving. During the background job, three of 795 frames exceeded
100 ms (maximum 216.90 ms), versus none in the shorter surrounding windows.
These measurements prove that full checkpoint capture and encoding no longer
block the match loop, but do not prove the absence of occasional long frames
or establish their cause. The reports retain these outliers rather than
treating a successful save/load as proof of perfectly smooth rendering.

A separate 30-second A/B diagnostic used the editor runtime with the same
save, speed, fixed camera, 1280×720 window and per-stage instrumentation.
It is not a packaged Release FPS comparison. With autosave disabled/enabled,
the longest frames were 258.47/315.78 ms at the same simulation tick 64405;
the live AI snapshot dominated both, specifically navigation topology capture
(185.90/235.99 ms). This establishes an existing source of long frames, while
also showing contention overhead during recovery work: mean frames were
23.53/27.99 ms, p95 57.06/68.02 ms. Peak Godot static memory was 2.59/5.23 GB.
The background design avoids a synchronous full-world snapshot pause; it does
not make recovery computation or its additional world free of CPU/RAM cost.
Both complete A/B reports remain in the QA directory.

Existing manual save/load, checkpoint continuation, pending AI save/resume and
background manual-save queue checks must also pass. The release workflow uses
`tools/ror-full-build.ps1 -VerifyStartup`, followed by the autosave diagnostic
entry points in the actual Release executable. `prototype/qa/autosave-20261017/`
contains the reports and logs; these files are excluded from game export.

The subsequent AI/movement optimizations and recovery pacing were verified in
the full Release built at 01:14 on 2026-10-18. Both checkpoint/lifecycle probes
passed. In the 120-second x1 large-map run, two autosaves completed with 3.57 ms
foreground preparation, mean frames of 18.409 ms during saving versus 18.395 ms
idle, p95 34.83/33.55 ms and no frame above 100 ms. Accelerated x2 large-map play
still failed the frame/speed acceptance checks; successful background saving
does not resolve all simulation throughput limits. Full results and historical
failures are in [AI_SMOOTHNESS_20261017.md](AI_SMOOTHNESS_20261017.md) and
`prototype/qa/ai-smoothness-20261017/`.
