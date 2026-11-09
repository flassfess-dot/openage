class_name RoRHudViewModel
extends RefCounted

const IconRegistry := preload("res://scripts/interface_icon_registry.gd")
const GateCatalog := preload("res://scripts/gate_catalog.gd")
const RoRCommands := preload("res://scripts/commands.gd")
const RESOURCE_NAMES := {0: "food", 1: "wood", 2: "stone", 3: "gold"}
const FORMATIONS := [
	{"id": "LINE", "label": "Линия", "hotkey": "F5"},
	{"id": "RECTANGLE", "label": "Каре", "hotkey": "F6"},
	{"id": "COLUMN", "label": "Колонна", "hotkey": "F7"},
	{"id": "WEDGE", "label": "Клин", "hotkey": "F8"},
	{"id": "STAGGERED", "label": "Рассредоточенный", "hotkey": "F9"},
	{"id": "FLANK", "label": "Фланги", "hotkey": "F10"},
]
const STANCE_LABELS_RU := {
	"aggressive": "Агрессивная",
	"defensive": "Оборонительная",
	"stand_ground": "Держать позицию",
	"passive": "Не атаковать",
}
const HIDDEN_COMMAND_REASONS := {
	"building_unavailable": true,
	"unit_unavailable": true,
	"unit_replaced": true,
	"unknown_unit_type": true,
	"wrong_production_location": true,
	"invalid_production_building": true,
	"unknown_technology": true,
	"technology_disabled": true,
	"missing_prerequisites": true,
	"already_researched": true,
	"already_researching": true,
	"wrong_research_location": true,
	"invalid_research_building": true,
}

var runtime_catalog: Dictionary = {}
var object_catalog: Dictionary = {}
var building_icon_set_by_civilization: Dictionary = {}
var localization
var technology_description_cache: Dictionary = {}
var grouped_signature_enabled := OS.get_environment("ROR_DIAGNOSTIC_GROUPED_HUD_SIGNATURE") != "0"
var grouped_signature_calls := 0
var profile_signature := "--profile-grouped-hud-signature" in OS.get_cmdline_user_args()
var last_signature_us := 0


func configure(runtime_data: Dictionary, localization_catalog, object_data: Dictionary = {}) -> void:
	runtime_catalog = runtime_data
	localization = localization_catalog
	object_catalog = object_data
	technology_description_cache.clear()
	building_icon_set_by_civilization.clear()
	for civilization_value in object_catalog.get("civilizations", []):
		var civilization: Dictionary = civilization_value
		var civilization_id := int(civilization.get("civilization_id", -1))
		var icon_set := int(civilization.get("icon_set", 1))
		building_icon_set_by_civilization[civilization_id] = clampi(icon_set, 0, 4)


func build(snapshot: Dictionary, selected_ids: Array[int], formation_name: String, locale: String = "ru") -> Dictionary:
	var selected := _selected_entities(snapshot, selected_ids)
	return _build_from_selected(snapshot, selected, formation_name, locale)


func build_update(snapshot: Dictionary, selected_ids: Array[int], formation_name: String, previous_signature: Variant = null, locale: String = "ru") -> Dictionary:
	var selected := _selected_entities(snapshot, selected_ids)
	var signature_started := Time.get_ticks_usec() if profile_signature else 0
	var signature := _input_signature(snapshot, selected, formation_name, locale)
	if profile_signature: last_signature_us = Time.get_ticks_usec() - signature_started
	if previous_signature != null and int(previous_signature) == signature:
		return {"changed": false, "signature": signature}
	return {
		"changed": true,
		"signature": signature,
		"model": _build_from_selected(snapshot, selected, formation_name, locale),
	}


func refresh_dynamic_model(model: Dictionary, snapshot: Dictionary, selected_ids: Array[int]) -> void:
	model["tick"] = int(snapshot.get("tick", 0))
	model["status_indicators"] = status_indicators(snapshot, model)
	refresh_global_progress(model, snapshot)
	var selected := _selected_entities(snapshot, selected_ids)
	if bool(model.get("read_only", false)) or selected.size() != 1 or _category(selected[0]) != "building":
		return
	var source_queue: Array = selected[0].get("production_queue", [])
	var model_queue: Array = model.get("queue", [])
	if source_queue.size() != model_queue.size():
		return
	for index in range(source_queue.size()):
		var order: Dictionary = source_queue[index]
		var model_order: Dictionary = model_queue[index]
		var duration := maxf(0.05, float(order.get("duration", 0.05)))
		model_order["progress"] = clampf(float(order.get("progress", 0.0)) / duration, 0.0, 1.0)
		model_order["remaining_seconds"] = maxf(0, duration - float(order.get("progress", 0)))


