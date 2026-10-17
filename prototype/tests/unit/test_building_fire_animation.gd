extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	for spec in [[79,826],[199,821]]:
		var tower := {"id":400,"kind":"tower","team":1,"source_unit_id":spec[0],"display_graphic_id":spec[1],"hp":200.0,"max_hp":200.0,"state":"complete","anim_state":"Idle","components":{"ownership":{"civilization_id":13}}}
		var frames: Array[int] = []
		for step in range(20):
			var info: Dictionary = catalog.building_frame_info(tower, float(step) * 0.05)
			var fire: Array = info.get("composite_parts", []).filter(func(part): return int(part.get("graphic_id", -1)) == 324)
			check(fire.size() == 4, "all four source torches remain present")
			if fire.is_empty(): continue
			frames.append(int(fire[0]["frame_index"]))
		check(frames.size() == 20, "one source fire cycle sampled")
		for i in range(1, frames.size()): check(frames[i] != frames[i-1], "fire advances each 50 ms instead of holding for one second")
		var time := 0.374
		var idle: Dictionary = catalog.building_frame_info(tower, time)
		tower["anim_state"] = "AttackWindup"
		tower["anim"] = 0.0
		var attack: Dictionary = catalog.building_frame_info(tower, time)
		var fire_frames := func(info: Dictionary): return info.get("composite_parts", []).filter(func(part): return int(part.get("graphic_id", -1)) == 324).map(func(part): return int(part["frame_index"]))
		check(fire_frames.call(idle) == fire_frames.call(attack), "firing a projectile cannot restart the torches")
		check(not catalog.building_presentations.complete_static_frames.has(["tower",1,spec[0],spec[1],13,-1,0]), "animated tower never enters complete-static cache")
	check(float(catalog.graphics_catalog_data["graphics"]["324"]["frame_rate"]) == 1.0, "raw imported metadata stays unchanged")
	for failure in failures: push_error(failure)
	print("Building continuous fire: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
