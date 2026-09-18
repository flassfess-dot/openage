# RoR native pathfinding kernel

This optional GDExtension accelerates only the dense A* search used by the
authoritative GDScript pathfinder. Terrain/restriction rules, endpoint
selection, direct-path checks, smoothing, orders, economy, save/load and
replay remain in GDScript.

The kernel consumes a revisioned byte mask produced by `RoRPathfinder`, uses
the same direction order, diagonal corner rule, octile heuristic and stable
score/y/x heap tie-break as the fallback, and returns the raw cell path. If the
extension cannot be loaded, `RoRPathfinder` automatically uses its original
GDScript implementation.

Build on the development machine from the repository root:

```powershell
.\tools\build_native_pathfinding.ps1
```

The script acquires the pinned official `godot-cpp` `10.0.0-stable` source
when `.tools/godot-cpp` is absent and writes the local DLL to `prototype/bin`.
Generated bindings, build objects and the DLL are ignored; source, the
`.gdextension` descriptor and the deterministic fallback are tracked.