func _build_from_selected(snapshot: Dictionary, selected: Array, formation_name: String, locale: String) -> Dictionary:
	var player_state: Dictionary = snapshot.get("player_state", {})
	var spectator := String(player_state.get("status", "active")) in ["resigned", "defeated"]
	var disabled_reason := "battle_over" if bool(snapshot.get("battle_over", false)) else "player_not_active" if spectator else ""
	var observer_team := int(snapshot.get("observer_team", player_state.get("team", 0)))
	var foreign_selection := selected.any(func(entity): return _category(entity) != "resource" and int(entity.get("team", observer_team)) != observer_team)
	var selection_model := _selection_model(selected, player_state, locale)
	var model := {
		"tick": int(snapshot.get("tick", 0)),
		"icon_team": observer_team,
		"idle_worker_icon_id": _icon_id_for_kind("villager", {"team": observer_team}),
		"resources": {
			"wood": int(player_state.get("wood", 0)),
			"food": int(player_state.get("food", 0)),
			"gold": int(player_state.get("gold", 0)),
			"stone": int(player_state.get("stone", 0)),
		},
		"population": {
			"current": int(player_state.get("population", 0)),
			"points": int(player_state.get("population_points", int(player_state.get("population", 0)) * 2)),
			"reserved": int(player_state.get("population_reserved", 0)),
			"cap": int(player_state.get("population_cap", 0)),
		},
		"kills": int(player_state.get("kills", 0)),
		"age": _age_model(int(player_state.get("age", 0)), locale),
		"selection": selection_model,
		"command_title": "COMMANDS",
		"global_queue": global_queue_model(snapshot, locale),
		"commands": [],
		"queue": [],
		"garrison": {},
		"battle_over": bool(snapshot.get("battle_over", false)),
		"read_only": not disabled_reason.is_empty(),
		"spectator": spectator,
		"match_result": snapshot.get("match_result", {}).duplicate(true),
	}
	if foreign_selection:
		model["read_only"] = true
		model["global_queue"] = []
		model["selection"]["leader"]["show_population"] = false
		model["selection"]["leader"]["farm_reserve_count"] = -1
		return model
	var unit_count := selected.filter(func(entity): return _category(entity) == "unit").size()
	if unit_count == selected.size() and unit_count > 0:
		var leader_stance := String(selected[0].get("stance", "aggressive"))
		var next_stance := RoRCommands.next_stance(leader_stance)
		for action_value in [
			{"id": "attack_move", "label": "Атаковать по пути", "short_label": "АТАКА", "hotkey": "Q"},
			{"id": "stop", "label": "Остановиться", "short_label": "СТОП", "hotkey": "X"},
			{"id": "delete", "label": "Удалить выбранные объекты", "short_label": "УДАЛИТЬ", "hotkey": "Del"},
			{"id": "hold", "label": "Держать позицию", "short_label": "ДЕРЖ", "hotkey": "H"},
			{"id": "stance", "label": "Стойка: %s" % String(STANCE_LABELS_RU.get(next_stance, next_stance)), "short_label": "СТОЙКА", "hotkey": "V", "stance": next_stance},
		]:
			var action: Dictionary = action_value
			action["type"] = "unit_action"
			if String(action["id"]) in ["attack_move", "hold", "stance"] and selected.all(func(unit): return bool(unit.get("components", {}).get("cargo", {}).get("enabled", false))) and not selected.any(func(unit): return bool(unit.get("combat_enabled", false))):
				continue
			action.merge(IconRegistry.command_icon(String(action["id"]), next_stance))
			action["enabled"] = disabled_reason.is_empty()
			action["active"] = false
			action["reason"] = disabled_reason
			model["commands"].append(action)
		var transports := selected.filter(func(unit): return bool(unit.get("components", {}).get("cargo", {}).get("enabled", false)))
		if not transports.is_empty():
			var loaded := transports.any(func(unit): return not unit.get("components", {}).get("cargo", {}).get("passenger_ids", []).is_empty())
			var action := {"type": "unit_action", "id": "unload", "label": "Высадить пассажиров", "short_label": "ВЫСАДКА", "hotkey": "U", "enabled": loaded and disabled_reason.is_empty(), "active": false, "reason": disabled_reason if not disabled_reason.is_empty() else "" if loaded else "Нет пассажиров"}
			action.merge(IconRegistry.command_icon("unload"))
			model["commands"].push_front(action)
		var all_ground_attackers := true
		for entity in selected:
			var combat: Dictionary = entity.get("components", {}).get("combat", {})
			if not bool(entity.get("combat_enabled", false)) or int(combat.get("projectile_id", -1)) < 0 or float(combat.get("blast_range", 0.0)) <= 0.0:
				all_ground_attackers = false
				break
		if all_ground_attackers:
			model["commands"].append({
				"type": "unit_action",
				"id": "attack_ground",
				"label": "Атаковать землю",
				"short_label": "ПО ЗЕМЛЕ",
				"hotkey": "G",
				"icon_kind": "command_custom",
				"icon_id": 0,
				"enabled": disabled_reason.is_empty(),
				"active": false,
				"reason": disabled_reason,
			})
	if unit_count == selected.size() and unit_count > 1:
		for definition_value in FORMATIONS:
			var definition: Dictionary = definition_value
			model["commands"].append({
				"type": "formation",
				"id": String(definition["id"]),
				"label": String(definition["label"]),
				"hotkey": String(definition["hotkey"]),
				"enabled": unit_count > 1 and disabled_reason.is_empty(),
				"active": String(definition["id"]) == formation_name,
				"reason": "single_unit" if unit_count <= 1 else disabled_reason,
			})
	var only_traders := not selected.is_empty() and unit_count == selected.size() and selected.all(func(entity):
		return bool(entity.get("components", {}).get("trade", {}).get("enabled", false))
	)
	if only_traders:
		var selected_resource := int(selected[0].get("components", {}).get("trade", {}).get("selected_input_resource_type_id", 1))
		for resource_type_id in [0, 1, 2]:
			model["commands"].append({
				"type": "trade_resource",
				"id": String.num_int64(resource_type_id),
				"resource_type_id": resource_type_id,
				"label": _trade_resource_label(resource_type_id, locale),
				"cost_text": "20 %s" % String(RESOURCE_NAMES[resource_type_id]).to_upper(),
				"duration": 0.0,
				"enabled": disabled_reason.is_empty(),
				"active": resource_type_id == selected_resource,
				"reason": disabled_reason,
			})
	var selected_worker: Dictionary = {}
	for entity_value in selected:
		var entity: Dictionary = entity_value
		if _category(entity) == "unit" and _is_worker(entity) and String(entity.get("movement_domain", "land")) == "land":
			selected_worker = entity
			break
	if not selected_worker.is_empty():
		var worker: Dictionary = selected_worker
		if String(worker.get("movement_domain", "land")) == "land":
			model["commands"].append({
				"type": "unit_action",
				"id": "repair",
				"label": "Ремонтировать здание или судно",
				"short_label": "РЕМОНТ",
				"hotkey": "R",
				"icon_kind": "command",
				"icon_id": int(IconRegistry.COMMAND_GLYPHS["repair"]),
				"enabled": disabled_reason.is_empty(),
				"active": false,
				"reason": disabled_reason,
			})
		for option_value in worker.get("command_options", {}).get("build", []):
			var option: Dictionary = option_value
			if not _command_option_is_visible(option):
				continue
			var kind := String(option.get("kind", ""))
			var reason := disabled_reason if not disabled_reason.is_empty() else String(option.get("reason", ""))
			model["commands"].append({
				"type": "build",
				"id": kind,
				"label": _name_for_kind(kind, worker, locale),
				"icon_kind": "gate" if kind == "gate" else _building_icon_kind(worker),
				"icon_id": GateCatalog.icon_id(int(option.get("source_unit_id", 10072)), _building_icon_set(worker)) if kind == "gate" else int(option.get("icon_id", _icon_id_for_kind(kind, worker))),
				"source_unit_id": int(option.get("source_unit_id", -1)),
				"button_id": int(option.get("button_id", -1)),
				"cost": option.get("cost", {}).duplicate(true),
				"cost_text": _cost_text(option.get("cost", {})),
				"duration": float(option.get("duration", 0.0)),
				"enabled": bool(option.get("accepted", false)) and reason.is_empty(),
				"active": false,
				"reason": reason,
			})
	if not selected.is_empty() and selected.all(func(entity): return String(entity.get("kind", "")) == "gate"):
		for mode in ["auto", "open", "locked"]:
			model["commands"].append({"type": "unit_action", "id": "gate_" + mode, "label": {"auto": "Автоматические ворота", "open": "Держать открытыми", "locked": "Запереть ворота"}[mode], "short_label": {"auto": "АВТО", "open": "ОТКРЫТЬ", "locked": "ЗАПЕРЕТЬ"}[mode], "icon_kind": "gate_mode", "icon_id": ["auto", "open", "locked"].find(mode), "enabled": disabled_reason.is_empty() and selected.all(func(gate): return String(gate.get("state", "")) == "complete"), "active": selected.all(func(gate): return String(gate.get("gate_mode", "auto")) == mode), "reason": disabled_reason})
	if selected.size() == 1 and _category(selected[0]) == "building":
		var building: Dictionary = selected[0]
		if String(building.get("kind", "")) == "granary" and String(building.get("state", "")) == "complete" and bool(player_state.get("farm_reserve_available", false)):
			var reserve_count := int(player_state.get("farm_reserve_count", 0))
			var reserve_cost: Dictionary = player_state.get("farm_reserve_cost", {})
			var affordable := reserve_cost.keys().all(func(id): return int(player_state.get(RESOURCE_NAMES.get(int(id), ""), 0)) >= int(reserve_cost[id]))
			var farm_context := {"components": {"ownership": building.get("components", {}).get("ownership", {})}}
			model["commands"].append({"type": "farm_reserve", "id": "farm_reserve_add", "amount": 1, "building_id": int(building["id"]), "label": "Зарезервировать повторный посев фермы", "icon_kind": _building_icon_kind(building), "icon_id": _icon_id_for_kind("farm", farm_context), "cost_text": _cost_text(reserve_cost), "queue_count": reserve_count, "enabled": affordable and reserve_count < 40 and disabled_reason.is_empty(), "reason": disabled_reason if not disabled_reason.is_empty() else "insufficient_resources" if not affordable else "farm_reserve_full" if reserve_count >= 40 else ""})
			var cancel_reserve := {"type": "farm_reserve", "id": "farm_reserve_cancel", "amount": -1, "building_id": int(building["id"]), "label": "Отменить один запасной посев с возвратом ресурсов", "enabled": reserve_count > 0 and disabled_reason.is_empty(), "reason": disabled_reason if not disabled_reason.is_empty() else "farm_reserve_empty" if reserve_count == 0 else ""}
			cancel_reserve.merge(IconRegistry.command_icon("cancel_production"))
			model["commands"].append(cancel_reserve)
		if building.has("garrison"):
			var garrison: Dictionary = building["garrison"]
			var occupants: Array = []
			for unit in garrison.get("units", []):
				var entry: Dictionary = unit.duplicate(true)
				entry["name"] = _name_for_kind(String(unit.get("kind", "")), unit, locale)
				entry["icon_kind"] = "unit"
				entry["icon_id"] = _icon_id_for_kind(String(unit.get("kind", "")), unit)
				entry["icon_team"] = int(unit.get("team", 1))
				occupants.append(entry)
			model["garrison"] = {"building_id": int(building["id"]), "capacity": int(garrison.get("capacity", 5)), "units": occupants, "extra_arrows": int(garrison.get("extra_arrows", 0))}
			var action := {"type": "unit_action", "id": "ungarrison", "label": "Высадить весь гарнизон", "short_label": "ВЫСАДИТЬ", "hotkey": "U", "enabled": not occupants.is_empty() and disabled_reason.is_empty(), "reason": disabled_reason, "active": false}
			action.merge(IconRegistry.command_icon("unload"))
			model["commands"].append(action)
		var production_queue: Array = building.get("production_queue", [])
		for option_value in building.get("command_options", {}).get("train", []):
			var option: Dictionary = option_value
			if not _command_option_is_visible(option):
				continue
			var reason := disabled_reason if not disabled_reason.is_empty() else String(option.get("reason", ""))
			var unit_kind := String(option.get("kind", ""))
			var unit_context := _production_unit_context(unit_kind, building, option)
			var queued_count: int = production_queue.filter(func(order): return String(order.get("order_type", "unit")) == "unit" and String(order.get("kind", "")) == unit_kind).size()
			var last_matching_index := -1
			for queue_index in range(production_queue.size() - 1, -1, -1):
				var queued_order: Dictionary = production_queue[queue_index]
				if String(queued_order.get("order_type", "unit")) == "unit" and String(queued_order.get("kind", "")) == unit_kind:
					last_matching_index = queue_index
					break
			model["commands"].append({
				"type": "train",
				"id": unit_kind,
				"building_id": int(building.get("id", -1)),
				"label": _name_for_kind(unit_kind, unit_context, locale),
				"icon_kind": "unit",
				"icon_id": int(option.get("icon_id", _icon_id_for_kind(unit_kind, unit_context))),
				"cost": option.get("cost", {}).duplicate(true),
				"cost_text": _cost_text(option.get("cost", {})),
				"population_cost": int(option.get("population_cost", 0)),
				"queue_count": queued_count,
				"cancel_queue_index": last_matching_index,
				"hotkey": "Z" if unit_kind == "swordsman" else "T" if unit_kind == "scout" else "",
				"duration": float(option.get("duration", 0.0)),
				"enabled": bool(option.get("accepted", false)) and reason.is_empty(),
				"active": false,
				"reason": reason,
			})
		for option_value in building.get("command_options", {}).get("research", []):
			var option: Dictionary = option_value
			if not _command_option_is_visible(option):
				continue
			var reason := disabled_reason if not disabled_reason.is_empty() else String(option.get("reason", ""))
			var technology_id := int(option.get("technology_id", -1))
			model["commands"].append({
				"type": "research",
				"id": String.num_int64(technology_id),
				"technology_id": technology_id,
				"building_id": int(building.get("id", -1)),
				"label": _technology_name(technology_id, locale),
				"description": _technology_description(technology_id, locale, building),
				"icon_kind": "technology",
				"icon_id": int(object_catalog.get("technologies", {}).get(String.num_int64(technology_id), {}).get("icon_id", -1)),
				"cost": option.get("cost", {}).duplicate(true),
				"cost_text": _cost_text(option.get("cost", {})),
				"duration": float(option.get("duration", 0.0)),
				"enabled": bool(option.get("accepted", false)) and reason.is_empty(),
				"active": false,
				"reason": reason,
			})
		var queue_model: Array = _queue_model(production_queue, building, locale)
		model["queue"] = queue_model
		if not queue_model.is_empty():
			var last_index: int = queue_model.size() - 1
			var last_order: Dictionary = queue_model[last_index]
			model["commands"].append({
				"type": "cancel_production",
				"id": "cancel_0",
				"building_id": int(building.get("id", -1)),
				"queue_index": last_index,
				"label": "Отменить один: %s" % String(last_order.get("label", "")) if locale == "ru" else "Cancel one: %s" % String(last_order.get("label", "")),
				"cost_text": "",
				"duration": 0.0,
				"enabled": disabled_reason.is_empty(),
				"active": false,
				"reason": disabled_reason,
			})
		if production_queue.size() > 1:
			model["commands"].append({
				"type": "unit_action",
				"id": "stop",
				"label": "Очистить ожидающую очередь" if locale == "ru" else "Clear waiting queue",
				"short_label": "СТОП" if locale == "ru" else "STOP",
				"hotkey": "X",
				"icon_kind": "command",
				"icon_id": int(IconRegistry.COMMAND_GLYPHS["stop"]),
				"enabled": disabled_reason.is_empty(),
				"active": false,
				"reason": disabled_reason,
			})
	if model["commands"].any(func(command): return String(command.get("type", "")) == "trade_resource"):
		model["command_title"] = "TRADE"
	elif model["commands"].any(func(command): return String(command.get("type", "")) == "build"):
		model["command_title"] = "BUILD"
	elif model["commands"].any(func(command): return String(command.get("type", "")) in ["formation", "unit_action"]):
		model["command_title"] = "ORDERS"
	model["status_indicators"] = status_indicators(snapshot, model)
	refresh_global_progress(model, snapshot)
	return model


