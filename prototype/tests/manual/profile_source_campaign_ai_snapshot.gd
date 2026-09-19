extends SceneTree

const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const PerformanceProbe := preload("res://scripts/performance_probe.gd")
const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"


func _initialize() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var probe = PerformanceProbe.new(64)
	for ai_value in game.ai_players:
		var snapshot_started := Time.get_ticks_msec()
		var options: Dictionary = ai_value.presentation_options()
		options["performance_probe"] = probe
		options["performance_prefix"] = "profile.team_%d" % int(ai_value.team)
		var knowledge := SimulationSnapshot.presentation(game.simulation_world, game.game_controller.tick_index, int(ai_value.team), options)
		var snapshot_elapsed := Time.get_ticks_msec() - snapshot_started
		var warm_snapshot_started := Time.get_ticks_msec()
		SimulationSnapshot.presentation(game.simulation_world, game.game_controller.tick_index, int(ai_value.team), options)
		var warm_snapshot_elapsed := Time.get_ticks_msec() - warm_snapshot_started
		var plan_started := Time.get_ticks_msec()
		var commands: Array = ai_value.collect_commands(knowledge, game.game_controller.tick_index + 1)
		var plan_elapsed := Time.get_ticks_msec() - plan_started
		print("team=%d snapshot_cold=%d ms snapshot_warm=%d ms plan=%d ms units=%d buildings=%d resources=%d commands=%d" % [int(ai_value.team), snapshot_elapsed, warm_snapshot_elapsed, plan_elapsed, knowledge.get("units", []).size(), knowledge.get("buildings", []).size(), knowledge.get("resources", []).size(), commands.size()])
	var report: Dictionary = probe.report().get("metrics_microseconds", {})
	for metric_name in report.keys():
		var metric: Dictionary = report[metric_name]
		print("%s p50=%0.3f ms p95=%0.3f ms" % [metric_name, float(metric.get("p50", 0)) / 1000.0, float(metric.get("p95", 0)) / 1000.0])
	game.free()
	quit(0)
