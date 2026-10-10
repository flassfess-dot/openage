class_name RoRMatchLifecycleService
extends RefCounted
const Archive := preload("res://scripts/game_save_archive.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Decisions := preload("res://scripts/ai_decision_queue.gd")
const SoundHistory := preload("res://scripts/sound_cue_history.gd")
const Data := preload("res://scripts/isolated_task_data.gd")

func restore(path: String, new_world: Callable, new_players: Callable, configure_cadence: Callable, capture_ai: Callable, inspected: Dictionary = {}) -> Dictionary:
	var loaded: Dictionary = Archive.read(path) if inspected.is_empty() else inspected
	if not bool(loaded.get("valid", false)): return {"error": String(loaded.get("error", "archive_invalid"))}
	var archive: Dictionary = loaded["archive"]
	var blob: Dictionary = archive["checkpoint"]
	if String(archive["state_sha256"]) != String(blob["sha256"]): return {"error": "checkpoint_invalid"}
	var checkpoint: Dictionary = Checkpoint.unpack(blob)
	if checkpoint.is_empty(): return {"error": "checkpoint_invalid"}
	var definition: Dictionary = checkpoint["match_definition"]
	var map: Dictionary = checkpoint["map_definition"]
	if Archive.fingerprint(definition) != String(archive["match_fingerprint"]): return {"error": "match_fingerprint_mismatch"}
	var world = new_world.call(map["size"])
	var controller = Controller.new(world)
	if not Checkpoint.restore(checkpoint, world, controller) or int(controller.tick_index) != int(archive["tick"]): return _failed(world, "checkpoint_invalid")
	if not controller.install_recording_history(archive["replay"], false): return _failed(world, "recording_history_invalid")
	var players: Array = new_players.call(definition)
	configure_cadence.call(players)
	var states := {}
	for state in archive["ai_states"]: states[int(state["team"])] = state
	for ai in players:
		if not states.has(int(ai.team)) or not ai.restore_state(states[int(ai.team)]): return _failed(world, "ai_state_invalid:%d" % int(ai.team))
	var decisions := Decisions.new()
	var saved_controller: Dictionary = archive["controller_state"]
	if not saved_controller.get("ai_decisions", {}) is Dictionary or not decisions.restore_state(saved_controller.get("ai_decisions", {}), players, controller.tick_index, capture_ai): return _failed(world, "ai_decision_state_invalid")
	var sound_history := SoundHistory.new()
	if not sound_history.restore_state(archive["view_state"]["sound_cue_history"], int(archive["tick"])): return _failed(world, "sound_cue_history_invalid")
	return {"error": "", "archive": archive, "world": world, "controller": controller, "definition": definition, "map": map, "players": players, "decisions": decisions, "sound_history": sound_history}

func _failed(world, error: String) -> Dictionary:
	world.shutdown_derived_state()
	return {"error": error}

func capture_save(world, controller, players: Array, decisions, path: String, slot_name: String, match_path: String, definition: Dictionary, map: Dictionary, view: Dictionary, runtime: Dictionary) -> Dictionary:
	var ai_states: Array = []
	for ai in players: ai_states.append(ai.canonical_state())
	runtime = runtime.duplicate()
	runtime["ai_decisions"] = decisions.canonical_state()
	# Capture one detached checkpoint at the completed source boundary. Its
	# checksum, compression and archive encoding belong to the save worker.
	var checkpoint: Dictionary = Checkpoint.capture(world, controller, definition, map)
	return {"path": path, "slot_name": slot_name, "match_path": match_path, "definition": Data.copy(definition), "tick": controller.tick_index, "state_hash": "", "replay": Data.copy(controller.replay_recorder.to_dictionary()), "ai_states": Data.copy(ai_states), "view": Data.copy(view), "controller": Data.copy(runtime), "checkpoint": checkpoint}
