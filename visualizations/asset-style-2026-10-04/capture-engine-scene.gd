extends SceneTree
# Art-direction fixture: runs the actual main scene and renderer. Does not change game resources.
const Definition = preload("res://scripts/match_definition.gd")
const SIZE = Vector2i(1920, 1080)
var fixture_directory = "D:/Develop/Rise of Rome/visualizations/asset-style-2026-10-04"
var entities: Array = []

func _initialize() -> void:
	call_deferred("capture")

func add_entity(category: String, kind: String, at: Vector2, team: int = 1, amount: int = 0, selected: bool = false) -> void:
	var entity = {"category": category, "kind": kind, "position": [at.x, at.y], "team": team}
	if category == "resource":
		entity["amount"] = amount
		entity["placement_validated"] = true
	if selected:
		entity["selected"] = true
	entities.append(entity)

func capture() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/matches/prototype_match.json"))
	raw["id"] = "art_direction_coastal_settlement"
	raw["title"] = "Визуальная сцена: прибрежное поселение"
	raw["start_message"] = ""
	raw["players"][0]["start"] = [31.0, 30.0]
	raw["players"][0]["population_limit"] = 75
	raw["players"][0]["starting_age_technology_id"] = 102
	raw["players"][0]["starting_resources"] = {"wood": 825, "food": 640, "gold": 350, "stone": 420}
	raw["players"][1]["start"] = [54.0, 54.0]
	raw["players"][1]["starting_age_technology_id"] = 102
	var terrain: Array = []
	var levels: Array = []
	terrain.resize(64 * 64)
	levels.resize(65 * 65)
	levels.fill(0)
	for y in range(64):
		var coast = 22 + roundi(sin(float(y) * 0.19) * 1.5)
		for x in range(64):
			terrain[y * 64 + x] = 1 if x < coast else 2 if x == coast else 0
	raw["map"] = {"size": [64, 64], "seed": 20261004, "generator": {"type": "fixed_source", "terrain_ids": terrain, "vertex_levels": levels}}
	for placement in [
		["town_center", 31.0, 30.0],
		["house", 26.5, 28.5], ["house", 29.8, 25.5], ["house", 33.5, 25.5],
		["storage_pit", 27.0, 24.2], ["granary", 26.8, 33.3],
		["barracks", 38.0, 30.5], ["market", 38.0, 25.0],
		["farm", 30.8, 35.0], ["farm", 34.0, 37.0], ["farm", 37.3, 37.0],
		["dock", 21.2, 37.0]
	]:
		add_entity("building", placement[0], Vector2(placement[1], placement[2]))
	for at in [Vector2(28.1,29.0), Vector2(29.0,31.0), Vector2(26.0,32.0), Vector2(30.0,34.1), Vector2(33.0,36.1), Vector2(36.3,36.1), Vector2(28.1,24.7), Vector2(23.2,36.0), Vector2(33.0,27.0)]:
		add_entity("unit", "villager", at)
	for row in range(2):
		for column in range(4):
			add_entity("unit", "archer" if row == 0 else "clubman", Vector2(34.0 + column * 0.65, 31.8 + row * 0.9), 1, 0, row == 0)
	add_entity("unit", "fishing_boat", Vector2(18.2,35.5))
	add_entity("unit", "scout_ship", Vector2(17.0,39.0))
	for row in range(4):
		for column in range(5):
			add_entity("resource", "tree", Vector2(25.0 + column * 0.75, 20.6 + row * 0.7), 0, 75)
	for row in range(4):
		for column in range(4):
			add_entity("resource", "tree", Vector2(40.6 + column * 0.8, 31.0 + row * 0.85), 0, 75)
	for i in range(4):
		add_entity("resource", "berries", Vector2(24.5 + (i % 2) * 0.65, 29.4 + (i / 2) * 0.7), 0, 150)
		add_entity("resource", "gold_mine", Vector2(37.0 + (i % 2) * 0.7, 20.5 + (i / 2) * 0.7), 0, 400)
		add_entity("resource", "stone_mine", Vector2(29.0 + (i % 2) * 0.75, 39.5 + (i / 2) * 0.7), 0, 250)
	add_entity("resource", "deep_fish", Vector2(18.0,32.5), 0, 250)
	add_entity("building", "town_center", Vector2(54,54), 2)
	add_entity("unit", "villager", Vector2(53,53), 2)
	raw["entities"] = entities
	var source_file = FileAccess.open(fixture_directory.path_join("engine-scene-definition.json"), FileAccess.WRITE)
	source_file.store_string(JSON.stringify(raw, "\t"))
	source_file.close()
	var definition = Definition.normalize(raw)
	if not bool(definition.get("valid", false)):
		push_error(str(definition.get("errors", [])))
		quit(1)
		return
	var viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	game.match_definition_override = definition
	viewport.add_child(game)
	game.game_controller.set_paused(true)
	game.set_process(false)
	if game.audio_player != null:
		game.audio_player.stop()
	for _frame in range(4):
		await process_frame
	var fog = game.simulation_world.fog_of_war
	fog.ensure_player(1)
	var cells: PackedByteArray = fog.states_by_player[1]
	cells.fill(2)
	fog.states_by_player[1] = cells
	fog.revision += 1
	fog.revisions_by_player[1] = int(fog.revisions_by_player[1]) + 1
	game.view_zoom = 1.5
	game.center_view_on_world(Vector2(30.3,30.3))
	game.message_time = 0
	game.cached_overview_tick = -1
	game.sync_world_state(true)
	game.refresh_hud_model()
	game.queue_redraw()
	for _frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var output_path = fixture_directory.path_join("engine-scene-source.png")
	var error = viewport.get_texture().get_image().save_png(output_path)
	print("Engine art-direction fixture saved: %s; result %s; entities %d" % [output_path, error_string(error), entities.size()])
	quit(0 if error == OK else 1)
