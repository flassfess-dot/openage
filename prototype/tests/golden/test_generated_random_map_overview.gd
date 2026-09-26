extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

const SCALE := 3
const GAP := 8
const PANEL := 72 * SCALE


func _initialize() -> void:
	var profiles: Array = SkirmishSettings.catalog().get("map_types", [])
	var image := Image.create(PANEL * 3 + GAP * 4, PANEL * 3 + GAP * 4, false, Image.FORMAT_RGB8)
	image.fill(Color(0.08, 0.07, 0.06))
	for profile_index in range(profiles.size()):
		var settings := SkirmishSettings.default_settings()
		settings["map_type_id"] = String(profiles[profile_index].get("id", ""))
		settings["seed"] = 41721
		for slot in range(8):
			settings["players"][slot]["enabled"] = slot < 4
		var built := SkirmishSettings.build(settings)
		if not bool(built.get("valid", false)):
			push_error("%s overview map invalid: %s" % [settings["map_type_id"], built.get("errors", [])])
			quit(1)
			return
		var map_data: Dictionary = built["map_data"]
		var size: Vector2i = map_data["size"]
		var left := GAP + (profile_index % 3) * (PANEL + GAP)
		var top := GAP + int(profile_index / 3) * (PANEL + GAP)
		var terrain_ids: Array = map_data["terrain_ids"]
		for y in range(size.y):
			for x in range(size.x):
				_fill_cell(image, left, top, Vector2i(x, y), _terrain_color(int(terrain_ids[y * size.x + x])))
		for cliff_value in map_data.get("cliff_cells", []):
			_fill_cell(image, left, top, Vector2i(cliff_value), Color(0.5, 0.27, 0.16))
		for resource_value in map_data.get("resources", []):
			var resource: Dictionary = resource_value
			var kind := String(resource.get("kind", ""))
			var color := Color(0.12, 0.32, 0.1)
			if kind == "berries": color = Color(0.8, 0.1, 0.32)
			elif kind == "gold_mine": color = Color(1.0, 0.83, 0.05)
			elif kind == "stone_mine": color = Color(0.72, 0.72, 0.74)
			elif kind == "deep_fish": color = Color(0.2, 0.78, 1.0)
			elif String(resource.get("category", "")) == "unit": color = Color(0.94, 0.45, 0.16)
			_fill_cell(image, left, top, Vector2i(Vector2(resource.get("position", Vector2.ZERO))), color)
		for player_value in built["definition"].get("players", []):
			var start := Vector2i(Vector2(player_value.get("start", Vector2.ZERO)))
			for offset_y in range(-1, 2):
				for offset_x in range(-1, 2):
					_fill_cell(image, left, top, start + Vector2i(offset_x, offset_y), Color(0.98, 0.1, 0.95))
	var output := "res://qa/golden/random-map-profiles-4p.png"
	var error := image.save_png(output)
	if error != OK:
		push_error("Failed to save random-map overview: %d" % error)
		quit(1)
		return
	print("RoR random-map overview saved: %s (profiles in catalog order)" % ProjectSettings.globalize_path(output))
	quit(0)


func _fill_cell(image: Image, left: int, top: int, cell: Vector2i, color: Color) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= 72 or cell.y >= 72:
		return
	for offset_y in range(SCALE):
		for offset_x in range(SCALE):
			image.set_pixel(left + cell.x * SCALE + offset_x, top + cell.y * SCALE + offset_y, color)


func _terrain_color(terrain_id: int) -> Color:
	if terrain_id in TerrainRules.WATER_TERRAIN_IDS:
		return Color(0.08, 0.23, 0.55) if terrain_id != 22 else Color(0.04, 0.12, 0.37)
	if terrain_id == 2:
		return Color(0.81, 0.72, 0.45)
	if terrain_id in TerrainRules.SOURCE_FOREST_TERRAIN_IDS:
		return Color(0.1, 0.28, 0.09)
	if terrain_id == 6:
		return Color(0.66, 0.55, 0.3)
	return Color(0.4, 0.57, 0.24)
