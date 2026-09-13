extends SceneTree

const DataRepository := preload("res://scripts/ror_data_repository.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_identifier_domains_and_civilization_resolution()
	test_economic_relationships_are_normalized()
	test_data_only_scout_archetype_enters_simulation()

	if failures.is_empty():
		print("I2 normalized runtime data tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_identifier_domains_and_civilization_resolution() -> void:
	var repository: Variant = configured_repository()
	assert_true(repository.has_archetype("villager"), "villager archetype exists")
	var identifiers: Dictionary = repository.identifiers("villager")
	assert_equal(identifiers.get("internal_id"), "ror.unit.villager", "stable internal ID")
	assert_equal(identifiers.get("source_unit_id"), 83, "original logical Villager source ID")
	assert_equal(identifiers.get("presentation_id"), "unit.villager", "presentation ID")
	var roman_record: Dictionary = repository.normalized_record("villager", 13)
	assert_equal(roman_record.get("source_key"), "13:83", "team civilization record")
	assert_equal(roman_record.get("presentation", {}).get("fallback_name"), "Villager", "localized fallback comes from catalog")
	var tree_record: Dictionary = repository.normalized_record("tree", 13)
	assert_equal(tree_record.get("source_key"), "0:144", "Gaia archetype ignores team civilization")
	assert_equal(repository.runtime_metadata("tree").get("resource_type_id"), 1, "resource strategy comes from manifest")


func test_data_only_scout_archetype_enters_simulation() -> void:
	var world := SimulationWorld.new(Vector2i(12, 12))
	world.set_gamespec(read_json("res://assets/generated/gamespec-prototype.json"))
	world.set_object_catalog(read_json("res://assets/generated/objects-catalog.json"))
	world.set_runtime_catalog(read_json("res://assets/generated/runtime-catalog.json"))
	world.set_team_civilization(1, 13)
	var scout: Dictionary = world.add_unit(1, "scout", Vector2(4.0, 4.0), false)
	assert_equal(scout.get("source_unit_id"), 299, "new type resolves original Scout object record")
	assert_equal(scout.get("internal_id"), "ror.unit.scout", "new type receives internal identity")
	assert_equal(scout.get("presentation_id"), "unit.scout", "new type receives presentation identity")
	assert_true("scout" in scout.get("behavior_tags", []), "new type receives data-driven behavior tag")
	assert_true(float(scout.get("speed", 0.0)) > 0.0, "new type receives normalized movement stats")
	assert_true(float(scout.get("max_hp", 0.0)) > 0.0, "new type receives normalized health")
	assert_true(scout.get("components", {}).get("identity", {}).get("internal_id") == "ror.unit.scout", "component identity is synchronized")


func test_economic_relationships_are_normalized() -> void:
	var repository: Variant = configured_repository()
	assert_equal(repository.category("barracks"), "building", "Barracks is a building archetype")
	assert_equal(repository.train_location_unit_id("clubman", 13), 12, "Clubman train location comes from source relationship")
	assert_equal(repository.train_location_unit_id("villager", 13), 109, "Villager production uses explicit base-unit runtime relationship")
	assert_equal(repository.completion_technology_id("barracks", 13), 62, "Barracks completion technology is normalized")
	var accepted_resource_ids: Array = repository.runtime_metadata("granary").get("accepted_resource_type_ids", [])
	assert_equal(accepted_resource_ids.size(), 1, "Granary has one accepted resource class")
	assert_equal(int(accepted_resource_ids[0]), 0, "drop-site policy remains data-driven")


func configured_repository():
	var repository: Variant = DataRepository.new()
	repository.configure_runtime(read_json("res://assets/generated/runtime-catalog.json"))
	repository.configure_objects(read_json("res://assets/generated/objects-catalog.json"))
	repository.configure_compatibility_gamespec(read_json("res://assets/generated/gamespec-prototype.json"))
	return repository


func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
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
