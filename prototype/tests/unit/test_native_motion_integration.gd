extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var kernel = ClassDB.instantiate("RoRReadModelKernel")
	if kernel == null or not kernel.has_method("integrate_unit_motion"):
		push_error("Current native motion kernel is required")
		quit(1)
		return
	var fast := World.new(Vector2i(16, 16))
	var reference := World.new(Vector2i(16, 16))
	var actor: Dictionary = fast.add_unit(1, "villager", Vector2(5.5, 5.5), false)
	var other: Dictionary = reference.add_unit(1, "villager", Vector2(5.5, 5.5), false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 918271
	for hills in [false, true]:
		if hills:
			fast.configure_demo_elevation(Vector2i(8, 8), 5, 2)
			reference.configure_demo_elevation(Vector2i(8, 8), 5, 2)
		for index in range(320):
			var origin := Vector2(rng.randf_range(0.5, 15.5), rng.randf_range(0.5, 15.5))
			var target := origin + Vector2.from_angle(float(index) * TAU / 32.0) * rng.randf_range(0.01, 3.0)
			var velocity := (target - origin).normalized() * rng.randf_range(0.0, 20.0)
			if index % 8 == 0: origin = Vector2(0.5, 0.5)
			if index % 9 == 0: velocity = Vector2.ZERO
			var delta := [0.0, 0.05, 0.15, 0.5][index % 4] as float
			var reason := "local_blocked" if index % 5 == 0 else ""
			for unit in [actor, other]:
				unit["pos"] = origin
				unit["target"] = target
				unit["actual_velocity"] = velocity
				unit["desired_velocity"] = velocity * 1.1
				unit["elevation"] = 1.0
				unit["desired_facing"] = 3
				unit["movement_facing"] = 4
				unit["facing"] = 5
				unit["diagnostic_reason"] = "existing"
			fast.entity_changes.flush()
			reference.entity_changes.flush()
			var cursor: int = fast.entity_changes.revision
			var old_cursor: int = reference.entity_changes.revision
			var vertices: Dictionary = fast.terrain_elevation.vertex_levels if hills else {}
			var mask: int = kernel.integrate_unit_motion(actor, delta, fast.map_size, vertices, reason)
			if mask != 0: fast.notify_entity_changed(actor, mask)
			reference.movement_system._integrate_unit_motion(other, delta, reason, reference)
			if actor != other:
				failures.append("Motion fields differ: hills=%s case=%d" % [hills, index])
				break
			var changes: Dictionary = fast.entity_changes.changes_since(cursor)
			var old_changes: Dictionary = reference.entity_changes.changes_since(old_cursor)
			if changes.masks != old_changes.masks:
				failures.append("Motion journal differs: hills=%s case=%d %s vs %s" % [hills, index, changes.masks, old_changes.masks])
				break
	for failure in failures: push_error(failure)
	print("Native motion integration: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