func _input_signature(snapshot: Dictionary, selected: Array, formation_name: String, locale: String) -> int:
	var player_state: Dictionary = snapshot.get("player_state", {})
	var values: Array = [
		global_input_signature(snapshot),
		formation_name,
		locale,
		int(snapshot.get("observer_team", player_state.get("team", 0))),
		bool(snapshot.get("battle_over", false)),
		hash(snapshot.get("match_result", {})),
		int(player_state.get("wood", 0)),
		int(player_state.get("food", 0)),
		int(player_state.get("gold", 0)),
		int(player_state.get("stone", 0)),
		int(player_state.get("population", 0)),
		int(player_state.get("population_points", int(player_state.get("population", 0)) * 2)),
		int(player_state.get("population_reserved", 0)),
		int(player_state.get("population_cap", 0)),
		int(player_state.get("kills", 0)),
		int(player_state.get("age", 0)),
		int(player_state.get("farm_reserve_count", 0)),
		hash(player_state.get("farm_reserve_cost", {})),
		String(player_state.get("status", "active")),
		int(player_state.get("blocked_population_queues", 0)),
	]
	if grouped_signature_enabled:
		values.append(_selection_input_signature(selected, int(snapshot.get("observer_team", player_state.get("team", 0)))))
	else:
		for entity_value in selected:
			values.append(_entity_input_signature(entity_value))
	return hash(values)


