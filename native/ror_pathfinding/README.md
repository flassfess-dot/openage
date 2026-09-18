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
