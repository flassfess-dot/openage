# Visual parity contract

Status: architecture `INTEGRATED`, visible acceptance `REOPENED` by the 2026-09-14 user capture. Source-asset correctness is machine checked, but HUD geometry, health presentation, fog/elevation compositing and the lower-right map edge are current E1/E2 blockers. A packaged build without errors or one 1280×720 golden is not visual acceptance.

This contract owns palette decoding, sprite alpha, terrain/fog boundaries and the evidence required before world or UI presentation can be called `PARITY`. It does not move game rules into the renderer.

## 1. Source and ownership

- `tools/ror_import/import_assets.js` is the only owner of SLP command decoding and palette selection.
- `prototype/assets/generated/assets.json` records semantic pixel counts for every exported frame.
- Runtime presentation may choose a frame, player palette and composite layer, but must not reinterpret SLP pixel commands.
- The authoritative simulation owns visibility state. `RoRFogPresentation` only maps that state to pixels.
- `RoRHudViewModel` owns read-only UI meaning. Layout and skins consume its model and never duplicate command availability or costs.

## 2. AoE1 player-colour invariant

The [openage SLP format documentation](https://github.com/SFTtech/openage/blob/master/doc/media/slp-files.md) records that the AoE1 player-colour command carries ten shade values `0x00..0x09`. The final palette index is:

    16 * player_number + shade

Masking the shade with `7` is invalid for AoE1: it aliases shades 8 and 9 to the two brightest entries and produces conspicuous bright fragments on clothing, roofs, pots and other colourable details.

For the AoE1 SLP format, the frame-header `palette_offset` field is unused. Normal ingame graphics therefore use source palette `50500`, unless an asset selection explicitly names another source-backed palette. Loading-screen and interface assets that require another palette must declare it in the catalog; their frame-header padding must not silently select one.

The following conditions are mandatory for every representative player-one/player-two frame pair:

1. dimensions are identical;
2. alpha masks are identical;
3. changed source-visible pixels equal `semanticPixels.player_color + semanticPixels.outline` (Godot may fill RGB in fully transparent border texels during lossless import; alpha zero keeps those bytes non-visible);
4. dark shade entries remain present where they occur in the source;
5. shadow, transparency and ordinary palette pixels do not change with player number.

Machine evidence: `prototype/tests/unit/test_player_palette_pixels.gd` and the importer SLP self-test.

## 3. Alpha and composite invariant

- Transparent SLP commands remain alpha zero.
- Player colour, shadow, outline and anti-outline retain distinct semantic accounting through import.
- A mutually exclusive base/delta/composite choice is made before drawing. The same source part may not be drawn twice.
- Hotspot and mirror transforms are applied once around the source anchor.
- Nearest filtering and integer screen snapping are required for source-resolution sprites.
- Texture-edge fixes must preserve visible source pixels; padding or atlasing may duplicate transparent/border texels but may not repaint the frame.

Complete parity requires fixed-scene comparisons for buildings, villagers, military units, ships, projectiles, construction, damage and death in at least two player colours.

## 4. Fog and map-edge invariant

Fog has three simulation states:

- `UNKNOWN`: pure opaque black in the world and minimap; unseen terrain and entities cannot leak through it;
- `EXPLORED`: remembered terrain may be shown through a stable translucent overlay, while non-persistent hidden entities remain absent from the presentation snapshot;
- `VISIBLE`: no fog overlay.

World fog geometry must conform to each terrain cell and to the actual source slope footprint, use the same elevation vertices and pixel policy as terrain, and participate in a compatible isometric depth order. A merged multi-cell row contour is not a parity primitive: retaining intermediate vertices does not guarantee a simple triangulable polygon and can produce long dark wedges around hills. The current row-run renderer is therefore an `INTEGRATED` fallback only.

Presentation batching must cover each non-visible cell exactly once, never cover a visible cell and never change visibility state. E1 first establishes correct individual-cell geometry, slope footprint, depth order and map-edge composition. E6 then replaces full scans/copies with revisioned deltas, a shared world/minimap presentation cache, retained visible chunks and nearest-sampled compact state masks. No-op visibility and camera movement must not scan or rebuild the full fog map in the E6 release path. Map-edge background is a separate layer and may not substitute for unknown fog. See `ELEVATION_AWARE_FOG_OPTIMIZATION_PLAN.md`.

Machine evidence: `prototype/tests/unit/test_viewport_culling.gd`, `prototype/tests/unit/test_fog_of_war.gd` and `prototype/tests/unit/test_simulation_snapshot.gd`.

## 5. UI parity gate

The next visual vertical is a data-driven RoR HUD skin, not a rewrite of game rules. Before implementation, every available `INTERFAC.DRS` asset is classified as one of:

- scalable panel/tile fragment;
- fixed-resolution background or loading image;
- command, technology or object icon sheet;
- progress/status strip;
- cursor, button state or decoration;
- source asset requiring an explicit non-default palette;
- unused/unknown pending evidence.

The runtime layout contract must define source-backed anchors and rectangles for the resource/age strip, world viewport, command grid, selected-object panel, status/queue area and minimap for the native 640×480, 800×600 and 1024×768 HUD families. Modern and wide windows select the appropriate family/scale, extend the world viewport and repeat only approved neutral panel regions; they do not anchor controls to a 1280×720 mock-up or stretch source pixels arbitrarily.

Acceptance evidence is a deterministic capture matrix at the three native source resolutions plus representative modern 16:9 and ultrawide windows:

1. a representative RoR source screenshot with provenance and crop recorded;
2. the same gameplay/UI state in the project;
3. a visual-difference report separating intentional modern formation controls from defects.

The formation controls are part of the single normal UI. They should reuse the command area and source visual language; they do not justify a separate extended-mode HUD.

Current architectural evidence (phase 2B-9b1): all three installed interface archives are inventoried without flattening duplicate IDs; runtime assets carry an exact archive path and explicit palette. Source HUD family 50733…50744 provides native 20px top and 126px bottom frames at 640/800/1024. The intended composition rule remains valid, but the 2026-09-14 capture demonstrates that current runtime anchors, resolution handling and control placement do not yet satisfy it. The first source variant is a temporary integrated default; mapping the four variants to original executable contexts and source button-state order remains required before `PARITY`.

Phase 2B-9b2 machine evidence corrects the earlier four-frame assumption. Each 50713…50716 SLP contains four byte-identical decoded 54×54 frames, so those indices cannot be mapped bijectively to normal/hover/pressed/disabled. Each 50725…50728 SLP has four distinct decoded 54×31 frames, but their roles and composition remain executable-observation work. Source 50745 has 26 distinct 50×7 green-to-red frames and may be used only as a presentation candidate until its exact role and threshold mapping are measured; the HUD must always display authoritative `current/max` health and must not imply a false value. `source_ui_executable_gate.json` pins the executable, DAT and interface archive hashes and keeps all semantics, shell-context mapping and rectangle/text calibration pending. See `SOURCE_UI_EXECUTABLE_MEASUREMENT.md`.

## 6. Import and performance hygiene

- Import is incremental and content-addressed: unchanged source hash, decoder/importer version, schema, palette and extraction parameters reuse the existing artifact, and byte-identical outputs are not rewritten.
- Missing or changed resources append/replace only affected manifest entries and their direct derivatives. A full clean repack is allowed only after an incompatible schema, SLP decoder, palette/alpha semantic change or an explicit clean-rebuild request.
- The current one-file-per-frame layout is accepted for functional parity but is an explicit E6 import/startup debt.
- E6 benchmarks source-frame atlases or packed frame pages, bounded parallel import and grouped render buckets. Any packing scheme must preserve per-frame hotspot, direction, mirror, semantic player colour, animation timing and isometric sort key.
- Fog authoritative state uses compact byte storage. E6 removes ordinary full-map snapshot copies, unconditional revision changes and per-frame row-polygon submission through deterministic deltas and bounded retained chunks; exact gates are defined in `ELEVATION_AWARE_FOG_OPTIMIZATION_PLAN.md`.

## 7. Status boundary

Architecture is `INTEGRATED` when machine invariants pass and a packaged build renders without errors. Visible acceptance is independent: it becomes `PARITY` only after source-backed side-by-side captures cover the full resolution/state matrix and every unexplained difference has either been fixed or recorded as an approved modern difference. The current visible status remains `REOPENED` until the recorded HUD, health, fog/elevation and lower-right map-edge defects are closed.
