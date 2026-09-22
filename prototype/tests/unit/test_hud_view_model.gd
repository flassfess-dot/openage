extends SceneTree

const HudViewModel := preload("res://scripts/hud_view_model.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var barracks: Dictionary = world.add_building(80, "barracks", Vector2(10.0, 10.0), 1)
	var view_model = HudViewModel.new()
	view_model.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)

	var snapshot := SimulationSnapshot.presentation(world, 7, 1)
	var model: Dictionary = view_model.build(snapshot, [80], "RECTANGLE", "ru")
	assert_equal(model["resources"]["food"], 180, "resources come from presentation snapshot")
	assert_equal(model["age"]["label"], "Каменный век", "age has localized display model")
	assert_equal(model["selection"]["leader"]["name"], "Казармы", "selected entity name comes from localization catalog")
	assert_equal(model["selection"]["leader"]["civilization_name"], "Римляне", "selection card resolves the source civilization label")
	assert_equal(model["selection"]["leader"]["icon_kind"], "building_4", "Roman building selection uses the source Roman architecture icon sheet")
	assert_true(model["selection"]["leader"].has("attack") and model["selection"]["leader"].has("armor"), "selection card receives authoritative combat values")
	var train: Dictionary = first_command(model["commands"], "train", "clubman")
	assert_true(not train.is_empty(), "Barracks exposes its data-driven train command")
	assert_true(bool(train["enabled"]), "authoritative availability enables affordable Clubman")
	assert_equal(train["cost"], {0: 50}, "command shows authoritative modified cost")
	assert_equal(train["cost_text"], "50 FOOD", "command formats cost without changing it")
	assert_equal(train["icon_kind"], "unit", "train command identifies the unit icon sheet")
	assert_equal(train["icon_id"], 2, "train command preserves Clubman DAT icon ID")

	world.set_resource_amount(1, 0, 0)
	model = view_model.build(SimulationSnapshot.presentation(world, 8, 1), [80], "RECTANGLE", "ru")
	train = first_command(model["commands"], "train", "clubman")
	assert_true(not bool(train["enabled"]), "unaffordable command is visibly disabled")
	assert_equal(train["reason"], "insufficient_resources", "disabled reason comes from production system")

	world.set_resource_amount(1, 0, 100)
	assert_true(world.enqueue_unit_production(int(barracks["id"]), 1, "clubman") != null, "fixture enters authoritative queue")
	model = view_model.build(SimulationSnapshot.presentation(world, 9, 1), [80], "RECTANGLE", "ru")
	assert_equal(model["queue"].size(), 1, "selected building queue is exposed")
	assert_equal(model["queue"][0]["label"], "Воин с палицей", "queue item is localized")
	assert_equal(float(model["queue"][0]["progress"]), 0.0, "queued item progress is normalized")

	var town_center: Dictionary = world.add_building(81, "town_center", Vector2(15.0, 10.0), 1)
	world.add_building(82, "granary", Vector2(15.0, 15.0), 1)
	world.set_resource_amount(1, 0, 500)
	model = view_model.build(SimulationSnapshot.presentation(world, 10, 1), [int(town_center["id"])], "RECTANGLE", "ru")
	var tool_age: Dictionary = first_command(model["commands"], "research", "101")
	assert_true(not tool_age.is_empty(), "Town Center exposes currently reachable age research")
	assert_true(bool(tool_age["enabled"]), "research availability includes authoritative prerequisites and resources")
	assert_equal(tool_age["label"], "Неолит", "research command uses original localized technology name")
	assert_equal(tool_age["icon_kind"], "technology", "research command identifies the technology icon sheet")
	assert_equal(tool_age["icon_id"], 65, "research command preserves Tool Age DAT icon ID")

	var worker: Dictionary = world.add_unit(1, "villager", Vector2(7.0, 7.0), false)
	model = view_model.build(SimulationSnapshot.presentation(world, 10, 1), [int(worker["id"])], "RECTANGLE", "ru")
	var house: Dictionary = first_command(model["commands"], "build", "house")
	assert_equal(model["command_title"], "BUILD", "single worker opens the build palette")
	assert_true(not house.is_empty() and bool(house.get("enabled", false)), "worker exposes affordable House construction")
	assert_equal(house.get("icon_kind"), "building_4", "Roman worker uses the source Roman building icon sheet")
	assert_equal(house.get("icon_id"), 15, "build command preserves House DAT icon ID")
	assert_equal(house.get("source_unit_id"), 70, "build command preserves resolved source object ID")
	assert_true(first_command(model["commands"], "build", "government_center").is_empty(), "locked future building is absent from worker palette")

	var first: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(5.0, 4.0), false)
	model = view_model.build(SimulationSnapshot.presentation(world, 11, 1), [int(first["id"]), int(second["id"])], "WEDGE", "ru")
	assert_equal(model["commands"].filter(func(command): return command["type"] == "formation").size(), 5, "mobile group receives formation palette")
	assert_true(bool(first_command(model["commands"], "formation", "WEDGE")["active"]), "current formation is marked active")
	assert_equal(model["commands"].filter(func(command): return command["type"] == "unit_action").size(), 4, "mobile selection exposes its complete order palette")
	assert_equal(first_command(model["commands"], "unit_action", "attack_move").get("icon_id"), 4, "attack-move uses the source attack glyph")
	assert_equal(first_command(model["commands"], "unit_action", "stop").get("icon_id"), 3, "stop uses the source raised-hand glyph")
	assert_equal(first_command(model["commands"], "unit_action", "hold").get("icon_id"), 12, "hold-position uses the source guarded-stance glyph")
	assert_equal(first_command(model["commands"], "unit_action", "hold").get("icon_kind"), "command", "unit orders identify the source command glyph sheet")
	assert_equal(first_command(model["commands"], "unit_action", "stance").get("icon_id"), 7, "stance cycling uses a distinct source order glyph")
	assert_equal(first_command(model["commands"], "unit_action", "stance").get("stance"), "defensive", "stance action derives the next mode from authoritative selection state")
	assert_equal(model["selection"]["leader"].get("stance"), "aggressive", "selection presentation exposes the authoritative stance")

	var trader: Dictionary = world.add_unit(1, "trade_boat", Vector2(5.5, 5.5), false)
	model = view_model.build(SimulationSnapshot.presentation(world, 12, 1), [int(trader["id"])], "RECTANGLE", "ru")
	assert_equal(model["command_title"], "TRADE", "Trade Boat opens the trade resource palette")
	assert_equal(model["commands"].filter(func(command): return command["type"] == "trade_resource").size(), 3, "Trade Boat can choose food, wood, or stone")
	assert_true(bool(first_command(model["commands"], "trade_resource", "1")["active"]), "source default trade resource is wood")
	assert_true(bool(model["selection"]["leader"]["trade_enabled"]), "selection model exposes own Trade Boat state")

	var hidden_snapshot := SimulationSnapshot.presentation(world, 13, 1)
	var hidden_building := presentation_entity(hidden_snapshot.get("buildings", []), int(barracks["id"]))
	var hidden_options: Dictionary = hidden_building.get("command_options", {})
	hidden_options.get("train", []).append({"kind": "locked_test_unit", "accepted": false, "reason": "unit_unavailable"})
	hidden_options.get("research", []).append({"technology_id": 9999, "accepted": false, "reason": "missing_prerequisites"})
	model = view_model.build(hidden_snapshot, [int(barracks["id"])], "RECTANGLE", "ru")
	assert_true(first_command(model["commands"], "train", "locked_test_unit").is_empty(), "technology-locked units are absent instead of translucent")
	assert_true(first_command(model["commands"], "research", "9999").is_empty(), "prerequisite-locked research is absent instead of translucent")

	if failures.is_empty():
		print("I10-001 HUD view model tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func first_command(commands: Array, command_type: String, command_id: String) -> Dictionary:
	for command_value in commands:
		var command: Dictionary = command_value
		if String(command.get("type", "")) == command_type and String(command.get("id", "")) == command_id:
			return command
	return {}


func presentation_entity(entities: Array, entity_id: int) -> Dictionary:
	for entity_value in entities:
		var entity: Dictionary = entity_value
		if int(entity.get("id", -1)) == entity_id:
			return entity
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
