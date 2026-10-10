extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Replay := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []
func _initialize() -> void:
	for version in [1, 2, 3, 4]: check(Archive.validate({"format_version": version}) == "unsupported_version", "old save %d is rejected before restoration" % version)
	for version in [1, 2, 3]: check(not Replay.new().load_dictionary({"format_version": version}), "old replay %d is rejected" % version)
	var world := World.new(Vector2i(24, 24))
	var controller := Controller.new(world)
	controller.start_recording(1, false)
	var definition := {"players": [], "map": {"size": Vector2i(24, 24)}}
	var map := {"size": Vector2i(24, 24)}
	var checkpoint := Checkpoint.capture(world, controller, definition, map)
	check(checkpoint.has("observation_memory") and not checkpoint["runtime"].has("activity"), "current checkpoints separate durable fog memory from derived actor indices")
	var incomplete := checkpoint.duplicate(true)
	incomplete.erase("observation_memory")
	check(not Checkpoint.validate(incomplete), "current checkpoints require complete durable observation memory")
	var packed := Checkpoint.pack(checkpoint)
	var archive := Archive.create("res://data/current-fixture.json", definition, 0, "", controller.replay_recorder.to_dictionary(), [], {}, {"ai_decisions": {}}, "Текущий формат", packed)
	check(Archive.validate(archive).is_empty(), "only the current checkpoint archive is valid")
	check(archive["state_sha256"] == packed["sha256"], "archive integrity uses the checkpoint digest without rehashing a live world")
	check(not Checkpoint.unpack(packed).is_empty(), "current checkpoint has a complete restoration contract")
	var stale := archive.duplicate(true)
	stale["checkpoint"]["version"] = 1
	check(Archive.validate(stale) == "checkpoint_invalid", "old checkpoint blobs cannot enter a current archive")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Current checkpoint archive: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
