extends SceneTree

# Deterministic presentation capture for HUD and world-layout review. This is a
# manual L3 tool, not part of the automated test suite and does not rebuild the
# imported source-resource cache.

const DEFAULT_SIZE := Vector2i(800, 600)
const DEFAULT_OUTPUT := "res://qa/main-scene-capture.png"
const DEFAULT_SCENE := "res://main.tscn"
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")


func _initialize() -> void:
	var requested_size := DEFAULT_SIZE
	var output_path := DEFAULT_OUTPUT
	var scene_path := DEFAULT_SCENE
	var selection_kind := ""
	var open_build_menu := false
	var hud_modal := ""
	var random_map_type := ""
	var focus_coast := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			requested_size = parse_size(argument.trim_prefix("--size="))
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--selection-kind="):
			selection_kind = argument.trim_prefix("--selection-kind=")
		elif argument == "--open-build-menu":
			open_build_menu = true
		elif argument.begins_with("--hud-modal="):
			hud_modal = argument.trim_prefix("--hud-modal=")
		elif argument.begins_with("--random-map-type="):
			random_map_type = argument.trim_prefix("--random-map-type=")
		elif argument == "--focus-coast":
			focus_coast = true

	var viewport := SubViewport.new()
	viewport.size = requested_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("Failed to load presentation scene: %s" % scene_path)
		quit(1)
		return
	var instance := scene.instantiate()
	if not random_map_type.is_empty():
		var settings := SkirmishSettings.default_settings()
		settings["map_type_id"] = random_map_type
		var built := SkirmishSettings.build(settings)
		if not bool(built.get("valid", false)):
			push_error("Failed to build random map: %s" % [str(built.get("errors", []))])
			quit(1)
			return
		instance.set("match_definition_override", built["definition"])
		instance.set("map_definition_override", built["map_data"])
	viewport.add_child(instance)
	for _frame in range(6):
		await process_frame
	if focus_coast:
		var coast_position := nearest_coast_position(instance)
		if coast_position.x >= 0.0:
			instance.call("center_view_on_world", coast_position)
			for _frame in range(3):
				await process_frame
	if not selection_kind.is_empty():
		apply_selection_kind(instance, selection_kind)
		for _frame in range(2):
			await process_frame
	if open_build_menu:
		var hud_controls = instance.get("hud_controls")
		if hud_controls != null and hud_controls.train_button != null:
			hud_controls.train_button.emit_signal("pressed")
			for _frame in range(2):
				await process_frame
	if not hud_modal.is_empty():
		if hud_modal == "menu" and instance.has_method("_toggle_game_menu"):
			instance.call("_toggle_game_menu")
		elif hud_modal == "diplomacy" and instance.has_method("_show_diplomacy_summary"):
			instance.call("_show_diplomacy_summary")
		for _frame in range(2):
			await process_frame

	var image := viewport.get_texture().get_image()
	var result := image.save_png(output_path)
	if result != OK:
		push_error("Failed to save presentation capture %s: %s" % [output_path, error_string(result)])
		quit(1)
		return
	print("Presentation capture saved: %s from %s (%dx%d)" % [output_path, scene_path, requested_size.x, requested_size.y])
	quit(0)


func parse_size(value: String) -> Vector2i:
	var parts := value.to_lower().split("x", false)
	if parts.size() != 2:
		return DEFAULT_SIZE
	var parsed := Vector2i(int(parts[0]), int(parts[1]))
	return parsed if parsed.x >= 320 and parsed.y >= 240 else DEFAULT_SIZE


func apply_selection_kind(instance: Node, kind: String) -> void:
	var control_state = instance.get("player_control_state")
	if control_state == null:
		return
	var entities: Array = []
	var presented_units: Variant = instance.get("units")
	if presented_units is Array:
		entities.append_array(presented_units)
	var snapshot: Dictionary = instance.get("presentation_snapshot")
	entities.append_array(snapshot.get("buildings", []))
	for entity_value in entities:
		var entity: Dictionary = entity_value
		if String(entity.get("kind", "")) != kind or int(entity.get("team", 0)) != 1:
			continue
		var selected_ids: Array[int] = [int(entity.get("id", -1))]
		control_state.replace_or_add(selected_ids, false)
		if instance.has_method("refresh_hud_model"):
			instance.call("refresh_hud_model")
		print("Presentation capture selected %s #%d" % [kind, int(entity.get("id", -1))])
		return


func nearest_coast_position(instance: Node) -> Vector2:
	var map_data: Dictionary = instance.get("map_definition")
	var size: Vector2i = map_data.get("size", Vector2i.ZERO)
	var ids: Array = map_data.get("terrain_ids", [])
	var definition: Dictionary = instance.get("match_definition")
	var players: Array = definition.get("players", [])
	if size.x <= 2 or size.y <= 2 or ids.size() < size.x * size.y or players.is_empty():
		return Vector2(-1.0, -1.0)
	var start: Vector2 = players[0].get("start", Vector2(size) * 0.5)
	var best_distance := INF
	var best := Vector2(-1.0, -1.0)
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			var center_id := int(ids[y * size.x + x])
			if center_id in TerrainRules.WATER_TERRAIN_IDS:
				continue
			var neighboring_water := false
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = Vector2i(x, y) + offset
				if int(ids[neighbor.y * size.x + neighbor.x]) in TerrainRules.WATER_TERRAIN_IDS:
					neighboring_water = true
					break
			if not neighboring_water:
				continue
			var candidate := Vector2(x, y)
			var distance := candidate.distance_squared_to(start)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best
