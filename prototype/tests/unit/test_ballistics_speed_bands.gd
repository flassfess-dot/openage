extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(5, 8), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(10, 8), false)
	archer["components"]["combat"]["accuracy"] = 100
	target["actual_velocity"] = Vector2(1, 0)
	archer["components"]["combat"]["ballistics"] = false
	var ballistic: Dictionary = world.spawn_projectile(archer, target)
	assert_equal(String(ballistic.get("guidance", "")), "ballistic", "unresearched source arrow does not predict movement")
	assert_equal(Vector2(ballistic.get("target_position", Vector2.ZERO)), Vector2(target["pos"]), "ordinary arrow aims at the current target position")
	archer["components"]["combat"]["ballistics"] = true
	var lead_by_speed: Array[float] = []
	for speed in [0.5, 2.0, 5.0]:
		target["actual_velocity"] = Vector2(speed, 0)
		var projectile: Dictionary = world.spawn_projectile(archer, target)
		assert_equal(String(projectile.get("guidance", "")), "predictive", "Ballistics uses the technology-driven aim policy")
		lead_by_speed.append(Vector2(projectile["target_position"]).x - Vector2(target["pos"]).x)
	assert_true(lead_by_speed[0] > 0.0 and lead_by_speed[0] < lead_by_speed[1] and lead_by_speed[1] < lead_by_speed[2], "slower, medium and faster target bands receive increasing travel-time lead")
	# Source hit-rate boundaries for siege projectiles remain gated by the
	# original-game measurement manifest; this test only locks the aim policy.
	if failures.is_empty():
		print("P03 Ballistics aim-policy tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