func _selection_input_signature(selected: Array, observer_team: int) -> int:
	grouped_signature_calls += 1
	if selected.is_empty(): return hash([])
	# The panel displays the leader's detailed statistics. Other members affect
	# group capabilities and membership, not the leader's HP, armor or cargo.
	# Hash exactly those group inputs instead of every combat table and queue.
	var leader: Dictionary = selected[0]
	var leader_kind := String(leader.get("kind", ""))
	var leader_category := _category(leader)
	var members: Array[int] = []
	var homogeneous := true
	var same_category := true
	var unit_count := 0
	var foreign := false
	var all_transports := true
	var any_combat := false
	var loaded_transport := false
	var ground_attackers := true
	var traders := true
	var all_gates := true
	var complete_gates := true
	var gate_modes: Dictionary = {}
	var first_worker: Dictionary = {}
	for entity_value in selected:
		var entity: Dictionary = entity_value
		var kind := String(entity.get("kind", ""))
		var category := _category(entity)
		var components: Dictionary = entity.get("components", {})
		var cargo: Dictionary = components.get("cargo", {})
		var combat: Dictionary = components.get("combat", {})
		var transport := bool(cargo.get("enabled", false))
		var combat_enabled := bool(entity.get("combat_enabled", false))
		members.append(int(entity.get("id", -1)))
		homogeneous = homogeneous and kind == leader_kind
		same_category = same_category and category == leader_category
		if category == "unit": unit_count += 1
		foreign = foreign or (category != "resource" and int(entity.get("team", observer_team)) != observer_team)
		all_transports = all_transports and transport
		any_combat = any_combat or combat_enabled
		loaded_transport = loaded_transport or (transport and not cargo.get("passenger_ids", []).is_empty())
		ground_attackers = ground_attackers and combat_enabled and int(combat.get("projectile_id", -1)) >= 0 and float(combat.get("blast_range", 0.0)) > 0.0
		traders = traders and bool(components.get("trade", {}).get("enabled", false))
		all_gates = all_gates and kind == "gate"
		if kind == "gate":
			complete_gates = complete_gates and String(entity.get("state", "")) == "complete"
			gate_modes[String(entity.get("gate_mode", "auto"))] = true
		if first_worker.is_empty() and category == "unit" and _is_worker(entity) and String(entity.get("movement_domain", "land")) == "land": first_worker = entity
	var leader_signature := _entity_input_signature(leader)
	var worker_signature := 0 if first_worker.is_empty() or is_same(first_worker, leader) else _entity_input_signature(first_worker)
	return hash([members, leader_signature, worker_signature, homogeneous, same_category, unit_count, foreign, all_transports, any_combat, loaded_transport, ground_attackers, traders, all_gates, complete_gates, gate_modes])


