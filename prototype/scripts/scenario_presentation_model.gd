class_name RoRScenarioPresentationModel
extends RefCounted

var localization
var object_catalog: Dictionary = {}


func configure(localization_catalog, object_data: Dictionary) -> void:
	localization = localization_catalog
	object_catalog = object_data


func build(match_definition: Dictionary, scenario_state: Dictionary, observer_team: int, locale: String = "ru") -> Dictionary:
	var participant: Dictionary = scenario_state.get("participant", {})
	if participant.is_empty():
		return {"visible": false, "objectives": [], "over": false, "outcome": ""}
	var condition_states: Dictionary = scenario_state.get("condition_states", {})
	var aggregates: Dictionary = {}
	for group_value in participant.get("groups", []):
		var group: Dictionary = group_value
		for condition_value in group.get("conditions", []):
			var condition: Dictionary = condition_value
			var key := _aggregate_key(condition)
			if not aggregates.has(key):
				aggregates[key] = {
					"condition": condition.duplicate(true),
					"condition_count": 0,
					"achieved_count": 0,
				}
			var aggregate: Dictionary = aggregates[key]
			aggregate["condition_count"] = int(aggregate["condition_count"]) + 1
			var state: Dictionary = condition_states.get(String(condition.get("id", "")), {})
			if bool(state.get("achieved", false)):
				aggregate["achieved_count"] = int(aggregate["achieved_count"]) + 1
	var objectives: Array = []
	var keys: Array = aggregates.keys()
	keys.sort()
	for key_value in keys:
		var aggregate: Dictionary = aggregates[key_value]
		var condition: Dictionary = aggregate["condition"]
		var current := int(aggregate["achieved_count"])
		var required := int(aggregate["condition_count"])
		objectives.append({
			"id": String(key_value),
			"label": _condition_label(condition, required, match_definition, observer_team, locale),
			"current": current,
			"required": required,
			"achieved": current >= required,
		})
	var result: Dictionary = scenario_state.get("result", {})
	var over := bool(result.get("over", false))
	var winner_team := int(result.get("winner_team", -1))
	var winning_side: Array = result.get("winner_teams", [winner_team])
	return {
		"visible": true,
		"title": String(match_definition.get("title", "Сценарий")),
		"briefing": String(match_definition.get("briefing", match_definition.get("start_message", ""))),
		"objectives": objectives,
		"over": over,
		"winner_team": winner_team,
		"outcome": "victory" if over and observer_team in winning_side else "defeat" if over else "",
	}


func _aggregate_key(condition: Dictionary) -> String:
	return "%s:%d:%s" % [
		String(condition.get("type", "unknown")),
		int(condition.get("source_unit_id", condition.get("target_source_unit_id", condition.get("target_team", -1)))),
		String(condition.get("kind", "")),
	]


func _condition_label(condition: Dictionary, count: int, match_definition: Dictionary, observer_team: int, locale: String) -> String:
	match String(condition.get("type", "")):
		"create_in_area":
			var name := _source_object_name(int(condition.get("source_unit_id", -1)), match_definition, observer_team, locale)
			if locale == "ru":
				return "Постройте «%s» в каждой из отмеченных областей" % name if count > 1 else "Постройте «%s» в отмеченной области" % name
			return "Build %s in every marked area" % name if count > 1 else "Build %s in the marked area" % name
		"destroy_player":
			return "Уничтожьте игрока %d" % int(condition.get("target_team", -1)) if locale == "ru" else "Destroy player %d" % int(condition.get("target_team", -1))
		"destroy_object":
			var name := _source_object_name(int(condition.get("target_source_unit_id", -1)), match_definition, observer_team, locale)
			if locale == "ru":
				return "Уничтожьте: %s (%d)" % [name, count] if count > 1 else "Уничтожьте: %s" % name
			return "Destroy: %s (%d)" % [name, count] if count > 1 else "Destroy: %s" % name
		"destroy_count":
			var name := _source_object_name(int(condition.get("target_source_unit_id", -1)), match_definition, observer_team, locale)
			var required := int(condition.get("required_count", count))
			return "Уничтожьте: %s (%d)" % [name, required] if locale == "ru" else "Destroy: %s (%d)" % [name, required]
		"bring_object_to_area":
			var name := _source_object_name(int(condition.get("target_source_unit_id", -1)), match_definition, observer_team, locale)
			return "Доставьте «%s» в отмеченную область" % name if locale == "ru" else "Bring %s to the marked area" % name
	return "Выполните условие сценария" if locale == "ru" else "Complete the scenario objective"


func _source_object_name(source_unit_id: int, match_definition: Dictionary, observer_team: int, locale: String) -> String:
	var civilization_id := 13
	for player_value in match_definition.get("players", []):
		var player: Dictionary = player_value
		if int(player.get("team", 0)) == observer_team:
			civilization_id = int(player.get("civilization_id", civilization_id))
			break
	var objects: Dictionary = object_catalog.get("objects", {})
	var record: Dictionary = objects.get("%d:%d" % [civilization_id, source_unit_id], objects.get("0:%d" % source_unit_id, {}))
	var name_id := int(record.get("language", {}).get("name_id", -1))
	if localization != null and name_id >= 0:
		var translated := String(localization.text(name_id, locale))
		if not translated.begins_with("["):
			return translated
	return "объект %d" % source_unit_id if locale == "ru" else "object %d" % source_unit_id
