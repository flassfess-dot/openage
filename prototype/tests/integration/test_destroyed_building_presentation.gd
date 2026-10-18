extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Render := preload("res://scripts/render_world.gd")
const Item := preload("res://scripts/render_item.gd")
var catalog
var failures: Array[String] = []

func _initialize() -> void:
	catalog = Catalog.new()
	catalog.load()
	for kind in ["farm","barracks","archery_range","town_center"]:
		var world = World.new(Vector2i(32,32))
		world.set_gamespec(catalog.gamespec_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		var building: Dictionary = world.add_building(900,kind,Vector2(15,15),2)
		var worker: Dictionary = world.add_unit(1,"villager",Vector2(14.8,14.8),false)
		world.begin_entity_death(building)
		world.advance_death_only(float(building["death_duration"])+0.1)
		world.rebuild_spatial_index(false)
		world.update_fog_of_war()
		var snapshot := Snapshot.presentation(world,0,1)
		check(snapshot["buildings"].any(func(actor):return int(actor["id"])==900),"visible enemy %s ruin reaches the observer snapshot" % kind)
		var frame: Dictionary = catalog.building_frame_info(building)
		check(frame.get("texture") != null or frame.get("composite_parts",[]).any(func(part):return part.get("texture") != null),"destroyed %s has visible artwork" % kind)
		for native in [false,true]:
			var renderer = Render.new()
			renderer.native_buildings_enabled = native
			var items: Array = renderer.create_world_drawables(snapshot,project,1.0,frame_info)
			var ruins := items.filter(func(item):return item["kind"] in ["building","building_part"] and int(item["stable_id"])==900)
			check(not ruins.is_empty(),"%s rubble remains rendered (native=%s)" % [kind,native])
			check(ruins.all(func(item):return int(item["layer"]) < Item.Layer.UNIT_BUILDING),"all %s rubble parts stay below a unit walking over them (native=%s)" % [kind,native])
		world.advance_death_only(9)
		world.purge_removed_units()
		check(world.find_building(900)==null,"%s ruin eventually expires through normal lifecycle" % kind)
	for failure in failures: push_error(failure)
	print("Destroyed building presentation: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func project(point: Vector2) -> Vector2:
	return Vector2((point.x-point.y)*32,(point.x+point.y)*16)

func frame_info(kind: String, actor: Dictionary) -> Dictionary:
	return catalog.building_frame_info(actor) if kind=="building" else catalog.unit_frame_info(actor,"idle") if kind=="unit" else {}

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
