extends SceneTree

const AudioEventRouter := preload("res://scripts/presentation_audio_event_router.gd")
const AudioRouter := preload("res://scripts/presentation_audio_router.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const MatchScreen := preload("res://main.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	entities[3]["last_known"] = true
	assert_true(event_router.consume([event("death", {"entity_id": 3}, 18)], resolver).is_empty(), "remembered enemy building cannot reveal its destruction through audio")
	var silent := func(_position: Vector2): return 0.0
	var distant_impact := event("projectile_impact", {"position": [5, 5], "impact_effect_graphic_id": 270}, 19)
	assert_true(event_router.consume([distant_impact], resolver, Callable(), func(_payload): return true, silent).is_empty(), "visible but distant projectile impact is inaudible")
	check_camera_playback(catalog)

	if failures.is_empty():
		print("I12-018 presentation audio event router tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func entity(entity_id: int, kind: String, source_unit_id: int) -> Dictionary:
	return {"id": entity_id, "kind": kind, "pos": Vector2(5, 5), "source_unit_id": source_unit_id, "facing": 0, "components": {"ownership": {"civilization_id": 13}}}


func check_camera_playback(catalog) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 700)
	root.add_child(viewport)
	var game := MatchScreen.new()
	game.prepared_load_bootstrap = true
	viewport.add_child(game)
	game.set_process(false)
	game.resource_catalog = catalog
	game.setup_sfx()
	var center := Vector2(500, (700 + game.hud_top_height() - game.hud_bottom_height()) * 0.5)
	var near := entity(41, "clubman", 73)
	var far := entity(42, "clubman", 73)
	near.pos = game.screen_to_world(center)
	far.pos = game.screen_to_world(center + Vector2(1200, 0))
	game.presentation_snapshot = {"units": [near, far]}
	game.process_world_audio_events([event("attack", {"attacker_id": 42}, 80), event("attack", {"attacker_id": 41}, 81)])
	var player: AudioStreamPlayer = game.sfx_players[0]
	assert_true(player.playing and is_equal_approx(player.volume_db, game.sfx_volume_db), "camera-center attacker plays at full volume")
	assert_equal(game.spatial_sfx_sources.get(player), near.pos, "inaudible attacker cannot consume the nearby attacker's channel or cooldown")
	game.view_offset += Vector2(400, 0)
	game._update_battle_sound_volumes()
	var middle_db := player.volume_db
	game.view_offset += Vector2(150, 0)
	game._update_battle_sound_volumes()
	assert_true(player.playing and player.volume_db < middle_db and middle_db < game.sfx_volume_db, "ongoing combat fades progressively while panning")
	game.match_preferences.values["sound"] = 0.25
	game._apply_audio_preferences()
	assert_true(is_equal_approx(player.volume_db, linear_to_db(0.25 * game.battle_sound_gain(near.pos)) - 3.0), "sound slider scales active battle audio")
	game.view_offset += Vector2(600, 0)
	game._update_battle_sound_volumes()
	assert_true(not player.playing and game.spatial_sfx_sources.is_empty(), "distant combat stops when the camera leaves")
	game.process_world_audio_events([event("unit_produced", {"entity_id": 41}, 82)])
	assert_true(player.playing and is_equal_approx(player.volume_db, game.sfx_volume_db), "production notification uses the configured volume on the reused channel")
	viewport.free()


func event(type: String, payload: Dictionary, sequence_id: int) -> Dictionary:
	return {"type": type, "payload": payload, "sequence_id": sequence_id}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
