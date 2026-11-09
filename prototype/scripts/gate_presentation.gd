class_name RoRGatePresentation
extends RefCounted

const WallPlacement := preload("res://scripts/wall_placement.gd")
const GROUPS := ["egyptian", "greek", "mesopotamian", "east_asian", "roman"]
const PROFILES := [
	{"left": Vector2(112,112), "right": Vector2(184,148), "height":26.0,"flag_height":24.0},
	{"left": Vector2(112,114), "right": Vector2(180,148), "height":34.0,"flag_height":38.0},
	{"left": Vector2(107,114), "right": Vector2(175,148), "height":36.0,"flag_height":38.0},
	{"left": Vector2(112,112), "right": Vector2(184,148), "height":34.0,"flag_height":56.0},
	{"left": Vector2(112,116), "right": Vector2(176,148), "height":38.0,"flag_height":35.0},
]
var textures: Dictionary = {}
var cache: Dictionary = {}
# Immutable visual definitions belong to this configured asset generation.
var visual_sources: Dictionary = {}

func prewarm_textures() -> void:
	for group in range(GROUPS.size()):
		if not textures.has(group): textures[group] = load("res://assets/gates/%s-door.png" % GROUPS[group])

static func project(position: Vector2, height: float = 0.0) -> Vector2:
	return Vector2((position.x-position.y)*32.0, (position.x+position.y)*16.0-height)

static func unproject(pixel: Vector2) -> Vector2:
	pixel -= Vector2(160,124)
	return Vector2((pixel.x/32.0+pixel.y/16.0)*0.5, (pixel.y/16.0-pixel.x/32.0)*0.5)

static func orient(position: Vector2, axis: int) -> Vector2:
	return position if axis == 0 else Vector2(position.y,position.x)

static func visual_origin(building: Dictionary) -> Vector2:
	# Even-width footprints have no central tile; use the same tile anchors as walls.
	return WallPlacement.masonry_center(building)-Vector2(building.get("pos",Vector2.ZERO))

func _visual_source(registry, building: Dictionary) -> Dictionary:
	var civilization := int(building.get("components", {}).get("ownership", {}).get("civilization_id", 13))
	var wall_id := int(building.get("source_unit_id",10072))-10000
	if wall_id not in [72,117,155]: wall_id = 72
	var key := Vector2i(civilization,wall_id)
	if visual_sources.has(key): return visual_sources[key]
	var group := 0 if wall_id == 72 else int(registry.civilization_icon_sets.get(civilization,4))
	var source: Dictionary = registry.object_catalog.get("objects", {}).get("%d:%d" % [civilization,wall_id], {})
	var result := {"civilization":civilization,"wall_id":wall_id,"group":group,"source":source,"graphic":int(source.get("graphics",{}).get("idle",-1))}
	result.make_read_only()
	visual_sources[key] = result
	return result


func graphic_dependencies(registry, building: Dictionary) -> Array:
	# Synthetic gates do not have an imported graphic at their synthetic ID.
	# Declare the same masonry, flag, reference and damage sources used to draw.
	var visual := _visual_source(registry,building)
	var graphics: Dictionary = visual["source"].get("graphics",{})
	var ids := {702:true}
	for name in ["idle","death","construction"]:
		var id := int(graphics.get(name,-1))
		if id >= 0: ids[id] = true
	for damage in graphics.get("damage",[]):
		var id := int(damage.get("graphic_id",-1))
		if id >= 0: ids[id] = true
	if int(visual["wall_id"]) == 155:
		var reference: Dictionary = registry.object_catalog.get("objects",{}).get("%d:117" % int(visual["civilization"]),{})
		var id := int(reference.get("graphics",{}).get("idle",-1))
		if id >= 0: ids[id] = true
	return ids.keys()


