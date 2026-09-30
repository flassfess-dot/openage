extends "res://scripts/environment_preview.gd"

const Settings := preload("res://scripts/skirmish_settings.gd")
var generated: Dictionary = {}
var profile_choice: OptionButton
var seed_input: SpinBox
var profiles: Array = []

func _ready() -> void:
	get_window().title = "Rise of Rome — новые случайные карты"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	catalog.load()
	catalog.enable_environment_pack()
	_build_map_ui()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed_input.value = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--map-type="):
			for index in range(profiles.size()):
				if profiles[index]["id"] == argument.trim_prefix("--map-type="): profile_choice.select(index)
	add_child(terrain)
	add_child(object_layer)
	object_layer.preview = self
	label_style.bg_color = Color(0.065, 0.08, 0.065, 0.88)
	get_viewport().size_changed.connect(_fit_view)
	generate_map()

func _build_map_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 104
	ui.add_child(panel)
	var row := HBoxContainer.new()
	row.position = Vector2(20, 12)
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var title := Label.new()
	title.text = "НОВЫЕ СЛУЧАЙНЫЕ КАРТЫ"
	row.add_child(title)
	profile_choice = OptionButton.new()
	profiles = Settings.catalog()["map_types"]
	for profile in profiles: profile_choice.add_item(String(profile.get("name", profile["id"])))
	profile_choice.select(3)
	row.add_child(profile_choice)
	seed_input = SpinBox.new()
	seed_input.min_value = 1
	seed_input.max_value = 2147483647
	seed_input.value = 41721
	row.add_child(seed_input)
	var generate_button := Button.new()
	generate_button.text = "Создать карту"
	generate_button.pressed.connect(generate_map)
	row.add_child(generate_button)
	var next_button := Button.new()
	next_button.text = "Другой вариант"
	next_button.pressed.connect(func(): seed_input.value += 1; generate_map())
	row.add_child(next_button)
	var fit_button := Button.new()
	fit_button.text = "Вся карта"
	fit_button.pressed.connect(_fit_view)
	row.add_child(fit_button)
	status = Label.new()
	status.position = Vector2(20, 58)
	panel.add_child(status)
	subtitle = Label.new()
	subtitle.position = Vector2(20, 80)
	subtitle.text = "Колесо — масштаб · Средняя кнопка — перемещение · Карты доступны в обычной случайной игре"
	panel.add_child(subtitle)

func generate_map() -> void:
	var settings := Settings.default_settings()
	settings["map_type_id"] = profiles[profile_choice.selected]["id"]
	settings["seed"] = int(seed_input.value)
	for i in range(8): settings["players"][i]["enabled"] = i < 4
	generated = Settings.build(settings)
	if not bool(generated.get("valid", false)):
		status.text = "Не удалось создать карту: " + str(generated.get("errors", []))
		return
	var data: Dictionary = generated["map_data"]
	map_size = data["size"]
	cells.clear()
	objects.clear()
	markers.clear()
	elevation = Elevation.new(map_size)
	for y in range(map_size.y + 1):
		for x in range(map_size.x + 1): elevation.set_vertex(Vector2i(x, y), int(data["vertex_levels"][y * (map_size.x + 1) + x]))
	for y in range(map_size.y):
		for x in range(map_size.x): cells[Vector2i(x, y)] = int(data["terrain_ids"][y * map_size.x + x])
	objects.append_array(data["scenery"])
	for resource in data["resources"]:
		var info: Dictionary = {}
		if resource.get("category", "resource") == "resource":
			info = catalog.resource_frame_info(resource)
		else:
			var unit: Dictionary = resource.duplicate(true)
			unit["id"] = objects.size() + 1
			unit["team"] = 0
			unit["pos"] = resource["position"]
			unit["texture_key"] = resource["kind"]
			unit["direction"] = Vector2.DOWN
			info = catalog.unit_frame_info(unit, "idle", 0.0)
		if not info.is_empty(): objects.append({"position": resource["position"], "reference": true, "frame_info": info})
	for player in generated["definition"]["players"]:
		var at := Vector2(player["start"])
		var town := {"kind": "town_center", "team": int(player["team"]), "state": "complete", "hp": 600.0, "max_hp": 600.0, "components": {"ownership": {"civilization_id": int(player["civilization_id"])}}}
		var info: Dictionary = catalog.building_frame_info(town)
		if info.get("texture") != null: objects.append({"position": at, "reference": true, "frame_info": info})
		for part in info.get("composite_parts", []):
			if part.get("texture") != null: objects.append({"position": at, "reference": true, "frame_info": part})
		markers.append({"position": at + Vector2(0, 3), "text": "ИГРОК %d" % int(player["team"])})
	_fit_view()
	print("Generated landscape preview ready: %s seed %d" % [settings["map_type_id"], settings["seed"]])

func terrain_id_at(cell: Vector2i) -> int:
	return int(cells.get(cell, -1))

func _fit_view() -> void:
	if generated.is_empty() or not bool(generated.get("valid", false)): return
	var viewport := get_viewport_rect().size
	zoom = minf((viewport.x - 60.0) / ((map_size.x + map_size.y) * 32.0), (viewport.y - 180.0) / ((map_size.x + map_size.y) * 16.0))
	view_offset = Vector2(viewport.x * 0.5, 134.0)
	_refresh()

func _refresh(reconfigure: bool = true) -> void:
	if generated.is_empty() or not bool(generated.get("valid", false)): return
	if reconfigure:
		revision += 1
		terrain.view_zoom = zoom
		terrain.view_offset = view_offset
		terrain.viewport_size = get_viewport_rect().size
		terrain.terrain_revision = revision
		terrain.configure(map_size, int(seed_input.value), catalog, {"terrain_elevation": elevation}, terrain_id_at, func(): return Rect2i(Vector2i.ZERO, map_size))
	else:
		terrain.set_view_state(zoom, view_offset, get_viewport_rect().size, revision)
	object_layer.queue_redraw()
	var sources: Dictionary = generated["map_data"]["ecology"]["tree_sources"]
	status.text = "%d × %d · 4 игрока · Деревья RoR: %d · AoE2: %d · %d природных деталей · Масштаб %d%%" % [map_size.x, map_size.y, sources["ror"], sources["aoe2"], generated["map_data"]["scenery"].size(), roundi(zoom * 100)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var previous := zoom
		zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.18, 3.0)
		view_offset = event.position - (event.position - view_offset) * zoom / previous
		_refresh(false)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		view_offset += event.relative
		_refresh(false)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
