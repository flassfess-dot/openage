extends SceneTree

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_unknown_explored_visible_and_allies()
	test_overlapping_sources_keep_shared_cells_visible()
	test_simulation_and_render_visibility()
	test_gaia_visibility_contract()

	if failures.is_empty():
		print("S-006 fog of war tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_gaia_visibility_contract() -> void:
	var fog = FogOfWar.new(Vector2i(8, 8))
	assert_equal(fog.state_at_world(0, Vector2(2.5, 2.5)), FogOfWar.UNKNOWN, "Gaia fog queries are safe and remain unknown")
	assert_equal(fog.snapshot(0).size(), 0, "Gaia does not allocate a player fog buffer")
	var world = SimulationWorld.new(Vector2i(8, 8))
	assert_true(world.is_entity_visible_to(0, {"team": 1, "pos": Vector2(2.5, 2.5)}), "Gaia perception targets are not rejected by player fog")


func test_unknown_explored_visible_and_allies() -> void:
	var fog = FogOfWar.new(Vector2i(12, 12))
	fog.ensure_player(1)
	var scout := vision_entity(1, Vector2(2.5, 2.5), 2.0)
	var enemy_scout := vision_entity(2, Vector2(1.5, 10.5), 2.0)
	fog.update([scout, enemy_scout], [])
	assert_equal(fog.state_name(fog.state_at_world(1, Vector2(2.5, 2.5))), "visible", "own sight reveals current cells")
	assert_equal(fog.state_name(fog.state_at_world(1, Vector2(11.5, 11.5))), "unknown", "unseen cells remain unknown")
	assert_equal(fog.state_name(fog.state_at_world(1, enemy_scout["pos"])), "unknown", "enemy vision is not shared")

	scout["pos"] = Vector2(7.5, 2.5)
	fog.update([scout, enemy_scout], [])
	assert_equal(fog.state_name(fog.state_at_world(1, Vector2(2.5, 2.5))), "explored", "cells leave visible state but retain exploration")
	assert_equal(fog.state_name(fog.state_at_world(1, Vector2(7.5, 2.5))), "visible", "moving source reveals new cells")

	var ally := vision_entity(3, Vector2(10.5, 8.5), 1.0)
	fog.set_alliance(1, 3, true)
	fog.update([scout, enemy_scout, ally], [])
	assert_equal(fog.state_name(fog.state_at_world(1, ally["pos"])), "visible", "allied vision is shared")
	ally["hp"] = 0.0
	fog.update([scout, enemy_scout, ally], [])
	assert_equal(fog.state_name(fog.state_at_world(1, ally["pos"])), "explored", "destroyed source stops granting vision")
	var snapshot: PackedByteArray = fog.snapshot(1)
	assert_equal(int(snapshot[8 * 12 + 10]), FogOfWar.EXPLORED, "minimap snapshot uses the same exploration grid")


func test_overlapping_sources_keep_shared_cells_visible() -> void:
	var fog = FogOfWar.new(Vector2i(12, 12))
	var first := vision_entity(1, Vector2(4.5, 4.5), 2.0)
	first["id"] = 10
	var second := vision_entity(1, Vector2(5.5, 4.5), 2.0)
	second["id"] = 11
	fog.update([first, second], [])
	first["pos"] = Vector2(9.5, 9.5)
	fog.update([first, second], [])
	assert_equal(fog.state_at_world(1, Vector2(5.5, 4.5)), FogOfWar.VISIBLE, "moving one overlapping source preserves the other source's visibility")
	second["hp"] = 0.0
	fog.update([first, second], [])
	assert_equal(fog.state_at_world(1, Vector2(5.5, 4.5)), FogOfWar.EXPLORED, "last overlapping source removal downgrades the shared cell")


func test_simulation_and_render_visibility() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_gamespec({"units": {"scout": {
		"hit_points": 10.0,
		"speed": 1.0,
		"line_of_sight": 2.0,
		"attack_period": 1.0,
		"range": 0.0,
		"projectile_id": -1,
		"attacks": [{"amount": 1.0}],
	}}})
	var observer: Dictionary = world.add_unit(1, "scout", Vector2(3.5, 3.5), false)
	var enemy: Dictionary = world.add_unit(2, "scout", Vector2(4.5, 3.5), false)
	world.update_fog_of_war()
	assert_true(world.is_entity_visible_to(1, enemy), "enemy inside sight radius is targetable")
	var renderer = RenderWorld.new()
	var visible_items: Array = renderer.create_world_drawables(world, func(position): return position, 1.0, Callable(self, "fake_frame_info"), [], 1)
	assert_equal(visible_items.filter(func(item): return item["kind"] == "unit" and item["stable_id"] == enemy["id"]).size(), 1, "visible enemy enters render queue")

	enemy["pos"] = Vector2(13.5, 13.5)
	world.update_fog_of_war()
	assert_true(not world.is_entity_visible_to(1, enemy), "enemy outside sight is not targetable")
	var hidden_items: Array = renderer.create_world_drawables(world, func(position): return position, 1.0, Callable(self, "fake_frame_info"), [], 1)
	assert_equal(hidden_items.filter(func(item): return item["kind"] == "unit" and item["stable_id"] == enemy["id"]).size(), 0, "hidden enemy is absent from render queue")
	assert_equal(hidden_items.filter(func(item): return item["kind"] == "unit" and item["stable_id"] == observer["id"]).size(), 1, "own unit remains rendered")

	var ally: Dictionary = world.add_unit(3, "scout", Vector2(12.5, 13.5), false)
	world.set_alliance(1, 3, true)
	assert_true(world.is_entity_visible_to(1, enemy), "allied unit reveals distant enemy")
	ally["hp"] = 0.0
	world.update_fog_of_war()
	assert_true(not world.is_entity_visible_to(1, enemy), "dead ally no longer reveals enemy")


func vision_entity(team: int, position: Vector2, sight_radius: float) -> Dictionary:
	return {
		"team": team,
		"pos": position,
		"hp": 10.0,
		"components": {"vision": {"range": sight_radius, "enabled": true}},
	}


func fake_frame_info(_kind: String, _data: Variant) -> Dictionary:
	return {"frame_index": 0, "hotspot": Vector2(8, 20), "mirrored": false}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
