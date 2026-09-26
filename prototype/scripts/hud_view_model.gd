class_name RoRHudViewModel
extends RefCounted

const RoRCommands := preload("res://scripts/commands.gd")
const RESOURCE_NAMES := {0: "food", 1: "wood", 2: "stone", 3: "gold"}
const FORMATIONS := [
	{"id": "LINE", "label": "Линия", "hotkey": "F5"},
	{"id": "RECTANGLE", "label": "Каре", "hotkey": "F6"},
	{"id": "COLUMN", "label": "Колонна", "hotkey": "F7"},
	{"id": "WEDGE", "label": "Клин", "hotkey": "F8"},
	{"id": "STAGGERED", "label": "Шахматный", "hotkey": "F9"},
]
const STANCE_LABELS_RU := {
	"aggressive": "Агрессивная",
	"defensive": "Оборонительная",
	"stand_ground": "Держать позицию",
	"passive": "Не атаковать",
}
const UNIT_ACTION_ICON_IDS := {
	"attack_move": 4,
	"attack_ground": 4,
	"stop": 3,
	"hold": 12,
	"stance": 7,
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


func configure(runtime_data: Dictionary, localization_catalog, object_data: Dictionary = {}) -> void:
	runtime_catalog = runtime_data
	localization = localization_catalog
	object_catalog = object_data
	building_icon_set_by_civilization.clear()
	for civilization_value in object_catalog.get("civilizations", []):
		var civilization: Dictionary = civilization_value
		var civilization_id := int(civilization.get("civilization_id", -1))
		var icon_set := int(civilization.get("icon_set", 1))
		building_icon_set_by_civilization[civilization_id] = clampi(icon_set, 0, 4)


func build(snapshot: Dictionary, selected_ids: Array[int], formation_name: String, locale: String = "ru") -> Dictionary:
	var selected := _selected_entities(snapshot, selected_ids)
	var player_state: Dictionary = snapshot.get("player_state", {})
	var spectator := String(player_state.get("status", "active")) in ["resigned", "defeated"]
	var disabled_reason := "battle_over" if bool(snapshot.get("battle_over", false)) else "player_not_active" if spectator else ""
	var selection_model := _selection_model(selected, locale)
	var model := {
		"tick": int(snapshot.get("tick", 0)),
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
		"commands": [],
		"queue": [],
		"battle_over": bool(snapshot.get("battle_over", false)),
		"read_only": not disabled_reason.is_empty(),
		"spectator": spectator,
		"match_result": snapshot.get("match_result", {}).duplicate(true),
	}
	var unit_count := selected.filter(func(entity): return _category(entity) == "unit").size()
	if unit_count == selected.size() and unit_count > 0:
		var leader_stance := String(selected[0].get("stance", "aggressive"))
		var next_stance := RoRCommands.next_stance(leader_stance)
		for action_value in [
			{"id": "attack_move", "label": "Атаковать по пути", "short_label": "АТАКА", "hotkey": "Q"},
			{"id": "stop", "label": "Остановиться", "short_label": "СТОП", "hotkey": "X"},
			{"id": "hold", "label": "Держать позицию", "short_label": "ДЕРЖ", "hotkey": "H"},
			{"id": "stance", "label": "Стойка: %s" % String(STANCE_LABELS_RU.get(next_stance, next_stance)), "short_label": "СТОЙКА", "hotkey": "V", "stance": next_stance},
		]:
			var action: Dictionary = action_value
			action["type"] = "unit_action"
			action["icon_kind"] = "command"
			action["icon_id"] = int(UNIT_ACTION_ICON_IDS.get(String(action.get("id", "")), -1))
			action["enabled"] = disabled_reason.is_empty()
			action["active"] = false
			action["reason"] = disabled_reason
			model["commands"].append(action)
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
				"icon_kind": "command",
				"icon_id": int(UNIT_ACTION_ICON_IDS["attack_ground"]),
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
		if _category(entity) == "unit" and _is_worker(entity):
			selected_worker = entity
			break
	if not selected_worker.is_empty():
		var worker: Dictionary = selected_worker
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
				"icon_kind": _building_icon_kind(worker),
				"icon_id": int(option.get("icon_id", _icon_id_for_kind(kind, worker))),
				"source_unit_id": int(option.get("source_unit_id", -1)),
				"button_id": int(option.get("button_id", -1)),
				"cost": option.get("cost", {}).duplicate(true),
				"cost_text": _cost_text(option.get("cost", {})),
				"duration": float(option.get("duration", 0.0)),
				"enabled": bool(option.get("accepted", false)) and reason.is_empty(),
				"active": false,
				"reason": reason,
			})
	if selected.size() == 1 and _category(selected[0]) == "building":
		var building: Dictionary = selected[0]
		var production_queue: Array = building.get("production_queue", [])
		for option_value in building.get("command_options", {}).get("train", []):
			var option: Dictionary = option_value
			if not _command_option_is_visible(option):
				continue
			var reason := disabled_reason if not disabled_reason.is_empty() else String(option.get("reason", ""))
			var unit_kind := String(option.get("kind", ""))
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
				"label": _name_for_kind(String(option.get("kind", "")), building, locale),
				"icon_kind": "unit",
				"icon_id": _icon_id_for_kind(String(option.get("kind", "")), building),
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
				"icon_id": int(UNIT_ACTION_ICON_IDS["stop"]),
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
	return model


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
	var player_team := int(snapshot.get("observer_team", snapshot.get("player_state", {}).get("team", 0)))
	var result: Array = []
	for collection_name in ["units", "buildings", "resources"]:
		for entity_value in snapshot.get(collection_name, []):
			var entity: Dictionary = entity_value
			if requested.has(int(entity.get("id", -1))) and (collection_name == "resources" or int(entity.get("team", 0)) == player_team) and (collection_name == "resources" or float(entity.get("hp", 0.0)) > 0.0):
				# The view model only reads the detached presentation snapshot. A
				# second deep copy duplicated combat tables and production queues on
				# every fixed tick without providing additional isolation.
				result.append(entity)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


