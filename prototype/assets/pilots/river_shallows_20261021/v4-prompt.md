# Shallows v4 style revision — 2026-10-21

Created with the built-in ImageGen tool. Edit target:
`shallows_strip_v3_ground.png`; output: `shallows_strip_v4_ground.png`.
Previous variants are preserved. Original reference images:

- RoR SLP 596 frames 3 and 6, imported as `ror_shallows_03.png` and `ror_shallows_06.png`.
- `res://assets/generated/terrain_water_00.png`.
- `res://assets/generated/terrain_sand_00.png`.

The engine pilot retains the 15 native green sedge clumps from SLP 596 frame 0
as a separate upright layer. The map fixture, ford geometry and vegetation
count match v3. Only the ground sprite is restyled. It is not yet enabled in
ordinary generated matches.

## Exact prompt

Use case: style-transfer / precise-object-edit.
Image 1 is the EDIT TARGET, the current v3 Shallows ground strip. Images 2 and 3 are ORIGINAL Rise of Rome Shallows sprites. Image 4 is the actual ORIGINAL GAME WATER TILE. Image 5 is the actual ORIGINAL GAME SAND TILE. Images 2–5, not image 1's current bright colours, are the authority for the finished rendering style.

Restyle only the surface rendering of image 1 so it blends with the original Age of Empires 1 / Rise of Rome terrain. Preserve its overall long silhouette, exact canvas size and position, lower-left to upper-right diagonal, 2:1 isometric projection, approximate patch layout, numerous SMALL low sandy land patches and network of NARROW winding shallow water channels. The user likes these features and the dense sedge layer; this file remains the GROUND layer, with the original sedge added separately upright in the engine. Do not bake plants into this file.

The specific problem to fix: image 1 currently looks like brightly outlined miniature orange slabs with cobalt/cyan borders and toy-like bevelled pebbles; its busy painted blue water does not match the quieter game water. Replace that treatment with the modest, flat, finely mottled low-resolution ground rendering of references 2–5.

SAND AND GRAVEL: match the subdued dusty beige, grey-brown wet sand and fine irregular pixel texture of the native sand and Shallows references. Reduce the orange/yellow saturation and bright cream highlights. The sand patches lie almost flush with the riverbed; remove raised slab sides, bevels, dark rims and the impression of cookies or stepping stones. Use restrained local shading, sparse tiny grey-brown pebbles and quiet fine grain at the ORIGINAL game's pixel scale. No large individually modelled boulders or shiny stones. Preserve enough exposed sand to read as dense interlaced shallows.

WATER AND EDGES: match the dark muted blue of reference 4, with only occasional tiny native-style dark wave dashes and restrained mid-blue marks as seen in references 2 and 3. Remove the bright electric-blue/cyan rings around every island, the thick blue outline around the entire strip, pale foam highlights and dense decorative ripple noise. Water veins are mostly TRANSPARENT negative-space channels that reveal the game water underneath, with a few thin low-opacity muted blue-grey submerged-bed transitions along selected wet edges. Keep many narrow channels readable by their silhouettes, not by glowing outlines. The outer water fringe should be thin and fade to genuine transparency, so there is no visible sticker border or opaque water patch when composited on the actual water tile.

Keep a restrained 1990s RoR sprite aesthetic, nearest-neighbour-scale pixel clusters and a small native-looking palette. Do not convert to cartoon tile art, polished modern pixel art, painterly illustration, photorealism or high-resolution microdetail. Do not regularize the organic patches into a grid. Do not replace the original design with one smooth road, bridge, dam or a few scattered isolated dots. No text, grid, frame, background, grass, reeds, trees, cast shadows or halos. Deliver ONE revised transparent RGBA ground sprite, suitable for direct compositing over the actual original game water.
