extends SceneTree

const ProjectileMotion := preload("res://scripts/projectile_motion.gd")
const CombatRules := preload("res://scripts/combat_rules.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	test_original_projectile_data(catalog)
	test_release_flight_and_impact(catalog)
	test_ballistic_target_can_evade(catalog)
	test_predictive_aim_and_accuracy(catalog)
	test_minimum_range_and_generic_blast(catalog)
	test_render_layer(catalog)

	if failures.is_empty():
		print("S-004 projectile tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_projectile_data(catalog) -> void:
	var objects: Dictionary = catalog.object_catalog_data.get("objects", {})
	var archer: Dictionary = objects.get("13:4", {})
	var arrow: Dictionary = objects.get("13:9", {})
	assert_equal(archer["combat"]["weapon_offset"], [0.0, 0.5, 1.5], "original archer weapon offset")
	assert_float(float(arrow["speed"]), 8.0, "original arrow speed")
	assert_float(float(arrow["projectile"]["arc"]), 0.05000000074505806, "original arrow arc")
	assert_equal(arrow["projectile"]["smart_mode"], false, "original arrow ballistic mode")
	assert_equal(catalog.projectile_animation_frames(9).size(), 37, "all stored arrow directions loaded")
	var arrow_frame: Dictionary = catalog.projectile_frame_info({"projectile_unit_id": 9, "origin": Vector2.ZERO, "target_position": Vector2.RIGHT, "pos": Vector2.ZERO})
	assert_equal(arrow_frame.get("asset_name"), "arrow", "arrow resolves through source-aware projectile registry")


func test_release_flight_and_impact(catalog) -> void:
	var world = original_world(catalog)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(6.0, 6.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(10.0, 6.0), false)
	var initial_health := float(target["hp"])
	world.assign_command_attack([archer], int(target["id"]))
	for unused in range(12):
		world.advance(0.05, 1, 2)
		if not world.get_projectiles().is_empty():
			break
	assert_float(float(target["hp"]), initial_health, "release frame does not damage target")
	assert_equal(world.get_projectiles().size(), 1, "release creates one projectile")
	var projectile: Dictionary = world.get_projectiles()[0]
	assert_equal(projectile["origin"], Vector2(6.5, 6.0), "projectile starts at original weapon offset")
	assert_float(float(projectile["launch_height"]), 1.5, "projectile starts at original weapon height")
	for unused in range(20):
		world.update_projectiles(0.05, 1)
		if world.get_projectiles().is_empty():
			break
	assert_true(world.get_projectiles().is_empty(), "projectile resolves after flight")
	assert_float(initial_health - float(target["hp"]), 3.0, "projectile applies launcher attacks only on impact")
	var distress: Array = world.get_attack_distress_signals(2)
	assert_equal(distress.size(), 1, "projectile impact records one bounded distress signal for the victim team")
	assert_equal(int(distress[0].get("attacker_id", -1)), int(archer["id"]), "projectile distress preserves launcher identity")
	var resolved: Dictionary = world.get_resolved_projectiles()[-1]
	assert_true(resolved["hit"], "stationary target is hit")
	assert_true(float(resolved["visual_height"]) <= 0.0001, "trajectory lands at target height")


func test_ballistic_target_can_evade(catalog) -> void:
	var world = original_world(catalog)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(6.0, 8.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(10.0, 8.0), false)
	var initial_health := float(target["hp"])
	var projectile: Dictionary = world.spawn_projectile(archer, target)
	target["pos"] += Vector2(0.0, 2.0)
	for unused in range(20):
		world.update_projectiles(0.05, 1)
		if world.get_projectiles().is_empty():
			break
	assert_float(float(target["hp"]), initial_health, "ballistic projectile can miss a moved target")
	assert_equal(projectile["hit"], false, "evaded projectile records miss")


func test_predictive_aim_and_accuracy(catalog) -> void:
	var attacker := {"id": 1, "pos": Vector2.ZERO}
	var moving_target := {"id": 2, "pos": Vector2(4.0, 0.0), "actual_velocity": Vector2(1.0, 0.0), "footprint_radius": 0.3}
	var predictive: Dictionary = ProjectileMotion.aim_position(attacker, moving_target, 4.0, true, 100, 3)
	assert_equal(predictive["position"], Vector2(5.0, 0.0), "smart projectile predicts target motion")

	var world = original_world(catalog)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(6.0, 10.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(10.0, 10.0), false)
	archer["components"]["combat"]["accuracy"] = 0
	var initial_health := float(target["hp"])
	var missed: Dictionary = world.spawn_projectile(archer, target)
	assert_true(not bool(missed["accurate"]), "zero accuracy deterministically selects a miss")
	for unused in range(20):
		world.update_projectiles(0.05, 1)
		if world.get_projectiles().is_empty():
			break
	assert_float(float(target["hp"]), initial_health, "accuracy miss deals no damage")


func test_minimum_range_and_generic_blast(catalog) -> void:
	var world = original_world(catalog)
	var attacker: Dictionary = world.add_unit(1, "archer", Vector2(5.0, 12.0), false)
	var close_target: Dictionary = world.add_unit(2, "clubman", Vector2(5.8, 12.0), false)
	attacker["attack_range_min"] = 2.0
	attacker["components"]["combat"]["range_min"] = 2.0
	assert_true(CombatRules.is_too_close(attacker, close_target), "minimum range is a first-class combat constraint")
	assert_true(not CombatRules.is_in_range(attacker, close_target), "point-blank ranged target is outside legal firing band")

	var target: Dictionary = world.add_unit(2, "clubman", Vector2(9.0, 12.0), false)
	var adjacent: Dictionary = world.add_unit(2, "clubman", Vector2(9.0, 12.5), false)
	var friendly: Dictionary = world.add_unit(1, "clubman", Vector2(9.0, 11.5), false)
	attacker["components"]["combat"]["blast_range"] = 0.5
	attacker["components"]["combat"]["friendly_fire"] = true
	var target_hp := float(target["hp"])
	var adjacent_hp := float(adjacent["hp"])
	var friendly_hp := float(friendly["hp"])
	var projectile: Dictionary = world.spawn_projectile(attacker, target)
	for unused in range(30):
		world.update_projectiles(0.05, 1)
		if not bool(projectile.get("active", true)):
			break
	assert_true(float(target["hp"]) < target_hp, "generic blast damages direct target")
	assert_true(float(adjacent["hp"]) < adjacent_hp, "generic blast damages adjacent enemy")
	assert_true(float(friendly["hp"]) < friendly_hp, "explicit friendly-fire policy is authoritative")
	assert_equal(projectile.get("hit_target_ids", []).size(), 3, "generic blast records deterministic affected set")


func test_render_layer(catalog) -> void:
	var world = original_world(catalog)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(7.0, 7.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(10.0, 7.0), false)
	var projectile: Dictionary = world.spawn_projectile(archer, target)
	ProjectileMotion.advance(projectile, 0.2)
	assert_true(float(projectile["visual_height"]) > 0.0, "arc exposes positive visual height during flight")
	var renderer = RenderWorld.new()
	var items: Array = renderer.create_world_drawables(world, func(position): return position)
	var projectile_items: Array = items.filter(func(item): return item["kind"] == "projectile")
	assert_equal(projectile_items.size(), 1, "active projectile enters render queue")
	assert_equal(projectile_items[0]["layer"], RenderItem.Layer.PROJECTILE_EFFECT, "projectile uses effect layer")


func original_world(catalog):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	return world


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
