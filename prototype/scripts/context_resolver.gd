class_name RoRContextResolver


static func resolve(selected_units: Array, clicked_entity: Variant, ground_target: Vector2, player_team: int, allied_teams: Array = []) -> Dictionary:
	if allied_teams.is_empty():
		allied_teams = [player_team]
	var has_worker := selected_units.any(func(unit):
		return bool(unit.get("components", {}).get("worker", {}).get("enabled", false)) or "worker" in unit.get("behavior_tags", []) or (unit.get("behavior_tags", []).is_empty() and String(unit.get("kind", "")) == "villager")
	)
	var has_carrier := selected_units.any(func(unit): return float(unit.get("carried_amount", 0.0)) > 0.0)
	var only_converters := not selected_units.is_empty() and selected_units.all(func(unit):
		return bool(unit.get("components", {}).get("conversion", {}).get("enabled", false)) or "converter" in unit.get("behavior_tags", [])
	)
	var only_healers := not selected_units.is_empty() and selected_units.all(func(unit):
		return bool(unit.get("components", {}).get("healing", {}).get("enabled", false)) or "healer" in unit.get("behavior_tags", [])
	)
	var only_traders := not selected_units.is_empty() and selected_units.all(func(unit):
		return bool(unit.get("components", {}).get("trade", {}).get("enabled", false))
	)
	if not selected_units.is_empty() and selected_units.all(func(entity): return entity.has("production_queue") or String(entity.get("entity_type", "")) == "building"):
		if selected_units.all(func(entity): return not entity.get("command_options", {}).get("train", []).is_empty() and int(entity.get("team", 0)) == player_team and String(entity.get("state", "complete")) == "complete"):
			return {"type": "set_rally_point", "target": ground_target}
		return {"type": "unsupported", "message": "Выберите здание, производящее юнитов"}
	if clicked_entity is Dictionary:
		if bool(clicked_entity.get("last_known", false)):
			return {"type": "move", "target": clicked_entity.get("pos", ground_target)}
		var entity_type := String(clicked_entity.get("entity_type", ""))
		if entity_type.is_empty():
			if clicked_entity.has("production_queue") or clicked_entity.has("footprint"):
				entity_type = "foundation" if String(clicked_entity.get("state", "complete")) == "foundation" else "building"
			elif clicked_entity.has("resource_type_id") and clicked_entity.has("amount"):
				entity_type = "resource"
			elif clicked_entity.has("task") or clicked_entity.has("combat_enabled"):
				entity_type = "unit"
		match entity_type:
			"unit":
				if "capturable" in clicked_entity.get("behavior_tags", []):
					return {"type": "move", "target": clicked_entity.get("pos", ground_target)}
				var unit_team := int(clicked_entity.get("team", player_team))
				var cargo: Dictionary = clicked_entity.get("components", {}).get("cargo", {})
				if unit_team in allied_teams and bool(cargo.get("enabled", false)) and selected_units.any(func(unit): return String(unit.get("movement_domain", "land")) in cargo.get("allowed_domains", ["land"])):
					return {"type": "board", "target_id": int(clicked_entity["id"])}
				if has_worker and unit_team in allied_teams and String(clicked_entity.get("movement_domain", "land")) == "water" and float(clicked_entity.get("hp", 0.0)) > 0.0 and float(clicked_entity.get("hp", 0.0)) < float(clicked_entity.get("max_hp", 0.0)):
					return {"type": "repair", "target_id": int(clicked_entity["id"])}
				if unit_team not in allied_teams:
					if only_converters:
						return {"type": "convert", "target_id": int(clicked_entity["id"])}
					return {"type": "attack", "target_id": int(clicked_entity["id"])}
				if only_healers and float(clicked_entity.get("hp", 0.0)) > 0.0 and float(clicked_entity.get("hp", 0.0)) < float(clicked_entity.get("max_hp", 0.0)):
					return {"type": "heal", "target_id": int(clicked_entity["id"])}
			"resource":
				if has_worker:
					return {"type": "gather", "target_id": int(clicked_entity["id"])}
				return {"type": "unsupported", "reason": "no_worker_selected", "message": "Для сбора ресурса выберите работника"}
			"foundation":
				if int(clicked_entity.get("team", player_team)) != player_team:
					if only_converters:
						return {"type": "convert", "target_id": int(clicked_entity["id"])}
					return {"type": "attack", "target_id": int(clicked_entity["id"])}
				if has_worker:
					return {
						"type": "build",
						"building_type": String(clicked_entity.get("kind", clicked_entity.get("building_type", ""))),
						"target": clicked_entity.get("pos", ground_target),
					}
			"building":
				var building_team := int(clicked_entity.get("team", player_team))
				if building_team not in allied_teams:
					if only_traders and _is_trade_dock_for(selected_units[0], clicked_entity):
						return {"type": "trade", "target_id": int(clicked_entity["id"])}
					if only_converters:
						return {"type": "convert", "target_id": int(clicked_entity["id"])}
					return {"type": "attack", "target_id": int(clicked_entity["id"])}
				if has_worker and bool(clicked_entity.get("harvestable", false)):
					if int(clicked_entity.get("amount", 0)) > 0:
						return {"type": "gather", "target_id": int(clicked_entity["id"])}
					if String(clicked_entity.get("resource_state", "depleted")) == "depleted":
						return {
							"type": "build",
							"building_type": String(clicked_entity.get("kind", "")),
							"target": clicked_entity.get("pos", ground_target),
						}
				if has_worker and has_carrier and building_team == player_team:
					return {"type": "return_resources", "target_id": int(clicked_entity["id"])}
				if has_worker and building_team in allied_teams and float(clicked_entity.get("hp", 0.0)) > 0.0 and float(clicked_entity.get("hp", 0.0)) < float(clicked_entity.get("max_hp", 0.0)) and String(clicked_entity.get("state", "complete")) == "complete":
					return {"type": "repair", "target_id": int(clicked_entity["id"])}
				return {"type": "unsupported", "reason": "no_context_action", "message": "Для этого здания нет доступной контекстной команды"}
	return {"type": "move", "target": ground_target}


static func _is_trade_dock_for(trader: Dictionary, building: Dictionary) -> bool:
	var source_id := int(trader.get("components", {}).get("trade", {}).get("target_building_source_id", -1))
	return source_id >= 0 and building.get("unit_lineage", []).any(func(value): return int(value) == source_id)


static func feedback_marker(resolution: Dictionary, clicked_entity: Variant, ground_target: Vector2) -> Variant:
	if clicked_entity is Dictionary:
		return {"entity_id": int(clicked_entity.get("id", -1))}
	return ground_target if String(resolution.get("type", "")) in ["move", "set_rally_point"] else null
