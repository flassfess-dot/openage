class_name RoRHUDControls
extends Control

const InterfaceLayout := preload("res://scripts/interface_layout.gd")
const StatusPanel := preload("res://scripts/hud_status_panel.gd")
const Typography := preload("res://scripts/hud_typography.gd")

signal building_selected(building_id: int)
signal formation_requested(formation_name: String)
signal build_requested(building_kind: String)
signal build_menu_opened
signal train_requested(unit_kind: String, building_id: int)
signal research_requested(technology_id: int, building_id: int)
signal cancel_production_requested(building_id: int, queue_index: int)
signal trade_resource_requested(resource_type_id: int)
signal unit_action_requested(action_name: String)

const HUD_HEIGHT: float = InterfaceLayout.BOTTOM_HEIGHT
const FORMATIONS := [
	["LINE", "F5 LINE", "Line formation"],
	["RECTANGLE", "F6 BLOCK", "Compact block formation"],
	["COLUMN", "F7 COLUMN", "Narrow column formation"],
	["WEDGE", "F8 WEDGE", "Wedge formation"],
	["STAGGERED", "F9 STAGGER", "Staggered formation"],
]
const FORMATION_ICONS := {
	"LINE": preload("res://assets/ui/formations/formation_line.png"),
	"RECTANGLE": preload("res://assets/ui/formations/formation_rectangle.png"),
	"COLUMN": preload("res://assets/ui/formations/formation_column.png"),
	"WEDGE": preload("res://assets/ui/formations/formation_wedge.png"),
	"STAGGERED": preload("res://assets/ui/formations/formation_staggered.png"),
}

var status_panel: StatusPanel
var formation_buttons: Dictionary = {}
var train_button: Button
var train_buttons: Array[Button] = []
var queue_badges: Array[Label] = []
var hotkey_badges: Array[Label] = []
var active_train_commands: Array = []
var formation_group := ButtonGroup.new()
var trade_resource_group := ButtonGroup.new()
var icon_registry
var interface_skin
var interface_style_index := 0
var current_layout: Dictionary = {}
var current_model: Dictionary = {}
var selection_context := ""
var build_menu_open := false
var available_formation_buttons: Array[Button] = []
var previous_commands_button: Button
var next_commands_button: Button
var command_page := 0
var command_page_size := 1
var command_page_count := 1
var command_signature := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_controls()
	status_panel = StatusPanel.new()
	add_child(status_panel)
	status_panel.cancel_requested.connect(func(building_id: int, queue_index: int): cancel_production_requested.emit(building_id, queue_index))
	status_panel.building_selected.connect(func(building_id: int): building_selected.emit(building_id))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not formation_buttons.is_empty():
		current_layout = InterfaceLayout.for_viewport(size)
		layout_controls()

func build_controls() -> void:
	for index in range(FORMATIONS.size()):
		var definition: Array = FORMATIONS[index]
		var formation_name: String = definition[0]
		var button := Button.new()
		button.text = ""
		button.icon = FORMATION_ICONS[formation_name]
		button.expand_icon = true
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.tooltip_text = definition[2]
		button.toggle_mode = true
		button.button_group = formation_group
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		apply_button_theme(button)
		button.add_theme_font_size_override("font_size", 9)
		button.clip_text = true
		set_bottom_rect(button, Rect2(4, 4, 41, 31))
		button.pressed.connect(_on_formation_pressed.bind(formation_name))
		formation_buttons[formation_name] = button
		add_child(button)

	for index in range(18):
		_append_action_button()
	train_button = train_buttons[0]
	previous_commands_button = _make_command_page_button("‹", "Предыдущие команды", -1)
	next_commands_button = _make_command_page_button("›", "Следующие команды", 1)


func _make_command_page_button(label: String, tooltip: String, step: int) -> Button:
	var button := Button.new()
	button.text = label
	button.tooltip_text = tooltip
	button.visible = false
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	apply_button_theme(button)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(func():
		command_page = clampi(command_page + step, 0, command_page_count - 1)
		layout_controls()
	)
	add_child(button)
	return button


