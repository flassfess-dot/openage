extends SceneTree

const Knowledge := preload("res://scripts/ai_navigation_knowledge.gd")
const Probe := preload("res://scripts/performance_probe.gd")

func _initialize() -> void:
	var cases: Array = []
	var valid := true
	for side in [128, 256, 400]:
		var knowledge := Knowledge.new()
		var original: Array[Vector2] = []
		var additions: Array[Vector2] = []
		for y in range(side):
			for x in range(side / 2):
				original.append(Vector2(x, y) + Vector2(0.5, 0.5))
			for x in range(side / 2, side / 2 + 10):
				additions.append(Vector2(x, y) + Vector2(0.5, 0.5))
		original.make_read_only()
		var legacy_times: Array = []
		var merged_times: Array = []
		var output_points := 0
		for repetition in range(3):
			# This reproduces the previous per-discovery array insertion on the
			# same frozen input, including its initial copy-on-write allocation.
			var legacy: Array = original
			var start := Time.get_ticks_usec()
			for point in additions:
				var slot: int = knowledge._bucket_position(legacy, point)
				if legacy.is_read_only():
					legacy = legacy.duplicate()
				legacy.insert(slot, point)
			legacy_times.append(Time.get_ticks_usec() - start)
			var entry: Dictionary = knowledge._new_entry(Vector2i(side, side))
			entry["buckets"]["land"] = original
			knowledge.last_bucket_merged_points = 0
			start = Time.get_ticks_usec()
			for point in additions:
				var index: int = floori(point.y) * int(side) + floori(point.x)
				knowledge._set_bucket(entry, "land", index, point, true)
			knowledge._apply_bucket_changes(entry)
			merged_times.append(Time.get_ticks_usec() - start)
			output_points = knowledge.last_bucket_merged_points
			valid = valid and legacy == entry["buckets"]["land"] and original.size() == side * side / 2
		var result := {"map_side": side, "known_points": original.size(), "discoveries": additions.size(), "legacy_us": Probe.summarize(legacy_times), "batched_us": Probe.summarize(merged_times), "emitted_points": output_points}
		cases.append(result)
		print("NAVIGATION GROWTH ", JSON.stringify(result))
	var output := "res://qa/progressive-slowdown-20261008/navigation-benchmark.json"
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--output="):
			output = String(arg).trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write progressive navigation benchmark")
		quit(1)
		return
	file.store_string(JSON.stringify({"scope": "Controlled CPU microbenchmark; identical navigation points; legacy array insertion versus batched merge, three repetitions. Not a game FPS measurement.", "equivalent": valid, "cases": cases}, "\t"))
	file.close()
	if not valid:
		push_error("Progressive navigation benchmark changed the point projection")
	quit(0 if valid else 1)
