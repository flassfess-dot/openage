class_name RoRMatchMenuBackdrop
extends TextureRect

const CAMP := preload("res://assets/menu/in-match-camp-v1.png")
const COUNCIL := preload("res://assets/menu/in-match-chronicles-v1.png")

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = CAMP

func show_section(section: String) -> void:
	texture = CAMP if section in ["menu", "settings", "confirm", "defeat"] else COUNCIL
