class_name RoRRiverFeaturePresentation
extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")
const CliffChain := preload("res://scripts/cliff_chain.gd")
const MAX_CACHED_MESHES := 128
# Landmarks in the complete, uncut native waterfall (SLP 702).
const SOURCE_LIP := Vector2(53,3)
const SOURCE_FOOT := Vector2(17,65)
const SOURCE_SHOULDER_Y := 37.0
static var geometry_cache: Dictionary = {}

static func frame_info(item: Dictionary, rock_frames: Array, _time: float, art: Dictionary = {}) -> Dictionary:
	return {
		"river_geometry":item,
		"rock_texture":art.get("rock",rock_frames[1] if rock_frames.size()>1 else null),
		"cascade_texture":art.get("cascade"), "bank_rocks":art.get("banks",[]),
		"animation_frames":1,
		"asset_name":"river_ledge", "hotspot":Vector2.ZERO, "graphic_layer":20,
		"frame_index":0, "screen_offset":item.get("cliff_screen_offset",Vector2.ZERO),
	}

# The waterfall is built from whole authored rocks with water already flowing
# around their faces. Only the narrow upstream neck follows the river direction;
# the large lower body retains its original proportions, outline and lighting.
static func draw(canvas: CanvasItem, info: Dictionary, screen: Vector2, zoom: float, opacity: float = 1.0) -> void:
	var feature: Dictionary = info["river_geometry"]
	var fall: Dictionary = feature["river_form"]
	canvas.draw_set_transform(screen+Vector2(info["screen_offset"])*zoom,0,Vector2.ONE*zoom)
	var modulation := Color(1,1,1,opacity)
	canvas.draw_mesh(_mesh(info,"rock"),info["rock_texture"],Transform2D.IDENTITY,modulation)
	var banks := _bank_layout(fall,Vector2(feature["position"]),info["bank_rocks"])
	_draw_banks(canvas,banks,false,opacity)
	if info["cascade_texture"] != null:
		canvas.draw_mesh(_mesh(info,"cascade"),info["cascade_texture"],Transform2D.IDENTITY,modulation)
	_draw_banks(canvas,banks,true,opacity)
	canvas.draw_set_transform(Vector2.ZERO)

static func _bank_layout(fall: Dictionary, anchor: Vector2, banks: Array) -> Array:
	if banks.is_empty(): return []
	var direction: Vector2 = fall["direction"]
	var normal := Vector2(-direction.y,direction.x)
	var center: Vector2 = fall["position"]
	var result: Array = []
	for side in [-1,1]:
		var outward := normal*float(side)
		var connection: int
		if absf(outward.x)+0.0001>=absf(outward.y):
			connection=CliffChain.RIGHT if outward.x>0.0 else CliffChain.LEFT
		else:
			connection=CliffChain.DOWN if outward.y>0.0 else CliffChain.UP
		# The connected end continues into the land. Its free, tapering end
		# faces the water; use the same authored orientation as ordinary cliffs.
		var wanted := int(CliffChain.piece(connection)["source_frame"])
		var bank: Dictionary = banks.filter(func(record):return record["source_frame"]==wanted)[0]
		var across := float(fall["radius"])*float(side)
		var point := center+outward*(float(fall["radius"])+0.65)+direction*(_crown(across)+0.15)
		var screen := Coordinates.iso_raw(point-anchor)+Vector2(0,_drop(fall)*0.42)
		result.append({"bank":bank,"screen":screen,"source_frame":wanted,"connection":connection,
			"outward":outward,"foreground":Coordinates.iso_raw(outward).y>0.001})
	return result

static func _draw_banks(canvas: CanvasItem, banks: Array, foreground: bool, opacity: float) -> void:
	for placement in banks:
		if placement["foreground"]!=foreground: continue
		var bank: Dictionary = placement["bank"]
		var texture: Texture2D = bank["texture"]
		canvas.draw_texture_rect(texture,Rect2((Vector2(placement["screen"])-Vector2(bank["hotspot"])).round(),texture.get_size()),false,Color(1,1,1,opacity))

static func _mesh(info: Dictionary, kind: String, _frame: int = 0) -> ArrayMesh:
	var feature: Dictionary = info["river_geometry"]
	var fall: Dictionary = feature["river_form"]
	var key := str([fall["position"],fall["direction"],fall["radius"],_drop(fall),feature["position"],kind,info["rock_texture"],info["cascade_texture"]])
	if geometry_cache.has(key): return geometry_cache[key]
	var arrays: Array
	if kind=="rock": arrays=_rock_arrays(fall,Vector2(feature["position"]))
	else: arrays=_cascade_arrays(fall,Vector2(feature["position"]),info["cascade_texture"].get_size())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if geometry_cache.size()>=MAX_CACHED_MESHES: geometry_cache.erase(geometry_cache.keys()[0])
	geometry_cache[key]=mesh
	return mesh

