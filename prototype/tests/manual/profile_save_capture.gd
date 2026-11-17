extends SceneTree
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const Ready := preload("res://tests/support/match_ready.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var path := ""
	var storage_only := false
	var measure_component_sharing := false
	var storage_output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.trim_prefix("--save=")
		elif arg == "--storage-only": storage_only = true
		elif arg == "--measure-component-sharing": measure_component_sharing = true
		elif arg.begins_with("--storage-output="): storage_output = arg.trim_prefix("--storage-output=")
	if storage_only:
		profile_resource_storage(path, storage_output, measure_component_sharing)
		return
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await Ready.wait_for_ready(self, game, 120000): quit(1); return
	if not game.load_game_from_path(path): push_error(game.last_save_error); quit(1); return
	if not await Ready.wait_for_ready(self, game, 120000): quit(1); return
	game.set_process(false)
	for field in Checkpoint.WORLD_FIELDS:
		var stamp := Time.get_ticks_usec()
		var value: Variant = game.simulation_world.get(field)
		var copied: Variant = Data.copy(value)
		print("SAVE_FIELD ", field, " us=", Time.get_ticks_usec() - stamp, " count=", value.size() if value is Array or value is Dictionary else 0)
	for owner in [game.simulation_world.navigation_grid, game.simulation_world.fog_of_war]:
		var fields: Array = Checkpoint.GRID_FIELDS if owner == game.simulation_world.navigation_grid else Checkpoint.FOG_FIELDS
		for field in fields:
			var stamp := Time.get_ticks_usec()
			var copied: Variant = Data.copy(owner.get(field))
			print("SAVE_FIELD ", field, " us=", Time.get_ticks_usec() - stamp)
	for team in game.simulation_world.movement_system.knowledge.entries:
		var stamp := Time.get_ticks_usec()
		var entry: Dictionary = game.simulation_world.movement_system.knowledge.entries[team]
		var copied: Variant = Checkpoint._capture_fields(entry["grid"], Checkpoint.GRID_FIELDS)
		print("SAVE_FIELD knowledge ", team, " us=", Time.get_ticks_usec() - stamp)
	var started := Time.get_ticks_usec()
	var checkpoint := Checkpoint.capture(game.simulation_world, game.game_controller, game.match_definition, game.map_definition)
	print("SAVE_PROFILE checkpoint_us=", Time.get_ticks_usec() - started)
	game.free()
	quit(0)


func profile_resource_storage(path: String, output: String, measure_sharing: bool = false) -> void:
	# Read the existing checkpoint without a scene, simulation or textures.
	# Serialized sizes describe repeated values; they are not a RAM estimate.
	var started := Time.get_ticks_usec()
	var archive: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not archive is Dictionary or not archive.get("checkpoint") is Dictionary:
		push_error("Cannot inspect checkpoint"); quit(1); return
	var data: Dictionary = Checkpoint.unpack(archive["checkpoint"])
	if data.is_empty(): push_error("Cannot unpack checkpoint"); quit(1); return
	var resources: Array = data.get("world", {}).get("resource_nodes", [])
	var counts: Dictionary = {}
	var sampled: Dictionary = {}
	var groups: Dictionary = {}
	var unique: Dictionary = {}
	for resource in resources:
		var kind := String(resource.get("kind", ""))
		counts[kind] = int(counts.get(kind, 0)) + 1
		if int(sampled.get(kind, 0)) >= 64: continue
		sampled[kind] = int(sampled.get(kind, 0)) + 1
		for name in resource.get("components", {}):
			var value: Variant = resource["components"][name]
			if not groups.has(name):
				groups[name] = {"samples":0,"distinct_values":0,"serialized_bytes":0,"unique_serialized_bytes":0,"readonly_samples":0}
				unique[name] = {}
			var row: Dictionary = groups[name]
			var bytes := var_to_bytes(value).size()
			row["samples"] += 1
			row["serialized_bytes"] += bytes
			if (value is Dictionary or value is Array) and value.is_read_only(): row["readonly_samples"] += 1
			var key := hash(value)
			var bucket: Array = unique[name].get(key, [])
			if not bucket.any(func(previous): return previous == value):
				bucket.append(value)
				unique[name][key] = bucket
				row["distinct_values"] += 1
				row["unique_serialized_bytes"] += bytes
	var report := {"save":path,"resource_count":resources.size(),"counts":counts,"sampled":sampled,"components":groups,"checkpoint_bytes":archive["checkpoint"]["size"],"elapsed_us":Time.get_ticks_usec()-started,"godot_static_memory_bytes":OS.get_static_memory_usage()}
	if measure_sharing:
		# Measure the actual bounded runtime interner in a private decoded archive,
		# without a scene, simulation or changing the original save.
		unique.clear()
		var sharing_before := OS.get_static_memory_usage()
		var sharing_started := Time.get_ticks_usec()
		var pool := preload("res://scripts/resource_component_pool.gd").new()
		for resource in resources:
			pool.intern(resource)
		report["sharing"] = {"mode":"runtime_pool","memory_before":sharing_before,"memory_after":OS.get_static_memory_usage(),"replacements":pool.shared_components,"templates":pool.template_count,"encoded_bytes":pool.retained_bytes,"elapsed_us":Time.get_ticks_usec()-sharing_started}
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null: push_error("Cannot write storage report"); quit(1); return
		file.store_string(JSON.stringify(report,"\t")); file.close()
	print("RESOURCE_STORAGE ", JSON.stringify(report))
	quit(0)
