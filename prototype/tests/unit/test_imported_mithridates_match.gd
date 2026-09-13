extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")

const MATCH_PATH := "res://assets/generated/matches/mithridates.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	assert_true(bool(definition.get("valid", false)), "Mithridates match validates: %s" % [definition.get("errors", [])])
	assert_equal(String(definition.get("id", "")), "campaign_mithridates", "stable runtime id survives conversion")
	assert_equal(String(definition.get("title", "")), "Митридат", "source mission title survives conversion")
	assert_equal(definition.get("map", {}).get("size"), Vector2i(200, 200), "source map size survives conversion")
	assert_equal(definition.get("players", []).size(), 5, "all five active source players are present")
	assert_equal(int(definition.get("local_team", -1)), 1, "Roman player remains local")
	assert_equal(int(definition.get("gaps", {}).get("source_object_count", -1)), 9253, "gap ledger owns every source object")
	assert_equal(int(definition.get("gaps", {}).get("runtime_entity_count", -1)), 8487, "all simulation-owned objects enter runtime")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_object_count", -1)), 0, "Mithridates has no unsupported source objects")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_legacy_victory_condition_count", -1)), 0, "Mithridates has no unsupported legacy conditions")
	assert_equal(int(definition.get("gaps", {}).get("source_ai_player_count_pending", -1)), 0, "all four source AI profiles have an executable supported subset")
	assert_equal(int(definition.get("gaps", {}).get("source_settings", {}).get("gap_count", -1)), 0, "Mithridates source settings are completely represented")
	assert_true(definition.get("presentation_environment", []).any(func(item): return String(item.get("asset_name", "")) == "graphic_575"), "last source rock graphic is represented exactly")

	var players: Array = definition.get("players", [])
	assert_equal(players.map(func(player): return int(player.get("starting_age_technology_id", -1))), [103, 102, 103, 103, 103], "all source starting ages survive conversion")
	assert_equal(players.map(func(player): return String(player.get("starting_technology_mode", ""))), ["age_start", "age_start", "post_iron", "age_start", "age_start"], "source Post-Iron semantics remain explicit")
	var disabled_node: Dictionary = players[1].get("disabled_technology_nodes", [])[0]
	assert_equal(int(disabled_node.get("slot", -1)), 14, "source slot 14 restriction survives conversion")
	assert_equal(String(disabled_node.get("node", "")), "town_center", "source slot 14 maps to Town Center")
	assert_equal(int(disabled_node.get("source_object_id", -1)), 109, "Town Center source identity is retained")
	for player_index in [1, 2]:
		var source_ai: Dictionary = players[player_index].get("source_ai", {})
		assert_equal(String(source_ai.get("status", "")), "partial", "build-order-only source AI remains an explicit partial profile")
		assert_true(bool(players[player_index].get("ai", {}).get("enabled", false)), "build-order-only source AI executes its supported economy subset")
		assert_true(not bool(source_ai.get("runtime_support", {}).get("military_enabled", true)), "build-order-only source AI does not invent military rules")
		assert_true(not source_ai.get("build_order", []).is_empty(), "source build order remains available to the runtime planner")
	for player_index in [3, 4]:
		assert_true(bool(players[player_index].get("source_ai", {}).get("runtime_support", {}).get("military_enabled", false)), "source strategic rules enable military planning where present")
	var tactical_ai: Dictionary = players[4]
	var tactical_support: Dictionary = tactical_ai.get("source_ai", {}).get("runtime_support", {})
	var tactical_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == 88)
	assert_equal(tactical_numbers.size(), 1, "Mithridates team 5 retains one source tactical-update setting")
	assert_true(tactical_numbers.size() == 1 and String(tactical_numbers[0].get("runtime_semantics", "")) == "implemented", "source tactical-update frequency is an implemented runtime semantic")
	assert_equal(int(tactical_support.get("tactical_update_interval_ticks", -1)), 40, "source two-second tactical cadence converts through the 20 Hz simulation clock")
	assert_equal(String(tactical_support.get("tactical_update_source", "")), "strategic_number_88", "runtime cadence records its exact source")
	assert_equal(int(tactical_ai.get("ai", {}).get("military_interval_ticks", -1)), 40, "runtime AI consumes the imported tactical cadence")
	assert_true(88 not in tactical_support.get("pending_strategic_number_ids", []), "implemented tactical cadence leaves the parity gap ledger")
	assert_true(bool(tactical_support.get("defence_response_enabled", false)), "Mithridates source profile enables its documented distress response")
	for response_id in [19, 20, 48]:
		var response_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == response_id)
		assert_true(not response_numbers.is_empty() and response_numbers.all(func(entry): return String(entry.get("runtime_semantics", "")) == "implemented"), "response strategic number %d is executable" % response_id)
		assert_true(response_id not in tactical_support.get("pending_strategic_number_ids", []), "response strategic number %d leaves the parity gap ledger" % response_id)
	for lifecycle_id in [30, 31, 49, 91]:
		var lifecycle_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == lifecycle_id)
		assert_true(not lifecycle_numbers.is_empty() and lifecycle_numbers.all(func(entry): return String(entry.get("runtime_semantics", "")) == "implemented"), "attack-group lifecycle strategic number %d is executable" % lifecycle_id)
		assert_true(lifecycle_id not in tactical_support.get("pending_strategic_number_ids", []), "attack-group lifecycle strategic number %d leaves the parity gap ledger" % lifecycle_id)
	for coordination_id in [40, 41, 47]:
		var coordination_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == coordination_id)
		assert_true(not coordination_numbers.is_empty() and coordination_numbers.all(func(entry): return String(entry.get("runtime_semantics", "")) == "implemented"), "attack-group coordination strategic number %d is executable" % coordination_id)
		assert_true(coordination_id not in tactical_support.get("pending_strategic_number_ids", []), "attack-group coordination strategic number %d leaves the parity gap ledger" % coordination_id)
	var commander_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == 75)
	assert_true(commander_numbers.size() == 1 and String(commander_numbers[0].get("runtime_semantics", "")) == "implemented", "group commander selection method is executable")
	assert_true(75 not in tactical_support.get("pending_strategic_number_ids", []), "group commander selection leaves the parity gap ledger")
	for drop_site_id in [86, 87]:
		var drop_site_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == drop_site_id)
		assert_true(drop_site_numbers.size() == 1 and String(drop_site_numbers[0].get("runtime_semantics", "")) == "implemented", "drop-site distance strategic number %d is executable" % drop_site_id)
		assert_true(drop_site_id not in tactical_support.get("pending_strategic_number_ids", []), "drop-site distance strategic number %d leaves the parity gap ledger" % drop_site_id)
	for city_plan_id in [73, 74, 84, 85]:
		var city_plan_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == city_plan_id)
		assert_true(city_plan_numbers.size() == 1 and String(city_plan_numbers[0].get("runtime_semantics", "")) == "implemented", "city/wall plan strategic number %d is executable" % city_plan_id)
		assert_true(city_plan_id not in tactical_support.get("pending_strategic_number_ids", []), "city/wall plan strategic number %d leaves the parity gap ledger" % city_plan_id)
	for naval_id in [58, 59, 60, 61, 62, 63, 67, 68, 69, 70]:
		var naval_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == naval_id)
		assert_true(naval_numbers.size() == 1 and String(naval_numbers[0].get("runtime_semantics", "")) == "implemented", "naval group strategic number %d is executable" % naval_id)
		assert_true(naval_id not in tactical_support.get("pending_strategic_number_ids", []), "naval group strategic number %d leaves the parity gap ledger" % naval_id)
	assert_true(bool(tactical_support.get("naval_attack_enabled", false)), "Mithridates source profile enables its boat attack groups")
	assert_true(bool(tactical_support.get("naval_exploration_enabled", false)), "Mithridates source profile enables its boat exploration group")
	for escort_id in [64, 65, 66]:
		var escort_numbers: Array = tactical_ai.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == escort_id)
		assert_true(escort_numbers.size() == 1 and String(escort_numbers[0].get("runtime_semantics", "")) == "implemented", "escort strategic number %d uses the shared escort lifecycle" % escort_id)
		assert_true(escort_id not in tactical_support.get("pending_strategic_number_ids", []), "escort strategic number %d leaves the parity gap ledger" % escort_id)
	assert_true(not bool(tactical_support.get("naval_escort_enabled", true)), "zero desired escorts do not reserve warboats in Mithridates")
	var lock_entries: Array = []
	for player_value in players:
		lock_entries.append_array(player_value.get("source_ai", {}).get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == 71))
	assert_true(not lock_entries.is_empty() and lock_entries.all(func(entry): return String(entry.get("runtime_semantics", "")) == "pending"), "ambiguous lock attack/response semantics remains explicitly pending")
	assert_equal(int(players[3].get("ai", {}).get("military_interval_ticks", -1)), 20, "profiles without strategic number 88 keep the existing one-second fallback cadence")
	assert_equal(String(players[3].get("source_ai", {}).get("runtime_support", {}).get("tactical_update_source", "")), "runtime_fallback", "fallback cadence remains distinguishable from source evidence")

	var participants: Array = definition.get("scenario_definition", {}).get("participants", [])
	assert_equal(participants.size(), 1, "single source objective participant is normalized")
	var condition: Dictionary = participants[0].get("groups", [])[0].get("conditions", [])[0]
	assert_equal(String(condition.get("type", "")), "destroy_object", "Roman objective retains exact destroy-object semantics")
	assert_equal(int(condition.get("target_scenario_object_id", -1)), 10755, "Roman objective targets exact scenario object 10755")
	assert_equal(int(condition.get("target_source_unit_id", -1)), 276, "Roman objective targets the source Wonder")
	assert_equal(int(condition.get("target_team", -1)), 3, "source Wonder ownership survives conversion")
	var targets: Array = definition.get("entities", []).filter(func(entity): return int(entity.get("scenario_object_id", -1)) == 10755)
	assert_equal(targets.size(), 1, "exact Wonder target exists once")
	assert_true(targets.size() == 1 and String(targets[0].get("kind", "")) == "wonder", "exact target resolves to the shared Wonder archetype")
	assert_equal(definition.get("victory_rules", []).map(func(rule): return String(rule.get("type", ""))), ["scenario_definition", "conquest"], "source custom objective coexists with global Conquest")

	if failures.is_empty():
		print("I12-020K imported Mithridates match contract tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
