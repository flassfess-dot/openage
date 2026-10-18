extends RefCounted

# Scene input tests must wait for actual navigation publication, not a fixed
# number of frames. Keep the loading/input barrier enabled in these fixtures.
static func wait_for_ready(tree: SceneTree, game: Node, timeout_msec: int = 30000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	if not game.is_node_ready():
		await game.ready
	while game.navigation_loading.is_loading():
		if not game.is_processing() or Time.get_ticks_msec() >= deadline:
			push_error("Match navigation did not become ready before input assertions")
			return false
		await tree.process_frame
	if game.has_method("join_simulation_owner"): game.join_simulation_owner()
	return true

# Background preparation can yield without advancing a fixed tick. Tests must
# measure simulated time, while allowing the frame loop to publish worker work.
static func advance_to_tick(tree: SceneTree, controller, target_tick: int, player_team: int, enemy_team: int, timeout_msec: int = 30000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while controller.tick_index < target_tick:
		if Time.get_ticks_msec() >= deadline:
			push_error("Simulation did not reach tick %d (current %d)" % [target_tick, controller.tick_index])
			return false
		controller.advance_frame(controller.FIXED_STEP_SECONDS, player_team, enemy_team)
		if controller.preparation_waiting:
			await tree.process_frame
	return true
