extends SceneTree
# Uses the actual game's draw order, sprites, terrain and fog. Only the HUD and
# autonomous simulation are disabled, to make visual fixtures deterministic.
class Fixture extends "res://main.gd":
 func _ready() -> void: pass
 func _process(_delta: float) -> void: pass
 func draw_hud() -> void: pass

var catalog = preload("res://scripts/resource_catalog.gd").new()
var game
var viewport: SubViewport
var output := "res://qa/visual-fixes-20261003"
func _initialize() -> void:
 call_deferred("capture")
func capture() -> void:
 catalog.load()
 catalog.enable_environment_pack()
 viewport = SubViewport.new()
 viewport.size = Vector2i(1100,720)
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 root.add_child(viewport)
 game = Fixture.new()
 game.resource_catalog = catalog
 game.render_world = preload("res://scripts/render_world.gd").new()
 game.simulation_world = preload("res://scripts/simulation_world.gd").new(Vector2i(40,40))
 game.map_size = Vector2i(40,40)
 game.simulation_world.set_gamespec(catalog.gamespec_data)
 game.simulation_world.set_object_catalog(catalog.object_catalog_data)
 game.simulation_world.set_runtime_catalog(catalog.runtime_catalog_data)
 game.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
 game.view_zoom = 2.0
 viewport.add_child(game)
 game.terrain_canvas = preload("res://scripts/terrain_canvas.gd").new()
 game.terrain_canvas.z_index = -100
 game.terrain_canvas.async_rebuilds = false
 game.add_child(game.terrain_canvas)
 game.terrain_canvas.configure(game.map_size,41,catalog,game.simulation_world,func(_p): return 0,func(): return Rect2i(Vector2i.ZERO,game.map_size))
 game.view_offset = Vector2(550,300)-game.simulation_world.terrain_elevation.world_to_screen(Vector2(10,10),game.view_zoom,Vector2.ZERO)
 var cells := PackedByteArray()
 cells.resize(40*40)
 cells.fill(2)
 game.presentation_snapshot = {"tick": 0,"units": [],"buildings": [],"resources": [],"environment": [],"fog": {"cells": cells},"fog_revision":0}
 var farms := []
 var workers := []
 for offset in [Vector2(-3,-3),Vector2(2,-3),Vector2(-3,2),Vector2(2,2)]:
  var at: Vector2 = Vector2(10,10)+offset
  var farm: Dictionary = game.simulation_world.add_building(1,"farm",at)
  farm["amount"] = 250
  farms.append(farm)
  var relative: Vector2 = Vector2(-.4,-.4) if farms.size()<=2 else Vector2(.5,.5)
  var worker: Dictionary = game.simulation_world.add_unit(1,"villager",at+relative,false)
  worker["presentation_state_overrides"] = {"Gather":"farmer_work"}
  worker["anim_state"] = "Gather"
  worker["anim"] = 0.0
  worker["facing"] = 3
  workers.append(worker)
 game.presentation_snapshot["buildings"] = farms
 game.presentation_snapshot["units"] = workers
 await save_frame("farm-depth.png")
 # Trees at both back edges of the map, under full visibility and explored fog.
 game.presentation_snapshot["buildings"] = []
 game.presentation_snapshot["units"] = []
 var trees := []
 for y in range(2,14):
  var tree: Dictionary = game.simulation_world.add_resource("tree",Vector2(.45,y+.5),75)
  tree["environment_asset"] = "pine"
  tree["environment_variant"] = y%3
  trees.append(tree)
 game.presentation_snapshot["resources"] = trees
 game.view_offset = Vector2(550,360)-game.simulation_world.terrain_elevation.world_to_screen(Vector2(0,8),game.view_zoom,Vector2.ZERO)
 await save_frame("map-edge-visible.png")
 cells.fill(1)
 game.presentation_snapshot["fog_revision"] = 1
 game.presentation_snapshot["fog"]["cells"] = cells
 await save_frame("map-edge-explored.png")
 game.presentation_snapshot["resources"] = []
 cells.fill(2)
 game.presentation_snapshot["fog_revision"] = 2
 game.presentation_snapshot["fog"]["cells"] = cells
 game.simulation_world.map_terrain_ids.clear()
 for y in range(40):
  for x in range(40): game.simulation_world.map_terrain_ids[Vector2i(x,y)]=1
 game.simulation_world.terrain_revision += 1
 game.terrain_canvas.configure(game.map_size,41,catalog,game.simulation_world,func(_p):return 1,func():return Rect2i(Vector2i.ZERO,game.map_size))
 game.view_zoom = 2.0
 game.view_offset = Vector2(550,440)-game.simulation_world.terrain_elevation.world_to_screen(Vector2(10,10),game.view_zoom,Vector2.ZERO)
 var ships := []
 for i in range(8):
  var at := Vector2(10,10)+Vector2((i%4-1.5)*2.2,(i/4-.5)*3.2)
  var ship: Dictionary = game.simulation_world.add_unit(1 if i<4 else 2,"scout_ship",at,false)
  ship["pos"] = at
  ship["previous_pos"] = at
  ship["source_unit_id"] = 20
  ship["texture_key"] = "scout_ship#20" if i<4 else "enemy_scout_ship#20"
  ship["facing"] = i
  ship["anim_state"] = "Move"
  ship["anim"] = 0.0
  ships.append(ship)
 game.presentation_snapshot["units"] = ships
 for f in range(8):
  for ship in ships: ship["anim"] = f*.14
  await save_frame("galley-%02d.png" % f)
 game.queue_free()
 await process_frame
 # A generated ridge uses its native ground blend and source centreline.
 var scene = load("res://random_map_preview.tscn").instantiate()
 viewport.add_child(scene)
 scene.seed_input.value = 41689
 for i in range(scene.profiles.size()):
  if scene.profiles[i]["id"]=="hill_country":scene.profile_choice.select(i)
 scene.generate_map()
 var cliffs: Array = scene.generated["map_data"]["cliff_obstructions"]
 var at: Vector2 = cliffs[cliffs.size()/2]["position"]
 scene.zoom = 2.0
 scene.view_offset = Vector2(550,360)-scene.elevation.world_to_screen(at,scene.zoom,Vector2.ZERO)
 scene._refresh(false)
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 viewport.get_texture().get_image().save_png(output.path_join("cliff-ground-transition.png"))
 print("Visual fixtures captured in "+output)
 quit()
func save_frame(name: String) -> void:
 game.presentation_revision += 1
 game._sync_terrain_canvas()
 game.queue_redraw()
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 var err := viewport.get_texture().get_image().save_png(output.path_join(name))
 if err!=OK: push_error(error_string(err))