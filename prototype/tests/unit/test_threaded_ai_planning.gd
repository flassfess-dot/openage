extends SceneTree
const Ai := preload("res://scripts/ai_player.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const Replay := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var coordinator := Coordinator.new()
	var players: Array = []
	var inputs: Array = []
	var expected: Array = []
	var codec := Replay.new()
	for team in [1, 2]:
		var definition := {"team": team, "ai": {"economic_interval_ticks": 5, "military_interval_ticks": 7, "formation": "WEDGE"}}
		var ai := Ai.new(definition)
		var snapshot := {"observer_team": team, "map_size": Vector2i(24, 24), "player_state": {"team": team, "allies": [team]}, "units": [{"id": team * 10, "team": team, "kind": "villager", "hp": 25.0, "pos": Vector2(4, 4), "task": "idle", "movement_domain": "land", "components": {"worker": {"enabled": true}, "movement": {"domain": "land"}}}], "buildings": [], "resources": [{"id": 80, "kind": "berries", "pos": Vector2(5, 4), "amount": 100}]}
		var input := Task.capture(ai, snapshot, 1)
		var records: Array = []
		for command in ai.collect_commands(snapshot, 1):
			records.append({"tick": command.tick, "type": command.command_type(), "unit_ids": command.unit_ids, "params": codec.encode_variant(command.params, false)})
		expected.append({"commands": records, "state": ai.canonical_state()})
		players.append(ai)
		inputs.append(input)
	var outputs := coordinator.run_ordered("ai_planning", inputs, Task.run, 1)
	for index in range(outputs.size()):
		check(outputs[index]["commands"] == expected[index]["commands"], "commands and tick match sequential planner")
		check(outputs[index]["state"] == expected[index]["state"], "all planner state is preserved")
		check(Task.decode_commands(outputs[index]).size() == expected[index]["commands"].size(), "command serialization is complete")
		check(not players[index].needs_decision(2), "cadence survives planning")
	inputs[0]["definition"]["ai"]["enabled"] = false
	check(Task.run(inputs[0])["commands"].is_empty(), "disabled player emits no proposal")
	var defeated: Dictionary = inputs[1].duplicate(true)
	defeated["snapshot"]["player_state"]["status"] = "defeated"
	check(Task.run(defeated)["commands"].is_empty(), "defeated player emits no proposal")
	coordinator.shutdown()
	finish()
