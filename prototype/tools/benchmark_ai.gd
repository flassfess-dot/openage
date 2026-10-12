# Manual measurement harness. Never invoked by tests or project startup.
extends SceneTree
const Settings := preload("res://scripts/skirmish_settings.gd")
const Policy := preload("res://scripts/skirmish_ai_policy.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Ai := preload("res://scripts/ai_player.gd")
const Runtime := preload("res://scripts/ai_runtime_coordinator.gd")
const Decisions := preload("res://scripts/ai_decision_queue.gd")
const Store := preload("res://scripts/ai_observation_store.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const AXES := [
	"seeds",
	"map_type_ids",
	"map_size_ids",
	"resource_preset_ids",
	"starting_age_ids",
	"difficulty_ids",
	"civilization_pairs",
	"opponent_policy_ids",
	"swap_positions"
]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var matrix: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ai/benchmark_matrix.json"))
	var case_index := 0
	var output := "user://ai-benchmark-case-0.json"
	var revision := "unspecified"
	var threaded := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):
			case_index = int(arg.trim_prefix("--case="))
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
		if arg.begins_with("--revision="):
			revision = arg.trim_prefix("--revision=")
		if arg == "--sequential":
			threaded = false
	var total := 1
	for axis in AXES:
		total *= matrix[axis].size()
	if case_index < 0 or case_index >= total:
		push_error("AI benchmark case is outside matrix")
		quit(1)
		return
	var row: Dictionary = {}
	var cursor := case_index
	for axis in AXES:
		row[axis] = matrix[axis][cursor % matrix[axis].size()]
		cursor /= matrix[axis].size()
	var settings := Settings.default_settings()
	settings.merge(
		{
			"seed": row["seeds"],
			"map_type_id": row["map_type_ids"],
			"map_size_id": row["map_size_ids"],
			"resource_preset_id": row["resource_preset_ids"],
			"starting_age_id": row["starting_age_ids"],
			"ai_difficulty_id": row["difficulty_ids"]
		},
		true
	)
	var subject_team := 2 if bool(row["swap_positions"]) else 1
	for slot in settings["players"]:
		slot["enabled"] = int(slot["team"]) <= 2
		slot["controller"] = "ai"
		if int(slot["team"]) <= 2:
			slot["civilization_id"] = row["civilization_pairs"][0 if int(slot["team"]) == subject_team else 1]
	var built := Settings.build(settings)
	if not bool(built.get("valid", false)):
		push_error(str(built.get("errors", [])))
		quit(1)
		return
	var catalog := Catalog.new()
	catalog.load()
	var world := World.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world, built["definition"], built["map_data"])
	world.task_coordinator.enabled = threaded
	var controller := Controller.new(world)
	controller.start_recording(int(settings["seed"]), false)
	controller.set_speed_multiplier(1.0)
	var players: Array = []
	for definition in built["definition"]["players"]:
		var copied: Dictionary = definition.duplicate(true)
		copied["ai"] = Policy.resolve(
			(
				String(matrix["subject_policy_id"])
				if int(definition["team"]) == subject_team
				else String(row["opponent_policy_ids"])
			),
			String(row["difficulty_ids"])
		)
		players.append(Ai.new(copied))
	var runtime := Runtime.new()
	var decisions := Decisions.new()
	runtime.configure(world, controller, players, decisions, Store.new(), world.task_coordinator)
	controller.set_before_fixed_tick(Callable(runtime, "queue_commands"))
	var started := Time.get_ticks_msec()
	var error := ""
	while (
		controller.tick_index < int(matrix["maximum_ticks"])
		and not bool(world.victory_system.result.get("over", false))
	):
		for step in range(20):
			if controller.tick_index >= int(matrix["maximum_ticks"]):
				break
			var previous := controller.tick_index
			controller.advance_frame(0.05, 1, 2)
			if controller.tick_index == previous or bool(world.victory_system.result.get("over", false)):
				break
		if not runtime.error.is_empty() or Time.get_ticks_msec() - started > 3_600_000:
			error = runtime.error if not runtime.error.is_empty() else "measurement_wall_time_limit"
			break
		await process_frame
	var summaries: Array = []
	for ai in players:
		# Drain only once the detached job is no longer active.
		if not decisions.active:
			ai.collect_feedback(controller, controller.tick_index)
		var metrics: Dictionary = ai.strategy.metrics.duplicate(true)
		metrics["idle_worker_ratio"] = float(metrics["idle_worker_ticks"]) / maxf(1.0, float(metrics["worker_ticks"]))
		metrics["command_rejection_ratio"] = (
			float(metrics["commands_rejected"])
			/ maxf(1.0, float(metrics["commands_accepted"] + metrics["commands_rejected"]))
		)
		summaries.append(
			{"team": int(ai.team), "policy_id": ai.economic_policy.get("policy_id", ""), "metrics": metrics}
		)
	var victory: Dictionary = world.victory_system.result.duplicate(true)
	var outcome := (
		"draw"
		if not bool(victory.get("over", false))
		else "win" if subject_team in victory.get("winner_teams", [victory.get("winner_team", -1)]) else "loss"
	)
	var report := {
		"schema_version": 1,
		"case_id": case_index,
		"matrix_sha256": Archive.fingerprint(matrix),
		"case": row,
		"revision": revision,
		"threaded": threaded,
		"subject_team": subject_team,
		"simulation_ticks": controller.tick_index,
		"wall_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"outcome": outcome,
		"victory": victory,
		"players": summaries,
		"error": error
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		error = "measurement_output_unwritable"
	else:
		file.store_string(JSON.stringify(report, "\t"))
	runtime.shutdown()
	world.shutdown_derived_state()
	print("AI measurement case ", case_index, ": ", outcome, "; output=", output)
	quit(0 if error.is_empty() else 1)
