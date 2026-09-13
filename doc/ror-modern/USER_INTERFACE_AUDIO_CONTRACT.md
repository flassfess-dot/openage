# I10 — User interface and audio contract

## Boundary

The user interface is a presentation client of the authoritative simulation. `RoRHudViewModel` reads only a detached presentation snapshot plus normalized catalogs. It may localize and format values, but it must not recalculate command legality, prices, prerequisites, population limits, queue rules or match results.

Every state-changing HUD action creates the same immutable command used by pointer input, replay and AI. Train, research and cancel therefore pass through `GameController`, receive a command result and publish typed events. A button is enabled only by availability data produced by `SimulationProductionSystem`.

## Screen contract

- The top strip displays the authoritative resource, population and age models.
- Selection information is derived from the visible snapshot; hidden entities cannot leak into the HUD.
- Mobile multi-selection exposes the five formation commands. A single worker exposes an age-filtered data-driven building palette; a selected building exposes train/research, costs, disabled reason, queue progress and cancellation.
- Object and technology commands carry their original DAT icon IDs. `RoRInterfaceIconRegistry` maps them directly onto complete Interfac SLP 50730 (61 frames) and 50729 (101 frames); availability and pricing remain authoritative simulation data.
- HUD controls are anchored to the 1280×720 virtual canvas; Godot preserves aspect ratio for other window sizes. The control layer also remains valid if its parent canvas changes size.
- Minimap projection is an exact reversible world-space mapping. Fog filters dots, the camera polygon shows the visible world region and click/drag recenters through the same camera function as control groups.
- Debug information remains opt-in and is not needed to conduct the prototype match.

## Audio contract

`RoRPresentationAudioRouter` resolves logical sounds from the selected civilization's runtime presentation. Weighted variants are deterministic for a supplied event seed, missing assets fail silently with a typed reason, and per-category cooldowns prevent repeated selection/combat sounds from becoming a burst.

Animation-owned sounds follow `archetype -> animation graphic -> graphic sound_id/frame event -> logical sound variants -> imported WAV`. This preserves original attack, conversion, healing, gathering and death bindings instead of inventing filename rules. Domain sounds are emitted only when the associated entity exists in the observer's presentation snapshot, so fog does not disclose unseen activity. Eight presentation players allow legitimate overlap without one event cutting off the previous one.

Music and effects have separate players. Muting effects pauses the SFX player without changing simulation state.

## Evidence and limits

- `test_hud_view_model.gd`: snapshot-to-view-model, localization, availability reasons and queue formatting.
- `test_hud_command_pipeline.gd`: HUD model to train/cancel commands, controller result, domain event and updated snapshot.
- `test_main_hud_scene.gd`: real scene geometry, formation controls, minimap recenter and resized control canvas.
- `test_minimap_projection.gd`: reversible projection, map polygon and bounds.
- `test_presentation_audio_router.gd`: original selection/command/train/death IDs, real WAV loading, deterministic variants and throttling.
- `test_presentation_audio_event_router.gd`: visibility-safe attack/death/conversion/healing/gather/build/train event mapping.
- `test_interface_icon_registry.gd`: complete source sheets and direct DAT icon lookup.
- `test_build_palette_pipeline.gd`: worker palette -> icon button -> placement click -> normal BuildCommand -> foundation.
- Reviewed L3 frame: `prototype/qa/golden/hud-main-1280x720.png`.

I10 is `INTEGRATED`, not `PARITY`. I12-018 closes source icon coverage, the age-filtered construction palette and active sound variants/events of the current land slice. Remaining UI/audio work includes every contextual command and warning, menu/settings flows, naval bindings, multiple reference resolutions and side-by-side RoR comparisons.
