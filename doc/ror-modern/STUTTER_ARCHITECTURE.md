# Periodic simulation stalls and durable checkpoints

Navigation maintains clearance-aware connected components for each movement configuration. Native and fallback planners share deterministic region IDs, diagonal corner rules, and blocked-origin escape behavior. Native disconnected endpoints are rejected before A*. The fallback reuses existing component information and otherwise resolves short cold requests through reference A*, avoiding an unnecessary map-wide scan. Native masks invalidate connectivity only when a patch actually changes walkability.

World routes, cell corridors and smoothed corridors have independent bounded caches. Positive geometry survives unrelated journalled topology edits; affected geometry and all negative results are invalidated. Eviction removes the oldest entry rather than clearing the complete cache. Navigation request observations retain only the latest 1024 payloads while request IDs remain monotonic.

AI groups and exploration frontiers use the observer’s learned navigation, domain, restriction and footprint. Formation commands partition disconnected members and choose a reachable member as route origin when the centroid is blocked. Both `no_path` and `no_group_route` enter local recovery with persistent bounded exponential retries. Resource observations retain compact records and apply memory deltas instead of reconstructing the entire explored resource list.

Save version 4 embeds the exact match, terrain and compressed typed checkpoint with a SHA-256 checksum. Simulation records, random state, queues, fog, reservations, formation state, autonomous decision phases and retained index membership survive loading. Catalogs and entity references are reconstructed in an isolated world before publication. Version 3 replay archives remain readable when their original match and generator are available. Legacy replay preserves `plan_only` construction parameters. Loaded live controllers bound acknowledgements and start feedback consumers after historical events.

The distribution uses `--export-release` and the Windows Release export template. It must report `OS.is_debug_build() == false` and lack the editor feature. Native navigation is compiled in Release.

Regression coverage includes disconnected islands, clearance and diagonal boundaries, topology invalidation, corridor reuse, bounded eviction, local AI recovery, legal incremental resource memory, cross-map loading, corruption rejection and identical simulation continuation after restore. Performance measurements use the original heavy save at tick 103578 and preserve its original archive.

## Verified heavy-save results

The exported Windows package was loaded by the Windows Release runtime. It reported neither the editor feature nor a debug build, restored tick 103578 on the exact 400 × 400 world, and passed the save hash check. The fixture contains 127 units (including wildlife), 70 buildings and 9016 resource nodes; its population limit is 500. The original named archive was preserved byte for byte. A separate “Тяжелое сохранение — обновлённое” slot contains the migrated version 4 checkpoint.

All 334 test scripts passed in one complete run after the final source changes. The log is `prototype/qa/heavy-save-analysis/final-suite-v3.out.log`.

| Measurement, 1000 updates / 50 simulation seconds | Original Release | Fixed Release |
|---|---:|---:|
| Mean update | 19.481 ms | 17.429 ms |
| 99th percentile | 99.533 ms | 38.958 ms |
| Updates above 50 ms | 50 | 1 |
| Native A* expanded nodes | 8,591,407 | 35,974 |

The next two continuous 100-second windows each contained one update above 50 ms. Their mean updates were 17.456 and 17.560 ms, and their 99th percentiles were 38.135 and 38.348 ms. There was no recurring one-second stall pattern or progressive timing growth in this run. Cache occupancy increases as genuinely new routes are explored, within the tested capacity limits.

These are instrumented CPU update timings with the same engine and project settings, run headlessly; they are not rendered FPS or GPU measurements. The AI remained continuously active throughout the three measured windows. The separate disabled-AI diagnostic ran afterward: resuming multiple overdue AI planners together would artificially synchronize their decision phases and invalidate a continuous-play comparison.

A remaining startup cost is initial preparation of native movement masks and AI placement/navigation indices: the first 40 updates included cold-cache pauses up to 915 ms. This is separate from the removed recurring route-search stalls. Rare ordinary update peaks remain (approximately 52–56 ms in these windows). The measurements do not guarantee a frame budget for every population, map or GPU.

The machine-readable report is `prototype/qa/heavy-save-analysis/fixed-measurements-summary.json`.
