extends SceneTree

const PresentationAudioRouter := preload("res://scripts/presentation_audio_router.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var router = PresentationAudioRouter.new()
	router.configure(catalog.runtime_catalog_data, catalog.sound_catalog_data, catalog.asset_records, catalog.graphics_catalog_data, catalog.object_catalog_data)

	var selection: Dictionary = router.request("villager", "selection", 13, 7)
	assert_true(bool(selection.get("accepted", false)), "villager selection resolves through runtime sound ID")
	assert_equal(selection.get("sound_id"), 47, "original villager selection sound ID is retained")
	assert_true(selection.get("stream") is AudioStream, "resolved original WAV is loadable")
	var throttled: Dictionary = router.request("villager", "selection", 13, 8)
	assert_equal(throttled.get("reason"), "throttled", "repeated voice is throttled by presentation category")
	router.advance(0.2)
	assert_true(bool(router.request("villager", "selection", 13, 8).get("accepted", false)), "voice becomes available after cooldown")

	router.reset()
	var first: Dictionary = router.request("clubman", "command", 13, 22)
	router.reset()
	var second: Dictionary = router.request("clubman", "command", 13, 22)
	assert_equal(first.get("resource_id"), second.get("resource_id"), "weighted variant selection is deterministic for a supplied seed")
	assert_equal(router.request("clubman", "missing", 13).get("reason"), "sound_unavailable", "missing event is explicit and silent")
	router.advance(0.2)
	assert_equal(router.request("clubman", "train", 13, 3).get("sound_id"), 128, "production event uses original unit train sound")

	router.reset()
	var unit_death: Dictionary = router.request_animation("clubman", "death", 13, 31)
	assert_true(bool(unit_death.get("accepted", false)), "unit death resolves sound through the death graphic")
	assert_equal(unit_death.get("sound_id"), 52, "clubman death graphic retains original sound ID")
	assert_equal(unit_death.get("graphic_id"), 171, "clubman death resolves from the civilization presentation")
	router.reset()
	var building_death: Dictionary = router.request_animation("town_center", "death", 13, 32)
	assert_true(bool(building_death.get("accepted", false)), "building death resolves sound through the death graphic")
	assert_equal(building_death.get("sound_id"), 70, "town center death graphic retains original sound ID")

	var priest := {"kind": "priest", "source_unit_id": 125, "facing": 3, "components": {"ownership": {"civilization_id": 13}}}
	router.reset()
	var conversion: Dictionary = router.request_entity_animation(priest, "convert", 41)
	assert_true(bool(conversion.get("accepted", false)), "conversion frame event resolves an imported original sound")
	assert_equal(conversion.get("graphic_id"), 36, "conversion uses DAT action graphic 36")
	assert_equal(conversion.get("sound_id"), 159, "conversion uses graphic event sound 159")
	router.reset()
	var healing: Dictionary = router.request_entity_animation(priest, "heal", 42)
	assert_true(bool(healing.get("accepted", false)), "healing frame event resolves an imported original sound")
	assert_equal(healing.get("graphic_id"), 816, "healing uses DAT action graphic 816")
	assert_equal(healing.get("sound_id"), 160, "healing uses graphic event sound 160")

	var scout_ship := {"kind": "scout_ship", "source_unit_id": 19, "facing": 2, "components": {"ownership": {"civilization_id": 13}}}
	router.reset()
	var scout_attack: Dictionary = router.request_entity_animation(scout_ship, "attack", 43)
	assert_true(bool(scout_attack.get("accepted", false)), "Scout Ship attack resolves an imported original combat sound")
	assert_equal(scout_attack.get("graphic_id"), 793, "composite Scout Ship audio follows its DAT attack wrapper")
	assert_equal(scout_attack.get("sound_id"), 13, "Scout Ship attack retains original sound 13")
	var trireme := {"kind": "scout_ship", "source_unit_id": 21, "facing": 5, "components": {"ownership": {"civilization_id": 13}}}
	router.reset()
	assert_equal(router.request_entity_animation(trireme, "attack", 44).get("sound_id"), 44, "Trireme attack retains original sound 44")
	var catapult_ship := {"kind": "catapult_trireme", "source_unit_id": 250, "facing": 6, "components": {"ownership": {"civilization_id": 13}}}
	router.reset()
	assert_equal(router.request_entity_animation(catapult_ship, "death", 45).get("sound_id"), 35, "Catapult Trireme death retains original ship-death sound")
	router.reset()
	assert_equal(router.request("scout_ship", "selection", 13, 46).get("sound_id"), 190, "warship selection binding is backed by imported WAV")
	router.reset()
	assert_equal(router.request("fishing_boat", "selection", 13, 47).get("sound_id"), 120, "economic ship selection binding is backed by imported WAV")
	router.reset()
	assert_equal(router.request_graphic(270, "impact", 13, 48).get("sound_id"), 70, "naval blast resolves original impact sound")
	router.reset()
	assert_equal(router.request_graphic(326, "damage", 13, 49).get("sound_id"), 72, "ship fire overlay resolves original damage sound")

	for record_value in catalog.asset_records:
		var record: Dictionary = record_value
		if String(record.get("extension", "")) != "wav":
			continue
		assert_true(load("res://assets/generated/%s" % String(record.get("file", ""))) is AudioStream, "imported WAV %s loads in Godot" % record.get("file", ""))

	if failures.is_empty():
		print("I10-004 presentation audio router tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
