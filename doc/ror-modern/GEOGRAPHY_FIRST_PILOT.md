# Geography-first map pilot

Current status (2026-10-18): the shared revision 6 generator is now the default
for all nine profiles. See [the current contract](RANDOM_MAP_WORLD_V6.md).
The pilot stages below record the development of this implementation.

The initial opt-in generator revision 4 creates land/sea silhouettes, relief, cliff
footprints and regional woodland domains before selecting any settlement site.
That pilot supports Islands, Coastal, Highlands and Grasslands. At that stage,
ordinary settings still selected revision 3. No release package was changed.

## Preview

From the repository root in PowerShell:

```powershell
.\tools\preview-geography-first.ps1 -MapType islands -Seed 41721
.\tools\preview-geography-first.ps1 -MapType highlands -Seed 41721
```

The preview uses the game's terrain, elevation, tree, cliff and building
renderers. Choose a profile, size and seed, use the wheel to zoom and the middle
mouse button to pan. The “Крупная география” switch compares the pilot with the
existing generator; it limits the profile list to the four pilot profiles.

API clients opt in with `landscape_version: 4` in skirmish settings. The match
definition records generator revision 4 and explicit selected starts. Geometry
is reconstructed from seed, size, profile and capacity, independent of start
positions. Geometry and woodland use separate seeded random streams.

## Composition and playability

- Islands include independent offshore landforms in addition to the major
  landmasses. A warped channel field keeps the major landmasses separated.
- Coastal maps combine large embayments and headlands with regional shore
  detail; seeds can place the ocean on different map edges.
- Long cliff spines have open ends and explicit passes. Their obstruction
  footprints exist before settlement selection.
- Woodland regions scale with the map. Trees may occupy legal gentle slopes.
  Resource placement protects forest interiors, and economic routes prefer
  woodland margins and existing corridors. Crossing woodland remains possible
  where required to preserve access.
- Settlement candidates need land clearance, usable component area and player
  separation. Local terraces accommodate starting buildings and villagers.
- The existing final validator checks resources, shared land where required,
  dock/staging access, terrain gradients and the published content hash. The
  pilot additionally requires at least 10% forest coverage and a largest
  connected grove of at least 1.5% of the dry-land area.

Invalid geography fails explicitly rather than silently changing the seed or
map size. This is a composition pilot, not a claim of original RoR map parity.
It does not yet cover every catalog profile, exhaustive seeds or full AI matches.

## Verification entry points

- `tests/unit/test_geography_first.gd`: profile/seed/size/player matrix, final
  quality, additional islands, woodland coherence, serialized-definition
  regeneration and generation time. `-- --islands-only` reruns the island cases.
- `tests/integration/test_geography_first_live.gd`: bootstrap into the actual
  simulation, cell occupancy agreement and footprint-aware worker paths to
  nearby food, wood, gold and stone.
- `tests/unit/test_random_map_natural_landscape.gd`: existing revision 3 checks
  and frozen revision 2 surface/elevation identities.
- `tests/manual/capture_geography_first.gd`: control images through the real
  renderer. Logs and measurements belong in `prototype/qa/geography-first-20261018/`.

## Wild islands and rivers

Revision 5 is a separate opt-in Islands pilot. Geography does not receive player
positions or count. Starts require only a usable foothold; minerals, island size,
woodland and distances remain unequal. Enable `landscape_version: 5` and
`river_network: true` in skirmish settings, or run:

```powershell
.\tools\preview-river-islands.ps1
```

This launcher opens the saved single 400 x 400 map, seed 41721. The preview can
zoom and pan without regenerating it. A changed seed explicitly generates a new
map. Preview captures use the actual game renderer and environment pack.

Independent island families retain irregular sea straits instead of merging
into one continent. Before settlements, priority-flood drainage routes runoff
from the relief to the sea; catchment area determines river width. Substantial
basins expose tributaries, while tiny coastal streams stay implicit. Head
strictly decreases downstream and discharge increases at confluences.

River terrain distinguishes submerged shoals (source terrain 15, blocked for
ships and land units), navigable water (1), deep lower channels (22), and dry
inner-bend sediment bars (6). The shoal renders with the shallow-water material
while retaining its own navigation class. A continuous scoured main channel
prevents tributary banks from blocking ship clearance. Resources and scenery
respect the river reservation. These are static generated channels, with no
runtime fluid simulation or tides.

`tests/manual/capture_one_wild_islands.gd -- --river-islands --map-type=islands
--map-size=supergiant --seed=41721` saves one map and overview/detail images to
`prototype/qa/river-islands-one-20261018/`.
`tests/manual/verify_river_islands_saved.gd` loads that exact saved map and
checks native/script shoal restrictions, main-channel clearance, ship routes
from the sea, actual command-driven ship arrivals, unobstructed river
reservations and drainage graph invariants. Water-route smoothing validates
the swept hull and re-smooths unsafe native shortcuts around shoal corners.

## Continental watersheds, lakes and fords (revision 6)

The common hydrology stage in `random_map_hydrology.gd` admits lakes in every
geographic family, including Highland. A profile may vary their frequency and
size rather than forbidding inland water. Lake capacity scales with map area;
actual lakes require a suitable depression. Rivers, lakes and crossings are
determined before player positions, without wealth or distance equalization.

The first revision 6 preview connected this stage to Continental and Highland.
The subsequent rollout to every menu profile is documented in
[the current contract](RANDOM_MAP_WORLD_V6.md). Preview a current map with:

```powershell
.\tools\preview-watershed-world.ps1
```

Continental generates a substantial asymmetric mainland, external sea, bays,
peninsulas, offshore islands, long ridges and regional woodland. Visible rivers
require large catchments, keeping broad interior regions between river systems.
Priority-flood spill levels identify enclosed depressions for lakes; their shore
and deeper interior are classified separately. These are static terrain basins.

Fords use original terrain 4 (Shallows), accessible to BOTH ground units and
ships. They are distinct from impassable submerged shoals (15). Candidates use
gentle, relatively straight middle reaches with comparable bank heights, away
from confluences, lake margins and estuaries. Both banks and approaches remain
clear of trees, resources and cliff placement. There is no per-player crossing
allocation and no requirement that every river contain a ford.

`tests/manual/capture_one_watershed_world.gd` records one 400 x 400 Continental
map, seed 41721, with overview, ford and lake details in
`prototype/qa/continental-one-20261018/`. The saved example has five lakes,
six fords and eight river outlets. Generation/preview preparation took about
48 seconds on this host. `tests/manual/verify_continental_hydrology_saved.gd`
loads that exact fixture, checks both ship restrictions and infantry against
native/script masks, verifies paths across every ford, and exercises actual
move-command arrivals for infantry and boats at three fords. It also checks
seed determinism on a small geometry fixture and permits a lake on Highland
160 x 160. No release package is produced by these previews.
