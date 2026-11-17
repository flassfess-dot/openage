extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Replay := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	for wire in [false, true]:
		verify_mixed_ownership(wire)
	var catalog := Catalog.new()
	catalog.load_generated_data()
	verify_production(catalog)
	for failure in failures: push_error(failure)
	print("Audit command boundaries: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func verify_mixed_ownership(wire: bool) -> void:
	var world := World.new(Vector2i(24,24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var own := world.add_unit(1,"villager",Vector2(5,5),false)
	var enemy := world.add_unit(2,"villager",Vector2(19,19),false)
	world.append_entity_queued_order(enemy,{"type":"move","tick":1,"issuer_id":2,"sequence_id":9,"unit_ids":[int(enemy["id"])],"params":{"target":{"__vector2":[18,18]}}})
	enemy["boarding_position"] = Vector2(20,20)
	enemy["combat_pursuit"] = true
	var before := enemy.duplicate(true)
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var command = Commands.MoveCommand.new(1,[int(own["id"]),int(enemy["id"])],Vector2(9,9))
	if wire:
		command = Replay.new().command_from_record({"tick":1,"issuer_id":1,"sequence_id":1,"type":"move","unit_ids":command.unit_ids,"params":{"target":{"__vector2":[9,9]}}})
	controller.enqueue_command(command,false,1)
	controller.tick_index=1
	controller.process_commands()
	check(bool(controller.get_command_result(command.sequence_id).get("accepted",false)),"own movement is accepted, wire=%s" % wire)
	check(enemy == before,"all enemy state survives mixed command cleanup, wire=%s" % wire)
	check(String(own["task"])=="move","own unit receives its move")
	for _step in range(100): controller.advance_frame(0.05,1,2)
	check(Vector2(own["pos"]).distance_to(Vector2(9,9))<0.8,"own unit reaches the requested destination")
	world.shutdown_derived_state()

func verify_production(catalog) -> void:
	var world := World.new(Vector2i(24,24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var center := world.add_building(700,"town_center",Vector2(6,6),1)
	world.add_unit(2,"clubman",Vector2(21,21),false)
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	for ids in [[700],[]]:
		var typed_ids: Array[int] = []
		typed_ids.assign(ids)
		var command = Commands.TrainCommand.new(1,typed_ids,"clubman",1,Vector2(9,9))
		controller.enqueue_command(command,false,1)
		controller.tick_index=1
		controller.process_commands()
		check(not bool(controller.get_command_result(command.sequence_id).get("accepted",false)),"wrong/missing producer cannot bypass unit availability")
	check(center["production_queue"].is_empty() and world.get_food()==180,"rejected training changes neither queue nor stockpile")
	var barracks := world.add_building(701,"barracks",Vector2(15,6),1)
	var command = Commands.TrainCommand.new(2,[],"clubman",1,Vector2(15,10))
	controller.enqueue_command(command,false,1)
	controller.advance_frame(0.05,1,2)
	check(bool(controller.get_command_result(command.sequence_id).get("accepted",false)),"automatic selection still accepts a legal producer")
	check(center["production_queue"].is_empty() and barracks["production_queue"].size()==1,"automatic training selects the barracks")
	for _step in range(540): controller.advance_frame(0.05,1,2)
	check(world.get_units().any(func(unit):return int(unit.get("team",0))==1 and String(unit.get("kind",""))=="clubman"),"accepted production creates the requested unit")
	world.shutdown_derived_state()