func _entity_input_signature(entity: Dictionary) -> int:
	var components: Dictionary = entity.get("components", {})
	var combat: Dictionary = components.get("combat", {})
	var conversion: Dictionary = components.get("conversion", {})
	var trade: Dictionary = components.get("trade", {})
	var ownership: Dictionary = components.get("ownership", {})
	var worker: Dictionary = components.get("worker", {})
	var cargo: Dictionary = components.get("cargo", {})
	return hash([
		int(entity.get("id", -1)),
		int(entity.get("team", 0)),
		String(entity.get("kind", "")),
		_category(entity),
		int(entity.get("source_unit_id", -1)),
		int(entity.get("presentation_facing", 0)),
		float(entity.get("hp", 0.0)),
		float(entity.get("max_hp", 0.0)),
		float(entity.get("attack_damage", 0.0)),
		String(entity.get("task", "")),
		String(entity.get("state", "")),
		String(entity.get("stance", "")),
		String(entity.get("gate_mode", "")),
		float(entity.get("carried_amount", 0.0)),
		float(entity.get("carry_capacity", 0.0)),
		int(entity.get("carried_resource_type_id", -1)),
		bool(entity.get("harvestable", false)),
		int(entity.get("amount", 0)),
		int(entity.get("max_amount", 0)),
		String(entity.get("resource_state", "")),
		bool(entity.get("combat_enabled", false)),
		hash(combat.get("attacks", [])),
		hash(combat.get("armors", [])),
		float(combat.get("base_armor", 0.0)),
		int(combat.get("projectile_id", -1)),
		float(combat.get("blast_range", 0.0)),
		bool(conversion.get("enabled", false)),
		float(conversion.get("faith", 0.0)),
		float(conversion.get("max_faith", 100.0)),
		bool(trade.get("enabled", false)),
		String(trade.get("stage", "idle")),
		int(trade.get("selected_input_resource_type_id", -1)),
		int(trade.get("cargo_gold", 0)),
		int(ownership.get("civilization_id", runtime_catalog.get("default_civilization_id", 13))),
		bool(worker.get("enabled", false)),
		bool(cargo.get("enabled", false)),
		hash(entity.get("garrison", {})),
		int(cargo.get("capacity", 0)),
		hash(cargo.get("passenger_ids", [])),
		hash(entity.get("behavior_tags", [])),
		hash(entity.get("command_options", {})),
		_production_queue_signature(entity.get("production_queue", [])),
	])


func _production_queue_signature(queue: Array) -> int:
	var values: Array = []
	for order_value in queue:
		var order: Dictionary = order_value
		values.append([
			int(order.get("id", -1)),
			String(order.get("order_type", "unit")),
			String(order.get("kind", "")),
			int(order.get("technology_id", -1)),
			String(order.get("status", "queued")),
			float(order.get("duration", 0.05)),
			int(order.get("population_cost", 0)),
		])
	return hash(values)


static func status_indicators(snapshot: Dictionary, model: Dictionary) -> Dictionary:
	var population: Dictionary = model.get("population", {})
	var player_state: Dictionary = snapshot.get("player_state", {})
	var queue: Array = model.get("queue", [])
	var blocked := int(player_state.get("blocked_population_queues", 0)) > 0 or (not queue.is_empty() and String(queue[0].get("status", "")) == "blocked_population")
	var elapsed := maxf(0.0, float(snapshot.get("match_elapsed_seconds", float(snapshot.get("tick", 0)) * 0.05)))
	var whole_seconds := floori(elapsed)
	var hours := int(whole_seconds / 3600.0)
	var minutes := int(whole_seconds / 60.0) % 60
	var seconds := whole_seconds % 60
	return {
		"population_text": "%d/%d" % [int(population.get("current", 0)), int(population.get("cap", 0))],
		"clock_text": "%02d:%02d:%02d" % [hours, minutes, seconds],
		"blocked": blocked,
		"blink_on": not blocked or floori(elapsed * 2.0) % 2 == 0,
	}


func _selected_entities(snapshot: Dictionary, selected_ids: Array[int]) -> Array:
	var requested: Dictionary = {}
	for entity_id in selected_ids:
		requested[int(entity_id)] = true
	var result: Array = []
	var has_control_projection := snapshot.has("control_units") and snapshot.has("control_buildings") and snapshot.has("control_resources")
	var collection_sets: Array = []
	if has_control_projection:
		collection_sets.append(["control_units", "control_buildings", "control_resources"])
	# A snapshot may expose empty control arrays when it was created without an
	# always-include selection. Fall back only for IDs missing from the compact
	# projection, preserving the fast path used by the live HUD.
	collection_sets.append(["units", "buildings", "resources"])
	var found: Dictionary = {}
	for collection_names_value in collection_sets:
		var collection_names: Array = collection_names_value
		for collection_name_value in collection_names:
			var collection_name := String(collection_name_value)
			var is_resource_collection: bool = collection_name in ["resources", "control_resources"]
			for entity_value in snapshot.get(collection_name, []):
				var entity: Dictionary = entity_value
				var entity_id := int(entity.get("id", -1))
				if requested.has(entity_id) and not found.has(entity_id) and not bool(entity.get("last_known", false)) and (is_resource_collection or float(entity.get("hp", 0.0)) > 0.0):
					# The view model only reads the detached presentation snapshot. A
					# second deep copy duplicated combat tables and production queues on
					# every fixed tick without providing additional isolation.
					result.append(entity)
					found[entity_id] = true
		if found.size() >= requested.size():
			break
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


