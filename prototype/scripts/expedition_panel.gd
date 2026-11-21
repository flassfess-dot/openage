extends VBoxContainer

signal hero_requested(id: int, carrier: int, position: Vector2)
signal action_requested(id: int, action: String, details: Dictionary)

const Service := preload("res://scripts/expedition.gd")
const Inv := preload("res://scripts/expedition_inventory.gd")
const Typography := preload("res://scripts/hud_typography.gd")
const GOLD := Color("e8cd8e")
const PARCHMENT := Color("eadfc6")

var icons
var shell
var roster_bar := HBoxContainer.new()
var actions := HBoxContainer.new()
var inventory := PanelContainer.new()
var title := Label.new()
var rank_text := Label.new()
var experience := ProgressBar.new()
var details := Label.new()
var primary := Button.new()
var discard := Button.new()
var slot_buttons: Array[Button] = []
var selection_borders: Array[Panel] = []
var role_buttons: Dictionary = {}
var action_buttons: Dictionary = {}
var roster: Array = []
var loot: Array = []
var hero: Dictionary = {}
var selected_slot := 0
var current_tick := 0
var last_focused := -1
var refresh_key: Variant = null

func configure(controls, registry) -> void:
	shell = controls
	icons = registry
	name = "ExpeditionPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	for row in [roster_bar, actions]:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.add_theme_constant_override("separation", 2)
		add_child(row)
	for role in Service.ROLES:
		var button := make_button(roster_bar, "", Vector2(108, 40))
		role_buttons[role] = button
		button.pressed.connect(select_role.bind(role))
	for spec in [["inventory","J"], ["ability","E"], ["pickup","F"], ["balm","C"]]:
		var button := make_button(actions, spec[1], Vector2(51, 39))
		action_buttons[spec[0]] = button
		button.pressed.connect(trigger.bind(spec[0]))
	inventory.name = "HeroInventory"
	inventory.mouse_filter = Control.MOUSE_FILTER_STOP
	inventory.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("292720")
	frame.border_color = Color("a99058")
	frame.set_border_width_all(2)
	frame.shadow_size = 2
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: frame.set_content_margin(side, 8)
	inventory.add_theme_stylebox_override("panel", frame)
	add_child(inventory)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	inventory.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	style_label(title, 15, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := make_button(header, "×", Vector2(26, 24))
	close.tooltip_text = "Закрыть · J / Esc"
	close.pressed.connect(close_inventory)
	style_label(rank_text, 12, PARCHMENT)
	column.add_child(rank_text)
	experience.custom_minimum_size.y = 5
	experience.show_percentage = false
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color("bf9a54")
	experience.add_theme_stylebox_override("fill", bar)
	column.add_child(experience)
	for section in ["Снаряжение", "Рюкзак"]:
		var label := Label.new()
		label.text = section
		style_label(label, 12, GOLD)
		column.add_child(label)
		var row := HBoxContainer.new()
		column.add_child(row)
		var count := Inv.GEAR.size() if section == "Снаряжение" else Inv.PACK_SIZE
		for i in count:
			var button := make_button(row, "", Vector2(67, 39))
			button.toggle_mode = true
			button.pressed.connect(select_slot.bind(slot_buttons.size()))
			slot_buttons.append(button)
			var outline := Panel.new()
			outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var border := StyleBoxFlat.new()
			border.draw_center = false
			border.set_border_width_all(2)
			border.border_color = GOLD
			outline.add_theme_stylebox_override("panel", border)
			button.add_child(outline)
			outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			selection_borders.append(outline)
	style_label(details, 13, PARCHMENT)
	details.custom_minimum_size = Vector2(288, 36)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(details)
	var verbs := HBoxContainer.new()
	column.add_child(verbs)
	for button in [primary, discard]:
		verbs.add_child(button)
		decorate(button)
		button.custom_minimum_size = Vector2(118, 27)
	primary.pressed.connect(item_action.bind(false))
	discard.text = "Выложить"
	discard.tooltip_text = "Положить один предмет у ног героя"
	discard.pressed.connect(item_action.bind(true))
	inventory.hide()
	hide()

func style_label(label: Label, size_px: int, color: Color) -> void:
	label.add_theme_font_override("font", Typography.body_font())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)

