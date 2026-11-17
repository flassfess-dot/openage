extends PanelContainer

const LauncherTheme := preload("res://scripts/launcher_theme.gd")
const Typography := preload("res://scripts/launcher_typography.gd")
const HudModalOverlay := preload("res://scripts/hud_modal_overlay.gd")
const STAGES := {
	"queued": [0, "Ожидание записи"],
	"capture": [1, "Снимок состояния игры"],
	"transfer": [1, "Передача данных"],
	"materialize": [1, "Сборка снимка"],
	"encoding": [2, "Кодирование данных"],
	"hashing": [2, "Расчёт контрольной суммы"],
	"compressing": [3, "Сжатие данных"],
	"encoding_checkpoint": [3, "Упаковка снимка"],
	"writing": [4, "Запись файла"],
	"committing": [4, "Завершение записи"],
}
const KINDS := {"manual":"Сохранение", "quick":"Быстрое сохранение", "auto":"Автосохранение"}

var _label := Label.new()
var _amount := Label.new()
var _bar := ProgressBar.new()
var _dismiss := Timer.new()
var _last_state := {}
var _modal: HudModalOverlay
var _floating_parent: Node

func _init() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := LauncherTheme.panel_style()
	surface.content_margin_left = 11
	surface.content_margin_right = 11
	surface.content_margin_top = 5
	surface.content_margin_bottom = 6
	add_theme_stylebox_override("panel", surface)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	add_child(column)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)
	for label in [_label, _amount]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", Typography.body_font())
		label.add_theme_font_size_override("font_size", 15)
		line.add_child(label)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_amount.add_theme_color_override("font_color", LauncherTheme.GOLD_BRIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.custom_minimum_size.y = 8
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", LauncherTheme.progress_background_style())
	_bar.add_theme_stylebox_override("fill", LauncherTheme.progress_fill_style())
	column.add_child(_bar)
	_dismiss.one_shot = true
	_dismiss.process_mode = Node.PROCESS_MODE_ALWAYS
	_dismiss.ignore_time_scale = true
	_dismiss.timeout.connect(_hide_indicator)
	add_child(_dismiss)

# The match has one indicator. The launcher can also place an instance directly
# in its save page while the current match is suspended.
func attach_to_hud(modal: HudModalOverlay) -> void:
	_modal = modal
	_floating_parent = get_parent()
	_modal.visibility_changed.connect(_place_in_hud, CONNECT_DEFERRED)
	_modal.menu_panel.visibility_changed.connect(_place_in_hud, CONNECT_DEFERRED)
	get_viewport().size_changed.connect(_place_in_hud)
	_place_in_hud()

func _place_in_hud() -> void:
	if not is_instance_valid(_modal) or not is_inside_tree() or _floating_parent.is_queued_for_deletion(): return
	var in_menu: bool = _modal.visible and _modal.menu_panel.visible
	var parent: Node = _modal.save_progress_host if in_menu else _floating_parent
	if get_parent() != parent: reparent(parent, false)
	_modal.save_progress_host.visible = in_menu and visible
	z_index = 0 if in_menu else 301
	if not in_menu:
		set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		position = Vector2(10, 40)
		size = Vector2(minf(380, maxf(1, get_viewport_rect().size.x - 20)), 0)

func set_save_progress(state: Dictionary) -> void:
	if state.is_empty():
		if _dismiss.is_stopped() and not _last_state.is_empty():
			_hide_indicator()
			_last_state.clear()
		return
	if state == _last_state: return
	_last_state = state.duplicate()
	var stage := String(state.get("stage", ""))
	var kind := String(state.get("kind", "manual"))
	var title := String(KINDS.get(kind, KINDS["manual"]))
	var message := String(state.get("message", ""))
	var failed := stage == "error"
	var finished := failed or stage == "done"
	var step: Array = STAGES.get(stage, [0, message])
	var completed := int(state.get("completed", 0))
	var total := int(state.get("total", 0))
	_label.add_theme_color_override("font_color", Color("ffc0a8") if failed else Color("f2ead7"))
	if finished:
		var success := "Игра сохранена" if kind == "manual" else title + " готово"
		_label.text = (message if not message.is_empty() else "Не удалось сохранить игру") if failed else success
		_dismiss.start(8.0 if failed else 3.5)
	else:
		_dismiss.stop()
		var action := String(step[1])
		_label.text = title if action.is_empty() else "%s · %s" % [title, action]
	_bar.visible = not finished
	_amount.visible = not finished and (total > 0 or int(step[0]) > 0)
	_bar.indeterminate = not finished and total <= 0
	if not finished and total > 0:
		_bar.max_value = total
		_bar.value = clampi(completed, 0, total)
		_amount.text = "%d%%" % floori(100.0 * _bar.value / total)
	elif _amount.visible:
		_amount.text = "Этап %d из 4" % int(step[0])
	show()
	if _modal != null: _place_in_hud()

func _hide_indicator() -> void:
	hide()
	if is_instance_valid(_modal): _modal.save_progress_host.hide()
