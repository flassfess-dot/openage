extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_named_events_fire_once()
	test_attack_timing_cache_invalidation()
	test_damage_waits_for_original_frame()
	test_projectile_release_frame()

	if failures.is_empty():
		print("R-006 animation event tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_named_events_fire_once() -> void:
	for event_name in ["damage_frame", "projectile_release_frame", "resource_hit_frame", "construction_hit_frame", "death_complete_frame"]:
		var unit := {"anim_state": AnimationController.IDLE, "anim": 0.3, "animation_events_fired": {}}
		assert_equal(AnimationController.event_reached(unit, event_name, 2, 0.1), true, "%s fires" % event_name)
		assert_equal(AnimationController.event_reached(unit, event_name, 2, 0.1), false, "%s fires once" % event_name)


func test_attack_timing_cache_invalidation() -> void:
	var world = SimulationWorld.new(Vector2i(8, 8))
	world.set_gamespec({"units": {"clubman": {
		"hit_points": 30.0,
		"speed": 1.0,
		"attack_frame_delay": 3,
		"animations": {"attack": {"frame_rate": 0.125}},
	}}})
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(2.0, 2.0), false)
	var first: Dictionary = world.attack_animation_spec(unit)
	var second: Dictionary = world.attack_animation_spec(unit)
	assert_equal(first, second, "cached attack timing remains stable")
	assert_equal(first["damage_frame"], 3, "fallback damage frame is cached")
	assert_equal(first["projectile_release_frame"], 3, "fallback projectile frame is cached")
	assert_equal(first["frame_rate"], 0.125, "fallback frame rate is cached")
	assert_equal(world.attack_animation_spec_cache.get("clubman", {}).size(), 1, "one timing entry is cached")
	world.set_gamespec({"units": {"clubman": {
		"hit_points": 30.0,
		"speed": 1.0,
		"attack_frame_delay": 5,
		"animations": {"attack": {"frame_rate": 0.2}},
	}}})
	var updated: Dictionary = world.attack_animation_spec(unit)
	assert_equal(updated["damage_frame"], 5, "gamespec replacement invalidates cached damage frame")
	assert_equal(updated["frame_rate"], 0.2, "gamespec replacement invalidates cached frame rate")


func test_damage_waits_for_original_frame() -> void:
	var world := attack_world("clubman", -1, "damage_frame", 2)
	var attacker: Dictionary = world["attacker"]
	var target: Dictionary = world["target"]
	var initial_hp: float = target["hp"]
	world["world"].advance(0.05, 1, 2)
	world["world"].advance(0.05, 1, 2)
	world["world"].advance(0.05, 1, 2)
	world["world"].advance(0.05, 1, 2)
	assert_equal(target["hp"], initial_hp, "melee damage waits before frame 2")
	world["world"].advance(0.05, 1, 2)
	assert_equal(target["hp"], initial_hp - attacker["attack_damage"], "melee damage applies on frame 2")


func test_projectile_release_frame() -> void:
	var world := attack_world("archer", 77, "projectile_release_frame", 1)
	var attacker: Dictionary = world["attacker"]
	var target: Dictionary = world["target"]
	var initial_hp: float = target["hp"]
	world["world"].advance(0.05, 1, 2)
	world["world"].advance(0.05, 1, 2)
	assert_equal(target["hp"], initial_hp, "projectile waits before release frame")
	world["world"].advance(0.05, 1, 2)
	assert_equal(target["hp"], initial_hp, "projectile release does not deal early damage")
	assert_equal(world["world"].get_projectiles().size(), 1, "projectile is created on release frame")


func attack_world(kind: String, projectile_id: int, event_name: String, event_frame: int) -> Dictionary:
	var world = SimulationWorld.new(Vector2i(12, 12))
	world.set_gamespec({"units": {kind: {
		"hit_points": 30.0,
		"speed": 1.0,
		"attack_period": 1.5,
		"range": 1.0,
		"projectile_id": projectile_id,
		"accuracy": 100,
		"weapon_offset": [0.0, 0.0, 0.0],
		"attacks": [{"amount": 4.0}],
		"animations": {"attack": {"frame_rate": 0.1, event_name: event_frame}},
	}}})
	var attacker: Dictionary = world.add_unit(1, kind, Vector2(4.0, 4.0), false)
	var target: Dictionary = world.add_unit(2, kind, Vector2(4.5, 4.0), false)
	world.assign_command_attack([attacker], target["id"])
	return {"world": world, "attacker": attacker, "target": target}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
