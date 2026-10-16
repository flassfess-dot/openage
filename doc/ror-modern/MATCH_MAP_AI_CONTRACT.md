# I11 — Match, map and AI contract

## Match and map boundary

`RoRMatchDefinition` is the validated external description of a match. It owns map size/seed/generator settings, players, controllers, civilizations, starting resources and housing, static entities, diplomacy, victory rules and the start message. Invalid sizes, teams, controllers, civilizations or entity positions fail with stable reasons before a world is created.

`RoRRandomMapGenerator` is a pure seeded transformation from a normalized match definition to terrain cells, vertex heights and procedural resource placements. It never uses the global RNG. Equal definitions produce equal map dictionaries; changing the seed changes procedural placements while declarative geometry remains unchanged.

E5-003 adds a versioned `seeded_skirmish_v1` boundary instead of teaching the launcher terrain rules. `RoRRandomMapContract` translates a catalogued profile into topology/resource/elevation requirements; `RoRRandomMapGenerator` materializes it; `RoRRandomMapQuality` independently audits the result before launch. The generated map dictionary is then handed to `main.tscn`, so a successful seed is not regenerated during scene startup.

Current engine profiles are `inland_v1`, `highlands_v1`, `coastal_v1` and `islands_v1`. They guarantee:

- every Town Center start is on land and all starts respect a size-relative separation;
- inland/coastal starts share the required land component, while island starts each own a minimum viable land component;
- water ratio stays inside the profile's declared interval;
- every player receives nearby food, wood, stone and gold clusters;
- every coastal/island player receives a deterministic legal dock footprint plus land/water staging cells;
- identical match definition and seed produce an equal terrain/resource/naval-zone dictionary.

Map sizes declare player capacity, preventing eight players from being forced onto the compact profile. These are stable engine guarantees, not a claim that current preset labels/dimensions or topology distributions already reproduce classic RoR. Their source status remains pending executable calibration.

`RoRMatchBootstrap` is the only normal path that applies a match to `SimulationWorld`. It resets the world without legacy demo objects, configures terrain/elevation/navigation, players and civilizations, resources/housing, diplomacy, entities/objectives and victory rules. Restart reapplies the same map and produces stable entity IDs. `main.gd` no longer contains a hand-authored army/resource setup and draws/minimaps the active map size and seed.

## Player and diplomacy boundary

`RoRPlayerRegistry` owns public player identity, controller type, civilization, symmetric ally/enemy/neutral relations and the lifecycle `active -> resigned|defeated|victorious`. Fog sharing and combat queries use the same alliance decision. Player state is included in both presentation and canonical replay snapshots.

Resign is an immutable player command, is serialized by replay, produces command result plus `player_resigned`, and participates in the configured victory system on the same fixed tick. Commands from a non-active player are rejected with `player_not_active`. Conquest emits `player_defeated` once when a participant has no qualifying units/buildings.

## AI boundary

An `RoRAiPlayer` never owns or reads `SimulationWorld`. It receives only `SimulationSnapshot.presentation(..., its_team)`, so unseen entities and resources cannot enter a decision. The snapshot exposes public diplomacy but not hidden enemy state.

- The strategic layer chooses a legal observed or remembered enemy objective, or a deterministic exploration goal.
- The economic layer assigns idle workers to visible resources and consumes authoritative building command options for train/research; it does not duplicate prices or prerequisites.
- The tactical layer converts a goal into normal attack, attack-move or formation-move commands and uses the same formation lifecycle as the human player.

AI commands use the normal controller queue, issuer/ownership checks, results, events and replay recording. Cadences prevent duplicate decisions when several render frames precede one fixed tick. A terminal AI produces no further commands.

E5-005 adds a separate engine-owned `skirmish_policy_v1` contract. The launcher selects `easy`, `standard` or `hard`; the generated match records the resolved cadence, initial attack delay, attack separation, minimum/maximum group size and defensive response distance. The policy contains a pinned relative path/hash and six explicitly selected values from the AoE DE build 97381 evidence ledger, but neither the DE installation nor the full ledger is read by the match runtime. DE remains secondary evidence, not executable authority.

