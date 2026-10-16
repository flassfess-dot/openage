extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func find(rows: Array, id: int) -> Dictionary:
	for row in rows:
		if int(row["id"]) == id: return row
	return {}
func _initialize() -> void:
	var world := World.new(Vector2i(20, 20))
	var observer: Dictionary = world.add_unit(1, "villager", Vector2(5.5, 5.5), false)
	observer["components"]["vision"] = {"enabled": true, "range": 5.0}
	world.add_building(100, "house", Vector2(4.5, 4.5), 1)
	world.add_building(101, "house", Vector2(6.5, 6.5), 2)
	var own: Dictionary = world.find_building(100)
	var enemy: Dictionary = world.find_building(101)
	world.set_entity_field(enemy, "hp", 73.0)
	world.update_fog_of_war()
	var options := {"compact_render_entities": true, "borrow_visible_render_entities": true, "entity_bounds": Rect2(0, 0, 20, 20), "include_navigation": false}
	var reference := Snapshot.presentation(world, 1, 1, options)
	options["borrow_sampled_building_memory"] = true
	var sampled := Snapshot.presentation(world, 1, 1, options)
	check(reference["buildings"] == sampled["buildings"], "sampled visible building records preserve the ordinary projection")
	world.set_entity_field(own, "hp", 31.0)
	var fresh := Snapshot.presentation(world, 2, 1, options)
	check(find(fresh["buildings"], 100).get("hp") == 31.0, "writes after the sampled boundary use a fresh projection")
	check(find(sampled["buildings"], 100).get("hp") != 31.0, "new observations do not mutate old publications")
	world.set_entity_field(observer, "pos", Vector2(18.5, 18.5))
	own["components"]["vision"]["enabled"] = false
	world.update_fog_of_war()
	world.set_entity_field(enemy, "hp", 1.0)
	var hidden := Snapshot.presentation(world, 3, 1, options)
	check(find(hidden["buildings"], 101).get("hp") == 73.0, "hidden building changes retain the last observed health")
	for failure in failures: push_error(failure)
	print("Sampled building memory: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
