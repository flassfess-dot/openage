class_name RoRAiObservationProfile
extends RefCounted
const Rules := preload("res://scripts/combat_rules.gd")


static func from_record(source: Dictionary, entity: Dictionary = {}) -> Dictionary:
	var combat: Dictionary = source.get("combat", {})
	var live: Dictionary = entity.get("components", {}).get("combat", {})
	return {
		"attacks": live.get("attacks", combat.get("attacks", [])).duplicate(true),
		"armors": live.get("armors", combat.get("armors", [])).duplicate(true),
		"base_armor": float(live.get("base_armor", combat.get("base_armor", 0.0))),
		"damage": float(entity.get("attack_damage", Rules.primary_attack_damage(combat.get("attacks", []), 1.0))),
		"period": float(entity.get("attack_period", combat.get("attack_period", 2.0))),
		"range": float(entity.get("attack_range", combat.get("range_max", 0.0))),
		"speed": float(entity.get("speed", source.get("speed", 0.0))),
		"max_hp": float(entity.get("max_hp", source.get("health", 1.0))),
		"enabled": bool(entity.get("combat_enabled", not combat.get("attacks", []).is_empty())),
		"transport": bool(entity.get("components", {}).get("cargo", {}).get("enabled", false))
	}


static func actor(world, row: Dictionary, team: int) -> Dictionary:
	var source: Dictionary = world.object_record_by_id(int(row.get("source_unit_id", -1)), int(row.get("team", 0)))
	# Enemy definitions are public estimates. Never look up a live foreign actor.
	if int(row.get("team", 0)) != team:
		return from_record(source, row)
	var live: Variant = (
		world.find_building(int(row.get("id", -1)))
		if String(row.get("entity_type", "")) == "building"
		else world.find_unit(int(row.get("id", -1)))
	)
	var data := from_record(source, live if live is Dictionary else row)
	if live is Dictionary:
		data["carried_amount"] = float(live.get("carried_amount", 0.0))
		data["carried_resource_type_id"] = int(live.get("carried_resource_type_id", -1))
		data["gather_stage"] = String(live.get("gather_stage", ""))
	return data


static func decorate_options(world, options: Dictionary, team: int, units: Array, generation_cache: Variant = null) -> Dictionary:
	var result := options.duplicate(true)
	# This cache belongs to one pinned observer generation, never to live team
	# state. All producers use the same researched rules and owned army counts.
	var retained: Dictionary = generation_cache if generation_cache is Dictionary else {}
	if not retained.has("train"): retained["train"] = {}
	if not retained.has("research"): retained["research"] = {}
	if not result.get("train", []).is_empty() and not retained.has("effects"):
		retained["effects"] = world.technology_system.persistent_entity_effects(team)
	for option in result.get("train", []):
		var source_id := int(option.get("source_unit_id", -1))
		var profile_key := "%d:%s:%s" % [source_id, String(option.get("kind", "")), str("transport" in option.get("behavior_tags", []))]
		if retained["train"].has(profile_key):
			var previous: Dictionary = retained["train"][profile_key]
			option["ai_profile"] = previous["profile"].duplicate(true)
			option["population_points_cost"] = previous["population"]
			continue
		var source: Dictionary = world.object_record_by_id(source_id, team)
		if source.is_empty():
			source = world.object_record_for(String(option.get("kind", "")), team)
		var data: Dictionary = from_record(source)
		var probe := {"source_unit_id": int(source.get("unit_id", source_id)), "team": team}
		# Apply the owner's already researched public modifiers to a detached
		# estimate using the same pure operators as authoritative combat.
		for effect in retained["effects"]:
			if not world.technology_effect_matches_entity(probe, effect):
				continue
			var raw := int(effect.get("type_id", -1))
			var operator := raw % 10 if raw >= 10 and raw < 30 else raw
			var value := float(effect.get("attr_d", 0.0))
			match int(effect.get("attr_c", -1)):
				0:
					data["max_hp"] = maxf(1.0, world.apply_effect_operator(float(data["max_hp"]), operator, value))
				5:
					data["speed"] = maxf(0.0, world.apply_effect_operator(float(data["speed"]), operator, value))
				8:
					world.modify_combat_class_value(data["armors"], operator, value)
				9:
					world.modify_combat_class_value(data["attacks"], operator, value)
				10:
					data["period"] = maxf(0.1, world.apply_effect_operator(float(data["period"]), operator, value))
				12:
					data["range"] = maxf(0.0, world.apply_effect_operator(float(data["range"]), operator, value))
				15:
					data["base_armor"] = world.apply_effect_operator(float(data["base_armor"]), operator, value)
		data["damage"] = Rules.primary_attack_damage(data["attacks"], float(data["damage"]))
		data["transport"] = "transport" in option.get("behavior_tags", [])
		option["ai_profile"] = data
		option["population_points_cost"] = world.unit_population_points_cost(String(option.get("kind", "")), team)
		if retained["train"].size() < 256:
			retained["train"][profile_key] = {"profile": data.duplicate(true), "population": option["population_points_cost"]}
	if not retained.has("counts"):
		var owned_counts := {}
		for unit in units:
			if int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0:
				var id := int(unit.get("source_unit_id", -1))
				owned_counts[id] = int(owned_counts.get(id, 0)) + 1
		var owned_ids: Array = owned_counts.keys()
		owned_ids.sort()
		retained["counts"] = owned_counts
		retained["ids"] = owned_ids
	var counts: Dictionary = retained["counts"]
	var ids: Array = retained["ids"]
	for option in result.get("research", []):
		var technology_id := int(option.get("technology_id", -1))
		if retained["research"].has(technology_id):
			var previous: Array = retained["research"][technology_id]
			option["ai_relevance"] = previous[0]
			option["ai_economic"] = previous[1]
			continue
		var relevance := 0.0
		var economic := false
		for effect in world.technology_system.effect_commands(int(option.get("technology_id", -1))):
			var raw := int(effect.get("type_id", -1))
			var type_id := raw % 10 if raw >= 10 and raw < 30 else raw
			var attribute := int(effect.get("attr_c", -1))
			for id in ids:
				var probe := {"source_unit_id": int(id), "team": team}
				var matches: bool = (
					world.technology_effect_matches_entity(probe, effect)
					if type_id in [0, 4, 5]
					else (type_id == 3 and int(effect.get("attr_a", -1)) == int(id))
				)
				if not matches or (type_id != 3 and attribute not in [0, 5, 8, 9, 10, 12, 13, 14, 15]):
					continue
				var magnitude := absf(float(effect.get("attr_d", 0.0)))
				if type_id == 5:
					magnitude = absf(magnitude - 1.0) * 10.0
				relevance += float(counts[id]) * clampf(magnitude, 0.25, 3.0)
				if attribute in [13, 14]:
					economic = true
		option["ai_relevance"] = relevance
		option["ai_economic"] = economic
		if retained["research"].size() < 512: retained["research"][technology_id] = [relevance, economic]
	return result
