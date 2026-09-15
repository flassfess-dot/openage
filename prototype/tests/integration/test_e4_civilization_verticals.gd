extends SceneTree

const CombatRules := preload("res://scripts/combat_rules.gd")
const CompositeGraphic := preload("res://scripts/composite_graphic.gd")
const PresentationAudioRouter := preload("res://scripts/presentation_audio_router.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

const MATRIX_PATHS := [
	"res://data/content_waves/civilizations_1_4.json",
	"res://data/content_waves/civilizations_5_8.json",
]
const ALL_CIVILIZATIONS_PATH := "res://data/content_waves/all_civilizations.json"

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var all_civilizations := read_json(ALL_CIVILIZATIONS_PATH)
	for matrix_path in MATRIX_PATHS:
		var matrix := read_json(matrix_path)
		for civilization_value in matrix.get("civilizations", []):
			verify_civilization_vertical(catalog, civilization_value, all_civilizations.get("common_roster_lines", []))
	if failures.is_empty():
		print("E4 civilization vertical tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_civilization_vertical(catalog, specification: Dictionary, common_roster: Array) -> void:
	var civilization_id := int(specification.get("civilization_id", -1))
	var context := String(specification.get("alias", "civilization_%d" % civilization_id))
	var world = configured_world(catalog, civilization_id)
	var source_civilization: Dictionary = world.civilization_record(1)
	assert_equal(int(source_civilization.get("tech_tree_id", -1)), int(specification.get("technology_tree_effect_bundle_id", -2)), "%s source technology tree" % context)
	assert_equal(int(source_civilization.get("icon_set", -1)), int(specification.get("icon_set", -2)), "%s source building shell" % context)
	assert_equal(world.technology_system.can_research(1, int(specification.get("signature_disabled_technology_id", -1))), "technology_disabled", "%s source restriction" % context)

	var town_center: Dictionary = world.add_building(1000 + civilization_id, "town_center", Vector2(12.0, 12.0), 1)
	var town_center_source: Dictionary = world.object_record_by_id(int(town_center.get("source_unit_id", -1)), 1)
	var town_center_frame: Dictionary = catalog.building_frame_info(town_center)
	assert_equal(int(town_center_frame.get("graphic_id", -1)), int(town_center_source.get("graphics", {}).get("idle", -2)), "%s Town Center uses its source graphic" % context)
	assert_true(town_center_frame.get("texture") != null, "%s Town Center shell is loadable" % context)

	var villager_order: Variant = world.enqueue_unit_production(int(town_center.get("id", -1)), 1, "villager")
	assert_true(villager_order != null, "%s Town Center produces Villager through the normal queue" % context)
	if villager_order != null:
		world.update_production(100.0)
		var produced: Array = world.get_units().filter(func(unit): return int(unit.get("production_order_id", -1)) == int(villager_order.get("id", -2)))
		assert_equal(produced.size(), 1, "%s Villager production completes" % context)
		if not produced.is_empty():
			assert_equal(int(produced[0].get("components", {}).get("ownership", {}).get("civilization_id", -1)), civilization_id, "%s produced unit keeps civilization identity" % context)

	world.grant_technology(1, 0)
	world.grant_technology(1, 10)
	var age_order: Variant = world.enqueue_research(int(town_center.get("id", -1)), 1, 101)
	assert_true(age_order != null, "%s can research Tool Age through the normal queue" % context)
	if age_order != null:
		world.update_production(1000.0)
		assert_true(world.get_researched_technologies(1).has(101), "%s Tool Age research completes" % context)

	verify_signature_bonus(world, specification, context)
	verify_shared_roster_presentation(catalog, world, civilization_id, common_roster, context)
	verify_common_presentation_and_audio(catalog, world, civilization_id, context)
	verify_short_combat(world, context)


func configured_world(catalog, civilization_id: int):
	var world = SimulationWorld.new(Vector2i(36, 36))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, civilization_id)
	world.set_team_civilization(2, 13)
	for team in [1, 2]:
		world.set_population_cap(team, 50)
		world.set_population_housing(team, 50)
		for resource_type in range(4):
			world.set_resource_amount(team, resource_type, 10000)
	return world


func verify_signature_bonus(world, specification: Dictionary, context: String) -> void:
	var bonus: Dictionary = specification.get("signature_bonus", {})
	var kind := String(bonus.get("kind", ""))
	var source_id := int(bonus.get("source_unit_id", -1))
	var source: Dictionary = world.object_record_by_id(source_id, 1)
	if String(bonus.get("field", "")) == "resource_cost":
		verify_signature_cost(world, source, bonus, kind, context)
		return
	var entity: Dictionary
	if String(source.get("movement", {}).get("domain", "land")) == "static" or kind == "tower":
		entity = world.add_building(1100 + int(specification.get("civilization_id", 0)), kind, Vector2(20.0, 20.0), 1)
	else:
		entity = world.add_unit(1, kind, Vector2(20.0, 20.0), false)
	var upgrade_from_source_id := int(bonus.get("upgrade_from_source_unit_id", -1))
	if upgrade_from_source_id >= 0:
		assert_equal(int(entity.get("source_unit_id", -1)), upgrade_from_source_id, "%s signature object upgrade source identity" % context)
		world.apply_unit_upgrade_to_entity(entity, source_id)
	assert_equal(int(entity.get("source_unit_id", -1)), source_id, "%s signature object source identity" % context)
	var field := String(bonus.get("field", ""))
	var source_value := source_field_value(source, field)
	var expected := source_value
	if String(bonus.get("operator", "")) == "multiply":
		expected *= float(bonus.get("value", 1.0))
	elif String(bonus.get("operator", "")) == "add":
		expected += float(bonus.get("value", 0.0))
	elif String(bonus.get("operator", "")) == "set":
		expected = float(bonus.get("value", source_value))
	assert_near(float(entity.get(field, 0.0)), expected, 0.0001, "%s signature bonus is active in runtime" % context)


func verify_signature_cost(world, source: Dictionary, bonus: Dictionary, kind: String, context: String) -> void:
	var resource_type_id := int(bonus.get("resource_type_id", -1))
	var source_cost := 0.0
	for cost_value in source.get("resources", {}).get("cost", []):
		var cost: Dictionary = cost_value
		if bool(cost.get("enabled", false)) and int(cost.get("type_id", -1)) == resource_type_id:
			source_cost = float(cost.get("amount", 0.0))
	var expected := source_cost
	if String(bonus.get("operator", "")) == "multiply":
		expected *= float(bonus.get("value", 1.0))
	elif String(bonus.get("operator", "")) == "add":
		expected += float(bonus.get("value", 0.0))
	var actual := int(world.unit_resource_cost(kind, 1).get(resource_type_id, -1))
	assert_equal(actual, maxi(0, roundi(expected)), "%s signature production cost is active in runtime" % context)


func source_field_value(source: Dictionary, field: String) -> float:
	match field:
		"max_hp": return float(source.get("health", 0.0))
		"attack_period": return float(source.get("combat", {}).get("attack_period", 0.0))
		"attack_range": return float(source.get("combat", {}).get("range_max", 0.0))
		"carry_capacity": return float(source.get("resources", {}).get("capacity", 0.0))
	return float(source.get(field, 0.0))


func verify_common_presentation_and_audio(catalog, world, civilization_id: int, context: String) -> void:
	var bowman: Dictionary = world.add_unit(1, "archer", Vector2(8.0, 8.0), false)
	var source: Dictionary = world.object_record_by_id(int(bowman.get("source_unit_id", -1)), 1)
	var attack_frame: Dictionary = catalog.unit_frame_info(bowman, "attack")
	assert_equal(int(attack_frame.get("graphic_id", -1)), int(source.get("graphics", {}).get("attack", -2)), "%s Bowman uses its source attack graphic" % context)
	assert_true(attack_frame.get("texture") != null, "%s Bowman attack presentation is loadable" % context)
	var audio = PresentationAudioRouter.new()
	audio.configure(catalog.runtime_catalog_data, catalog.sound_catalog_data, catalog.asset_records, catalog.graphics_catalog_data, catalog.object_catalog_data)
	var request: Dictionary = audio.request_entity_animation(bowman, "attack", civilization_id)
	assert_true(bool(request.get("accepted", false)), "%s Bowman source attack audio is playable" % context)


func verify_shared_roster_presentation(catalog, world, civilization_id: int, common_roster: Array, context: String) -> void:
	for line_value in common_roster:
		var line: Dictionary = line_value
		var alias := String(line.get("runtime_alias", ""))
		var category := String(line.get("category", ""))
		for source_id_value in line.get("source_unit_ids", []):
			var source_id := int(source_id_value)
			var source: Dictionary = world.object_record_by_id(source_id, 1)
			assert_true(not source.is_empty(), "%s %s source %d exists" % [context, alias, source_id])
			if source.is_empty():
				continue
			if category == "unit":
				verify_unit_source_presentation(catalog, source, alias, civilization_id, context)
			elif category == "building":
				verify_building_source_presentation(catalog, source, alias, civilization_id, context)


func verify_unit_source_presentation(catalog, source: Dictionary, alias: String, civilization_id: int, context: String) -> void:
	var source_id := int(source.get("unit_id", -1))
	var unit := {
		"kind": alias,
		"source_unit_id": source_id,
		"team": 1,
		"facing": 0,
		"anim": 0.0,
		"hp": float(source.get("health", 1.0)),
		"max_hp": float(source.get("health", 1.0)),
		"components": {"ownership": {"civilization_id": civilization_id}},
	}
	for state in ["idle", "move", "attack", "death"]:
		var expected_graphic := int(source.get("graphics", {}).get(state, -1))
		if expected_graphic < 0:
			continue
		var frame: Dictionary = catalog.unit_frame_info(unit, state)
		verify_source_graphic_resolution(catalog, frame, expected_graphic, "%s %s source %d %s" % [context, alias, source_id, state])


func verify_building_source_presentation(catalog, source: Dictionary, alias: String, civilization_id: int, context: String) -> void:
	var source_id := int(source.get("unit_id", -1))
	var building := {
		"kind": alias,
		"source_unit_id": source_id,
		"team": 1,
		"state": "complete",
		"hp": float(source.get("health", 1.0)),
		"max_hp": float(source.get("health", 1.0)),
		"amount": 100,
		"max_amount": 100,
		"components": {"ownership": {"civilization_id": civilization_id}},
	}
	var frame: Dictionary = catalog.building_frame_info(building)
	verify_source_graphic_resolution(catalog, frame, int(source.get("graphics", {}).get("idle", -2)), "%s %s source %d" % [context, alias, source_id])


func verify_source_graphic_resolution(catalog, frame: Dictionary, source_graphic_id: int, context: String) -> void:
	var expected_graphics: Array[int] = []
	collect_visible_graphic_layers(catalog.graphics_catalog_data, source_graphic_id, 0, expected_graphics, {})
	assert_true(not expected_graphics.is_empty(), "%s source graphic %d has a renderable layer" % [context, source_graphic_id])
	var rendered_graphics: Array[int] = []
	if frame.get("texture") != null:
		rendered_graphics.append(int(frame.get("graphic_id", -1)))
	for part_value in frame.get("composite_parts", []):
		var part: Dictionary = part_value
		if part.get("texture") != null:
			rendered_graphics.append(int(part.get("graphic_id", -1)))
	assert_true(not rendered_graphics.is_empty(), "%s resolves at least one loadable layer" % context)
	for graphic_id in expected_graphics:
		assert_true(rendered_graphics.has(graphic_id), "%s resolves source layer %d" % [context, graphic_id])


func collect_visible_graphic_layers(graphics_catalog: Dictionary, graphic_id: int, logical_facing: int, result: Array[int], visited: Dictionary) -> void:
	if graphic_id < 0 or visited.has(graphic_id):
		return
	visited[graphic_id] = true
	var specification: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
	if specification.is_empty():
		return
	if bool(specification.get("slp", {}).get("valid", false)):
		result.append(graphic_id)
	for delta_value in specification.get("deltas", []):
		var delta: Dictionary = delta_value
		var child_id := int(delta.get("graphic_id", -1))
		if child_id < 0 or not CompositeGraphic.delta_visible(int(delta.get("display_angle", -1)), logical_facing, int(specification.get("angle_count", 1))):
			continue
		collect_visible_graphic_layers(graphics_catalog, child_id, logical_facing, result, visited)


func verify_short_combat(world, context: String) -> void:
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(26.0, 25.0), false)
	var target: Dictionary = world.add_unit(2, "villager", Vector2(26.6, 25.0), false)
	var hp_before := float(target.get("hp", 0.0))
	var expected_damage := CombatRules.damage_from_attacks(attacker.get("components", {}).get("combat", {}).get("attacks", []), target)
	assert_true(expected_damage > 0.0, "%s combat rules produce positive damage" % context)
	assert_true(world.assign_command_attack([attacker], int(target.get("id", -1))), "%s authoritative attack order is accepted" % context)
	for _step in range(24):
		world.advance(0.25, 1, 2)
		if float(target.get("hp", 0.0)) < hp_before:
			break
	assert_true(float(target.get("hp", 0.0)) < hp_before, "%s short combat exchange deals damage" % context)


func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("unable to open %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, tolerance: float, context: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %s ± %s, got %s" % [context, expected, tolerance, actual])
