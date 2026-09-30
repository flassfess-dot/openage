extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var results: Dictionary = {}
	for profile in ["grasslands", "highlands", "hill_country", "islands"]:
		var settings := Settings.default_settings()
		settings["map_type_id"] = profile
		var built := Settings.build(settings)
		check(bool(built.get("valid", false)), "%s is valid: %s" % [profile, built.get("errors", [])])
		if bool(built.get("valid", false)): results[profile] = built["map_data"]
	if results.size() == 4:
		check(results["grasslands"]["terrain_ids"] != results["highlands"]["terrain_ids"], "profile changes vegetation and soils")
		check(results["highlands"]["vertex_levels"].max() >= 2, "highlands have visible multi-level relief")
		check(results["highlands"]["vertex_levels"] != results["hill_country"]["vertex_levels"], "hill country differs from highlands")
		check(results["islands"]["vertex_levels"].max() >= 1, "islands can have hills despite surrounding water")
		var mask: PackedByteArray = results["grasslands"]["forest_mask"]
		check(mask.count(1) > 100, "forest field produces substantial actual woodlands")
	# Irregular coast clearance permits an inland hill even with water in its bounding box.
	var size := Vector2i(36, 36)
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	terrain.fill(1)
	for y in range(36):
		for x in range(36):
			if Vector2(x - 18, y - 18).length() < 14: terrain[y * 36 + x] = 0
	var starts: Array[Vector2] = []
	var fields := Landscape.select_fields(size, terrain, starts, "islands", 41721)
	check(fields["vertex_levels"].max() > 0, "distance-to-coast relief survives an irregular island")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Random map coherent profile features passed")
	quit(0 if failures.is_empty() else 1)

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
