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

- The strategic layer chooses a visible enemy or a deterministic exploration goal.
- The economic layer assigns idle workers to visible resources and consumes authoritative building command options for train/research; it does not duplicate prices or prerequisites.
- The tactical layer converts a goal into normal attack, attack-move or formation-move commands and uses the same formation lifecycle as the human player.

AI commands use the normal controller queue, issuer/ownership checks, results, events and replay recording. Cadences prevent duplicate decisions when several render frames precede one fixed tick. A terminal AI produces no further commands.

E5-005 adds a separate engine-owned `skirmish_policy_v1` contract. The launcher selects `easy`, `standard` or `hard`; the generated match records the resolved cadence, initial attack delay, attack separation, minimum/maximum group size and defensive response distance. The policy contains a pinned relative path/hash and six explicitly selected values from the AoE DE build 97381 evidence ledger, but neither the DE installation nor the full ledger is read by the match runtime. DE remains secondary evidence, not executable authority.

The tactical planner sorts eligible fighters by stable entity ID, waits for the minimum force, caps the issued group and sends only public attack commands. The opening delay and regroup interval can be bypassed only when a visible enemy lies within the configured response distance of a living owned unit or building. This extension applies only to generated skirmish AI; legacy and source-campaign profiles retain their existing behavior.

## Match controls

Space pauses; comma/period change the fixed-tick speed; R restarts the same definition and seed; Shift+R submits resign; Escape closes the application. These inputs are presentation intents only and do not mutate simulation objects directly.

## Evidence and limits

- `test_match_definition.gd`, `test_random_map_generator.gd`, `test_random_map_profiles.gd`, `test_match_bootstrap.gd`.
- `test_ai_player.gd`, `test_ai_command_pipeline.gd`.
- `test_skirmish_ai_policy.gd`, `test_skirmish_settings.gd`, `test_launcher_scene.gd` and `test_generated_skirmish_main_scene.gd` cover evidence pinning, difficulty resolution and generated-match propagation.
- `test_player_registry.gd`, `test_resign_pipeline.gd` and replay round-trip coverage.
- `test_ai_vs_ai_match.gd`: both sides receive their legal snapshots, issue accepted public commands and finish a deterministic unscripted conquest match.
- Full suite at integration: `108 passed, 0 failed`.

I11 is `INTEGRATED`, not `PARITY`. Under the 2026-09-14 core-first rebaseline, E3 first revalidates the common gameplay command/AI boundary, E4 supplies the complete civilization content consumed by it, and E5 expands skirmish setup, random-map algorithms/biomes/fairness, economic/naval AI, difficulty and multi-team diplomacy. Long load/stability gates belong to E6. Scenario actions, imported RoR scenarios and campaigns are deliberately postponed to E7 so they consume a stable engine instead of driving it.
