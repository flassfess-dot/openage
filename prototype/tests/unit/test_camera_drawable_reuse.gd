extends SceneTree
const Renderer := preload("res://scripts/render_world.gd")
var failures: Array[String] = []
var offset := Vector2(180, -100)
var zoom := 1.0
var texture: Texture2D
func project(point: Vector2) -> Vector2:
	return Vector2((point.x-point.y)*32.0, (point.x+point.y)*16.0 - float(int(point.x) % 3)*8.0)*zoom+offset
func info(kind: String, _data: Dictionary) -> Dictionary:
	var value := {"texture":texture, "hotspot":Vector2(14,38), "screen_offset":Vector2(2,-3)}
	if kind == "building":
		value["composite_parts"] = [{"texture":texture,"hotspot":Vector2(10,30),"graphic_layer":21,"world_offset":Vector2(0.5,0.5)}]
		value["gate_occluders"] = [{"start":Vector2(-1,-1),"end":Vector2(1,1),"depth":Vector2.ZERO}]
	return value
func _initialize() -> void:
	texture = ImageTexture.create_from_image(Image.create(30,48,false,Image.FORMAT_RGBA8))
	var fast := Renderer.new()
	var reference := Renderer.new()
	reference.native_render_kernel = null
	reference.affine_static_projection = false
	var scene := {"resources":[],"environment":[],"units":[],"buildings":[]}
	for n in range(25):
		scene["resources"].append({"id":n+1,"kind":"tree","pos":Vector2(n%5,n/5),"amount":100})
		scene["environment"].append({"id":n+50,"position":Vector2(n%5+1,n/5+1),"source_frame":0})
	for n in range(4):
		scene["units"].append({"id":100+n,"kind":"clubman","pos":Vector2(n+0.3,3.2),"previous_pos":Vector2(n-0.2,3.0),"hp":100,"team":1})
		scene["buildings"].append({"id":200+n,"kind":"gate","pos":Vector2(n*2,2),"hp":600,"team":1,"movement_domain":"static"})
	var viewport := Rect2(0,0,300,240)
	fast.create_world_drawables(scene,project,0.0,info,[100],1,[101,200],zoom,viewport)
	for step in range(50):
		zoom = [0.75,1.0,1.5][(step/17)%3]
		offset = Vector2(220+sin(step*0.3)*330,-180+cos(step*0.2)*170)
		var alpha := float(step%10)/9.0
		var actual := fast.refresh_camera_drawables(project,alpha,zoom,viewport)
		var expected := reference.create_world_drawables(scene,project,alpha,info,[100],1,[101,200],zoom,viewport)
		check(actual.size()==expected.size(),"same visible item count at pan %d: %d/%d"%[step,actual.size(),expected.size()])
		for n in range(mini(actual.size(),expected.size())):
			var a: Dictionary=actual[n]
			var b: Dictionary=expected[n]
			for key in ["kind","stable_id","sub_order","world_anchor","screen_position","screen_y"]:
				check(is_equal_approx(float(a.get(key)),float(b.get(key))) if key=="screen_y" else a.get(key)==b.get(key),"same %s at step %d item %d (%s/%s): %s/%s"%[key,step,n,a["kind"],b["kind"],a.get(key),b.get(key)])
			if a.has("sprite_command") and b.has("sprite_command"):
				check(a["sprite_command"][1]==b["sprite_command"][1],"same sprite rectangle at step %d item %d"%[step,n])
		if step%7==0:
			# A new publication after camera reuse must retain its current transform.
			fast.create_world_drawables(scene,project,alpha,info,[100],1,[101,200],zoom,viewport)
	var prepared_weak: WeakRef = weakref(fast.cached_resource_clip["prepared"])
	check(prepared_weak.get_ref().get_record_count() == fast.cached_resource_drawables.size(), "native projection is bounded by the current query")
	fast.clear_caches()
	check(prepared_weak.get_ref() == null, "reset releases the native projection and its sprite references")
	check(not fast.can_refresh_camera(),"reset invalidates camera queue")
	for failure in failures.slice(0,20): push_error(failure)
	print("Camera drawable reuse: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value:bool,message:String)->void:
	if not value: failures.append(message)
