extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Autosave := preload("res://scripts/background_autosave.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const DIRECTORY := "res://qa/audit-state-integrity"
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	var world := World.new(Vector2i(12,12))
	var controller := Controller.new(world)
	var replay := Replay.new()
	var terrain: Array = []
	terrain.resize(144)
	terrain.fill(0)
	world.configure_map_data({"terrain_ids":terrain})
	var before := replay.world_state_hash(world,0,controller)
	terrain[130]=1
	world.configure_map_data({"terrain_ids":terrain})
	check(replay.world_state_hash(world,0,controller)!=before,"terrain changes invalidate the deterministic hash")
	before=replay.world_state_hash(world,0,controller)
	world.terrain_elevation.river_shape={"model_version":0,"seed":7}
	check(replay.world_state_hash(world,0,controller)!=before,"river geometry participates in the hash")
	before=replay.world_state_hash(world,0,controller)
	world.set_gamespec({"units":{"villager":{"creation_time":99}}})
	check(replay.world_state_hash(world,0,controller)!=before,"rule catalogs participate in the hash")
	world.terrain_elevation.river_shape={}
	var resource := world.add_resource("tree",Vector2(9,9),100)
	var anchor := Autosave.state_anchor(world,controller)
	world.set_entity_field(resource,"amount",25)
	check(Autosave.state_anchor(world,controller)!=anchor,"autosave verification detects resource depletion")
	var unit := world.add_unit(1,"villager",Vector2(3,3),false)
	anchor=Autosave.state_anchor(world,controller)
	world.set_entity_field(unit,"path",[Vector2(4,4),Vector2(5,5)])
	check(Autosave.state_anchor(world,controller)!=anchor,"autosave verification detects path changes")
	anchor=Autosave.state_anchor(world,controller)
	world.get_fog_of_war().reveal_explored_cell(1,Vector2i(10,10))
	check(Autosave.state_anchor(world,controller)!=anchor,"autosave verification detects fog changes")
	anchor=Autosave.state_anchor(world,controller)
	world.technology_system.complete_research(1,114)
	check(Autosave.state_anchor(world,controller)!=anchor,"autosave verification detects technology state")
	world.static_obstructions.append({"pos":Vector2(1,1),"radius":0.5})
	world.static_obstructions.append({"pos":Vector2(2,2),"radius":0.5})
	anchor=Autosave.state_anchor(world,controller)
	world.static_obstructions[0]["radius"]=0.75
	check(Autosave.state_anchor(world,controller)!=anchor,"every obstruction contributes even without an entity ID")
	world.static_obstructions.clear()
	verify_atomic_archive(world,controller)
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Audit state integrity: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func verify_atomic_archive(world,controller) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var path := Archive.named_path("Recovery",DIRECTORY)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	controller.start_recording(41721,false)
	var definition := {"id":"audit-state"}
	var checkpoint := Checkpoint.pack(Checkpoint.capture(world,controller,definition,{"size":world.map_size}))
	var archive := Archive.create("res://data/matches/prototype_match.json",definition,0,"",controller.replay_recorder.to_dictionary(),[],{},{},"Recovery",checkpoint)
	check(Archive.write(path,archive)==OK,"manual save writes through atomic replacement")
	check(Archive.write(path,archive,false)==OK,"legacy false argument also preserves atomic replacement")
	check(not FileAccess.file_exists(path+".bak"),"manual replacement never creates a missing-file backup window")
	check(DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(path+".bak"))==OK,"interrupted legacy write fixture retains the committed backup")
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	file.store_string("{incomplete")
	file.close()
	check(bool(Archive.read(path).get("valid",false)),"missing primary recovers the previous complete backup")
	var entries := Archive.list_named_saves(DIRECTORY)
	check(entries.size()==1 and entries[0]["path"]==path,"load menu discovers a recovered named save at its stable path")
	check(Archive.list_saves(DIRECTORY.path_join("none"),path,DIRECTORY.path_join("missing")).size()==1,"quick-save discovery also recovers a backup")
	check(Archive.write(path,archive)==OK and bool(Archive.read(path).get("valid",false)),"a recovered slot can be overwritten and loaded normally")
	check(Archive.list_named_saves(DIRECTORY).size()==1,"an old backup never duplicates an existing committed slot")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
