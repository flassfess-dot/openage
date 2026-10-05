extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Queue := preload("res://scripts/background_save_queue.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var world = World.new(Vector2i(16, 16))
	var controller := Controller.new(world)
	controller.start_recording(41721, false)
	var definition := {"id": "threaded-save", "players": [{"team": 1, "civilization_id": 13}]}
	var codec := Replay.new()
	var path := "res://qa/threaded-save-queue.json"
	var input := {"path": path, "slot_name": "First", "match_path": "res://data/matches/prototype_match.json", "definition": definition, "tick": controller.tick_index, "state_hash": codec.world_state_hash(world, controller.tick_index, controller), "replay": controller.replay_recorder.to_dictionary(), "ai_states": [], "view": {"selection": []}, "controller": {"paused": false, "speed": 1.0}, "checkpoint": Data.copy(Checkpoint.capture(world, controller, definition, {"size": Vector2i(16, 16)}))}
	var queue := Queue.new()
	check(queue.enqueue(Data.copy(input)), "first save accepted")
	var second: Dictionary = Data.copy(input)
	second["slot_name"] = "Second"
	check(queue.enqueue(second), "same-slot saves queue in order")
	check(not queue.enqueue(Data.copy(input)), "save queue cannot grow without bound")
	world.add_unit(1, "villager", Vector2(8, 8), false)
	var results := queue.drain()
	check(results.size() == 2 and results.all(func(result): return int(result["error"]) == OK), "all writes complete before success")
	var loaded := Archive.read(path)
	check(bool(loaded.get("valid", false)), "completed save is readable")
	if bool(loaded.get("valid", false)):
		check(loaded["archive"]["metadata"]["slot_name"] == "Second", "same-slot order is stable")
		var checkpoint := Checkpoint.unpack(loaded["archive"]["checkpoint"])
		check(checkpoint["world"]["units"].is_empty(), "live changes do not alter captured checkpoint")
	check(not queue.enqueue({"object": RefCounted.new()}), "shared-object capture rejected")
	queue.shutdown()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	finish()
