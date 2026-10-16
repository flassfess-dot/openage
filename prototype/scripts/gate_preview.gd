extends Node2D
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Renderer := preload("res://scripts/render_world.gd")
const Presentation := preload("res://scripts/gate_presentation.gd")
const GROUPS := ["Египетская","Греческая","Месопотамская","Восточноазиатская","Римская"]
const CIVILIZATIONS := [1,2,3,10,13]
var catalog = Catalog.new()
var renderer = Renderer.new()
var world
var gate: Dictionary
var group := 0
var level := 1
var axis := 0
var zoom := 3.0
var capture := false
var show_walls := false
var junction_pattern := "straight"
const Contract := preload("res://scripts/entity_read_contract.gd")
const WallPlacement := preload("res://scripts/wall_placement.gd")

func _ready() -> void:
	catalog.load()
	var arguments := OS.get_cmdline_user_args()
	show_walls = "--gate-junctions" in arguments or "--capture-gate-junctions" in arguments
	capture = "--capture-gates" in arguments or "--capture-gate-junctions" in arguments
	for argument in arguments:
		if argument.begins_with("--junction-pattern="):
			junction_pattern = argument.trim_prefix("--junction-pattern=")
	_create_gate()
	if capture:
		_capture_gallery()

func _create_gate() -> void:
	world = World.new(Vector2i(20,20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_team_civilization(1,CIVILIZATIONS[group])
	var technologies := [101,11]
	if level >= 1:
		technologies.append_array([102,13])
	if level >= 2:
		technologies.append_array([103,14])
	for technology in technologies:
		world.apply_technology_commands(1,world.technology_system.complete_research(1,technology))
	gate = world.add_building(1,"gate",Vector2(10,10),1,true,{"gate_axis":axis})
	if show_walls:
		var piers := WallPlacement.connection_cells(gate)
		var along := Vector2i.RIGHT if axis == 0 else Vector2i.DOWN
		var normal := Vector2i.DOWN if axis == 0 else Vector2i.RIGHT
		for side in range(2):
			var step := along*(-1 if side == 0 else 1)
			if junction_pattern != "straight":
				step = normal*(1 if junction_pattern == "front" else -1)
			for distance in [1,2]:
				world.add_building(100+side*2+distance,"wall",Vector2(Vector2i(piers[side])+step*distance))
	queue_redraw()

func _process(delta: float) -> void:
	if capture:
		return
	world.gate_system.advance(delta)
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_C:
				group = (group+1)%5
				_create_gate()
			KEY_1,KEY_2,KEY_3:
				level = event.keycode-KEY_1
				_create_gate()
			KEY_TAB:
				axis = 1-axis
				_create_gate()
			KEY_W:
				show_walls = not show_walls
				_create_gate()
			KEY_SPACE:
				world.gate_system.set_mode([1],1,"open" if gate["gate_mode"] != "open" else "locked")
			KEY_ESCAPE:
				get_tree().quit()

func _project(position: Vector2) -> Vector2:
	return get_viewport_rect().size*Vector2(0.5,0.6)+Presentation.project(position-Vector2(10,10))*zoom

func _frame_info(kind: String, entity: Dictionary) -> Dictionary:
	return catalog.building_frame_info(entity,0) if kind == "building" else {}

func _draw() -> void:
	draw_rect(get_viewport_rect(),Color("#1b221e"))
	if world == null:
		return
	for y in range(-12,13):
		for x in range(-12,13):
			var texture: Texture2D = catalog.terrain_all_textures["grass"][posmod(x*3+y*5,8)]
			var point := _project(Vector2(10+x,10+y))-Vector2(32,16)*zoom
			draw_texture_rect(texture,Rect2(point,Vector2(65,33)*zoom),false)
	var drawables: Array = renderer.create_world_drawables({"buildings":world.get_buildings().map(func(building): return Contract.render(building))},Callable(self,"_project"),1.0,Callable(self,"_frame_info"))
	for item in drawables:
		var info: Dictionary = item["frame_info"]
		var screen: Vector2 = item["screen_position"]
		if info.has("gate_polygon"):
			draw_set_transform(screen,0,Vector2.ONE*zoom)
			draw_polygon(info["gate_polygon"],PackedColorArray([info.get("gate_color",Color.WHITE)]),info.get("gate_uv",PackedVector2Array()),info.get("texture"))
			draw_set_transform(Vector2.ZERO)
		elif info.get("texture") != null:
			screen += Vector2(info.get("screen_offset",Vector2.ZERO))*zoom
			draw_texture_rect(info["texture"],Rect2(screen-Vector2(info.get("hotspot",Vector2.ZERO))*zoom,info["texture"].get_size()*zoom),false)
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(0,0,get_viewport_rect().size.x,85),Color(0.1,0.13,0.11,0.92))
	draw_string(font,Vector2(24,32),"%s · %s стены · %s" % [GROUPS[group],["Малые","Средние","Укреплённые"][level],"Открыто" if float(gate["gate_open_fraction"]) > 0.9 else "Открывается" if float(gate["gate_open_fraction"]) > 0.1 else "Закрыто"],HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color.WHITE)
	draw_string(font,Vector2(24,64),"C — стиль · 1/2/3 — уровень · Tab — направление · Пробел — открыть/закрыть · W — стены · Esc — выход",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)

func _capture_gallery() -> void:
	var directory := "res://qa/gate-junctions/%s" % junction_pattern if show_walls else "res://qa/gates"
	var poses: Array = [0.0,0.5,1.0] if show_walls else [0.0,1.0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for next_group in range(5):
		group = next_group
		for next_level in range(3):
			level = next_level
			for next_axis in range(2):
				axis = next_axis
				_create_gate()
				for pose in poses:
					gate["gate_open_fraction"] = pose
					queue_redraw()
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var image := get_viewport().get_texture().get_image()
					image.save_png("%s/group-%d-level-%d-axis-%d-%s.png" % [directory,group,level,axis,"open" if pose > 0.9 else "moving" if pose > 0.1 else "closed"])
	print("Captured %d real renderer gate previews, walls=%s pattern=%s" % [30*poses.size(),show_walls,junction_pattern])
	get_tree().quit()
