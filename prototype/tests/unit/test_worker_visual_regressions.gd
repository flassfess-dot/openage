extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const Renderer := preload("res://scripts/render_world.gd")
const Item := preload("res://scripts/render_item.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	for team in [1, 2, 3, 8]:
		for facing in range(8):
			var farmer := {"id": 1, "kind": "villager", "team": team, "source_unit_id": 83, "facing": facing, "anim": 0.18}
			var info: Dictionary = catalog.unit_frame_info(farmer, "farmer_carry")
			check(info.get("texture") != null and info["texture"].get_height() >= 30, "food-carrying farmer has a complete body (team %d facing %d)" % [team, facing])
			var parts: Array = info.get("composite_parts", [])
			check(parts.size() == 1, "farmer hat is attached as original composite")
			if parts.is_empty(): continue
			check(parts[0].get("graphic_id") == 829 and parts[0].get("texture") != null, "farmer hat resolves source graphic")
			check(parts[0].get("frame_index") == info.get("frame_index") and parts[0].get("mirrored") == info.get("mirrored"), "body and hat share animation timing and facing")
	var renderer = Renderer.new()
	for worker_y in [9.0, 11.0]:
		var corpse := {"id": 10, "kind": "gazelle_carcass", "behavior_tags": ["resource", "carcass"], "pos": Vector2(10, 10), "amount": 50, "hp": 0}
		var worker := {"id": 11, "kind": "villager", "team": 1, "pos": Vector2(10, worker_y), "hp": 25}
		var drawables: Array = renderer.create_world_drawables({"resources": [corpse], "units": [worker]}, func(point): return Vector2(point.x - point.y, point.x + point.y), 1, func(_kind, _entity): return {})
		var corpse_index := -1
		var worker_index := -1
		for index in range(drawables.size()):
			if drawables[index]["kind"] == "resource": corpse_index = index
			if drawables[index]["kind"] == "unit": worker_index = index
		check(corpse_index >= 0 and corpse_index < worker_index, "carcass stays beneath worker approaching from either side")
	check(Renderer.resource_layer({"tree_phase": "felled"}) == Item.Layer.DECAL, "felled trunks render on the ground")
	check(Renderer.resource_layer({"tree_phase": "standing"}) == Item.Layer.UNIT_BUILDING, "standing trees retain ordinary depth sorting")
	for failure in failures: push_error(failure)
	print("Farmer composite and corpse layering: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
