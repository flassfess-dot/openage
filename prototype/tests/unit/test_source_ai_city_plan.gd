extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const CityPlan := preload("res://scripts/source_ai_city_plan.gd")
const Planner := preload("res://scripts/source_campaign_ai_planner.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_deterministic_geometry_and_round_trip()
	test_wall_gap_and_city_envelope_filtering()
	test_ai_owns_and_presents_persistent_plan()
	if failures.is_empty():
		print("I12-020L source AI city plan tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_deterministic_geometry_and_round_trip() -> void:
	var plan = CityPlan.new(2)
	var snapshot := base_snapshot()
	var buildings := [town_center()]
	plan.synchronize(snapshot, [worker()], buildings, city_numbers())
	assert_true(plan.initialized and plan.enabled, "source numbers initialize one persistent city plan")
	assert_equal(plan.anchor_entity_id, 100, "lowest-id living Town Center anchors the plan")
	assert_equal(plan.center, Vector2(20.5, 20.5), "source city plan retains its world center")
	assert_equal(plan.perimeter_cells.size(), 40, "radius-five square perimeter has one deterministic 40-cell traversal")
	assert_equal(plan.gate_cells.size(), 6, "two three-cell source gates remove exactly six wall cells")
	assert_equal(plan.wall_cells.size(), 34, "wall cells exclude every planned gate cell")
	assert_true(plan.gate_cells.all(func(cell): return cell not in plan.wall_cells), "gate and wall cells never overlap")
	var restored = CityPlan.from_state(plan.canonical_state())
	assert_equal(restored.canonical_state(), plan.canonical_state(), "city plan survives an exact dictionary round trip")
	var old_center: Vector2 = restored.center
	var old_revision: int = restored.revision
	buildings[0]["hp"] = 0.0
	restored.synchronize(snapshot, [worker()], buildings, city_numbers())
	assert_equal(restored.center, old_center, "destroying the anchor does not silently move an established city")
	assert_equal(restored.revision, old_revision, "unchanged source constraints do not rebuild persistent geometry")


func test_wall_gap_and_city_envelope_filtering() -> void:
	var snapshot := base_snapshot()
	var builder := worker()
	var buildings := [town_center()]
	var plan = CityPlan.new(2)
	plan.synchronize(snapshot, [builder], buildings, city_numbers())
	var gate_site := Vector2(plan.gate_cells[0]) + Vector2(0.5, 0.5)
	var wall_site := Vector2(plan.wall_cells[0]) + Vector2(0.5, 0.5)
	assert_equal(plan.filter_sites([gate_site, wall_site], "wall"), [wall_site], "wall planner leaves the planned source-sized passage open")
	assert_equal(plan.filter_sites([Vector2(22.5, 20.5), Vector2(30.5, 20.5)], "barracks"), [Vector2(22.5, 20.5)], "core city buildings remain inside the maximum town envelope")
	assert_equal(plan.filter_sites([Vector2(40.5, 20.5)], "storage_pit"), [Vector2(40.5, 20.5)], "resource drop sites keep their independent source distance policy")

	snapshot["units"] = [builder]
	snapshot["buildings"] = buildings
	snapshot["build_sites"] = {"wall": [gate_site, wall_site]}
	var contract := {
		"strategic_numbers": city_number_entries(),
		"build_order": [{"type": "building", "source_id": 72, "target_count": 1, "runtime_alias": "wall"}],
	}
	var commands := Planner.plan_economy(snapshot, 1, 2, contract, plan)
	assert_equal(commands.size(), 1, "planned wall segment uses the normal economy command path")
	if not commands.is_empty():
		assert_equal(commands[0].command_type(), "build", "city plan emits an ordinary BuildCommand")
		assert_equal(commands[0].target, wall_site, "a gate cell is never selected even when it appears first")


func test_ai_owns_and_presents_persistent_plan() -> void:
	var contract := {
		"strategic_numbers": city_number_entries(),
		"build_order": [{"type": "building", "source_id": 72, "target_count": 1, "runtime_alias": "wall"}],
		"runtime_support": {"military_enabled": false},
	}
	var player = AiPlayer.new({
		"team": 2,
		"source_ai": contract,
		"ai": {"enabled": true, "profile": "source_campaign_v1"},
	})
	player.source_city_plan.synchronize(base_snapshot(), [worker()], [town_center()], city_numbers())
	var state := player.canonical_state()
	var restored = AiPlayer.new({
		"team": 2,
		"source_ai": contract,
		"ai": {"enabled": true, "profile": "source_campaign_v1"},
	})
	assert_true(restored.restore_state(state), "AI accepts its own serialized city plan")
	assert_equal(restored.source_city_plan.canonical_state(), player.source_city_plan.canonical_state(), "AI restore keeps exact wall and gate geometry")
	var options: Dictionary = restored.presentation_options()
	assert_true("wall" in options.get("strict_preferred_build_site_kinds", []), "snapshot requests only planned cells for wall construction")
	assert_equal(options.get("preferred_build_sites", {}).get("wall", []).size(), player.source_city_plan.wall_cells.size(), "all planned wall cells reach authoritative placement validation")


func base_snapshot() -> Dictionary:
	return {
		"observer_team": 2,
		"map_size": Vector2i(64, 64),
		"units": [],
		"buildings": [],
		"resources": [],
		"build_sites": {},
		"player_state": {
			"population": 1,
			"population_reserved": 0,
			"population_cap": 10,
			"population_limit": 50,
			"researched_technologies": [],
		},
	}


func worker() -> Dictionary:
	return {
		"id": 1,
		"team": 2,
		"kind": "villager",
		"pos": Vector2(20.5, 20.5),
		"hp": 25.0,
		"task": "idle",
		"movement_domain": "land",
		"components": {"worker": {"enabled": true}},
		"command_options": {"build": [{"kind": "wall", "accepted": true}]},
	}


func town_center() -> Dictionary:
	return {
		"id": 100,
		"team": 2,
		"kind": "town_center",
		"source_unit_id": 109,
		"unit_lineage": [109],
		"pos": Vector2(20.5, 20.5),
		"hp": 600.0,
		"state": "complete",
		"production_queue": [],
	}


func city_numbers() -> Dictionary:
	return {73: 3, 74: 5, 84: 2, 85: 3}


func city_number_entries() -> Array:
	return [
		{"source_id": 73, "value": 3, "runtime_semantics": "implemented"},
		{"source_id": 74, "value": 5, "runtime_semantics": "implemented"},
		{"source_id": 84, "value": 2, "runtime_semantics": "implemented"},
		{"source_id": 85, "value": 3, "runtime_semantics": "implemented"},
	]


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
