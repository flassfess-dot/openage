extends SceneTree
const Replay := preload("res://scripts/replay_system.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var codec := Replay.new()
	check(ClassDB.instantiate("RoRReadModelKernel").has_method("encode_replay_variant"), "native canonical encoder installed")
	var source: Dictionary = {"Я": [Vector2(0.0000005, -12.123456789), Vector2i(-8, 11), -0.0000005, 9223372036854775807, null, true, PackedInt32Array([1, 2])], "A": {Vector2i(4, 5): ["nested", 0.9999995], 10: 3.1415926535, "text": "Перестановка ключей"}}
	for quantized in [false, true]:
		var native: Variant = codec.encode_variant(source, quantized)
		var reference: Variant = codec.encode_variant_reference(source, quantized)
		check(JSON.stringify(native) == JSON.stringify(reference), "identical JSON, sorting and quantization")
		check(codec.decode_variant(native) == codec.decode_variant(reference), "decoded shape and types match")
		var before := JSON.stringify(native)
		source["A"]["text"] = "Changed"
		check(JSON.stringify(native) == before, "encoded containers do not alias the source")
	var collision := {1: "int", "1": "string"}
	check(JSON.stringify(codec.encode_variant(collision)) == JSON.stringify(codec.encode_variant_reference(collision)), "ambiguous converted keys use unchanged reference ordering")
	var world := World.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	for i in range(40): world.add_unit(1 + i % 2, "villager", Vector2(4 + i % 8, 4 + i / 8), false)
	for i in range(40): world.add_resource("tree", Vector2(15 + i % 8, 15 + i / 8), 100)
	var controller := Controller.new(world)
	for _step in range(12): controller.advance_frame(0.05, 1, 2)
	var fast := codec.world_state_hash(world, controller.tick_index, controller)
	codec.native_encoding_enabled = false
	check(fast == codec.world_state_hash(world, controller.tick_index, controller), "canonical world SHA256 exactly matches legacy encoder")
	world.task_coordinator.shutdown()
	for failure in failures: push_error(failure)
	print("Native canonical encoding checks: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
