extends SceneTree
const Contract := preload("res://scripts/entity_read_contract.gd")
const World := preload("res://scripts/simulation_world.gd")
const Preparation := preload("res://scripts/ai_observation_preparation.gd")
const Store := preload("res://scripts/ai_observation_store.gd")
const Player := preload("res://scripts/ai_player.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
var failures: Array[String] = []
func _initialize() -> void:
	check(ClassDB.class_exists("RoRReadModelKernel") and ClassDB.instantiate("RoRReadModelKernel").has_method("project_ai"), "rebuilt native module exposes AI projection")
	var world := World.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var entities: Array = [world.add_unit(1, "villager", Vector2(4, 4), false), world.add_building(900, "town_center", Vector2(16, 16), 1), world.add_resource("tree", Vector2(9, 9), 100)]
	for entity in entities:
		entity["components"]["trade"] = {"enabled": true, "cargo_gold": 7, "target_dock_id": 900, "approach_position": Vector2.ONE}
		entity["components"]["cargo"] = {"enabled": true, "passenger_ids": [3, 4], "capacity": 4, "allow_allied": false}
		entity["components"]["order"] = {"type": "move", "completed": false, "target_entity_id": 13}
		entity["allowed_gatherer_domains"] = ["land", "water"]
		if entity.has("production_queue"):
			entity["production_queue"] = [{"kind": "villager", "status": "queued", "progress": 3.5}]
		for observer in [0, 1, 2, 3]:
			var previous: Dictionary = {}
			for step in range(8):
				entity["pos"] = Vector2(step, step + 1)
				entity["hp"] = float(100 - step)
				entity["components"]["order"]["completed"] = step % 2 == 0
				entity["components"]["trade"]["cargo_gold"] = step
				if step % 2 == 0: entity["diagnostic_reason"] = "test"
				else: entity.erase("diagnostic_reason")
				var expected := Contract.ai_reference(entity, observer)
				var projected := Contract.ai(entity, observer, previous)
				check(projected == expected, "native AI facts preserve every reference field and observer privacy")
				check(projected.is_read_only() and projected["components"].is_read_only(), "AI facts are recursively immutable")
				check(is_same(projected, Contract.ai(entity, observer, projected)), "unchanged facts reuse exact identity")
				var before := projected.duplicate(true)
				entity["components"]["cargo"]["passenger_ids"].append(step)
				entity["allowed_gatherer_domains"].append("test")
				check(projected == before, "live nested changes cannot mutate published knowledge")
				if observer > 1:
					check(not projected.has("production_queue") and not projected["components"].has("order"), "foreign production/orders remain private")
					check(not projected["components"]["cargo"].has("passenger_ids") and not projected["components"]["trade"].has("cargo_gold"), "foreign cargo and trade remain private")
				previous = projected
	Contract.native_enabled = false
	check(Contract.ai(entities[0], 1) == Contract.ai_reference(entities[0], 1), "old DLL/GDScript fallback preserves AI facts")
	Contract.native_enabled = true
	world.update_fog_of_war()
	var ai := Player.new({"team": 1, "ai": {"enabled": true}})
	var store := Store.new()
	var preparation := Preparation.new()
	var captured := preparation.capture(world, store, ai, 20, 28)
	for iteration in range(100):
		if not bool(captured.get("pending", false)): break
		captured = preparation.capture(world, store, ai, 20, 28)
	check(not bool(captured.get("pending", false)) and not captured.is_empty(), "preparation completes independently of main scene/UI")
	var options: Dictionary = ai.presentation_options()
	options["defer_build_sites"] = true
	var expected := Task.capture(ai, store.observe_with_queries(world, 20, 1, options), 28)
	check(captured == expected, "explicit preparation interface preserves the old snapshot and fixed target")
	preparation.clear()
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Native AI projection and preparation: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
