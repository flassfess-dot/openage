class_name RoRContextResolver


static func resolve(selected_units: Array, clicked_entity: Variant, ground_target: Vector2, player_team: int) -> Dictionary:
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
	if clicked_entity is Dictionary:
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
				if int(clicked_entity.get("team", player_team)) != player_team:
					if only_converters:
						return {"type": "convert", "target_id": int(clicked_entity["id"])}
					return {"type": "attack", "target_id": int(clicked_entity["id"])}
				if only_healers and float(clicked_entity.get("hp", 0.0)) > 0.0 and float(clicked_entity.get("hp", 0.0)) < float(clicked_entity.get("max_hp", 0.0)):
					return {"type": "heal", "target_id": int(clicked_entity["id"])}
				if bool(clicked_entity.get("components", {}).get("cargo", {}).get("enabled", false)) and not selected_units.is_empty():
					return {"type": "board", "target_id": int(clicked_entity["id"])}
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
						"building_type": String(clicked_entity.get("building_type", "")),
						"target": clicked_entity.get("pos", ground_target),
					}
			"building":
				if int(clicked_entity.get("team", player_team)) != player_team:
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
				if has_worker and has_carrier:
					return {"type": "return_resources", "target_id": int(clicked_entity["id"])}
				if has_worker and int(clicked_entity.get("team", -1)) == player_team and float(clicked_entity.get("hp", 0.0)) < float(clicked_entity.get("max_hp", 0.0)):
					return {"type": "repair", "target_id": int(clicked_entity["id"])}
				return {"type": "unsupported", "reason": "no_context_action", "message": "Для этого здания нет доступной контекстной команды"}
	return {"type": "move", "target": ground_target}


static func _is_trade_dock_for(trader: Dictionary, building: Dictionary) -> bool:
	var source_id := int(trader.get("components", {}).get("trade", {}).get("target_building_source_id", -1))
	return source_id >= 0 and building.get("unit_lineage", []).any(func(value): return int(value) == source_id)