static func _rock_arrays(fall: Dictionary, anchor: Vector2) -> Array:
	var direction: Vector2 = fall["direction"]
	var normal := Vector2(-direction.y,direction.x)
	var center: Vector2 = fall["position"]
	var radius := float(fall["radius"])
	var span := radius+0.9
	var columns := ceili(span*2.0/0.24)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var pixel_width := Coordinates.iso_raw(normal).length()
	for i in range(columns+1):
		var across := lerpf(-span,span,float(i)/columns)
		var top := Coordinates.iso_raw(center+normal*across+direction*_crown(across)-anchor)
		var foot := Coordinates.iso_raw(center+normal*across+direction*(0.82+sin(across*4.1)*0.12)-anchor)+Vector2(0,_drop(fall))
		var light := 0.96+sin(across*4.71)*0.025
		var u := clampf((across+span)*pixel_width/512.0,0.0,0.98)
		vertices.append(Vector3(top.x,top.y,0)); vertices.append(Vector3(foot.x,foot.y,0))
		uvs.append(Vector2(u,0)); uvs.append(Vector2(u,clampf(top.distance_to(foot)/64.0,0.2,1.0)))
		colors.append(Color(light,light,light)); colors.append(Color(light*0.94,light*0.94,light*0.94))
		if i<columns:
			var at := i*2
			indices.append_array(PackedInt32Array([at,at+2,at+3,at,at+3,at+1]))
	return _arrays(vertices,uvs,colors,indices)

static func _cascade_layout(fall: Dictionary, anchor: Vector2) -> Array:
	var direction: Vector2 = fall["direction"]
	var normal := Vector2(-direction.y,direction.x)
	var center: Vector2 = fall["position"]
	var radius := float(fall["radius"])*0.84
	var drop := _drop(fall)
	var count := clampi(ceili(radius*2.0/0.72)+1,4,10)
	var result: Array = []
	var projected := Coordinates.iso_raw(direction)
	for i in range(count):
		var across := lerpf(-radius,radius,float(i)/float(count-1))+sin(i*4.71+2.13)*0.10
		var run := 1.2+sin(i*2.39)*0.18
		var lip_along := _crown(across)-0.22
		var foot := Coordinates.iso_raw(center+normal*across+direction*(lip_along+run)-anchor)+Vector2(0,drop)
		var lip := Coordinates.iso_raw(center+normal*across+direction*lip_along-anchor)
		# Match the authored vertical span instead of flattening a long neck
		# across the upper pool. This leaves the stream and stone proportionate.
		var size := maxf(0.75,(drop+projected.y*run)/(SOURCE_FOOT.y-SOURCE_LIP.y))*1.32
		result.append({"foot":foot,"lip":lip,"scale":size,"mirrored":projected.x>0.0,"across":across})
	result.sort_custom(func(a,b):return a["foot"].y<b["foot"].y)
	return result

static func _cascade_point(stone: Dictionary, source: Vector2) -> Vector2:
	var scale := float(stone["scale"])
	var native := source-SOURCE_FOOT
	var native_lip_delta := SOURCE_LIP-SOURCE_FOOT
	if stone["mirrored"]:
		native.x=-native.x
		native_lip_delta.x=-native_lip_delta.x
	var native_lip := Vector2(stone["foot"])+native_lip_delta*scale
	var neck := 1.0-smoothstep(SOURCE_LIP.y,SOURCE_SHOULDER_Y,source.y)
	return Vector2(stone["foot"])+native*scale+(Vector2(stone["lip"])-native_lip)*neck

static func _cascade_arrays(fall: Dictionary, anchor: Vector2, source_size: Vector2) -> Array:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for stone in _cascade_layout(fall,anchor):
		var start := vertices.size()
		for y in range(int(source_size.y)+1):
			for x in [0.0,source_size.x]:
				var source := Vector2(x,y)
				var point := _cascade_point(stone,source)
				vertices.append(Vector3(point.x,point.y,0))
				uvs.append(source/source_size)
				colors.append(Color.WHITE)
			if y<int(source_size.y):
				var at := start+y*2
				indices.append_array(PackedInt32Array([at,at+1,at+3,at,at+3,at+2]))
	return _arrays(vertices,uvs,colors,indices)

static func _arrays(vertices: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> Array:
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX]=vertices
	result[Mesh.ARRAY_TEX_UV]=uvs
	result[Mesh.ARRAY_COLOR]=colors
	result[Mesh.ARRAY_INDEX]=indices
	return result

static func _crown(across: float) -> float:
	return sin(across*2.17)*0.42+sin(across*5.31+0.7)*0.16

static func _drop(fall: Dictionary) -> float:
	return (float(fall["upper_level"])-float(fall["lower_level"]))*16.0
