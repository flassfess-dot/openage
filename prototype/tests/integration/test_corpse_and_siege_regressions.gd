extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Main := preload("res://main.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const ReadContract := preload("res://scripts/entity_read_contract.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	test_corpses(catalog)
	test_harvestable_decay(catalog)
	test_impact_pipeline(catalog)
	test_forest_blasts(catalog)
	catalog.unit_presentations.shutdown_loading()
	for failure in failures:
		push_error(failure)
	print("Corpse and siege regressions: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func fixture(catalog):
	var world := World.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world

func test_corpses(catalog) -> void:
	var world = fixture(catalog)
	for kind in ["gazelle", "elephant", "alligator", "lion", "clubman", "archer", "villager"]:
		var unit: Dictionary = world.add_unit(1, kind, Vector2(8, 8), false)
		unit["facing"] = 7
		world.begin_entity_death(unit)
		world.advance_death(unit, float(unit["death_duration"]) + 0.01)
		check(unit["death_phase"] == "corpse", "%s enters corpse phase" % kind)
		var state := AnimationController.clip_for_state(unit["anim_state"])
		check(state == "corpse", "Decay resolves the corpse clip outside the main scene too")
		var fresh: Dictionary = catalog.unit_frame_info(ReadContract.render(unit), state)
		var graphic: Dictionary = catalog.graphics_catalog_data["graphics"].get(str(fresh.get("graphic_id", -1)), {})
		var count := maxi(1, int(graphic.get("frames_per_angle", 1)))
		check(not fresh.is_empty() and int(fresh.get("frame_index", -1)) % count == 0, "%s begins at fresh corpse, never idle or random decay" % kind)
		check(String(fresh.get("asset_name", "")).contains("corpse") or String(fresh.get("asset_name", "")).contains("carcass"), "%s uses a corpse asset" % kind)
		check(bool(fresh.get("mirrored", false)), "%s preserves mirrored facing" % kind)
		world.advance_death(unit, float(graphic.get("frame_rate", 10.0)) + 0.01)
		var next: Dictionary = catalog.unit_frame_info(ReadContract.render(unit), state)
		check(int(next.get("frame_index", -1)) == int(fresh.get("frame_index", -1)) + 1, "%s advances exactly one decay stage" % kind)
		world.advance_death(unit, float(unit["corpse_duration"]) * 0.6)
		var late: Dictionary = catalog.unit_frame_info(ReadContract.render(unit), state)
		check(int(late.get("frame_index", -1)) > int(next.get("frame_index", -1)), "%s reaches later stages gradually" % kind)
	world.task_coordinator.shutdown()

func test_harvestable_decay(catalog) -> void:
	var world = fixture(catalog)
	var renderer := RenderWorld.new()
	for kind in ["gazelle", "elephant", "alligator", "lion"]:
		var animal: Dictionary = world.add_unit(0, kind, Vector2(12, 12), false)
		animal["facing"] = 7
		world.begin_entity_death(animal, {"is_worker": true})
		world.advance_death(animal, float(animal["death_duration"]) + 0.01)
		var resource: Dictionary = world.resource_nodes[-1]
		check(resource["facing"] == 7, "%s carcass keeps death direction" % kind)
		var fresh: Dictionary = catalog.resource_frame_info(ReadContract.render(resource))
		check(int(fresh.get("frame_index", -1)) == 4 and bool(fresh.get("mirrored", false)), "%s resource starts at fresh directional frame" % kind)
		var copy := resource.duplicate(true)
		copy["id"] = int(resource["id"]) + 3
		check(catalog.resource_frame_info(copy)["frame_index"] == fresh["frame_index"], "carcass decay does not depend on entity ID")
		var provider := func(_kind, data): return catalog.resource_frame_info(data)
		renderer.create_world_drawables({"resources": [ReadContract.render(resource)]}, func(pos): return pos, 1.0, provider)
		# Food harvesting must not skip the initial animation stages.
		resource["amount"] = maxi(5, int(resource["amount"]) / 2)
		var source: Dictionary = world.object_record_by_id(int(resource["source_unit_id"]), 0)
		var graphic_id := int(source["graphics"]["idle"])
		var seconds := float(catalog.graphics_catalog_data["graphics"][str(graphic_id)]["frame_rate"])
		world.advance_resource_lifecycle(seconds + 0.01)
		var next: Dictionary = catalog.resource_frame_info(ReadContract.render(resource))
		check(int(next.get("frame_index", -1)) == 5, "%s age advances one resource frame" % kind)
		var draws: Array = renderer.create_world_drawables({"resources": [ReadContract.render(resource)]}, func(pos): return pos, 1.0, provider)
		check(not draws.is_empty() and int(draws[0]["frame"]) == 5, "retained resource cache refreshes decay frames")
		# Imported scenario carcasses use the source-graphic renderer instead.
		copy = resource.duplicate(true)
		copy["source_graphic_id"] = graphic_id
		copy["source_graphic_asset_name"] = String(fresh["asset_name"])
		copy["source_frame"] = 19
		check(catalog.source_resource_frame_info(copy)["frame_index"] == 5, "scenario source frame cannot force a late decay stage")
		check(bool(catalog.source_resource_frame_info(copy)["mirrored"]), "scenario carcass also mirrors the original facing")
	var controller := Controller.new(world)
	var saved := Checkpoint.capture(world, controller, {}, {})
	var restored = fixture(catalog)
	var restored_controller := Controller.new(restored)
	check(Checkpoint.restore(saved, restored, restored_controller), "corpse world restores from checkpoint")
	for resource in world.resource_nodes:
		var loaded: Dictionary = restored.resource_nodes_by_id[int(resource["id"])]
		check(loaded["decay_elapsed"] == resource["decay_elapsed"] and loaded["facing"] == resource["facing"], "save retains carcass age and direction")
		check(catalog.resource_frame_info(loaded)["frame_index"] == catalog.resource_frame_info(resource)["frame_index"], "load does not jump to another decay stage")
	world.task_coordinator.shutdown()
	restored.task_coordinator.shutdown()

func launcher(world, kind: String, source_id: int) -> Dictionary:
	var attacker: Dictionary = world.add_building(800, kind, Vector2(4, 4), 1) if kind == "tower" else world.add_unit(1, kind, Vector2(4, 4), false)
	# Materialize the exact source variant, as a loaded upgraded entity would.
	var source: Dictionary = world.object_record_by_id(source_id, 1)
	attacker["source_unit_id"] = source_id
	attacker["projectile_id"] = source["combat"]["projectile_id"]
	attacker["blast_range"] = source["combat"]["blast_range"]
	attacker["components"]["combat"]["blast_range"] = attacker["blast_range"]
	attacker["components"]["combat"]["impact_effect_graphic_id"] = -1
	return attacker

func test_impact_pipeline(catalog) -> void:
	for entry in [["stone_thrower", 35, 272], ["stone_thrower", 36, 272], ["stone_thrower", 280, 272], ["ballista", 11, 272], ["ballista", 279, 272], ["catapult_trireme", 250, 270], ["catapult_trireme", 277, 270], ["tower", 278, 272]]:
		var world = fixture(catalog)
		var attacker := launcher(world, entry[0], entry[1])
		var projectile: Dictionary = world.spawn_projectile(attacker, {"id": -1, "pos": Vector2(8, 8), "elevation": 2.0, "attack_ground": true})
		check(projectile["impact_effect_graphic_id"] == entry[2], "source projectile restores missing impact metadata for %s" % entry[1])
		world.begin_event_capture()
		world.update_projectiles(10.0, 1)
		world.end_event_capture()
		var events: Array = world.drain_domain_events()
		var game := Main.new()
		game.render_world = RenderWorld.new()
		game.resource_catalog = catalog
		game.simulation_world = world
		game.game_controller = Controller.new(world)
		game.presentation_snapshot = {"units": [], "resources": [], "buildings": []}
		game.presentation_effect_timeline.configure(catalog.effect_presentations)
		game.presentation_effect_timeline.consume(events, func(_pos): return true)
		game._sync_effect_snapshot()
		var draws: Array = game.current_world_drawables().filter(func(item): return item["kind"] == "effect")
		check(draws.size() == (2 if entry[2] == 272 else 1), "impact and its source dust enter the main render queue: %s" % entry[1])
		for draw in draws:
			check(draw["frame_info"].get("texture") != null, "impact texture is actually imported")
			check(float(draw["data"].get("elevation", 0)) == 2.0, "impact stays on elevated target ground")
		game.presentation_effect_timeline.advance(0.15)
		game._sync_effect_snapshot()
		draws = game.current_world_drawables().filter(func(item): return item["kind"] == "effect")
		check(not draws.is_empty() and int(draws[0]["frame"]) > 0, "impact animates between simulation publications")
		game.presentation_effect_timeline.advance(2.0)
		game._sync_effect_snapshot()
		check(game.current_world_drawables().is_empty(), "completed impact is removed")
		game.free()
		world.task_coordinator.shutdown()
	check(not catalog.effect_presentations.has_graphic(814), "ordinary arrows retain the original absence of an explosion sprite")

func test_forest_blasts(catalog) -> void:
	for entry in [["stone_thrower", 35, false], ["stone_thrower", 36, false], ["stone_thrower", 280, true], ["catapult_trireme", 250, false], ["catapult_trireme", 277, true], ["ballista", 279, false], ["tower", 278, false]]:
		var world = fixture(catalog)
		var attacker := launcher(world, entry[0], entry[1])
		var tree: Dictionary = world.add_resource("tree", Vector2(12.5, 12.5), 150)
		var nearby: Dictionary = world.add_resource("tree", Vector2(13.5, 12.5), 150)
		var distant: Dictionary = world.add_resource("tree", Vector2(16.5, 12.5), 150)
		var berries: Dictionary = world.add_resource("berry_bush", Vector2(12.5, 13.5), 150)
		var cell := Vector2i(12, 12)
		check(not world.navigation_grid.is_walkable(cell), "standing tree blocks its tile")
		var terrain_before: int = world.terrain_revision
		world.spawn_projectile(attacker, {"id": -1, "pos": Vector2(12.5, 12.5), "elevation": 0.0, "attack_ground": true})
		# In-flight save/load must preserve the source's forest-clearing ability.
		var controller := Controller.new(world)
		var checkpoint := Checkpoint.capture(world, controller, {}, {})
		check(Checkpoint.restore(checkpoint, world, controller), "restore in-flight forest shot")
		tree = world.resource_nodes_by_id[int(tree["id"])]
		nearby = world.resource_nodes_by_id[int(nearby["id"])]
		distant = world.resource_nodes_by_id[int(distant["id"])]
		berries = world.resource_nodes_by_id[int(berries["id"])]
		world.update_projectiles(10.0, 1)
		check((int(tree["amount"]) == 0) == bool(entry[2]), "forest clearing matches original source %s" % entry[1])
		check((int(nearby["amount"]) == 0) == bool(entry[2]), "blast clears nearby trees for %s" % entry[1])
		check(int(distant["amount"]) == 150 and int(berries["amount"]) == 150, "blast leaves distant trees and non-tree resources intact")
		if bool(entry[2]):
			check(tree["tree_phase"] == "stump", "destroyed tree cannot be harvested or stand up again")
			check(world.navigation_grid.is_walkable(cell), "destroying tree opens navigation")
			check(world.terrain_revision > terrain_before, "forest surface invalidates locally")
			world.advance_resource_lifecycle(1.0)
			check(tree["tree_phase"] == "stump", "resource lifecycle preserves destroyed state")
		world.task_coordinator.shutdown()
