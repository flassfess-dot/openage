extends SceneTree
const Archive := preload("res://scripts/game_save_archive.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Autosave := preload("res://scripts/background_autosave.gd")
const DIRECTORY := "res://qa/autosave-archive-unit"
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var target := DIRECTORY.path_join("автосохранение.json")
	var stage := DIRECTORY.path_join(".autosave-test.pending")
	for path in [target, stage, stage + ".tmp", target + ".bak"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var world := World.new(Vector2i(8, 8))
	var controller := Controller.new(world)
	controller.start_recording(123, false)
	var definition := {"id": "autosave-test", "players": [{"team": 1, "civilization_id": 13}]}
	var checkpoint := Checkpoint.pack(Checkpoint.capture(world, controller, definition, {"size": world.map_size}))
	var archive := Archive.create("res://data/matches/prototype_match.json", definition, 0, "", controller.replay_recorder.to_dictionary(), [], {}, {}, Archive.AUTOSAVE_NAME, checkpoint)
	check(Archive.write(stage, archive) == OK, "complete staging file writes")
	check(Archive.list_saves(DIRECTORY, DIRECTORY.path_join("missing.json"), target).is_empty(), "pending file is hidden from load menus")
	check(Archive.commit_autosave(stage, target) == OK, "first autosave publishes")
	var original := FileAccess.get_file_as_bytes(target)
	var temporary := FileAccess.open(stage + ".tmp", FileAccess.WRITE)
	temporary.store_string("{incomplete")
	temporary.close()
	check(Archive.commit_autosave(stage, target) != OK, "interrupted write cannot replace previous save")
	check(FileAccess.get_file_as_bytes(target) == original, "previous autosave survives interruption")
	archive["metadata"]["saved_at_unix"] += 1
	check(Archive.write(stage, archive) == OK and Archive.commit_autosave(stage, target) == OK, "atomic rename replaces an existing Windows slot")
	var entries := Archive.list_saves(DIRECTORY, DIRECTORY.path_join("missing.json"), target)
	check(entries.size() == 1 and bool(entries[0].get("autosave", false)) and entries[0]["slot_name"] == Archive.AUTOSAVE_NAME, "exactly one labelled autosave is discoverable")
	check(bool(Archive.read(target).get("valid", false)), "replacement is loadable")
	check(not FileAccess.file_exists(target + ".bak"), "autosave does not retain a second backup slot")
	check(Archive.named_path(Archive.AUTOSAVE_NAME).is_empty(), "manual saves cannot impersonate the automatic slot")
	check(Archive.write(stage, archive, true) == OK and Archive.write(stage, archive, true) == OK and not FileAccess.file_exists(stage + ".bak"), "retries replace staging atomically without accumulating backups")
	var scheduler := Autosave.new()
	check(not scheduler.advance(120, false) and scheduler.elapsed == 0, "paused/loading/network time does not count")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Autosave archive: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
