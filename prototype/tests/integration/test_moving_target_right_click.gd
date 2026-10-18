extends SceneTree

const Main := preload("res://main.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Geometry := preload("res://scripts/sprite_geometry.gd")
const Pixels := preload("res://scripts/pixel_scaling.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	var world = World.new(Vector2i(32,32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var attacker: Dictionary = world.add_unit(1,"clubman",Vector2(10,12),false)
	var target: Dictionary = world.add_unit(2,"archer",Vector2(14,12),false)
	world.assign_command_move([target],Vector2(20,12))
	for unused in range(8):
		world.update_units(0.05,1,2)
		world.rebuild_spatial_index(false)
	check(target["pos"] != Vector2(14,12),"enemy is actually moving before the click")
	var game = Main.new()
	game.resource_catalog = catalog
	game.render_world = Main.RenderWorld.new()
	game.simulation_world = world
	game.game_controller = Controller.new(world)
	game.local_player_team = 1
	game.map_size = world.map_size
	game.units = world.get_units().map(func(unit):return unit.duplicate(true))
	game.presentation_snapshot = {"units":game.units,"buildings":[],"resources":[]}
	var selected: Array[int] = [int(attacker["id"])]
	game.player_control_state.replace_or_add(selected,false)
	game.view_zoom = 2.0
	var point: Variant = transparent_body_point(game,int(target["id"]))
	check(point is Vector2,"actual moving archer frame has a transparent body-area pixel")
	if point is Vector2:
		game.issue_order(point)
		var queue: Array = game.game_controller.command_queue
		check(queue.size()==1 and queue[0].command_type()=="attack" and queue[0].target_entity_id==int(target["id"]),"right-click through a transparent sprite pixel issues attack on that enemy")
		game.game_controller.tick_index += 1
		game.game_controller.process_commands()
		check(attacker["task"]=="attack" and int(attacker["target_id"])==int(target["id"]),"attack reaches authoritative simulation with the moving target ID")
		var hp: float = target["hp"]
		world.stop_unit_motion(target)
		for unused in range(500):
			world.update_units(0.05,1,2)
			world.rebuild_spatial_index(false)
			if float(target["hp"]) < hp: break
		check(float(target["hp"]) < hp,"attacker follows the issued target and deals damage")
	game.free()
	for failure in failures: push_error(failure)
	print("Moving target right-click: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func transparent_body_point(game, id: int) -> Variant:
	for item in game.current_world_drawables():
		if item["kind"] != "unit" or int(item["stable_id"]) != id: continue
		var info: Dictionary = item["frame_info"]
		var texture: Texture2D = info.get("texture")
		if texture == null: continue
		var image := texture.get_image()
		var anchor: Vector2 = Pixels.snap_screen(game.world_to_screen(item["world_anchor"])) + Vector2(info.get("screen_offset",Vector2.ZERO))*game.view_zoom
		for y in range(image.get_height()/5,image.get_height()*3/5):
			for x in range(image.get_width()/5,image.get_width()*4/5):
				if image.get_pixel(x,y).a > 0.05: continue
				var point := Geometry.source_to_screen(Vector2(x+0.5,y+0.5),anchor,game.view_zoom,item["hotspot"],bool(info.get("mirrored",false)))
				if not game.picking_service.footprint_hit(point,"unit",item["data"],Callable(game,"world_to_screen"),game.view_zoom): return point
	return null

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
