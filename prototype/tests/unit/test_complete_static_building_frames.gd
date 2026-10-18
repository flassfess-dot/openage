extends SceneTree
const Catalog:=preload("res://scripts/resource_catalog.gd")
var failures:Array[String]=[]
func _initialize()->void:
	var catalog=Catalog.new()
	catalog.load()
	var registry=catalog.building_presentations
	for spec in [["house",70,817],["barracks",12,13],["town_center",109,598],["granary",68,863],["storage_pit",103,515],["archery_range",87,873],["farm",50,273]]:
		var building:Dictionary={"id":10,"kind":spec[0],"team":1,"source_unit_id":spec[1],"display_graphic_id":spec[2],"hp":600.0,"max_hp":600.0,"state":"complete","anim_state":"Idle","harvestable":spec[0]=="farm","amount":150,"components":{"ownership":{"civilization_id":13}}}
		for step in range(60):
			var time:=step*0.137
			check(registry.frame_info(building,time)==registry._resolve_frame_info(building,time),"complete composition remains exact: %s at %s"%[spec[0],time])
		for field in ["team","presentation_facing","hp","state"]:
			var changed:=building.duplicate(true)
			changed[field]=2 if field in ["team","presentation_facing"] else 120.0 if field=="hp" else "foundation"
			check(registry.frame_info(changed,0.73)==registry._resolve_frame_info(changed,0.73),"invalidation for %s/%s"%[spec[0],field])
	check(not registry.complete_static_frames.is_empty(),"time-invariant compositions are actually retained")
	var building := {"id":200,"kind":"barracks","team":1,"source_unit_id":12,"display_graphic_id":13,"hp":600.0,"max_hp":600.0,"state":"complete","anim_state":"Idle","components":{"ownership":{"civilization_id":13}}}
	var frame: Dictionary = registry.frame_info(building,0.0,true)
	check(frame.is_read_only() and is_same(frame,registry.frame_info(building,2.0,true)),"renderer borrows the same immutable static composition")
	var editable: Dictionary = registry.frame_info(building,2.0)
	check(not editable.is_read_only() and editable == frame,"ordinary frame callers retain a mutable descriptor")
	editable["graphic_id"] = -999
	check(registry.frame_info(building,2.0,true)["graphic_id"] != -999,"ordinary caller edits cannot alter retained graphics")
	var farm := {"id":301,"kind":"farm","team":1,"source_unit_id":50,"display_graphic_id":273,"hp":300.0,"max_hp":300.0,"state":"complete","anim_state":"Idle","harvestable":true,"amount":150,"components":{"ownership":{"civilization_id":13}}}
	var farm_frame: Dictionary = registry.frame_info(farm,0.0,true)
	check(farm_frame.is_read_only() and is_same(farm_frame,registry.frame_info(farm,5.7,true)),"healthy farms retain static crop, hut and depth offsets")
	farm["amount"] = 0
	check(registry.frame_info(farm,5.7,true) == registry._resolve_frame_info(farm,5.7),"depleted farms bypass the healthy composition")
	for failure in failures:push_error(failure)
	print("Complete static building frames: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value:bool,message:String)->void:
	if not value:failures.append(message)
