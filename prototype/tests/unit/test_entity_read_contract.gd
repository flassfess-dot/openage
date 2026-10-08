extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Components := preload("res://scripts/entity_components.gd")
const Contract := preload("res://scripts/entity_read_contract.gd")
const Store := preload("res://scripts/ai_observation_store.gd")
const Replay := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var world := World.new(Vector2i(20, 20))
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(5.5, 5.5), false)
	check(not worker["components"]["health"].has("current") and not worker["components"]["transform"].has("position"), "live entities have no second mutable owner for health/position")
	var view := Components.view(worker)
	worker["hp"] = 17.0
	check(float(view["health"]["current"]) != 17.0 and float(Components.component_view(worker, "health")["current"]) == 17.0, "component views derive current values and preserve earlier views")
	worker["path"] = [Vector2(8, 8)]
	var movement := Components.component_view(worker, "movement")
	movement["path"][0] = Vector2(19, 19)
	check(worker["path"][0] == Vector2(8, 8), "compatibility views own their nested arrays")
	worker["path"] = []
	var first := world.compact_render_projection(worker)
	check(first.is_read_only() and first["components"].is_read_only(), "retained render contract is enforced by immutable containers")
	check(is_same(first, world.compact_render_projection(worker)), "unchanged entities reuse the same immutable record")
	worker["hp"] = 12.0
	var second := world.compact_render_projection(worker)
	check(not is_same(first, second) and float(first["hp"]) == 17.0 and float(second["hp"]) == 12.0, "updates cannot mutate an earlier published record")
	var schema_building := {"id": 90, "entity_type": "foundation", "state": "foundation", "construction_stage": 1, "construction_progress": 0.25, "environment_variant": 3}
	var building_dto := Contract.render(schema_building)
	check(Contract.category(building_dto) == "building" and not building_dto.has("production_queue"), "explicit type survives compact building projection")
	check(building_dto["construction_stage"] == 1 and building_dto["construction_progress"] == 0.25, "construction fields use one shared contract")
	schema_building.erase("environment_variant")
	var updated := Contract.render(schema_building, building_dto)
	check(not updated.has("environment_variant") and building_dto["environment_variant"] == 3, "removed optional fields cannot remain stale")

	var store := Store.new()
	var options := {"compact_entities": true, "include_projectiles": false, "include_fog_cells": false}
	var knowledge := store.observe(world, 1, 1, options)
	worker["hp"] = 9.0
	var later := store.observe(world, 2, 1, options)
	check(float(knowledge["units"][0]["hp"]) == 12.0 and float(later["units"][0]["hp"]) == 9.0, "retained AI observations never mutate earlier factual rows")

	worker["components"]["vision"] = {"range": 6.0, "enabled": true}
	var tree: Dictionary = world.add_resource("tree", Vector2(6.5, 5.5), 75)
	world.update_fog_of_war()
	var before := Snapshot.presentation(world, 3, 1, {"compact_render_entities": true, "borrow_visible_render_entities": true, "include_overview": true, "borrow_overview_entities": true})
	var remembered: Array = world.get_known_resources(1)
	check(remembered.size() == 1, "visible resource is remembered before the mutation")
	if remembered.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	var memory: Dictionary = remembered[0]
	tree["amount"] = 50
	world.mark_known_resource_dirty(tree)
	var after := Snapshot.presentation(world, 4, 1, {"compact_render_entities": true, "borrow_visible_render_entities": true, "include_overview": true, "borrow_overview_entities": true})
	check(int(memory["amount"]) == 75 and int(before["resources"][0]["amount"]) == 75 and int(after["resources"][0]["amount"]) == 50, "legal resource memory uses replacement rather than mutating historical records")
	check(not is_same(before["overview"]["resources"], world.get_known_resources(1)), "published resource lists own their container")
	var codec := Replay.new()
	var hash_before := codec.world_state_hash(world, 4)
	worker["components"]["health"]["current"] = -123.0
	Components.sync_dynamic(worker)
	check(not worker["components"]["health"].has("current") and codec.world_state_hash(world, 4) == hash_before, "legacy mirror migration preserves canonical simulation state")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
