# I11 — Match, map and AI contract

## Match and map boundary

`RoRMatchDefinition` is the validated external description of a match. It owns map size/seed/generator settings, players, controllers, civilizations, starting resources and housing, static entities, diplomacy, victory rules and the start message. Invalid sizes, teams, controllers, civilizations or entity positions fail with stable reasons before a world is created.

`RoRRandomMapGenerator` is a pure seeded transformation from a normalized match definition to terrain cells, vertex heights and procedural resource placements. It never uses the global RNG. Equal definitions produce equal map dictionaries; changing the seed changes procedural placements while declarative geometry remains unchanged.

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

## Match controls

Space pauses; comma/period change the fixed-tick speed; R restarts the same definition and seed; Shift+R submits resign; Escape closes the application. These inputs are presentation intents only and do not mutate simulation objects directly.

## Evidence and limits

- `test_match_definition.gd`, `test_random_map_generator.gd`, `test_match_bootstrap.gd`.
- `test_ai_player.gd`, `test_ai_command_pipeline.gd`.
- `test_player_registry.gd`, `test_resign_pipeline.gd` and replay round-trip coverage.
- `test_ai_vs_ai_match.gd`: both sides receive their legal snapshots, issue accepted public commands and finish a deterministic unscripted conquest match.
- Full suite at integration: `108 passed, 0 failed`.

I11 is `INTEGRATED`, not `PARITY`. I12 must expand random-map algorithms/biomes and fairness rules, authoritative build availability for economic AI, naval AI, difficulty policies, multi-team diplomacy UI, scenario actions/triggers, imported RoR scenarios and long L4 balance/stability matches.