The tactical planner sorts eligible fighters by stable entity ID, waits for the minimum force, caps the issued group and sends only public attack commands. The opening delay and regroup interval can be bypassed only when a visible enemy lies within the configured response distance of a living owned unit or building. This extension applies only to generated skirmish AI; legacy and source-campaign profiles retain their existing behavior.

E5-006A extends the same policy with an engine-owned opening economy. Construction priorities and limits, housing reserve, land-worker target, age technology IDs and minimum structure clearance are policy data rather than planner constants. The AI sees authoritative command availability and research costs through its own presentation snapshot; future age planning exposes no enemy or map state. It serializes foundations, uses only reachable approach sites, can replace a failed builder, saves the required source resources and never recruits workers into an ordinary strike group.

A building centre is the default "no rally point" sentinel. Produced units remain at a valid exit slot unless a real rally point was set. A fighter whose previous destination was unreachable receives an individual move to the nearest observer-known navigation point; healthy members keep their strategic group order.

E5-006B closes the first complete generated outcome. The presentation snapshot derives reachable land/water fog frontiers during the existing navigation scan, without exposing unknown cells or copying the full fog array into the skirmish planner. With no visible enemy, the strategic layer advances toward a deterministic far frontier from the owned centre. A multi-unit explorer receives one formation route; normal combat awareness releases members into individual engagements when an enemy becomes visible.

E5-006C2a closes the generated fishing loop. Naval map resources require enough water clearance for the source-sized Fishing Boat approach and preserve their quality-checked positions through bootstrap. Resources without an explicit gatherer-domain declaration default to land-only. The policy owns separate `land_worker_target` and `water_worker_target` composition goals, but both unit classes consume the same authoritative population and housing capacity. The AI discovers fish only through fog-safe knowledge and uses normal train/gather/deposit commands.

E5-006C2b closes autonomous generated-island transport landing. The AI uses only fog-safe presentation data and public board, move and unload commands. Navigation requests carry the mobile entity's footprint radius through goal projection, A*, path smoothing, cache identity and reachability checks, so a path accepted by the global planner obeys the same terrain-clearance contract as local movement.

E5-006C2c proves naval combat can close a generated-map match without a special victory path. Both AI sides discover and attack through the normal presentation/command boundary; source projectile impacts, death removal, participant defeat and the common conquest rule produce the terminal result.

E5-006C3 extends the generated naval contract to four and eight participants on both coastal and islands profiles. A naval start is accepted only when its Dock/staging pair has enough clearance-valid open water inside the resource guarantee radius. Naval resource clusters are allocated round-robin across teams and use bounded placement, preventing early starts from exhausting later starts or moving their guaranteed fish outside the audited radius. Clearance capacity is precomputed and cached during generation.

## Match controls

Space pauses; comma/period change the fixed-tick speed. R is reserved for villager repair and Shift+R has no destructive shortcut. Escape cancels targeting/construction first, then opens the match menu; F10 opens/closes that menu, and F1 opens help. Restart/resign/load/exit are explicit confirmed menu intents. Split flank formation moved from F10 to Shift+F9. These inputs are presentation intents only and do not mutate simulation objects directly. See `MATCH_MENU_CONTRACT.md` for sections, TimeLine, confirmation and layout rules.

## Evidence and limits

- `test_match_definition.gd`, `test_random_map_generator.gd`, `test_random_map_profiles.gd`, `test_match_bootstrap.gd`.
- `test_ai_player.gd`, `test_ai_command_pipeline.gd`.
- `test_skirmish_ai_policy.gd`, `test_skirmish_settings.gd`, `test_launcher_scene.gd` and `test_generated_skirmish_main_scene.gd` cover evidence pinning, difficulty resolution and generated-match propagation.
- `test_player_registry.gd`, `test_resign_pipeline.gd` and replay round-trip coverage.
- `test_ai_vs_ai_match.gd`: both sides receive their legal snapshots, issue accepted public commands and finish a deterministic unscripted conquest match.
- `test_generated_skirmish_ai_acceptance.gd`: a generated inland opening reaches housing, Barracks/Granary, Tool Age and a policy-sized attack group through public commands.
- `test_generated_skirmish_deterministic_outcome.gd`: a generated two-player inland match reaches conquest, then a fresh runtime replays the recorded public commands to an identical terminal tick, canonical hash and victory result.
- `test_generated_naval_ai_acceptance.gd`, `test_generated_naval_economy_pipeline.gd`, `test_generated_transport_landing_pipeline.gd`, `test_generated_naval_combat_victory.gd` and `test_generated_multiplayer_naval_matrix.gd`: autonomous islands discovery, generated Dock/Fishing Boat/Deep Fish/deposit, Transport embark/sail/landing, naval combat/conquest and 4/8-player coastal/islands openings.
- Full suite at integration: `108 passed, 0 failed`.