func _append_action_button() -> void:
	var index := train_buttons.size()
	var button := Button.new()
	button.visible = false
	button.tooltip_text = "Команда производства"
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.expand_icon = true
	button.clip_text = true
	apply_button_theme(button)
	button.pressed.connect(_on_action_pressed.bind(index))
	button.gui_input.connect(_on_action_gui_input.bind(index))
	var badge := Label.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_right = 1.0
	badge.anchor_bottom = 1.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Color("fff1bd"))
	badge.add_theme_color_override("font_outline_color", Color("1a1109"))
	badge.add_theme_constant_override("outline_size", 2)
	badge.visible = false
	button.add_child(badge)
	train_buttons.append(button)
	queue_badges.append(badge)
	var hotkey := Label.new()
	hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotkey.position = Vector2(4, 34)
	hotkey.add_theme_font_override("font", Typography.body_font())
	hotkey.add_theme_font_size_override("font_size", 11)
	hotkey.add_theme_color_override("font_color", Color("fff1bd"))
	hotkey.add_theme_color_override("font_outline_color", Color("1a1109"))
	hotkey.add_theme_constant_override("outline_size", 2)
	button.add_child(hotkey)
	hotkey_badges.append(hotkey)
	add_child(button)
	if interface_skin != null:
		apply_source_command_theme(button)


func _ensure_action_button_capacity(required: int) -> void:
	while train_buttons.size() < required:
		_append_action_button()


func configure_icons(registry) -> void:
	icon_registry = registry
	status_panel.icon_registry = registry


func configure_interface_skin(skin, style_index: int = 0) -> void:
	interface_skin = skin
	interface_style_index = clampi(style_index, 0, 4)
	status_panel.configure(icon_registry, skin, interface_style_index)
	for button_value in formation_buttons.values() + train_buttons + [previous_commands_button, next_commands_button]:
		apply_source_command_theme(button_value)


func set_layout(layout: Dictionary) -> void:
	current_layout = layout.duplicate(true)
	layout_controls()

func set_state(formation_name: String, can_train: bool) -> void:
	available_formation_buttons.clear()
	for key in formation_buttons:
		formation_buttons[key].visible = true
		available_formation_buttons.append(formation_buttons[key])
		formation_buttons[key].set_pressed_no_signal(key == formation_name)
	train_button.visible = true
	train_button.text = "TRAIN"
	layout_controls()
	train_button.disabled = not can_train


