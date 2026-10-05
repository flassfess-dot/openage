extends RefCounted

# Scene input tests must wait for actual navigation publication, not a fixed
# number of frames. Keep the loading/input barrier enabled in these fixtures.
static func wait_for_ready(tree: SceneTree, game: Node, timeout_msec: int = 30000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while game.navigation_loading.is_loading():
		if not game.is_processing() or Time.get_ticks_msec() >= deadline:
			push_error("Match navigation did not become ready before input assertions")
			return false
		await tree.process_frame
	return true
