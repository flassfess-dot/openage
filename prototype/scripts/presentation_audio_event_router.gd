class_name RoRPresentationAudioEventRouter
extends RefCounted

var audio_router


func configure(router) -> void:
	audio_router = router


func consume(events: Array, entity_resolver: Callable, presentation_state_resolver: Callable = Callable(), event_visibility_resolver: Callable = Callable(), source_gain: Callable = Callable()) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if audio_router == null or not entity_resolver.is_valid():
		return results
	for event_value in events:
		var event: Dictionary = event_value
		var payload: Dictionary = event.get("payload", {})
		var event_type := String(event.get("type", ""))
		var binding := _binding(event_type, payload)
		if binding.is_empty():
			continue
		var seed := int(event.get("sequence_id", -1))
		var result: Dictionary
		var mode := String(binding.get("mode", "animation"))
		var entity: Dictionary = {}
		if mode == "graphic":
			if event_visibility_resolver.is_valid() and not bool(event_visibility_resolver.call(payload)):
				continue
		else:
			entity = entity_resolver.call(int(payload.get(String(binding.get("entity_field", "")), -1)))
			if entity.is_empty() or entity.get("last_known", false):
				continue
		var position: Variant = null
		var gain := 1.0
		if binding.get("spatial", false):
			position = payload.get("position", entity.get("pos"))
			if position is Array and position.size() >= 2:
				position = Vector2(float(position[0]), float(position[1]))
			if not position is Vector2:
				continue
			if source_gain.is_valid():
				gain = float(source_gain.call(position))
				# An inaudible battle must not claim a nearby battle's sound cooldown.
				if gain <= 0.0:
					continue
		if mode == "graphic":
			result = audio_router.request_graphic(int(payload.get(String(binding.get("graphic_field", "")), -1)), String(binding.get("name", "effect")), -1, seed)
		elif mode == "event":
			var civilization_id := int(entity.get("components", {}).get("ownership", {}).get("civilization_id", -1))
			result = audio_router.request(String(entity.get("kind", "")), String(binding.get("name", "")), civilization_id, seed)
		elif mode == "animation":
			var state := String(binding.get("name", ""))
			if state == "current" and presentation_state_resolver.is_valid():
				state = String(presentation_state_resolver.call(entity))
			result = audio_router.request_entity_animation(entity, state, seed)
		if bool(result.get("accepted", false)):
			if position is Vector2:
				result["world_position"] = position
				result["gain"] = gain
			result["event_type"] = event_type
			result["entity_id"] = int(entity.get("id", -1)) if not entity.is_empty() else -1
			results.append(result)
	return results


func _binding(event_type: String, _payload: Dictionary) -> Dictionary:
	return {
		"death": {"entity_field": "entity_id", "mode": "animation", "name": "death", "spatial": true},
		"attack": {"entity_field": "attacker_id", "mode": "animation", "name": "attack", "spatial": true},
		"conversion_chant": {"entity_field": "converter_id", "mode": "animation", "name": "convert", "spatial": true},
		"healing_started": {"entity_field": "healer_id", "mode": "animation", "name": "heal", "spatial": true},
		"resource_gathered": {"entity_field": "worker_id", "mode": "animation", "name": "current"},
		"build_complete": {"entity_field": "building_id", "mode": "event", "name": "construction"},
		"unit_produced": {"entity_field": "entity_id", "mode": "event", "name": "train"},
		"projectile_impact": {"mode": "graphic", "graphic_field": "impact_effect_graphic_id", "name": "impact", "spatial": true},
	}.get(event_type, {})
