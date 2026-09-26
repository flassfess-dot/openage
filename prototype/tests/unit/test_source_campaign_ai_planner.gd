extends SceneTree

const AiPlayer := preload("res://scripts/ai_player.gd")
const Planner := preload("res://scripts/source_campaign_ai_planner.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_source_attack_timing_and_groups()
	test_source_build_order()
	test_source_building_order()
	test_source_drop_site_distance_limits()
	test_population_support_planning()
	test_source_profile_contract()
	test_build_order_only_profile_does_not_invent_military_rules()
	test_source_documented_noop_is_not_executed()
	test_source_distress_response()
	if failures.is_empty():
		print("I12-020E source campaign AI planner tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_source_attack_timing_and_groups() -> void:
	var snapshot := snapshot_base()
	for id in range(1, 7):
		snapshot["units"].append(fighter(id))
	snapshot["units"].append(worker(99))
	var contract := source_contract()
	var early := Planner.plan_military(snapshot, 19, 2, contract, -1, 0)
	assert_true(not bool(early.get("issued", true)), "source initial attack delay is measured in simulation ticks")
	var wave := Planner.plan_military(snapshot, 20, 2, contract, -1, 0)
	assert_true(bool(wave.get("issued", false)), "source attack begins exactly after its imported delay")
	assert_equal(wave.get("commands", []).size(), 2, "source attack group count is preserved")
	assert_equal(wave.get("commands", [])[0].unit_ids, [1, 2, 3], "first source group respects its maximum size")
	assert_equal(wave.get("commands", [])[1].unit_ids, [4, 5, 6], "second source group receives the remaining fighters")
	assert_equal(wave.get("commands", [])[0].target, Vector2(32, 174), "first source group follows its imported Flare marker")
	assert_equal(wave.get("commands", [])[1].target, Vector2(34, 165), "second source group follows the next imported Flare marker")
	var too_soon := Planner.plan_military(snapshot, 619, 2, contract, 20, 1)
	assert_true(not bool(too_soon.get("issued", true)), "source separation time prevents an early second attack")
	var next_wave := Planner.plan_military(snapshot, 620, 2, contract, 20, 1)
	assert_true(bool(next_wave.get("issued", false)), "source separation time releases the next attack on schedule")
	assert_true(99 not in next_wave.get("commands", [])[0].unit_ids, "workers never enter source military groups")
	assert_equal(Planner.strategic_number_values({"strategic_numbers": [{"source_id": 19, "value": 0}, {"source_id": 19, "value": 1}]}).get(19), 1, "later source strategic-number assignments override earlier values")


func test_source_build_order() -> void:
	var snapshot := snapshot_base()
	for id in range(1, 6):
		snapshot["units"].append(worker(id))
	snapshot["buildings"] = [producer(100, 109, {"research": [{"technology_id": 101, "accepted": true}]})]
	var commands := Planner.plan_economy(snapshot, 1, 2, source_contract())
	assert_equal(commands.size(), 1, "source build order emits one deterministic production command per decision")
	assert_equal(commands[0].command_type(), "research", "completed opening villagers advance to source Tool Age research")
	assert_equal(commands[0].technology, "101", "source technology id survives through the public research command")

	snapshot["player_state"]["researched_technologies"] = [101]
	snapshot["buildings"].append(producer(101, 12, {"train": [{"kind": "slinger", "accepted": true}]}))
	commands = Planner.plan_economy(snapshot, 2, 2, source_contract())
	assert_equal(commands.size(), 1, "source build order advances only after prior steps are complete")
	assert_equal(commands[0].command_type(), "train", "source military unit is queued through the public train command")
	assert_equal(commands[0].unit_type, "slinger", "source DAT unit maps to its explicit runtime alias")
	assert_equal(commands[0].unit_ids, [101], "source unit uses its imported producer type")


func test_source_building_order() -> void:
	var snapshot := snapshot_base()
	var builder := worker(7)
	builder["command_options"] = {"build": [{"kind": "barracks", "accepted": true}]}
	snapshot["units"] = [builder]
	snapshot["build_sites"] = {"barracks": [Vector2(9.5, 8.5)]}
	var contract := {
		"build_order": [
			{"type": "building", "source_opcode": "B", "source_id": 12, "target_count": 1, "producer_source_unit_id": -1, "runtime_alias": "barracks"},
		]
	}
	var commands := Planner.plan_economy(snapshot, 4, 2, contract)
	assert_equal(commands.size(), 1, "source building entry emits one deterministic command")
	assert_equal(commands[0].command_type(), "build", "source building uses the public build command")
	assert_equal(commands[0].building_type, "barracks", "source DAT building maps to its runtime alias")
	assert_equal(commands[0].target, Vector2(9.5, 8.5), "source building uses an authoritative placement candidate")

	snapshot["buildings"] = [{"id": 200, "team": 2, "kind": "barracks", "source_unit_id": 12, "unit_lineage": [12], "pos": Vector2(9.5, 8.5), "hp": 25.0, "state": "foundation", "production_queue": []}]
	commands = Planner.plan_economy(snapshot, 5, 2, contract)
	assert_true(commands.is_empty(), "an existing foundation satisfies the source target count and prevents duplicate construction")


func test_source_drop_site_distance_limits() -> void:
	var snapshot := snapshot_base()
	var builder := worker(7)
	builder["pos"] = Vector2(90, 90)
	builder["command_options"] = {"build": [{"kind": "storage_pit", "accepted": true}, {"kind": "granary", "accepted": true}]}
	snapshot["units"] = [builder]
	snapshot["buildings"] = [producer(100, 109, {})]
	snapshot["buildings"][0]["kind"] = "town_center"
	snapshot["buildings"][0]["pos"] = Vector2(10, 10)
	snapshot["build_sites"] = {
		"storage_pit": [Vector2(89, 90), Vector2(20, 10)],
		"granary": [Vector2(88, 90), Vector2(10, 24)],
	}
	var contract := {
		"strategic_numbers": [{"source_id": 86, "value": 15, "runtime_semantics": "implemented"}],
		"build_order": [{"type": "building", "source_id": 103, "target_count": 1, "producer_source_unit_id": -1, "runtime_alias": "storage_pit"}],
	}
	var commands := Planner.plan_economy(snapshot, 1, 2, contract)
	assert_equal(commands.size(), 1, "storage-pit distance keeps one legal source site")
	assert_equal(commands[0].target, Vector2(20, 10), "storage pit cannot use the closer worker-side site beyond its Town Center limit")
	contract = {
		"strategic_numbers": [{"source_id": 87, "value": 15, "runtime_semantics": "implemented"}],
		"build_order": [{"type": "building", "source_id": 68, "target_count": 1, "producer_source_unit_id": -1, "runtime_alias": "granary"}],
	}
	commands = Planner.plan_economy(snapshot, 2, 2, contract)
	assert_equal(commands.size(), 1, "granary distance keeps one legal source site")
	assert_equal(commands[0].target, Vector2(10, 24), "granary uses its independent source maximum distance")
	contract["strategic_numbers"][0]["value"] = 5
	commands = Planner.plan_economy(snapshot, 3, 2, contract)
	assert_true(commands.is_empty(), "drop-site order waits when every candidate violates the source distance")


func test_source_profile_contract() -> void:
	var player = AiPlayer.new({
		"team": 2,
		"source_ai": source_contract(),
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 20},
	})
	assert_true(player.needs_decision(1), "source campaign AI requests its first decision")
	var options: Dictionary = player.presentation_options()
	assert_true(bool(options.get("compact_entities", false)), "source profile requests compact entity projections")
	assert_true(not bool(options.get("include_navigation", true)) and not bool(options.get("include_fog_cells", true)), "source profile omits unused large map arrays")
	assert_true(not bool(options.get("include_worker_command_options", true)) and bool(options.get("requested_production_only", false)), "source profile requests only contract production checks")
	assert_equal(options.get("production_requests", []).size(), 3, "source profile forwards only its imported build-order entries")
	assert_equal(options.get("requested_build_site_kinds", []), ["house"], "source profile requests only the housing site it can consume")

	var building_contract := source_contract()
	building_contract["build_order"].append({"type": "building", "source_id": 12, "target_count": 1, "producer_source_unit_id": -1, "runtime_alias": "barracks"})
	var building_player = AiPlayer.new({
		"team": 2,
		"source_ai": building_contract,
		"ai": {"enabled": true, "profile": "source_campaign_v1"},
	})
	var building_options: Dictionary = building_player.presentation_options()
	assert_equal(building_options.get("production_requests", []).size(), 3, "building entries do not pollute producer option requests")
	assert_equal(building_options.get("requested_build_site_kinds", []), ["house", "barracks"], "building entries request only their named authoritative site kinds")


func test_build_order_only_profile_does_not_invent_military_rules() -> void:
	var contract := source_contract()
	contract["runtime_support"] = {"economy_enabled": true, "build_order_enabled": true, "military_enabled": false}
	var player = AiPlayer.new({
		"team": 2,
		"source_ai": contract,
		"ai": {"enabled": true, "profile": "source_campaign_v1", "economic_interval_ticks": 20, "military_interval_ticks": 20},
	})
	var snapshot := snapshot_base()
	snapshot["units"] = [fighter(1), fighter(2)]
	var commands: Array = player.collect_commands(snapshot, 1)
	assert_true(commands.is_empty(), "build-order-only source profile does not invent an attack without source military rules")
	assert_equal(player.last_military_tick, -1, "disabled source military planner remains explicitly inactive")
	assert_true(not player.needs_decision(2), "disabled military cadence does not force a build-order-only AI decision every tick")


func test_source_documented_noop_is_not_executed() -> void:
	var snapshot := snapshot_base()
	for id in range(1, 7):
		snapshot["units"].append(fighter(id))
	var contract := {
		"strategic_numbers": [
			{"source_id": 16, "value": 3, "runtime_semantics": "implemented"},
			{"source_id": 26, "value": 15, "runtime_semantics": "source_documented_noop"},
			{"source_id": 36, "value": 1, "runtime_semantics": "implemented"},
			{"source_id": 46, "value": 30, "runtime_semantics": "implemented"},
			{"source_id": 104, "value": 0, "runtime_semantics": "implemented"},
		],
		"target_markers": [{"source_unit_id": 112, "position": Vector2(12, 12)}],
	}
	var wave := Planner.plan_military(snapshot, 1, 2, contract, -1, 0)
	assert_true(bool(wave.get("issued", false)), "implemented source attack settings still issue a wave")
	assert_equal(wave.get("commands", []).size(), 1, "source-documented no-op does not suppress the attack")
	assert_equal(wave.get("commands", [])[0].unit_ids, [1, 2, 3], "unused maximum group size cannot alter the implemented minimum-size fallback")
	assert_true(4 not in wave.get("commands", [])[0].unit_ids, "fighters beyond the implemented fallback stay outside the source group")


func test_source_distress_response() -> void:
	var snapshot := snapshot_base()
	var distressed := fighter(1)
	distressed["pos"] = Vector2(10, 10)
	var first := fighter(2)
	first["pos"] = Vector2(11, 10)
	var second := fighter(3)
	second["pos"] = Vector2(12, 10)
	var third := fighter(4)
	third["pos"] = Vector2(13, 10)
	var fourth := fighter(5)
	fourth["pos"] = Vector2(14, 10)
	var busy := fighter(6)
	busy["pos"] = Vector2(10, 11)
	busy["task"] = "attack"
	var far := fighter(7)
	far["pos"] = Vector2(30, 30)
	var enemy := fighter(90)
	enemy["team"] = 3
	enemy["pos"] = Vector2(10.5, 9.5)
	snapshot["units"] = [distressed, first, second, third, fourth, busy, far, worker(99), enemy]
	snapshot["ai_distress_signals"] = [{
		"sequence": 7,
		"target_team": 2,
		"target_id": 1,
		"attacker_team": 3,
		"attacker_id": 90,
		"position": Vector2(10, 10),
	}]
	var contract := source_contract()
	contract["strategic_numbers"].append_array([
		{"source_id": 19, "value": 50, "runtime_semantics": "implemented"},
		{"source_id": 20, "value": 6, "runtime_semantics": "implemented"},
		{"source_id": 48, "value": 3, "runtime_semantics": "implemented"},
	])
	var response := Planner.plan_response(snapshot, 100, 2, contract, -1)
	assert_true(bool(response.get("issued", false)), "source distress signal produces a response")
	assert_equal(response.get("commands", []).size(), 1, "one distress call produces one group response")
	assert_equal(response.get("commands", [])[0].unit_ids, [2, 3], "source percentage selects the nearest deterministic fraction of idle troops")
	assert_equal(response.get("commands", [])[0].target_unit_id, 90, "responders attack the visible distress source")
	assert_equal(response.get("signal_sequence", -1), 7, "response identifies the exact source distress signal")
	var excluded: Dictionary = {}
	for unit_id in response.get("unit_ids", []):
		excluded[int(unit_id)] = true
	var wave := Planner.plan_military(snapshot, 100, 2, contract, -1, 0, excluded)
	assert_true(wave.get("commands", []).all(func(command): return 2 not in command.unit_ids and 3 not in command.unit_ids), "distress responders cannot receive a conflicting scheduled attack")
	assert_true(not bool(Planner.plan_response(snapshot, 159, 2, contract, 100).get("issued", true)), "response separation suppresses subsequent distress calls for the source interval")
	assert_true(bool(Planner.plan_response(snapshot, 160, 2, contract, 100).get("issued", false)), "response separation expires exactly on the source tick")
	contract["strategic_numbers"].append({"source_id": 19, "value": 5, "runtime_semantics": "implemented"})
	assert_true(not bool(Planner.plan_response(snapshot, 200, 2, contract, -1).get("issued", true)), "source response percentage uses integer troop allocation without inventing a minimum responder")


func test_population_support_planning() -> void:
	var snapshot := snapshot_base()
	snapshot["player_state"].merge({"population": 7, "population_reserved": 0, "population_cap": 8, "population_limit": 75}, true)
	var builder := worker(7)
	builder["command_options"] = {"build": [{"kind": "house", "accepted": true}]}
	snapshot["units"] = [builder]
	snapshot["build_sites"] = {"house": [Vector2(10.5, 10.5)]}
	var commands := Planner.plan_economy(snapshot, 3, 2, {"build_order": []})
	assert_equal(commands.size(), 1, "housing pressure commits one worker without issuing a conflicting gather order")
	assert_equal(commands[0].command_type(), "build", "source economy expands housing through the public build command")
	assert_equal(commands[0].building_type, "house", "source economy requests the RoR House archetype")
	assert_equal(commands[0].target, Vector2(10.5, 10.5), "source economy uses an authoritative local placement candidate")
	snapshot["player_state"]["population_points"] = 13
	assert_equal(Planner.plan_economy(snapshot, 4, 2, {"build_order": []}).size(), 0, "source economy uses exact half-population pressure")
	snapshot["buildings"] = [{"id": 40, "team": 2, "kind": "barracks", "hp": 350.0, "state": "complete", "production_queue": [{"status": "blocked_population"}]}]
	var blocked_commands := Planner.plan_economy(snapshot, 5, 2, {"build_order": []})
	assert_equal(blocked_commands.size(), 1, "blocked producer restores source housing priority")
	assert_equal(blocked_commands[0].command_type(), "build", "blocked production does not enqueue a duplicate training order")


func source_contract() -> Dictionary:
	return {
		"schema_version": 1,
		"status": "normalized",
		"strategic_numbers": [
			{"source_id": 36, "value": 2},
			{"source_id": 16, "value": 2},
			{"source_id": 26, "value": 3},
			{"source_id": 46, "value": 30},
			{"source_id": 104, "value": 1},
		],
		"build_order": [
			{"type": "unit", "source_id": 83, "target_count": 5, "producer_source_unit_id": 109, "runtime_alias": "villager"},
			{"type": "technology", "source_id": 101, "target_count": 1, "producer_source_unit_id": 109},
			{"type": "unit", "source_id": 347, "target_count": 50, "producer_source_unit_id": 12, "runtime_alias": "slinger"},
		],
		"target_markers": [
			{"source_unit_id": 112, "position": Vector2(32, 174)},
			{"source_unit_id": 112, "position": Vector2(34, 165)},
		],
	}


func snapshot_base() -> Dictionary:
	return {
		"observer_team": 2,
		"map_size": Vector2i(250, 250),
		"player_state": {"team": 2, "status": "active", "researched_technologies": []},
		"units": [],
		"buildings": [],
		"resources": [],
	}


func fighter(id: int) -> Dictionary:
	return {"id": id, "team": 2, "kind": "slinger", "source_unit_id": 347, "pos": Vector2(4 + id, 5), "hp": 25.0, "task": "idle", "combat_enabled": true, "behavior_tags": ["combatant"], "components": {"worker": {"enabled": false}}}


func worker(id: int) -> Dictionary:
	return {"id": id, "team": 2, "kind": "villager", "source_unit_id": 83, "unit_lineage": [83], "pos": Vector2(4 + id, 4), "hp": 25.0, "task": "idle", "combat_enabled": false, "components": {"worker": {"enabled": true}}}


func producer(id: int, source_unit_id: int, command_options: Dictionary) -> Dictionary:
	return {"id": id, "team": 2, "kind": "producer", "source_unit_id": source_unit_id, "unit_lineage": [source_unit_id], "pos": Vector2(8, 8), "hp": 100.0, "state": "complete", "production_queue": [], "command_options": command_options}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
