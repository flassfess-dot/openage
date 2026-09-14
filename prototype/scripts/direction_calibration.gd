extends Node2D

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SpriteGeometry := preload("res://scripts/sprite_geometry.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")

const ANIMATION_KEYS := {KEY_1: "idle", KEY_2: "move", KEY_3: "attack"}

var catalog: ResourceCatalog
var texture_key := "clubman"
var animation_state := "attack"
var animation_time := 0.0
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	catalog = ResourceCatalog.new()
	catalog.load()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--unit="):
			var requested_unit := argument.trim_prefix("--unit=")
			if not requested_unit.is_empty():
				texture_key = requested_unit
		elif argument.begins_with("--animation="):
			var requested_animation := argument.trim_prefix("--animation=")
			if requested_animation in ["idle", "move", "attack"]:
				animation_state = requested_animation
	queue_redraw()

func _process(delta: float) -> void:
	animation_time += delta
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_F10:
			get_tree().change_scene_to_file("res://main.tscn")
		elif ANIMATION_KEYS.has(event.keycode):
			var requested: String = ANIMATION_KEYS[event.keycode]
			if not catalog.unit_animation_frames(texture_key, requested).is_empty():
				animation_state = requested
				animation_time = 0.0

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("101820"), true)
	draw_string(font, Vector2(32, 38), "R-002 DIRECTION CALIBRATION — %s / %s" % [texture_key, animation_state], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("f4e8c7"))
	draw_string(font, Vector2(32, 66), "1 idle   2 move   3 attack   F10/Esc return", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("d7bd7c"))
	var frames: Array = catalog.unit_animation_frames(texture_key, animation_state)
	var descriptor = catalog.get_graphic_descriptor(texture_key, animation_state)

	for facing in range(8):
		var column := facing % 4
		var row := floori(float(facing) / 4.0)
		var anchor := Vector2(145 + column * 300, 225 + row * 310)
		var resolved: Dictionary = descriptor.resolve(facing, animation_time, frames.size())
		var frame_index: int = resolved["frame_index"]
		var texture: Texture2D = frames[frame_index]
		var hotspot: Vector2 = descriptor.hotspot_for(frame_index, Vector2(texture.get_width() * 0.5, texture.get_height()))
		draw_calibration_sprite(texture, anchor, hotspot, resolved["mirrored"], 2.5)
		draw_line(anchor - Vector2(7, 0), anchor + Vector2(7, 0), Color("ffcf55"), 1.0)
		draw_line(anchor - Vector2(0, 7), anchor + Vector2(0, 7), Color("ffcf55"), 1.0)
		var facing_vector := FacingConvention.screen_vector(facing)
		draw_line(anchor, anchor + facing_vector * 42.0, Color("ff45cf"), 2.0)
		var label_position := anchor + Vector2(-105, 78)
		draw_string(font, label_position, "%s  logical=%d  source=%d  frame=%d" % [FacingConvention.label(facing), facing, resolved["source_direction"], resolved["animation_frame"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff1bd"))
		draw_string(font, label_position + Vector2(0, 20), "mirror=%s  vector=(%.2f, %.2f)  hotspot=(%.0f, %.0f)" % [resolved["mirrored"], facing_vector.x, facing_vector.y, hotspot.x, hotspot.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9ee8ff"))

func draw_calibration_sprite(texture: Texture2D, anchor: Vector2, hotspot: Vector2, mirrored: bool, scale: float) -> void:
	var rectangle := SpriteGeometry.anchored_rectangle(texture.get_size(), hotspot, scale)
	if mirrored:
		draw_set_transform(anchor, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(texture, rectangle, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		rectangle.position += anchor
		draw_texture_rect(texture, rectangle, false)
