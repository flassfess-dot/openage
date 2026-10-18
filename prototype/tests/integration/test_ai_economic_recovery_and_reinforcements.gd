extends SceneTree

const Ai := preload("res://scripts/ai_player.gd")
const Policy := preload("res://scripts/skirmish_ai_policy.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Commands := preload("res://scripts/commands.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load_generated_data()
	verify_build_cargo_recovery(catalog)
	verify_reinforcement_march_and_combat(catalog)
	for failure in failures: push_error(failure)
	print("AI economic recovery and reinforcement pipeline: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func configured_world(catalog):
	var world := World.new(Vector2i(48, 48))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for type_id in range(4): world.set_resource_amount(1, type_id, 0)
	return world

func isolated_policy(workers: int) -> Dictionary:
	var policy := Policy.resolve()
	policy["land_worker_target"] = workers
	policy["maximum_workers"] = workers
	policy["construction_priorities"] = []
	policy["building_limits"] = {}
	policy["minimum_workers_before_age_up"] = 999
	return policy

func step_ai(world, controller, ai) -> void:
	ai.collect_feedback(controller, controller.tick_index)
	var tick: int = controller.tick_index + 1
	if ai.needs_decision(tick):
		var snapshot := Snapshot.with_queries(world, controller.tick_index, 1, ai.presentation_options())
		for command in ai.collect_commands(snapshot, tick):
			var metadata: Dictionary = command.params.get("_ai_feedback", {})
			command.params.erase("_ai_feedback")
			controller.enqueue_command(command, true, 1)
			ai.register_proposal(command, metadata)
	controller.advance_frame(0.05, 1, 2)

func verify_build_cargo_recovery(catalog) -> void:
	var world = configured_world(catalog)
	world.set_resource_amount(1, 1, 200)
	world.add_building(700, "town_center", Vector2(8, 8), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(5, 6), false)
	var opponent: Dictionary = world.add_unit(2, "clubman", Vector2(42, 42), false)
	opponent["stance"] = "passive"
	var resource: Dictionary = world.add_resource("berries", Vector2(4, 5), 1000)
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var gather := Commands.GatherCommand.new(1, [int(worker["id"])], int(resource["id"]))
	controller.enqueue_command(gather, true, 1)
	for unused in range(300):
		controller.advance_frame(0.05, 1, 2)
		if float(worker.get("carried_amount", 0.0)) >= 1.0: break
	check(float(worker.get("carried_amount", 0.0)) > 0.0, "setup worker harvests food through a public gather order")
	var build := Commands.BuildCommand.new(controller.tick_index + 1, [int(worker["id"])], "house", Vector2(12.5, 8.5))
	controller.enqueue_command(build, true, 1)
	for unused in range(1600):
		controller.advance_frame(0.05, 1, 2)
		if String(worker.get("task", "")) == "idle": break
	check(bool(controller.get_command_result(build.sequence_id).get("accepted", false)), "public house construction is accepted")
	check(world.get_buildings().any(func(b): return b.get("kind") == "house" and b.get("state") == "complete"), "interrupted gatherer actually completes the house")
	check(String(worker.get("task", "")) == "idle" and float(worker.get("carried_amount", 0.0)) > 0.0, "completed construction reproduces idle carried food")
	var carried: float = worker.get("carried_amount", 0.0)
	var before: int = world.get_resource_amount(1, 0)
	var ai := Ai.new({"team": 1, "ai": isolated_policy(1)})
	for unused in range(2400):
		step_ai(world, controller, ai)
		if int(worker.get("deposit_cycles", 0)) >= 2: break
	check(controller.events_after().any(func(e): return e["type"] == "command_accepted" and e.get("payload", {}).get("command_type") == "return_resources"), "AI recovery submits an accepted public return order")
	check(world.get_resource_amount(1, 0) >= before + roundi(carried) + 10, "recovered worker deposits its cargo and produces another food delivery")
	check(int(worker.get("deposit_cycles", 0)) >= 2, "worker resumes a full harvest and delivery cycle after construction")
	world.shutdown_derived_state()

func verify_reinforcement_march_and_combat(catalog) -> void:
	var world = configured_world(catalog)
	var town: Dictionary = world.add_building(700, "town_center", Vector2(8, 8), 1)
	town["components"]["vision"]["range"] = 60.0
	town["components"]["vision"]["enabled"] = true
	var enemy: Dictionary = world.add_building(701, "town_center", Vector2(35, 35), 2)
	for index in range(4): world.add_unit(1, "clubman", Vector2(12 + index, 10), false)
	world.update_fog_of_war()
	var ai := Ai.new({"team": 1, "ai": isolated_policy(0)})
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var first_departed := false
	for unused in range(1000):
		step_ai(world, controller, ai)
		if world.get_units().any(func(u): return u["team"] == 1 and Vector2(u["pos"]).distance_to(Vector2(8, 8)) >= 18.0):
			first_departed = true
			break
	check(first_departed, "first operation actually marches out of the settlement")
	var recruits: Array = []
	for index in range(5): recruits.append(world.add_unit(1, "clubman", Vector2(11 + index, 9), false))
	var before_hp: float = enemy["hp"]
	var second_departed := false
	var multiple_groups := false
	for unused in range(2600):
		step_ai(world, controller, ai)
		multiple_groups = multiple_groups or ai.operations.groups.size() >= 2
		second_departed = second_departed or recruits.any(func(u): return Vector2(u["pos"]).distance_to(Vector2(8, 8)) >= 18.0)
		if second_departed and float(enemy["hp"]) < before_hp: break
	check(multiple_groups, "a second operation is created while the first is active")
	check(second_departed, "reinforcements actually leave the base through normal movement")
	check(float(enemy["hp"]) < before_hp, "the army damages the enemy building through authoritative combat")
	check(recruits.filter(func(u): return Vector2(u["pos"]).distance_to(Vector2(8, 8)) < 12.0).size() >= 2, "a local reserve remains near the settlement")
	world.shutdown_derived_state()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
