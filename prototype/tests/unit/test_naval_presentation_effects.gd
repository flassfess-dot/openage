extends SceneTree

const EffectTimeline := preload("res://scripts/presentation_effect_timeline.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_source_damage_thresholds(catalog)
	verify_impact_lifecycle(catalog)
	if failures.is_empty():
		print("I12-019F naval presentation effects tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_source_damage_thresholds(catalog) -> void:
	var scout := ship("scout_ship", 19, 1, 49.0, 100.0)
	var light: Dictionary = catalog.unit_frame_info(scout, "idle")
	assert_equal(light.get("damage_graphic_id"), 326, "Scout Ship uses DAT 50% damage graphic")
	assert_true(has_effect(light, 326), "Scout Ship draws imported light fire overlay")
	scout["hp"] = 24.0
	var heavy: Dictionary = catalog.unit_frame_info(scout, "attack")
	assert_equal(heavy.get("damage_graphic_id"), 327, "Scout Ship advances to DAT 75% damage graphic")
	assert_true(has_effect(heavy, 327), "Scout Ship draws imported medium fire overlay")

	var trireme := ship("scout_ship", 21, 2, 19.0, 100.0)
	var trireme_info: Dictionary = catalog.unit_frame_info(trireme, "idle")
	assert_equal(trireme_info.get("damage_graphic_id"), 329, "Trireme uses its DAT 80% large-fire graphic")
	assert_true(has_effect(trireme_info, 329), "enemy Trireme composes source fire with player-two hull layers")

	var juggernaught := ship("catapult_trireme", 277, 2, 19.0, 100.0)
	var juggernaught_info: Dictionary = catalog.unit_frame_info(juggernaught, "idle")
	assert_equal(juggernaught_info.get("damage_graphic_id"), 330, "Juggernaught uses its distinct DAT 80% damage graphic")
	assert_true(has_effect(juggernaught_info, 330), "neutral fire asset safely falls back while hull keeps enemy palette")
	var death_info: Dictionary = catalog.unit_frame_info(juggernaught, "death")
	assert_equal(death_info.get("damage_graphic_id"), -1, "death clip replaces rather than stacks the persistent damage overlay")
	assert_true(not death_info.get("composite_parts", []).any(func(part): return String(part.get("effect_kind", "")) == "damage"), "death clip contains no live damage overlay")


func verify_impact_lifecycle(catalog) -> void:
	assert_true(catalog.effect_presentations.has_graphic(270, 1), "original catapult impact graphic 270 is imported")
	assert_true(catalog.effect_presentations.has_graphic(270, 2), "neutral impact graphic is available for both teams")
	var timeline = EffectTimeline.new()
	timeline.configure(catalog.effect_presentations)
	var impact := {"type": "projectile_impact", "sequence_id": 80, "payload": {"projectile_id": 44, "team": 2, "position": Vector2(6.5, 7.5), "impact_effect_graphic_id": 270}}
	timeline.consume([impact], func(_position): return false)
	assert_equal(timeline.snapshot().size(), 0, "hidden impact does not leak through fog of war")
	timeline.consume([impact], func(_position): return true)
	assert_equal(timeline.snapshot().size(), 1, "visible impact creates one presentation-only effect")
	var effect: Dictionary = timeline.snapshot()[0]
	var frame: Dictionary = catalog.effect_frame_info(effect)
	assert_equal(frame.get("asset_name"), "graphic_270_p1", "impact resolves the exact source SLP through generic graphic identity")
	assert_true(frame.get("texture") != null, "impact frame is loadable")
	var renderer = RenderWorld.new()
	var world_snapshot := {"units": [], "resources": [], "buildings": [], "projectiles": [], "effects": timeline.snapshot()}
	var drawables: Array = renderer.create_world_drawables(world_snapshot, func(position): return position, 1.0, func(kind, data): return catalog.effect_frame_info(data) if kind == "effect" else {})
	var effect_items := drawables.filter(func(item): return String(item.get("kind", "")) == "effect")
	assert_equal(effect_items.size(), 1, "active impact enters the render queue")
	if not effect_items.is_empty():
		assert_equal(effect_items[0].get("layer"), RenderItem.Layer.PROJECTILE_EFFECT, "impact uses the projectile/effect layer")
	timeline.advance(catalog.effect_presentations.duration(270) + 0.01)
	assert_equal(timeline.snapshot().size(), 0, "impact expires after the source animation duration")


func ship(kind: String, source_unit_id: int, team: int, hp: float, max_hp: float) -> Dictionary:
	return {
		"id": source_unit_id,
		"kind": kind,
		"source_unit_id": source_unit_id,
		"team": team,
		"facing": 3,
		"anim": 0.16,
		"hp": hp,
		"max_hp": max_hp,
		"components": {"ownership": {"civilization_id": 13}},
	}


func has_effect(info: Dictionary, graphic_id: int) -> bool:
	return info.get("composite_parts", []).any(func(part): return int(part.get("graphic_id", -1)) == graphic_id and String(part.get("effect_kind", "")) == "damage" and part.get("texture") != null)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
