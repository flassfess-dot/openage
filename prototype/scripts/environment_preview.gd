extends Node2D

const Catalog := preload("res://scripts/resource_catalog.gd")
const TerrainCanvas := preload("res://scripts/terrain_canvas.gd")
const Elevation := preload("res://scripts/terrain_elevation.gd")
const RenderWorld := preload("res://scripts/render_world.gd")

# Share the game layer ordering: flat artwork must remain below actors/trees.
static func object_less(a: Dictionary, b: Dictionary) -> bool:
	var left := RenderWorld.environment_layer(a)
	var right := RenderWorld.environment_layer(b)
	if left != right: return left < right
	return a["position"].x + a["position"].y < b["position"].x + b["position"].y

const Coordinates := preload("res://scripts/coordinates.gd")

class ObjectsLayer extends Node2D:
	var preview
	func _draw() -> void:
		if preview == null:
			return
		var items: Array = preview.objects.duplicate()
		items.sort_custom(preview.object_less)
		for item in items:
			if not preview.show_pack and not bool(item.get("reference", false)):
				continue
			var info: Dictionary = item.get("frame_info", {})
			if item.has("animated_resource"):
				info = preview.catalog.resource_frame_info(item["animated_resource"], preview.animation_time)
			elif info.is_empty():
				info = preview.catalog.environment_frame_info(item)
			if info.is_empty():
				continue
			var point: Vector2 = preview.elevation.world_to_screen(item["position"], preview.zoom, preview.view_offset)
			var texture: Texture2D = info["texture"]
			var origin: Vector2 = (point - Vector2(info["hotspot"]) * preview.zoom).round()
			draw_texture_rect(texture, Rect2(origin, texture.get_size() * preview.zoom), false)
		if preview.show_grid:
			for y in range(preview.map_size.y):
				for x in range(preview.map_size.x):
					var points := PackedVector2Array()
					for shift in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, Vector2.ZERO]:
						points.append(preview.elevation.world_to_screen(Vector2(x, y) + shift, preview.zoom, preview.view_offset))
					draw_polyline(points, Color(0.9, 0.85, 0.65, 0.24), 1.0)
		for marker in preview.markers:
			var point: Vector2 = preview.elevation.world_to_screen(marker["position"], preview.zoom, preview.view_offset)
			var text: String = marker["text"]
			var font := ThemeDB.fallback_font
			var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			var left := point - Vector2(text_size.x / 2.0, 0)
			draw_style_box(preview.label_style, Rect2(left - Vector2(8, 17), text_size + Vector2(16, 5)))
			draw_string(font, left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e4ddc8"))

var catalog = Catalog.new()
var terrain = TerrainCanvas.new()
var object_layer = ObjectsLayer.new()
var elevation = Elevation.new(Vector2i(24, 24))
var map_size := Vector2i(24, 24)
var cells: Dictionary = {}
var objects: Array = []
var markers: Array = []
var zoom := 1.0
var view_offset := Vector2(720, 150)
var show_pack := true
var show_grid := false
var view_mode := 0
var decoration_choice: OptionButton
var decoration_keys: Array[String] = []
var label_style := StyleBoxFlat.new()
var status: Label
var subtitle: Label
var revision := 0
var animation_time := 0.0
var has_animated_objects := false
var animation_redraw_elapsed := 0.0


func _process(delta: float) -> void:
	animation_time += delta
	animation_redraw_elapsed += delta
	if has_animated_objects and animation_redraw_elapsed >= 0.05:
		animation_redraw_elapsed = 0.0
		object_layer.queue_redraw()


func _ready() -> void:
	get_window().title = "Rise of Rome — окружение RoR и AoE2"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	catalog.load()
	_build_ui()
	if not catalog.enable_environment_pack():
		status.text = "Набор недоступен. Запустите tools/preview-environment.ps1 -Reimport"
		return
	for spec in catalog.environment_pack.definition["objects"]:
		if not spec.has("placement"): continue
		decoration_keys.append(spec["key"])
		decoration_choice.add_item(spec["title"])
	add_child(terrain)
	add_child(object_layer)
	object_layer.preview = self
	object_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label_style.bg_color = Color(0.065, 0.08, 0.065, 0.88)
	label_style.corner_radius_top_left = 3
	label_style.corner_radius_top_right = 3
	label_style.corner_radius_bottom_left = 3
	label_style.corner_radius_bottom_right = 3
	get_viewport().size_changed.connect(_fit_view)
	set_mode(0)
	print("Mixed environment preview ready: 4 materials, 121 decoration variants")


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var header := Panel.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size.y = 100
	header.offset_bottom = 100
	var background := StyleBoxFlat.new()
	background.bg_color = Color("19221d")
	background.border_color = Color("a59665")
	background.border_width_bottom = 1
	header.add_theme_stylebox_override("panel", background)
	ui.add_child(header)
	var title := Label.new()
	title.text = "ОКРУЖЕНИЕ  /  УМЕРЕННЫЙ ЛАНДШАФТ"
	title.position = Vector2(24, 11)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("e7dfc7"))
	header.add_child(title)
	subtitle = Label.new()
	subtitle.position = Vector2(24, 40)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("b7bead"))
	header.add_child(subtitle)
	var controls := HBoxContainer.new()
	controls.position = Vector2(24, 66)
	controls.add_theme_constant_override("separation", 8)
	header.add_child(controls)
	for index in range(4):
		var button := Button.new()
		button.text = ["Ландшафт", "Деревья и камни", "Покрытия", "Декали и детали"][index]
		button.pressed.connect(set_mode.bind(index))
		controls.add_child(button)
	decoration_choice = OptionButton.new()
	decoration_choice.item_selected.connect(func(_index): set_mode(3))
	controls.add_child(decoration_choice)
	var toggle := CheckButton.new()
	toggle.text = "Окружение"
	toggle.button_pressed = true
	toggle.toggled.connect(func(on: bool): show_pack = on; _refresh())
	controls.add_child(toggle)
	var grid := CheckButton.new()
	grid.text = "Сетка"
	grid.toggled.connect(func(on: bool): show_grid = on; object_layer.queue_redraw())
	controls.add_child(grid)
	var reset := Button.new()
	reset.text = "Вписать в окно"
	reset.pressed.connect(_fit_view)
	controls.add_child(reset)
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_left = 24
	status.offset_top = -32
	status.offset_bottom = -8
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color("c8c4af"))
	ui.add_child(status)


