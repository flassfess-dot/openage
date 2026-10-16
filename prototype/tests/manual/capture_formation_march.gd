extends SceneTree

const Definition := preload("res://scripts/match_definition.gd")
const Geometry := preload("res://scripts/formation_geometry.gd")
const Commands := preload("res://scripts/commands.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")

func _initialize() -> void:
	var terrain: Array[int] = []
	for y in range(40):
		for x in range(48): terrain.append(1 if x in range(23, 26) and y != 20 else 0)
	var heights: Array[int] = []
	heights.resize(49 * 41)
	heights.fill(0)
	var entities: Array = []
	for position in Geometry.world_slots(Geometry.local_slots(36, Geometry.LINE), Vector2(9.5, 20.5), Vector2.RIGHT):
		entities.append({"category": "unit", "team": 1, "kind": "clubman", "position": [position.x, position.y], "selected": true})
	entities.append({"category": "unit", "team": 2, "kind": "clubman", "position": [45, 37]})
	var definition := Definition.normalize({"id": "formation_march_capture", "title": "Formation march", "map": {"size": [48, 40], "seed": 17017, "generator": {"type": "fixed_source", "terrain_ids": terrain, "vertex_levels": heights}}, "players": [{"team": 1, "controller": "human", "civilization_id": 13, "start": [9, 20], "population_housing": 100}, {"team": 2, "controller": "ai", "civilization_id": 13, "start": [45, 37], "ai": {"enabled": false}}], "entities": entities, "victory_rules": [{"type": "conquest"}]})
	if not definition["valid"]:
		push_error(str(definition["errors"]))
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_definition_override = definition
	viewport.add_child(game)
	for frame in range(6): await process_frame
	if not await MatchReady.wait_for_ready(self, game):
		quit(1)
		return
	game.set_process(false)
	game.game_controller.set_speed_multiplier(1.0)
	var ids: Array[int] = []
	for unit in game.simulation_world.get_units():
		unit["stance"] = "passive"
		if int(unit["team"]) == 1: ids.append(int(unit["id"]))
	for y in range(40):
		for x in range(48): game.simulation_world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	game.game_controller.enqueue_command(Commands.FormationMoveCommand.new(game.game_controller.tick_index + 1, ids, Vector2(38.5, 20.5), Geometry.LINE, Vector2.RIGHT))
	for tick in range(1400):
		game.game_controller.advance_frame(0.05, 1, 2)
		if tick == 300: await capture(game, viewport, "res://qa/formations-20261017/march.png", Vector2(24, 20))
		if tick % 100 == 0: await process_frame
		if tick > 300 and ids.all(func(id): return game.simulation_world.find_unit(id)["task"] == "idle"): break
	await capture(game, viewport, "res://qa/formations-20261017/deployed.png", Vector2(38.5, 20.5))
	var arrived: int = ids.filter(func(id):
		var unit: Dictionary = game.simulation_world.find_unit(id)
		return unit.get("formation_home") != null and Vector2(unit["pos"]).distance_to(unit["formation_home"]) < 0.04).size()
	print("Graphical formation march: %d/%d arrived" % [arrived, ids.size()])
	game.free()
	quit(0 if arrived == ids.size() else 1)

func capture(game, viewport: SubViewport, output: String, center: Vector2) -> void:
	game.view_zoom = 0.8
	game.center_view_on_world(center)
	game.sync_world_state()
	game._sync_terrain_canvas()
	game.queue_redraw()
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image().save_png(output)
	if result != OK: push_error("Formation capture failed: %s" % error_string(result))
