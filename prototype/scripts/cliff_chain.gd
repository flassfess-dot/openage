class_name RoRCliffChain
extends RefCounted

const LEFT := 1
const UP := 2
const RIGHT := 4
const DOWN := 8
const STRIDE := 3
const NEIGHBORS := {LEFT: Vector2i.LEFT, UP: Vector2i.UP, RIGHT: Vector2i.RIGHT, DOWN: Vector2i.DOWN}
# These are world-space connections under (x-y, x+y) isometric projection.
# RoR's scenario angle numbers use another orientation. Read the actual art:
# frames 1/2 join NW-SE, frames 4/5 join NE-SW. Do not rotate the bitmap.
# The outer corner crest sits five pixels below the adjoining native faces.
# Raise only its drawing anchor; its world position and footprint stay fixed.
const PIECES := {
	0: {"frames": [24], "kind": "isolated"},
	LEFT: {"frames": [19], "kind": "right_end"},
	UP: {"frames": [16], "kind": "left_end"},
	RIGHT: {"frames": [18], "kind": "left_end"},
	DOWN: {"frames": [17], "kind": "right_end"},
	LEFT | RIGHT: {"frames": [1, 2], "kind": "straight"},
	UP | DOWN: {"frames": [4, 5], "kind": "straight"},
	LEFT | UP: {"frames": [3], "kind": "outer_corner", "offset": Vector2(0, -5)},
	RIGHT | DOWN: {"frames": [15], "kind": "inner_corner"},
}


static func connections_at(center: Vector2i, centers: Dictionary) -> int:
	var connections := 0
	for bit in NEIGHBORS:
		if centers.has(center + NEIGHBORS[bit] * STRIDE):
			connections |= int(bit)
	return connections


static func piece(connections: int, variation: int = 0) -> Dictionary:
	# The source sheet has no usable side-corner or T/X frames. A solid isolated
	# rock joins those uncommon shapes instead of selecting a transparent frame.
	var spec: Dictionary = PIECES.get(connections, {"frames": [24], "kind": "junction"})
	var frames: Array = spec["frames"]
	return {"source_frame": int(frames[posmod(variation, frames.size())]), "cliff_piece": String(spec["kind"]), "cliff_connections": connections, "cliff_screen_offset": spec.get("offset", Vector2.ZERO)}


static func apply(scenery: Array, variations: Dictionary = {}) -> void:
	var centers: Dictionary = {}
	for item in scenery:
		centers[Vector2i(Vector2(item["position"]).floor())] = true
	for item in scenery:
		var center := Vector2i(Vector2(item["position"]).floor())
		var connections := connections_at(center, centers)
		item.merge(piece(connections, int(variations.get(center, 0))), true)
		item["cliff_axis"] = Vector2i.RIGHT if connections in [LEFT, RIGHT, LEFT | RIGHT] else Vector2i.DOWN if connections in [UP, DOWN, UP | DOWN] else Vector2i.ZERO