func set_view_model(model: Dictionary) -> void:
	current_model = model
	status_panel.set_view_model(model)
	var selection: Dictionary = model.get("selection", {})
	var leader: Dictionary = selection.get("leader", {})
	var new_context := "%s:%d:%s" % [String(selection.get("category", "none")), int(leader.get("id", -1)), String(leader.get("kind", ""))]
	if new_context != selection_context:
		selection_context = new_context
		build_menu_open = false
		command_page = 0
	var formation_commands: Dictionary = {}
	active_train_commands.clear()
	var build_commands: Array = []
	for command_value in model.get("commands", []):
		var command: Dictionary = command_value
		match String(command.get("type", "")):
			"formation": formation_commands[String(command.get("id", ""))] = command
			"build": build_commands.append(command)
			"train", "research", "trade_resource", "unit_action":
				if not (String(selection.get("category", "")) == "building" and String(command.get("type", "")) == "unit_action" and String(command.get("id", "")) == "stop"):
					active_train_commands.append(command)
	if build_commands.is_empty():
		build_menu_open = false
	if not build_commands.is_empty():
		var unit_actions := active_train_commands.filter(func(command): return String(command.get("type", "")) == "unit_action")
		active_train_commands.clear()
		if build_menu_open:
			active_train_commands.append_array(build_commands)
			active_train_commands.append({"type": "close_build_menu", "id": "close_build_menu", "label": "Назад", "hotkey": "Esc", "enabled": true, "reason": ""})
		else:
			# The original first hammer opens Build; the second command is Repair.
			active_train_commands.append({"type": "open_build_menu", "id": "open_build_menu", "label": "Строить", "hotkey": "B", "enabled": true, "reason": ""})
			active_train_commands.append_array(unit_actions.filter(func(command): return command.get("id") == "repair"))
			active_train_commands.append_array(unit_actions.filter(func(command): return command.get("id") != "repair"))
	available_formation_buttons.clear()
	for formation_name in formation_buttons:
		var button: Button = formation_buttons[formation_name]
		var command: Dictionary = formation_commands.get(formation_name, {})
		button.visible = not build_menu_open and not command.is_empty()
		if command.is_empty():
			continue
		if not build_menu_open:
			available_formation_buttons.append(button)
		button.text = ""
		button.icon = FORMATION_ICONS[formation_name]
		button.disabled = not bool(command.get("enabled", false))
		button.set_pressed_no_signal(bool(command.get("active", false)))
		var hotkey := String(command.get("hotkey", ""))
		var label := String(command.get("label", formation_name))
		button.tooltip_text = reason_text(String(command.get("reason", ""))) if button.disabled else "%s%s" % [label, " (%s)" % hotkey if not hotkey.is_empty() else ""]
	var identities: Array = []
	for command in active_train_commands:
		identities.append([command.get("type"), command.get("id")])
	for button in available_formation_buttons:
		identities.append(button.get_instance_id())
	var next_signature := hash(identities)
	if next_signature != command_signature:
		command_signature = next_signature
		command_page = 0
	_ensure_action_button_capacity(active_train_commands.size())
	for index in range(train_buttons.size()):
		var button: Button = train_buttons[index]
		button.visible = index < active_train_commands.size()
		if not button.visible:
			continue
		var command: Dictionary = active_train_commands[index]
		var cost_text := String(command.get("cost_text", ""))
		var label := String(command.get("label", command.get("id", "")))
		var icon := command_icon(command)
		button.icon = icon
		button.expand_icon = true
		var hotkey := String(command.get("hotkey", ""))
		var short_label := String(command.get("short_label", label))
		hotkey_badges[index].text = hotkey
		button.text = "" if icon != null else short_label
		var queue_count := int(command.get("queue_count", 0))
		queue_badges[index].visible = queue_count > 0
		queue_badges[index].text = "×%d" % queue_count if queue_count > 0 else ""
		button.disabled = not bool(command.get("enabled", false))
		button.toggle_mode = String(command.get("type", "")) == "trade_resource"
		button.button_group = trade_resource_group if button.toggle_mode else null
		button.set_pressed_no_signal(button.toggle_mode and bool(command.get("active", false)))
		var description := "%s%s" % [label, " — %s" % cost_text if not cost_text.is_empty() else ""]
		if float(command.get("duration", 0.0)) > 0.0:
			description += " · %.0f сек." % float(command.get("duration", 0.0))
		if queue_count > 0:
			description += " · В очереди: %d" % queue_count
			if String(command.get("type", "")) == "train":
				description += " · ПКМ: отменить одного"
		if not hotkey.is_empty():
			description += " · %s" % hotkey
		button.tooltip_text = reason_text(String(command.get("reason", ""))) if button.disabled else description
	layout_controls()


func layout_controls() -> void:
	if current_layout.is_empty():
		current_layout = InterfaceLayout.for_viewport(size)
	var command_rect: Rect2 = current_layout.get("command", Rect2(4, size.y - HUD_HEIGHT + 4, 300, HUD_HEIGHT - 8))
	var bottom_height := float(current_layout.get("bottom", Rect2(0, size.y - HUD_HEIGHT, size.x, HUD_HEIGHT)).size.y)
	var local_rect := Rect2(command_rect.position - Vector2(0, size.y - bottom_height), command_rect.size)
	if status_panel != null:
		status_panel.size = size
		status_panel.set_layout(current_layout if current_layout.has("production") else {})
	var commands: Array[Button] = []
	for index in range(train_buttons.size()):
		var button := train_buttons[index]
		button.visible = false
		if index < active_train_commands.size():
			commands.append(button)
	# Compatibility entry point before a view model has been supplied.
	if current_model.is_empty() and train_button != null:
		commands.append(train_button)
	for button in formation_buttons.values():
		button.visible = false
	commands.append_array(available_formation_buttons)
	var grid := command_grid(local_rect.size)
	var capacity: int = grid["capacity"]
	var pinned_cancel: Button = null
	if build_menu_open and not active_train_commands.is_empty() and active_train_commands.back().get("type") == "close_build_menu":
		pinned_cancel = train_buttons[active_train_commands.size() - 1]
		commands.erase(pinned_cancel)
	elif not build_menu_open:
		for index in range(active_train_commands.size()):
			if active_train_commands[index].get("type") == "unit_action" and active_train_commands[index].get("id") == "delete":
				pinned_cancel = train_buttons[index]
				commands.erase(pinned_cancel)
				break
	var paged := commands.size() > capacity - (1 if pinned_cancel != null else 0)
	command_page_size = capacity - (2 if paged else 0) - (1 if pinned_cancel != null else 0)
	command_page_size = maxi(1, command_page_size)
	command_page_count = maxi(1, ceili(float(commands.size()) / command_page_size)) if paged else 1
	command_page = clampi(command_page, 0, command_page_count - 1)
	var displayed: Array[Button] = []
	for index in range(command_page * command_page_size, mini(commands.size(), (command_page + 1) * command_page_size)):
		displayed.append(commands[index])
	if paged or pinned_cancel != null:
		# The original red cross stays in the final cell for Delete and Back.
		while displayed.size() < command_page_size:
			displayed.append(null)
		if paged:
			displayed.append(previous_commands_button)
			displayed.append(next_commands_button)
		if pinned_cancel != null:
			displayed.append(pinned_cancel)
	previous_commands_button.visible = paged
	next_commands_button.visible = paged
	previous_commands_button.disabled = command_page == 0
	next_commands_button.disabled = command_page + 1 >= command_page_count
	previous_commands_button.tooltip_text = "Предыдущие команды (%d/%d)" % [command_page + 1, command_page_count]
	next_commands_button.tooltip_text = "Следующие команды (%d/%d)" % [command_page + 1, command_page_count]
	var cell_size: Vector2 = grid["cell_size"]
	var columns: int = grid["columns"]
	for slot in range(displayed.size()):
		var button := displayed[slot]
		if button == null:
			continue
		button.visible = true
		var column := slot % columns
		var row := floori(float(slot) / float(columns))
		set_bottom_rect(button, Rect2(local_rect.position + Vector2(column, row) * (InterfaceLayout.COMMAND_CELL_SIZE + InterfaceLayout.COMMAND_GAP), cell_size))
		button.add_theme_constant_override("icon_max_width", int(InterfaceLayout.COMMAND_CELL_SIZE) - 14)
		if train_buttons.has(button):
			hotkey_badges[train_buttons.find(button)].position = Vector2(4, InterfaceLayout.COMMAND_CELL_SIZE - 16)


