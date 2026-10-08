extends SceneTree
# Standalone assembly: never loads any game scenes or resources.
const OUTPUT = "D:/Develop/Rise of Rome/visualizations/qwen-image-2.1-sample-2026-10-06"
var textures: Dictionary = {}
var bounds: Dictionary = {}
var regions: Array = []
var pivots: Array = []

class Painter extends Node2D:
	var textures: Dictionary
	var bounds: Dictionary
	var regions: Array
	var pivots: Array
	var phase = 0
	var mode = "scene"
	var houses = [Vector2(7.5,8.3),Vector2(6.5,13.0),Vector2(12.5,12.0)]
	var trees = [Vector3(3.5,11.5,0.98),Vector3(4.8,10.0,0.9),Vector3(11,4.2,1.04),Vector3(12.5,4.8,0.95),Vector3(14,5.5,1.08),Vector3(2.8,14.5,0.96),Vector3(3.8,15.1,0.88),Vector3(11.5,19.3,0.94),Vector3(18,12,1.02),Vector3(18.6,13.8,0.9)]
	var workers = [Vector2(8.7,9.7),Vector2(10.1,6.8),Vector2(7,13.8),Vector2(8,14.2),Vector2(12.9,13.6),Vector2(13.6,13.8),Vector2(11.8,7.8)]

	func project(at: Vector2) -> Vector2:
		return Vector2((at.x-at.y)*64,(at.x+at.y)*32)+Vector2(800,-140)

	func sprite(key: String,at: Vector2,size: Vector2,pivot: Vector2,region: Rect2,tint: Color = Color.WHITE) -> void:
		draw_texture_rect_region(textures[key],Rect2(at-size*pivot,size),region,tint)

	func worker(at: Vector2,frame: int,height: float = 72.0) -> void:
		var region: Rect2 = regions[frame]
		var size = Vector2(region.size.x/region.size.y*height,height)
		draw_set_transform(at+Vector2(0,-1),0,Vector2(1,0.42))
		draw_circle(Vector2.ZERO,height*0.13,Color(0.16,0.12,0.06,0.17),true,-1,true)
		draw_set_transform(Vector2.ZERO)
		sprite("worker",at,size,pivots[frame],region)

	func surface_uv(at: Vector2) -> Vector2:
		var local = at-Vector2(800,-140)
		return Vector2(local.x/128+local.y/64,local.y/64-local.x/128)/4

	func earth_polygon(points: PackedVector2Array,opacity: float) -> void:
		var uvs = PackedVector2Array()
		for at in points:
			uvs.append(surface_uv(at))
		draw_polygon(points,PackedColorArray([Color(1.0,1.0,1.0,opacity)]),uvs,textures["earth"])

	func smooth_world(points: Array) -> Array:
		var result: Array = []
		for segment in range(points.size()-1):
			var p0: Vector2 = points[maxi(0,segment-1)]
			var p1: Vector2 = points[segment]
			var p2: Vector2 = points[segment+1]
			var p3: Vector2 = points[mini(points.size()-1,segment+2)]
			for step in range(16):
				var t = float(step)/16
				result.append(0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
		result.append(points[-1])
		return result

	func earth_ribbon(points: Array,radius: float,opacity: float) -> void:
		var polygon = PackedVector2Array()
		var right = PackedVector2Array()
		for i in range(points.size()):
			var tangent: Vector2 = points[mini(points.size()-1,i+1)]-points[maxi(0,i-1)]
			var normal = Vector2(-tangent.y,tangent.x).normalized()
			var left_width = radius*(1.0+0.09*sin(float(i)*0.71)+0.035*sin(float(i)*2.2))
			var right_width = radius*(1.0+0.1*sin(float(i)*0.63+1.2)+0.04*sin(float(i)*1.9))
			polygon.append(project(points[i]+normal*left_width))
			right.append(project(points[i]-normal*right_width))
		for i in range(right.size()-1,-1,-1):
			polygon.append(right[i])
		earth_polygon(polygon,opacity)

	func feather_layers() -> Array:
		var layers: Array = []
		var previous = 0.0
		for i in range(1,33):
			var t = float(i)/32.0
			var target = t*t*(3.0-2.0*t)
			var opacity = (target-previous)/maxf(0.000001,1.0-previous)
			layers.append([0.28*(1.0-t),opacity])
			previous = target
		return layers

	func earth_path(points: Array,radius: float) -> void:
		var smooth = smooth_world(points)
		for layer in feather_layers():
			earth_ribbon(smooth,radius+float(layer[0]),float(layer[1]))

	func earth_pad(at: Vector2) -> void:
		for layer in feather_layers():
			var polygon = PackedVector2Array()
			var extra = float(layer[0])
			for i in range(48):
				var angle = float(i)/48*TAU
				var irregularity = 1.0+0.055*sin(angle*5.0+at.x)+0.04*sin(angle*9.0+at.y)
				var world = at+Vector2(cos(angle)*(1.36+extra),sin(angle)*(0.95+extra))*irregularity
				polygon.append(project(world))
			earth_polygon(polygon,float(layer[1]))

	func ground() -> void:
		var corners = PackedVector2Array([Vector2.ZERO,Vector2(1600,0),Vector2(1600,1000),Vector2(0,1000)])
		var uvs = PackedVector2Array()
		for at in corners:
			uvs.append(surface_uv(at))
		draw_polygon(corners,PackedColorArray([Color.WHITE]),uvs,textures["grass"])
		for at in houses:
			earth_pad(at)
		earth_path([Vector2(8.15,8.55),Vector2(9.2,9.6),Vector2(10.2,11.3),Vector2(11.8,12.0),Vector2(13.15,12.25)],0.34)
		earth_path([Vector2(7.15,13.25),Vector2(8.0,12.8),Vector2(9.1,11.9),Vector2(10.2,11.3)],0.28)

	func card() -> StyleBoxFlat:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("#f7efde")
		style.border_color = Color("#b9a586")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		return style

	func _draw() -> void:
		if mode == "unit":
			draw_rect(Rect2(0,0,480,360),Color("#eee3cb"))
			worker(Vector2(240,312),phase,246)
			return
		if mode == "board":
			draw_rect(Rect2(0,0,1600,1000),Color("#eee3cb"))
			var cards = [Rect2(24,24,752,448),Rect2(824,24,752,448),Rect2(24,520,752,456),Rect2(824,520,752,456)]
			var titles = ["Земля — трава и дорожки","Дом — отдельный спрайт","Дуб — отдельный спрайт","Рабочий — пробные фазы шага"]
			for i in range(4):
				draw_style_box(card(),cards[i])
				draw_string(ThemeDB.fallback_font,cards[i].position+Vector2(24,36),titles[i],HORIZONTAL_ALIGNMENT_LEFT,-1,23,Color("#3f3023"))
			draw_texture_rect(textures["grass"],Rect2(90,92,290,350),false)
			draw_texture_rect(textures["earth"],Rect2(410,92,290,350),false)
			var hr: Rect2 = bounds["house"]
			sprite("house",Vector2(1200,426),Vector2(450,450*hr.size.y/hr.size.x),Vector2(0.5,1),hr)
			var tr: Rect2 = bounds["oak"]
			sprite("oak",Vector2(400,946),Vector2(350*tr.size.x/tr.size.y,350),Vector2(0.5,1),tr)
			for i in range(4):
				worker(Vector2(915+i*190,935),i,260)
			return
		ground()
		var ordered: Array = []
		for i in range(houses.size()):
			ordered.append({"kind":"house","at":houses[i],"depth":houses[i].x+houses[i].y,"index":i})
		for i in range(trees.size()):
			var t: Vector3 = trees[i]
			ordered.append({"kind":"oak","at":Vector2(t.x,t.y),"depth":t.x+t.y,"index":i,"scale":t.z})
		for i in range(workers.size()):
			ordered.append({"kind":"worker","at":workers[i],"depth":workers[i].x+workers[i].y,"index":i})
		ordered.sort_custom(func(a,b):return a["depth"]<b["depth"])
		for item in ordered:
			var at = project(item["at"])
			var key: String = item["kind"]
			if key == "worker":
				worker(at,(phase+int(item["index"]))%4)
			elif key == "house":
				var region: Rect2 = bounds[key]
				var size = Vector2(288,288*region.size.y/region.size.x)
				sprite(key,at,size,Vector2(0.54,0.84),region)
			else:
				var region: Rect2 = bounds[key]
				var height: float = 248*float(item["scale"])
				sprite(key,at,Vector2(height*region.size.x/region.size.y,height),Vector2(0.54,0.93),region,Color(0.97,0.99,0.95))

func _initialize() -> void:
	call_deferred("render")

# Ignore near-zero-alpha haze when determining display regions; source PNGs stay intact.
func visible_bounds(image: Image) -> Rect2i:
	var min_x = image.get_width()
	var min_y = image.get_height()
	var max_x = -1
	var max_y = -1
	for y in range(0,image.get_height(),2):
		for x in range(0,image.get_width(),2):
			if image.get_pixel(x,y).a >= 0.15:
				min_x = mini(min_x,x)
				min_y = mini(min_y,y)
				max_x = maxi(max_x,x)
				max_y = maxi(max_y,y)
	if max_x < min_x:
		return image.get_used_rect()
	min_x = maxi(0,min_x-3)
	min_y = maxi(0,min_y-3)
	max_x = mini(image.get_width()-1,max_x+3)
	max_y = mini(image.get_height()-1,max_y+3)
	return Rect2i(min_x,min_y,max_x-min_x+1,max_y-min_y+1)

func rect_values(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func render() -> void:
	var metadata = {"model":"Qwen/Qwen-Image-2.1","provider":"official demo for sprites; local Q4_K for ground and pose correction","purpose":"standalone sample only","renderer":"Godot 4.7.2","projection":{"cell":[64,32],"zoom":2},"render_sizes":{"house_width":288,"worker_height":72,"tree_height":248},"assets":{},"animation":{"direction":"screen lower-right","frames":4,"fps":6,"status":"draft; pose guide improved passing poses, opposite stride still missing"}}
	var images: Dictionary = {}
	for pair in [["grass","grass.png"],["earth","earth.png"],["house","house.png"],["oak","oak.png"],["worker","worker-walk-v2-sheet.png"]]:
		var key: String = pair[0]
		var image = Image.load_from_file(OUTPUT.path_join(pair[1]))
		if image == null or image.is_empty():
			push_error("Cannot load "+key)
			quit(1)
			return
		images[key] = image
		image.generate_mipmaps()
		textures[key] = ImageTexture.create_from_image(image)
		bounds[key] = Rect2(image.get_used_rect() if key in ["grass","earth"] else visible_bounds(image))
		var alpha_type = image.detect_alpha()
		if key not in ["grass","earth"] and alpha_type == Image.ALPHA_NONE:
			push_error("Missing real transparency: "+key)
			quit(1)
			return
		metadata["assets"][key] = {"file":pair[1],"size":[image.get_width(),image.get_height()],"used_rect":rect_values(bounds[key]),"alpha_type":alpha_type,"corner_alpha":image.get_pixel(0,0).a}
	var sheet: Image = images["worker"]
	var cell = Vector2i(sheet.get_width()/2,sheet.get_height()/2)
	for i in range(4):
		var origin = Vector2i((i%2)*cell.x,(i/2)*cell.y)
		var frame = sheet.get_region(Rect2i(origin,cell))
		var used = visible_bounds(frame)
		regions.append(Rect2(Vector2(origin+used.position),Vector2(used.size)))
		var sum_x = 0.0
		var count = 0
		for y in range(used.position.y+int(used.size.y*0.54),used.position.y+int(used.size.y*0.64)):
			for x in range(used.position.x,used.end.x):
				if frame.get_pixel(x,y).a>0.5:
					sum_x += x-used.position.x
					count += 1
		pivots.append(Vector2(sum_x/maxi(1,count)/float(used.size.x),1))
	metadata["animation"]["regions"] = regions.map(func(r):return rect_values(r))
	metadata["animation"]["pivots"] = pivots.map(func(p):return [p.x,p.y])
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1600,1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas = Painter.new()
	canvas.textures = textures
	canvas.bounds = bounds
	canvas.regions = regions
	canvas.pivots = pivots
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	viewport.add_child(canvas)
	await capture(viewport,canvas,OUTPUT.path_join("assembled-scene.png"))
	canvas.mode = "board"
	await capture(viewport,canvas,OUTPUT.path_join("assets-overview.png"))
	canvas.mode = "scene"
	for i in range(4):
		canvas.phase = i
		await capture(viewport,canvas,OUTPUT.path_join("frames/scene-%02d.png"%i))
	canvas.mode = "unit"
	viewport.size = Vector2i(480,360)
	for i in range(4):
		canvas.phase = i
		await capture(viewport,canvas,OUTPUT.path_join("frames/worker-%02d.png"%i))
	var file = FileAccess.open(OUTPUT.path_join("asset-manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"\t"))
	file.close()
	print("Scene assembled from five PNG assets; scale and terrain revised. Actual alpha verified. All captures saved.")
	quit(0)

func capture(viewport: SubViewport,canvas: Painter,path: String) -> void:
	canvas.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error = viewport.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Cannot save capture "+path)
		quit(1)
