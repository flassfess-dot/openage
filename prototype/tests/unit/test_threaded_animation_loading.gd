extends SceneTree
const Registry := preload("res://scripts/unit_presentation_registry.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var registry := Registry.new()
	registry.records_by_name = {"idle": [{"file": "ror_cursor_00.png"}], "move": [{"file": "ror_cursor_01.png"}], "part": [{"file": "ror_cursor_02.png"}]}
	var move := {"asset_name": "move", "graphic_id": 1, "composite_parts": [{"asset_name": "part", "graphic_id": 2}]}
	registry.definitions["fixture"] = {"alias": "fixture", "team": 1, "archetype": {}, "source_unit_id": -1, "state_specs": {"idle": {"asset_name": "idle", "graphic_id": 0}, "move": move}}
	registry.ensure_loaded("fixture", "idle")
	registry.background_loading_enabled = true
	registry.ensure_loaded("fixture", "move")
	registry.ensure_loaded("fixture", "move")
	check(registry.pending_states.size() <= 1, "duplicate clip requests merge")
	var deadline := Time.get_ticks_msec() + 10000
	while not registry.pending_states.is_empty() and Time.get_ticks_msec() < deadline:
		registry.poll_background_loading()
		check(registry.texture_queue.active.size() <= 8, "active load count stays bounded")
		if not registry.pending_states.is_empty(): await process_frame
	check(registry.textures.get("fixture", {}).has("move"), "base state becomes ready")
	check(registry.composite_parts.get("fixture", {}).get("move", []).size() == 1, "composite parts publish with the state")
	registry.definitions["shared"] = {"alias": "shared", "team": 1, "archetype": {}, "source_unit_id": -1, "state_specs": {"move": move, "attack": move}}
	registry.ensure_loaded("shared", "move")
	registry.ensure_loaded("shared", "attack")
	deadline = Time.get_ticks_msec() + 10000
	while not registry.pending_states.is_empty() and Time.get_ticks_msec() < deadline:
		registry.poll_background_loading()
		if not registry.pending_states.is_empty(): await process_frame
	check(registry.textures.get("shared", {}).has("move") and registry.textures.get("shared", {}).has("attack"), "shared frame paths remain available to every pending state")
	registry.ensure_loaded("fixture", "missing_state")
	check(registry.loaded_states["fixture"].has("missing_state"), "unknown state uses declared fallback without repeated I/O")
	registry.shutdown_loading()
	check(registry.pending_states.is_empty() and registry.texture_queue.active.is_empty(), "shutdown drains loading")
	finish()