I11 is `INTEGRATED`, not `PARITY`. Under the 2026-09-14 core-first rebaseline, E3 first revalidates the common gameplay command/AI boundary, E4 supplies the complete civilization content consumed by it, and E5 expands skirmish setup, random-map algorithms/biomes/fairness, economic/naval AI, difficulty and multi-team diplomacy. Long load/stability gates belong to E6. Scenario actions, imported RoR scenarios and campaigns are deliberately postponed to E7 so they consume a stable engine instead of driving it.

## Normal-resource age progression regression (2026-10-03)

Reserving the resources for the next age restricts spending, not the set of deposits workers may gather. Filtering that set to the age's cost types caused a Stone Age deadlock: food accumulation continued, while the wood required for prerequisite buildings could never be replenished. Legal observer-known wood and other resources remain available for economic assignments during saving; existing production/construction spending restrictions remain in force.

`test_ai_player.gd` checks prerequisite wood gathering while reserving food for Tool Age or food/gold for Iron Age. `test_standard_resource_ai_progression.gd` uses a generated compact Grasslands match (seed 41721), ordinary 200 food/200 wood, standard difficulty, no free AI resources and no prebuilt prerequisites. The AI completes its own Barracks/Granary and Tool Age at tick 14580. The passive opponent receives extra HP solely to prevent victory from terminating the economy regression early.

The longer diagnostic in `profile_skirmish_age_progression.gd` also reaches Bronze Age from ordinary starting resources. This confirms removal of the age-saving deadlock; it is not an economy-speed or late-game combat parity claim. Evidence is under `prototype/qa/economy-fixes-20261003/`.

## Adaptive skirmish policy — 2026-10-11

Generated skirmishes enable `adaptive_strategy` in the existing engine-owned `skirmish_policy_v1` profile. Legacy fallback and source-campaign decisions continue through their original planners. The new heuristics are engine-owned improvements, not a claim of original RoR AI parity or a trained model.

`ai_strategy_state.gd` owns common strategic goals, independent land/naval objectives, bounded enemy memory and own command feedback. Remembered positions lose confidence over the configured simulation lifetime; a fog-memory row cannot refresh a sighting. Observer-visible empty locations disprove an old observation. Goal utility combines base defence, economic/strategic target value, distance, danger and target inertia. Foreign live actors are never looked up: `ai_observation_profile.gd` enriches owned actors with actual statistics, and estimates foreign actors from public DAT definitions and legal observed rows. Own available production profiles include researched combat modifiers and exact population points.

`ai_plan_budget.gd` reserves resources, queued population points and one proposed spending order per producer for the whole decision. It includes every queued unit's future population demand. Age saving protects the required resource types; housing, essential worker recovery and food infrastructure can use emergency reserves. Every action still uses authoritative availability, normal costs and the controller's ownership/legality checks. A rejected proposal produces a bounded retry cooldown. Repair consumes resources over time in the ordinary simulation; its advisory policy keeps a wood reserve rather than pretending all future repair charges are known.

`ai_adaptive_economy.gd` forecasts 30–60 seconds of expected production, age and infrastructure demand. Observed stock changes plus accepted proposal spending estimate income; repairs, tributes received and other external changes can bias that estimate. Worker targets scale with age, time and population limit. Known nearby food scarcity enables farms; travel distances enable additional drop sites; a busy productive economy enables more producers and, where legal, another town center. At most two foundations run concurrently, and abandoned reachable foundations are recovered. Age research may be queued legally behind workers. Research utility weights effects against the owner's actual unit composition; training utility uses source attack/armor classes, HP, range, speed and observed enemy composition, with ordinary civilization availability.

