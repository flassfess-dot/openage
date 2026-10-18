extends SceneTree
const Renderer := preload("res://scripts/render_world.gd")
var failures: Array[String] = []
var animation := 0
var texture: Texture2D
func info(kind: String, actor: Dictionary) -> Dictionary:
	if kind == "rally_flag": return {"frame_index":animation,"hotspot":Vector2(2,3)}
	return {"texture":texture,"frame_index":animation,"hotspot":Vector2(10,20),"graphic_layer":20,"composite_parts":[{"texture":texture,"frame_index":1,"graphic_layer":10,"presentation_layer":"shadow","depth_world_offset":Vector2(1,-1)},{"texture":texture,"frame_index":2,"graphic_layer":20,"presentation_layer":"upright","depth_world_offset":Vector2(0.4,0.2)}]}
func project(point: Vector2) -> Vector2:
	return Vector2((point.x-point.y)*32,(point.x+point.y)*16)+Vector2(120,80)
func _initialize() -> void:
	var kernel: Variant = ClassDB.instantiate("RoRReadModelKernel")
	check(kernel.has_method("create_building_render_items"),"native building kernel is present")
	if not failures.is_empty(): quit(1); return
	texture = ImageTexture.create_from_image(Image.create(24,32,false,Image.FORMAT_RGBA8))
	var reference := Renderer.new()
	reference.native_buildings_enabled = false
	reference.sprite_atlas_enabled = false
	var native := Renderer.new()
	native.sprite_atlas_enabled = false
	var buildings: Array = []
	for index in range(7):
		buildings.append({"id":10+index,"kind":["house","farm","wall","gate","town_center","barracks","granary"][index],"team":1 if index%2==0 else 2,"hp":100.0,"max_hp":100.0,"pos":Vector2(8+index,9),"elevation":0.25*index,"state":"complete","death_phase":"alive","harvestable":index==1,"rally_point_set":index==4,"rally_point":Vector2(13,11)})
	for step in range(12):
		animation = step / 3
		var selected: Array[int] = []
		selected.append_array([14] if step%2==0 else [12,10])
		var preview: Array[int] = []
		if step%3==0: preview.append(11)
		if step==3:
			buildings[0]["hp"]=0.0
			buildings[0]["death_phase"]="ruin"
		if step==5: buildings[1]["state"]="foundation"
		if step==7: buildings.pop_back()
		if step==9: buildings[0]["death_phase"]="removed"
		if step>0:
			var replacement: Dictionary = buildings[2].duplicate(true)
			replacement["pos"] += Vector2(0.1,0.2)
			buildings[2]=replacement
		var snapshot := {"buildings":buildings,"units":[],"resources":[],"effects":[]}
		var expected := reference.create_world_drawables(snapshot,Callable(self,"project"),1.0,Callable(self,"info"),preview,1,selected,1.5,Rect2(0,0,1800,1200))
		var actual := native.create_world_drawables(snapshot,Callable(self,"project"),1.0,Callable(self,"info"),preview,1,selected,1.5,Rect2(0,0,1800,1200))
		check(actual==expected,"native items preserve composition, depth, selection, rally and lifecycle at step %d"%step)
		check(native.rally_drawables==reference.rally_drawables,"rally publication matches at step %d"%step)
	var drawable := {"kind":"building","sprite_command":[null,Rect2(1000,1000,20,20)]}
	var overlay := {"kind":"selection","sprite_command":[null,Rect2(1000,1000,20,20)]}
	check(kernel.clip_building_render_items([drawable,overlay],Rect2(0,0,100,100))==[overlay],"native clipping keeps the original overlay policy")
	for failure in failures: push_error(failure)
	print("Native building render items: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
