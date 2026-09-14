# E2/I12-020L — Source UI executable measurement

Status: `ACTIVE EVIDENCE GATE` for E2. The 2026-09-14 project capture is accepted as defect evidence for wrong layout/resolution adaptation/health presentation, but it is not evidence of how the original executable maps unresolved source frames.

## Purpose

This protocol prevents imported `Interfac.drs` frames from being assigned to `normal`, `hover`, `pressed`, `disabled`, health, progress or civilization styles by filename folklore or visual guesswork. The reference is the installed Rise of Rome 1.1 executable pinned in `prototype/data/parity/source_ui_executable_gate.json`.

The runtime may expose unresolved frames as candidates. It may not attach semantic interaction states until the gate contains immutable original captures and measured mappings. Simulation legality remains owned by the command pipeline; this protocol changes presentation only.

## Machine-established facts

- `data/Interfac.drs` SHA-256 is `8a7f1b1f9009d4bc0262c7890935d69d62668c80751ec3b861345064a0e63d33`; in-game palette is explicitly `50500`.
- IDs 50713…50716 each contain four 54×54 frames. Within each individual SLP all four decoded PNG hashes are identical. Therefore frame index cannot encode four distinct button states.
- IDs 50725…50728 each contain four 54×31 frames. Independent Genie-compatible reference code and the decoded pixels agree that frames 0/1 are normal/pressed forward-arrow controls and 2/3 are normal/pressed cancel controls; the four source IDs are shell styles rather than interaction states.
- IDs 50717…50719 each contain two distinct 72×20 frames; IDs 50747…50750 each contain two distinct 108×20 frames. Independent reference code identifies the first family as small top-menu buttons and the second as medium top-menu buttons, with frame 0 normal and frame 1 held/pressed. Runtime uses the light-brown 50717/50747 pair at native 72×20 and 108×20 sizes; exact original crops remain required for final `PARITY`.
- ID 50721 contains 15 distinct glyph frames at 50×50, 50×51 and 3×3. Both openage metadata and the independent reference identify it as the in-game task/command glyph sheet; the reference maps frame 2 to the worker build-menu action. Other frame semantics remain capture-gated.
- Runtime therefore uses only the independently confirmed frame 2 for the worker build root. The visually suggestive repair, stance, formation, delete and arrow glyphs remain unbound until an original executable interaction identifies them; ordinary unit, building and technology icons continue to come from their source icon sheets.
- ID 50745 contains 26 distinct 50×7 frames forming a green-to-red progression. Independent reference identifiers and HUD code confirm it as the unit health strip and the 0…25 missing-health mapping. Runtime now uses it only in the selection card; compact world-space health bars remain a separate presentation.
- IDs 50733…50744 are the four two-frame HUD shell variants at 640, 800 and 1024 pixels. Their context/civilization mapping is still unknown.

Every exported frame records a SHA-256 digest in `assets.json`, so equality and later capture matching do not depend on timestamps or image viewers.

## Required capture procedure

1. Start the pinned `EMPIRESX.EXE` build at native 640×480, 800×600 and 1024×768, without an HD interface replacement.
2. Record the selected civilization, selected object, available command set, population display mode and exact shell source candidate.
3. For the same control capture pointer outside, pointer over, mouse held, release and a genuinely disabled state. Repeat the sequence twice.
4. Preserve full-frame screenshots and lossless crops. Record each artifact path and SHA-256 in the gate manifest.
5. Match crop pixels against imported frame hashes. If a state is composited from backplate, glyph, icon and tint, record every layer; do not force a one-frame mapping.
6. Measure command, selection, minimap rectangles and text baselines at every native resolution.
7. Change the gate to `measured` only when all scenes validate and every remaining delta is an explicit approved modern difference.

## Current E2 priority and boundary

1. Establish exact top strip, bottom strip, world viewport, command area, selection/status area and minimap rectangles for native 640×480, 800×600 and 1024×768.
2. Validate the resulting responsive rules at representative 16:9 and ultrawide sizes without treating those sizes as new source layouts.
3. Verify health numerically (`current/max`) and visually at boundary values before assigning 50745 thresholds.
4. Capture no-selection, unit, multi-selection, building, queue, disabled command and damaged-object states.

The presentation pipeline is `INTEGRATED`, not `PARITY`. If automated Windows capture is unavailable, deterministic implementation work based on already measured source frame geometry continues; only claims about original state semantics remain capture-gated. User-provided lossless RoR captures are valid evidence when their resolution, state and provenance are recorded. `FolkertVanVerseveld/aoe` may be consulted as a secondary implementation/resource-layout reference, but it is neither the runtime dependency nor authority for executable behavior, palette semantics or gameplay rules.

## Secondary-reference result, 2026-09-15

The public `FolkertVanVerseveld/aoe` source was inspected locally as a read-only reference. Its DRS inventory names 50721 as unit command buttons, 50725…50728 as four styled command-arrow families, 50745 as unit health progress, 50717 as the small menu button family and 50747 as the medium family. Its HUD code independently uses 50745 at selection offset `(+10,+91)`, draws the numeric HP at `(+10,+102)`, uses task glyph frame 2 to enter the worker build menu, and switches menu-button frame 0 to frame 1 while held.

These agreements are sufficient for `reference_confirmed` runtime use because they match our own decoded dimensions/hashes and the user-provided RoR frames. They do not close the executable measurement gate: final pixel crops, disabled/hover composition and all remaining task-glyph meanings still require observations of the pinned RoR build.