func set_mode(mode: int) -> void:
	view_mode = mode
	if decoration_choice != null: decoration_choice.visible = mode == 3
	cells.clear()
	objects.clear()
	markers.clear()
	map_size = Vector2i(42, 28) if mode == 3 else Vector2i(24, 24) if mode == 0 else Vector2i(26, 22)
	elevation = Elevation.new(map_size)
	if mode == 0:
		_landscape()
	elif mode == 1:
		_gallery()
	elif mode == 2:
		_surfaces()
	else:
		_decoration_gallery()
	subtitle.text = ["Лесная опушка, вытоптанная земля и сухой склон. Здание и жители — исходные RoR.", "Деревья, камни и пни; справа — исходные объекты RoR.", "Четыре материала, переходы с травой RoR и рельеф с перепадом в один уровень.", "Все варианты выбранного семейства на подходящем грунте."][mode]
	_fit_view()


func _landscape() -> void:
	for y in range(map_size.y):
		for x in range(map_size.x):
			var p := Vector2(x, y)
			var forest := p.distance_to(Vector2(7, 7)) + sin(x * 0.7) * 0.65 + cos(y * 0.9) * 0.55
			var id := 0
			if forest < 4.0:
				id = 1000
			elif forest < 5.0:
				id = 1001
			elif forest < 6.4:
				id = 1003
			var dry := p.distance_to(Vector2(18, 9)) + sin(y * 0.6) * 0.7
			if dry < 4.3:
				id = 1002
			if dry < 2.2:
				id = 1001
			if absf(float(y) - 16.0 - sin(float(x) * 0.33)) < 0.75 and x > 7 and x < 19:
				id = 1001
			cells[Vector2i(x, y)] = id
	for y in range(3, 12):
		for x in range(3, 12):
			if Vector2(x, y).distance_to(Vector2(7, 7)) > 4.2 or posmod(x * 17 + y * 31, 5) == 0:
				continue
			var jitter := Vector2(sin(x * 19.1 + y), cos(y * 17.3 + x)) * 0.24
			_add("oak" if x < 8 else "pine", Vector2(x + 0.5, y + 0.5) + jitter, x + y * 7)
	for y in range(map_size.y + 1):
		for x in range(map_size.x + 1):
			if maxi(absi(x - 18), absi(y - 9)) < 3:
				elevation.set_vertex(Vector2i(x, y), 1)
	for i in range(6):
		_add("boulders", Vector2(17.0 + float(i % 3) * 1.05, 8.1 + float(i / 3) * 1.25), i)
	_add("stump", Vector2(10.8, 10.6), 0)
	_add("stump", Vector2(8.8, 12.0), 1)
	_add("stump", Vector2(6.2, 11.4), 2)
	_add_reference(Vector2(14.0, 18.0))
	markers = [{"position": Vector2(3.0, 12.0), "text": "ЛЕСНАЯ ОПУШКА"}, {"position": Vector2(20.0, 12.8), "text": "СУХОЙ СКЛОН"}, {"position": Vector2(16.0, 21.0), "text": "RoR + AoE2"}]


func _gallery() -> void:
	var groups := ["oak", "pine", "boulders", "stump"]
	for row in range(groups.size()):
		var key: String = groups[row]
		var count: int = catalog.environment_pack.object_variant_count(key)
		for i in range(count):
			_add(key, Vector2(3.0 + i * 2.0, 3.0 + row * 4.0), i)
		markers.append({"position": Vector2(6.0, 4.6 + row * 4.0), "text": String(catalog.environment_pack.object_definition(key)["title"]) + "  ·  %d" % count})
	for y in range(map_size.y):
		for x in range(map_size.x):
			cells[Vector2i(x, y)] = 1003 if y < 9 else 1001
	_add_reference(Vector2(20, 10))
	markers.append({"position": Vector2(21, 14), "text": "МАСШТАБ RoR"})


