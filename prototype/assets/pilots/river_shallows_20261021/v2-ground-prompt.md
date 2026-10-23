# v2 ground layer

Built-in ImageGen edit of `shallows_strip_v2.png` into
`shallows_strip_v2_ground.png`. The engine pilot uses this as the flat decal
and draws five original RoR vegetation sprites from SLP 596 frames 0 and 5
above it. Their blue water pixels are excluded with a canvas shader; the
original files and their plant pixels are not repainted. Native hotspots
and upright screen axes are preserved when the river cross-section rotates.

## Exact prompt

Use case: precise-object-edit. The input is the approved v2 Shallows pixel-art sprite, which already has the desired thin blue water runnels. Make ONLY this technical layer-separation edit: remove all upright grass and reed tufts from the sprite, seamlessly restoring the underlying tiny patch of sand or water at each removed tuft. Remove their stems and any vegetation shadows too. This will be the GROUND LAYER; the game renderer will add the original RoR grass sprites as a separate upright layer.

Keep every other feature unchanged: exact same canvas dimensions, same sprite position and 2:1 isometric projection, same diagonal, silhouette, sand shelves, pebbles, all of the newly added thin branching water veins, ripples, blue water fringe, coarse pixel-art drawing style, colours, texture and alpha transparency. Do not simplify, enlarge or reroute the blue water veins. Do not remove stones. No new objects, no text, no background. Preserve genuine transparent RGBA in all currently transparent areas. Do not invent another art variant; produce the matching vegetation-free ground plate for this exact sprite.
