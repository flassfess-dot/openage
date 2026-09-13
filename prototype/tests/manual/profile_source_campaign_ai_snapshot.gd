extends SceneTree

const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"


func _initialize() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	for ai_value in game.ai_players:
		var snapshot_started := Time.get_ticks_msec()
		var knowledge := SimulationSnapshot.presentation(game.simulation_world, game.game_controller.tick_index, int(ai_value.team), ai_value.presentation_options())
		var snapshot_elapsed := Time.get_ticks_msec() - snapshot_started
		var plan_started := Time.get_ticks_msec()
		var commands: Array = ai_value.collect_commands(knowledge, game.game_controller.tick_index + 1)
		var plan_elapsed := Time.get_ticks_msec() - plan_started
		print("team=%d snapshot=%d ms plan=%d ms units=%d buildings=%d resources=%d commands=%d" % [int(ai_value.team), snapshot_elapsed, plan_elapsed, knowledge.get("units", []).size(), knowledge.get("buildings", []).size(), knowledge.get("resources", []).size(), commands.size()])
	game.free()
	quit(0)