func _surfaces() -> void:
	for y in range(map_size.y):
		for x in range(map_size.x):
			var quadrant := (1 if x >= 13 else 0) + (2 if y >= 11 else 0)
			var local := Vector2i(x % 13, y % 11)
			var id := 1000 + quadrant if local.x >= 2 and local.x <= 10 and local.y >= 2 and local.y <= 8 else 0
			cells[Vector2i(x, y)] = id
	for region in range(4):
		var origin := Vector2i((region % 2) * 13, (region / 2) * 11)
		for y in range(4, 8):
			for x in range(5, 9):
				elevation.set_vertex(origin + Vector2i(x, y), 1)
		markers.append({"position": Vector2(origin + Vector2i(7, 10)), "text": String(catalog.environment_pack.materials_by_id[1000 + region]["title"])})


func _add(key: String, at: Vector2, variant: int) -> void:
	objects.append(catalog.environment_pack.scenery(key, at, objects.size() + 1, variant))


func _add_reference(at: Vector2) -> void:
	var meta: Dictionary = catalog.get_texture_metadata("town_center", 0)
	var hotspot: Array = meta.get("hotspot", [catalog.town_center_texture.get_width() / 2, catalog.town_center_texture.get_height()])
	objects.append({"position": at, "reference": true, "frame_info": {"texture": catalog.town_center_texture, "hotspot": Vector2(hotspot[0], hotspot[1])}})
	meta = catalog.get_texture_metadata("tree", 0)
	hotspot = meta.get("hotspot", [catalog.tree_texture.get_width() / 2, catalog.tree_texture.get_height()])
	objects.append({"position": at + Vector2(-3.0, 1.0), "reference": true, "frame_info": {"texture": catalog.tree_texture, "hotspot": Vector2(hotspot[0], hotspot[1])}})
	for i in range(3):
		var unit := {"id": i + 1, "kind": "villager", "team": 1, "texture_key": "villager", "direction": Vector2.DOWN, "pos": at + Vector2(0.7 + i * 0.7, 2.5), "hp": 25.0, "max_hp": 25.0}
		var info: Dictionary = catalog.unit_frame_info(unit, "idle", 0.0)
		if not info.is_empty():
			objects.append({"position": unit["pos"], "reference": true, "frame_info": info})


func terrain_id_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return -1
	return int(cells.get(cell, 0)) if show_pack else 0


func _fit_view() -> void:
	if not catalog.environment_pack.enabled:
		return
	var size := get_viewport_rect().size
	zoom = minf((size.x - 100.0) / ((map_size.x + map_size.y) * 32.0), (size.y - 200.0) / ((map_size.x + map_size.y) * 16.0))
	zoom = clampf(zoom, 0.5, 2.0)
	view_offset = Vector2(size.x * 0.5 - (map_size.x - map_size.y) * 16.0 * zoom, 134.0)
	_refresh()


func _refresh(reconfigure: bool = true) -> void:
	if not catalog.environment_pack.enabled:
		return
	revision += 1
	if reconfigure:
		terrain.view_zoom = zoom
		terrain.view_offset = view_offset
		terrain.viewport_size = get_viewport_rect().size
		terrain.terrain_revision = revision
		terrain.configure(map_size, 41721, catalog, {"terrain_elevation": elevation}, terrain_id_at, func(): return Rect2i(Vector2i.ZERO, map_size))
	else:
		terrain.set_view_state(zoom, view_offset, get_viewport_rect().size, revision)
	object_layer.queue_redraw()
	status.text = "4 покрытия  /  Смешанное окружение RoR и AoE2     •     Колесо — масштаб   ·   Средняя кнопка — перемещение   ·   1 / 2 / 3 / 4 — сцены     •     %d%%" % roundi(zoom * 100)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var previous := zoom
		zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.4, 3.0)
		view_offset = event.position - (event.position - view_offset) * zoom / previous
		_refresh(false)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		view_offset += event.relative
		terrain.set_view_state(zoom, view_offset, get_viewport_rect().size, revision)
		object_layer.queue_redraw()
	elif event is InputEventKey and event.pressed:
		if event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
			set_mode(event.keycode - KEY_1)
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _decoration_gallery() -> void:
	if decoration_keys.is_empty(): return
	var key: String = decoration_keys[maxi(0, decoration_choice.selected)]
	var spec: Dictionary = catalog.environment_pack.object_definition(key)
	var count: int = catalog.environment_pack.object_variant_count(key)
	for y in range(map_size.y):
		for x in range(map_size.x): cells[Vector2i(x, y)] = int(spec["placement"]["materials"][0])
	for i in range(count):
		var position := Vector2(7 + (i % 5) * 6, 7 + (i / 5) * 6)
		_add(key, position, i)
		markers.append({"position": position + Vector2(1.5, 1.5), "text": "%d" % (i + 1)})
