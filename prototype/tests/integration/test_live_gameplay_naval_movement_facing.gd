extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ReadContract := preload("res://scripts/entity_read_contract.gd")
const Animation := preload("res://scripts/animation_controller.gd")
const DIRECTIONS := [Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0)]
const BLOCKS_8 := [0, 1, 2, 3, 4, 3, 2, 1]
const BLOCKS_16 := [0, 2, 4, 6, 8, 6, 4, 2]
var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	for source_id in [19, 20, 21, 250, 277]:
		for team in [1, 2]:
			verify_movement_and_attack(catalog, source_id, team)
	finish()

func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(28, 28))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain_ids: Array[int] = []
	terrain_ids.resize(28 * 28)
	terrain_ids.fill(1)
	var vertex_levels: Array[int] = []
	vertex_levels.resize(29 * 29)
	vertex_levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain_ids, "vertex_levels": vertex_levels})
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	return world

func verify_movement_and_attack(catalog, source_id: int, team: int) -> void:
	var world = configured_world(catalog)
	var kind := "scout_ship" if source_id in [19, 20, 21] else "catapult_trireme"
	var ship: Dictionary = world.add_unit(team, kind, Vector2(14.5, 14.5), false)
	world.apply_unit_upgrade_to_entity(ship, source_id)
	world.set_entity_field(ship, "stance", "passive")
	check(ship.get("movement_domain") == "water", "test uses actual ship water navigation")
	# Successive commands exercise turns and reversals without manually setting
	# facing, including the north/east sectors which used to select west frames.
	for facing in range(8):
		var target := Vector2(ship["pos"]) + DIRECTIONS[facing].normalized() * 4.0
		world.assign_command_move([ship], target)
		var movement_samples := 0
		for _step in range(12):
			var origin := Vector2(ship["pos"])
			world.advance(0.05, 1, 2)
			var displacement := Vector2(ship["pos"]) - origin
			if displacement.length_squared() <= 0.000001: continue
			movement_samples += 1
			var actual_facing: int = world.facing_for_vector(displacement)
			check(int(ship["facing"]) == actual_facing, "movement facing follows actual displacement")
			check(actual_facing == facing, "open-water route preserves requested direction")
			var render_record: Dictionary = ReadContract.render(ship)
			check(render_record.is_read_only(), "render consumes an immutable simulation projection")
			verify_presentation(catalog, render_record, Animation.clip_for_state(String(ship["anim_state"])), actual_facing, source_id, "moving")
		check(movement_samples > 0, "ship %d moves after direction %d command" % [source_id, facing])
	world.halt_unit(ship)
	verify_presentation(catalog, ReadContract.render(ship), "idle", int(ship["facing"]), source_id, "stopped")
	# Combat and subsequent sailing use the same compass conversion, rather
	# than retaining either the attack frame direction or a previous move.
	var enemy: Dictionary = world.add_unit(3 - team, "scout_ship", Vector2(ship["pos"]) + Vector2(-1.5, -1.5), false)
	world.set_entity_field(enemy, "stance", "passive")
	world.update_fog_of_war()
	world.assign_command_attack([ship], int(enemy["id"]))
	world.advance(0.05, 1, 2)
	var attack_facing: int = world.facing_for_vector(Vector2(enemy["pos"]) - Vector2(ship["pos"]))
	check(int(ship["facing"]) == attack_facing, "ship faces its combat target")
	verify_presentation(catalog, ReadContract.render(ship), "attack", attack_facing, source_id, "attacking")
	world.assign_command_move([ship], Vector2(ship["pos"]) + Vector2(2, -2))
	var before := Vector2(ship["pos"])
	world.advance(0.05, 1, 2)
	var after_displacement := Vector2(ship["pos"]) - before
	check(after_displacement.length_squared() > 0.000001, "ship resumes sailing after attack")
	if after_displacement.length_squared() > 0.000001:
		verify_presentation(catalog, ReadContract.render(ship), "move", world.facing_for_vector(after_displacement), source_id, "moving after attack")

func verify_presentation(catalog, unit: Dictionary, state: String, facing: int, source_id: int, phase: String) -> void:
	var info: Dictionary = catalog.unit_frame_info(unit, state)
	var context := "ship %d %s compass %d" % [source_id, phase, facing]
	check(not info.is_empty(), context + " resolves frame")
	if info.is_empty(): return
	var expected: int = BLOCKS_16[facing] if source_id in [21, 250, 277] else BLOCKS_8[facing]
	var layers: Array = [info]
	layers.append_array(info.get("composite_parts", []))
	for layer in layers:
		check(int(layer.get("source_direction", -1)) == expected, context + " bow/sail/weapon source agrees with actual heading")
		check(bool(layer.get("mirrored", false)) == (facing > 4), context + " eastward sailing mirrors all parts")
		check(int(layer.get("direction_degrees", -1)) == facing * 45, context + " all parts keep compass orientation")

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)

func finish() -> void:
	if failures.is_empty():
		print("Live gameplay naval movement and combat facing passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)
