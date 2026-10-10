extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	for team in [1, 2]:
		for damage in [{"hp": 70.0, "graphic": 131}, {"hp": 40.0, "graphic": 132}, {"hp": 10.0, "graphic": 133}]:
			var building := {"id": 81, "kind": "barracks", "source_unit_id": 82, "team": team, "state": "complete", "hp": damage["hp"], "max_hp": 100.0, "anim_state": "idle"}
			var graphic := int(damage["graphic"])
			var spec: Dictionary = catalog.graphics_catalog_data["graphics"][str(graphic)]
			var frame_duration := float(spec["frame_rate"])
			var frames := int(spec["frames_per_angle"])
			var key: String = catalog.building_presentations._ensure_loaded(graphic, team)
			var descriptor = catalog.building_presentations.descriptors_by_key[key]
			check(is_equal_approx(descriptor.replay_delay, float(spec["replay_delay"])), "damage graphic %d uses source replay delay" % graphic)
			var phase: float = catalog.building_presentations._idle_presentation_time(building, 0.0)
			var first_cycle: int = ceili(phase / (frame_duration * frames)) + 1
			for index in range(frames * 3 + 2):
				var sample := (first_cycle * frames + index + 0.25) * frame_duration
				var info: Dictionary = catalog.building_frame_info(building, sample - phase)
				var parts: Array = info.get("composite_parts", []).filter(func(part): return int(part.get("graphic_id", -1)) == graphic)
				check(parts.size() == 1, "damaged building has one fire overlay")
				if parts.size() == 1:
					check(int(parts[0]["frame_index"]) == index % frames, "fire %d team %d advances through wrap at sample %d" % [graphic, team, index])
	finish("Live gameplay continuous building fire")

func finish(label: String) -> void:
	if failures.is_empty():
		print(label + " passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
