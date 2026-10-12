extends "res://main.gd"

# Exercise production input planning without a viewport or HUD in these fixtures.
var fixture_workers: Array = []
var fixture_preview_outlines: Array = []
var fixture_preview_items: Array = []


func selected_units() -> Array:
	return fixture_workers


func screen_to_world(screen: Vector2) -> Vector2:
	return screen


func update_interaction_cursor(_screen_position: Vector2) -> void:
	pass


func _queue_local_command(command) -> void:
	game_controller.enqueue_command(command, true, local_player_team)


func enqueue_with_feedback(command: Variant, _message: String, _sound: String, _marker: Variant = null) -> void:
	_queue_local_command(command)


func is_world_interaction_area(_screen_position: Vector2) -> bool:
	return true


func draw_foundation_preview_at(_kind: String, center: Vector2, wall_entry: Dictionary = {}, _draw_sprite: bool = true) -> void:
	fixture_preview_outlines.append({"position": center, "entry": wall_entry})


func draw_render_body(item: Dictionary) -> void:
	fixture_preview_items.append(item)