Gathering uses a resource-type spatial index and batches assignments with worker rotation. Scoring accounts for forecast shortages, observed income, travel, dropoff distance, assigned gatherers, threat and switching inertia. Queries examine at most 16 typed buckets with 64 entries each and return a policy-bounded candidate list. All known resources enter the index. Failed worker/resource pairs expire or are released after changes to known navigation; a persistent completed order cannot refresh the same failure forever.

`ai_operations.gd` reuses `source_ai_attack_group.gd` membership, loss tracking, transitions and serialization. Skirmish operations retain assembly, march, combat, retreat and regroup phases, recruit reinforcements, respect known movement components and preserve members inside owned cargo. Strength is a deterministic estimate using the normal RoR damage-class calculation; it is not a full combat prediction. Attack and retreat thresholds use hysteresis. Existing combat awareness retains local target acquisition and fights; operations avoid replacing an active combat order unnecessarily. Dedicated scouts select known reachable frontiers, prefer fast military units and record information visits instead of sending the whole army to explore.

Transports retain loading, escort, sailing, unloading and return-for-troops missions. Ordinary worker villagers are excluded from assault cargo. Landing candidates come from the known target land component; up to 128 coast candidates receive threat scoring. A threatened route waits for enough local escort strength and assembly. Ships receive water approach destinations and normal board/move/unload commands.

Search budgets use fixed operation counts and stable IDs, not wall-clock stopping conditions or global randomness. Enemy memory defaults to 256 records, income history to 64 samples, scout visit history to 256 entries and operations to eight. Difficulty changes forecast horizon, search quotas, scouting cadence and strength thresholds as well as decision timing. Detached planning and the existing fixed source/apply barrier remain in use. Feedback is published between jobs; details of its save boundary are in `GAME_SAVE_CONTRACT.md`.

### Prepared measurements and current verification limit

`prototype/data/ai/benchmark_matrix.json` defines 30,720 reproducible cases across five seeds, four map topologies, two sizes, two resource presets, Stone/Bronze starts, two difficulties, sixteen civilization pairs, three opponent policies and swapped positions. `early_pressure` and `economic_growth` are reproducible policy variants using normal fog, costs and production rules.

`prototype/tools/benchmark_ai.gd` is an explicitly invoked manual measurement runner using the normal AI runtime and fixed-tick gate. Arguments select `--case`, `--output`, `--revision` and optional `--sequential`. It records outcomes, age timing, worker idle ratio, rejected commands, losses, budget denials, simulated ticks and elapsed wall time. It is not invoked by startup or tests. `prototype/tools/summarize_ai_benchmark.py` reads saved reports, reports Wilson intervals and map/start/opponent strata, and compares matching cases between revisions. A timeout is a draw; these summaries alone do not establish causation or independence across correlated map cases.

`prototype/tools/check_ai_static.py` parses AI GDScript with gdtoolkit, parses Python source without execution, validates JSON policy variants and matrix references, checks preload existence/cycles and observer/feedback/replay source boundaries. It never launches Godot, tests, builds or matches. The implementation received only these static checks on 2026-10-11, as requested. Runtime type checking, tactical quality, performance, save/replay continuation and sequential/threaded equivalence remain unmeasured for the new implementation.

The static audit requires gdtoolkit 4.5.0. This workspace keeps its wheel installation in the ignored `.tools/ai-static` directory. No project/compiler dependency or game asset was rebuilt.


### Runtime regression follow-up — 2026-10-12

The first Godot run found problems not detected by the third-party grammar parser. Nested multiline lambda chains were simplified and ambiguous local variables received explicit types. The primary strategic objective now copies its domain-map entry before embedding `goals_by_domain`; this prevents recursive dictionary aliases during planning and state capture.

