class_name RoRInteractionCursor
extends RefCounted

const ContextResolver := preload("res://scripts/context_resolver.gd")


static func resolve(selected_units: Array, hovered_entity: Variant, ground_target: Vector2, player_team: int) -> Dictionary:
	if not selected_units.is_empty():
		var contextual := ContextResolver.resolve(selected_units, hovered_entity, ground_target, player_team)
		if String(contextual.get("type", "")) in ["board", "trade"]:
			return {
				"semantic": String(contextual.get("type", "")),
				"entity_id": int(hovered_entity.get("id", -1)),
				"reason": "",
			}
	if hovered_entity is Dictionary:
		var entity_type := String(hovered_entity.get("entity_type", ""))
		var team := int(hovered_entity.get("team", 0))
		if team == player_team and entity_type in ["unit", "building", "foundation"]:
			return {"semantic": "select", "entity_id": int(hovered_entity.get("id", -1))}
	if selected_units.is_empty():
		return {"semantic": "default", "entity_id": int(hovered_entity.get("id", -1)) if hovered_entity is Dictionary else -1}
	var resolution := ContextResolver.resolve(selected_units, hovered_entity, ground_target, player_team)
	return {
		"semantic": String(resolution.get("type", "default")),
		"entity_id": int(hovered_entity.get("id", -1)) if hovered_entity is Dictionary else -1,
		"reason": String(resolution.get("reason", "")),
	}
