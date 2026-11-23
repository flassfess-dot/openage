class_name RoRInteractionCursor
extends RefCounted

const ContextResolver := preload("res://scripts/context_resolver.gd")


static func resolve(selected_units: Array, hovered_entity: Variant, ground_target: Vector2, player_team: int, allied_teams: Array = []) -> Dictionary:
	var resolution := ContextResolver.resolve(selected_units, hovered_entity, ground_target, player_team, allied_teams)
	if String(resolution.get("type", "")) in ["board", "trade", "repair"]:
		return {"semantic": String(resolution["type"]), "entity_id": int(hovered_entity["id"]), "reason": ""}
	if hovered_entity is Dictionary:
		var entity_type := String(hovered_entity.get("entity_type", ""))
		var team := int(hovered_entity.get("team", 0))
		if team == player_team and entity_type in ["unit", "building", "foundation"]:
			return {"semantic": "select", "entity_id": int(hovered_entity.get("id", -1))}
	if selected_units.is_empty():
		return {"semantic": "default", "entity_id": int(hovered_entity.get("id", -1)) if hovered_entity is Dictionary else -1}
	if hovered_entity is Dictionary and String(hovered_entity.get("entity_type", "")) == "resource":
		if not selected_units.any(ContextResolver.is_worker):
			return {"semantic": "default", "entity_id": -1, "reason": ""}
	return {
		"semantic": String(resolution.get("type", "default")),
		"entity_id": int(hovered_entity.get("id", -1)) if hovered_entity is Dictionary else -1,
		"reason": String(resolution.get("reason", "")),
	}