func _selection_model(selected: Array, player_state: Dictionary, locale: String) -> Dictionary:
	if selected.is_empty():
		return {"count": 0, "category": "none", "leader": {}, "summary": "Ничего не выбрано" if locale == "ru" else "Nothing selected"}
	var leader: Dictionary = selected[0]
	var category := _category(leader)
	var homogeneous := selected.all(func(entity): return String(entity.get("kind", "")) == String(leader.get("kind", "")))
	var conversion: Dictionary = leader.get("components", {}).get("conversion", {})
	var trade: Dictionary = leader.get("components", {}).get("trade", {})
	var ownership: Dictionary = leader.get("components", {}).get("ownership", {})
	var civilization_id := int(ownership.get("civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var combat: Dictionary = leader.get("components", {}).get("combat", {})
	var kind := String(leader.get("kind", ""))
	var show_hp := not (category == "resource" and kind in ["berries", "shore_fish", "deep_fish"])
	var show_combat_stats := category != "building" or kind in ["tower", "mirror_tower"]
	return {
		"count": selected.size(),
		"category": category if selected.all(func(entity): return _category(entity) == category) else "mixed",
		"leader": {
			"id": int(leader.get("id", -1)),
			"kind": String(leader.get("kind", "")),
			"name": _name_for_kind(String(leader.get("kind", "")), leader, locale),
			"civilization_id": civilization_id,
			"civilization_name": _civilization_name(civilization_id, locale),
			"hp": roundi(float(leader.get("hp", 0.0))),
			"max_hp": roundi(float(leader.get("max_hp", 0.0))),
			"show_hp": show_hp,
			"show_combat_stats": show_combat_stats,
			"attack": roundi(float(leader.get("attack_damage", _largest_amount(combat.get("attacks", []))))),
			"armor": maxi(0, roundi(maxf(float(combat.get("base_armor", 0.0)), _largest_amount(combat.get("armors", []))))),
			"task": String(leader.get("task", leader.get("state", ""))),
			"stance": String(leader.get("stance", "")),
			"carried_amount": roundi(float(leader.get("carried_amount", 0.0))),
			"carry_capacity": roundi(float(leader.get("carry_capacity", 0.0))),
			"carried_resource": String(RESOURCE_NAMES.get(int(leader.get("carried_resource_type_id", -1)), "")),
			"resource_amount": int(leader.get("amount", 0)) if bool(leader.get("harvestable", false)) or category == "resource" else 0,
			"resource_maximum": int(leader.get("max_amount", 0)) if bool(leader.get("harvestable", false)) or category == "resource" else 0,
			"resource_state": String(leader.get("resource_state", "")),
			"show_population": category == "building" and kind == "house" and selected.size() == 1,
			"farm_reserve_count": int(player_state.get("farm_reserve_count", 0)) if kind == "granary" else -1,
			"population_current": int(player_state.get("population", 0)),
			"population_cap": int(player_state.get("population_cap", 0)),
			"conversion_enabled": bool(conversion.get("enabled", false)),
			"faith": float(conversion.get("faith", 0.0)),
			"max_faith": float(conversion.get("max_faith", 100.0)),
			"trade_enabled": bool(trade.get("enabled", false)),
			"trade_stage": String(trade.get("stage", "idle")),
			"trade_resource_type_id": int(trade.get("selected_input_resource_type_id", -1)),
			"trade_cargo_gold": int(trade.get("cargo_gold", 0)),
			"icon_team": int(leader.get("team", 1)),
			"icon_kind": _building_icon_kind(leader) if category == "building" else "unit",
			"icon_id": _icon_id_for_kind(String(leader.get("kind", "")), leader),
		},
		"summary": _name_for_kind(String(leader.get("kind", "")), leader, locale) if selected.size() == 1 else "%d × %s" % [selected.size(), _name_for_kind(String(leader.get("kind", "")), leader, locale)] if homogeneous else "%d %s" % [selected.size(), "объектов" if locale == "ru" else "objects"],
	}


func _civilization_name(civilization_id: int, locale: String) -> String:
	# The original language table numbers the twelve AoE civilizations from
	# 10231 and the four Rise of Rome additions from 10246.
	var name_id := 10230 + civilization_id if civilization_id <= 12 else 10233 + civilization_id
	if localization != null and civilization_id > 0:
		var translated := String(localization.text(name_id, locale))
		if not translated.begins_with("["):
			return translated
	return "Цивилизация %d" % civilization_id if locale == "ru" else "Civilization %d" % civilization_id


func _largest_amount(entries: Array) -> float:
	var result := 0.0
	for entry_value in entries:
		var entry: Dictionary = entry_value
		result = maxf(result, float(entry.get("amount", 0.0)))
	return result


func _trade_resource_label(resource_type_id: int, locale: String) -> String:
	var english := {0: "Trade Food", 1: "Trade Wood", 2: "Trade Stone"}
	var russian := {0: "Обменивать еду", 1: "Обменивать дерево", 2: "Обменивать камень"}
	return String((russian if locale == "ru" else english).get(resource_type_id, "Trade"))


func _queue_model(queue: Array, context_entity: Dictionary, locale: String) -> Array:
	var result: Array = []
	for index in range(queue.size()):
		var order: Dictionary = queue[index]
		var order_type := String(order.get("order_type", "unit"))
		var kind := String(order.get("kind", ""))
		var technology_id := int(order.get("technology_id", -1))
		var duration := maxf(0.05, float(order.get("duration", 0.05)))
		var technology: Dictionary = object_catalog.get("technologies", {}).get(String.num_int64(technology_id), {})
		var unit_context := _production_unit_context(kind, context_entity, order)
		result.append({
			"index": index,
			"id": int(order.get("id", -1)),
			"type": order_type,
			"kind": kind,
			"technology_id": technology_id,
			"label": _name_for_kind(kind, unit_context, locale) if order_type == "unit" else _technology_name(technology_id, locale),
			"icon_team": int(context_entity.get("team", 1)),
			"icon_kind": "unit" if order_type == "unit" else "technology",
			"icon_id": _icon_id_for_kind(kind, unit_context) if order_type == "unit" else int(technology.get("icon_id", -1)),
			"status": String(order.get("status", "queued")),
			"duration": duration,
			"remaining_seconds": maxf(0, duration - float(order.get("progress", 0))),
			"progress": clampf(float(order.get("progress", 0.0)) / duration, 0.0, 1.0),
		})
	return result

func _production_unit_context(kind: String, building: Dictionary, metadata: Dictionary) -> Dictionary:
	var source_id := int(metadata.get("source_unit_id", -1))
	if source_id < 0:
		for option in building.get("command_options", {}).get("train", []):
			if String(option.get("kind", "")) == kind:
				source_id = int(option.get("source_unit_id", -1))
				break
	return {"kind": kind, "source_unit_id": source_id, "team": int(building.get("team", 1)), "components": building.get("components", {})}

func _name_for_kind(kind: String, entity: Dictionary, locale: String) -> String:
	var archetype: Dictionary = runtime_catalog.get("archetypes", {}).get(kind, {})
	if archetype.is_empty():
		return kind
	var civilization_id := int(entity.get("components", {}).get("ownership", {}).get("civilization_id", archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13))))
	var records: Dictionary = archetype.get("records", {})
	var record: Dictionary = records.get(String.num_int64(civilization_id), records.get(String.num_int64(int(archetype.get("default_civilization_id", 13))), {}))
	var presentation: Dictionary = record.get("presentation", {})
	var fallback := String(presentation.get("fallback_name", kind))
	var name_id := int(presentation.get("name_id", -1))
	if String(entity.get("kind", "")) == kind:
		var source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [civilization_id, int(entity.get("source_unit_id", -1))], {})
		name_id = int(source.get("language", {}).get("name_id", name_id))
	if localization == null or name_id < 0:
		return fallback
	var translated := String(localization.text(name_id, locale))
	return fallback if translated.begins_with("[") else translated


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for resource_id in [0, 1, 2, 3]:
		if int(cost.get(resource_id, 0)) > 0:
			parts.append("%d %s" % [int(cost[resource_id]), String(RESOURCE_NAMES[resource_id]).to_upper()])
	return " · ".join(parts)


