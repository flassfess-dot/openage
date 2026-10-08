extends SceneTree
const Contract := preload("res://scripts/entity_read_contract.gd")
const Cache := preload("res://scripts/render_entity_projection_cache.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var cache := Cache.new()
	var live := {"id": 7, "entity_type": "resource", "pos": Vector2(5.5, 5.5), "amount": 100, "resource_type_id": 1, "path": [Vector2.ZERO]}
	var memory := cache.project(live)
	check(Contract.is_render_record(memory) and not memory.has("path"), "resource memory is a compact readonly render record")
	check(is_same(cache.project(memory), memory) and is_same(Contract.render(memory), memory), "reusing memory retains its exact record rather than rebuilding the schema")
	live["amount"] = 50
	var updated := cache.project(live)
	check(memory["amount"] == 100 and updated["amount"] == 50 and not is_same(memory, updated), "live updates replace records without changing remembered facts")
	check(is_same(cache.project(memory), memory) and is_same(cache.project(live), updated), "projecting old fog memory does not overwrite the live entity cache")
	var forged := {Contract.RENDER_SCHEMA_KEY: Contract.SCHEMA_VERSION, "object": RefCounted.new()}
	forged.make_read_only()
	check(not Data.is_detached(forged), "render schema never bypasses worker object isolation")
	var world := World.new(Vector2i(20, 20))
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(5.5, 5.5), false)
	worker["components"]["vision"] = {"range": 6.0, "enabled": true}
	var tree: Dictionary = world.add_resource("tree", Vector2(6.5, 5.5), 75)
	world.update_fog_of_war()
	var options := {"compact_render_entities": true, "borrow_visible_render_entities": true, "include_overview": false}
	var first := Snapshot.presentation(world, 1, 1, options)
	var second := Snapshot.presentation(world, 2, 1, options)
	check(first["resources"].size() == 1 and is_same(first["resources"][0], second["resources"][0]), "unchanged presentation ticks share already projected resources")
	var known: Array = world.get_known_resources(1)
	check(not known.is_empty() and is_same(known[0], second["resources"][0]), "resource fog memory and render publication share one immutable record")
	tree["amount"] = 25
	world.mark_known_resource_dirty(tree)
	var third := Snapshot.presentation(world, 3, 1, options)
	check(first["resources"][0]["amount"] == 75 and third["resources"][0]["amount"] == 25, "dirty resource replaces only its new publication")
	check(world.get_known_resources(2).is_empty(), "other observers cannot borrow unexplored resource records")
	world.task_coordinator.shutdown()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
