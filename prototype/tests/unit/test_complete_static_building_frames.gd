extends SceneTree
const Catalog:=preload("res://scripts/resource_catalog.gd")
var failures:Array[String]=[]
func _initialize()->void:
	var catalog=Catalog.new()
	catalog.load()
	var registry=catalog.building_presentations
	for spec in [["house",70,817],["barracks",12,13],["town_center",109,598],["granary",68,863],["storage_pit",103,515],["archery_range",87,873]]:
		var building:Dictionary={"id":10,"kind":spec[0],"team":1,"source_unit_id":spec[1],"display_graphic_id":spec[2],"hp":600.0,"max_hp":600.0,"state":"complete","anim_state":"Idle","components":{"ownership":{"civilization_id":13}}}
		for step in range(60):
			var time:=step*0.137
			check(registry.frame_info(building,time)==registry._resolve_frame_info(building,time),"complete composition remains exact: %s at %s"%[spec[0],time])
		for field in ["team","presentation_facing","hp","state"]:
			var changed:=building.duplicate(true)
			changed[field]=2 if field in ["team","presentation_facing"] else 120.0 if field=="hp" else "foundation"
			check(registry.frame_info(changed,0.73)==registry._resolve_frame_info(changed,0.73),"invalidation for %s/%s"%[spec[0],field])
	check(not registry.complete_static_frames.is_empty(),"time-invariant compositions are actually retained")
	for failure in failures:push_error(failure)
	print("Complete static building frames: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value:bool,message:String)->void:
	if not value:failures.append(message)
