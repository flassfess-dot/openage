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
avoidance arithmetic, and returns only a proposed velocity; GDScript still
owns position integration and every gameplay transition.

`RoRVisibilityKernel` performs only the bounded circle-to-row-major-cell
geometry. Player/alliance relations, explored/visible state, overlap counts,
revisioning and presentation remain in the deterministic GDScript fog system.

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
4x4 preview immediately and refine it on `WorkerThreadPool`; scene resources and
mesh upload remain on the main thread. Only the newest request may install its
result. Reconfiguration and shutdown join outstanding work. The GDScript renderer
remains the fallback when the extension is unavailable.

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
