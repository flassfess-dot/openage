# I12-020L — Source UI executable measurement

## Purpose

This protocol prevents imported `Interfac.drs` frames from being assigned to `normal`, `hover`, `pressed`, `disabled`, health, progress or civilization styles by filename folklore or visual guesswork. The reference is the installed Rise of Rome 1.1 executable pinned in `prototype/data/parity/source_ui_executable_gate.json`.

The runtime may expose unresolved frames as candidates. It may not attach semantic interaction states until the gate contains immutable original captures and measured mappings. Simulation legality remains owned by the command pipeline; this protocol changes presentation only.

## Machine-established facts

- `data/Interfac.drs` SHA-256 is `8a7f1b1f9009d4bc0262c7890935d69d62668c80751ec3b861345064a0e63d33`; in-game palette is explicitly `50500`.
- IDs 50713…50716 each contain four 54×54 frames. Within each individual SLP all four decoded PNG hashes are identical. Therefore frame index cannot encode four distinct button states.
- IDs 50725…50728 each contain four 54×31 frames. All four decoded hashes within each SLP are distinct, but this alone does not establish their control role or state meaning.
- ID 50745 contains 26 distinct 50×7 frames forming a green-to-red progression. It is provisionally used by the presentation layer for remaining health, with the old drawn bar retained as a missing-asset fallback. Exact executable role and threshold mapping remain capture-gated.
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

## Current boundary

The stage is `INTEGRATED`, not `PARITY`. Automated Windows capture is currently unavailable because the Computer Use helper exits with `trusted Node process exited unexpectedly`; no inferred replacement observation is accepted.
