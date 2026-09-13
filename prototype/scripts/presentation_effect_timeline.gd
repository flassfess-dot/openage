class_name RoRPresentationEffectTimeline
extends RefCounted

var effect_registry
var effects: Array[Dictionary] = []


func configure(registry) -> void:
	effect_registry = registry
	reset()


func reset() -> void:
	effects.clear()


func consume(events: Array, visibility_resolver: Callable = Callable()) -> void:
	if effect_registry == null:
		return
	for event_value in events:
		var event: Dictionary = event_value
		if String(event.get("type", "")) != "projectile_impact":
			continue
		var payload: Dictionary = event.get("payload", {})
		var graphic_id := int(payload.get("impact_effect_graphic_id", -1))
		if graphic_id < 0:
			continue
		var position := _position(payload.get("position", Vector2.ZERO))
		if visibility_resolver.is_valid() and not bool(visibility_resolver.call(position)):
			continue
		effects.append({
			"id": int(payload.get("projectile_id", event.get("sequence_id", effects.size() + 1))),
			"graphic_id": graphic_id,
			"team": int(payload.get("team", 0)),
			"pos": position,
			"elapsed": 0.0,
			"duration": effect_registry.duration(graphic_id),
			"active": true,
		})


func advance(delta: float) -> void:
	var survivors: Array[Dictionary] = []
	for effect_value in effects:
		var effect: Dictionary = effect_value
		effect["elapsed"] = float(effect.get("elapsed", 0.0)) + maxf(0.0, delta)
		if float(effect["elapsed"]) + 0.000001 < float(effect.get("duration", 0.0)):
			survivors.append(effect)
	effects = survivors


func snapshot() -> Array:
	return effects.duplicate(true)


func _position(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
