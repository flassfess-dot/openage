extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_lazy_loading(catalog)
	verify_default_and_enemy(catalog)
	verify_axeman_upgrade(catalog)
	verify_naval_composites(catalog)
	if failures.is_empty():
		print("I12-003 unit presentation variants tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_lazy_loading(catalog) -> void:
	assert_equal(catalog.unit_presentations.textures.size(), 0, "catalog startup does not decode every unit frame")
	assert_true(catalog.has_unit_presentation("swordsman"), "unloaded line remains discoverable")


func verify_default_and_enemy(catalog) -> void:
	var clubman := unit_stub(73, 1)
	var enemy := unit_stub(73, 2)
	assert_equal(catalog.unit_frame_info(clubman, "idle").get("asset_name"), "clubman_idle", "player unit resolves default presentation")
	assert_equal(catalog.unit_frame_info(enemy, "idle").get("asset_name"), "enemy_clubman_idle", "enemy unit resolves recolored presentation")
	assert_true(catalog.unit_presentations.has_unit("villager"), "registry discovers unit types from runtime catalog")


func verify_axeman_upgrade(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_resource_amount(1, 0, 1000)
	var barracks: Dictionary = world.add_building(900, "barracks", Vector2(12.0, 12.0), 1)
	var existing: Dictionary = world.add_unit(1, "clubman", Vector2(8.0, 8.0), false)
	world.apply_technology_commands(1, world.technology_system.complete_research(1, 101))
	var order: Variant = world.enqueue_research(int(barracks["id"]), 1, 63)
	assert_true(order != null, "Battle Axe enters normal research queue")
	world.update_production(41.0)
	assert_equal(existing.get("source_unit_id"), 74, "completed upgrade changes existing line member source")
	assert_equal(catalog.unit_frame_info(existing, "idle").get("asset_name"), "axeman_idle", "upgraded member uses source-specific idle")
	assert_equal(catalog.unit_frame_info(existing, "attack").get("asset_name"), "axeman_attack", "upgraded member uses source-specific attack")
	var future: Dictionary = world.add_unit(1, "clubman", Vector2(9.0, 8.0), false)
	assert_equal(future.get("source_unit_id"), 74, "persistent upgrade applies to future line members")
	var enemy_axeman := unit_stub(74, 2)
	assert_equal(catalog.unit_frame_info(enemy_axeman, "death").get("asset_name"), "enemy_axeman_death", "upgraded enemy uses recolored death sequence")


func verify_naval_composites(catalog) -> void:
	var transport := {"kind": "transport", "source_unit_id": 17, "team": 1, "facing": 0, "anim": 0.0}
	var transport_info: Dictionary = catalog.unit_frame_info(transport, "idle")
	assert_equal(transport_info.get("asset_name"), "transport_hull", "Transport base layer resolves source hull")
	assert_equal(transport_info.get("composite_parts", []).size(), 1, "Transport adds one source composite layer")
	if not transport_info.get("composite_parts", []).is_empty():
		assert_equal(transport_info["composite_parts"][0].get("asset_name"), "transport_sail", "Transport composite resolves source sail")
		assert_true(transport_info["composite_parts"][0].get("texture") != null, "Transport sail texture is loadable")
	var trireme := {"kind": "scout_ship", "source_unit_id": 21, "team": 1, "facing": 7, "anim": 0.2}
	var trireme_info: Dictionary = catalog.unit_frame_info(trireme, "attack")
	assert_equal(trireme_info.get("asset_name"), "trireme_hull", "Trireme resolves source hull variant")
	assert_equal(trireme_info.get("composite_parts", []).map(func(part): return String(part.get("asset_name", ""))), ["trireme_oars", "heavy_transport_sail"], "Trireme composes oars and sail in source order")
	var enemy := {"kind": "catapult_trireme", "source_unit_id": 277, "team": 2, "facing": 4, "anim": 0.1}
	var enemy_info: Dictionary = catalog.unit_frame_info(enemy, "idle")
	assert_equal(enemy_info.get("asset_name"), "enemy_trireme_hull", "enemy naval base layer uses player-two palette")
	assert_equal(enemy_info.get("composite_parts", []).map(func(part): return String(part.get("asset_name", ""))), ["enemy_catapult_trireme_weapon", "enemy_heavy_transport_sail"], "enemy naval composite layers use player-two palette")


func unit_stub(source_unit_id: int, team: int) -> Dictionary:
	return {"kind": "clubman", "source_unit_id": source_unit_id, "team": team, "facing": 0, "anim": 0.0}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
