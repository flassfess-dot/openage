extends SceneTree

const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.configure_players([
		{"team": 1, "controller": "human"},
		{"team": 2, "controller": "ai"},
		{"team": 3, "controller": "ai"},
	])
	world.reset_game(false)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(3, 3), false)
	var second: Dictionary = world.add_unit(2, "clubman", Vector2(10, 10), false)
	var third: Dictionary = world.add_unit(3, "clubman", Vector2(15, 15), false)
	assert_equal(world.conquest_counts_by_team.get(1), 1, "unit creation increments conquest presence")
	assert_true(world.transfer_entity_ownership(second, 1), "conversion path transfers a live unit")
	assert_equal(world.conquest_counts_by_team.get(1), 2, "conversion adds the new owner's presence")
	assert_equal(world.conquest_counts_by_team.get(2), 0, "conversion removes the old owner's presence")
	world.begin_death(third)
	assert_equal(world.conquest_counts_by_team.get(3), 0, "death removes conquest presence immediately")
	world.check_battle_state(1, 2, 0.05)
	assert_equal(world.get_victory_result().get("winner_team"), 1, "fixed-tick conquest resolves from the indexed presence")
	assert_equal(world.get_victory_result().get("reason"), "conquest", "indexed outcome keeps the authoritative reason")

	var wonder: Dictionary = world.add_victory_object("wonder", Vector2(6, 6), 1, true)
	assert_equal(world.victory_system.objective_summary.get("wonder", {}).get("completed_by_team", {}).get(1), 1, "completed Wonder increments indexed objective count")
	world.set_victory_object_completed(int(wonder["id"]), false)
	assert_equal(world.victory_system.objective_summary.get("wonder", {}).get("completed_by_team", {}).get(1), 0, "unfinished Wonder loses completed count")
	world.set_victory_object_owner(int(wonder["id"]), 2)
	assert_equal(world.victory_system.objective_summary.get("wonder", {}).get("by_team", {}).get(2), 1, "objective conversion updates the owner index")
	world.remove_victory_object(int(wonder["id"]))
	assert_equal(world.victory_system.objective_summary.get("wonder", {}).get("by_team", {}).get(2), 0, "destroyed objective leaves the active owner index")
	assert_equal(world.victory_system.objective_summary.get("wonder", {}).get("total"), 0, "destroyed objective leaves the active victory target count")
	assert_true(float(first.get("hp", 0.0)) > 0.0, "winning side remains present")
	finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P07 incremental victory presence passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
