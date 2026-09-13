extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var matrix := read_json("res://data/content_waves/stone_age.json")
	var catalog = ResourceCatalog.new()
	catalog.load()
	var runtime: Dictionary = catalog.runtime_catalog_data.get("archetypes", {})
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)

	assert_equal(matrix.get("schema_version"), 1, "content matrix schema is explicit")
	assert_true(not matrix.get("allowed_differences", []).is_empty(), "modern formation/navigation differences are documented")
	for entry_value in matrix.get("entries", []):
		var entry: Dictionary = entry_value
		var alias := String(entry.get("alias", ""))
		var archetype: Dictionary = runtime.get(alias, {})
		assert_true(not archetype.is_empty(), "%s reaches runtime catalog" % alias)
		assert_equal(int(archetype.get("identifiers", {}).get("source_unit_id", -1)), int(entry.get("source_unit_id", -2)), "%s source ID matches matrix" % alias)
		assert_equal(String(archetype.get("category", "")), String(entry.get("category", "")), "%s category matches matrix" % alias)
		assert_true(not entry.get("systems", []).is_empty(), "%s names simulation consumers" % alias)
		assert_true(not entry.get("commands", []).is_empty(), "%s names user/AI commands" % alias)
		assert_equal(entry.get("status"), "integrated", "%s has explicit evidence level" % alias)
		for test_path in entry.get("tests", []):
			assert_true(FileAccess.file_exists(String(test_path)), "%s evidence exists: %s" % [alias, test_path])
		verify_presentation(alias, entry.get("presentation", {}), catalog, world)
	assert_true(matrix.get("known_gaps", []).is_empty(), "completed Stone Age slice has no hidden content gaps")

	if failures.is_empty():
		print("I12-001 Stone Age content coverage matrix tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_presentation(alias: String, presentation: Dictionary, catalog, world) -> void:
	match String(presentation.get("mode", "")):
		"unit":
			assert_true(catalog.has_unit_presentation(alias), "%s owns a unit presentation" % alias)
			for state in presentation.get("states", []):
				var frames: Array = catalog.unit_animation_frames(alias, String(state))
				assert_true(not frames.is_empty() and frames.all(func(frame): return frame != null), "%s.%s frames are loadable" % [alias, state])
		"building":
			var building: Dictionary = world.create_building(1, alias, Vector2(16, 16), true)
			var frame: Dictionary = catalog.building_frame_info(building, 0.0)
			var has_base: bool = frame.get("texture") != null
			var composite_parts: Array = frame.get("composite_parts", [])
			var has_composite: bool = not composite_parts.is_empty()
			assert_true(not frame.is_empty() and (has_base or has_composite), "%s resolves data-driven building presentation" % alias)
		"asset":
			for asset_name in presentation.get("assets", []):
				assert_true(catalog.asset_records.any(func(record): return String(record.get("name", "")) == String(asset_name)), "%s asset %s is imported" % [alias, asset_name])
		"resource":
			for asset_name in presentation.get("assets", []):
				assert_true(catalog.asset_records.any(func(record): return String(record.get("name", "")) == String(asset_name)), "%s asset %s is imported" % [alias, asset_name])
			var resource: Dictionary = world.add_resource(alias, Vector2(8.0 + world.get_resources().size(), 8.0), 1)
			var resource_frame: Dictionary = catalog.resource_frame_info(resource)
			assert_true(resource_frame.get("texture") != null, "%s resolves resource presentation through registry" % alias)
		"projectile":
			var source_id := int(catalog.runtime_catalog_data.get("archetypes", {}).get(alias, {}).get("identifiers", {}).get("source_unit_id", -1))
			var frames: Array = catalog.projectile_animation_frames(source_id)
			assert_true(not frames.is_empty() and frames.all(func(frame): return frame != null), "%s projectile frames are loadable" % alias)
		_:
			failures.append("%s: unknown presentation evidence mode" % alias)


func read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	failures.append("cannot parse %s" % path)
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