Adaptive gather retries now consult the expiring blacklist rather than the legacy completed-order veto. A living owned farm remains a valid resource for retaining that cooldown. Worker allocation also uses quotas per resource type, updated for each proposal in a batch, so an entire workforce cannot repeatedly follow one stock shortage. Owner-side profiles carry the current gathered amount and gather stage; an ongoing delivery is retained. These changes do not expose foreign live worker state. During base defence, the scout planner retains fighters for the responding operation.

Two regression tests cover the adaptive paths in addition to the existing suites. The unit test exercises resource/population budgets, legal memory expiry, separate domain goals without cycles, loss-based retreat, recovery of failed gather targets, delivery retention, worker allocation, exact saved feedback and sequential/threaded equivalence. The integration test exercises accepted public AI commands, unconsumed feedback, save/load and continued world/AI/command equality on a generated match.

The narrow fishing fixture now explicitly caps adaptive land workers to its intended starting workforce. The controlled naval weapon fixture accepts both attack and attack-move and explicitly commits both sides to combat; source projectile impacts, elimination and the winner are still checked. Default retreat behaviour remains covered separately. These are fixture updates for intentional AI behaviour, not relaxed simulation outcomes.

Run results and per-test engine logs are in `prototype/qa/ai-validation-20261012-final/`. The RTS benchmark matrix remains prepared but unexecuted; functional regressions do not measure win rates across that matrix. A Release package was not built or checked in this follow-up.

The completed targeted validation passed 49 tests with no actionable Godot errors. Subsequent scout fixes were checked with affected reruns, including ordinary-resource progression, inland/naval exploration, deterministic outcomes and adaptive save/resume. The consolidated result is `prototype/qa/ai-validation-20261012-summary.json`.

Scout missions now retain an in-progress movement target until arrival or a bounded deadline based on distance and observed speed. The generated inland fixture counts accepted scout moves separately from worker moves and verifies actual exploration away from the starting town, while retaining the army, age, legality and command-budget assertions. The ordinary-resource fixture completed Tool Age at tick 13,160 in the final rerun.

### Retained build-search topology — 2026-10-12

AI build-site captures publish immutable 16x16 cell pages. Exact local deltas copy only affected pages; unknown/expired deltas and epoch/source changes rebuild the publication. The old whole-grid DTO is still accepted. The queue retains at most eight private build-planner executors; an executor runs one non-overlapping job at a time and owns its mutable grid, native masks and route caches. Its grid consumes the captured change journal before cache reuse. Runtime object identity is kept only in the owner cache and is not serialized into the input. Cancel/load/match replacement releases executors; the task coordinator retains abandoned job owners until completion.

Decision cadence, source/apply ticks, legal observer knowledge and command ordering are unchanged. `test_chunked_build_topology.gd` checks old-publication isolation, local/full invalidation, exact worker walkability, native route invalidation and binary round-trip. `test_deferred_ai_build_sites.gd` compares cached and fresh planner commands, state and sites. Pending-plan and adaptive save/resume tests exercise continuation with derived caches rebuilt.

Short preparation waits retain wall-clock debt for up to 150 ms, capped at 350 ms of simulation time. A rendered frame still completes at most four ordered ticks and normally yields after its 24 ms simulation budget; these limits remain independent of AI cadence and command ordering. Waits longer than 150 ms restore the original pre-barrier debt, preserving protection against repeated long worker stalls. Pause, reset, replay and load clear the wait clock as appropriate. `test_preparation_wait_clock.gd` checks both short-wait movement/tick equality and the existing 400-frame long-wait protection. This changes wall-clock pacing, not fixed-step rules.

Food-coverage forecasts test resource type and land-worker eligibility before measuring proximity to drop sites. Trees and minerals still enter the gathering/delivery lookup; they do not incur food-coverage distance searches. `test_ai_food_coverage_policy.gd` checks nearby/distant food, water-only fish and non-food delivery distances.

AI actor portions use the existing `capture_frozen` native validation/detachment kernel before joining the pinned publication. The GDScript fallback remains available; object/callable rejection, immutable previous inputs and exact numeric/container types remain unchanged. Actor portions and producer quotas still bound the work; this removes repeated per-field GDScript registry probes rather than weakening isolation.
