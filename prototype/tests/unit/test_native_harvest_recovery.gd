extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Order := preload("res://scripts/order_pipeline.gd")
var failures: Array[String] = []

func fixture(direction: Vector2, grouped: bool, completed: bool, stage: String) -> Dictionary:
	var world := World.new(Vector2i(16, 16))
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(7.5, 7.5) - direction, false)
	var resource: Dictionary = world.add_resource("berries", Vector2(7.5, 7.5), 100)
	worker["components"]["worker"]["enabled"] = true
	worker["task"] = "gather"
	worker["resource_id"] = resource["id"]
	worker["resource_approach_slot"] = worker["pos"]
	worker["gather_stage"] = stage
	worker["work"] = 0.3
	worker["carry_capacity"] = 10.0
	worker["carried_amount"] = 0.0
	world.resource_approach_slots[resource["id"]] = {worker["id"]: worker["pos"]}
	if grouped: world.resource_approach_slots[resource["id"]][999] = Vector2(8.5, 7.5)
	Order.begin(worker, "gather", int(resource["id"]), resource["pos"], true)
	Order.transition(worker, Order.RECOVER)
	if completed: Order.complete(worker)
	world.entity_changes.flush()
	return {"world": world, "worker": worker, "cursor": world.entity_changes.revision}

func _initialize() -> void:
	var kernel = ClassDB.instantiate("RoRReadModelKernel")
	if kernel == null or not kernel.has_method("advance_harvesting_recovery"):
		push_error("Current native recovery kernel is required")
		quit(1)
		return
	for direction in [Vector2(0.9, 0), Vector2(-0.9, 0), Vector2(0, 0.9), Vector2(0, -0.9), Vector2(0.55, 0.55), Vector2(-0.55, 0.55), Vector2(0.55, -0.55), Vector2(-0.55, -0.55), Vector2.ZERO]:
		for grouped in [false, true]:
			for completed in [false, true]:
				for stage in ["harvesting", "approaching"]:
					var fast := fixture(direction, grouped, completed, stage)
					var reference := fixture(direction, grouped, completed, stage)
					reference.world.gathering_system.native_recovery_enabled = false
					var actual: int = fast.world.gathering_system.update_gather_order(fast.worker, 0.05)
					var expected: int = reference.world.gathering_system.update_gather_order(reference.worker, 0.05)
					if actual != expected or fast.worker != reference.worker:
						failures.append("Recovery differs for %s grouped=%s completed=%s stage=%s" % [direction, grouped, completed, stage])
					var changes: Dictionary = fast.world.entity_changes.changes_since(fast.cursor)
					var old_changes: Dictionary = reference.world.entity_changes.changes_since(reference.cursor)
					if changes["masks"] != old_changes["masks"]: failures.append("Recovery changes different source groups")
	for failure in failures: push_error(failure)
	print("Native harvesting recovery parity: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