static func command_grid(available_size: Vector2) -> Dictionary:
	var stride := InterfaceLayout.COMMAND_CELL_SIZE + InterfaceLayout.COMMAND_GAP
	var columns := maxi(1, floori((available_size.x + InterfaceLayout.COMMAND_GAP) / stride))
	var rows := maxi(1, floori((available_size.y + InterfaceLayout.COMMAND_GAP) / stride))
	return {"columns": columns, "rows": rows, "capacity": columns * rows, "cell_size": Vector2.ONE * InterfaceLayout.COMMAND_CELL_SIZE}


func set_bottom_rect(control: Control, rectangle: Rect2) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = rectangle.position.x
	control.offset_right = rectangle.end.x
	var bottom_height := float(current_layout.get("bottom", Rect2(0, 0, size.x, HUD_HEIGHT)).size.y)
	control.offset_top = -bottom_height + rectangle.position.y
	control.offset_bottom = -bottom_height + rectangle.end.y

func apply_button_theme(button: Button) -> void:
	button.add_theme_font_override("font", Typography.body_font())
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_constant_override("icon_max_width", 36)
	button.add_theme_color_override("font_color", Color("fff1bd"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("fff5c9"))
	button.add_theme_color_override("font_disabled_color", Color("8c826d"))
	button.add_theme_stylebox_override("normal", make_style(Color("725b37"), Color("d7bd7c")))
	button.add_theme_stylebox_override("hover", make_style(Color("8a7044"), Color("f1d890")))
	button.add_theme_stylebox_override("pressed", make_style(Color("9b7c42"), Color("fff1bd")))
	button.add_theme_stylebox_override("disabled", make_style(Color("443b2d"), Color("746850")))


func apply_source_command_theme(button: Button) -> void:
	if interface_skin == null:
		return
	var backplate: Texture2D = interface_skin.square_command_backplate(interface_style_index)
	if backplate == null:
		return
	button.add_theme_stylebox_override("normal", texture_style(backplate, Color.WHITE))
	button.add_theme_stylebox_override("hover", texture_style(backplate, Color(1.08, 1.08, 1.08, 1.0)))
	button.add_theme_stylebox_override("pressed", texture_style(backplate, Color(0.78, 0.78, 0.78, 1.0)))
	button.add_theme_stylebox_override("disabled", texture_style(backplate, Color(0.48, 0.48, 0.48, 1.0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func texture_style(texture: Texture2D, modulation: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = modulation
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func command_icon(command: Dictionary) -> Texture2D:
	var command_type := String(command.get("type", ""))
	if interface_skin != null and command_type == "trade_resource":
		var resource_name := String({0: "food", 1: "wood", 2: "stone"}.get(int(command.get("resource_type_id", -1)), ""))
		return interface_skin.resource_icon(resource_name, interface_style_index)
	if interface_skin != null and command_type == "open_build_menu":
		var glyphs: Array = interface_skin.source_candidate(50721).get("frames", [])
		return glyphs[2] if glyphs.size() > 2 else null
	if interface_skin != null and command_type == "cancel_production":
		var glyphs: Array = interface_skin.source_candidate(50721).get("frames", [])
		return glyphs[10] if glyphs.size() > 10 else null
	if interface_skin != null and command_type == "close_build_menu":
		var glyphs: Array = interface_skin.source_candidate(50721).get("frames", [])
		return glyphs[10] if glyphs.size() > 10 else null
	return icon_registry.texture(String(command.get("icon_kind", "")), int(command.get("icon_id", -1))) if icon_registry != null else null

func make_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style

func _on_formation_pressed(formation_name: String) -> void:
	formation_requested.emit(formation_name)


func _on_action_pressed(index: int) -> void:
	if index < 0 or index >= active_train_commands.size():
		return
	var command: Dictionary = active_train_commands[index]
	match String(command.get("type", "")):
		"open_build_menu":
			set_build_menu_open(true)
		"close_build_menu":
			set_build_menu_open(false)
		"build":
			set_build_menu_open(false)
			build_requested.emit(String(command.get("id", "")))
		"train":
			for request_index in range(training_batch_size(command, Input.is_key_pressed(KEY_SHIFT))):
				train_requested.emit(String(command.get("id", "")), int(command.get("building_id", -1)))
		"research": research_requested.emit(int(command.get("technology_id", -1)), int(command.get("building_id", -1)))
		"cancel_production": cancel_production_requested.emit(int(command.get("building_id", -1)), int(command.get("queue_index", 0)))
		"trade_resource": trade_resource_requested.emit(int(command.get("resource_type_id", -1)))
		"unit_action": unit_action_requested.emit(String(command.get("id", "")))


func set_build_menu_open(open: bool) -> bool:
	if open and not current_model.get("commands", []).any(func(command): return command.get("type") == "build"):
		return false
	build_menu_open = open
	set_view_model(current_model)
	if open:
		build_menu_opened.emit()
	return build_menu_open == open


func _on_action_gui_input(event: InputEvent, index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if index < 0 or index >= active_train_commands.size():
		return
	var command: Dictionary = active_train_commands[index]
	if String(command.get("type", "")) != "train" or int(command.get("cancel_queue_index", -1)) < 0 or bool(current_model.get("read_only", false)):
		return
	cancel_production_requested.emit(int(command.get("building_id", -1)), int(command.get("cancel_queue_index", -1)))
	if is_inside_tree():
		train_buttons[index].accept_event()


static func reason_text(reason: String) -> String:
	return String({
		"single_unit": "Для строя выберите несколько юнитов",
		"battle_over": "Матч завершён",
		"player_not_active": "Режим наблюдателя",
		"insufficient_resources": "Недостаточно ресурсов",
		"population_cap": "Достигнут предел населения",
		"queue_full": "Очередь заполнена",
		"different_unit_line_queued": "Сначала завершите или остановите текущую линию",
		"research_in_progress": "В здании идёт исследование",
		"building_busy": "Здание занято производством",
		"unit_unavailable": "Юнит ещё не открыт",
		"building_unavailable": "Здание ещё не открыто",
		"invalid_production_building": "Здание не может производить этот юнит",
	}.get(reason, reason))


func update_dynamic_model(model: Dictionary) -> void:
	current_model = model
	status_panel.update_dynamic_model(model)


func training_batch_size(command: Dictionary, multiple: bool) -> int:
	if not multiple:
		return 1
	var count := mini(5, maxi(0, 15 - current_model.get("queue", []).size()))
	var resources: Dictionary = current_model.get("resources", {})
	var names := {0: "food", 1: "wood", 2: "stone", 3: "gold"}
	for resource_id in command.get("cost", {}):
		var cost := int(command["cost"][resource_id])
		if cost > 0:
			count = mini(count, floori(float(resources.get(names.get(int(resource_id), ""), 0)) / cost))
	return count