func _technology_name(technology_id: int, locale: String) -> String:
	var record: Dictionary = object_catalog.get("technologies", {}).get(String.num_int64(technology_id), {})
	var name_id := int(record.get("language", {}).get("name_id", -1))
	if localization != null and name_id >= 0:
		var translated := String(localization.text(name_id, locale))
		if not translated.begins_with("["):
			return translated
	return "%s %d" % ["Исследование" if locale == "ru" else "Research", technology_id]


func _technology_description(technology_id: int, locale: String, building: Dictionary) -> String:
	var civilization_id := int(building.get("components", {}).get("ownership", {}).get("civilization_id", 0))
	var key := "%d:%d:%s" % [technology_id, civilization_id, locale]
	if technology_description_cache.has(key):
		return technology_description_cache[key]
	var record: Dictionary = object_catalog.get("technologies", {}).get(str(technology_id), {})
	var lines: PackedStringArray = []
	var description_id := int(record.get("language", {}).get("description_id", -1))
	if localization != null and description_id > 0:
		var text := String(localization.text(description_id, locale)).strip_edges()
		if not text.begins_with("["): lines.append(text)
	# The original Russian localization mistranslates these effects (HP as
	# attack/range, and shared sight as shared research). Follow the DAT rules.
	if locale == "ru":
		var corrections := {
			21: "Удваивает здоровье жрецов, помогая им пережить нападение.",
			34: "Увеличивает здоровье кавалерии, конных лучников, колесниц и всадников на верблюдах на 15%. Необходимо для боевых колесниц.",
			112: "Ускоряет строительство на 33% и увеличивает здоровье зданий и стен на 20%.",
			114: "Открывает общий обзор и исследованную карту союзников. Позволяет видеть происходящее у союзников.",
		}
		if corrections.has(technology_id): lines = PackedStringArray([corrections[technology_id]])
	if technology_id in [101, 102, 103]:
		lines.append("Открывает здания, войска и исследования следующей эпохи, доступные вашей цивилизации." if locale == "ru" else "Unlocks the next age's buildings, troops and technologies available to your civilization.")
	var bundle: Dictionary = object_catalog.get("effect_bundles", {}).get(str(record.get("effect_bundle_id", -1)), {})
	for effect in bundle.get("commands", []):
		var type_id := int(effect.get("type_id", -1))
		if type_id != 3 and not (type_id == 2 and int(effect.get("attr_b", 0)) == 1): continue
		var new_id := int(effect.get("attr_b", -1)) if type_id == 3 else int(effect.get("attr_a", -1))
		var source := _technology_object(new_id, civilization_id)
		if source.is_empty(): continue
		var name := String(localization.text(int(source.get("language", {}).get("name_id", -1)), locale)) if localization != null else ""
		var is_building := int(source.get("unit_type", 0)) == 80
		if type_id == 3:
			lines.append("Улучшает существующие и новые объекты: %s." % name if locale == "ru" else "Upgrades existing and newly created objects to %s." % name)
		else:
			lines.append(("Позволяет строить: %s." if is_building else "Позволяет нанимать: %s.") % name if locale == "ru" else "Unlocks %s." % name)
		# The imported unit help explains roles and special attacks omitted from
		# short upgrade labels. Prefer the detailed encyclopedia entry.
		if localization != null and not name.is_empty():
			var strings: Dictionary = localization.languages.get(locale, {}).get("strings", {})
			var help := ""
			for string_id in strings:
				var text := String(strings[string_id])
				if int(string_id) >= 39000 and int(string_id) < 40000 and text.begins_with(name + " - ") and text.length() > help.length(): help = text
			if not help.is_empty(): lines.append(help.substr(name.length() + 3))
		var old := _technology_object(int(effect.get("attr_a", -1)), civilization_id) if type_id == 3 else {}
		var stats: PackedStringArray = []
		for stat in ["health", "range", "attack", "speed"]:
			var value := _technology_stat(source, stat)
			var before := _technology_stat(old, stat)
			if value <= 0.0 or (not old.is_empty() and is_equal_approx(value, before)): continue
			var label: String = String({"health": "Здоровье", "range": "Дальность", "attack": "Атака", "speed": "Скорость"}.get(stat)) if locale == "ru" else String(stat).capitalize()
			stats.append("%s: %s%s" % [label, String.num(before, 2) + " → " if not old.is_empty() else "", String.num(value, 2)])
		if not stats.is_empty(): lines.append(("Базовые параметры: " if locale == "ru" else "Base stats: ") + "; ".join(stats))
	var result := "\n".join(lines)
	technology_description_cache[key] = result
	return result


