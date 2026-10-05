extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Publication := preload("res://scripts/presentation_publication.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var catalog := Catalog.new()
	catalog.load()
	catalog.enable_environment_pack()
	var world := World.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var building := world.add_building(9000, "barracks", Vector2(14.5, 14.5), 1, false)
	var tree := world.add_resource("tree", Vector2(18.5, 18.5), 100)
	tree["environment_asset"] = "pine"
	tree["environment_variant"] = 2
	tree["tree_condition"] = "healthy"
	world.mark_known_resource_dirty(tree)
	var coordinator := Coordinator.new()
	coordinator.subsystem_enabled["presentation"] = true
	var publication := Publication.new()
	var previous: Array = []
	for index in range(8):
		building["construction_stage"] = index % 4
		building["construction_progress"] = float(index % 4) / 4.0
		var snapshot := Snapshot.with_queries(world, index, 1, {"compact_render_entities": true, "include_navigation": false, "include_build_sites": false, "borrow_visible_render_entities": true})
		var captured: Dictionary = snapshot["buildings"][0]
		var published := publication.publish(snapshot, [], coordinator)
		var projected: Dictionary = published["buildings"][0]
		check(projected.get("state") == "foundation", "unselected foundations survive real compact snapshot and repeated slot reuse")
		check(projected.get("construction_stage") == index % 4, "construction stages remain live in both publication slots")
		var expected := catalog.building_frame_info(captured)
		var actual := catalog.building_frame_info(projected)
		check(actual.get("asset_name") == expected.get("asset_name") and actual.get("frame_index") == expected.get("frame_index"), "published construction uses original construction graphic and frame")
		check(not actual.has("damage_overlay"), "foundation does not use completed building damage overlay")
		for resource in published["resources"]:
			if int(resource["id"]) != int(tree["id"]): continue
			check(resource.get("environment_asset") == "pine" and resource.get("environment_variant") == 2, "forest species and variant survive actual gameplay snapshot")
			check(resource.get("tree_condition") == "healthy", "tree condition survives gameplay publication")
			check(String(catalog.resource_frame_info(resource).get("asset_name", "")).begins_with("aoe2_temperate:"), "imported trees retain imported artwork")
		previous.append(projected)
		if index > 1: check(previous[0].get("construction_stage") == 0, "reusing publication slots cannot rewrite earlier foundation")
	building["state"] = "complete"
	building["hp"] = building["max_hp"]
	var snapshot := Snapshot.with_queries(world, 9, 1, {"compact_render_entities": true, "include_navigation": false, "include_build_sites": false})
	var published := publication.publish(snapshot, [], coordinator)
	check(published["buildings"][0].get("state") == "complete", "completed building leaves construction art")
	var ghost := {"id": 999, "state": "complete", "health_unknown": true, "location_only": true, "last_known": true, "active": false, "kind": "barracks", "pos": Vector2(20, 20)}
	for index in range(3):
		var result := publication.publish({"tick": index, "units": [], "resources": [], "buildings": [ghost]}, [], coordinator)
		for field in ["health_unknown", "location_only", "last_known", "active"]:
			check(result["buildings"][0].get(field) == ghost[field], "fog/visibility metadata survives publication: " + field)
	coordinator.shutdown()
	world.task_coordinator.shutdown()
	for failure in failures: push_error(failure)
	print("Gameplay presentation contract: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
