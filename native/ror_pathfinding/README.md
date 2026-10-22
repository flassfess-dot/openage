# RoR native navigation kernels

This optional GDExtension accelerates the measured dense A*, local-avoidance
and visibility-footprint hot loops used by the authoritative GDScript
simulation. Terrain/restriction rules and endpoint selection remain in
GDScript; the same revisioned mask now also handles measured direct-cell and
smoothing geometry. Fog ownership/counts, orders, integration, stuck recovery, economy,
save/load and replay remain in GDScript.

The kernel consumes a revisioned byte mask produced by `RoRPathfinder`, uses
the same direction order, diagonal corner rule, octile heuristic, smoothing
contract and stable score/y/x heap tie-break as the fallback, and returns the
raw or smoothed cell path requested by the caller. If the
extension cannot be loaded, `RoRPathfinder` automatically uses its original
GDScript implementation. The local-movement kernel consumes one immutable
per-tick snapshot, reproduces stable-ID neighbor order and the existing
avoidance arithmetic, and returns a proposed velocity. The owner-thread motion
integration pass applies the same destination clamp, terrain interpolation and
facing arithmetic, returning one union of changed entity groups. Set
`movement_system.native_integration_enabled = false` to compare its GDScript
reference. Route decisions, arrival and stuck recovery remain in the existing
ordered gameplay loop.

`RoRVisibilityKernel` collects bounded source footprints and applies ordered
visibility deltas to detached packed buffers. Circle geometry allocates its
bounded cell buffer once. Personal exploration records only the sorted fringe
outside the previous footprint for the same owner; reset retires all footprints
and checkpoint restoration retains their personal exploration together.
Player/alliance policy and revision boundaries remain with the owner-thread
GDScript fog system. Hidden observation memory is unchanged.

Owned AI actor profiles are built directly from complete normalized runtime
records. Incomplete records and foreign estimates use the catalog reference.
The native capture kernel also accepts an internal ownership-transfer operation:
all mutable containers reached through mutable parents belong to the producer
and may be frozen in place, including before a failed validation. Readonly
borrowed parents retain normal detachment semantics for mutable descendants.
Packed buffers are always copied, and live objects/callables/signals/RIDs remain
invalid. Both capture paths avoid rewriting unchanged scalar slots already
present in a shallow copy.

Build on the development machine from the repository root:

```powershell
.\tools\build_native_pathfinding.ps1
```

The script acquires the pinned official `godot-cpp` `10.0.0-stable` source
when `.tools/godot-cpp` is absent and writes the local DLL to `prototype/bin`.
Generated bindings, build objects and the DLL are ignored; source, the
`.gdextension` descriptor and the deterministic fallback are tracked.

The walkability mask accepts validated, atomic patches for the exact cells in
`RoRNavigationGrid`'s bounded revision journal. An expired or incomplete journal
still causes a full mask rebuild. Adding or removing a local obstacle therefore
does not rescan all 160,000 cells of a supergiant map on the next path query.

`RoRTerrainKernel` builds presentation geometry from detached numeric terrain,
elevation and atlas samples. Its full-detail output matches the GDScript terrain
reference (8x8 material blends, 16x16 coast contours). Camera changes display a
4x4 soil-blend preview immediately and refine it on `WorkerThreadPool`; coastline
cells retain 16x16 geometry in both passes so the water contour never changes.
Scene resources and
mesh upload remain on the main thread. Only the newest request may install its
result. Reconfiguration and shutdown join outstanding work. The GDScript renderer
remains the fallback when the extension is unavailable.
River geometry uses a four-component depth field (bank distance, influence,
depth below water, gravel fraction), preceded by six material slots. Exposed
silt/gravel, submerged shelves and deep water use the same field as logical
terrain classification. The native walkability model recognizes both added
land materials, 1004 and 1005.
The CPU worker partitions indexed triangles into at most 16384 vertices per GPU
part, preserving every attribute and triangle order. Upload and retirement are
bounded on main; a full replacement publishes only after every part is ready.
`known_resources_in_bounds` filters the observer's legal memory buckets directly,
without accepting a live world/resource index or revealing hidden depletion.

Regression coverage:

- `prototype/tests/unit/test_native_terrain_mesh.gd`: reference geometry, UVs,
  lighting, shore blending, boundaries and slopes.
- `prototype/tests/unit/test_async_terrain_mesh.gd`: superseded camera requests,
  full-detail output, invalidation, reconfiguration and shutdown.
- `prototype/tests/unit/test_incremental_navigation_masks.gd`: 400x400 local
  updates, fallback rebuilding, route parity and forest surface invalidation.

`prototype/tests/manual/benchmark_large_random_match.gd` reproduces the reported
Mediterranean / two-player / supergiant camera freezes. It runs 700 simulation
steps and clicks the minimap at steps 200, 400 and 600. Pass `--rendered` after
`--` (and omit `--headless`) to include actual frame rendering, `--ticks=1400` for
a longer run, and `--output=<path>` for the JSON report. Run packaged checks using
the exported executable with its directory as the working directory and its updated `bin` DLL; loading only the PCK with
a different executable can silently test the GDScript fallback instead.
