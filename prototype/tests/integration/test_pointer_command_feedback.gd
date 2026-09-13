extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const CommandFeedbackRouter := preload("res://scripts/command_feedback_router.gd")
const ContextResolver := preload("res://scripts/context_resolver.gd")
const GameController := preload("res://scripts/game_controller.gd")
const InputAdapter := preload("res://scripts/input_adapter.gd")
const PickingService := preload("res://scripts/picking_service.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_pointer_to_accepted_command_event()
	test_target_disappearing_after_pick_is_rejected()

	if failures.is_empty():
		print("I3-003 pointer-to-feedback integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_pointer_to_accepted_command_event() -> void:
	var fixture := attack_fixture()
	var command = command_from_pointer(fixture)
	fixture["controller"].enqueue_command(command, true, 1)
	var router := CommandFeedbackRouter.new()
	router.register(command, "Атаковать выбранного врага", "military_command", fixture["target"]["pos"])
	fixture["controller"].advance_frame(0.05, 1, 2)
	var events: Array = fixture["controller"].events_after()
	assert_equal(events[0]["type"], "command_accepted", "accepted result reaches presentation event stream")
	assert_equal(events[0]["payload"]["sequence_id"], command.sequence_id, "feedback correlates with command envelope")
	assert_equal(fixture["attacker"]["task"], "attack", "accepted pointer intent changes authoritative task")
	var feedback: Dictionary = router.consume(events, 1)[0]
	assert_equal(feedback["message"], "Атаковать выбранного врага", "accepted event resolves registered presentation message")
	assert_equal(feedback["marker"], fixture["target"]["pos"], "accepted event exposes command marker")


func test_target_disappearing_after_pick_is_rejected() -> void:
	var fixture := attack_fixture()
	var command = command_from_pointer(fixture)
	var router := CommandFeedbackRouter.new()
	fixture["controller"].enqueue_command(command, true, 1)
	router.register(command, "Не должно отображаться", "military_command", fixture["target"]["pos"])
	fixture["target"]["hp"] = 0.0
	fixture["controller"].advance_frame(0.05, 1, 2)
	var events: Array = fixture["controller"].events_after()
	assert_equal(events[0]["type"], "command_rejected", "late invalidation is visible instead of optimistic success")
	assert_equal(events[0]["payload"]["reason"], "invalid_target", "rejection exposes stable reason")
	assert_equal(fixture["attacker"]["task"], "idle", "rejected intent does not mutate simulation task")
	var feedback: Dictionary = router.consume(events, 1)[0]
	assert_equal(feedback["message"], "Цель больше недоступна", "rejection becomes explicit localized feedback")
	assert_equal(feedback["sound_name"], "", "rejection never plays optimistic acknowledgement")


func attack_fixture() -> Dictionary:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(3, 3), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(10, 10), false)
	return {"world": world, "controller": GameController.new(world), "attacker": attacker, "target": target}


func command_from_pointer(fixture: Dictionary):
	var adapter = InputAdapter.new()
	var target: Dictionary = fixture["target"]
	adapter.translate(mouse_button(MOUSE_BUTTON_RIGHT, true, target["pos"]))
	var pointer_action: Dictionary = adapter.translate(mouse_button(MOUSE_BUTTON_RIGHT, false, target["pos"]))[0]
	assert_equal(pointer_action["type"], "context_committed", "physical right click becomes context intent")

	var picking = PickingService.new()
	var hits: Array = picking.hit_stack(pointer_action["position"], [unit_drawable(target)], Callable(self, "identity_projection"), 1.0)
	assert_equal(hits.size(), 1, "context intent resolves through rendered hit stack")
	var resolution: Dictionary = ContextResolver.resolve([fixture["attacker"]], picking.context_entity(hits[0]), pointer_action["position"], 1)
	assert_equal(resolution["type"], "attack", "enemy unit resolves to attack semantics")
	var ids: Array[int] = [int(fixture["attacker"]["id"])]
	return Commands.AttackCommand.new(1, ids, int(resolution["target_id"]))


func unit_drawable(unit: Dictionary) -> Dictionary:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	return {
		"kind": "unit",
		"stable_id": int(unit["id"]),
		"world_anchor": unit["pos"],
		"hotspot": Vector2(2, 2),
		"data": unit,
		"frame_info": {"texture": texture, "hotspot": Vector2(2, 2), "mirrored": false},
	}


func mouse_button(button: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	return event


func identity_projection(value: Vector2) -> Vector2:
	return value


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
