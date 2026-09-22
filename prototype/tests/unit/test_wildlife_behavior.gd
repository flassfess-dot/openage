extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const WILDLIFE_SCRIPT_PATH := "res://scripts/wildlife_behavior_system.gd"

var failures: Array[String] = []
var catalog
var WildlifeBehaviorSystem: Script


func _initialize() -> void:
	WildlifeBehaviorSystem = load(WILDLIFE_SCRIPT_PATH) as Script
	if WildlifeBehaviorSystem == null or not WildlifeBehaviorSystem.can_instantiate():
		push_error("wildlife behavior script does not compile")
		quit(1)
		return
	catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_original_wildlife_contract()
	test_land_wildlife_stays_idle_without_trigger()
	test_gazelle_flees_from_players_and_lions()
	test_lion_hunts_gazelles_but_never_elephants()
	test_alligator_hunts_only_beside_the_coast()

	if failures.is_empty():
		print("W-001 wildlife behavior tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_wildlife_contract() -> void:
	var objects: Dictionary = catalog.object_catalog_data.get("objects", {})
	var gazelle: Dictionary = objects.get("0:65", {})
	var lion: Dictionary = objects.get("0:126", {})
	var alligator: Dictionary = objects.get("0:1", {})
	assert_equal(float(gazelle.get("line_of_sight", -1.0)), 2.0, "source gazelle reacts across two cells")
	assert_equal(float(lion.get("line_of_sight", -1.0)), 3.0, "source lion acquires targets across three cells")
	assert_equal(float(alligator.get("line_of_sight", -1.0)), 5.0, "source alligator acquires targets across five cells")
	assert_true(lion.get("commands", []).any(func(command): return int(command.get("type", -1)) == 11 and int(command.get("unit_id", -1)) == 65), "source lion command explicitly targets gazelles")
	var hawk: Dictionary = objects.get("0:95", {})
	var eagle: Dictionary = objects.get("0:96", {})
	assert_true(hawk.get("commands", []).any(func(command): return int(command.get("type", -1)) == 10 and int(command.get("move_sprite_id", -1)) == 482), "source hawk is a continuously flying ambient actor")
	assert_true(eagle.get("commands", []).any(func(command): return int(command.get("type", -1)) == 10 and int(command.get("move_sprite_id", -1)) == 483), "source eagle is a continuously flying ambient actor")


func test_land_wildlife_stays_idle_without_trigger() -> void:
	for kind in ["gazelle", "elephant", "lion"]:
		var world = configured_world()
		var animal: Dictionary = world.add_unit(0, kind, Vector2(10.0, 10.0), false)
		var wildlife = WildlifeBehaviorSystem.new()
		for tick in [1, 120, 240, 480]:
			assert_equal(wildlife.collect_commands(world, tick).size(), 0, "%s remains stationary without an attack or flee trigger" % kind)
		assert_equal(String(animal.get("task", "")), "idle", "%s keeps its original idle state" % kind)


func test_gazelle_flees_from_players_and_lions() -> void:
	var world = configured_world()
	var gazelle: Dictionary = world.add_unit(0, "gazelle", Vector2(10.0, 10.0), false)
	world.add_unit(0, "elephant", Vector2(10.5, 10.0), false)
	var villager: Dictionary = world.add_unit(1, "villager", Vector2(11.5, 10.0), false)
	var wildlife = WildlifeBehaviorSystem.new()
	var flee_tick := decision_tick(int(gazelle["id"]), WildlifeBehaviorSystem.GAZELLE_FLEE_SCAN_INTERVAL_TICKS, 53)
	var moves := commands_for(wildlife.collect_commands(world, flee_tick), int(gazelle["id"]), "move")
	assert_equal(moves.size(), 1, "gazelle flees when a player unit enters its two-cell sight range")
	if not moves.is_empty():
		var away_from_player := Vector2(gazelle["pos"]) - Vector2(villager["pos"])
		var escape_vector := Vector2(moves[0].target) - Vector2(gazelle["pos"])
		assert_true(escape_vector.dot(away_from_player) > 0.0, "gazelle escape destination leads away from the player")

	var lion_world = configured_world()
	var second_gazelle: Dictionary = lion_world.add_unit(0, "gazelle", Vector2(10.0, 10.0), false)
	var lion: Dictionary = lion_world.add_unit(0, "lion", Vector2(11.5, 10.0), false)
	var lion_flee_tick := decision_tick(int(second_gazelle["id"]), WildlifeBehaviorSystem.GAZELLE_FLEE_SCAN_INTERVAL_TICKS, 53)
	var lion_moves := commands_for(WildlifeBehaviorSystem.new().collect_commands(lion_world, lion_flee_tick), int(second_gazelle["id"]), "move")
	assert_equal(lion_moves.size(), 1, "gazelle also flees when a lion enters sight range")
	if not lion_moves.is_empty():
		var away_from_lion := Vector2(second_gazelle["pos"]) - Vector2(lion["pos"])
		var lion_escape_vector := Vector2(lion_moves[0].target) - Vector2(second_gazelle["pos"])
		assert_true(lion_escape_vector.dot(away_from_lion) > 0.0, "gazelle escape destination leads away from the lion")


func test_lion_hunts_gazelles_but_never_elephants() -> void:
	var world = configured_world()
	var lion: Dictionary = world.add_unit(0, "lion", Vector2(10.0, 10.0), false)
	var elephant: Dictionary = world.add_unit(0, "elephant", Vector2(10.5, 10.0), false)
	var gazelle: Dictionary = world.add_unit(0, "gazelle", Vector2(12.5, 10.0), false)
	var wildlife = WildlifeBehaviorSystem.new()
	var attacks := commands_for(wildlife.collect_commands(world, 1), int(lion["id"]), "attack")
	assert_equal(attacks.size(), 1, "lion starts hunting a visible gazelle without an artificial random gate")
	if attacks.is_empty():
		return
	assert_equal(attacks[0].target_entity_id, gazelle["id"], "lion chooses tagged prey")
	assert_true(attacks[0].target_entity_id != elephant["id"], "lion never chooses an elephant as automatic prey")

	var distant_world = configured_world()
	var second_lion: Dictionary = distant_world.add_unit(0, "lion", Vector2(10.0, 10.0), false)
	distant_world.add_unit(0, "gazelle", Vector2(13.1, 10.0), false)
	assert_equal(commands_for(WildlifeBehaviorSystem.new().collect_commands(distant_world, 1), int(second_lion["id"]), "attack").size(), 0, "lion does not detect gazelles beyond the original three-cell range")


func test_alligator_hunts_only_beside_the_coast() -> void:
	var world = configured_world()
	configure_test_coast(world, 4)
	var alligator: Dictionary = world.add_unit(0, "alligator", Vector2(4.5, 10.5), false)
	var shore_villager: Dictionary = world.add_unit(1, "villager", Vector2(5.5, 10.5), false)
	var inland_villager: Dictionary = world.add_unit(1, "villager", Vector2(8.5, 10.5), false)
	var wildlife = WildlifeBehaviorSystem.new()
	var attacks := commands_for(wildlife.collect_commands(world, 1), int(alligator["id"]), "attack")
	assert_equal(attacks.size(), 1, "alligator can acquire a creature beside the shore")
	if not attacks.is_empty():
		assert_equal(attacks[0].target_entity_id, shore_villager["id"], "alligator ignores the inland creature")
	shore_villager["hp"] = 0.0
	var scan_tick := decision_tick(int(alligator["id"]), WildlifeBehaviorSystem.PREDATOR_SCAN_INTERVAL_TICKS, 19, 2)
	assert_equal(commands_for(wildlife.collect_commands(world, scan_tick), int(alligator["id"]), "attack").size(), 0, "alligator does not begin an inland hunt")

	alligator["task"] = "attack"
	alligator["target_id"] = inland_villager["id"]
	var return_tick := decision_tick(int(alligator["id"]), WildlifeBehaviorSystem.COAST_RETURN_INTERVAL_TICKS, 41, 2)
	var disengage: Array = wildlife.collect_commands(world, return_tick).filter(func(command): return command.unit_ids.has(int(alligator["id"])) and command.command_type() in ["move", "stop"])
	assert_equal(disengage.size(), 1, "alligator abandons a target that leaves the coast")

	alligator["pos"] = Vector2(9.5, 10.5)
	alligator["previous_pos"] = alligator["pos"]
	alligator["task"] = "idle"
	alligator["target_id"] = -1
	var returns := commands_for(wildlife.collect_commands(world, return_tick), int(alligator["id"]), "move")
	assert_equal(returns.size(), 1, "alligator away from water returns to its coastal home")
	if not returns.is_empty():
		assert_true(WildlifeBehaviorSystem._is_near_water(world, returns[0].target, 1), "alligator return destination lies beside water")

	alligator["pos"] = Vector2(4.5, 10.5)
	alligator["previous_pos"] = alligator["pos"]
	alligator["task"] = "idle"
	alligator["target_id"] = -1
	assert_equal(wildlife.collect_commands(world, return_tick).size(), 0, "idle alligator remains at its source coastal position")


func decision_tick(entity_id: int, interval: int, salt: int, minimum_tick: int = 1) -> int:
	for tick in range(minimum_tick, minimum_tick + interval + 1):
		if WildlifeBehaviorSystem._decision_due(tick, entity_id, interval, salt):
			return tick
	return -1


func commands_for(commands: Array, entity_id: int, command_type: String) -> Array:
	return commands.filter(func(command): return command.command_type() == command_type and command.unit_ids.has(entity_id))


func configured_world():
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	return world


func configure_test_coast(world, shore_x: int) -> void:
	world.map_terrain_ids.clear()
	for y in range(world.map_size.y):
		for x in range(world.map_size.x):
			world.map_terrain_ids[Vector2i(x, y)] = 1 if x < shore_x else 2 if x == shore_x else 0
	world.navigation_grid.configure_terrain(func(cell: Vector2i): return world.terrain_kind_at_cell(cell))
	world.set_terrain_catalog(catalog.terrain_catalog_data)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