func _technology_object(unit_id: int, civilization_id: int) -> Dictionary:
	var objects: Dictionary = object_catalog.get("objects", {})
	return objects.get("%d:%d" % [civilization_id, unit_id], objects.get("0:%d" % unit_id, {}))


func _technology_stat(source: Dictionary, stat: String) -> float:
	match stat:
		"health", "speed": return float(source.get(stat, 0.0))
		"range": return float(source.get("combat", {}).get("range_max", 0.0))
		"attack":
			var damage := 0.0
			for attack in source.get("combat", {}).get("attacks", []):
				if int(attack.get("type_id", -1)) in [3, 4]: damage = maxf(damage, float(attack.get("amount", 0.0)))
			return damage
	return 0.0


func _icon_id_for_kind(kind: String, entity: Dictionary) -> int:
	if kind == "gate":
		return GateCatalog.icon_id(int(entity.get("source_unit_id", 10072)), _building_icon_set(entity))
	var archetype: Dictionary = runtime_catalog.get("archetypes", {}).get(kind, {})
	if archetype.is_empty():
		return -1
	var default_civilization_id := int(archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var civilization_id := int(entity.get("components", {}).get("ownership", {}).get("civilization_id", default_civilization_id))
	# A selected entity can have advanced to another DAT record while retaining
	# its gameplay kind. Its current source and packed age facet own the icon.
	if String(entity.get("kind", "")) == kind:
		var source_id := int(entity.get("source_unit_id", -1))
		var source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [civilization_id, source_id], {})
		var icon_id := int(source.get("interface", {}).get("icon_id", -1))
		if icon_id >= 0:
			return icon_id + maxi(0, int(entity.get("presentation_facing", 0))) if _category(entity) == "building" else icon_id
	var records: Dictionary = archetype.get("records", {})
	var record: Dictionary = records.get(String.num_int64(civilization_id), records.get(String.num_int64(default_civilization_id), {}))
	return int(record.get("presentation", {}).get("icon_id", -1))


func _building_icon_kind(entity: Dictionary) -> String:
	if String(entity.get("kind", "")) == "gate":
		return "gate"
	return "building_%d" % _building_icon_set(entity)


func _building_icon_set(entity: Dictionary) -> int:
	var default_civilization_id := int(runtime_catalog.get("default_civilization_id", 13))
	var civilization_id := int(entity.get("components", {}).get("ownership", {}).get("civilization_id", default_civilization_id))
	var icon_set := int(building_icon_set_by_civilization.get(civilization_id, building_icon_set_by_civilization.get(default_civilization_id, 0)))
	return clampi(icon_set, 0, 4)


func _command_option_is_visible(option: Dictionary) -> bool:
	return not HIDDEN_COMMAND_REASONS.has(String(option.get("reason", "")))


func _category(entity: Dictionary) -> String:
	var kind := String(entity.get("kind", ""))
	return String(runtime_catalog.get("archetypes", {}).get(kind, {}).get("category", "building" if entity.has("production_queue") else "unit"))


func _is_worker(entity: Dictionary) -> bool:
	return "worker" in entity.get("behavior_tags", []) or String(entity.get("kind", "")) == "villager"


func _age_model(age: int, locale: String) -> Dictionary:
	var english := ["Stone Age", "Tool Age", "Bronze Age", "Iron Age"]
	var russian := ["Каменный век", "Неолит", "Бронзовый век", "Железный век"]
	var index := clampi(age - 100 if age >= 100 else age, 0, english.size() - 1)
	return {"id": age, "label": russian[index] if locale == "ru" else english[index]}


func global_queue_model(snapshot: Dictionary, locale: String) -> Array:
	var result: Array = []
	for building_value in snapshot.get("production_overview", []):
		var building: Dictionary = building_value
		var orders := _queue_model(building.get("production_queue", []), building, locale)
		if orders.is_empty():
			continue
		var entry: Dictionary = orders[0]
		entry["building_id"] = int(building.get("id", -1))
		entry["building_label"] = _name_for_kind(String(building.get("kind", "")), building, locale)
		result.append(entry)
	return result


static func global_input_signature(snapshot: Dictionary) -> int:
	var values: Array = []
	for building_value in snapshot.get("production_overview", []):
		var building: Dictionary = building_value
		var orders: Array = building.get("production_queue", [])
		if not orders.is_empty():
			var order: Dictionary = orders[0]
			values.append([building.get("id"), order.get("id"), order.get("status"), order.get("source_unit_id")])
	return hash(values)


static func refresh_global_progress(model: Dictionary, snapshot: Dictionary) -> void:
	var heads: Dictionary = {}
	for building_value in snapshot.get("production_overview", []):
		var building: Dictionary = building_value
		var orders: Array = building.get("production_queue", [])
		if not orders.is_empty():
			heads[int(building.get("id", -1))] = orders[0]
	for entry_value in model.get("global_queue", []):
		var entry: Dictionary = entry_value
		var order: Dictionary = heads.get(int(entry.get("building_id", -1)), {})
		var duration := maxf(0.05, float(order.get("duration", 0.05)))
		entry["progress"] = clampf(float(order.get("progress", 0)) / duration, 0, 1)
		entry["remaining_seconds"] = maxf(0, duration - float(order.get("progress", 0)))
