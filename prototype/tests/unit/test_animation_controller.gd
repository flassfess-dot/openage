extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_all_states_and_clips()
	test_transition_starts_at_frame_zero()
	test_shared_attack_clip_is_continuous_and_restartable()
	test_simulation_attack_phases()

	if failures.is_empty():
		print("R-005 animation controller tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_all_states_and_clips() -> void:
	assert_equal(AnimationController.ALL_STATES.size(), 13, "all required states")
	assert_equal(AnimationController.clip_for_state(AnimationController.ATTACK_WINDUP), "attack", "attack windup clip")
	assert_equal(AnimationController.clip_for_state(AnimationController.ATTACK_RECOVER), "attack", "attack recover clip")
	assert_equal(AnimationController.state_for_task("gather", false), AnimationController.GATHER, "gather state")
	assert_equal(AnimationController.state_for_task("heal", false), AnimationController.HEAL, "healing state")
	assert_equal(AnimationController.clip_for_state(AnimationController.HEAL), "heal", "healing clip")
	assert_equal(AnimationController.state_for_task("carry", true), AnimationController.MOVE, "moving state has priority")


func test_transition_starts_at_frame_zero() -> void:
	var unit := {"anim_state": AnimationController.IDLE, "anim": 4.0}
	var changed := AnimationController.update(unit, AnimationController.MOVE, 0.05)
	assert_equal(changed, true, "state transition reported")
	assert_equal(unit["anim"], 0.0, "new state starts at time zero")
	AnimationController.update(unit, AnimationController.MOVE, 0.05)
	assert_equal(unit["anim"], 0.05, "unchanged state advances time")


func test_shared_attack_clip_is_continuous_and_restartable() -> void:
	var unit := {"anim_state": AnimationController.ATTACK_WINDUP, "anim": 0.4, "animation_events_fired": {"damage_frame": true}}
	AnimationController.update(unit, AnimationController.ATTACK_RECOVER, 0.05)
	assert_float(float(unit["anim"]), 0.45, "windup to recover keeps one continuous attack clip")
	assert_equal(unit["animation_events_fired"].get("damage_frame"), true, "phase transition does not re-fire action event")
	AnimationController.update(unit, AnimationController.ATTACK_WINDUP, 0.05, true)
	assert_equal(unit["anim"], 0.0, "next attack cycle explicitly restarts clip")
	assert_equal(unit["animation_events_fired"], {}, "next attack cycle resets frame events")


func test_simulation_attack_phases() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(4.5, 4.0), false)
	attacker["attack_period"] = 1.0
	world.assign_command_attack([attacker], target["id"])
	world.advance(0.05, 1, 2)
	assert_equal(attacker["anim_state"], AnimationController.ATTACK_WINDUP, "ready attack enters windup")
	assert_equal(attacker["anim"], 0.0, "windup begins at zero")
	world.advance(0.05, 1, 2)
	assert_equal(attacker["anim_state"], AnimationController.ATTACK_RECOVER, "cooldown enters recovery")
	assert_float(float(attacker["anim"]), 0.05, "recovery continues the same attack clip")
	var recovery_history_size: int = attacker.get("components", {}).get("order", {}).get("history", []).size()
	world.advance(0.05, 1, 2)
	assert_equal(attacker.get("components", {}).get("order", {}).get("history", []).size(), recovery_history_size, "recovery tick does not churn face/recover order history")


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %.4f, got %.4f" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
