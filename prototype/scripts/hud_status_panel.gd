class_name RoRHUDStatusPanel
extends Control

const Typography := preload("res://scripts/hud_typography.gd")
const Aperture := preload("res://scripts/minimap_aperture.gd")
const MASK := Color(0.063, 0.063, 0.051, 0.80)
const INK := Color("f4e6c7")

signal cancel_requested(building_id: int, queue_index: int)
signal building_selected(building_id: int)

var model: Dictionary = {}
var layout: Dictionary = {}
var icon_registry
var skin
var style_index := 0
var frame_texture: Texture2D
var name_label: Label
var owner_label: Label
var stats_label: Label
var portrait: TextureRect
var job_icon: TextureRect
var job_label: Label
var percent_label: Label
var time_label: Label
var cancel_button: Button
var previous_button: Button
var next_button: Button
var pending_buttons: Array[Button] = []
var pending_groups: Array = []
var queue_page := 0
var queue_page_size := 1
var context_id := -1
var global_buttons: Array[Button] = []
var global_more: Button
var global_popup: PopupMenu
var global_entries: Array = []
var visible_global_count := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label = make_label(14, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	owner_label = make_label(12, true)
	owner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label = make_label(12, true)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait = make_icon()
	job_icon = make_icon()
	job_label = make_label(16, true)
	job_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_label.max_lines_visible = 2
	job_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	percent_label = make_label(14, true)
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label = make_label(12, true)
	cancel_button = make_button(24)
	cancel_button.tooltip_text = "Отменить текущий заказ"
	cancel_button.pressed.connect(func(): cancel_requested.emit(context_id, 0))
	previous_button = make_button(0)
	previous_button.text = "‹"
	previous_button.tooltip_text = "Предыдущие заказы"
	previous_button.pressed.connect(func(): queue_page = maxi(0, queue_page - 1); layout_pending())
	next_button = make_button(0)
	next_button.text = "›"
	next_button.tooltip_text = "Следующие заказы"
	next_button.pressed.connect(func(): queue_page += 1; layout_pending())
	for index in range(14):
		var button := make_button(26)
		button.pressed.connect(_cancel_pending.bind(index))
		pending_buttons.append(button)
	for index in range(12):
		var button := make_button(32)
		button.pressed.connect(_select_global.bind(index))
		global_buttons.append(button)
	global_more = make_button(0)
	global_more.tooltip_text = "Остальные производящие здания"
	global_more.pressed.connect(_show_global_popup)
	global_popup = PopupMenu.new()
	global_popup.add_theme_font_override("font", Typography.body_font())
	global_popup.add_theme_font_size_override("font_size", 14)
	global_popup.id_pressed.connect(_select_global)
	add_child(global_popup)


func configure(registry, interface_skin, requested_style: int) -> void:
	icon_registry = registry
	skin = interface_skin
	style_index = clampi(requested_style, 0, 4)
	frame_texture = Aperture.frame_texture(skin.hud_shell(1024, style_index).get("bottom"))
	cancel_button.icon = skin.texture("hud_glyph_50721", 10)
	for button in pending_buttons + global_buttons + [cancel_button, previous_button, next_button, global_more]:
		style_button(button)
	queue_redraw()


func set_layout(value: Dictionary) -> void:
	layout = value
	layout_contents()
	queue_redraw()


func set_view_model(value: Dictionary) -> void:
	model = value
	var leader: Dictionary = model.get("selection", {}).get("leader", {})
	var next_context := int(leader.get("id", -1))
	if context_id != next_context:
		queue_page = 0
	context_id = next_context
	name_label.text = String(leader.get("name", ""))
	portrait.texture = icon_for(leader)
	portrait.tooltip_text = "%s\nАтака: %d · Броня: %d" % [String(leader.get("civilization_name", "")), int(leader.get("attack", 0)), int(leader.get("armor", 0))]
	var category := String(model.get("selection", {}).get("category", ""))
	owner_label.text = String(leader.get("civilization_name", ""))
	if category == "resource":
		owner_label.text = "Осталось: %d" % int(leader.get("resource_amount", 0))
	elif bool(leader.get("show_population", false)):
		owner_label.text = "%d/%d" % [int(leader.get("population_current", 0)), int(leader.get("population_cap", 0))]
	elif int(leader.get("carried_amount", 0)) > 0:
		owner_label.text = "%s: %d" % [String({"food": "Пища", "wood": "Дерево", "stone": "Камень", "gold": "Золото"}.get(leader.get("carried_resource", ""), "Груз")), int(leader.get("carried_amount", 0))]
	elif bool(leader.get("conversion_enabled", false)):
		owner_label.text = "Вера: %d" % roundi(float(leader.get("faith", 0)))
	elif category == "unit" and bool(leader.get("show_combat_stats", true)):
		owner_label.text = "АТК %d · БРН %d" % [int(leader.get("attack", 0)), int(leader.get("armor", 0))]
	stats_label.text = "%d/%d" % [int(leader.get("hp", 0)), int(leader.get("max_hp", 0))] if bool(leader.get("show_hp", true)) else "%d/%d" % [int(leader.get("resource_amount", 0)), int(leader.get("resource_maximum", 0))]
	var count := int(model.get("selection", {}).get("count", 0))
	if count > 1:
		name_label.text = "%d × %s" % [count, name_label.text]
	for node in [name_label, owner_label, stats_label, portrait]:
		node.visible = not leader.is_empty()
	pending_groups = group_pending(model.get("queue", []))
	global_entries = model.get("global_queue", [])
	update_dynamic_model(value)
	layout_contents()


func update_dynamic_model(value: Dictionary) -> void:
	model = value
	var orders: Array = model.get("queue", [])
	var active: Dictionary = orders[0] if not orders.is_empty() else {}
	for node in [job_label, job_icon, percent_label, time_label, cancel_button]:
		node.visible = not active.is_empty()
	if not active.is_empty():
		job_label.text = String(active.get("label", ""))
		job_label.tooltip_text = job_label.text
		job_icon.texture = icon_for(active)
		percent_label.text = "%d%%" % floori(float(active.get("progress", 0)) * 100)
		var status := String(active.get("status", ""))
		time_label.text = "Лимит населения" if status == "blocked_population" else "Выход занят" if status == "blocked_spawn" else "%s · %d с" % ["Исследуется" if String(active.get("type", "unit")) == "research" else "Нанимается", ceili(float(active.get("remaining_seconds", 0)))]
		cancel_button.disabled = bool(model.get("read_only", false))
		job_icon.visible = _show_job_icon()
	global_entries = model.get("global_queue", [])
	queue_redraw()


static func group_pending(orders: Array) -> Array:
	var result: Array = []
	for index in range(1, orders.size()):
		var order: Dictionary = orders[index]
		var last: Dictionary = result.back() if not result.is_empty() else {}
		if String(order.get("type", "unit")) == "unit" and not last.is_empty() and last.get("type") == "unit" and last.get("kind") == order.get("kind"):
			last["count"] += 1
		else:
			var group := order.duplicate()
			group["count"] = 1
			group["first_index"] = index
			result.append(group)
	return result


func layout_contents() -> void:
	if layout.is_empty():
		return
	var card: Rect2 = layout["selection"]
	place(name_label, Rect2(card.position + Vector2(6, 3), Vector2(116, 30)))
	place(portrait, Rect2(card.position + Vector2(43, 35), Vector2(42, 42)))
	place(stats_label, Rect2(card.position + Vector2(6, 87), Vector2(116, 14)))
	place(owner_label, Rect2(card.position + Vector2(6, 103), Vector2(116, 14)))
	var production: Rect2 = layout["production"]
	var icon_space := 46.0 if _show_job_icon() else 0.0
	place(job_icon, Rect2(production.position + Vector2(8, 5), Vector2(38, 38)))
	place(job_label, Rect2(production.position + Vector2(8 + icon_space, 5), Vector2(maxf(1, production.size.x - 59 - icon_space), 46)))
	place(percent_label, Rect2(Vector2(production.end.x - 43, production.position.y + 5), Vector2(35, 18)))
	place(time_label, Rect2(production.position + Vector2(8, 63), Vector2(production.size.x - 16, 14)))
	place(cancel_button, Rect2(Vector2(production.end.x - 42, production.position.y + 79), Vector2(34, 34)))
	layout_pending()
	layout_global()
	job_icon.visible = not model.get("queue", []).is_empty() and _show_job_icon()


func layout_pending() -> void:
	if layout.is_empty():
		return
	var production: Rect2 = layout["production"]
	var available := production.size.x - 58
	var capacity := maxi(1, floori((available + 4) / 38))
	var paged := pending_groups.size() > capacity
	queue_page_size = maxi(1, floori((available - 56) / 38)) if paged else capacity
	queue_page = clampi(queue_page, 0, maxi(0, ceili(float(pending_groups.size()) / queue_page_size) - 1))
	var x := production.position.x + 8
	var y := production.position.y + 79
	previous_button.visible = paged
	next_button.visible = paged
	if paged:
		place(previous_button, Rect2(x, y, 26, 34))
		x += 30
		previous_button.disabled = queue_page == 0
	for index in range(pending_buttons.size()):
		var button := pending_buttons[index]
		var group_index := queue_page * queue_page_size + index
		button.visible = index < queue_page_size and group_index < pending_groups.size()
		if not button.visible:
			continue
		var group: Dictionary = pending_groups[group_index]
		button.icon = icon_for(group)
		button.set_meta("group_index", group_index)
		button.tooltip_text = "%s%s" % [String(group.get("label", "")), " ×%d" % int(group["count"]) if int(group["count"]) > 1 else ""]
		button.disabled = bool(model.get("read_only", false))
		var badge: Label = button.get_node("Count")
		badge.text = "×%d" % int(group["count"]) if int(group["count"]) > 1 else ""
		place(button, Rect2(x, y, 34, 34))
		x += 38
	if paged:
		place(next_button, Rect2(x, y, 26, 34))
		next_button.disabled = (queue_page + 1) * queue_page_size >= pending_groups.size()


func layout_global() -> void:
	if layout.is_empty():
		return
	var available_slots := maxi(1, floori((size.x - 16) / 50))
	visible_global_count = mini(global_buttons.size(), mini(global_entries.size(), available_slots))
	if global_entries.size() > visible_global_count:
		visible_global_count = maxi(0, mini(visible_global_count, available_slots - 1))
	for index in range(global_buttons.size()):
		var button := global_buttons[index]
		button.visible = index < visible_global_count
		if not button.visible:
			continue
		var entry: Dictionary = global_entries[index]
		button.icon = icon_for(entry)
		button.tooltip_text = "%s: %s" % [String(entry.get("building_label", "")), String(entry.get("label", ""))]
		place(button, Rect2(8 + index * 50, float(layout["top"].size.y) + 10, 44, 44))
	global_more.visible = global_entries.size() > visible_global_count
	global_more.text = "+%d" % (global_entries.size() - visible_global_count)
	place(global_more, Rect2(8 + visible_global_count * 50, float(layout["top"].size.y) + 10, 44, 44))


func _show_job_icon() -> bool:
	return not layout.is_empty() and layout["production"].size.x >= 250.0


func _draw() -> void:
	if layout.is_empty():
		return
	if frame_texture != null:
		draw_texture_rect(frame_texture, layout["minimap_plane"], false)
	var card: Rect2 = layout["selection"]
	var leader: Dictionary = model.get("selection", {}).get("leader", {})
	if not leader.is_empty():
		draw_rect(card, MASK)
		if bool(leader.get("show_hp", true)):
			var health := Rect2(card.position + Vector2(11, 81), Vector2(106, 4))
			draw_rect(health, Color("292c23"))
			var ratio := clampf(float(leader.get("hp", 0)) / maxf(1, float(leader.get("max_hp", 1))), 0, 1)
			draw_rect(Rect2(health.position, Vector2(health.size.x * ratio, 4)), Color("58b340") if ratio > 0.5 else Color("d7a443"))
	var production: Rect2 = layout["production"]
	draw_recess(production)
	var orders: Array = model.get("queue", [])
	if not orders.is_empty():
		var active: Dictionary = orders[0]
		var track := Rect2(production.position + Vector2(8, 55), Vector2(production.size.x - 16, 6))
		draw_rect(track, Color(0.039, 0.055, 0.027, 0.4))
		var blocked := String(active.get("status", "")).begins_with("blocked_")
		draw_rect(Rect2(track.position, Vector2(track.size.x * clampf(float(active.get("progress", 0)), 0, 1), 6)), Color("d7a443") if blocked else Color("57af33"))
	for index in range(visible_global_count):
		var entry: Dictionary = global_entries[index]
		var track := Rect2(global_buttons[index].position + Vector2(2, 44), Vector2(40, 4))
		draw_rect(track, Color(0.039, 0.055, 0.027, 0.4))
		draw_rect(Rect2(track.position, Vector2(40 * clampf(float(entry.get("progress", 0)), 0, 1), 4)), Color("d7a443") if String(entry.get("status", "")).begins_with("blocked_") else Color("57af33"))


func draw_recess(rectangle: Rect2) -> void:
	draw_rect(rectangle, MASK)
	var rim: Array[Color] = [Color("9b9b8c"), Color("35382f")]
	if skin != null:
		rim = skin.rim_colors(style_index)
	for inset in range(5, 0, -1):
		var shade := Color(0, 0, 0, 0.15 + (5 - inset) * 0.07)
		draw_line(rectangle.position + Vector2(inset, inset), Vector2(rectangle.end.x - inset, rectangle.position.y + inset), shade)
		draw_line(rectangle.position + Vector2(inset, inset), Vector2(rectangle.position.x + inset, rectangle.end.y - inset), shade)
	draw_line(rectangle.position, Vector2(rectangle.end.x - 1, rectangle.position.y), rim[0])
	draw_line(rectangle.position, Vector2(rectangle.position.x, rectangle.end.y - 1), rim[0])
	draw_line(Vector2(rectangle.position.x, rectangle.end.y - 1), rectangle.end - Vector2.ONE, rim[1])
	draw_line(Vector2(rectangle.end.x - 1, rectangle.position.y), rectangle.end - Vector2.ONE, rim[1])
	draw_rect(rectangle.grow(-1), Color(0, 0, 0, 0.85), false, 1)
	draw_line(rectangle.position + Vector2(2, 2), Vector2(rectangle.end.x - 3, rectangle.position.y + 2), Color(0, 0, 0, 0.65))
	draw_line(Vector2(rectangle.position.x + 2, rectangle.end.y - 3), rectangle.end - Vector2(3, 3), Color(0.86, 0.82, 0.68, 0.2))


func make_label(font_size: int, light: bool) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Typography.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK if light else Color("20180f"))
	label.clip_text = true
	add_child(label)
	return label


