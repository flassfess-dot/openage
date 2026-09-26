extends SceneTree

const MapGenerator := preload("res://scripts/random_map_generator.gd")
const MapContract := preload("res://scripts/random_map_contract.gd")
const SourceProfile := preload("res://scripts/random_map_source_profile.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const AiPlayer := preload("res://scripts/ai_player.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_verify_tree_palettes()
	_verify_landscape()
	_verify_bounded_histories()
	if failures.is_empty():
		print("Map landscape and bounded-history tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _verify_tree_palettes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1742
	var palms: Array = MapGenerator._forest_palette(13, rng)
	_check(palms.size() >= 5, "desert forests have several palm silhouettes")
	for id_value in palms:
		_check(MapGenerator.TREE_GRAPHICS.has(int(id_value)), "every palm has a source graphic")
	for graphic_value in MapGenerator.TREE_GRAPHICS.values():
		_check(FileAccess.file_exists("res://assets/generated/graphic_%d.png" % int(graphic_value)), "chosen tree graphic exists in the source asset import")
	var broadleaf_clumps := 0
	var mixed_clumps := 0
	var pure_conifer_clumps := 0
	for index in range(100):
		var palette: Array = MapGenerator._forest_palette(10, rng)
		var conifers := palette.filter(func(id_value): return int(id_value) in MapGenerator.CONIFER_TREES)
		if conifers.is_empty():
			broadleaf_clumps += 1
		elif conifers.size() == palette.size():
			pure_conifer_clumps += 1
		else:
			mixed_clumps += 1
	_check(broadleaf_clumps > 0, "some green clumps remain pure broadleaf")
	_check(mixed_clumps > 0, "green clumps mix broadleaf and conifer")
	_check(pure_conifer_clumps < 12, "pure conifer clumps stay rare")


func _verify_landscape() -> void:
	var size := Vector2i(64, 64)
	var starts: Array[Vector2] = [Vector2(25.5, 25.5), Vector2(49.5, 49.5)]
	var profile := {"id": "coastal", "topology": "coastal", "coast_fraction": 0.21, "requires_naval_starts": false}
	var generator: Dictionary = MapContract.build(profile, size, starts)
	generator["source_profile"] = SourceProfile.get_profile("coastal")
	var definition := {"map": {"size": size, "seed": 41721, "generator": generator}, "players": [{"start": starts[0]}, {"start": starts[1]}], "entities": []}
	var map_data: Dictionary = MapGenerator.generate(definition)
	_check(map_data == MapGenerator.generate(definition), "landscape generation remains deterministic")
	var tree_graphics: Dictionary = {}
	var palm_graphics: Dictionary = {}
	for resource_value in map_data["resources"]:
		var resource: Dictionary = resource_value
		if String(resource.get("kind", "")) != "tree":
			continue
		var graphic_id := int(resource.get("source_graphic_id", -1))
		if graphic_id > 0:
			tree_graphics[graphic_id] = true
			if int(resource.get("source_unit_id", -1)) in MapGenerator.PALM_TREES:
				palm_graphics[graphic_id] = true
	_check(tree_graphics.size() >= 3, "one generated map uses several tree sprites")
	_check(palm_graphics.size() >= 2, "palm groves vary within the map")
	var elevated := 0
	for level in map_data["vertex_levels"]:
		if int(level) > 0:
			elevated += 1
	_check(elevated > 100, "coastal map contains distributed relief")
	_check(map_data["terrain_ids"].has(22), "offshore water contains darker patches")
	_check(map_data.get("scenery", []).size() >= 5, "landscape includes decorative rock outcrops")
	var shoreline_positions: Dictionary = {}
	for y in range(24, 58):
		for x in range(2, size.x - 2):
			if int(map_data["terrain_ids"][y * size.x + x]) not in [1, 4, 22]:
				shoreline_positions[x] = true
				break
	_check(shoreline_positions.size() >= 3, "coastline bends across several cells: %s" % [shoreline_positions.keys()])


func _verify_bounded_histories() -> void:
	var controller = GameController.new()
	for sequence in range(1, 9):
		controller.command_results[sequence] = {"accepted": true}
	controller.set_command_result_limit(3)
	_check(controller.command_results.size() == 3, "live command results shrink to their window")
	_check(not controller.get_command_result(8).is_empty(), "latest command result remains available")
	_check(controller.get_command_result(1).is_empty(), "old command result is discarded")
	var world = SimulationWorld.new(Vector2i(16, 16))
	var resource: Dictionary = world.add_resource("berries", Vector2(4.5, 4.5), 2)
	resource["decay_rate"] = 10.0
	world.decaying_resource_nodes.append(resource)
	world.advance_resource_lifecycle(1.0)
	_check(world.decaying_resource_nodes.is_empty(), "depleted decay entries leave the per-tick queue")
	_check(world.find_resource(int(resource["id"])) == null, "exhausted invisible decay nodes leave the authoritative roster")
	var finder = Pathfinder.new(NavigationGrid.new(Vector2i(8, 8)))
	finder.route_cache_revision = finder.grid.revision
	for index in range(Pathfinder.MAX_ROUTE_CACHE_ENTRIES):
		finder.cache[str(index)] = []
	finder.find_path(Vector2(2.5, 2.5), Vector2(6.5, 6.5))
	_check(finder.cache.size() <= Pathfinder.MAX_ROUTE_CACHE_ENTRIES, "unique path endpoints cannot grow the route cache forever")
	var ai = AiPlayer.new({"team": 2})
	ai.failed_gather_targets = {7: {18: true}, 8: {19: true}}
	ai._remember_failed_gather_targets({"units": [{"id": 8, "team": 2, "hp": 10.0}], "resources": [{"id": 19, "amount": 0}]})
	_check(ai.failed_gather_targets.is_empty(), "AI forgets failures for dead workers and exhausted resources")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
