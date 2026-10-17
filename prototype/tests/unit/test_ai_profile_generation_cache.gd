extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Profile := preload("res://scripts/ai_observation_profile.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var world := World.new(Vector2i(16,16))
	world.set_gamespec({"units":{"clubman":{"unit_id":73,"hit_points":40,"resource_cost":[{"type_id":4,"amount":1}]}}})
	world.object_catalog_data = {"objects":{"13:73":{"unit_id":73,"unit_class":1,"health":40,"speed":1.0,"combat":{"attacks":[{"class":4,"amount":3}]},"resources":{"cost":[{"type_id":4,"amount":1}]}}}}
	world.technology_system.configure({"technologies":{"200":{"effect_bundle_id":3}},"effect_bundles":{"3":{"commands":[{"type_id":4,"attr_a":73,"attr_b":-1,"attr_c":9,"attr_d":2.0}]}}})
	world.technology_system._state(1)["entity_effects"] = [{"type_id":4,"attr_a":73,"attr_b":-1,"attr_c":0,"attr_d":10.0}]
	var units := [{"id":1,"team":1,"hp":40.0,"source_unit_id":73},{"id":2,"team":1,"hp":0.0,"source_unit_id":73},{"id":3,"team":2,"hp":40.0,"source_unit_id":73}]
	var options := {"train":[{"kind":"clubman","source_unit_id":73,"behavior_tags":[]}],"research":[{"technology_id":200}]}
	var cache := {}
	var first := Profile.decorate_options(world, options, 1, units, cache)
	for _producer in range(8):
		check(Profile.decorate_options(world, options, 1, units, cache) == Profile.decorate_options(world, options, 1, units), "shared producer estimates equal fresh live calculations")
	var stable := first.duplicate(true)
	first["train"][0]["ai_profile"]["max_hp"] = -1
	check(Profile.decorate_options(world, options, 1, units, cache) == stable, "a caller cannot mutate another producer's cached estimate")
	units.append({"id":4,"team":1,"hp":40.0,"source_unit_id":73})
	world.technology_system._state(1)["entity_effects"].append({"type_id":4,"attr_a":73,"attr_b":-1,"attr_c":0,"attr_d":20.0})
	var next := Profile.decorate_options(world, options, 1, units, {})
	check(next == Profile.decorate_options(world, options, 1, units), "a new generation reads researched modifiers and army changes")
	check(next != stable, "generation changes are visible to the next decision")
	check(options["train"][0].get("ai_profile") == null, "catalog options stay unmodified")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("AI profile generation cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
