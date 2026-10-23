# Shallows river strip pilot — 2026-10-21

## Current v4: closer rendering style to native RoR terrain

`shallows_strip_v4_ground.png` restyles the v3 ground layer using original RoR
Shallows frames 3 and 6, `terrain_water_00.png` and `terrain_sand_00.png` as
visual references. The revised sand has less orange saturation and slab-like
shading; the water fringe has fewer bright blue accents. Small exposed patches,
narrow channels and 15 upright native sedge clumps are retained. The exact
ImageGen prompt and source references are saved in `v4-prompt.md`.

The revision was rendered in the same Godot scene at three scales:

- `res://qa/river-shape-fix-20261020/generated-strip-v4-native-reeds-100pct.png` — 100%.
- `res://qa/river-shape-fix-20261020/generated-strip-v4-native-reeds.png` — 180%.
- `res://qa/river-shape-fix-20261020/generated-strip-v4-native-reeds-detail.png` — 300%, 1000×500 close-up.

Reproduce with `capture_generated_strip.gd` and these user arguments:

```text
--asset=res://assets/pilots/river_shallows_20261021/shallows_strip_v4_ground.png
--output=generated-strip-v4-native-reeds
--native-reeds
--reed-count=15
--detail
```

All three captures completed without script errors. This is an engine-rendered
art pilot; ordinary generated matches still use their existing artwork. All
previous images and original game assets are preserved.

## Previous v3: small sandy shelves, narrow runnels and denser sedge

`shallows_strip_v3_ground.png` is an ImageGen edit of the approved v2 ground
layer. Larger sandy slabs are divided into a closer mesh of smaller dry patches
and many narrow shallow-water veins. The engine pilot adds 15 green native
RoR sedge clumps, compared with five in v2. Exact provenance, prompt and plant
anchor details are saved in `v3-prompt.md`. All earlier files are preserved.

Actual engine captures on the same ford:

- `res://qa/river-shape-fix-20261020/generated-strip-v3-native-reeds.png` — 180%.
- `res://qa/river-shape-fix-20261020/generated-strip-v3-native-reeds-100pct.png` — 100%.

Reproduce with `capture_generated_strip.gd` and these user arguments:

```text
--asset=res://assets/pilots/river_shallows_20261021/shallows_strip_v3_ground.png
--output=generated-strip-v3-native-reeds
--native-reeds
--reed-count=15
```

The ground is a generated bitmap; the upright sedge is original RoR artwork
selected with a runtime shader. Both are rendered in Godot below actors and
trees. The pilot completed at 100% and 180% without script errors. It remains
separate from ordinary generated matches.

## Previous v2: native vegetation and water veins

The v2 edit adds branching blue runnels and small ripples, following original
RoR SLP 596 frames 0 and 5. `shallows_strip_v2.png` is the complete image edit.
For the engine pilot, `shallows_strip_v2_ground.png` supplies the flat bed and
five upright vegetation sprites use the original frames 0 and 5. This keeps
their source proportions, orientation and hotspots when the bed is rotated
to another river cross-section. Vegetation is not baked into the ground mesh.

Both edits used the built-in ImageGen tool. Exact prompts and source references
are in `v2-prompt.md` and `v2-ground-prompt.md`. The v1 file is preserved.

Actual engine captures:

- `res://qa/river-shape-fix-20261020/generated-strip-v2-native-reeds.png` — 180%.
- `res://qa/river-shape-fix-20261020/generated-strip-v2-native-reeds-100pct.png` — 100%.

Reproduce with `capture_generated_strip.gd` and these user arguments:

```text
--asset=res://assets/pilots/river_shallows_20261021/shallows_strip_v2_ground.png
--output=generated-strip-v2-native-reeds
--native-reeds
```

The screenshots were rendered in Godot on the same saved 96×96 river fixture;
they are not generated full-scene mockups. The preview log contains the five
chosen vegetation anchors and both captures completed without script errors.
This remains a static art pilot and is not enabled in ordinary matches.

## Previous v1

`shallows_strip_v1.png` is an experimental transparent river-ford decal generated
with the built-in ImageGen tool from the imported RoR Shallows frames
`ror_shallows_03.png` and `ror_shallows_06.png` (source SLP 596, graphic 503).
It is a new derived image, rather than an unmodified original-game asset.

This pilot is not enabled in ordinary generated matches. No source assets were
overwritten. The discarded procedural sand ribbons and dense sprite overlays
are not connected to the game either.

The actual engine render is saved in
`res://qa/river-shape-fix-20261020/generated-strip-in-map.png`.
Run `res://qa/river-shape-fix-20261020/capture_generated_strip.gd` to reproduce
it using the saved 96×96 map fixture. The script projects the decal's ground
plane onto the real cross-section, clips it to the saved continuous water
contour and renders it below trees and actors. Its geometry does not change
terrain passability. The image is static; no animation was requested or tested.

The pilot still needs visual acceptance and multiple shapes/directions before
generator integration. It has only been inspected on one real ford, and a
single successful frame does not establish suitability for all river bends.

## Exact generation prompt

Edit the provided original Age of Empires Rise of Rome Shallows pixel-art sprites into ONE usable continuous larger river-ford decal, as a faithful extension of those exact native sprites. This is a production game sprite on transparent RGBA, not concept illustration. Preserve the references' exact coarse pixel-art look, sandy tan/gravel clumps, small gray stones, subdued dark-blue water scallops and 2:1 isometric overhead projection. Extend and organically connect the original sandy clumps into a long uneven shallow reef, about FIVE original sprites long and TWO original sprites wide. Its long axis should run diagonally from lower left to upper right at the game's 2:1 isometric angle (roughly -26.6 degrees on screen). It should read as a continuous shallow ford made of worn sand, submerged pebbles and closely linked low sandy shelves, with narrow winding water runnels crossing between shelves. Material proportions: roughly 45 percent connected wet tan/gray bed, 25 percent subtle blue shallow-water fringe, 30 percent transparent water gaps. One unified irregular tapered silhouette, two irregular ends that can overlap a riverbank; gently varying width, uneven organic edges. Keep the sand naturally joined along the length, not separate little dot islands. Keep black outlines extremely restrained like the original single sprite; no accumulated black speckle or dark noise, no black background, no dirty black rectangle. Keep tiny warm sand clusters and gray stones, not giant boulders or vegetation. No grass or plants. No continuous straight road, dam, bridge or paving. No flat beige painted strip. No smooth modern illustration, no photorealism, no lighting halos, no cast shadow. Pixel art at an effective native resolution around 240x100 pixels, nearest-neighbor style clean readable pixels; can be presented enlarged on a larger transparent canvas without adding new microdetail. Center the entire sprite with empty transparent margin; no clipping. No text, borders, labels, other objects or grid. Deliver just ONE coherent ford sprite, not a sheet of variants. All visible water fringe must fade to real transparency rather than an opaque blue rectangular tile. The provided images are the palette and drawing-style authority.
