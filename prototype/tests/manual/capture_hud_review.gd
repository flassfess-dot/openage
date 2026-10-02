extends SceneTree

const Definition := preload("res://scripts/match_definition.gd")
const Layout := preload("res://scripts/interface_layout.gd")

func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: PackedScene = load("res://main.tscn")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa/hud-review"))
	for civilization in [13, 1, 2, 3, 10]:
		var game = scene.instantiate()
		var definition := Definition.load_json()
		definition["players"][0]["civilization_id"] = civilization
		game.match_definition_override = definition
		viewport.add_child(game)
		await process_frame
		await process_frame
		game.game_controller.set_paused(true)
		game.set_process(false)
		var world = game.simulation_world
		for type_id in [0, 1, 2, 3]: world.set_resource_amount(1, type_id, 1000 if type_id < 2 else 200)
		world.grant_technology(1, 101)
		world.grant_technology(1, 39)
		var pit: Dictionary = world.add_building(9900, "storage_pit", Vector2(10, 12), 1)
		world.add_building(9901, "town_center", Vector2(14, 17), 1)
		world.enqueue_research(9900, 1, 46)
		world.enqueue_research(9900, 1, 40)
		world.enqueue_research(9900, 1, 41)
		for _index in range(3): world.enqueue_unit_production(9901, 1, "villager")
		world.update_production(20)
		world.update_fog_of_war()
		game.select_hud_building(9900)
		game.message_time = 0
		for width in [1280, 800, 640] if civilization == 13 else [1280]:
			viewport.size = Vector2i(width, 720)
			game.hud_controls.size = Vector2(width, 720)
			game.hud_controls.set_layout(Layout.for_viewport(Vector2(width, 720)))
			game.top_bar_controls.set_viewport_size(Vector2(width, 720))
			game.center_view_on_world(Vector2(10, 12))
			game.sync_world_state()
			game.refresh_hud_model()
			game.queue_redraw()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var path := "res://qa/hud-review/civ-%d-%d.png" % [civilization, width]
			var error := image.save_png(path)
			print("HUD capture: %s, error %d" % [path, error])
		game.free()
	viewport.free()
	quit(0)