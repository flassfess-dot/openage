extends SceneTree
const Renderer := preload("res://scripts/render_world.gd")
var failures: Array[String] = []
var texture: Texture2D
func project(point: Vector2) -> Vector2:
	return Vector2((point.x-point.y)*32.0, (point.x+point.y)*16.0)
func info(kind: String, _entity: Dictionary) -> Dictionary:
	if kind == "building":
		return {"texture": texture, "hotspot": Vector2(4, 8), "gate_occluders": [{"start": Vector2(-1, -1), "end": Vector2(1, 1), "depth": Vector2(0, 0)}]}
	return {"texture": texture, "frame_index": 1, "hotspot": Vector2(4, 8), "graphic_layer": 20, "composite_parts": [{"texture": texture, "frame_index": 2, "hotspot": Vector2(5, 7), "graphic_layer": 21}]}
func _initialize() -> void:
	texture = ImageTexture.create_from_image(Image.create(12, 16, false, Image.FORMAT_RGBA8))
	var fast := Renderer.new()
	var reference := Renderer.new()
	reference.native_render_kernel = null
	var actors: Array = []
	for id in range(1, 10):
		actors.append({"id": id, "kind": "clubman", "pos": Vector2(4.3 + id * 0.17, 5.7), "previous_pos": Vector2(4.1 + id * 0.17, 5.6), "team": 1 + id % 3, "hp": 0.0 if id >= 7 else 100.0, "death_phase": "dying" if id == 7 else "corpse" if id == 8 else "removed" if id == 9 else "alive", "selected": id == 4, "elevation": float(id % 2)})
	var scene := {"units": actors, "buildings": [{"id": 100, "kind": "gate", "pos": Vector2(5, 5), "hp": 600.0}]}
	for alpha in [0.0, 0.17, 0.33, 0.57, 0.9, 1.0, 1.5, 3.0, 5.0]:
		var actual := fast.create_world_drawables(scene, project, alpha, info, [3, 8], 1, [1, 2, 7, 8])
		var expected := reference.create_world_drawables(scene, project, alpha, info, [3, 8], 1, [1, 2, 7, 8])
		if actual != expected:
			failures.append("Native actor items differ at interpolation %s" % alpha)
			if alpha == 0.0:
				print("COUNTS ", actual.size(), " ", expected.size())
				for n in range(mini(actual.size(), expected.size())):
					if actual[n] == expected[n]: continue
					for key in actual[n]:
						if actual[n].get(key) != expected[n].get(key): print("DIFF ", n, " ", key, " actual=", actual[n].get(key), " expected=", expected[n].get(key))
					break
		if alpha > 1.0:
			var predicted: Array = actual.filter(func(item): return String(item.get("kind", "")) == "unit" and int(item.get("stable_id", -1)) == 1)
			var source: Dictionary = actors[0]
			var predicted_position: Vector2 = Vector2(source["previous_pos"]).lerp(Vector2(source["pos"]), alpha)
			if predicted.is_empty() or not Vector2(predicted[0].get("world_anchor", Vector2.INF)).is_equal_approx(predicted_position):
				failures.append("Owner presentation does not extrapolate at interpolation %s" % alpha)
	var refreshed := fast.create_world_drawables(scene, project, 1.0, info, [3, 8], 1, [1, 2, 7, 8])
	refreshed = fast.refresh_world_drawables(refreshed, project, 3.0)
	var refreshed_unit: Array = refreshed.filter(func(item): return String(item.get("kind", "")) == "unit" and int(item.get("stable_id", -1)) == 1)
	var refreshed_source: Dictionary = actors[0]
	var refreshed_position: Vector2 = Vector2(refreshed_source["previous_pos"]).lerp(Vector2(refreshed_source["pos"]), 3.0)
	if refreshed_unit.is_empty() or not Vector2(refreshed_unit[0].get("world_anchor", Vector2.INF)).is_equal_approx(refreshed_position):
		failures.append("Retained native drawables do not extrapolate while the owner is pending")
	for failure in failures: push_error(failure)
	print("Native unit render items: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
