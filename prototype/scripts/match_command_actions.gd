extends RefCounted

# Scene access is scoped to each call; this owner never retains the scene.
const Coordinates := preload("res://scripts/coordinates.gd")
const GameController := preload("res://scripts/game_controller.gd")
const RoRCommands = preload("res://scripts/commands.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const CommandFeedbackRouter := preload("res://scripts/command_feedback_router.gd")
const ContextResolver := preload("res://scripts/context_resolver.gd")
const HUDControls := preload("res://scripts/hud_controls.gd")
const HUDModalOverlay := preload("res://scripts/hud_modal_overlay.gd")
const MinimapProjection := preload("res://scripts/minimap_projection.gd")
const WallPlacement := preload("res://scripts/wall_placement.gd")
const MinimapAperture := preload("res://scripts/minimap_aperture.gd")

var pending_build_kind := ""
var pending_gate_axis := 0
var pending_build_started := false
var resource_feedback_id := -1
var resource_feedback_time := 0.0
var placement_preview_key := ""
var placement_preview_valid := false
var wall_placement_preview_key := ""
var wall_placement_preview: Dictionary = {}
var wall_preview_renderer := RenderWorld.new()
var pending_target_command := ""
var pending_target_queue_order := false

func handle_input_action(game, action: Dictionary) -> void:
	if game.local_spectator and String(action.get("type", "")) not in ["consume_outside_world", "zoom", "pointer_moved", "toggle_audio", "toggle_pause", "change_speed", "toggle_diagnostics", "toggle_status_indicators", "next_sound_cue", "reset_game", "quit", "open_game_menu", "open_help"]:
		return
	match String(action.get("type", "")):
		"consume_outside_world":
			game.selection_preview_ids.clear()
			game.get_viewport().set_input_as_handled()
		"zoom":
			game.zoom_at(action["position"], 1.12 if int(action["steps"]) > 0 else 1.0 / 1.12)
		"selection_started":
			game.selection_preview_ids.clear()
		"selection_committed":
			if not pending_target_command.is_empty():
				game.commit_pending_target(action["to"], bool(action.get("queue_order", false)))
			elif pending_build_kind.is_empty():
				game.finish_selection(action["from"], action["to"], String(action.get("mode", "select_click")))
			else:
				game.commit_build_placement(action["to"], bool(action.get("queue_order", false)), action["from"])
			game.selection_preview_ids.clear()
		"context_committed":
			if pending_target_command in ["repair", "unload"]:
				game.cancel_pending_targeting()
			elif not pending_target_command.is_empty():
				game.commit_pending_target(action["position"], bool(action.get("queue_order", false)))
			elif pending_build_kind.is_empty():
				game.issue_order(action["position"], action.get("direction_end"), bool(action.get("queue_order", false)))
			else:
				pending_build_kind = ""
				pending_build_started = false
				game.update_interaction_cursor(game.input_adapter.pointer_position)
				game.game_message = "Строительство отменено"
				game.message_time = 1.5
		"pointer_moved":
			game.view_offset += Vector2(action.get("pan_delta", Vector2.ZERO))
			game.update_selection_preview()
			game.update_interaction_cursor(action.get("position", game.input_adapter.pointer_position))
		"control_group":
			if bool(action["assign"]):
				game.assign_control_group(int(action["number"]))
			else:
				game.recall_control_group(int(action["number"]), bool(action["additive"]))
		"set_formation":
			game.set_formation(String(action["formation"]))
		"attack_move_mode":
			game.begin_attack_move()
		"attack_ground_mode":
			game.begin_attack_ground()
		"stop":
			game.issue_unit_action("stop")
		"hold":
			game.issue_unit_action("hold")
		"cycle_stance":
			game.issue_unit_action("stance")
		"train":
			game.request_primary_train_command()
		"train_shortcut":
			game.request_train_shortcut(String(action.get("archetype", "")))
		"toggle_status_indicators":
			game.compact_status_visible = not game.compact_status_visible
			game.queue_redraw()
		"next_sound_cue":
			var cue = game.sound_cue_history.next_cue()
			if not cue.is_empty():
				game.center_view_on_world(cue["position"])
				game.queue_redraw()
		"toggle_audio":
			game.audio_player.stream_paused = not game.audio_player.stream_paused
			for player in game.sfx_players:
				player.stream_paused = game.audio_player.stream_paused
		"toggle_pause":
			game.join_simulation_owner()
			if game.network_session != null:
				game.game_message = "Пауза в сетевом матче недоступна"
				return
			var is_paused = game.game_controller.toggle_paused()
			game.game_message = "Пауза" if is_paused else "Игра продолжена"
			game.message_time = 1.5
		"change_speed":
			game.join_simulation_owner()
			if game.network_session != null:
				game.game_message = "Скорость сетевого матча фиксирована"
				return
			var speed = game.game_controller.cycle_speed(int(action["direction"]))
			game.game_message = "Скорость игры: %.1fx" % speed
			game.message_time = 1.5
		"toggle_diagnostics":
			game.diagnostics_enabled = not game.diagnostics_enabled
			game.game_message = "Диагностика включена" if game.diagnostics_enabled else "Диагностика выключена"
			game.message_time = 1.5
		"open_calibration":
			game.get_tree().change_scene_to_file("res://calibration.tscn")
		"delete_context":
			game.issue_delete_context()
		"unload":
			game.issue_unload_at_pointer(bool(action.get("queue_order", false)))
		"reset_game":
			if game.network_session == null:
				game._open_hud_modal(HUDModalOverlay.MODE_MENU)
				game.hud_modal_overlay.request_confirmation("restart")
			else:
				game.game_message = "Перезапуск сетевого матча требует нового лобби"
		"resign":
			game._open_hud_modal(HUDModalOverlay.MODE_MENU)
			game.hud_modal_overlay.request_confirmation("resign")
		"open_game_menu":
			game._toggle_game_menu()
		"open_help":
			game._open_hud_modal(HUDModalOverlay.MODE_MENU)
			game.hud_modal_overlay.show_section("help")
		"quit":
			game._request_window_quit()


func handle_minimap_input(game, event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and game.minimap_right_pressed:
		game.minimap_right_pressed = false
		return true
	var screen_position: Variant = null
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		screen_position = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		screen_position = event.position
	if not screen_position is Vector2:
		return false
	var geometry = game.minimap_geometry()
	if not MinimapAperture.contains(screen_position, geometry["rectangle"]) or not MinimapProjection.contains_world(screen_position, game.map_size, geometry["center"], geometry["scale"]):
		return false
	var target = Coordinates.clamp_world(MinimapProjection.minimap_to_world(screen_position, geometry["center"], geometry["scale"]), game.map_size)
	if event is InputEventMouseButton:
		if not event.pressed: return false
		if event.button_index == MOUSE_BUTTON_RIGHT:
			game.minimap_right_pressed = true
			if not game.local_spectator and not game.battle_over and not game.navigation_loading.is_loading():
				game.issue_ground_order(target, event.shift_pressed)
			return true
	game.center_view_on_world(target)
	game.queue_redraw()
	return true


func issue_order(game, mouse: Vector2, direction_end: Variant = null, queue_order: bool = false) -> void:
	game.join_simulation_owner()
	var selected = game.selected_units()
	if selected.is_empty():
		selected = game.selected_entities().filter(func(entity): return int(entity.get("team", 0)) == game.local_player_team)
	if selected.is_empty():
		game.game_message = "Для этого приказа выберите своих юнитов"
		game.message_time = 1.5
		return

	var mouse_world = game.screen_to_world(mouse)
	var formation_forward = Vector2.ZERO
	if direction_end is Vector2:
		formation_forward = game.screen_to_world(direction_end) - mouse_world
	var clicked_entity: Variant = null
	var hit_stack = game.pick_stack_at(mouse)
	if not hit_stack.is_empty():
		clicked_entity = game.picking_service.context_entity(hit_stack[0])

	var resolution = ContextResolver.resolve(selected, clicked_entity, mouse_world, game.local_player_team, game.simulation_world.get_allied_teams(game.local_player_team))
	var selected_ids = game._selection_ids(selected)
	var command: Variant = null
	var accepted_message = ""
	match resolution["type"]:
		"set_rally_point":
			command = RoRCommands.SetRallyPointCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target"])
			accepted_message = "Точка сбора установлена"
		"attack":
			command = RoRCommands.AttackCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Атаковать цель"
		"convert":
			command = RoRCommands.ConvertCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Обратить цель"
		"heal":
			command = RoRCommands.HealCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Исцелить союзника"
		"board":
			command = RoRCommands.BoardCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Погрузиться в транспорт"
		"trade":
			command = RoRCommands.TradeCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Торговый маршрут назначен"
		"gather":
			command = RoRCommands.GatherCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Работники отправлены к ресурсу"
		"return_resources":
			command = RoRCommands.ReturnResourcesCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Сдать ресурсы"
		"build":
			command = RoRCommands.BuildCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["building_type"], resolution["target"])
			accepted_message = "Продолжить строительство"
		"repair":
			command = RoRCommands.RepairCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Ремонтировать здание"
		"move":
			command = RoRCommands.MoveCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target"]) if queue_order else RoRCommands.FormationMoveCommand.new(game.game_controller.tick_index + 1, selected_ids, resolution["target"], game.formation, formation_forward)
			command.params["preserve_formations"] = true
			accepted_message = "Движение: %s" % game.formation_name()
		_:
			game.game_message = String(resolution.get("message", "Команда для этой цели пока недоступна"))
			game.message_time = 1.8
			return
	if queue_order and String(command.command_type()) in GameController.QUEUEABLE_ORDERS:
		command.params["queue_order"] = true
	var feedback_marker: Variant = ContextResolver.feedback_marker(resolution, clicked_entity, mouse_world)
	game.enqueue_with_feedback(command, accepted_message, "command:%s" % String(selected[0].get("kind", "")), feedback_marker)


func issue_ground_order(game, target: Vector2, queue_order: bool = false) -> void:
	game.join_simulation_owner()
	var selected = game.selected_units()
	if selected.is_empty():
		selected = game.selected_entities().filter(func(entity): return int(entity.get("team", 0)) == game.local_player_team)
	if selected.is_empty(): return
	var ids = game._selection_ids(selected)
	var resolution = ContextResolver.resolve(selected, null, target, game.local_player_team, game.simulation_world.get_allied_teams(game.local_player_team))
	var command: Variant = null
	if String(resolution.get("type", "")) == "set_rally_point":
		command = RoRCommands.SetRallyPointCommand.new(game.game_controller.tick_index + 1, ids, target)
	elif String(resolution.get("type", "")) == "move":
		command = RoRCommands.MoveCommand.new(game.game_controller.tick_index + 1, ids, target) if queue_order else RoRCommands.FormationMoveCommand.new(game.game_controller.tick_index + 1, ids, target, game.formation, Vector2.ZERO)
		command.params["preserve_formations"] = true
		if queue_order: command.params["queue_order"] = true
	else:
		return
	game.enqueue_with_feedback(command, CommandFeedbackRouter.accepted_message(command.command_type()), "command:%s" % String(selected[0].get("kind", "")), target)


func issue_martyrdom(game) -> void:
	game.join_simulation_owner()
	var selected = game.selected_units()
	if selected.is_empty():
		return
	var command = RoRCommands.MartyrdomCommand.new(game.game_controller.tick_index + 1, game._selection_ids(selected))
	game.enqueue_with_feedback(command, "Жертвоприношение", "", null)


func issue_delete_context(game) -> void:
	game.join_simulation_owner()
	var selected = game.selected_entities().filter(func(entity): return int(entity.get("team", 0)) == game.local_player_team and String(entity.get("entity_type", "")) != "resource")
	var martyr_ids: Array[int] = []
	var delete_ids: Array[int] = []
	for entity in selected:
		var entity_id = int(entity.get("id", -1))
		var live_unit = game.simulation_world.find_unit(entity_id)
		if live_unit != null and game.simulation_world.conversion_system.validate_martyrdom(live_unit).is_empty():
			martyr_ids.append(entity_id)
		else:
			delete_ids.append(entity_id)
	if not martyr_ids.is_empty():
		var martyrdom = RoRCommands.MartyrdomCommand.new(game.game_controller.tick_index + 1, martyr_ids)
		game.enqueue_with_feedback(martyrdom, "Жертвоприношение", "", null)
	if not delete_ids.is_empty():
		var deletion = RoRCommands.DeleteEntityCommand.new(game.game_controller.tick_index + 1, delete_ids)
		game.enqueue_with_feedback(deletion, "Удалить выбранные объекты", "", null)


func issue_unload_at_pointer(game, queue_order: bool = false) -> void:
	if game.battle_over or game.local_spectator:
		return
	var transports = game.selected_units().filter(func(unit): return bool(unit.get("components", {}).get("cargo", {}).get("enabled", false)) and not unit.get("components", {}).get("cargo", {}).get("passenger_ids", []).is_empty())
	if transports.is_empty():
		game.game_message = "Для высадки выберите транспорт с пассажирами"
		game.message_time = 1.5
		return
	pending_build_kind = ""
	pending_build_started = false
	pending_target_command = "unload"
	pending_target_queue_order = queue_order
	game.input_adapter.reset()
	if game.hud_controls != null:
		game.hud_controls.set_build_menu_open(false)
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	game.game_message = "Укажите берег для высадки (ПКМ или Esc — отмена)"
	game.message_time = 4.0


func issue_unit_action(game, action_name: String) -> void:
	game.join_simulation_owner()
	if action_name.begins_with("gate_"):
		var gates = game.selected_entities().filter(func(entity): return String(entity.get("kind", "")) == "gate" and int(entity.get("team", 0)) == game.local_player_team)
		if not gates.is_empty() and not game.battle_over:
			var gate_command = RoRCommands.GateModeCommand.new(game.game_controller.tick_index + 1, game._selection_ids(gates), action_name.trim_prefix("gate_"))
			game.enqueue_with_feedback(gate_command, "Режим ворот", "")
		return
	if action_name == "unload":
		game.issue_unload_at_pointer()
		return
	if action_name == "repair":
		game.begin_repair()
		return
	if action_name == "delete":
		game.issue_delete_context()
		return
	if action_name == "attack_move":
		game.begin_attack_move()
		return
	if action_name == "attack_ground":
		game.begin_attack_ground()
		return
	if game.battle_over:
		return
	var selected = game.selected_entities().filter(func(entity): return int(entity.get("team", 0)) == game.local_player_team and String(entity.get("entity_type", "")) != "resource") if action_name == "stop" else game.selected_units()
	if selected.is_empty():
		game.game_message = "Для приказа выберите свои объекты" if action_name == "stop" else "Для приказа выберите своих юнитов"
		game.message_time = 1.5
		return
	var ids = game._selection_ids(selected)
	var command: Variant = null
	var message = ""
	match action_name:
		"stop":
			command = RoRCommands.StopCommand.new(game.game_controller.tick_index + 1, ids)
			message = "Остановиться"
		"hold":
			command = RoRCommands.HoldCommand.new(game.game_controller.tick_index + 1, ids)
			message = "Держать позицию"
		"stance":
			var stance = RoRCommands.next_stance(String(selected[0].get("stance", "aggressive")))
			command = RoRCommands.StanceCommand.new(game.game_controller.tick_index + 1, ids, stance)
			message = "Стойка: %s" % game.stance_name(stance)
		_:
			return
	game.enqueue_with_feedback(command, message, "command:%s" % String(selected[0].get("kind", "")), null)


func repair_workers(game) -> Array:
	game.join_simulation_owner()
	if game.simulation_world == null:
		return []
	return game.selected_units().filter(func(unit): return game.simulation_world.entity_is_worker(unit) and String(unit.get("movement_domain", "land")) == "land")


func begin_repair(game) -> void:
	if game.battle_over or game.local_spectator or game.repair_workers().is_empty():
		return
	if game.hud_controls != null and game.hud_controls.build_menu_open:
		game.hud_controls.set_build_menu_open(false)
	pending_build_kind = ""
	pending_build_started = false
	pending_target_command = "repair"
	game.input_adapter.reset()
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	game.game_message = "Укажите повреждённое своё или союзное здание/судно (ПКМ или Esc — отмена)"
	game.message_time = 4.0


func cancel_pending_targeting(game) -> bool:
	if pending_build_kind.is_empty() and pending_target_command.is_empty():
		return false
	pending_build_kind = ""
	pending_build_started = false
	pending_target_command = ""
	pending_target_queue_order = false
	game.input_adapter.reset()
	game.selection_preview_ids.clear()
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	game.game_message = "Приказ отменён"
	game.message_time = 1.5
	return true


func repair_target_at(game, screen_position: Vector2, workers: Array) -> Dictionary:
	game.join_simulation_owner()
	for hit in game.pick_stack_at(screen_position):
		var target: Variant = game.simulation_world.find_building(int(hit.get("id", -1)))
		if target == null:
			target = game.simulation_world.find_unit(int(hit.get("id", -1)))
		if target != null and workers.any(func(worker): return game.simulation_world.can_worker_repair(worker, target)):
			return target
	return {}


func commit_repair_target(game, screen_position: Vector2) -> void:
	game.join_simulation_owner()
	var workers = game.repair_workers()
	if workers.is_empty() or game.battle_over:
		game.cancel_pending_targeting()
		return
	var target = game.repair_target_at(screen_position, workers)
	if target.is_empty():
		game.game_message = "Выберите повреждённое своё или союзное здание/судно"
		game.message_time = 2.0
		return
	workers = workers.filter(func(worker): return game.simulation_world.can_worker_repair(worker, target))
	var command = RoRCommands.RepairCommand.new(game.game_controller.tick_index + 1, game._selection_ids(workers), int(target["id"]))
	pending_target_command = ""
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	game.enqueue_with_feedback(command, "Ремонтировать цель", "command:%s" % String(workers[0].get("kind", "villager")), Vector2(target.get("pos", Vector2.ZERO)))


func begin_attack_move(game) -> void:
	if game.selected_units().is_empty() or game.battle_over:
		game.game_message = "Для атаки выберите своих юнитов"
		game.message_time = 1.5
		return
	pending_build_kind = ""
	pending_target_command = "attack_move"
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	game.game_message = "Укажите точку движения с атакой"
	game.message_time = 4.0


func begin_attack_ground(game) -> void:
	game.join_simulation_owner()
	if game.battle_over or game.game_controller == null:
		return
	var attackers: Array = game.selected_units().filter(func(unit): return game.simulation_world.can_attack_ground(unit))
	if attackers.is_empty():
		game.game_message = "Для атаки по земле выберите осадные орудия"
		game.message_time = 1.5
		return
	pending_build_kind = ""
	pending_target_command = "attack_ground"
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	game.game_message = "Укажите точку обстрела"
	game.message_time = 4.0


func commit_pending_target(game, screen_position: Vector2, queue_order: bool = false) -> void:
	game.join_simulation_owner()
	var target_command = pending_target_command
	if target_command == "repair":
		game.commit_repair_target(screen_position)
		return
	if target_command not in ["attack_move", "attack_ground", "unload"]:
		return
	pending_target_command = ""
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	var selected = game.selected_units()
	if selected.is_empty() or game.battle_over:
		return
	var target = game.screen_to_world(screen_position)
	var command: Variant
	var message: String
	if target_command == "unload":
		selected = selected.filter(func(unit): return bool(unit.get("components", {}).get("cargo", {}).get("enabled", false)) and not unit.get("components", {}).get("cargo", {}).get("passenger_ids", []).is_empty())
		if selected.is_empty():
			return
		command = RoRCommands.UnloadCommand.new(game.game_controller.tick_index + 1, game._selection_ids(selected), target)
		if pending_target_queue_order or queue_order:
			command.params["queue_order"] = true
		pending_target_queue_order = false
		message = "Высадить пассажиров"
	elif target_command == "attack_ground":
		selected = selected.filter(func(unit): return game.simulation_world.can_attack_ground(unit))
		if selected.is_empty():
			return
		command = RoRCommands.AttackGroundCommand.new(game.game_controller.tick_index + 1, game._selection_ids(selected), target)
		message = "Атаковать точку"
	else:
		command = RoRCommands.AttackMoveCommand.new(game.game_controller.tick_index + 1, game._selection_ids(selected), target)
		message = "Двигаться с атакой"
	game.enqueue_with_feedback(command, message, "command:%s" % String(selected[0].get("kind", "")), target)


func stance_name(game, value: String) -> String:
	return {"aggressive": "агрессивная", "defensive": "оборонительная", "stand_ground": "держать позицию", "passive": "не атаковать"}.get(value, value)


func set_formation(game, value: String) -> void:
	game.join_simulation_owner()
	if game.selected_units().is_empty():
		return
	game.formation = value
	game.game_message = "Выбран строй: %s" % game.formation_name()
	game.message_time = 1.5
	if game.game_controller == null or game.simulation_world == null:
		return
	var selected = game.selected_units()
	if selected.is_empty():
		return
	var center = Vector2.ZERO
	for unit in selected:
		center += unit["pos"]
	center /= float(selected.size())
	var existing_forward: Vector2 = selected[0].get("formation_forward", Vector2.ZERO)
	var reform = RoRCommands.FormationMoveCommand.new(game.game_controller.tick_index + 1, game._selection_ids(selected), center, value, existing_forward)
	game._queue_local_command(reform)


func formation_name(game) -> String:
	return {"LINE": "линия", "RECTANGLE": "каре", "COLUMN": "колонна", "WEDGE": "клин", "STAGGERED": "рассредоточенный", "FLANK": "фланги"}.get(game.formation, "смешанный" if game.formation.is_empty() else game.formation)


func request_primary_train_command(game) -> void:
	for command_value in game.hud_model.get("commands", []):
		var command: Dictionary = command_value
		if String(command.get("type", "")) != "train":
			continue
		if not bool(command.get("enabled", false)):
			game.game_message = HUDControls.reason_text(String(command.get("reason", "")))
			game.message_time = 2.0
			return
		game.train_unit_from_hud(String(command.get("id", "")), int(command.get("building_id", -1)))
		return
	game.game_message = "Выберите производящее здание"
	game.message_time = 2.0


func request_train_shortcut(game, unit_kind: String) -> void:
	for command_value in game.hud_model.get("commands", []):
		var command: Dictionary = command_value
		if String(command.get("type", "")) != "train" or String(command.get("id", "")) != unit_kind:
			continue
		if bool(command.get("enabled", false)):
			game.train_unit_from_hud(unit_kind, int(command.get("building_id", -1)))
		else:
			game.game_message = HUDControls.reason_text(String(command.get("reason", "")))
			game.message_time = 2.0
		return
	game.game_message = "Выберите здание для обучения: %s" % unit_kind
	game.message_time = 2.0


func begin_build_placement(game, building_kind: String) -> void:
	wall_placement_preview_key = ""
	if building_kind.is_empty() or game.selected_units().is_empty():
		return
	pending_target_command = ""
	pending_build_kind = building_kind
	pending_build_started = false
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	game.game_message = "Укажите место строительства: %s (ПКМ — отмена)" % ("ворота; Tab — повернуть" if building_kind == "gate" else building_kind)
	game.message_time = 4.0


func commit_build_placement(game, screen_position: Vector2, queue_order: bool = false, start_screen_position: Vector2 = Vector2.INF) -> void:
	game.join_simulation_owner()
	if pending_build_kind.is_empty() or game.simulation_world == null or game.battle_over:
		return
	var workers: Array = game.selected_units().filter(func(unit): return game.simulation_world.entity_is_worker(unit))
	if workers.is_empty():
		pending_build_kind = ""
		game.update_interaction_cursor(game.input_adapter.pointer_position)
		game.game_message = "Для строительства нужен рабочий"
		game.message_time = 2.0
		return
	var target = Coordinates.clamp_world(game.screen_to_world(screen_position).round(), game.map_size)
	var kind = pending_build_kind
	if kind == "wall":
		var start = Coordinates.clamp_world(game.screen_to_world(start_screen_position).round(), game.map_size) if start_screen_position != Vector2.INF else target
		var cells = WallPlacement.cells(Vector2i(start), Vector2i(target))
		if not queue_order:
			pending_build_kind = ""
			pending_build_started = false
		else:
			pending_build_started = true
		game.update_interaction_cursor(game.input_adapter.pointer_position)
		game.queue_wall_line(workers, cells, queue_order)
		return
	var defer_order = queue_order and pending_build_started
	if not queue_order:
		pending_build_kind = ""
		pending_build_started = false
	else:
		pending_build_started = true
	game.update_interaction_cursor(game.input_adapter.pointer_position)
	var command = RoRCommands.BuildCommand.new(game.game_controller.tick_index + 1, game._selection_ids(workers), kind, target)
	if kind == "gate":
		command.params["gate_axis"] = pending_gate_axis
	if defer_order:
		# A queued building is still a real world object: reserve and render its
		# foundation now, then queue only the workers' trip to that foundation.
		command.params["plan_only"] = true
	game.enqueue_with_feedback(command, "Строительство: %s" % ("ворота" if kind == "gate" else kind), "command:%s" % String(workers[0].get("kind", "villager")), null)


func queue_wall_line(game, workers: Array, cells: Array[Vector2i], queue_order: bool = false) -> void:
	game.join_simulation_owner()
	if cells.is_empty():
		return
	var command = RoRCommands.BuildCommand.new(game.game_controller.tick_index + 1, game._selection_ids(workers), "wall", Vector2(cells[0]))
	command.params["wall_cells"] = cells.duplicate()
	command.params["queue_order"] = queue_order
	game.enqueue_with_feedback(command, "Строительство стены", "command:%s" % String(workers[0].get("kind", "villager")), null)


func train_unit_from_hud(game, unit_kind: String, building_id: int) -> void:
	game.join_simulation_owner()
	if game.simulation_world == null or game.battle_over or building_id < 0 or unit_kind.is_empty():
		return
	var building: Variant = game.simulation_world.find_building(building_id)
	if building == null:
		game.game_message = "Здание больше недоступно"
		game.message_time = 2.0
		return
	var command = RoRCommands.TrainCommand.new(game.game_controller.tick_index + 1, [building_id], unit_kind, game.local_player_team, Vector2.ZERO)
	game.enqueue_with_feedback(command, "Добавлено в очередь: %s" % unit_kind, "", null)


func research_from_hud(game, technology_id: int, building_id: int) -> void:
	game.join_simulation_owner()
	if game.simulation_world == null or game.battle_over or building_id < 0 or technology_id < 0:
		return
	var building: Variant = game.simulation_world.find_building(building_id)
	if building == null:
		game.game_message = "Здание больше недоступно"
		game.message_time = 2.0
		return
	var command = RoRCommands.ResearchCommand.new(game.game_controller.tick_index + 1, [building_id], String.num_int64(technology_id))
	game.enqueue_with_feedback(command, "Исследование добавлено в очередь", "", null)


func cancel_production_from_hud(game, building_id: int, queue_index: int) -> void:
	game.join_simulation_owner()
	if game.simulation_world == null or building_id < 0:
		return
	var building: Variant = game.simulation_world.find_building(building_id)
	if building == null:
		game.game_message = "Здание больше недоступно"
		game.message_time = 2.0
		return
	var command = RoRCommands.CancelProductionCommand.new(game.game_controller.tick_index + 1, [building_id], queue_index)
	game.enqueue_with_feedback(command, "Элемент очереди отменён", "", null)


func set_trade_resource_from_hud(game, resource_type_id: int) -> void:
	game.join_simulation_owner()
	if game.simulation_world == null or game.battle_over or resource_type_id not in [0, 1, 2]:
		return
	var traders: Array = game.selected_units().filter(func(unit): return bool(unit.get("components", {}).get("trade", {}).get("enabled", false)))
	if traders.is_empty():
		game.game_message = "Выберите торговое судно"
		game.message_time = 2.0
		return
	var command = RoRCommands.SetTradeResourceCommand.new(game.game_controller.tick_index + 1, game._selection_ids(traders), resource_type_id)
	var label: String = String({0: "еда", 1: "дерево", 2: "камень"}.get(resource_type_id, "ресурс"))
	game.enqueue_with_feedback(command, "Торговый ресурс: %s" % label, "", null)


func assign_control_group(game, group_number: int) -> void:
	var ids = game._selection_ids(game.selected_units())
	if ids.is_empty():
		game.game_message = "Нельзя назначить пустую группу"
		game.message_time = 1.5
		return
	game.control_groups.assign(group_number, ids)
	game.game_message = "Группа %d назначена: %d юнитов" % [group_number, ids.size()]
	game.message_time = 1.5


func recall_control_group(game, group_number: int, additive: bool) -> void:
	game.join_simulation_owner()
	var available_ids: Array[int] = []
	# The overview is sampled every four ticks. A key press must validate the
	# current owned units, including deaths and newly trained units between samples.
	for unit in game.simulation_world.get_units():
		if unit["team"] == game.local_player_team and unit["hp"] > 0.0:
			available_ids.append(int(unit["id"]))
	var result: Dictionary = game.control_groups.recall(group_number, available_ids, game._selection_ids(game.selected_units()), additive)
	if result["ids"].is_empty():
		game.game_message = "Группа %d пуста" % group_number
		game.message_time = 1.5
		return
	var recalled_ids: Array[int] = []
	recalled_ids.assign(result["ids"])
	game.player_control_state.replace_or_add(recalled_ids, additive)
	if result["center"]:
		game.center_view_on_units(recalled_ids)
		game.game_message = "Камера: группа %d" % group_number
	else:
		game.game_message = "Выбрана группа %d: %d юнитов" % [group_number, recalled_ids.size()]
	game.message_time = 1.5


func select_hud_building(game, building_id: int) -> void:
	game.join_simulation_owner()
	if game.simulation_world == null:
		return
	var building: Variant = game.simulation_world.find_building(building_id)
	if building == null or int(building.get("team", 0)) != game.local_player_team or float(building.get("hp", 0)) <= 0:
		return
	var ids: Array[int] = [building_id]
	game.player_control_state.replace_or_add(ids, false)
	game.center_view_on_world(Vector2(building.get("pos", Vector2.ZERO)))
	game.sync_world_state()
	game.refresh_hud_model()
	game.queue_redraw()