func decorate(button: Button) -> void:
	shell.apply_button_theme(button)
	shell.apply_source_command_theme(button)
	button.add_theme_color_override("font_outline_color", Color("241b13"))
	button.add_theme_constant_override("outline_size", 3)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_constant_override("icon_max_width", 30)
	button.add_theme_font_size_override("font_size", 12)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func make_button(parent: Control, caption: String, minimum: Vector2) -> Button:
	var button := Button.new()
	decorate(button)
	button.text = caption
	button.custom_minimum_size = minimum
	parent.add_child(button)
	return button

func refresh(state: Dictionary, selected: Array[int], tick: int, blocked: bool) -> void:
	if blocked or not state.get("field_service_enabled", false):
		hide()
		close_inventory()
		refresh_key = null
		return
	current_tick = tick
	var before := int(hero.get("id", -1))
	roster = []
	hero = {}
	for row in state.get("service_heroes", []):
		if row.team == state.team:
			roster.append(row)
			if selected.size() == 1 and selected[0] == row.id and row.carrier < 0: hero = row
	loot = state.get("service_loot", [])
	if before != int(hero.get("id", -1)):
		close_inventory()
		selected_slot = 0
	visible = not roster.is_empty()
	if not visible: return
	var key := [hero.get("id", -1), seconds_left(), nearest_pile(), inventory.visible, selected_slot]
	for row in roster: key.append([row.id, row.icon, row.role, row.name, ceili(row.hp), row.max_hp, row.xp, row.carrier, row.kit, int(row.get("guard_until", 0)) > tick])
	if key == refresh_key: return
	refresh_key = key
	for button in role_buttons.values(): button.hide()
	for row in roster:
		var button: Button = role_buttons[row.role]
		button.show()
		button.icon = icons.texture("unit", int(row.icon), int(row.team))
		if button.icon == null: button.icon = icons.texture("technology", Service.ROLE_ICONS[row.role], int(row.team))
		var short_name := String(row.name)
		if short_name.length() > 10: short_name = short_name.left(9) + "…"
		button.text = "%s\n%s · %d/%d" % [short_name, ["I","II","III"][Service.level(row.xp)-1], ceili(row.hp), ceili(row.max_hp)]
		button.add_theme_color_override("font_color", GOLD if row.id == hero.get("id") else PARCHMENT)
		button.modulate = Color("d3c2a4") if row.carrier >= 0 else Color.WHITE
		button.tooltip_text = "%s · %s\nЗдоровье %d/%d · %s\n%s" % [row.name, Service.ROLES[row.role], ceili(row.hp), ceili(row.max_hp),
			"в гарнизоне / на борту" if row.carrier >= 0 else "в строю", "Нажмите для перехода к герою · F2 перебирает героев"]
		if int(row.get("guard_until", 0)) > tick: button.tooltip_text += "\nПод защитой щитового строя"
	actions.visible = not hero.is_empty()
	if hero.is_empty(): return
	var role := String(hero.role)
	var tier := Service.level(hero.xp)
	set_action("inventory", 83, "Инвентарь · J", false)
	set_action("ability", Service.ROLE_ICONS[role], "%s · E\n%s\n%s" % [Service.ABILITIES[role], Service.ability_detail(role, tier),
		"Готово" if seconds_left() == 0 else "Готовность через %d сек." % seconds_left()], seconds_left() > 0)
	action_buttons.ability.text = str(seconds_left()) if seconds_left() > 0 else "E"
	set_action("pickup", 16, "Подобрать ближайший видимый трофей · F", nearest_pile() < 0)
	var balms := 0
	for stack in hero.kit:
		if stack.get("item") == "balm": balms += int(stack.count)
	set_action("balm", Inv.ITEMS.balm.icon, "Бальзам · C · в рюкзаке %d\n%s" % [balms, Inv.ITEMS.balm.effect], balms == 0 or hero.hp >= hero.max_hp)
	action_buttons.balm.text = "C·%d" % balms
	if inventory.visible: refresh_inventory()
	reset_size()

func set_action(action: String, icon: int, tip: String, unavailable: bool) -> void:
	var button: Button = action_buttons[action]
	button.icon = icons.texture("technology", icon, int(hero.team))
	button.tooltip_text = tip
	button.disabled = unavailable

func seconds_left() -> int:
	return ceili(maxi(0, int(hero.get("ready", 0)) - current_tick) / 20.0)

func nearest_pile() -> int:
	if hero.is_empty(): return -1
	var best := -1
	var distance := INF
	for pile in loot:
		var d := Vector2(hero.pos).distance_squared_to(pile.pos)
		if d < distance or (d == distance and int(pile.id) < best):
			distance = d
			best = int(pile.id)
	return best