func make_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(icon)
	return icon


func make_button(icon_width: int) -> Button:
	var button := Button.new()
	button.visible = false
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", icon_width)
	button.add_theme_font_override("font", Typography.body_font())
	button.add_theme_font_size_override("font_size", 14)
	var count := Label.new()
	count.name = "Count"
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	count.add_theme_font_override("font", Typography.body_font())
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", INK)
	count.add_theme_color_override("font_outline_color", Color("201b12"))
	count.add_theme_constant_override("outline_size", 2)
	button.add_child(count)
	add_child(button)
	return button


func style_button(button: Button) -> void:
	var texture: Texture2D = skin.square_command_backplate(style_index)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var backplate := StyleBoxTexture.new()
		backplate.texture = texture
		backplate.modulate_color = Color(0.78, 0.78, 0.78) if state == "pressed" else Color(0.48, 0.48, 0.48) if state == "disabled" else Color(1.08, 1.08, 1.08) if state == "hover" else Color.WHITE
		backplate.content_margin_left = 4
		backplate.content_margin_right = 4
		backplate.content_margin_top = 4
		backplate.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, backplate)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", skin.text_color(style_index))


func icon_for(record: Dictionary) -> Texture2D:
	if icon_registry == null:
		return null
	return icon_registry.texture(String(record.get("icon_kind", "object")), int(record.get("icon_id", -1)))


func place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _cancel_pending(button_index: int) -> void:
	var group_index := int(pending_buttons[button_index].get_meta("group_index", -1))
	if group_index < 0 or group_index >= pending_groups.size() or bool(model.get("read_only", false)):
		return
	var group: Dictionary = pending_groups[group_index]
	var first_index := int(group["first_index"])
	var count := mini(5, int(group["count"])) if Input.is_key_pressed(KEY_SHIFT) and group.get("type") == "unit" else 1
	# Descending indices keep a Shift cancellation stable in the command stream.
	for index in range(first_index + count - 1, first_index - 1, -1):
		cancel_requested.emit(context_id, index)


func _select_global(index: int) -> void:
	if index >= 0 and index < global_entries.size():
		building_selected.emit(int(global_entries[index].get("building_id", -1)))


func _show_global_popup() -> void:
	global_popup.clear()
	for index in range(visible_global_count, global_entries.size()):
		var entry: Dictionary = global_entries[index]
		global_popup.add_icon_item(icon_for(entry), "%s: %s" % [String(entry.get("building_label", "")), String(entry.get("label", ""))], index)
	global_popup.position = Vector2i(global_more.get_global_rect().position + Vector2(0, 48))
	global_popup.popup()