func frame_info(registry, building: Dictionary, player: int) -> Dictionary:
	var visual := _visual_source(registry,building)
	var civilization := int(visual["civilization"])
	var wall_id := int(visual["wall_id"])
	var group := int(visual["group"])
	var source: Dictionary = visual["source"]
	var graphic := int(visual["graphic"])
	var axis := int(building.get("gate_axis",0))
	var pose := roundi(clampf(float(building.get("gate_open_fraction",0)),0,1)*7)
	var ruined := float(building.get("hp",1)) <= 0 or String(building.get("state","")) == "destroyed"
	var foundation := String(building.get("state","complete")) == "foundation"
	var stage := int(building.get("construction_stage",0)) if foundation else -1
	var damage := 2 if float(building.get("hp",1))/maxf(1,float(building.get("max_hp",1))) < 0.3 else 1 if float(building.get("hp",1))/maxf(1,float(building.get("max_hp",1))) < 0.65 else 0
	var origin := visual_origin(building)
	var key := "%d:%d:%d:%d:%d:%d:%d:%d:%.3f:%.3f" % [graphic,group,axis,pose,player,int(ruined),stage,damage,origin.x,origin.y]
	if cache.has(key):
		return cache[key]
	var parts: Array = []
	var occluders: Array = []
	if foundation:
		# One continuous four-tile site. Finished leaves cannot float between
		# scaffolds while the masonry piers are still under construction.
		for offset in [-1.5, -0.5, 0.5, 1.5]:
			var construction: Dictionary = registry._frame_at(int(source.get("graphics", {}).get("construction", 77)), player, stage)
			_add_sprite(parts, construction, origin + orient(Vector2(offset, 0), axis))
		var construction_result := {"texture": null, "graphic_id": graphic, "composite_parts": parts, "gate_occluders": occluders}
		cache[key] = construction_result
		return construction_result
	var base: Dictionary = registry._resolved_frame(graphic,player,2,0)
	var profile: Dictionary = PROFILES[group]
	var height: float = float(profile["height"])
	if wall_id == 155:
		var reference_source: Dictionary = registry.object_catalog.get("objects", {}).get("%d:117" % civilization,{})
		var reference: Dictionary = registry._resolved_frame(int(reference_source.get("graphics",{}).get("idle",-1)),player,2,0)
		if base.get("texture") != null and reference.get("texture") != null:
			height *= float(base["texture"].get_height())/maxf(1,float(reference["texture"].get_height()))
	height = 22.0 if wall_id == 72 else maxf(12,height)
	var flag_height: float = 19.0 if wall_id == 72 else float(profile["flag_height"])+height-float(profile["height"])
	for side in [-1,1]:
		var anchor := origin+orient(Vector2(side*1.5,0),axis)
		var sprite: Dictionary = base.duplicate()
		var overlays: Array = registry._composite_parts(graphic,player,2,0)
		if ruined:
			sprite = registry._resolved_frame(int(source.get("graphics",{}).get("death",-1)),player,0,0)
			overlays = registry._composite_parts(int(source.get("graphics",{}).get("death",-1)),player,0,0)
		elif foundation:
			sprite = registry._frame_at(int(source.get("graphics",{}).get("construction",77)),player,stage)
			overlays = []
		_add_sprite(parts,sprite,anchor)
		for overlay in overlays:
			if int(overlay.get("graphic_id",-1)) != 702:
				_add_sprite(parts,overlay,anchor)
		if not ruined and not foundation:
			var damaged: Dictionary = registry._damage_part(building,source,player,0,2)
			if not damaged.is_empty():
				_add_sprite(parts,damaged,anchor)
			var flag: Dictionary = registry._frame_at(702,player,12).duplicate()
			flag["screen_offset"] = Vector2(flag.get("screen_offset",Vector2.ZERO))+project(anchor)-Vector2(0,flag_height)
			flag["depth_world_offset"] = anchor
			parts.append(flag)
	if not ruined and (not foundation or stage >= 2):
		if not textures.has(group):
			textures[group] = load("res://assets/gates/%s-door.png" % GROUPS[group])
		var texture: Texture2D = textures[group]
		# Texture crop coordinates describe artwork, not masonry attachment
		# points. Seat both hinges inside the inner faces of the 1x1 piers;
		# swapping axes must keep the same physical overlap with the stone.
		var left := Vector2(-1.1, 0.25)
		var right := Vector2(1.1, 0.25)
		var length: float = right.x-left.x
		var angle := float(pose)/7.0*PI*0.5
		for side in [0,1]:
			var hinge: Vector2 = origin+orient(left if side == 0 else right,axis)
			var local_direction := Vector2(cos(angle)*(1 if side == 0 else -1),sin(angle))
			var direction := orient(local_direction,axis)
			var end: Vector2 = hinge+direction*length*0.5
			var front_normal := orient(Vector2(-local_direction.y,local_direction.x)*(1 if side == 0 else -1),axis)
			var back: Vector2 = -front_normal*0.09
			# Dedicated opaque material: no grass/player-color fringe sampled
			# from an isometric cutout, and vertical planks in both orientations.
			var face_uv := PackedVector2Array([Vector2(0,0), Vector2(63,0), Vector2(63,63), Vector2(0,63)])
			var top_uv := PackedVector2Array([Vector2(0,2), Vector2(63,2), Vector2(63,5), Vector2(0,5)])
			var shade := Color(0.82,0.82,0.82) if damage == 2 else Color.WHITE
			var visible_front := front_normal.x+front_normal.y >= 0
			var p0: Vector2 = hinge if visible_front else hinge+back
			var p1: Vector2 = end if visible_front else end+back
			# A leaf is one solid object. Never insert a rider between its faces.
			var leaf_depth := (hinge+end+back)*0.5
			var leaf_tags := {"gate_leaf":side}
			occluders.append({"start":p0,"end":p1,"depth":leaf_depth})
			_face(parts,[project(p0,height),project(p1,height),project(p1),project(p0)],face_uv,texture,shade,leaf_depth,leaf_tags)
			_face(parts,[project(hinge,height),project(end,height),project(end+back,height),project(hinge+back,height)],top_uv,texture,Color.WHITE,leaf_depth,leaf_tags)
			_face(parts,[project(end,height),project(end+back,height),project(end+back),project(end)],PackedVector2Array(),null,Color("#6b4b27"),leaf_depth,leaf_tags)
			# The near pier hides its inner mounting face. Hardware may only show
			# where the original masonry sprite is transparent.
			var mount_depth := hinge+Vector2(0.03,0.03) if side == 0 else origin+orient(Vector2(1.5,0),axis)-Vector2(0.01,0.01)
			var mount_tags := {"gate_hinge":side}
			# The iron pintles stay on the masonry while the straps turn with the slab.
			for ratio in [0.3,0.72]:
				var pin := project(hinge,height*(1-ratio))
				var strap := project(p0+direction*0.07,height*(1-ratio))
				var edge := (strap-pin).orthogonal().normalized()*1.5
				_face(parts,[pin-edge,strap-edge,strap+edge,pin+edge],PackedVector2Array(),null,Color("#373737"),mount_depth,mount_tags)
				_face(parts,[pin+Vector2(-2,-3),pin+Vector2(2,-3),pin+Vector2(3,-2),pin+Vector2(3,3),pin+Vector2(2,4),pin+Vector2(-2,4),pin+Vector2(-3,3),pin+Vector2(-3,-2)],PackedVector2Array(),null,Color("#252525"),mount_depth,mount_tags)
				_face(parts,[pin+Vector2(0,-2),pin+Vector2(2,-2),pin+Vector2(2,3),pin+Vector2(0,3)],PackedVector2Array(),null,Color("#6f6f6f"),mount_depth,mount_tags)
	if ruined:
		for index in range(3):
			var p := origin+orient(Vector2(-0.5+index*0.45,0.3),axis)
			var rubble_pixel := project(p)
			_face(parts,[rubble_pixel+Vector2(-14,-3),rubble_pixel+Vector2(9,6),rubble_pixel+Vector2(13,3),rubble_pixel+Vector2(-10,-6)],PackedVector2Array(),null,Color("#6b4b27"),p)
	var result := {"texture":null,"graphic_id":graphic,"composite_parts":parts,"gate_occluders":occluders}
	cache[key] = result
	return result

func _add_sprite(parts: Array, source: Dictionary, anchor: Vector2) -> void:
	if source.get("texture") == null:
		return
	var sprite: Dictionary = source.duplicate()
	sprite["screen_offset"] = Vector2(sprite.get("screen_offset",Vector2.ZERO))+project(anchor)
	sprite["depth_world_offset"] = anchor
	if int(sprite.get("graphic_layer",20)) < 20:
		sprite["presentation_layer"] = "shadow"
	parts.append(sprite)

func _face(parts: Array, points: Array, uvs: PackedVector2Array, texture: Texture2D, color: Color, depth: Vector2, tags: Dictionary = {}) -> void:
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(Vector2(point).round())
	var normalized := PackedVector2Array()
	if texture != null:
		for uv in uvs:
			normalized.append(uv/texture.get_size())
	var part := {"texture":texture,"gate_polygon":polygon,"gate_uv":normalized,"gate_color":color,"depth_world_offset":depth,"graphic_layer":20,"frame_index":0,"hotspot":Vector2.ZERO}
	part.merge(tags)
	parts.append(part)