func select_role(role: String) -> void:
	for row in roster:
		if row.role == role:
			last_focused = int(row.id)
			hero_requested.emit(row.id, row.carrier, row.pos)
			return

func cycle_hero() -> void:
	if roster.is_empty(): return
	var index := roster.find_custom(func(row): return row.id == hero.get("id", last_focused))
	select_role(roster[(index + 1) % roster.size()].role)

func trigger(action: String) -> void:
	if hero.is_empty(): return
	if action == "inventory":
		if inventory.visible: close_inventory()
		else:
			inventory.show()
			refresh_inventory()
		return
	var options := {}
	if action == "pickup": options["pile"] = nearest_pile()
	action_requested.emit(hero.id, action, options)

func close_inventory() -> void:
	if not inventory.visible: return
	inventory.hide()
	reset_size()

func select_slot(i: int) -> void:
	selected_slot = i
	refresh_inventory()

func refresh_inventory() -> void:
	var tier := Service.level(hero.xp)
	var next := int(Service.HERO_XP[mini(tier, 2)])
	title.text = "%s  ·  %s" % [hero.name, Service.ROLES[hero.role]]
	title.tooltip_text = Service.ROLE_DETAILS[hero.role]
	rank_text.text = "Уровень %s  ·  Опыт %.1f / %d" % [["I","II","III"][tier - 1], hero.xp / 1000.0, next / 1000]
	experience.min_value = Service.HERO_XP[tier - 1] if tier < 3 else 0
	experience.max_value = next
	experience.value = hero.xp
	experience.tooltip_text = "Уровень %d · опыт %.1f / %d" % [tier, hero.xp / 1000.0, next / 1000]
	for i in slot_buttons.size():
		var button := slot_buttons[i]
		var stack: Dictionary = hero.kit[i]
		var info: Dictionary = Inv.ITEMS.get(stack.get("item", ""), {})
		var label := String(Inv.SLOT_NAMES[i]) if i < Inv.GEAR.size() else str(i - Inv.GEAR.size() + 1)
		button.icon = null if info.is_empty() else icons.texture("technology", info.icon, int(hero.team))
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT if int(stack.get("count", 0)) > 1 else HORIZONTAL_ALIGNMENT_CENTER
		button.text = label if info.is_empty() else ("×%d" % stack.count if stack.count > 1 else "")
		button.tooltip_text = "%s · пусто" % label if info.is_empty() else "%s\n%s" % [info.name, info.effect]
		button.set_pressed_no_signal(i == selected_slot)
		selection_borders[i].visible = i == selected_slot
		button.modulate = Color.WHITE if i == selected_slot else Color("c8bda7")
	var active: Dictionary = hero.kit[selected_slot]
	var item: Dictionary = Inv.ITEMS.get(active.get("item", ""), {})
	discard.disabled = item.is_empty()
	primary.disabled = item.is_empty()
	primary.tooltip_text = ""
	if item.is_empty():
		details.text = "%s · свободно" % (Inv.SLOT_NAMES[selected_slot] if selected_slot < Inv.GEAR.size() else "Ячейка рюкзака")
		primary.text = "Применить"
	else:
		details.text = "%s\n%s" % [item.name, item.effect]
		if selected_slot >= Inv.GEAR.size() and item.slot >= 0:
			var worn: Dictionary = hero.kit[item.slot]
			if not worn.is_empty(): details.text += "\nСейчас: %s" % Inv.ITEMS[worn.item].name
		primary.text = "Снять" if selected_slot < Inv.GEAR.size() else "Надеть" if item.slot >= 0 else "Применить"
		if selected_slot < Inv.GEAR.size() and Inv.pack_slot(hero.kit.slice(Inv.GEAR.size()), active.item) < 0:
			primary.tooltip_text = "Освободите ячейку рюкзака"
		elif active.item == "balm" and hero.hp >= hero.max_hp:
			primary.tooltip_text = "Здоровье уже восстановлено"
		elif active.item == "incense" and seconds_left() == 0:
			primary.tooltip_text = "Умение уже готово"
		primary.disabled = not primary.tooltip_text.is_empty()

func item_action(drop: bool) -> void:
	if hero.is_empty(): return
	var stack: Dictionary = hero.kit[selected_slot]
	if stack.is_empty(): return
	action_requested.emit(hero.id, "drop" if drop else "activate", {"slot":selected_slot, "item":stack.item})
