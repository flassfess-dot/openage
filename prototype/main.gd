extends Node2D

const Coordinates := preload("res://scripts/coordinates.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const GameController := preload("res://scripts/game_controller.gd")
const RoRCommands = preload("res://scripts/commands.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const Diagnostics := preload("res://scripts/diagnostics.gd")
const InputAdapter := preload("res://scripts/input_adapter.gd")
const PickingService := preload("res://scripts/picking_service.gd")
const CommandFeedbackRouter := preload("res://scripts/command_feedback_router.gd")
const CommandMarkerPresentation := preload("res://scripts/command_marker_presentation.gd")
const InteractionCursor := preload("res://scripts/interaction_cursor.gd")
const PlayerControlState := preload("res://scripts/player_control_state.gd")
const ControlGroups := preload("res://scripts/control_groups.gd")
const ContextResolver := preload("res://scripts/context_resolver.gd")
const HUDControls := preload("res://scripts/hud_controls.gd")
const TopBarControls := preload("res://scripts/top_bar_controls.gd")
const HUDModalOverlay := preload("res://scripts/hud_modal_overlay.gd")
const HudViewModel := preload("res://scripts/hud_view_model.gd")
const PresentationAudioRouter := preload("res://scripts/presentation_audio_router.gd")
const PresentationAudioEventRouter := preload("res://scripts/presentation_audio_event_router.gd")
const PresentationEffectTimeline := preload("res://scripts/presentation_effect_timeline.gd")
const MinimapProjection := preload("res://scripts/minimap_projection.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")
const AiPlayer := preload("res://scripts/ai_player.gd")
const SpriteGeometry := preload("res://scripts/sprite_geometry.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")
const TerrainRenderer := preload("res://scripts/terrain_renderer.gd")
const ScenarioOverlay := preload("res://scripts/scenario_overlay.gd")
const ViewportCulling := preload("res://scripts/viewport_culling.gd")
const TerrainCanvas := preload("res://scripts/terrain_canvas.gd")
const EnvironmentPresentationField := preload("res://scripts/environment_presentation_field.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const FogPresentation := preload("res://scripts/fog_presentation.gd")
const InterfaceLayout := preload("res://scripts/interface_layout.gd")
const MAP_SEED := 41721
const FormationPreview := preload("res://scripts/formation_preview.gd")
const TILE_WIDTH := Coordinates.TILE_WIDTH
const TILE_HEIGHT := Coordinates.TILE_HEIGHT
const MAP_SIZE := Vector2i(24, 24)
const PLAYER_TEAM := 1
const ENEMY_TEAM := 2
const HUD_TOP := InterfaceLayout.TOP_HEIGHT
const HUD_BOTTOM := InterfaceLayout.BOTTOM_HEIGHT

@export_file("*.json") var match_path: String = MatchDefinition.DEFAULT_PATH

var view_offset := Vector2.ZERO
var view_zoom := 1.0
var map_size := MAP_SIZE
var map_seed := MAP_SEED
var match_definition: Dictionary = {}
var map_definition: Dictionary = {}
var ai_players: Array = []
var input_adapter := InputAdapter.new()
var picking_service := PickingService.new()
var selection_preview_ids: Array[int] = []
var command_feedback_router := CommandFeedbackRouter.new()
var command_marker_presentation := CommandMarkerPresentation.new()
var interaction_highlight_id: int = -1
var interaction_cursor_semantic := "default"
var control_groups := ControlGroups.new()
var player_control_state := PlayerControlState.new(PLAYER_TEAM)

var units: Array = []
var resource_nodes: Array = []
var presentation_snapshot: Dictionary = {}
var formation := "RECTANGLE"
var pending_build_kind := ""
var pending_target_command := ""
var game_message := "Выберите отряд и отдайте приказ правой кнопкой"
var message_time := 5.0
var battle_over := false
var diagnostics_enabled := false

var terrain_textures := {}
var terrain_border_textures := {}
var tree_texture: Texture2D
var berry_texture: Texture2D
var interface_panel_texture: Texture2D
var health_status_frames: Array[Texture2D] = []
var unit_textures := {}
var gamespec_data: Dictionary = {}
var audio_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_round_robin: int = 0
var presentation_audio_router := PresentationAudioRouter.new()
var presentation_audio_event_router := PresentationAudioEventRouter.new()
var presentation_effect_timeline := PresentationEffectTimeline.new()
var environment_presentation_field := EnvironmentPresentationField.new()
var font: Font

var resource_catalog: ResourceCatalog
var simulation_world: SimulationWorld
var game_controller: GameController
var render_world: RenderWorld
var hud_controls: HUDControls
var top_bar_controls: TopBarControls
var hud_modal_overlay: HUDModalOverlay
var modal_restore_paused := false
var last_save_error := ""
var hud_view_model := HudViewModel.new()
var hud_model: Dictionary = {}
var scenario_overlay: ScenarioOverlay
var terrain_canvas: TerrainCanvas
var cached_fog_revision: int = -1
var cached_fog_runs: Array = []

func _ready() -> void:
	font = ThemeDB.fallback_font
	resource_catalog = ResourceCatalog.new()
	resource_catalog.load()
	match_definition = MatchDefinition.load_json(match_path)
	if not bool(match_definition.get("valid", false)):
		push_error("Invalid match definition: %s" % [str(match_definition.get("errors", []))])
		return
	var environment_items: Array = match_definition.get("presentation_environment", []).duplicate(true)
	environment_items.append_array(match_definition.get("static_obstructions", []))
	environment_presentation_field.configure(environment_items)
	map_definition = RandomMapGenerator.generate(match_definition)
	map_size = map_definition.get("size", MAP_SIZE)
	map_seed = int(map_definition.get("seed", MAP_SEED))

	gamespec_data = resource_catalog.gamespec_data
	terrain_textures = resource_catalog.terrain_textures
	terrain_border_textures = resource_catalog.terrain_border_textures
	tree_texture = resource_catalog.tree_texture
	berry_texture = resource_catalog.berry_texture
	interface_panel_texture = resource_catalog.interface_panel_texture
	var status_candidate: Dictionary = resource_catalog.interface_skin.status_candidate()
	if resource_catalog.interface_skin.is_unit_health(status_candidate):
		for texture_value in status_candidate.get("frames", []):
			health_status_frames.append(texture_value)
	unit_textures = resource_catalog.unit_textures

	simulation_world = _new_simulation_world()
	game_controller = GameController.new(simulation_world)
	render_world = RenderWorld.new()
	terrain_canvas = TerrainCanvas.new()
	terrain_canvas.z_index = -100
	add_child(terrain_canvas)
	terrain_canvas.configure(map_size, map_seed, resource_catalog, simulation_world, Callable(self, "terrain_id_at_cell"), Callable(self, "visible_tile_bounds"))
	hud_view_model.configure(resource_catalog.runtime_catalog_data, resource_catalog.localization, resource_catalog.object_catalog_data)
	hud_controls = HUDControls.new()
	add_child(hud_controls)
	hud_controls.configure_icons(resource_catalog.interface_icons)
	hud_controls.configure_interface_skin(resource_catalog.interface_skin, 0)
	hud_controls.position = Vector2.ZERO
	hud_controls.size = get_viewport_rect().size
	hud_controls.formation_requested.connect(set_formation)
	hud_controls.build_requested.connect(begin_build_placement)
	hud_controls.train_requested.connect(train_unit_from_hud)
	hud_controls.research_requested.connect(research_from_hud)
	hud_controls.cancel_production_requested.connect(cancel_production_from_hud)
	hud_controls.trade_resource_requested.connect(set_trade_resource_from_hud)
	hud_controls.unit_action_requested.connect(issue_unit_action)
	top_bar_controls = TopBarControls.new()
	add_child(top_bar_controls)
	top_bar_controls.configure(resource_catalog.interface_skin, 0)
	top_bar_controls.set_viewport_size(get_viewport_rect().size)
	top_bar_controls.diplomacy_requested.connect(_show_diplomacy_summary)
	top_bar_controls.menu_requested.connect(_toggle_game_menu)
	hud_modal_overlay = HUDModalOverlay.new()
	add_child(hud_modal_overlay)
	hud_modal_overlay.configure(resource_catalog.interface_skin, match_definition, 0, resource_catalog.localization)
	hud_modal_overlay.set_viewport_size(get_viewport_rect().size)
	hud_modal_overlay.close_requested.connect(_close_hud_modal)
	hud_modal_overlay.save_requested.connect(_save_quick_game)
	hud_modal_overlay.load_requested.connect(_load_quick_game)
	hud_modal_overlay.resign_requested.connect(_resign_from_hud_modal)
	hud_modal_overlay.launcher_requested.connect(_return_to_launcher)
	scenario_overlay = ScenarioOverlay.new()
	add_child(scenario_overlay)
	scenario_overlay.configure(match_definition, resource_catalog.localization, resource_catalog.object_catalog_data)
	scenario_overlay.restart_requested.connect(_restart_from_scenario_overlay)
	scenario_overlay.menu_requested.connect(_return_to_launcher)

	reset_game()
	setup_audio()
	setup_sfx()
	get_viewport().size_changed.connect(center_initial_view)
	center_initial_view()
func unit_stats(kind: String) -> Dictionary:
	if simulation_world == null:
		return gamespec_data.get("units", {}).get(kind, {})
	return simulation_world.unit_stats(kind)


func _new_simulation_world():
	var world = SimulationWorld.new(map_size)
	world.set_gamespec(gamespec_data)
	world.set_terrain_catalog(resource_catalog.terrain_catalog_data)
	world.set_object_catalog(resource_catalog.object_catalog_data)
	world.set_graphics_catalog(resource_catalog.graphics_catalog_data)
	world.set_runtime_catalog(resource_catalog.runtime_catalog_data)
	return world

func setup_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	var music = load("res://assets/audio/xmusic1.mp3")
	if music != null:
		music.loop = true
		audio_player.stream = music
		audio_player.volume_db = -18.0
		add_child(audio_player)
		audio_player.play()

func setup_sfx() -> void:
	sfx_players.clear()
	for _index in range(8):
		var player := AudioStreamPlayer.new()
		player.volume_db = -5.0
		add_child(player)
		sfx_players.append(player)
	sfx_player = sfx_players[0]
	presentation_audio_router.configure(resource_catalog.runtime_catalog_data, resource_catalog.sound_catalog_data, resource_catalog.asset_records, resource_catalog.graphics_catalog_data, resource_catalog.object_catalog_data)
	presentation_audio_event_router.configure(presentation_audio_router)
	presentation_effect_timeline.configure(resource_catalog.effect_presentations)

func play_sfx(name: String) -> void:
	var parts := name.split(":", false, 1)
	if parts.size() != 2:
		return
	var request: Dictionary = presentation_audio_router.request(String(parts[1]), String(parts[0]))
	play_audio_request(request)


func play_audio_request(request: Dictionary) -> void:
	if not bool(request.get("accepted", false)) or sfx_players.is_empty():
		return
	var player: AudioStreamPlayer
	for candidate in sfx_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = sfx_players[sfx_round_robin % sfx_players.size()]
		sfx_round_robin += 1
	player.stream = request["stream"]
	player.play()

func center_initial_view() -> void:
	var size := get_viewport_rect().size
	if hud_controls != null:
		hud_controls.position = Vector2.ZERO
		hud_controls.size = size
		hud_controls.set_layout(InterfaceLayout.for_viewport(size))
	if top_bar_controls != null:
		top_bar_controls.set_viewport_size(size)
	if hud_modal_overlay != null:
		hud_modal_overlay.set_viewport_size(size)
	if scenario_overlay != null:
		scenario_overlay.position = Vector2.ZERO
		scenario_overlay.size = size
	var initial_world := Vector2(map_size.x / 2.0, map_size.y / 2.0)
	var local_team := int(match_definition.get("local_team", PLAYER_TEAM))
	for player_value in match_definition.get("players", []):
		var player: Dictionary = player_value
		if int(player.get("team", 0)) == local_team:
			initial_world = player.get("start", initial_world)
			break
	var initial_screen := iso_raw(initial_world) * view_zoom
	view_offset = Vector2(size.x * 0.5, (size.y - HUD_BOTTOM + HUD_TOP) * 0.48) - initial_screen
	_sync_terrain_canvas()
	queue_redraw()

func reset_game() -> void:
	if simulation_world == null:
		return
	var bootstrap: Dictionary = MatchBootstrap.apply(simulation_world, match_definition, map_definition)
	game_controller.reset_timing()
	game_controller.start_recording(map_seed, false)
	configure_ai_players()
	control_groups.clear()
	player_control_state.clear()
	input_adapter.reset()
	command_feedback_router.reset()
	presentation_effect_timeline.reset()
	cached_fog_revision = -1
	cached_fog_runs.clear()
	command_marker_presentation.reset()
	interaction_highlight_id = -1
	interaction_cursor_semantic = "default"
	units.clear()
	resource_nodes.clear()

	formation = "RECTANGLE"
	pending_build_kind = ""
	pending_target_command = ""
	player_control_state.replace_or_add(bootstrap.get("selected_ids", []), false)

	sync_world_state()
	if scenario_overlay != null:
		scenario_overlay.reset_presentation()
		scenario_overlay.set_snapshot(presentation_snapshot)
	if hud_modal_overlay != null:
		hud_modal_overlay.close()
	game_message = String(bootstrap.get("message", "Матч начат"))
	message_time = 7.0
	queue_redraw()

func add_unit(team: int, kind: String, position: Vector2, selected: bool) -> Dictionary:
	if simulation_world == null:
		return {"id": -1}
	var unit: Dictionary = simulation_world.add_unit(team, kind, position, false)
	if selected and team == PLAYER_TEAM:
		player_control_state.replace_or_add([int(unit["id"])], true)
	return unit

func add_resource(kind: String, position: Vector2, amount: int) -> void:
	if simulation_world == null:
		return
	simulation_world.add_resource(kind, position, amount)
func _process(delta: float) -> void:
	presentation_audio_router.advance(delta)
	presentation_effect_timeline.advance(delta)
	_sync_effect_snapshot()
	if scenario_overlay != null and scenario_overlay.is_blocking():
		return
	if hud_modal_overlay != null and hud_modal_overlay.is_blocking():
		return
	update_camera(delta)
	_sync_terrain_canvas()
	update_units(delta)
	if message_time > 0.0:
		message_time -= delta
	command_marker_presentation.advance(delta)
	queue_redraw()

func update_camera(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y -= 1.0
	if direction != Vector2.ZERO:
		view_offset += direction.normalized() * 430.0 * delta

func update_units(delta: float) -> void:
	if game_controller == null or simulation_world == null:
		return
	queue_ai_commands()
	var battle_text := game_controller.advance_frame(delta, PLAYER_TEAM, ENEMY_TEAM)
	sync_world_state()
	process_presentation_events()
	if battle_text != "":
		game_message = battle_text
		message_time = 2.0


func configure_ai_players() -> void:
	ai_players = _new_ai_players()


func _new_ai_players() -> Array:
	var result: Array = []
	for player_value in match_definition.get("players", []):
		var player: Dictionary = player_value
		if String(player.get("controller", "ai")) == "ai":
			var ai := AiPlayer.new(player)
			if ai.enabled:
				result.append(ai)
	return result


func queue_ai_commands() -> void:
	var next_tick := game_controller.tick_index + 1
	for ai_value in ai_players:
		var ai = ai_value
		if not ai.needs_decision(next_tick):
			continue
		var knowledge := SimulationSnapshot.presentation(simulation_world, game_controller.tick_index, int(ai.team), ai.presentation_options())
		for command in ai.collect_commands(knowledge, next_tick):
			game_controller.enqueue_command(command, true, int(ai.team))


func enqueue_with_feedback(command: Variant, accepted_message: String, sound_name: String, marker: Variant = null) -> void:
	game_controller.enqueue_command(command, true, PLAYER_TEAM)
	command_feedback_router.register(command, accepted_message, sound_name, marker)


func process_presentation_events() -> void:
	var new_events := game_controller.events_after(command_feedback_router.event_cursor)
	for feedback in command_feedback_router.consume(new_events, PLAYER_TEAM):
		game_message = String(feedback["message"])
		if bool(feedback["accepted"]):
			var sound_name := String(feedback["sound_name"])
			if not sound_name.is_empty():
				play_sfx(sound_name)
			if feedback["marker"] is Vector2:
				command_marker_presentation.trigger(feedback["marker"])
		message_time = 1.8
	presentation_effect_timeline.consume(new_events, Callable(self, "presentation_effect_visible"))
	_sync_effect_snapshot()
	process_world_audio_events(new_events)


func process_world_audio_events(events: Array) -> void:
	for request in presentation_audio_event_router.consume(events, Callable(self, "presentation_entity_by_id"), Callable(self, "presentation_audio_state"), Callable(self, "presentation_event_visible")):
		play_audio_request(request)


func presentation_effect_visible(position: Vector2) -> bool:
	return presentation_fog_state_at(position) == FogOfWar.VISIBLE


func presentation_event_visible(payload: Dictionary) -> bool:
	var position_value: Variant = payload.get("position")
	if position_value is Vector2:
		return presentation_effect_visible(position_value)
	if position_value is Array and position_value.size() >= 2:
		return presentation_effect_visible(Vector2(float(position_value[0]), float(position_value[1])))
	return true


func _sync_effect_snapshot() -> void:
	if not presentation_snapshot.is_empty():
		presentation_snapshot["effects"] = presentation_effect_timeline.snapshot()


func presentation_audio_state(entity: Dictionary) -> String:
	return resource_catalog.unit_presentation_state(entity, String(entity.get("anim_state", "idle")))


func presentation_entity_by_id(entity_id: int) -> Dictionary:
	for category in ["units", "buildings"]:
		for entity_value in presentation_snapshot.get(category, []):
			var entity: Dictionary = entity_value
			if int(entity.get("id", -1)) == entity_id:
				return entity
	return {}

func find_unit(id: int):
	if simulation_world == null:
		for unit in units:
			if unit["id"] == id:
				return unit
		return null
	return simulation_world.find_unit(id)

func find_resource(id: int):
	if simulation_world == null:
		for resource in resource_nodes:
			if resource["id"] == id:
				return resource
		return null
	return simulation_world.find_resource(id)

func iso_raw(world: Vector2) -> Vector2:
	return Coordinates.iso_raw(world)

func world_to_screen(world: Vector2) -> Vector2:
	if simulation_world != null:
		return simulation_world.terrain_elevation.world_to_screen(world, view_zoom, view_offset)
	return Coordinates.world_to_screen(world, view_zoom, view_offset)

func screen_to_world(screen: Vector2) -> Vector2:
	if simulation_world != null:
		return simulation_world.terrain_elevation.screen_to_world(screen, view_zoom, view_offset)
	return Coordinates.screen_to_world(screen, view_zoom, view_offset)

func _unhandled_input(event: InputEvent) -> void:
	if hud_modal_overlay != null and hud_modal_overlay.is_blocking():
		return
	if scenario_overlay != null and scenario_overlay.is_blocking():
		return
	if handle_minimap_input(event):
		get_viewport().set_input_as_handled()
		return
	var in_world_area := true
	if event is InputEventMouseButton:
		in_world_area = is_world_interaction_area(event.position)
	for action in input_adapter.translate(event, in_world_area):
		handle_input_action(action)


func handle_minimap_input(event: InputEvent) -> bool:
	var screen_position: Variant = null
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		screen_position = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		screen_position = event.position
	if not screen_position is Vector2:
		return false
	var geometry := minimap_geometry()
	if not geometry["rectangle"].has_point(screen_position) or not MinimapProjection.contains_world(screen_position, map_size, geometry["center"], geometry["scale"]):
		return false
	center_view_on_world(MinimapProjection.minimap_to_world(screen_position, geometry["center"], geometry["scale"]))
	queue_redraw()
	return true


func handle_input_action(action: Dictionary) -> void:
	match String(action.get("type", "")):
		"consume_outside_world":
			selection_preview_ids.clear()
			get_viewport().set_input_as_handled()
		"zoom":
			zoom_at(action["position"], 1.12 if int(action["steps"]) > 0 else 1.0 / 1.12)
		"selection_started":
			selection_preview_ids.clear()
		"selection_committed":
			if not pending_target_command.is_empty():
				commit_pending_target(action["to"])
			elif pending_build_kind.is_empty():
				finish_selection(action["from"], action["to"])
			else:
				commit_build_placement(action["to"])
			selection_preview_ids.clear()
		"context_committed":
			if not pending_target_command.is_empty():
				commit_pending_target(action["position"])
			elif pending_build_kind.is_empty():
				issue_order(action["position"], action.get("direction_end"))
			else:
				pending_build_kind = ""
				game_message = "Строительство отменено"
				message_time = 1.5
		"pointer_moved":
			view_offset += Vector2(action.get("pan_delta", Vector2.ZERO))
			update_selection_preview()
			update_interaction_cursor(action.get("position", input_adapter.pointer_position))
		"control_group":
			if bool(action["assign"]):
				assign_control_group(int(action["number"]))
			else:
				recall_control_group(int(action["number"]), bool(action["additive"]))
		"set_formation":
			set_formation(String(action["formation"]))
		"attack_move_mode":
			begin_attack_move()
		"stop":
			issue_unit_action("stop")
		"hold":
			issue_unit_action("hold")
		"cycle_stance":
			issue_unit_action("stance")
		"train":
			request_primary_train_command()
		"toggle_audio":
			audio_player.stream_paused = not audio_player.stream_paused
			for player in sfx_players:
				player.stream_paused = audio_player.stream_paused
		"toggle_pause":
			var is_paused := game_controller.toggle_paused()
			game_message = "Пауза" if is_paused else "Игра продолжена"
			message_time = 1.5
		"change_speed":
			var speed := game_controller.cycle_speed(int(action["direction"]))
			game_message = "Скорость игры: %.1fx" % speed
			message_time = 1.5
		"toggle_diagnostics":
			diagnostics_enabled = not diagnostics_enabled
			game_message = "Диагностика включена" if diagnostics_enabled else "Диагностика выключена"
			message_time = 1.5
		"open_calibration":
			get_tree().change_scene_to_file("res://calibration.tscn")
		"martyrdom":
			issue_martyrdom()
		"unload":
			issue_unload_at_pointer()
		"reset_game":
			reset_game()
		"resign":
			var command = RoRCommands.ResignCommand.new(game_controller.tick_index + 1)
			game_controller.enqueue_command(command, true, PLAYER_TEAM)
			command_feedback_router.register(command, "Вы сдались", "", null)
		"quit":
			get_tree().quit()


func _show_diplomacy_summary() -> void:
	_open_hud_modal(HUDModalOverlay.MODE_DIPLOMACY)


func _toggle_game_menu() -> void:
	if hud_modal_overlay != null and hud_modal_overlay.is_blocking():
		_close_hud_modal()
		return
	_open_hud_modal(HUDModalOverlay.MODE_MENU)


func _open_hud_modal(mode: String) -> void:
	if hud_modal_overlay == null or game_controller == null:
		return
	if not hud_modal_overlay.is_blocking():
		modal_restore_paused = game_controller.paused
	game_controller.set_paused(true)
	hud_modal_overlay.set_snapshot(presentation_snapshot)
	if mode == HUDModalOverlay.MODE_DIPLOMACY:
		hud_modal_overlay.show_diplomacy()
	else:
		hud_modal_overlay.set_save_available(FileAccess.file_exists(GameSaveArchive.SAVE_PATH))
		hud_modal_overlay.set_menu_status("")
		hud_modal_overlay.show_menu()


func _close_hud_modal() -> void:
	if hud_modal_overlay == null or not hud_modal_overlay.is_blocking():
		return
	hud_modal_overlay.close()
	if game_controller != null:
		game_controller.set_paused(modal_restore_paused)
	game_message = "Пауза" if modal_restore_paused else "Игра продолжена"
	message_time = 1.5


func _resign_from_hud_modal() -> void:
	if hud_modal_overlay != null:
		hud_modal_overlay.close()
	if game_controller == null:
		return
	game_controller.set_paused(false)
	var command = RoRCommands.ResignCommand.new(game_controller.tick_index + 1)
	game_controller.enqueue_command(command, true, PLAYER_TEAM)
	command_feedback_router.register(command, "Вы сдались", "", null)


func _save_quick_game() -> void:
	if save_game_to_path(GameSaveArchive.SAVE_PATH):
		hud_modal_overlay.set_save_available(true)
		hud_modal_overlay.set_menu_status("Игра сохранена")
	else:
		hud_modal_overlay.set_menu_status("Не удалось сохранить игру", true)


func _load_quick_game() -> void:
	if not load_game_from_path(GameSaveArchive.SAVE_PATH):
		if hud_modal_overlay != null:
			hud_modal_overlay.set_menu_status("Сохранение несовместимо или повреждено", true)


func save_game_to_path(path: String) -> bool:
	last_save_error = ""
	if game_controller == null or simulation_world == null or game_controller.replay_recorder == null:
		last_save_error = "runtime_not_ready"
		return false
	var ai_states: Array = []
	for ai in ai_players:
		ai_states.append(ai.canonical_state())
	var view_state := {
		"view_offset": view_offset,
		"view_zoom": view_zoom,
		"selection": player_control_state.selected_ids(),
		"formation": formation,
		"control_groups": control_groups.groups.duplicate(true),
		"last_recalled_group": control_groups.last_recalled_group,
	}
	var controller_state := {
		"speed": game_controller.get_speed_multiplier(),
		"paused": modal_restore_paused if hud_modal_overlay != null and hud_modal_overlay.is_blocking() else game_controller.paused,
	}
	var verifier := ReplaySystem.new()
	var archive := GameSaveArchive.create(
		match_path,
		match_definition,
		game_controller.tick_index,
		verifier.world_state_hash(simulation_world, game_controller.tick_index, game_controller),
		game_controller.replay_recorder.to_dictionary(),
		ai_states,
		view_state,
		controller_state
	)
	var write_error := GameSaveArchive.write(path, archive)
	if write_error != OK:
		last_save_error = "write_failed:%d" % int(write_error)
		return false
	return true


func load_game_from_path(path: String) -> bool:
	last_save_error = ""
	var loaded: Dictionary = GameSaveArchive.read(path)
	if not bool(loaded.get("valid", false)):
		return _load_failed(String(loaded.get("error", "archive_invalid")))
	var archive: Dictionary = loaded.get("archive", {})
	if String(archive.get("match_path", "")) != match_path:
		return _load_failed("match_path_mismatch")
	if String(archive.get("match_fingerprint", "")) != GameSaveArchive.fingerprint(match_definition):
		return _load_failed("match_fingerprint_mismatch")

	# Reconstruct off to the side. A corrupt or incompatible archive never
	# mutates the live match before its authoritative hash has been verified.
	var restored_world = _new_simulation_world()
	MatchBootstrap.apply(restored_world, match_definition, map_definition)
	var restored_controller = GameController.new(restored_world)
	restored_controller.reset_timing()
	var replay_data: Dictionary = archive.get("replay", {})
	if not restored_controller.load_replay(replay_data):
		return _load_failed("replay_invalid")
	if not restored_controller.replay_until_tick(int(archive.get("tick", 0)), PLAYER_TEAM, ENEMY_TEAM):
		return _load_failed("replay_failed:%s" % restored_controller.last_replay_mismatch)
	var verifier := ReplaySystem.new()
	var restored_hash := verifier.world_state_hash(restored_world, restored_controller.tick_index, restored_controller)
	if restored_hash != String(archive.get("state_sha256", "")):
		return _load_failed("state_hash_mismatch:%s" % restored_hash)
	restored_controller.replay_source = null
	if not restored_controller.install_recording_history(replay_data, false):
		return _load_failed("recording_history_invalid")

	var restored_ai_players := _new_ai_players()
	var ai_state_by_team: Dictionary = {}
	for state_value in archive.get("ai_states", []):
		var state: Dictionary = state_value
		ai_state_by_team[int(state.get("team", 0))] = state
	for ai in restored_ai_players:
		if not ai_state_by_team.has(int(ai.team)):
			return _load_failed("ai_state_missing:%d" % int(ai.team))
		if not ai.restore_state(ai_state_by_team[int(ai.team)]):
			return _load_failed("ai_state_invalid:%d" % int(ai.team))

	simulation_world = restored_world
	game_controller = restored_controller
	ai_players = restored_ai_players
	var saved_controller: Dictionary = archive.get("controller_state", {})
	game_controller.set_speed_multiplier(float(saved_controller.get("speed", 1.5)))
	game_controller.set_paused(bool(saved_controller.get("paused", false)))
	modal_restore_paused = game_controller.paused
	var saved_view: Dictionary = archive.get("view_state", {})
	view_offset = saved_view.get("view_offset", view_offset)
	view_zoom = float(saved_view.get("view_zoom", view_zoom))
	formation = String(saved_view.get("formation", "RECTANGLE"))
	player_control_state.clear()
	var selected_ids: Array[int] = []
	for entity_id in saved_view.get("selection", []):
		selected_ids.append(int(entity_id))
	player_control_state.replace_or_add(selected_ids, false)
	control_groups.clear()
	for group_key in saved_view.get("control_groups", {}):
		var group_ids: Array[int] = []
		for entity_id in saved_view["control_groups"][group_key]:
			group_ids.append(int(entity_id))
		control_groups.assign(int(group_key), group_ids)
	control_groups.last_recalled_group = int(saved_view.get("last_recalled_group", -1))
	input_adapter.reset()
	command_feedback_router.reset()
	presentation_effect_timeline.reset()
	command_marker_presentation.reset()
	cached_fog_revision = -1
	cached_fog_runs.clear()
	pending_build_kind = ""
	pending_target_command = ""
	terrain_canvas.configure(map_size, map_seed, resource_catalog, simulation_world, Callable(self, "terrain_id_at_cell"), Callable(self, "visible_tile_bounds"))
	_sync_terrain_canvas()
	sync_world_state()
	if scenario_overlay != null:
		scenario_overlay.reset_presentation()
		scenario_overlay.set_snapshot(presentation_snapshot)
	if hud_modal_overlay != null:
		hud_modal_overlay.close()
	game_message = "Игра загружена"
	message_time = 2.0
	queue_redraw()
	return true


func _load_failed(reason: String) -> bool:
	last_save_error = reason
	return false

func is_world_interaction_area(position: Vector2) -> bool:
	return position.y > HUD_TOP and position.y < get_viewport_rect().size.y - HUD_BOTTOM

func assign_control_group(group_number: int) -> void:
	var ids := _selection_ids(selected_units())
	if ids.is_empty():
		game_message = "Нельзя назначить пустую группу"
		message_time = 1.5
		return
	control_groups.assign(group_number, ids)
	game_message = "Группа %d назначена: %d юнитов" % [group_number, ids.size()]
	message_time = 1.5

func recall_control_group(group_number: int, additive: bool) -> void:
	var available_ids: Array[int] = []
	for unit in units:
		if unit["team"] == PLAYER_TEAM and unit["hp"] > 0.0:
			available_ids.append(int(unit["id"]))
	var result: Dictionary = control_groups.recall(group_number, available_ids, _selection_ids(selected_units()), additive)
	var recalled_ids: Array[int] = result["ids"]
	if recalled_ids.is_empty():
		game_message = "Группа %d пуста" % group_number
		message_time = 1.5
		return
	player_control_state.replace_or_add(recalled_ids, additive)
	if result["center"]:
		center_view_on_units(recalled_ids)
		game_message = "Камера: группа %d" % group_number
	else:
		game_message = "Выбрана группа %d: %d юнитов" % [group_number, recalled_ids.size()]
	message_time = 1.5

func center_view_on_units(entity_ids: Array[int]) -> void:
	var center := Vector2.ZERO
	var count := 0
	for entity_id in entity_ids:
		var unit = simulation_world.find_unit(entity_id)
		if unit != null and unit["hp"] > 0.0:
			center += unit["pos"]
			count += 1
	if count == 0:
		return
	center /= float(count)
	center_view_on_world(center)


func center_view_on_world(world_position: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	var visible_center := Vector2(viewport_size.x * 0.5, (HUD_TOP + viewport_size.y - HUD_BOTTOM) * 0.5)
	view_offset = visible_center - iso_raw(Coordinates.clamp_world(world_position, map_size)) * view_zoom

func zoom_at(mouse: Vector2, factor: float) -> void:
	var before := screen_to_world(mouse)
	view_zoom = PixelScaling.step_zoom(view_zoom, 1 if factor > 1.0 else -1)
	var after_screen := world_to_screen(before)
	view_offset += mouse - after_screen

func finish_selection(first: Vector2, mouse: Vector2) -> void:
	var rectangle := selection_rectangle(first, mouse)
	var click := rectangle.size.length() < 9.0
	var hits: Array = []
	if click:
		for hit_value in pick_stack_at(mouse):
			var hit: Dictionary = hit_value
			if int(hit.get("team", 0)) == PLAYER_TEAM and String(hit.get("entity_type", "")) in ["unit", "building", "foundation"]:
				hits.append(hit["entity"])
				break
	else:
		hits = selection_hits_in_rectangle(rectangle)

	var eligible_ids := selectable_player_ids()
	var hit_ids: Array[int] = []
	for unit in hits:
		hit_ids.append(int(unit["id"]))
	player_control_state.apply_selection(eligible_ids, hit_ids, Input.is_key_pressed(KEY_SHIFT))
	refresh_hud_model()
	var selected := selected_entities()
	game_message = "Выбрано объектов: %d" % selected.size()
	message_time = 1.5
	if not selected.is_empty() and not hits.is_empty():
		play_sfx("selection:%s" % String(selected[0]["kind"]))

func selection_hits_in_rectangle(rectangle: Rect2) -> Array:
	return picking_service.box_hits(rectangle, current_world_drawables(), Callable(self, "world_to_screen"), PLAYER_TEAM)


func current_world_drawables() -> Array:
	if render_world == null or presentation_snapshot.is_empty():
		return []
	var interpolation_alpha := game_controller.get_interpolation_alpha() if game_controller != null else 1.0
	var highlighted_ids: Array[int] = selection_preview_ids.duplicate()
	if interaction_highlight_id >= 0 and not highlighted_ids.has(interaction_highlight_id):
		highlighted_ids.append(interaction_highlight_id)
	return render_world.create_world_drawables(presentation_snapshot, Callable(self, "world_to_screen"), interpolation_alpha, Callable(self, "render_item_frame_info"), highlighted_ids, PLAYER_TEAM, player_control_state.selected_ids())


func pick_stack_at(screen_position: Vector2) -> Array:
	return picking_service.hit_stack(screen_position, current_world_drawables(), Callable(self, "world_to_screen"), view_zoom)

func update_selection_preview() -> void:
	selection_preview_ids.clear()
	var gesture := input_adapter.selection_gesture()
	if gesture.is_empty() or not bool(gesture["is_box"]):
		return
	var rectangle := selection_rectangle(gesture["from"], gesture["to"])
	for unit in selection_hits_in_rectangle(rectangle):
		selection_preview_ids.append(int(unit["id"]))


func update_interaction_cursor(screen_position: Vector2) -> void:
	var hovered: Variant = null
	var hits := pick_stack_at(screen_position)
	if not hits.is_empty():
		hovered = picking_service.context_entity(hits[0])
	var cursor := InteractionCursor.resolve(selected_units(), hovered, screen_to_world(screen_position), PLAYER_TEAM)
	interaction_highlight_id = int(cursor.get("entity_id", -1))
	interaction_cursor_semantic = String(cursor.get("semantic", "default"))
	Input.set_default_cursor_shape(cursor_shape_for_semantic(interaction_cursor_semantic))


func cursor_shape_for_semantic(semantic: String) -> Input.CursorShape:
	match semantic:
		"select": return Input.CURSOR_POINTING_HAND
		"attack", "convert": return Input.CURSOR_CROSS
		"gather", "return_resources", "build", "repair", "heal", "board", "trade": return Input.CURSOR_CAN_DROP
		"move": return Input.CURSOR_MOVE
		"unsupported": return Input.CURSOR_FORBIDDEN
		_: return Input.CURSOR_ARROW

func unit_frame_info(unit: Dictionary) -> Dictionary:
	var animation_state := AnimationController.clip_for_state(unit["anim_state"])
	if String(unit.get("death_phase", "alive")) == "corpse":
		animation_state = "corpse"
	animation_state = resource_catalog.unit_presentation_state(unit, animation_state)
	return resource_catalog.unit_frame_info(unit, animation_state)

func issue_order(mouse: Vector2, direction_end: Variant = null) -> void:
	var selected := selected_units()
	if selected.is_empty():
		game_message = "Для этого приказа выберите своих юнитов"
		message_time = 1.5
		return

	var mouse_world := screen_to_world(mouse)
	var formation_forward := Vector2.ZERO
	if direction_end is Vector2:
		formation_forward = screen_to_world(direction_end) - mouse_world
	var clicked_entity: Variant = null
	var hit_stack := pick_stack_at(mouse)
	if not hit_stack.is_empty():
		clicked_entity = picking_service.context_entity(hit_stack[0])

	var resolution := ContextResolver.resolve(selected, clicked_entity, mouse_world, PLAYER_TEAM)
	var selected_ids := _selection_ids(selected)
	var command: Variant = null
	var accepted_message := ""
	match resolution["type"]:
		"attack":
			command = RoRCommands.AttackCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Атаковать цель"
		"convert":
			command = RoRCommands.ConvertCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Обратить цель"
		"heal":
			command = RoRCommands.HealCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Исцелить союзника"
		"board":
			command = RoRCommands.BoardCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Погрузиться в транспорт"
		"trade":
			command = RoRCommands.TradeCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Торговый маршрут назначен"
		"gather":
			command = RoRCommands.GatherCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Работники отправлены к ресурсу"
		"return_resources":
			command = RoRCommands.ReturnResourcesCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Сдать ресурсы"
		"build":
			command = RoRCommands.BuildCommand.new(game_controller.tick_index + 1, selected_ids, resolution["building_type"], resolution["target"])
			accepted_message = "Продолжить строительство"
		"repair":
			command = RoRCommands.RepairCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target_id"])
			accepted_message = "Ремонтировать здание"
		"move":
			command = RoRCommands.FormationMoveCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target"], formation, formation_forward)
			accepted_message = "Движение: %s" % formation_name()
		_:
			game_message = String(resolution.get("message", "Команда для этой цели пока недоступна"))
			message_time = 1.8
			return
	var is_worker_group: bool = "worker" in selected[0].get("behavior_tags", []) or String(selected[0].get("kind", "")) == "villager"
	enqueue_with_feedback(command, accepted_message, "command:%s" % String(selected[0].get("kind", "")), mouse_world)


func issue_martyrdom() -> void:
	var selected := selected_units()
	if selected.is_empty():
		return
	var command = RoRCommands.MartyrdomCommand.new(game_controller.tick_index + 1, _selection_ids(selected))
	enqueue_with_feedback(command, "Жертвоприношение", "", null)


func issue_unload_at_pointer() -> void:
	var selected := selected_units()
	var transports: Array = selected.filter(func(unit): return bool(unit.get("components", {}).get("cargo", {}).get("enabled", false)))
	if transports.is_empty():
		game_message = "Для выгрузки выберите транспорт"
		message_time = 1.5
		return
	var target := screen_to_world(input_adapter.pointer_position)
	var command = RoRCommands.UnloadCommand.new(game_controller.tick_index + 1, _selection_ids(transports), target)
	enqueue_with_feedback(command, "Высадить пассажиров", "", target)


func issue_unit_action(action_name: String) -> void:
	if action_name == "attack_move":
		begin_attack_move()
		return
	if battle_over:
		return
	var selected := selected_units()
	if selected.is_empty():
		game_message = "Для приказа выберите своих юнитов"
		message_time = 1.5
		return
	var ids := _selection_ids(selected)
	var command: Variant = null
	var message := ""
	match action_name:
		"stop":
			command = RoRCommands.StopCommand.new(game_controller.tick_index + 1, ids)
			message = "Остановиться"
		"hold":
			command = RoRCommands.HoldCommand.new(game_controller.tick_index + 1, ids)
			message = "Держать позицию"
		"stance":
			var stance := RoRCommands.next_stance(String(selected[0].get("stance", "aggressive")))
			command = RoRCommands.StanceCommand.new(game_controller.tick_index + 1, ids, stance)
			message = "Стойка: %s" % stance_name(stance)
		_:
			return
	enqueue_with_feedback(command, message, "command:%s" % String(selected[0].get("kind", "")), null)


func begin_attack_move() -> void:
	if selected_units().is_empty() or battle_over:
		game_message = "Для атаки выберите своих юнитов"
		message_time = 1.5
		return
	pending_build_kind = ""
	pending_target_command = "attack_move"
	game_message = "Укажите точку движения с атакой"
	message_time = 4.0


func commit_pending_target(screen_position: Vector2) -> void:
	if pending_target_command != "attack_move":
		return
	pending_target_command = ""
	var selected := selected_units()
	if selected.is_empty() or battle_over:
		return
	var target := screen_to_world(screen_position)
	var command = RoRCommands.AttackMoveCommand.new(game_controller.tick_index + 1, _selection_ids(selected), target)
	enqueue_with_feedback(command, "Двигаться с атакой", "command:%s" % String(selected[0].get("kind", "")), target)


func stance_name(value: String) -> String:
	return {"aggressive": "агрессивная", "defensive": "оборонительная", "stand_ground": "держать позицию", "passive": "не атаковать"}.get(value, value)


func selected_units() -> Array:
	var selected: Array = []
	for unit in units:
		if unit["team"] == PLAYER_TEAM and unit["hp"] > 0.0 and player_control_state.is_selected(int(unit["id"])):
			selected.append(unit)
	selected.sort_custom(func(left, right): return left["id"] < right["id"])
	return selected


func selected_entities() -> Array:
	var selected: Array = selected_units()
	for building in presentation_snapshot.get("buildings", []):
		if int(building.get("team", 0)) == PLAYER_TEAM and float(building.get("hp", 0.0)) > 0.0 and player_control_state.is_selected(int(building.get("id", -1))):
			selected.append(building)
	selected.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return selected


func selectable_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for unit in units:
		if int(unit.get("team", 0)) == PLAYER_TEAM and float(unit.get("hp", 0.0)) > 0.0:
			ids.append(int(unit["id"]))
	for building in presentation_snapshot.get("buildings", []):
		if int(building.get("team", 0)) == PLAYER_TEAM and float(building.get("hp", 0.0)) > 0.0:
			ids.append(int(building["id"]))
	ids.sort()
	return ids

func unit_at_screen(mouse: Vector2, team: int):
	for hit_value in pick_stack_at(mouse):
		var hit: Dictionary = hit_value
		if String(hit.get("entity_type", "")) == "unit" and int(hit.get("team", 0)) == team:
			return hit["entity"]
	return null

func resource_at_screen(mouse: Vector2):
	for hit_value in pick_stack_at(mouse):
		var hit: Dictionary = hit_value
		if String(hit.get("entity_type", "")) == "resource":
			return hit["entity"]
	return null


func set_formation(value: String) -> void:
	formation = value
	refresh_hud_model()
	game_message = "Выбран строй: %s" % formation_name()
	message_time = 1.5
	if game_controller == null or simulation_world == null:
		return
	var selected = selected_units()
	if selected.size() <= 1:
		return
	var center = Vector2.ZERO
	for unit in selected:
		center += unit["pos"]
	center /= float(selected.size())
	var existing_forward: Vector2 = selected[0].get("formation_forward", Vector2.ZERO)
	var reform = RoRCommands.FormationMoveCommand.new(game_controller.tick_index + 1, _selection_ids(selected), center, formation, existing_forward)
	game_controller.enqueue_command(reform, true, PLAYER_TEAM)
func formation_name() -> String:
	return {"LINE": "линия", "RECTANGLE": "каре", "COLUMN": "колонна", "WEDGE": "клин", "STAGGERED": "шахматный"}.get(formation, formation)

func request_primary_train_command() -> void:
	for command_value in hud_model.get("commands", []):
		var command: Dictionary = command_value
		if String(command.get("type", "")) != "train":
			continue
		if not bool(command.get("enabled", false)):
			game_message = HUDControls.reason_text(String(command.get("reason", "")))
			message_time = 2.0
			return
		train_unit_from_hud(String(command.get("id", "")), int(command.get("building_id", -1)))
		return
	game_message = "Выберите производящее здание"
	message_time = 2.0


func begin_build_placement(building_kind: String) -> void:
	if building_kind.is_empty() or selected_units().is_empty():
		return
	pending_build_kind = building_kind
	game_message = "Укажите место строительства: %s (ПКМ — отмена)" % building_kind
	message_time = 4.0


func commit_build_placement(screen_position: Vector2) -> void:
	if pending_build_kind.is_empty() or simulation_world == null or battle_over:
		return
	var workers: Array = selected_units().filter(func(unit): return simulation_world.entity_is_worker(unit))
	if workers.is_empty():
		pending_build_kind = ""
		game_message = "Для строительства нужен рабочий"
		message_time = 2.0
		return
	var target := Coordinates.clamp_world(screen_to_world(screen_position).round(), map_size)
	var kind := pending_build_kind
	pending_build_kind = ""
	var command = RoRCommands.BuildCommand.new(game_controller.tick_index + 1, _selection_ids(workers), kind, target)
	enqueue_with_feedback(command, "Строительство: %s" % kind, "command:%s" % String(workers[0].get("kind", "villager")), target)


func train_unit_from_hud(unit_kind: String, building_id: int) -> void:
	if simulation_world == null or battle_over or building_id < 0 or unit_kind.is_empty():
		return
	var building: Variant = simulation_world.find_building(building_id)
	if building == null:
		game_message = "Здание больше недоступно"
		message_time = 2.0
		return
	var command = RoRCommands.TrainCommand.new(game_controller.tick_index + 1, [building_id], unit_kind, PLAYER_TEAM, Vector2.ZERO)
	enqueue_with_feedback(command, "Добавлено в очередь: %s" % unit_kind, "", Vector2(building.get("pos", Vector2.ZERO)))


func research_from_hud(technology_id: int, building_id: int) -> void:
	if simulation_world == null or battle_over or building_id < 0 or technology_id < 0:
		return
	var building: Variant = simulation_world.find_building(building_id)
	if building == null:
		game_message = "Здание больше недоступно"
		message_time = 2.0
		return
	var command = RoRCommands.ResearchCommand.new(game_controller.tick_index + 1, [building_id], String.num_int64(technology_id))
	enqueue_with_feedback(command, "Исследование добавлено в очередь", "", Vector2(building.get("pos", Vector2.ZERO)))


func cancel_production_from_hud(building_id: int, queue_index: int) -> void:
	if simulation_world == null or building_id < 0:
		return
	var building: Variant = simulation_world.find_building(building_id)
	if building == null:
		game_message = "Здание больше недоступно"
		message_time = 2.0
		return
	var command = RoRCommands.CancelProductionCommand.new(game_controller.tick_index + 1, [building_id], queue_index)
	enqueue_with_feedback(command, "Элемент очереди отменён", "", Vector2(building.get("pos", Vector2.ZERO)))


func set_trade_resource_from_hud(resource_type_id: int) -> void:
	if simulation_world == null or battle_over or resource_type_id not in [0, 1, 2]:
		return
	var traders: Array = selected_units().filter(func(unit): return bool(unit.get("components", {}).get("trade", {}).get("enabled", false)))
	if traders.is_empty():
		game_message = "Выберите торговое судно"
		message_time = 2.0
		return
	var command = RoRCommands.SetTradeResourceCommand.new(game_controller.tick_index + 1, _selection_ids(traders), resource_type_id)
	var label: String = String({0: "еда", 1: "дерево", 2: "камень"}.get(resource_type_id, "ресурс"))
	enqueue_with_feedback(command, "Торговый ресурс: %s" % label, "", null)


func refresh_hud_model() -> void:
	if hud_view_model == null or presentation_snapshot.is_empty():
		return
	hud_model = hud_view_model.build(presentation_snapshot, player_control_state.selected_ids(), formation, "ru")
	if hud_controls != null:
		hud_controls.set_view_model(hud_model)


func sync_world_state() -> void:
	if simulation_world == null:
		return
	presentation_snapshot = SimulationSnapshot.presentation(simulation_world, game_controller.tick_index if game_controller != null else 0, PLAYER_TEAM, {"include_navigation": false, "include_build_sites": false})
	presentation_snapshot["markers"] = match_definition.get("presentation_markers", [])
	var visible_bounds := visible_tile_bounds()
	var environment_bounds := Rect2i(visible_bounds.position - Vector2i(2, 2), visible_bounds.size + Vector2i(4, 4))
	presentation_snapshot["environment"] = environment_presentation_field.query(environment_bounds)
	units = presentation_snapshot.get("units", [])
	resource_nodes = presentation_snapshot.get("resources", [])
	player_control_state.prune(selectable_player_ids())
	battle_over = bool(presentation_snapshot.get("battle_over", false))
	refresh_hud_model()
	if scenario_overlay != null:
		scenario_overlay.set_snapshot(presentation_snapshot)
	if hud_modal_overlay != null:
		hud_modal_overlay.set_snapshot(presentation_snapshot)


func _restart_from_scenario_overlay() -> void:
	reset_game()


func _return_to_launcher() -> void:
	get_tree().change_scene_to_file("res://launcher.tscn")


func presentation_fog_state_at(position: Vector2) -> int:
	var cell := Vector2i(floori(position.x), floori(position.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return FogOfWar.UNKNOWN
	var cells: Variant = presentation_snapshot.get("fog", {}).get("cells", [])
	var index := cell.y * map_size.x + cell.x
	if index < 0 or index >= cells.size():
		return FogOfWar.UNKNOWN
	return int(cells[index])

func _selection_ids(selected: Array) -> Array[int]:
	var ids: Array[int] = []
	for unit in selected:
		if unit != null and unit.has("id"):
			ids.append(int(unit["id"]))
	return ids
func selection_rectangle(first: Vector2, second: Vector2) -> Rect2:
	var top_left := Vector2(minf(first.x, second.x), minf(first.y, second.y))
	var bottom_right := Vector2(maxf(first.x, second.x), maxf(first.y, second.y))
	return Rect2(top_left, bottom_right - top_left)

func _draw() -> void:
	draw_world_objects()
	draw_fog_overlay()
	draw_map_edge_guard()
	draw_command_marker()
	if diagnostics_enabled:
		draw_diagnostics()
	draw_formation_ghost()
	draw_hud()
	var selection_gesture := input_adapter.selection_gesture()
	if not selection_gesture.is_empty():
		var rectangle := selection_rectangle(selection_gesture["from"], selection_gesture["to"])
		draw_rect(rectangle, Color(0.25, 0.75, 1.0, 0.12), true)
		draw_rect(rectangle, Color(0.35, 0.9, 1.0, 0.9), false, 1.5)


func _sync_terrain_canvas() -> void:
	if terrain_canvas != null and simulation_world != null:
		terrain_canvas.set_view_state(view_zoom, view_offset, get_viewport_rect().size, int(simulation_world.terrain_revision))

func draw_formation_ghost() -> void:
	var gesture := input_adapter.formation_gesture()
	if gesture.is_empty():
		return
	var selected := selected_units()
	if selected.is_empty():
		return
	var destination := screen_to_world(gesture["position"])
	var direction_end := screen_to_world(gesture["direction_end"])
	var preview := FormationPreview.build(selected.size(), formation, destination, direction_end - destination, 1.0)
	if preview.is_empty():
		return
	var anchor_screen := world_to_screen(preview["destination"])
	var direction_screen := world_to_screen(preview["destination"] + preview["forward"] * 1.6)
	draw_line(anchor_screen, direction_screen, Color(1.0, 0.88, 0.25, 0.95), 2.0, true)
	draw_circle(direction_screen, 3.5, Color(1.0, 0.88, 0.25, 0.95))
	for slot in preview["slots"]:
		draw_formation_ghost_slot(slot)

func draw_formation_ghost_slot(world_position: Vector2) -> void:
	var points := PackedVector2Array()
	for index in range(17):
		var angle := TAU * float(index) / 16.0
		points.append(world_to_screen(world_position + Vector2(cos(angle), sin(angle)) * 0.32))
	draw_colored_polygon(points, Color(0.95, 0.84, 0.28, 0.16))
	draw_polyline(points, Color(1.0, 0.9, 0.35, 0.9), 1.25, true)

func draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("101820"), true)

func draw_terrain() -> void:
	var terrain_provider := Callable(self, "terrain_id_at_cell")
	var bounds := visible_tile_bounds()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var terrain_id := terrain_id_at_cell(cell)
			var drawable := TerrainRenderer.tile_drawable(cell, terrain_id, terrain_provider, resource_catalog, simulation_world.terrain_elevation, view_zoom, view_offset, map_seed)
			if drawable.is_empty():
				continue
			draw_texture_rect(drawable["texture"], Rect2(PixelScaling.snap_screen(drawable["position"]), drawable["size"]), false)
			for layer in drawable["borders"]:
				draw_terrain_border(drawable["position"], layer)

func terrain_at(x: int, y: int) -> String:
	return TerrainRules.base_texture_kind(terrain_id_at_cell(Vector2i(x, y)), resource_catalog.terrain_catalog_data)


func terrain_id_at_cell(cell: Vector2i) -> int:
	for resource in resource_nodes:
		if resource["amount"] > 0 and resource["kind"] == "tree" and Vector2i(floori(resource["pos"].x), floori(resource["pos"].y)) == cell:
			return TerrainRules.TERRAIN_IDS["forest_floor"]
	return simulation_world.terrain_id_at_cell(cell) if simulation_world != null else TerrainRules.terrain_id_for_logical(TerrainRules.terrain_at(cell))


func draw_terrain_border(tile_origin: Vector2, layer: Dictionary) -> void:
	var border_id := int(layer["border_id"])
	var frame := int(layer["frame"])
	var texture: Texture2D = resource_catalog.get_terrain_border_texture(border_id, frame)
	if texture == null:
		return
	var metadata := resource_catalog.get_texture_metadata(String(layer["asset_name"]), frame)
	var hotspot := Vector2.ZERO
	if metadata.has("hotspot"):
		hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
	var position := PixelScaling.snap_screen(tile_origin - hotspot * view_zoom)
	draw_texture_rect(texture, Rect2(position, texture.get_size() * view_zoom), false)

func draw_world_objects() -> void:
	if render_world != null:
		for drawable in current_world_drawables():
			match drawable["kind"]:
				"building", "building_part", "resource", "unit", "projectile", "effect", "marker", "environment": draw_render_body(drawable)
				"shadow": draw_unit_shadow(drawable)
				"selection": draw_unit_selection(drawable)
				"health_bar": draw_unit_health(drawable)
	return


func draw_command_marker() -> void:
	var marker := command_marker_presentation.snapshot()
	if marker.is_empty():
		return
	var center := PixelScaling.snap_screen(world_to_screen(marker["world_position"]))
	var half_extent: Vector2 = marker["half_extent"]
	var directions := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	for direction in directions:
		var outer_extent := half_extent.x if not is_zero_approx(direction.x) else half_extent.y
		var local_points := CommandMarkerPresentation.arrow_polygon(direction, outer_extent)
		var shadow_points := PackedVector2Array()
		var bright_points := PackedVector2Array()
		for point in local_points:
			shadow_points.append(PixelScaling.snap_screen(center + point + marker["shadow_offset"]))
			bright_points.append(PixelScaling.snap_screen(center + point))
		draw_colored_polygon(shadow_points, marker["shadow_color"])
		draw_colored_polygon(bright_points, marker["bright_color"])


func draw_fog_overlay() -> void:
	if presentation_snapshot.is_empty():
		return
	var bounds := visible_tile_bounds()
	var cells: Variant = presentation_snapshot.get("fog", {}).get("cells", [])
	if cells.size() < map_size.x * map_size.y:
		return
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var state := int(cells[y * map_size.x + x])
			if state == FogOfWar.VISIBLE:
				continue
			var color := FogPresentation.color_for_state(state)
			for triangle in FogPresentation.terrain_conforming_cell_triangles(Vector2i(x, y), Callable(self, "world_to_screen")):
				draw_colored_polygon(triangle, color)


func draw_map_edge_guard() -> void:
	for chain in FogPresentation.map_edge_guard_chains(map_size, Callable(self, "world_to_screen")):
		if chain.size() >= 2:
			# A two-pixel centered stroke covers the one shared texel outside either
			# rasterized edge orientation while consuming at most one pixel inside.
			draw_polyline(chain, Color.BLACK, maxf(2.0, view_zoom * 2.0), false)

func render_item_frame_info(kind: String, data: Variant) -> Dictionary:
	match kind:
		"unit":
			return unit_frame_info(data)
		"resource":
			var animation_time := float(presentation_snapshot.get("tick", 0)) * GameController.FIXED_STEP_SECONDS
			return resource_catalog.resource_frame_info(data, animation_time)
		"objective":
			var animation_time := float(presentation_snapshot.get("tick", 0)) * GameController.FIXED_STEP_SECONDS
			return resource_catalog.objective_frame_info(data, animation_time)
		"building":
			var animation_time := float(presentation_snapshot.get("tick", 0)) * GameController.FIXED_STEP_SECONDS
			return resource_catalog.building_frame_info(data, animation_time)
		"projectile":
			return resource_catalog.projectile_frame_info(data)
		"effect":
			return resource_catalog.effect_frame_info(data)
		"marker":
			var animation_time := float(presentation_snapshot.get("tick", 0)) * GameController.FIXED_STEP_SECONDS
			return resource_catalog.scenario_marker_frame_info(data, animation_time)
		"environment":
			var animation_time := float(presentation_snapshot.get("tick", 0)) * GameController.FIXED_STEP_SECONDS
			return resource_catalog.environment_frame_info(data, animation_time)
	return {}

func static_frame_info(texture: Texture2D, asset_name: String, frame_index: int = 0) -> Dictionary:
	var metadata := resource_catalog.get_texture_metadata(asset_name, frame_index)
	var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
	if metadata.has("hotspot"):
		hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
	return {"texture": texture, "asset_name": asset_name, "frame_index": frame_index, "hotspot": hotspot, "mirrored": false}

func draw_render_body(item: Dictionary) -> void:
	var frame_info: Dictionary = item["frame_info"]
	if frame_info.is_empty() or frame_info.get("texture") == null:
		return
	var screen := PixelScaling.snap_screen(world_to_screen(item["world_anchor"]))
	if item["kind"] == "projectile":
		screen.y -= float(item["data"].get("visual_height", 0.0)) * TerrainElevation.ELEVATION_PIXEL_STEP * view_zoom
	var screen_offset: Vector2 = frame_info.get("screen_offset", Vector2.ZERO)
	screen += screen_offset * view_zoom
	draw_anchored_texture(frame_info["texture"], frame_info["asset_name"], item["frame"], screen, view_zoom, bool(frame_info.get("mirrored", false)), float(item["opacity"]), item["hotspot"])

func draw_unit_selection(item: Dictionary) -> void:
	var unit: Dictionary = item["data"]
	var screen := PixelScaling.snap_screen(world_to_screen(item["world_anchor"]))
	var radius := Vector2(15.0, 6.5)
	var half_size: Variant = unit.get("footprint", {}).get("half_size")
	if half_size is Vector2:
		var footprint_span := float(half_size.x + half_size.y)
		radius = Vector2(maxf(15.0, footprint_span * 17.0), maxf(6.5, footprint_span * 8.5))
	var previewed := selection_preview_ids.has(int(unit["id"]))
	var hovered := interaction_highlight_id == int(unit["id"])
	var selected := player_control_state.is_selected(int(unit["id"]))
	if previewed:
		var preview_color := Color("f39a55") if Input.is_key_pressed(KEY_SHIFT) and selected else Color("66e8ff")
		draw_selection_ellipse(screen + Vector2(0, 7) * view_zoom, preview_color, radius)
	elif hovered:
		var hover_color := Color("ef5d55") if interaction_cursor_semantic == "attack" else Color("d6bc63") if interaction_cursor_semantic == "gather" else Color("66e8ff")
		draw_selection_ellipse(screen + Vector2(0, 7) * view_zoom, hover_color, radius)
	elif selected:
		draw_selection_ellipse(screen + Vector2(0, 7) * view_zoom, Color("e8f45b"), radius)


func draw_unit_shadow(item: Dictionary) -> void:
	var unit: Dictionary = item["data"]
	var screen := PixelScaling.snap_screen(world_to_screen(item["world_anchor"]))
	var radius := maxf(0.2, float(unit.get("footprint_radius", 0.3)))
	draw_set_transform(screen + Vector2(0.0, 5.0 * view_zoom), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, radius * 34.0 * view_zoom, Color(0.0, 0.0, 0.0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_unit_health(item: Dictionary) -> void:
	var unit: Dictionary = item["data"]
	var screen := PixelScaling.snap_screen(world_to_screen(item["world_anchor"]))
	var hotspot: Vector2 = item["hotspot"]
	var ratio: float = clampf(float(unit["hp"]) / maxf(1.0, float(unit["max_hp"])), 0.0, 1.0)
	# 50745 is the 50x7 selection-card meter. World-space selection bars in
	# RoR are a separate, compact presentation and must not reuse that strip.
	var bar_width := 25.0 * view_zoom
	var bar_height := maxf(3.0, 3.0 * view_zoom)
	var bar_pos := PixelScaling.snap_screen(Vector2(screen.x - bar_width * 0.5, screen.y - hotspot.y * view_zoom - 5.0))
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0.02, 0.04, 0.03, 0.95), true)
	draw_rect(Rect2(bar_pos + Vector2(1, 1), Vector2(maxf(0.0, (bar_width - 2.0) * ratio), maxf(1.0, bar_height - 2.0))), Color("21dc4b") if unit["team"] == PLAYER_TEAM else Color("e44339"), true)

func draw_anchored_texture(texture: Texture2D, name: String, frame: int, anchor: Vector2, scale: float, mirrored: bool = false, opacity: float = 1.0, provided_hotspot: Variant = null) -> void:
	var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
	if provided_hotspot is Vector2:
		hotspot = provided_hotspot
	elif resource_catalog != null:
		var metadata: Dictionary = resource_catalog.get_texture_metadata(name, frame)
		if metadata.has("hotspot"):
			hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
	var rectangle := SpriteGeometry.anchored_rectangle(texture.get_size(), hotspot, scale)
	var modulate := Color(1.0, 1.0, 1.0, opacity)
	if mirrored:
		draw_set_transform(anchor, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(texture, rectangle, false, modulate)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		rectangle.position += anchor
		draw_texture_rect(texture, rectangle, false, modulate)

func draw_selection_ellipse(center: Vector2, color: Color, radius: Vector2 = Vector2(15.0, 6.5)) -> void:
	var points := PackedVector2Array()
	for index in range(33):
		var angle := TAU * float(index) / 32.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * view_zoom)
	draw_polyline(points, color, 1.5, true)

func draw_diagnostics() -> void:
	draw_diagnostic_grid()
	for unit in units:
		if unit["hp"] <= 0.0:
			continue
		var snapshot: Dictionary = Diagnostics.unit_snapshot(unit, GameController.FIXED_STEP_SECONDS)
		var position: Vector2 = snapshot["position"]
		var screen := world_to_screen(position)
		var target: Vector2 = snapshot["target"]
		var desired_velocity: Vector2 = snapshot["desired_velocity"]
		var actual_velocity: Vector2 = snapshot["actual_velocity"]

		draw_world_radius(position, snapshot["footprint_radius"], Color(1.0, 0.35, 0.25, 0.8))
		if position.distance_squared_to(target) > 0.0001:
			draw_dashed_line(screen, world_to_screen(target), Color(1.0, 0.85, 0.2, 0.8), 1.0, 5.0)
			draw_diagnostic_cross(world_to_screen(target), Color(1.0, 0.85, 0.2, 0.9))
		if desired_velocity.length_squared() > 0.0001:
			draw_line(screen, world_to_screen(position + desired_velocity * 0.55), Color(0.2, 0.65, 1.0, 0.95), 2.0)
		if actual_velocity.length_squared() > 0.0001:
			draw_line(screen, world_to_screen(position + actual_velocity * 0.55), Color(0.2, 1.0, 0.45, 0.95), 2.0)

		var facing_screen := FacingConvention.screen_vector(int(snapshot["facing"])) * 24.0
		draw_line(screen, screen + facing_screen, Color(1.0, 0.25, 0.9, 0.95), 2.0)
		var label := "#%d  %s/%s  %s  T%d  G%d:S%d/%s  F%d  RK %.1f:%d  %s" % [
			snapshot["id"], snapshot["order"], snapshot["animation"], snapshot["stance"], snapshot["target_id"], snapshot["formation_group_id"], snapshot["formation_slot_id"], snapshot["formation_slot_mode"], snapshot["facing"], screen.y, snapshot["id"], snapshot["diagnostic_reason"]
		]
		draw_string(font, screen + Vector2(13, -16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 1.0, 0.75, 0.95))

func draw_diagnostic_grid() -> void:
	for y in range(map_size.y + 1):
		draw_line(world_to_screen(Vector2(0, y)), world_to_screen(Vector2(map_size.x, y)), Color(0.25, 0.85, 1.0, 0.18), 1.0)
	for x in range(map_size.x + 1):
		draw_line(world_to_screen(Vector2(x, 0)), world_to_screen(Vector2(x, map_size.y)), Color(0.25, 0.85, 1.0, 0.18), 1.0)

func draw_world_radius(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(25):
		var angle := TAU * float(index) / 24.0
		points.append(world_to_screen(center + Vector2(cos(angle), sin(angle)) * radius))
	draw_polyline(points, color, 1.25, true)

func draw_diagnostic_cross(center: Vector2, color: Color) -> void:
	draw_line(center - Vector2(5, 0), center + Vector2(5, 0), color, 1.5)
	draw_line(center - Vector2(0, 5), center + Vector2(0, 5), color, 1.5)

func draw_hud() -> void:
	var viewport_size := get_viewport_rect().size
	var width := viewport_size.x
	var layout := InterfaceLayout.for_viewport(viewport_size)
	var resources: Dictionary = hud_model.get("resources", {})
	draw_source_hud_shell(layout)
	var resource_x := [32.0, 104.0, 172.0, 240.0]
	var resource_keys := ["wood", "food", "gold", "stone"]
	for index in range(resource_x.size()):
		draw_string(font, Vector2(resource_x[index], 15), String.num_int64(int(resources.get(resource_keys[index], 0))), HORIZONTAL_ALIGNMENT_LEFT, 44.0, 11, Color("20180f"))
	draw_string(font, Vector2(width * 0.5 - 90.0, 15), String(hud_model.get("age", {}).get("label", "")), HORIZONTAL_ALIGNMENT_CENTER, 180.0, 11, Color("20180f"))

	var command_rect: Rect2 = layout["command"]
	var info_rect: Rect2 = layout["selection"]
	var map_rect: Rect2 = layout["minimap"]

	var selection: Dictionary = hud_model.get("selection", {})
	var leader: Dictionary = selection.get("leader", {})
	if not leader.is_empty():
		draw_rect(Rect2(info_rect.position + Vector2(3, 3), info_rect.size - Vector2(6, 6)), Color.BLACK, true)
		draw_string(font, info_rect.position + Vector2(5, 14), String(leader.get("civilization_name", "")), HORIZONTAL_ALIGNMENT_LEFT, info_rect.size.x - 10.0, 10, Color.WHITE)
		draw_string(font, info_rect.position + Vector2(5, 28), String(leader.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, info_rect.size.x - 10.0, 10, Color.WHITE)
		var portrait: Texture2D = resource_catalog.interface_icons.texture(String(leader.get("icon_kind", "object")), int(leader.get("icon_id", -1)))
		if portrait != null:
			draw_texture_rect(portrait, Rect2(info_rect.position + Vector2(5, 35), Vector2(50, 50)), false)
		var text_x := 61.0
		var selected_count := int(selection.get("count", 0))
		if selected_count > 1:
			draw_string(font, info_rect.position + Vector2(text_x, 48), "%d ×" % selected_count, HORIZONTAL_ALIGNMENT_LEFT, 60.0, 10, Color.WHITE)
		draw_string(font, info_rect.position + Vector2(text_x, 63), "АТК %d" % int(leader.get("attack", 0)), HORIZONTAL_ALIGNMENT_LEFT, 60.0, 10, Color.WHITE)
		draw_string(font, info_rect.position + Vector2(text_x, 77), "БРН %d" % int(leader.get("armor", 0)), HORIZONTAL_ALIGNMENT_LEFT, 60.0, 10, Color.WHITE)
		if int(leader.get("carried_amount", 0)) > 0:
			draw_string(font, info_rect.position + Vector2(text_x, 91), "%s %d" % [String(leader.get("carried_resource", "")).to_upper(), int(leader.get("carried_amount", 0))], HORIZONTAL_ALIGNMENT_LEFT, 60.0, 9, Color("f0d16d"))
		if bool(leader.get("conversion_enabled", false)):
			draw_string(font, info_rect.position + Vector2(text_x, 91), "ВЕРА %d" % roundi(float(leader.get("faith", 0.0))), HORIZONTAL_ALIGNMENT_LEFT, 60.0, 9, Color("d8c8ff"))
		var hp := int(leader.get("hp", 0))
		var max_hp := maxi(1, int(leader.get("max_hp", 1)))
		var hp_ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		var hp_rect := Rect2(info_rect.position + Vector2(5, 91), Vector2(50, 7))
		if not health_status_frames.is_empty():
			var hp_frame := resource_catalog.interface_skin.status_frame_index(hp_ratio, health_status_frames.size())
			draw_texture(health_status_frames[hp_frame], hp_rect.position)
		else:
			draw_rect(hp_rect, Color("351714"), true)
			var hp_color := Color("18d74a") if hp_ratio > 0.5 else Color("e2c62d") if hp_ratio > 0.25 else Color("dc352f")
			draw_rect(Rect2(hp_rect.position + Vector2.ONE, Vector2((hp_rect.size.x - 2.0) * hp_ratio, hp_rect.size.y - 2.0)), hp_color, true)
		draw_string(font, info_rect.position + Vector2(5, 108), "%d/%d" % [hp, max_hp], HORIZONTAL_ALIGNMENT_LEFT, 60.0, 9, Color.WHITE)
	var queue: Array = hud_model.get("queue", [])
	var queue_text := ""
	if not queue.is_empty():
		queue_text = "  Очередь: %s  %d%%" % [String(queue[0].get("label", "")), roundi(float(queue[0].get("progress", 0.0)) * 100.0)]
	if not queue_text.is_empty():
		draw_string(font, command_rect.position + Vector2(4, 116), queue_text.strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, command_rect.size.x - 8.0, 9, Color("e6d6ae"))

	draw_minimap(map_rect)
	if message_time > 0.0:
		var message_rect := Rect2(0.0, viewport_size.y - HUD_BOTTOM - 18.0, width, 18.0)
		draw_rect(message_rect, Color(0.0, 0.0, 0.0, 0.92), true)
		draw_string(font, message_rect.position + Vector2(5, 13), game_message, HORIZONTAL_ALIGNMENT_LEFT, message_rect.size.x - 10.0, 10, Color.WHITE)


func draw_source_hud_shell(layout: Dictionary) -> void:
	var viewport_size: Vector2 = layout["viewport"]
	var bottom_rect: Rect2 = layout["bottom"]
	draw_rect(layout["top"], Color("17130d"), true)
	draw_rect(bottom_rect, Color("4f3926"), true)
	if interface_panel_texture != null:
		var x := 0.0
		while x < viewport_size.x:
			draw_texture(interface_panel_texture, Vector2(x, bottom_rect.position.y))
			x += float(interface_panel_texture.get_width())
	var shell: Dictionary = resource_catalog.interface_skin.hud_shell(int(layout["source_width"]), 0)
	var top_texture: Texture2D = shell.get("top")
	var bottom_texture: Texture2D = shell.get("bottom")
	if top_texture == null or bottom_texture == null:
		return
	if not bool(layout["expanded"]):
		draw_texture(top_texture, Vector2.ZERO)
		draw_texture(bottom_texture, bottom_rect.position)
		return
	var split: Dictionary = layout["wide_split"]
	draw_split_hud_texture(top_texture, 0.0, viewport_size.x, 0.0, split)
	draw_split_hud_texture(bottom_texture, bottom_rect.position.y, viewport_size.x, bottom_rect.position.y, split)


func draw_split_hud_texture(texture: Texture2D, destination_y: float, destination_width: float, _source_y: float, split: Dictionary) -> void:
	var left_width := float(split["left_width"])
	var right_width := float(split["right_width"])
	var right_source_x := float(split["right_source_x"])
	draw_texture_rect_region(texture, Rect2(0, destination_y, left_width, texture.get_height()), Rect2(0, 0, left_width, texture.get_height()))
	draw_texture_rect_region(texture, Rect2(destination_width - right_width, destination_y, right_width, texture.get_height()), Rect2(right_source_x, 0, right_width, texture.get_height()))
	var source_center_width := right_source_x - left_width
	var destination_x := left_width
	var destination_end := destination_width - right_width
	while destination_x < destination_end:
		var piece_width := minf(source_center_width, destination_end - destination_x)
		draw_texture_rect_region(texture, Rect2(destination_x, destination_y, piece_width, texture.get_height()), Rect2(left_width, 0, piece_width, texture.get_height()))
		destination_x += piece_width

func living_player_count() -> int:
	return units.filter(func(unit): return unit["team"] == PLAYER_TEAM and unit["hp"] > 0.0).size()

func unit_display_name(unit: Dictionary) -> String:
	return {"villager": "Villager", "clubman": "Clubman", "archer": "Bowman"}.get(unit["kind"], unit["kind"])

func draw_minimap(rectangle: Rect2) -> void:
	var geometry := minimap_geometry(rectangle)
	var center: Vector2 = geometry["center"]
	var scale: float = geometry["scale"]
	var aperture := PackedVector2Array([
		Vector2(rectangle.get_center().x, rectangle.position.y),
		Vector2(rectangle.end.x, rectangle.get_center().y),
		Vector2(rectangle.get_center().x, rectangle.end.y),
		Vector2(rectangle.position.x, rectangle.get_center().y),
	])
	draw_colored_polygon(aperture, Color.BLACK)
	var map_points := MinimapProjection.map_polygon(map_size, center, scale)
	draw_colored_polygon(map_points, Color("3e7a35"))
	for run_value in fog_runs():
		var run: Dictionary = run_value
		var y := int(run["y"])
		var x_from := int(run["x_from"])
		var x_to := int(run["x_to"])
		var fog_points := PackedVector2Array([
			minimap_position(Vector2(x_from, y), center, scale),
			minimap_position(Vector2(x_to, y), center, scale),
			minimap_position(Vector2(x_to, y + 1), center, scale),
			minimap_position(Vector2(x_from, y + 1), center, scale),
		])
		var fog_color := FogPresentation.color_for_state(int(run["state"]), true)
		draw_colored_polygon(fog_points, fog_color)
	draw_polyline(PackedVector2Array([map_points[0], map_points[1], map_points[2], map_points[3], map_points[0]]), Color("d2bd7d"), 1.0)
	for resource in resource_nodes:
		if resource["amount"] > 0:
			draw_circle(minimap_position(resource["pos"], center, scale), 1.5, Color("18591d"))
	for unit in units:
		if unit["hp"] > 0.0:
			draw_circle(minimap_position(unit["pos"], center, scale), 2.0, Color("40b9ff") if unit["team"] == PLAYER_TEAM else Color("e33d31"))
	for building in presentation_snapshot.get("buildings", []):
		if building["hp"] > 0.0:
			draw_circle(minimap_position(building["pos"], center, scale), 3.0, Color("f0d16d") if building["team"] == PLAYER_TEAM else Color("e33d31"))
	var camera_world := PackedVector2Array([
		Coordinates.clamp_world(screen_to_world(Vector2(0, HUD_TOP)), map_size),
		Coordinates.clamp_world(screen_to_world(Vector2(get_viewport_rect().size.x, HUD_TOP)), map_size),
		Coordinates.clamp_world(screen_to_world(Vector2(get_viewport_rect().size.x, get_viewport_rect().size.y - HUD_BOTTOM)), map_size),
		Coordinates.clamp_world(screen_to_world(Vector2(0, get_viewport_rect().size.y - HUD_BOTTOM)), map_size),
	])
	var camera_points := PackedVector2Array()
	for world_point in camera_world:
		camera_points.append(MinimapProjection.world_to_minimap(world_point, center, scale))
	if camera_points.size() >= 3:
		camera_points.append(camera_points[0])
		draw_polyline(camera_points, Color("f5e28d"), 1.0, true)

func minimap_position(world: Vector2, center: Vector2, scale: float) -> Vector2:
	return MinimapProjection.world_to_minimap(world, center, scale)


func fog_runs() -> Array:
	var revision := int(presentation_snapshot.get("fog_revision", -1))
	if revision != cached_fog_revision:
		var fog_cells: Variant = presentation_snapshot.get("fog", {}).get("cells", [])
		cached_fog_runs = ViewportCulling.fog_runs(fog_cells, map_size, FogOfWar.VISIBLE)
		cached_fog_revision = revision
	return cached_fog_runs


func visible_tile_bounds(margin: int = 4) -> Rect2i:
	var viewport_size := get_viewport_rect().size
	var world_corners: Array[Vector2] = [
		screen_to_world(Vector2(0, HUD_TOP)),
		screen_to_world(Vector2(viewport_size.x, HUD_TOP)),
		screen_to_world(Vector2(viewport_size.x, viewport_size.y - HUD_BOTTOM)),
		screen_to_world(Vector2(0, viewport_size.y - HUD_BOTTOM)),
	]
	return ViewportCulling.tile_bounds(map_size, world_corners, margin)


func minimap_rectangle() -> Rect2:
	return InterfaceLayout.for_viewport(get_viewport_rect().size)["minimap"]


func minimap_geometry(rectangle: Rect2 = Rect2()) -> Dictionary:
	var resolved := rectangle if rectangle.size != Vector2.ZERO else minimap_rectangle()
	var horizontal_padding := 8.0
	var vertical_padding := 6.0
	var span := maxf(1.0, float(map_size.x + map_size.y))
	return {
		"rectangle": resolved,
		"center": resolved.position + Vector2(resolved.size.x * 0.5, vertical_padding),
		"scale": minf((resolved.size.x - horizontal_padding * 2.0) / span, (resolved.size.y - vertical_padding * 2.0) * 2.0 / span),
	}















