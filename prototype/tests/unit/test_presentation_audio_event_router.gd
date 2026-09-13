extends SceneTree

const AudioEventRouter := preload("res://scripts/presentation_audio_event_router.gd")
const AudioRouter := preload("res://scripts/presentation_audio_router.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var audio = AudioRouter.new()
	audio.configure(catalog.runtime_catalog_data, catalog.sound_catalog_data, catalog.asset_records, catalog.graphics_catalog_data, catalog.object_catalog_data)
	var event_router = AudioEventRouter.new()
	event_router.configure(audio)
	var entities := {
		1: entity(1, "priest", 125),
		2: entity(2, "clubman", 73),
		3: entity(3, "barracks", 12),
	}
	var resolver := func(entity_id: int): return entities.get(entity_id, {})

	var conversion := event_router.consume([event("conversion_chant", {"converter_id": 1}, 10)], resolver)
	assert_equal(conversion.size(), 1, "visible conversion event produces one sound request")
	assert_equal(conversion[0].get("sound_id"), 159, "conversion event uses original chant sound")
	audio.reset()
	var healing := event_router.consume([event("healing_started", {"healer_id": 1}, 11)], resolver)
	assert_equal(healing[0].get("sound_id"), 160, "healing event uses original heal sound")
	audio.reset()
	var attack := event_router.consume([event("attack", {"attacker_id": 2}, 12)], resolver)
	assert_true(not attack.is_empty() and int(attack[0].get("sound_id", -1)) >= 0, "attack release frame uses original graphic sound")
	audio.reset()
	var completed := event_router.consume([event("build_complete", {"building_id": 3}, 13)], resolver)
	assert_equal(completed[0].get("sound_id"), 15, "building completion uses source construction binding")
	audio.reset()
	var produced := event_router.consume([event("unit_produced", {"entity_id": 2}, 14)], resolver)
	assert_equal(produced[0].get("sound_id"), 128, "unit completion uses source train binding")
	audio.reset()
	var impact := event_router.consume([event("projectile_impact", {"position": Vector2(5, 5), "impact_effect_graphic_id": 270}, 15)], resolver, Callable(), func(_payload): return true)
	assert_equal(impact.size(), 1, "visible projectile impact creates one direct graphic sound request")
	assert_equal(impact[0].get("sound_id"), 70, "projectile impact uses source graphic sound 70")
	audio.reset()
	assert_true(event_router.consume([event("projectile_impact", {"position": Vector2(5, 5), "impact_effect_graphic_id": 270}, 16)], resolver, Callable(), func(_payload): return false).is_empty(), "hidden impact cannot leak through audio")
	assert_true(event_router.consume([event("death", {"entity_id": 999}, 17)], resolver).is_empty(), "unseen entity cannot leak through audio")

	if failures.is_empty():
		print("I12-018 presentation audio event router tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func entity(entity_id: int, kind: String, source_unit_id: int) -> Dictionary:
	return {"id": entity_id, "kind": kind, "source_unit_id": source_unit_id, "facing": 0, "components": {"ownership": {"civilization_id": 13}}}


func event(type: String, payload: Dictionary, sequence_id: int) -> Dictionary:
	return {"type": type, "payload": payload, "sequence_id": sequence_id}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