func _selection_model(selected: Array, locale: String) -> Dictionary:
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
			"conversion_enabled": bool(conversion.get("enabled", false)),
			"faith": float(conversion.get("faith", 0.0)),
			"max_faith": float(conversion.get("max_faith", 100.0)),
			"trade_enabled": bool(trade.get("enabled", false)),
			"trade_stage": String(trade.get("stage", "idle")),
			"trade_resource_type_id": int(trade.get("selected_input_resource_type_id", -1)),
			"trade_cargo_gold": int(trade.get("cargo_gold", 0)),
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
		var duration := maxf(0.05, float(order.get("duration", 0.05)))
		var label := _name_for_kind(String(order.get("kind", "")), context_entity, locale) if order_type == "unit" else _technology_name(int(order.get("technology_id", -1)), locale)
		result.append({
			"index": index,
			"id": int(order.get("id", -1)),
			"type": order_type,
			"label": label,
			"status": String(order.get("status", "queued")),
			"progress": clampf(float(order.get("progress", 0.0)) / duration, 0.0, 1.0),
		})
	return result


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


func _icon_id_for_kind(kind: String, entity: Dictionary) -> int:
	var archetype: Dictionary = runtime_catalog.get("archetypes", {}).get(kind, {})
	if archetype.is_empty():
		return -1
	var default_civilization_id := int(archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var civilization_id := int(entity.get("components", {}).get("ownership", {}).get("civilization_id", default_civilization_id))
	var records: Dictionary = archetype.get("records", {})
	var record: Dictionary = records.get(String.num_int64(civilization_id), records.get(String.num_int64(default_civilization_id), {}))
	return int(record.get("presentation", {}).get("icon_id", -1))


func _building_icon_kind(entity: Dictionary) -> String:
	var default_civilization_id := int(runtime_catalog.get("default_civilization_id", 13))
	var civilization_id := int(entity.get("components", {}).get("ownership", {}).get("civilization_id", default_civilization_id))
	var icon_set := int(building_icon_set_by_civilization.get(civilization_id, building_icon_set_by_civilization.get(default_civilization_id, 0)))
	return "building_%d" % clampi(icon_set, 0, 4)


func _command_option_is_visible(option: Dictionary) -> bool:
	return not HIDDEN_COMMAND_REASONS.has(String(option.get("reason", "")))


func _category(entity: Dictionary) -> String:
	var kind := String(entity.get("kind", ""))
	return String(runtime_catalog.get("archetypes", {}).get(kind, {}).get("category", "building" if entity.has("production_queue") else "unit"))


func _is_worker(entity: Dictionary) -> bool:
	return "worker" in entity.get("behavior_tags", []) or String(entity.get("kind", "")) == "villager"


func _age_model(age: int, locale: String) -> Dictionary:
	var english := ["Stone Age", "Tool Age", "Bronze Age", "Iron Age"]
	var russian := ["Каменный век", "Век орудий", "Бронзовый век", "Железный век"]
	var index := clampi(age - 100 if age >= 100 else age, 0, english.size() - 1)
	return {"id": age, "label": russian[index] if locale == "ru" else english[index]}
