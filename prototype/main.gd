extends Node2D

const Coordinates := preload("res://scripts/coordinates.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const GameController := preload("res://scripts/game_controller.gd")
const RoRCommands = preload("res://scripts/commands.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const Diagnostics := preload("res://scripts/diagnostics.gd")
const InputAdapter := preload("res://scripts/input_adapter.gd")
const PointerController := preload("res://scripts/pointer_controller.gd")
const PickingService := preload("res://scripts/picking_service.gd")
const CommandFeedbackRouter := preload("res://scripts/command_feedback_router.gd")
const CommandMarkerPresentation := preload("res://scripts/command_marker_presentation.gd")
const SourceCursorPresentation := preload("res://scripts/source_cursor_presentation.gd")
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
const SoundCueHistory := preload("res://scripts/sound_cue_history.gd")
const PresentationEffectTimeline := preload("res://scripts/presentation_effect_timeline.gd")
const MinimapProjection := preload("res://scripts/minimap_projection.gd")
const MinimapTerrainRaster := preload("res://scripts/minimap_terrain_raster.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const GameCheckpoint := preload("res://scripts/game_checkpoint.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")
const LockstepSession := preload("res://scripts/lockstep_session.gd")
const LockstepTcpRelay := preload("res://scripts/lockstep_tcp_relay.gd")
const AiPlayer := preload("res://scripts/ai_player.gd")
const AiObservationStore := preload("res://scripts/ai_observation_store.gd")
const SpriteGeometry := preload("res://scripts/sprite_geometry.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")
const Footprint := preload("res://scripts/footprint.gd")
const WallPlacement := preload("res://scripts/wall_placement.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const TerrainRenderer := preload("res://scripts/terrain_renderer.gd")
const ScenarioOverlay := preload("res://scripts/scenario_overlay.gd")
const ViewportCulling := preload("res://scripts/viewport_culling.gd")
const TerrainCanvas := preload("res://scripts/terrain_canvas.gd")
const EnvironmentPresentationField := preload("res://scripts/environment_presentation_field.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const FogPresentation := preload("res://scripts/fog_presentation.gd")
const InterfaceLayout := preload("res://scripts/interface_layout.gd")
const MinimapAperture := preload("res://scripts/minimap_aperture.gd")
const MinimapResourceIndex := preload("res://scripts/minimap_resource_index.gd")
const MAP_SEED := 41721
const FormationPreview := preload("res://scripts/formation_preview.gd")
const TILE_WIDTH := Coordinates.TILE_WIDTH
const TILE_HEIGHT := Coordinates.TILE_HEIGHT
const MAP_SIZE := Vector2i(24, 24)
const PLAYER_TEAM := 1
const ENEMY_TEAM := 2
const HUD_TOP := InterfaceLayout.TOP_HEIGHT
const HUD_BOTTOM := InterfaceLayout.BOTTOM_HEIGHT
# Minimap intelligence is intentionally decoupled from the 20 Hz simulation.
# At the default 1.5x speed this publishes roughly three times per second while
# the camera rectangle remains frame-smooth. The mesh no longer invalidates on
# intermediate fog revisions, so the cadence actually bounds rebuild spikes.
const OVERVIEW_REFRESH_TICKS := 10
const WORLD_FOG_GEOMETRY_CHUNK_SIZE := 16
const WORLD_FOG_GEOMETRY_RETAIN_MARGIN := 1
const MAX_PRESENTATION_EVENT_HISTORY := 16384
const PRESENTATION_EVENT_HISTORY_TAIL := 4096

@export_file("*.json") var match_path: String = MatchDefinition.DEFAULT_PATH
var match_definition_override: Dictionary = {}

var view_offset := Vector2.ZERO
var view_zoom := 1.0
var map_size := MAP_SIZE
var map_seed := MAP_SEED
var match_definition: Dictionary = {}
var map_definition_override: Dictionary = {}
var map_definition: Dictionary = {}
var ai_players: Array = []
var ai_observation_store := AiObservationStore.new()
var input_adapter := InputAdapter.new()
var picking_service := PickingService.new()
var selection_preview_ids: Array[int] = []
var command_feedback_router := CommandFeedbackRouter.new()
var command_marker_presentation := CommandMarkerPresentation.new()
var interaction_highlight_id: int = -1
var interaction_cursor_semantic := "default"
var source_cursor_frame_applied := -1
var source_cursor_frames: Array[Texture2D] = []
var source_command_marker_frames: Dictionary = {}
var control_groups := ControlGroups.new()
var player_control_state := PlayerControlState.new(PLAYER_TEAM)
var local_player_team: int = PLAYER_TEAM
var network_role := ""
var network_address := "127.0.0.1"
var network_port: int = 39741
var network_session
var network_relay
var network_accumulator := 0.0
var network_hello_cooldown := 0.0
var network_frame_submitted_tick := 0
var pending_network_commands: Array = []
var network_sent_commands: Dictionary = {}
var network_feedback_by_command: Dictionary = {}
var network_chat_input: LineEdit

var units: Array = []
var resource_nodes: Array = []
var overview_units: Array = []
var overview_resource_nodes: Array = []
var overview_buildings: Array = []
var presentation_snapshot: Dictionary = {}
var formation := "RECTANGLE"
var pending_build_kind := ""
var pending_build_started := false
var resource_feedback_id := -1
var resource_feedback_time := 0.0
var placement_preview_key := ""
var placement_preview_valid := false
var pending_target_command := ""
var game_message := "Выберите отряд и отдайте приказ правой кнопкой"
var message_time := 5.0
var battle_over := false
var local_spectator := false
var diagnostics_enabled := false

var terrain_textures := {}
var terrain_border_textures := {}
var tree_texture: Texture2D
var berry_texture: Texture2D
var interface_panel_texture: Texture2D
var interface_style_index := 0
var health_status_frames: Array[Texture2D] = []
var unit_textures := {}
var gamespec_data: Dictionary = {}
var audio_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_round_robin: int = 0
var presentation_audio_router := PresentationAudioRouter.new()
var presentation_audio_event_router := PresentationAudioEventRouter.new()
var sound_cue_history := SoundCueHistory.new()
var compact_status_visible := false
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
var cached_hud_signature: Variant = null
var scenario_overlay: ScenarioOverlay
var terrain_canvas: TerrainCanvas
var cached_fog_revision: int = -1
var cached_fog_runs: Array = []
var cached_world_fog_meshes: Dictionary = {}
var cached_world_fog_mesh_terrain_revision: int = -1
var cached_world_fog_texture: ImageTexture
var cached_world_fog_texture_data := PackedByteArray()
var cached_world_fog_texture_revision: int = -1
var cached_fog_slope_neighbor_cells := PackedByteArray()
var cached_fog_slope_neighbor_terrain_revision: int = -1
var cached_map_edge_chains: Array[PackedVector2Array] = []
var cached_map_edge_fog_meshes: Dictionary = {}
var cached_map_edge_fog_revision := -1
var cached_map_edge_zoom := -1.0
var cached_map_edge_terrain_revision := -1
var cached_minimap_mesh: ArrayMesh
var cached_minimap_terrain_texture: ImageTexture
var cached_minimap_terrain_revision: int = -1
var cached_minimap_terrain_rectangle := Rect2()
var cached_minimap_fog_texture: ImageTexture
var cached_minimap_fog_image: Image
var cached_minimap_exploration_revision: int = -1
var cached_minimap_fog_rectangle := Rect2()
var cached_minimap_mesh_tick: int = -1
var cached_minimap_mesh_rectangle := Rect2()
var minimap_resource_index := MinimapResourceIndex.new()
var presentation_revision: int = 0
var cached_presentation_tick: int = -1
var cached_presentation_bounds := Rect2i()
var cached_presentation_selection_signature: int = 0
var cached_presentation_diagnostics := false
var cached_overview_tick: int = -1
var cached_overview_resource_revision: int = -1
var cached_environment_revision := 0
var cached_environment_bounds := Rect2i()
var cached_environment_items: Array = []
var cached_world_drawables: Array = []
var cached_world_drawables_revision: int = -1
var cached_world_drawables_control_signature: int = 0
var cached_projection_offset := Vector2(INF, INF)
var cached_projection_zoom := -1.0

func _ready() -> void:
	font = ThemeDB.fallback_font
	resource_catalog = ResourceCatalog.new()
	resource_catalog.load()
	for frame_index in range(7):
		source_cursor_frames.append(load("res://assets/generated/ror_cursor_%02d.png" % frame_index))
	for frame_index in range(1, 7):
		source_command_marker_frames[frame_index] = load("res://assets/generated/ror_command_marker_%02d.png" % frame_index)
	_install_source_control_cursors()
	_apply_source_cursor("default")
	match_definition = match_definition_override.duplicate(true) if not match_definition_override.is_empty() else MatchDefinition.load_json(match_path)
	if not match_definition_override.is_empty():
		match_definition["source_path"] = match_path
	if not bool(match_definition.get("valid", false)):
		push_error("Invalid match definition: %s" % [str(match_definition.get("errors", []))])
		return
	if network_role.is_empty():
		local_player_team = int(match_definition.get("local_team", PLAYER_TEAM))
	player_control_state.player_id = local_player_team
	var environment_items: Array = match_definition.get("presentation_environment", []).duplicate(true)
	environment_items.append_array(match_definition.get("static_obstructions", []))
	map_definition = map_definition_override.duplicate(true) if not map_definition_override.is_empty() else RandomMapGenerator.generate(match_definition)
	if map_definition.has("generation_error"):
		push_error(String(map_definition["generation_error"]))
		return
	var expected_map_hash := String(match_definition.get("map", {}).get("content_hash", ""))
	if not expected_map_hash.is_empty() and expected_map_hash != String(map_definition.get("content_hash", "")):
		push_error("Сохранённая карта не соответствует версии генератора")
		return
	if String(map_definition.get("environment_pack", "")) == "aoe2_temperate":
		resource_catalog.enable_environment_pack()
	environment_items.append_array(map_definition.get("scenery", []))
	environment_items.append_array(map_definition.get("cliff_obstructions", []))
	environment_presentation_field.configure(environment_items)
	map_size = map_definition.get("size", MAP_SIZE)
	map_seed = int(map_definition.get("seed", MAP_SEED))

	gamespec_data = resource_catalog.gamespec_data
	terrain_textures = resource_catalog.terrain_textures
	terrain_border_textures = resource_catalog.terrain_border_textures
	tree_texture = resource_catalog.tree_texture
	berry_texture = resource_catalog.berry_texture
	interface_style_index = resource_catalog.interface_skin.style_index_for_match(match_definition, resource_catalog.object_catalog_data)
	interface_panel_texture = resource_catalog.interface_skin.panel_texture(interface_style_index)
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
	hud_controls.configure_interface_skin(resource_catalog.interface_skin, interface_style_index)
	hud_controls.position = Vector2.ZERO
	hud_controls.size = get_viewport_rect().size
	hud_controls.formation_requested.connect(set_formation)
	hud_controls.build_requested.connect(begin_build_placement)
	hud_controls.build_menu_opened.connect(cancel_pending_targeting)
	hud_controls.train_requested.connect(train_unit_from_hud)
	hud_controls.research_requested.connect(research_from_hud)
	hud_controls.cancel_production_requested.connect(cancel_production_from_hud)
	hud_controls.trade_resource_requested.connect(set_trade_resource_from_hud)
	hud_controls.unit_action_requested.connect(issue_unit_action)
	hud_controls.building_selected.connect(select_hud_building)
	top_bar_controls = TopBarControls.new()
	add_child(top_bar_controls)
	top_bar_controls.configure(resource_catalog.interface_skin, interface_style_index)
	top_bar_controls.set_viewport_size(get_viewport_rect().size)
	top_bar_controls.diplomacy_requested.connect(_show_diplomacy_summary)
	top_bar_controls.menu_requested.connect(_toggle_game_menu)
	hud_modal_overlay = HUDModalOverlay.new()
	add_child(hud_modal_overlay)
	hud_modal_overlay.configure(resource_catalog.interface_skin, match_definition, interface_style_index, resource_catalog.localization)
	hud_modal_overlay.set_viewport_size(get_viewport_rect().size)
	hud_modal_overlay.close_requested.connect(_close_hud_modal)
	hud_modal_overlay.save_requested.connect(_save_quick_game)
	hud_modal_overlay.load_requested.connect(_load_quick_game)
	hud_modal_overlay.named_save_requested.connect(_save_named_game)
	hud_modal_overlay.named_load_requested.connect(_load_named_game)
	hud_modal_overlay.resign_requested.connect(_resign_from_hud_modal)
	hud_modal_overlay.launcher_requested.connect(_return_to_launcher)
	hud_modal_overlay.diplomacy_relation_requested.connect(_change_diplomacy_from_hud)
	hud_modal_overlay.tribute_requested.connect(_pay_tribute_from_hud)
	scenario_overlay = ScenarioOverlay.new()
	add_child(scenario_overlay)
	scenario_overlay.configure(match_definition, resource_catalog.localization, resource_catalog.object_catalog_data)
	scenario_overlay.restart_requested.connect(_restart_from_scenario_overlay)
	scenario_overlay.menu_requested.connect(_return_to_launcher)

	reset_game()
	if not network_role.is_empty():
		_start_network_match()
		if network_session != null:
			_create_network_chat_input()
	setup_audio()
	setup_sfx()
	get_viewport().size_changed.connect(center_initial_view)
	center_initial_view()
func unit_stats(kind: String) -> Dictionary:
	if simulation_world == null:
		return gamespec_data.get("units", {}).get(kind, {})
	return simulation_world.unit_stats(kind)


func _new_simulation_world(size_override: Vector2i = Vector2i.ZERO):
	var world = SimulationWorld.new(size_override if size_override != Vector2i.ZERO else map_size)
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
	presentation_audio_router.configure(resource_catalog.runtime_catalog_data, resource_catalog.sound_catalog_data, resource_catalog.asset_records, resource_catalog.graphics_catalog_data, resource_catalog.object_catalog_data, resource_catalog.audio_asset_files_by_resource_id)
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
	if network_chat_input != null:
		network_chat_input.position = Vector2(16, size.y - hud_bottom_height() - 40)
	var initial_world := Vector2(map_size.x / 2.0, map_size.y / 2.0)
	var local_team := local_player_team
	for player_value in match_definition.get("players", []):
		var player: Dictionary = player_value
		if int(player.get("team", 0)) == local_team:
			initial_world = player.get("start", initial_world)
			break
	var initial_screen := iso_raw(initial_world) * view_zoom
	view_offset = Vector2(size.x * 0.5, (size.y - hud_bottom_height() + hud_top_height()) * 0.48) - initial_screen
	_sync_terrain_canvas()
	queue_redraw()

func reset_game() -> void:
	if simulation_world == null:
		return
	var bootstrap: Dictionary = MatchBootstrap.apply(simulation_world, match_definition, map_definition)
	resource_catalog.prewarm_match_entities(simulation_world.get_units(), simulation_world.get_buildings())
	game_controller.reset_timing()
	game_controller.start_recording(map_seed, false)
	game_controller.set_command_result_limit(1024)
	configure_ai_players()
	# Full-map masks and surface connectivity are loading work, not work for
	# the first AI decision or the first unit movement after the match opens.
	simulation_world.pathfinder.prepare_native_kernels_for_units(simulation_world.get_units())
	for ai in ai_players:
		simulation_world.ai_navigation_knowledge.snapshot(simulation_world, simulation_world.get_fog_of_war(), int(ai.team))
	game_controller.set_before_fixed_tick(Callable(self, "queue_ai_commands"))
	control_groups.clear()
	player_control_state.clear()
	sound_cue_history.reset()
	compact_status_visible = false
	local_spectator = false
	input_adapter.reset()
	command_feedback_router.reset()
	command_feedback_router.event_cursor = game_controller.event_stream.latest_sequence()
	game_controller.event_stream.prune_through(command_feedback_router.event_cursor)
	presentation_effect_timeline.reset()
	cached_fog_revision = -1
	cached_fog_runs.clear()
	cached_world_fog_meshes.clear()
	cached_world_fog_mesh_terrain_revision = -1
	cached_world_fog_texture = null
	cached_world_fog_texture_data.resize(0)
	cached_world_fog_texture_revision = -1
	cached_fog_slope_neighbor_cells.resize(0)
	cached_fog_slope_neighbor_terrain_revision = -1
	cached_map_edge_chains.clear()
	cached_map_edge_fog_meshes.clear()
	cached_map_edge_fog_revision = -1
	cached_map_edge_zoom = -1.0
	cached_map_edge_terrain_revision = -1
	cached_minimap_mesh = null
	cached_minimap_terrain_texture = null
	cached_minimap_terrain_revision = -1
	cached_minimap_terrain_rectangle = Rect2()
	cached_minimap_fog_texture = null
	cached_minimap_fog_image = null
	cached_minimap_exploration_revision = -1
	cached_minimap_fog_rectangle = Rect2()
	cached_minimap_mesh_tick = -1
	cached_minimap_mesh_rectangle = Rect2()
	minimap_resource_index.clear()
	cached_overview_tick = -1
	cached_overview_resource_revision = -1
	cached_hud_signature = null
	cached_environment_bounds = Rect2i()
	cached_environment_items.clear()
	if render_world != null:
		render_world.clear_caches()
	command_marker_presentation.reset()
	interaction_highlight_id = -1
	_apply_source_cursor("default")
	units.clear()
	resource_nodes.clear()
	overview_units.clear()
	overview_resource_nodes.clear()
	overview_buildings.clear()

	formation = "RECTANGLE"
	pending_build_kind = ""
	pending_target_command = ""
	player_control_state.replace_or_add(bootstrap.get("selected_ids", []), false)

	sync_world_state()
	# The initial fog mask scans the whole map; prepare it while the match is
	# loading, so the first visible frame only submits cached presentation.
	cached_fog_slope_neighbor_terrain_revision = int(simulation_world.terrain_revision)
	_sync_world_fog_texture(presentation_snapshot.get("fog", {}).get("cells", []), int(presentation_snapshot.get("fog_revision", -1)))
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
	if selected and team == local_player_team:
		player_control_state.replace_or_add([int(unit["id"])], true)
	return unit

func add_resource(kind: String, position: Vector2, amount: int) -> void:
	if simulation_world == null:
		return
	simulation_world.add_resource(kind, position, amount)
func _process(delta: float) -> void:
	var probe: Variant = game_controller.performance_probe if game_controller != null else null
	var frame_started := Time.get_ticks_usec() if probe != null else 0
	var stage_started := frame_started
	presentation_audio_router.advance(delta)
	presentation_effect_timeline.advance(delta)
	_sync_effect_snapshot()
	if network_session != null:
		_network_update(delta)
	if probe != null:
		probe.observe_microseconds("presentation.process.audio_effects", Time.get_ticks_usec() - stage_started)
	if scenario_overlay != null and scenario_overlay.is_blocking():
		return
	if hud_modal_overlay != null and hud_modal_overlay.is_blocking():
		return
	stage_started = Time.get_ticks_usec() if probe != null else 0
	update_camera(delta)
	_sync_terrain_canvas()
	if probe != null:
		probe.observe_microseconds("presentation.process.camera_terrain", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	if network_session == null:
		update_units(delta)
	if probe != null:
		probe.observe_microseconds("presentation.process.update_units", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	if message_time > 0.0:
		message_time -= delta
	command_marker_presentation.advance(delta)
	resource_feedback_time = maxf(0.0, resource_feedback_time - delta)
	queue_redraw()
	if probe != null:
		probe.observe_microseconds("presentation.process.feedback", Time.get_ticks_usec() - stage_started)
		probe.observe_microseconds("presentation.process.total", Time.get_ticks_usec() - frame_started)

func update_camera(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y -= 1.0
	if get_window().has_focus():
		direction += PointerController.edge_scroll_direction(get_viewport().get_mouse_position(), get_viewport_rect().size, PointerController.EDGE_SCROLL_MARGIN, hud_top_height(), hud_bottom_height())
	if direction != Vector2.ZERO:
		view_offset += direction.normalized() * 430.0 * delta

func update_units(delta: float) -> void:
	if game_controller == null or simulation_world == null:
		return
	var probe: Variant = game_controller.performance_probe
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	var battle_text := game_controller.advance_frame(delta, local_player_team, ENEMY_TEAM)
	if probe != null:
		probe.observe_microseconds("presentation.update.controller", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	sync_world_state(false)
	if probe != null:
		probe.observe_microseconds("presentation.update.snapshot", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	process_presentation_events()
	if probe != null:
		probe.observe_microseconds("presentation.update.events", Time.get_ticks_usec() - stage_started)
	if battle_text != "":
		game_message = battle_text
		message_time = 2.0


func _start_network_match() -> void:
	var participants: Array[int] = []
	for player_value in match_definition.get("players", []):
		var player: Dictionary = player_value
		if String(player.get("controller", "")) in ["human", "remote"]:
			participants.append(int(player.get("team", 0)))
		elif String(player.get("controller", "")) == "ai":
			game_message = "AI-места в сетевом матче пока не поддерживаются"
			return
	participants.sort()
	network_session = LockstepSession.new()
	var error: String = network_session.configure(game_controller, match_definition, map_seed, participants, local_player_team)
	if not error.is_empty():
		network_session = null
		game_message = "Сетевой матч не создан: %s" % error
		game_controller.set_paused(true)
		return
	game_controller.set_before_fixed_tick(Callable())
	network_relay = LockstepTcpRelay.new()
	if network_role == "host":
		error = network_relay.start_server(network_port, participants, participants[0], "0.0.0.0")
	elif network_role == "join":
		error = network_relay.connect_client(network_address, network_port)
	else:
		error = "network_role_invalid"
	if not error.is_empty():
		network_session = null
		network_relay = null
		game_message = "Сетевое соединение не создано: %s" % error
		game_controller.set_paused(true)
		return
	game_message = "Ожидание сетевых игроков…"
	message_time = 30.0


func _queue_local_command(command) -> void:
	if network_session == null:
		game_controller.enqueue_command(command, true, local_player_team)
		return
	command.tick = maxi(int(command.tick), network_frame_submitted_tick + 1)
	pending_network_commands.append(command)


func _register_local_feedback(command, accepted_message: String, sound_name: String, marker: Variant) -> void:
	if network_session == null:
		command_feedback_router.register(command, accepted_message, sound_name, marker)
	else:
		network_feedback_by_command[command.get_instance_id()] = {"accepted_message": accepted_message, "sound_name": sound_name, "marker": marker}


func _network_update(delta: float) -> void:
	if network_relay == null or network_session.phase == "aborted":
		return
	for event in network_relay.poll_events():
		match String(event.get("kind", "")):
			"packet":
				var packet: Dictionary = event["packet"]
				var error: String = network_session.receive_packet(packet)
				if not error.is_empty():
					game_message = "Сетевой матч остановлен: %s" % error
					message_time = 30.0
				elif String(packet.get("kind", "")) == "chat" and not network_session.chat_messages.is_empty():
					var latest: Dictionary = network_session.chat_messages.back()
					if latest == packet:
						game_message = "[%d] %s" % [int(packet.get("sender_team", 0)), String(packet.get("text", ""))]
						message_time = 5.0
			"disconnected":
				game_message = "Сетевой матч остановлен: %s" % network_session.peer_disconnected(int(event.get("team", -1)))
				message_time = 30.0
			"transport_error":
				game_message = "Сетевая ошибка: %s" % String(event.get("reason", ""))
				message_time = 5.0
	if network_session.phase == "aborted":
		return
	network_hello_cooldown -= delta
	if network_hello_cooldown <= 0.0:
		if network_relay.send_packet(network_session.hello_packet()).is_empty():
			network_hello_cooldown = 0.5
	if network_session.phase != "running":
		return
	var next_tick := int(game_controller.tick_index) + 1
	if network_frame_submitted_tick < next_tick:
		var commands: Array = []
		for command in pending_network_commands:
			if int(command.tick) == next_tick:
				commands.append(command)
		var frame: Dictionary = network_session.frame_packet(next_tick, commands)
		if not frame.is_empty() and network_relay.send_packet(frame).is_empty():
			network_frame_submitted_tick = next_tick
			network_sent_commands[next_tick] = commands
			pending_network_commands = pending_network_commands.filter(func(command): return int(command.tick) > next_tick)
		else:
			network_session.abort_packet("transport_send_failed")
			game_message = "Сетевой матч остановлен: transport_send_failed"
			message_time = 30.0
			return
	network_accumulator = minf(0.25, network_accumulator + delta)
	if network_accumulator < game_controller.FIXED_STEP_SECONDS or not network_session.can_advance():
		return
	var step: Dictionary = network_session.advance_one()
	if not bool(step.get("advanced", false)):
		game_message = "Сетевой матч остановлен: %s" % String(step.get("reason", ""))
		message_time = 30.0
		return
	var applied_tick := int(step.get("tick", -1))
	var original_commands: Array = network_sent_commands.get(applied_tick, [])
	var sequence_ids: Array = step.get("local_sequence_ids", [])
	for index in range(mini(original_commands.size(), sequence_ids.size())):
		var original = original_commands[index]
		var identity: int = int(original.get_instance_id())
		if network_feedback_by_command.has(identity):
			original.assign_envelope(local_player_team, int(sequence_ids[index]))
			var feedback: Dictionary = network_feedback_by_command[identity]
			command_feedback_router.register(original, String(feedback["accepted_message"]), String(feedback["sound_name"]), feedback["marker"])
			network_feedback_by_command.erase(identity)
	network_sent_commands.erase(applied_tick)
	network_accumulator -= game_controller.FIXED_STEP_SECONDS
	if not step.get("hash_packet", {}).is_empty():
		network_relay.send_packet(step["hash_packet"])
	sync_world_state(false)
	process_presentation_events()
	var battle_text: String = simulation_world.get_last_battle_message()
	if not battle_text.is_empty():
		game_message = battle_text
		message_time = 2.0


func _create_network_chat_input() -> void:
	network_chat_input = LineEdit.new()
	network_chat_input.placeholder_text = "Enter: союзный чат  /all: всем  /pop N: лимит хоста"
	network_chat_input.size = Vector2(470, 32)
	network_chat_input.position = Vector2(16, get_viewport_rect().size.y - hud_bottom_height() - 40)
	network_chat_input.visible = false
	network_chat_input.text_submitted.connect(_submit_network_chat)
	network_chat_input.gui_input.connect(_network_chat_gui_input)
	add_child(network_chat_input)


func _network_chat_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		network_chat_input.hide()
		network_chat_input.release_focus()
		get_viewport().set_input_as_handled()


func _submit_network_chat(raw_text: String) -> void:
	if network_chat_input != null:
		network_chat_input.clear()
		network_chat_input.hide()
		network_chat_input.release_focus()
	if network_session == null or network_session.phase != "running":
		return
	var message := raw_text.strip_edges()
	if message.is_empty():
		return
	if message.begins_with("/pop "):
		var requested := message.substr(5).strip_edges()
		if local_player_team == 1 and requested.is_valid_int() and int(requested) >= 1 and int(requested) <= 500:
			_queue_local_command(RoRCommands.PopulationLimitCommand.new(game_controller.tick_index + 1, int(requested)))
			game_message = "Новый лимит населения: %s" % requested
		else:
			game_message = "Только хост может менять лимит от 1 до 500"
		message_time = 4.0
		return
	var channel := "allies"
	if message.begins_with("/all "):
		channel = "all"
		message = message.substr(5).strip_edges()
	var packet: Dictionary = network_session.chat_packet(message, channel)
	if packet.is_empty():
		return
	if network_relay.send_packet(packet).is_empty():
		game_message = "[%d] %s" % [local_player_team, message]
		message_time = 5.0


func configure_ai_players() -> void:
	ai_observation_store.clear()
	ai_players = _new_ai_players()
	_configure_runtime_ai_cadence(ai_players)


func _configure_runtime_ai_cadence(players: Array) -> void:
	for ai_value in players:
		var ai = ai_value
		if String(ai.profile) != "source_campaign_v1":
			continue
		# Strategic economy and campaign group planning are deliberately slower
		# than the 20 Hz tactical simulation. Explicit fast scenario cadences
		# remain intact; imported one-second defaults receive a two-second floor.
		if int(ai.economic_interval) >= 20:
			ai.economic_interval = maxi(int(ai.economic_interval), 40)
		if int(ai.military_interval) >= 20:
			ai.military_interval = maxi(int(ai.military_interval), 40)


func _new_ai_players(definition: Dictionary = {}) -> Array:
	var result: Array = []
	for player_value in (definition if not definition.is_empty() else match_definition).get("players", []):
		var player: Dictionary = player_value
		if String(player.get("controller", "ai")) == "ai":
			var ai := AiPlayer.new(player)
			if ai.enabled:
				result.append(ai)
	return result


func queue_ai_commands(next_tick: int = -1) -> bool:
	if next_tick < 0:
		next_tick = game_controller.tick_index + 1
	var probe: Variant = game_controller.performance_probe
	var planned := false
	for ai_value in ai_players:
		var ai = ai_value
		if not ai.needs_decision(next_tick):
			continue
		# Fresh AIs used to perform their expensive first economy and military
		# plans on the same simulation tick. Give every team a stable phase so
		# campaign starts do not turn six independent planners into one frame
		# spike. The phase depends only on authoritative data, never render time.
		if int(ai.last_economic_tick) < 0 and int(ai.last_military_tick) < 0:
			var initial_decision_tick: int = AiPlayer.initial_decision_tick(ai, ai_players)
			if next_tick < initial_decision_tick:
				continue
		planned = true
		var stage_started := Time.get_ticks_usec() if probe != null else 0
		var snapshot_options: Dictionary = ai.presentation_options()
		if probe != null:
			snapshot_options["performance_probe"] = probe
			snapshot_options["performance_prefix"] = "presentation.ai.snapshot"
		var knowledge := ai_observation_store.observe(simulation_world, game_controller.tick_index, int(ai.team), snapshot_options)
		if probe != null:
			probe.observe_microseconds("presentation.ai.snapshot", Time.get_ticks_usec() - stage_started)
			stage_started = Time.get_ticks_usec()
		var commands: Array = ai.collect_commands(knowledge, next_tick)
		if probe != null:
			probe.observe_microseconds("presentation.ai.plan", Time.get_ticks_usec() - stage_started)
			stage_started = Time.get_ticks_usec()
		for command in commands:
			game_controller.enqueue_command(command, true, int(ai.team))
		if probe != null:
			probe.observe_microseconds("presentation.ai.enqueue", Time.get_ticks_usec() - stage_started)
	return planned


func enqueue_with_feedback(command: Variant, accepted_message: String, sound_name: String, marker: Variant = null) -> void:
	if local_spectator or battle_over:
		return
	_queue_local_command(command)
	_register_local_feedback(command, accepted_message, sound_name, marker)


func process_presentation_events() -> void:
	var new_events := game_controller.events_after(command_feedback_router.event_cursor)
	for feedback in command_feedback_router.consume(new_events, local_player_team):
		var quiet_order := bool(feedback["accepted"]) and String(feedback.get("command_type", "")) in ["train", "research", "cancel_production"]
		if not quiet_order:
			game_message = String(feedback["message"])
		if bool(feedback["accepted"]):
			var sound_name := String(feedback["sound_name"])
			if not sound_name.is_empty():
				play_sfx(sound_name)
			if feedback["marker"] is Vector2:
				command_marker_presentation.trigger(feedback["marker"])
			elif feedback["marker"] is Dictionary:
				resource_feedback_id = int(feedback["marker"].get("entity_id", feedback["marker"].get("resource_id", -1)))
				resource_feedback_time = 0.7
		message_time = 0.0 if quiet_order else 1.8
	presentation_effect_timeline.consume(new_events, Callable(self, "presentation_effect_visible"))
	_sync_effect_snapshot()
	process_world_audio_events(new_events)
	for cue in sound_cue_history.consume_distress(presentation_snapshot.get("ai_distress_signals", []), local_player_team, game_controller.tick_index):
		play_audio_request(presentation_audio_router.request_sound_id(10, "combat", -1, int(cue["sequence"])))
	# All presentation consumers have now observed these events. Keep a short
	# diagnostic tail while bounding the journal retained by a long live match.
	# Controllers used by replay/scenario tests do not opt into this pruning.
	if game_controller.event_stream.retained_count() > MAX_PRESENTATION_EVENT_HISTORY:
		game_controller.event_stream.prune_through(command_feedback_router.event_cursor - PRESENTATION_EVENT_HISTORY_TAIL)


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
	if network_chat_input != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and not network_chat_input.visible:
		network_chat_input.show()
		network_chat_input.grab_focus()
		get_viewport().set_input_as_handled()
		return
	if hud_modal_overlay != null and hud_modal_overlay.is_blocking():
		return
	if scenario_overlay != null and scenario_overlay.is_blocking():
		return
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed:
		if event.keycode == KEY_ESCAPE:
			if cancel_pending_targeting() or (hud_controls != null and hud_controls.build_menu_open and hud_controls.set_build_menu_open(false)):
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_B and hud_controls != null and hud_controls.set_build_menu_open(true):
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_R and not battle_over and not repair_workers().is_empty():
			begin_repair()
			get_viewport().set_input_as_handled()
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
	if not MinimapAperture.contains(screen_position, geometry["rectangle"]) or not MinimapProjection.contains_world(screen_position, map_size, geometry["center"], geometry["scale"]):
		return false
	center_view_on_world(MinimapProjection.minimap_to_world(screen_position, geometry["center"], geometry["scale"]))
	queue_redraw()
	return true


func handle_input_action(action: Dictionary) -> void:
	if local_spectator and String(action.get("type", "")) not in ["consume_outside_world", "zoom", "pointer_moved", "toggle_audio", "toggle_pause", "change_speed", "toggle_diagnostics", "toggle_status_indicators", "next_sound_cue", "reset_game", "quit"]:
		return
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
				finish_selection(action["from"], action["to"], String(action.get("mode", "select_click")))
			else:
				commit_build_placement(action["to"], bool(action.get("queue_order", false)), action["from"])
			selection_preview_ids.clear()
		"context_committed":
			if pending_target_command == "repair":
				cancel_pending_targeting()
			elif not pending_target_command.is_empty():
				commit_pending_target(action["position"])
			elif pending_build_kind.is_empty():
				issue_order(action["position"], action.get("direction_end"), bool(action.get("queue_order", false)))
			else:
				pending_build_kind = ""
				pending_build_started = false
				update_interaction_cursor(input_adapter.pointer_position)
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
		"attack_ground_mode":
			begin_attack_ground()
		"stop":
			issue_unit_action("stop")
		"hold":
			issue_unit_action("hold")
		"cycle_stance":
			issue_unit_action("stance")
		"train":
			request_primary_train_command()
		"train_shortcut":
			request_train_shortcut(String(action.get("archetype", "")))
		"toggle_status_indicators":
			compact_status_visible = not compact_status_visible
			queue_redraw()
		"next_sound_cue":
			var cue := sound_cue_history.next_cue()
			if not cue.is_empty():
				center_view_on_world(cue["position"])
				queue_redraw()
		"toggle_audio":
			audio_player.stream_paused = not audio_player.stream_paused
			for player in sfx_players:
				player.stream_paused = audio_player.stream_paused
		"toggle_pause":
			if network_session != null:
				game_message = "Пауза в сетевом матче недоступна"
				return
			var is_paused := game_controller.toggle_paused()
			game_message = "Пауза" if is_paused else "Игра продолжена"
			message_time = 1.5
		"change_speed":
			if network_session != null:
				game_message = "Скорость сетевого матча фиксирована"
				return
			var speed := game_controller.cycle_speed(int(action["direction"]))
			game_message = "Скорость игры: %.1fx" % speed
			message_time = 1.5
		"toggle_diagnostics":
			diagnostics_enabled = not diagnostics_enabled
			game_message = "Диагностика включена" if diagnostics_enabled else "Диагностика выключена"
			message_time = 1.5
		"open_calibration":
			get_tree().change_scene_to_file("res://calibration.tscn")
		"delete_context":
			issue_delete_context()
		"unload":
			issue_unload_at_pointer(bool(action.get("queue_order", false)))
		"reset_game":
			if network_session == null:
				reset_game()
			else:
				game_message = "Перезапуск сетевого матча требует нового лобби"
		"resign":
			var command = RoRCommands.ResignCommand.new(game_controller.tick_index + 1)
			_queue_local_command(command)
			_register_local_feedback(command, "Вы сдались", "", null)
		"quit":
			get_tree().quit()


func _show_diplomacy_summary() -> void:
	_open_hud_modal(HUDModalOverlay.MODE_DIPLOMACY)


func _change_diplomacy_from_hud(target_team: int, relation: String) -> void:
	if game_controller == null or local_spectator or battle_over or not RoRCommands.is_valid_diplomacy_relation(relation):
		return
	var command = RoRCommands.DiplomacyCommand.new(game_controller.tick_index + 1, target_team, relation)
	_queue_local_command(command)
	_register_local_feedback(command, "Дипломатия изменена", "", null)


func _pay_tribute_from_hud(target_team: int, resource_type_id: int, amount: int) -> void:
	if game_controller == null or local_spectator or battle_over:
		return
	var command = RoRCommands.TributeCommand.new(game_controller.tick_index + 1, target_team, resource_type_id, amount)
	_queue_local_command(command)
	_register_local_feedback(command, "Дань отправлена", "", null)


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
	if network_session == null:
		game_controller.set_paused(true)
	hud_modal_overlay.set_snapshot(presentation_snapshot)
	if mode == HUDModalOverlay.MODE_DIPLOMACY:
		hud_modal_overlay.show_diplomacy()
	else:
		hud_modal_overlay.set_save_available(FileAccess.file_exists(GameSaveArchive.SAVE_PATH))
		hud_modal_overlay.set_named_saves(GameSaveArchive.list_named_saves())
		hud_modal_overlay.set_menu_status("")
		hud_modal_overlay.show_menu()


func _close_hud_modal() -> void:
	if hud_modal_overlay == null or not hud_modal_overlay.is_blocking():
		return
	hud_modal_overlay.close()
	if game_controller != null and network_session == null:
		game_controller.set_paused(modal_restore_paused)
	game_message = "Пауза" if modal_restore_paused else "Игра продолжена"
	message_time = 1.5


func _resign_from_hud_modal() -> void:
	if hud_modal_overlay != null:
		hud_modal_overlay.close()
	if game_controller == null or local_spectator or battle_over:
		return
	game_controller.set_paused(false)
	var command = RoRCommands.ResignCommand.new(game_controller.tick_index + 1)
	_queue_local_command(command)
	_register_local_feedback(command, "Вы сдались", "", null)


func _save_quick_game() -> void:
	if save_game_to_path(GameSaveArchive.SAVE_PATH):
		hud_modal_overlay.set_save_available(true)
		hud_modal_overlay.set_menu_status("Игра сохранена")
	else:
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)


func _load_quick_game() -> void:
	if not load_game_from_path(GameSaveArchive.SAVE_PATH):
		if hud_modal_overlay != null:
			hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)


func _save_named_game(name: String) -> void:
	var path: String = GameSaveArchive.named_path(name)
	if path.is_empty():
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message("slot_name_invalid"), true)
		return
	if save_game_to_path(path, GameSaveArchive.normalized_slot_name(name)):
		hud_modal_overlay.set_named_saves(GameSaveArchive.list_named_saves())
		hud_modal_overlay.set_menu_status("Именованное сохранение создано")
	else:
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)


func _load_named_game(path: String) -> void:
	if not load_game_from_path(path):
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)


func save_game_to_path(path: String, slot_name: String = "Быстрое сохранение") -> bool:
	last_save_error = ""
	if network_session != null:
		last_save_error = "network_save_unsupported"
		return false
	if not GameSaveArchive.valid_slot_name(slot_name):
		last_save_error = "slot_name_invalid"
		return false
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
		"last_known_buildings": simulation_world.last_known_buildings_by_player.duplicate(true),
		"last_known_resources": simulation_world.known_resource_memory_state(),
		"last_recalled_group": control_groups.last_recalled_group,
		"compact_status_visible": compact_status_visible,
		"sound_cue_history": sound_cue_history.canonical_state(),
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
		controller_state,
		slot_name,
		GameCheckpoint.pack(GameCheckpoint.capture(simulation_world, game_controller, match_definition, map_definition))
	)
	var write_error := GameSaveArchive.write(path, archive)
	if write_error != OK:
		last_save_error = "write_failed:%d" % int(write_error)
		return false
	return true


func load_game_from_path(path: String) -> bool:
	last_save_error = ""
	if network_session != null:
		return _load_failed("network_load_unsupported")
	var loaded: Dictionary = GameSaveArchive.read(path)
	if not bool(loaded.get("valid", false)):
		return _load_failed(String(loaded.get("error", "archive_invalid")))
	var archive: Dictionary = loaded.get("archive", {})
	var checkpoint: Dictionary = {}
	var restored_definition := match_definition
	var restored_map := map_definition
	if int(archive.get("format_version", 3)) == GameSaveArchive.CHECKPOINT_FORMAT_VERSION:
		checkpoint = GameCheckpoint.unpack(archive.get("checkpoint", {}))
		if checkpoint.is_empty(): return _load_failed("checkpoint_invalid")
		restored_definition = checkpoint["match_definition"]
		restored_map = checkpoint["map_definition"]
		if GameSaveArchive.fingerprint(restored_definition) != String(archive.get("match_fingerprint", "")): return _load_failed("match_fingerprint_mismatch")
	else:
		if String(archive.get("match_path", "")) != match_path: return _load_failed("match_path_mismatch")
		if String(archive.get("match_fingerprint", "")) != GameSaveArchive.fingerprint(match_definition): return _load_failed("match_fingerprint_mismatch")
	# Validate an isolated world before publishing any map or runtime state.
	var restored_world = _new_simulation_world(restored_map.get("size", map_size))
	if checkpoint.is_empty(): MatchBootstrap.apply(restored_world, restored_definition, restored_map)
	var restored_controller = GameController.new(restored_world)
	var replay_data: Dictionary = archive.get("replay", {})
	if checkpoint.is_empty():
		restored_controller.reset_timing()
		if not restored_controller.load_replay(replay_data): return _load_failed("replay_invalid")
		if not restored_controller.replay_until_tick(int(archive.get("tick", 0)), local_player_team, ENEMY_TEAM): return _load_failed("replay_failed:%s" % restored_controller.last_replay_mismatch)
	else:
		if not GameCheckpoint.restore(checkpoint, restored_world, restored_controller): return _load_failed("checkpoint_invalid")
	if restored_controller.tick_index != int(archive.get("tick", -1)): return _load_failed("checkpoint_invalid")
	var verifier := ReplaySystem.new()
	var restored_hash := verifier.world_state_hash(restored_world, restored_controller.tick_index, restored_controller)
	if restored_hash != String(archive.get("state_sha256", "")):
		return _load_failed("state_hash_mismatch:%s" % restored_hash)
	restored_controller.replay_source = null
	if not restored_controller.install_recording_history(replay_data, false):
		return _load_failed("recording_history_invalid")

	var restored_ai_players := _new_ai_players(restored_definition)
	_configure_runtime_ai_cadence(restored_ai_players)
	var ai_state_by_team: Dictionary = {}
	for state_value in archive.get("ai_states", []):
		var state: Dictionary = state_value
		ai_state_by_team[int(state.get("team", 0))] = state
	for ai in restored_ai_players:
		if not ai_state_by_team.has(int(ai.team)):
			return _load_failed("ai_state_missing:%d" % int(ai.team))
		if not ai.restore_state(ai_state_by_team[int(ai.team)]):
			return _load_failed("ai_state_invalid:%d" % int(ai.team))
	var saved_view: Dictionary = archive.get("view_state", {})
	var restored_sound_history := SoundCueHistory.new()
	if not restored_sound_history.restore_state(saved_view.get("sound_cue_history", {}), int(archive.get("tick", 0))):
		return _load_failed("sound_cue_history_invalid")

	match_definition = restored_definition
	map_definition = restored_map
	match_path = String(archive["match_path"])
	match_definition_override = restored_definition.duplicate(true)
	map_definition_override = restored_map.duplicate(true)
	map_size = restored_world.map_size
	map_seed = int(restored_map.get("seed", MAP_SEED))
	local_player_team = int(restored_definition.get("local_team", PLAYER_TEAM))
	player_control_state.player_id = local_player_team
	var environment_items: Array = restored_definition.get("presentation_environment", []).duplicate(true)
	environment_items.append_array(restored_definition.get("static_obstructions", []))
	environment_items.append_array(restored_map.get("scenery", []))
	environment_items.append_array(restored_map.get("cliff_obstructions", []))
	environment_presentation_field.configure(environment_items)
	cached_environment_items.clear()
	cached_environment_bounds = Rect2()
	scenario_overlay.configure(match_definition, resource_catalog.localization, resource_catalog.object_catalog_data)
	simulation_world = restored_world
	game_controller = restored_controller
	game_controller.set_command_result_limit(1024)
	ai_observation_store.clear()
	ai_players = restored_ai_players
	resource_catalog.prewarm_match_entities(simulation_world.get_units(), simulation_world.get_buildings())
	game_controller.set_before_fixed_tick(Callable(self, "queue_ai_commands"))
	var saved_controller: Dictionary = archive.get("controller_state", {})
	game_controller.set_speed_multiplier(float(saved_controller.get("speed", 1.5)))
	game_controller.set_paused(bool(saved_controller.get("paused", false)))
	modal_restore_paused = game_controller.paused
	simulation_world.restore_last_known_buildings(saved_view.get("last_known_buildings", {}))
	simulation_world.restore_known_resource_memory(saved_view.get("last_known_resources", {}))
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
	compact_status_visible = bool(saved_view.get("compact_status_visible", false))
	sound_cue_history = restored_sound_history
	input_adapter.reset()
	command_feedback_router.reset()
	command_feedback_router.event_cursor = game_controller.event_stream.latest_sequence()
	game_controller.event_stream.prune_through(command_feedback_router.event_cursor)
	presentation_effect_timeline.reset()
	command_marker_presentation.reset()
	cached_fog_revision = -1
	cached_fog_runs.clear()
	cached_world_fog_meshes.clear()
	cached_world_fog_mesh_terrain_revision = -1
	cached_world_fog_texture = null
	cached_world_fog_texture_data.resize(0)
	cached_world_fog_texture_revision = -1
	cached_minimap_fog_texture = null
	cached_minimap_fog_image = null
	cached_minimap_exploration_revision = -1
	cached_minimap_fog_rectangle = Rect2()
	cached_overview_tick = -1
	cached_overview_resource_revision = -1
	cached_hud_signature = null
	pending_build_kind = ""
	pending_target_command = ""
	local_spectator = false
	terrain_canvas.configure(map_size, map_seed, resource_catalog, simulation_world, Callable(self, "terrain_id_at_cell"), Callable(self, "visible_tile_bounds"))
	_sync_terrain_canvas()
	sync_world_state()
	# The initial fog mask scans the whole map; prepare it while the match is
	# loading, so the first visible frame only submits cached presentation.
	cached_fog_slope_neighbor_terrain_revision = int(simulation_world.terrain_revision)
	_sync_world_fog_texture(presentation_snapshot.get("fog", {}).get("cells", []), int(presentation_snapshot.get("fog_revision", -1)))
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
	return position.y > hud_top_height() and position.y < get_viewport_rect().size.y - hud_bottom_height()

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
	for unit in overview_units:
		if unit["team"] == local_player_team and unit["hp"] > 0.0:
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
	var visible_center := Vector2(viewport_size.x * 0.5, (hud_top_height() + viewport_size.y - hud_bottom_height()) * 0.5)
	view_offset = visible_center - iso_raw(Coordinates.clamp_world(world_position, map_size)) * view_zoom

func zoom_at(mouse: Vector2, factor: float) -> void:
	var before := screen_to_world(mouse)
	view_zoom = PixelScaling.step_zoom(view_zoom, 1 if factor > 1.0 else -1)
	var after_screen := world_to_screen(before)
	view_offset += mouse - after_screen

func finish_selection(first: Vector2, mouse: Vector2, mode: String = "select_click") -> void:
	var rectangle := selection_rectangle(first, mouse)
	var click := rectangle.size.length() < 9.0
	var hits: Array = []
	if click:
		for hit_value in pick_stack_at(mouse):
			var hit: Dictionary = hit_value
			if String(hit.get("entity_type", "")) in ["unit", "building", "foundation", "resource"] and not bool(hit.get("entity", {}).get("last_known", false)):
				hits.append(picking_service.context_entity(hit))
				break
	else:
		hits = selection_hits_in_rectangle(rectangle)

	var eligible_ids := selectable_player_ids()
	if click and not hits.is_empty():
		var clicked_id := int(hits[0]["id"])
		if not eligible_ids.has(clicked_id):
			eligible_ids.append(clicked_id)
	var hit_ids: Array[int] = []
	if click and mode == "select_double_click" and not hits.is_empty():
		var clicked: Dictionary = hits[0]
		hit_ids = PlayerControlState.same_type_visible_ids(presentation_snapshot.get("units", []), clicked, local_player_team, InterfaceLayout.for_viewport(get_viewport_rect().size)["world"], Callable(self, "world_to_screen"))
	if hit_ids.is_empty():
		for unit in hits:
			hit_ids.append(int(unit["id"]))
	var inspection_click := click and not hits.is_empty() and int(hits[0].get("team", 0)) != local_player_team
	var previous_inspection := selected_entities().any(func(entity): return int(entity.get("team", 0)) != local_player_team)
	player_control_state.apply_selection(eligible_ids, hit_ids, Input.is_key_pressed(KEY_SHIFT) and not inspection_click and not previous_inspection)
	refresh_hud_model()
	var selected := selected_entities()
	game_message = "Выбрано объектов: %d" % selected.size()
	message_time = 1.5
	if not selected.is_empty() and not hits.is_empty():
		play_sfx("selection:%s" % String(selected[0]["kind"]))

func selection_hits_in_rectangle(rectangle: Rect2) -> Array:
	return picking_service.box_hits(rectangle, current_world_drawables(), Callable(self, "world_to_screen"), local_player_team)


func current_world_drawables() -> Array:
	if render_world == null or presentation_snapshot.is_empty():
		return []
	var interpolation_alpha := game_controller.get_interpolation_alpha() if game_controller != null else 1.0
	var highlighted_ids: Array[int] = selection_preview_ids.duplicate()
	if interaction_highlight_id >= 0 and not highlighted_ids.has(interaction_highlight_id):
		highlighted_ids.append(interaction_highlight_id)
	if resource_feedback_time > 0.0 and resource_feedback_id >= 0 and not highlighted_ids.has(resource_feedback_id):
		highlighted_ids.append(resource_feedback_id)
	highlighted_ids.sort()
	var selected_ids := player_control_state.selected_ids()
	var control_signature := hash([highlighted_ids, selected_ids])
	if cached_world_drawables_revision != presentation_revision or cached_world_drawables_control_signature != control_signature:
		var retained_snapshot := presentation_snapshot.duplicate()
		retained_snapshot["effects"] = []
		render_world.performance_probe = game_controller.performance_probe if game_controller != null else null
		cached_world_drawables = render_world.create_world_drawables(retained_snapshot, Callable(self, "world_to_screen"), interpolation_alpha, Callable(self, "render_item_frame_info"), highlighted_ids, local_player_team, selected_ids)
		# Retained static caches project before their depth merge. Refresh only
		# interpolation here; a second full scenery projection wastes frame time.
		render_world.refresh_world_drawables(cached_world_drawables, Callable(self, "world_to_screen"), interpolation_alpha, false)
		cached_world_drawables_revision = presentation_revision
		cached_world_drawables_control_signature = control_signature
	else:
		# Static drawables only need a fresh projection when the camera moved;
		# the affine pan/zoom preserves their relative depth order.
		var projection_changed := view_offset != cached_projection_offset or view_zoom != cached_projection_zoom
		render_world.refresh_world_drawables(cached_world_drawables, Callable(self, "world_to_screen"), interpolation_alpha, projection_changed)
	cached_projection_offset = view_offset
	cached_projection_zoom = view_zoom
	var effects: Array = presentation_snapshot.get("effects", [])
	if effects.is_empty():
		return cached_world_drawables
	var effect_drawables: Array = render_world.create_world_drawables({"effects": effects}, Callable(self, "world_to_screen"), interpolation_alpha, Callable(self, "render_item_frame_info"))
	return render_world.merge_sorted_drawables(cached_world_drawables, effect_drawables)


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
	var cursor := InteractionCursor.resolve(selected_units(), hovered, screen_to_world(screen_position), local_player_team)
	interaction_highlight_id = int(cursor.get("entity_id", -1))
	var semantic := String(cursor.get("semantic", "default"))
	if not pending_build_kind.is_empty():
		semantic = "build"
	elif not pending_target_command.is_empty():
		semantic = pending_target_command
	_apply_source_cursor(semantic)


func _apply_source_cursor(semantic: String) -> void:
	var frame_index := SourceCursorPresentation.frame_for_semantic(semantic)
	if semantic == interaction_cursor_semantic and frame_index == source_cursor_frame_applied:
		return
	interaction_cursor_semantic = semantic
	source_cursor_frame_applied = frame_index
	if frame_index < source_cursor_frames.size() and source_cursor_frames[frame_index] != null:
		var metadata := resource_catalog.get_texture_metadata("ror_cursor", frame_index)
		Input.set_custom_mouse_cursor(source_cursor_frames[frame_index], Input.CURSOR_ARROW, SourceCursorPresentation.hotspot_for_metadata(metadata))
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	else:
		Input.set_default_cursor_shape(cursor_shape_for_semantic(semantic))


func _install_source_control_cursors() -> void:
	for mapping in [
		[Input.CURSOR_POINTING_HAND, 3],
		[Input.CURSOR_CAN_DROP, 3],
		[Input.CURSOR_MOVE, 0],
		[Input.CURSOR_CROSS, 4],
		[Input.CURSOR_FORBIDDEN, 6],
	]:
		var frame_index := int(mapping[1])
		if frame_index >= source_cursor_frames.size() or source_cursor_frames[frame_index] == null:
			continue
		var metadata := resource_catalog.get_texture_metadata("ror_cursor", frame_index)
		Input.set_custom_mouse_cursor(source_cursor_frames[frame_index], int(mapping[0]), SourceCursorPresentation.hotspot_for_metadata(metadata))


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
	if animation_state == "idle" and String(unit.get("death_phase", "alive")) == "alive":
		var entity_id := int(unit.get("id", 0))
		var period := 7.0 + float(posmod(entity_id * 17, 61)) * 0.1
		var phase := fposmod(float(presentation_snapshot.get("tick", 0)) * GameController.FIXED_STEP_SECONDS + float(posmod(entity_id * 37, 100)) * 0.13, period)
		return resource_catalog.unit_frame_info(unit, animation_state, phase if phase < 0.8 else 0.0)
	return resource_catalog.unit_frame_info(unit, animation_state)

func issue_order(mouse: Vector2, direction_end: Variant = null, queue_order: bool = false) -> void:
	var selected := selected_units()
	if selected.is_empty():
		selected = selected_entities().filter(func(entity): return int(entity.get("team", 0)) == local_player_team)
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

	var resolution := ContextResolver.resolve(selected, clicked_entity, mouse_world, local_player_team, simulation_world.get_allied_teams(local_player_team))
	var selected_ids := _selection_ids(selected)
	var command: Variant = null
	var accepted_message := ""
	match resolution["type"]:
		"set_rally_point":
			command = RoRCommands.SetRallyPointCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target"])
			accepted_message = "Точка сбора установлена"
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
			command = RoRCommands.MoveCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target"]) if queue_order else RoRCommands.FormationMoveCommand.new(game_controller.tick_index + 1, selected_ids, resolution["target"], formation, formation_forward)
			accepted_message = "Движение: %s" % formation_name()
		_:
			game_message = String(resolution.get("message", "Команда для этой цели пока недоступна"))
			message_time = 1.8
			return
	if queue_order and String(command.command_type()) in GameController.QUEUEABLE_ORDERS:
		command.params["queue_order"] = true
	var feedback_marker: Variant = ContextResolver.feedback_marker(resolution, clicked_entity, mouse_world)
	enqueue_with_feedback(command, accepted_message, "command:%s" % String(selected[0].get("kind", "")), feedback_marker)


func issue_martyrdom() -> void:
	var selected := selected_units()
	if selected.is_empty():
		return
	var command = RoRCommands.MartyrdomCommand.new(game_controller.tick_index + 1, _selection_ids(selected))
	enqueue_with_feedback(command, "Жертвоприношение", "", null)


func issue_delete_context() -> void:
	var selected := selected_entities().filter(func(entity): return int(entity.get("team", 0)) == local_player_team and String(entity.get("entity_type", "")) != "resource")
	var martyr_ids: Array[int] = []
	var delete_ids: Array[int] = []
	for entity in selected:
		var entity_id := int(entity.get("id", -1))
		var live_unit = simulation_world.find_unit(entity_id)
		if live_unit != null and simulation_world.conversion_system.validate_martyrdom(live_unit).is_empty():
			martyr_ids.append(entity_id)
		else:
			delete_ids.append(entity_id)
	if not martyr_ids.is_empty():
		var martyrdom = RoRCommands.MartyrdomCommand.new(game_controller.tick_index + 1, martyr_ids)
		enqueue_with_feedback(martyrdom, "Жертвоприношение", "", null)
	if not delete_ids.is_empty():
		var deletion = RoRCommands.DeleteEntityCommand.new(game_controller.tick_index + 1, delete_ids)
		enqueue_with_feedback(deletion, "Удалить выбранные объекты", "", null)


func issue_unload_at_pointer(queue_order: bool = false) -> void:
	var selected := selected_units()
	var transports: Array = selected.filter(func(unit): return bool(unit.get("components", {}).get("cargo", {}).get("enabled", false)))
	if transports.is_empty():
		game_message = "Для выгрузки выберите транспорт"
		message_time = 1.5
		return
	var target := screen_to_world(input_adapter.pointer_position)
	var command = RoRCommands.UnloadCommand.new(game_controller.tick_index + 1, _selection_ids(transports), target)
	if queue_order:
		command.params["queue_order"] = true
	enqueue_with_feedback(command, "Высадить пассажиров", "", target)


func issue_unit_action(action_name: String) -> void:
	if action_name == "repair":
		begin_repair()
		return
	if action_name == "delete":
		issue_delete_context()
		return
	if action_name == "attack_move":
		begin_attack_move()
		return
	if action_name == "attack_ground":
		begin_attack_ground()
		return
	if battle_over:
		return
	var selected := selected_entities().filter(func(entity): return int(entity.get("team", 0)) == local_player_team and String(entity.get("entity_type", "")) != "resource") if action_name == "stop" else selected_units()
	if selected.is_empty():
		game_message = "Для приказа выберите свои объекты" if action_name == "stop" else "Для приказа выберите своих юнитов"
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


func repair_workers() -> Array:
	if simulation_world == null:
		return []
	return selected_units().filter(func(unit): return simulation_world.entity_is_worker(unit) and String(unit.get("movement_domain", "land")) == "land")


func begin_repair() -> void:
	if battle_over or local_spectator or repair_workers().is_empty():
		return
	if hud_controls != null and hud_controls.build_menu_open:
		hud_controls.set_build_menu_open(false)
	pending_build_kind = ""
	pending_build_started = false
	pending_target_command = "repair"
	input_adapter.reset()
	update_interaction_cursor(input_adapter.pointer_position)
	game_message = "Укажите повреждённое своё или союзное здание/судно (ПКМ или Esc — отмена)"
	message_time = 4.0


func cancel_pending_targeting() -> bool:
	if pending_build_kind.is_empty() and pending_target_command.is_empty():
		return false
	pending_build_kind = ""
	pending_build_started = false
	pending_target_command = ""
	input_adapter.reset()
	selection_preview_ids.clear()
	update_interaction_cursor(input_adapter.pointer_position)
	game_message = "Приказ отменён"
	message_time = 1.5
	return true


func repair_target_at(screen_position: Vector2, workers: Array) -> Dictionary:
	for hit in pick_stack_at(screen_position):
		var target: Variant = simulation_world.find_building(int(hit.get("id", -1)))
		if target == null:
			target = simulation_world.find_unit(int(hit.get("id", -1)))
		if target != null and workers.any(func(worker): return simulation_world.can_worker_repair(worker, target)):
			return target
	return {}


func commit_repair_target(screen_position: Vector2) -> void:
	var workers := repair_workers()
	if workers.is_empty() or battle_over:
		cancel_pending_targeting()
		return
	var target := repair_target_at(screen_position, workers)
	if target.is_empty():
		game_message = "Выберите повреждённое своё или союзное здание/судно"
		message_time = 2.0
		return
	workers = workers.filter(func(worker): return simulation_world.can_worker_repair(worker, target))
	var command = RoRCommands.RepairCommand.new(game_controller.tick_index + 1, _selection_ids(workers), int(target["id"]))
	pending_target_command = ""
	update_interaction_cursor(input_adapter.pointer_position)
	enqueue_with_feedback(command, "Ремонтировать цель", "command:%s" % String(workers[0].get("kind", "villager")), Vector2(target.get("pos", Vector2.ZERO)))


func begin_attack_move() -> void:
	if selected_units().is_empty() or battle_over:
		game_message = "Для атаки выберите своих юнитов"
		message_time = 1.5
		return
	pending_build_kind = ""
	pending_target_command = "attack_move"
	update_interaction_cursor(input_adapter.pointer_position)
	game_message = "Укажите точку движения с атакой"
	message_time = 4.0


func begin_attack_ground() -> void:
	if battle_over or game_controller == null:
		return
	var attackers: Array = selected_units().filter(func(unit): return simulation_world.can_attack_ground(unit))
	if attackers.is_empty():
		game_message = "Для атаки по земле выберите осадные орудия"
		message_time = 1.5
		return
	pending_build_kind = ""
	pending_target_command = "attack_ground"
	update_interaction_cursor(input_adapter.pointer_position)
	game_message = "Укажите точку обстрела"
	message_time = 4.0


func commit_pending_target(screen_position: Vector2) -> void:
	var target_command := pending_target_command
	if target_command == "repair":
		commit_repair_target(screen_position)
		return
	if target_command not in ["attack_move", "attack_ground"]:
		return
	pending_target_command = ""
	update_interaction_cursor(input_adapter.pointer_position)
	var selected := selected_units()
	if selected.is_empty() or battle_over:
		return
	var target := screen_to_world(screen_position)
	var command: Variant
	var message: String
	if target_command == "attack_ground":
		selected = selected.filter(func(unit): return simulation_world.can_attack_ground(unit))
		if selected.is_empty():
			return
		command = RoRCommands.AttackGroundCommand.new(game_controller.tick_index + 1, _selection_ids(selected), target)
		message = "Атаковать точку"
	else:
		command = RoRCommands.AttackMoveCommand.new(game_controller.tick_index + 1, _selection_ids(selected), target)
		message = "Двигаться с атакой"
	enqueue_with_feedback(command, message, "command:%s" % String(selected[0].get("kind", "")), target)


func stance_name(value: String) -> String:
	return {"aggressive": "агрессивная", "defensive": "оборонительная", "stand_ground": "держать позицию", "passive": "не атаковать"}.get(value, value)


func selected_units() -> Array:
	var selected: Array = []
	for unit in units:
		if unit["team"] == local_player_team and unit["hp"] > 0.0 and player_control_state.is_selected(int(unit["id"])):
			selected.append(unit)
	selected.sort_custom(func(left, right): return left["id"] < right["id"])
	return selected


func selected_entities() -> Array:
	var selected: Array = []
	for collection_name in ["units", "buildings", "resources"]:
		for entity in presentation_snapshot.get(collection_name, []):
			if not player_control_state.is_selected(int(entity.get("id", -1))):
				continue
			if collection_name != "resources" and (float(entity.get("hp", 0.0)) <= 0.0 or bool(entity.get("last_known", false))):
				continue
			selected.append(entity)
	selected.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return selected


func selectable_player_ids() -> Array[int]:
	var ids: Array[int] = []
	var seen: Dictionary = {}
	for unit in overview_units:
		if int(unit.get("team", 0)) == local_player_team and float(unit.get("hp", 0.0)) > 0.0:
			var entity_id := int(unit["id"])
			ids.append(entity_id)
			seen[entity_id] = true
	for building in overview_buildings:
		if int(building.get("team", 0)) == local_player_team and float(building.get("hp", 0.0)) > 0.0:
			var entity_id := int(building["id"])
			if not seen.has(entity_id):
				ids.append(entity_id)
				seen[entity_id] = true
	# Overview data refreshes less often than the local snapshot. A newly
	# spawned selected object must not be pruned before its first overview pass.
	for entity in units + presentation_snapshot.get("buildings", []):
		if float(entity.get("hp", 0.0)) <= 0.0 or bool(entity.get("last_known", false)):
			continue
		if int(entity.get("team", 0)) != local_player_team and not player_control_state.is_selected(int(entity.get("id", -1))):
			continue
		var entity_id := int(entity.get("id", -1))
		if entity_id >= 0 and not seen.has(entity_id):
			ids.append(entity_id)
			seen[entity_id] = true
	for resource in presentation_snapshot.get("resources", []):
		var resource_id := int(resource.get("id", -1))
		if player_control_state.is_selected(resource_id) and not seen.has(resource_id):
			ids.append(resource_id)
			seen[resource_id] = true
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
	_queue_local_command(reform)
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


func request_train_shortcut(unit_kind: String) -> void:
	for command_value in hud_model.get("commands", []):
		var command: Dictionary = command_value
		if String(command.get("type", "")) != "train" or String(command.get("id", "")) != unit_kind:
			continue
		if bool(command.get("enabled", false)):
			train_unit_from_hud(unit_kind, int(command.get("building_id", -1)))
		else:
			game_message = HUDControls.reason_text(String(command.get("reason", "")))
			message_time = 2.0
		return
	game_message = "Выберите здание для обучения: %s" % unit_kind
	message_time = 2.0


func begin_build_placement(building_kind: String) -> void:
	if building_kind.is_empty() or selected_units().is_empty():
		return
	pending_target_command = ""
	pending_build_kind = building_kind
	pending_build_started = false
	update_interaction_cursor(input_adapter.pointer_position)
	game_message = "Укажите место строительства: %s (ПКМ — отмена)" % building_kind
	message_time = 4.0


func commit_build_placement(screen_position: Vector2, queue_order: bool = false, start_screen_position: Vector2 = Vector2.INF) -> void:
	if pending_build_kind.is_empty() or simulation_world == null or battle_over:
		return
	var workers: Array = selected_units().filter(func(unit): return simulation_world.entity_is_worker(unit))
	if workers.is_empty():
		pending_build_kind = ""
		update_interaction_cursor(input_adapter.pointer_position)
		game_message = "Для строительства нужен рабочий"
		message_time = 2.0
		return
	var target := Coordinates.clamp_world(screen_to_world(screen_position).round(), map_size)
	var kind := pending_build_kind
	if kind == "wall" and start_screen_position != Vector2.INF:
		var start := Coordinates.clamp_world(screen_to_world(start_screen_position).round(), map_size)
		var cells := WallPlacement.cells(Vector2i(start), Vector2i(target), OrderPipeline.MAX_QUEUED_ORDERS + 1)
		if not queue_order:
			pending_build_kind = ""
			pending_build_started = false
		else:
			pending_build_started = true
		update_interaction_cursor(input_adapter.pointer_position)
		queue_wall_line(workers, cells)
		return
	var defer_order := queue_order and pending_build_started
	if not queue_order:
		pending_build_kind = ""
		pending_build_started = false
	else:
		pending_build_started = true
	update_interaction_cursor(input_adapter.pointer_position)
	var command = RoRCommands.BuildCommand.new(game_controller.tick_index + 1, _selection_ids(workers), kind, target)
	if defer_order:
		# A queued building is still a real world object: reserve and render its
		# foundation now, then queue only the workers' trip to that foundation.
		command.params["plan_only"] = true
	enqueue_with_feedback(command, "Строительство: %s" % kind, "command:%s" % String(workers[0].get("kind", "villager")), null)


func queue_wall_line(workers: Array, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var worker_ids := _selection_ids(workers)
	# Place foundations together, then let the builders finish the line from its
	# clicked anchor. Deferred BuildCommands reattach to existing foundations.
	for index in range(cells.size() - 1, -1, -1):
		var target := Vector2(cells[index])
		var command = RoRCommands.BuildCommand.new(game_controller.tick_index + 1, worker_ids, "wall", target)
		if index == 0:
			enqueue_with_feedback(command, "Стена: %d секций" % cells.size(), "command:%s" % String(workers[0].get("kind", "villager")), null)
		else:
			_queue_local_command(command)
	for index in range(1, cells.size()):
		var command = RoRCommands.BuildCommand.new(game_controller.tick_index + 1, worker_ids, "wall", Vector2(cells[index]))
		command.params["queue_order"] = true
		_queue_local_command(command)


func train_unit_from_hud(unit_kind: String, building_id: int) -> void:
	if simulation_world == null or battle_over or building_id < 0 or unit_kind.is_empty():
		return
	var building: Variant = simulation_world.find_building(building_id)
	if building == null:
		game_message = "Здание больше недоступно"
		message_time = 2.0
		return
	var command = RoRCommands.TrainCommand.new(game_controller.tick_index + 1, [building_id], unit_kind, local_player_team, Vector2.ZERO)
	enqueue_with_feedback(command, "Добавлено в очередь: %s" % unit_kind, "", null)


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
	var update: Dictionary = hud_view_model.build_update(presentation_snapshot, player_control_state.selected_ids(), formation, cached_hud_signature, "ru")
	cached_hud_signature = update.get("signature")
	if not bool(update.get("changed", false)):
		# Tick, clock/blink and active queue progress are intentionally excluded
		# from the structural signature. Keep their public model values current
		# without rebuilding commands or deep-copying them into controls.
		hud_view_model.refresh_dynamic_model(hud_model, presentation_snapshot, player_control_state.selected_ids())
		if hud_controls != null:
			hud_controls.update_dynamic_model(hud_model)
		if top_bar_controls != null:
			top_bar_controls.queue_redraw()
		var probe: Variant = game_controller.performance_probe if game_controller != null else null
		if probe != null:
			probe.increment("presentation.hud.skipped")
		return
	hud_model = update.get("model", {})
	if hud_controls != null:
		hud_controls.set_view_model(hud_model)
	if top_bar_controls != null:
		top_bar_controls.set_view_model(hud_model)


func sync_world_state(force: bool = true) -> void:
	if simulation_world == null:
		return
	var probe: Variant = game_controller.performance_probe if game_controller != null else null
	var current_tick := game_controller.tick_index if game_controller != null else 0
	var selected_ids := player_control_state.selected_ids()
	var selection_signature := hash(selected_ids)
	var required_view_bounds := _expanded_tile_bounds(visible_tile_bounds(), 2)
	if not force and not presentation_snapshot.is_empty() and current_tick == cached_presentation_tick and selection_signature == cached_presentation_selection_signature and diagnostics_enabled == cached_presentation_diagnostics and _tile_bounds_contains(cached_presentation_bounds, required_view_bounds):
		if probe != null:
			probe.increment("presentation.sync.skipped")
		return
	var sync_started := Time.get_ticks_usec() if probe != null else 0
	var stage_started := sync_started
	var snapshot_bounds := visible_tile_bounds(8)
	var previous_overview: Dictionary = presentation_snapshot.get("overview", {})
	var refresh_overview := cached_overview_tick < 0 or current_tick < cached_overview_tick or current_tick - cached_overview_tick >= OVERVIEW_REFRESH_TICKS
	var current_resource_memory_revision := simulation_world.known_resource_revision(local_player_team)
	var refresh_overview_resources := refresh_overview and (previous_overview.is_empty() or current_resource_memory_revision != cached_overview_resource_revision)
	var snapshot_options := {
		"include_navigation": false,
		"include_build_sites": false,
		"include_overview": refresh_overview,
		"include_overview_resources": refresh_overview_resources,
		"compact_render_entities": not diagnostics_enabled,
		"include_production_overview": true,
		"borrow_visible_render_entities": not diagnostics_enabled,
		"borrow_overview_entities": not diagnostics_enabled,
		"entity_bounds": Rect2(Vector2(snapshot_bounds.position), Vector2(snapshot_bounds.size)),
		"always_include_entity_ids": selected_ids,
		"command_option_entity_ids": selected_ids,
	}
	if probe != null:
		snapshot_options["performance_probe"] = probe
		snapshot_options["performance_prefix"] = "presentation.local.snapshot"
	presentation_snapshot = SimulationSnapshot.presentation(simulation_world, current_tick, local_player_team, snapshot_options)
	if probe != null:
		probe.observe_microseconds("presentation.sync.snapshot", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	if refresh_overview:
		cached_overview_tick = current_tick
		if refresh_overview_resources:
			cached_overview_resource_revision = int(presentation_snapshot.get("resource_memory_revision", current_resource_memory_revision))
		elif previous_overview.has("resources"):
			presentation_snapshot["overview"]["resources"] = previous_overview["resources"]
	elif not previous_overview.is_empty():
		presentation_snapshot["overview"] = previous_overview
	presentation_snapshot["overview_tick"] = cached_overview_tick
	cached_presentation_tick = current_tick
	cached_presentation_bounds = snapshot_bounds
	cached_presentation_selection_signature = selection_signature
	cached_presentation_diagnostics = diagnostics_enabled
	presentation_revision += 1
	presentation_snapshot["markers"] = match_definition.get("presentation_markers", [])
	var visible_bounds := visible_tile_bounds()
	var environment_bounds := Rect2i(visible_bounds.position - Vector2i(2, 2), visible_bounds.size + Vector2i(4, 4))
	if not _tile_bounds_contains(cached_environment_bounds, environment_bounds):
		cached_environment_bounds = _expanded_tile_bounds(environment_bounds, 6)
		cached_environment_items = environment_presentation_field.query(cached_environment_bounds)
		cached_environment_items.append_array(environment_presentation_field.mobile_items())
		cached_environment_revision += 1
	presentation_snapshot["environment"] = cached_environment_items
	presentation_snapshot["environment_revision"] = cached_environment_revision
	if probe != null:
		probe.observe_microseconds("presentation.sync.environment", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	units = presentation_snapshot.get("units", [])
	resource_nodes = presentation_snapshot.get("resources", [])
	# TerrainCanvas already keys its mesh by SimulationWorld.terrain_revision.
	# A visible-tree signature confused exploration with terrain mutation and
	# rebuilt the complete terrain mesh while units moved through fog.
	if probe != null:
		probe.observe_microseconds("presentation.sync.resource_projection", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	var overview: Dictionary = presentation_snapshot.get("overview", {})
	overview_units = overview.get("units", units)
	overview_resource_nodes = overview.get("resources", resource_nodes)
	overview_buildings = overview.get("buildings", presentation_snapshot.get("buildings", []))
	player_control_state.prune(selectable_player_ids())
	battle_over = bool(presentation_snapshot.get("battle_over", false))
	var now_spectator := String(presentation_snapshot.get("player_state", {}).get("status", "active")) in ["resigned", "defeated"]
	if now_spectator and not local_spectator:
		player_control_state.clear()
		control_groups.clear()
		pending_build_kind = ""
		pending_target_command = ""
		game_message = "Режим наблюдателя — управление войсками недоступно"
		message_time = 4.0
	local_spectator = now_spectator
	if probe != null:
		probe.observe_microseconds("presentation.sync.control_projection", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	refresh_hud_model()
	if scenario_overlay != null:
		scenario_overlay.set_snapshot(presentation_snapshot)
	if hud_modal_overlay != null:
		hud_modal_overlay.set_snapshot(presentation_snapshot)
	if probe != null:
		probe.observe_microseconds("presentation.sync.view_models", Time.get_ticks_usec() - stage_started)
		probe.observe_microseconds("presentation.sync.total", Time.get_ticks_usec() - sync_started)


func _restart_from_scenario_overlay() -> void:
	if network_session == null:
		reset_game()
	else:
		game_message = "Для новой сетевой игры вернитесь в лобби"


func _return_to_launcher() -> void:
	if network_relay != null:
		network_relay.close()
	get_tree().change_scene_to_file("res://launcher.tscn")


func _exit_tree() -> void:
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_CAN_DROP, Input.CURSOR_MOVE, Input.CURSOR_CROSS, Input.CURSOR_FORBIDDEN]:
		Input.set_custom_mouse_cursor(null, shape)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if network_relay != null:
		network_relay.close()


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
	var probe: Variant = game_controller.performance_probe if game_controller != null else null
	var draw_started := Time.get_ticks_usec() if probe != null else 0
	var stage_started := draw_started
	# The terrain seam belongs below sprites, including crowns beyond the map.
	draw_map_edge_guard()
	if probe != null:
		probe.observe_microseconds("presentation.draw.map_edge", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	draw_world_objects()
	if probe != null:
		probe.observe_microseconds("presentation.draw.world", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	draw_fog_overlay()
	if probe != null:
		probe.observe_microseconds("presentation.draw.fog", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	draw_command_marker()
	draw_build_placement_preview()
	if probe != null:
		probe.observe_microseconds("presentation.draw.command_marker", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	if diagnostics_enabled:
		draw_diagnostics()
	draw_formation_ghost()
	draw_hud()
	if probe != null:
		probe.observe_microseconds("presentation.draw.hud_overlays", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	var selection_gesture := input_adapter.selection_gesture()
	if not selection_gesture.is_empty():
		var rectangle := selection_rectangle(selection_gesture["from"], selection_gesture["to"])
		draw_rect(rectangle, Color(0.25, 0.75, 1.0, 0.12), true)
		draw_rect(rectangle, Color(0.35, 0.9, 1.0, 0.9), false, 1.5)
	if probe != null:
		probe.observe_microseconds("presentation.draw.gestures", Time.get_ticks_usec() - stage_started)
		probe.observe_microseconds("presentation.draw.total", Time.get_ticks_usec() - draw_started)


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
			for underlay in drawable.get("underlays", []):
				draw_texture_rect(underlay["texture"], Rect2(PixelScaling.snap_screen(underlay["position"]), underlay["size"]), false)
			if drawable.has("mesh_layers"):
				for layer in drawable["mesh_layers"]:
					TerrainRenderer.EnvironmentTerrain.draw_layer(self, layer)
			else:
				draw_texture_rect(drawable["texture"], Rect2(PixelScaling.snap_screen(drawable["position"]), drawable["size"]), false)
			for layer in drawable["borders"]:
				draw_terrain_border(drawable["position"], layer)

func terrain_at(x: int, y: int) -> String:
	return TerrainRules.base_texture_kind(terrain_id_at_cell(Vector2i(x, y)), resource_catalog.terrain_catalog_data)


func terrain_id_at_cell(cell: Vector2i) -> int:
	# The world maintains an O(1) forest-cell index; the previous linear scan
	# over every resource per cell multiplied pan-time terrain rebuilds.
	if simulation_world != null:
		return simulation_world.terrain_id_at_cell(cell)
	return TerrainRules.terrain_id_for_logical(TerrainRules.terrain_at(cell))


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
		var probe: Variant = game_controller.performance_probe if game_controller != null else null
		var stage_started := Time.get_ticks_usec() if probe != null else 0
		var drawables := current_world_drawables()
		if probe != null:
			probe.observe_microseconds("presentation.draw.world_prepare", Time.get_ticks_usec() - stage_started)
			stage_started = Time.get_ticks_usec()
		for drawable in drawables:
			match drawable["kind"]:
				"building", "building_part", "resource", "unit", "unit_part", "projectile", "effect", "marker", "environment": draw_render_body(drawable)
				"shadow": draw_unit_shadow(drawable)
				"selection": draw_unit_selection(drawable)
				"health_bar": draw_unit_health(drawable)
		if probe != null:
			probe.observe_microseconds("presentation.draw.world_submit", Time.get_ticks_usec() - stage_started)
	return


func draw_command_marker() -> void:
	var marker := command_marker_presentation.snapshot()
	if marker.is_empty():
		return
	var frame_index := int(marker["frame_index"])
	var texture: Texture2D = source_command_marker_frames.get(frame_index)
	if texture == null:
		return
	var center := PixelScaling.snap_screen(world_to_screen(marker["world_position"]))
	var metadata := resource_catalog.get_texture_metadata("ror_command_marker", frame_index)
	var source_hotspot := SourceCursorPresentation.hotspot_for_metadata(metadata)
	draw_anchored_texture(texture, "ror_command_marker", frame_index, center, 1.0, false, 1.0, source_hotspot)


func draw_build_placement_preview() -> void:
	if pending_build_kind.is_empty() or simulation_world == null or not is_world_interaction_area(input_adapter.pointer_position):
		return
	var center := Coordinates.clamp_world(screen_to_world(input_adapter.pointer_position).round(), map_size)
	if pending_build_kind == "wall" and input_adapter.pointer.is_selecting():
		var start := Coordinates.clamp_world(screen_to_world(input_adapter.pointer.anchor).round(), map_size)
		for cell in WallPlacement.cells(Vector2i(start), Vector2i(center), OrderPipeline.MAX_QUEUED_ORDERS + 1):
			draw_foundation_preview_at("wall", Vector2(cell))
		return
	draw_foundation_preview_at(pending_build_kind, center)


func draw_foundation_preview_at(kind: String, center: Vector2) -> void:
	var key := "%s:%d:%d:%d:%d" % [kind, roundi(center.x), roundi(center.y), game_controller.tick_index, simulation_world.navigation_grid.revision]
	if key != placement_preview_key:
		placement_preview_key = key
		placement_preview_valid = simulation_world.can_place_foundation(local_player_team, kind, center)
	var footprint := Footprint.building(simulation_world.unit_stats(kind), center)
	var ghost := {"kind": kind, "team": local_player_team, "pos": center, "state": "foundation", "construction_stage": 0, "footprint": footprint}
	var color := Color(0.45, 0.95, 0.5, 0.75) if placement_preview_valid else Color(1.0, 0.3, 0.25, 0.75)
	var points := building_selection_outline(ghost)
	draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.16))
	draw_polyline(points, color, maxf(1.0, view_zoom), true)
	var frame_info := resource_catalog.building_frame_info(ghost, 0.0)
	var texture: Texture2D = frame_info.get("texture")
	if texture != null:
		draw_anchored_texture(texture, String(frame_info.get("asset_name", "")), int(frame_info.get("frame_index", 0)), PixelScaling.snap_screen(world_to_screen(center)), view_zoom, bool(frame_info.get("mirrored", false)), 0.55, frame_info.get("hotspot"))


func draw_fog_overlay() -> void:
	if presentation_snapshot.is_empty():
		return
	var probe: Variant = game_controller.performance_probe if game_controller != null else null
	var cells: Variant = presentation_snapshot.get("fog", {}).get("cells", [])
	if cells.size() < map_size.x * map_size.y:
		return
	var fog_revision := int(presentation_snapshot.get("fog_revision", -1))
	var terrain_revision := int(simulation_world.terrain_revision) if simulation_world != null else -1
	if cached_fog_slope_neighbor_terrain_revision != terrain_revision:
		cached_fog_slope_neighbor_cells.resize(0)
		cached_fog_slope_neighbor_terrain_revision = terrain_revision
		cached_world_fog_meshes.clear()
		cached_world_fog_mesh_terrain_revision = -1
		cached_world_fog_texture_revision = -1
	var prepare_started := Time.get_ticks_usec() if probe != null else 0
	if cached_world_fog_mesh_terrain_revision != terrain_revision:
		cached_world_fog_meshes.clear()
		cached_world_fog_mesh_terrain_revision = terrain_revision
	_sync_world_fog_texture(cells, fog_revision, probe)
	var visible_meshes: Array[ArrayMesh] = []
	var bounds := _expanded_tile_bounds(visible_tile_bounds(), 12)
	var first_chunk := Vector2i(
		floori(float(bounds.position.x) / float(WORLD_FOG_GEOMETRY_CHUNK_SIZE)),
		floori(float(bounds.position.y) / float(WORLD_FOG_GEOMETRY_CHUNK_SIZE))
	)
	var last_chunk := Vector2i(
		floori(float(maxi(bounds.position.x, bounds.end.x - 1)) / float(WORLD_FOG_GEOMETRY_CHUNK_SIZE)),
		floori(float(maxi(bounds.position.y, bounds.end.y - 1)) / float(WORLD_FOG_GEOMETRY_CHUNK_SIZE))
	)
	var built_meshes := 0
	for chunk_y in range(first_chunk.y, last_chunk.y + 1):
		for chunk_x in range(first_chunk.x, last_chunk.x + 1):
			var chunk_key := Vector2i(chunk_x, chunk_y)
			var mesh: Variant = cached_world_fog_meshes.get(chunk_key)
			if not mesh is ArrayMesh:
				mesh = _build_world_fog_mesh(_world_fog_geometry_chunk_bounds(chunk_key))
				if mesh is ArrayMesh:
					cached_world_fog_meshes[chunk_key] = mesh
					built_meshes += 1
			if mesh is ArrayMesh:
				visible_meshes.append(mesh)
	var retained_bounds := Rect2i(
		first_chunk - Vector2i.ONE * WORLD_FOG_GEOMETRY_RETAIN_MARGIN,
		(last_chunk - first_chunk) + Vector2i.ONE * (WORLD_FOG_GEOMETRY_RETAIN_MARGIN * 2 + 1)
	)
	var evicted_meshes := _prune_world_fog_geometry_cache(retained_bounds)
	if probe != null:
		probe.observe_microseconds("presentation.fog.prepare", Time.get_ticks_usec() - prepare_started)
		if built_meshes > 0:
			probe.increment("presentation.fog.geometry_chunks_built", built_meshes)
		if evicted_meshes > 0:
			probe.increment("presentation.fog.geometry_chunks_evicted", evicted_meshes)
	if visible_meshes.is_empty() or cached_world_fog_texture == null:
		return
	var submit_started := Time.get_ticks_usec() if probe != null else 0
	draw_set_transform(PixelScaling.snap_screen(view_offset), 0.0, Vector2(view_zoom, view_zoom))
	for mesh in visible_meshes:
		draw_mesh(mesh, cached_world_fog_texture)
	draw_set_transform(Vector2.ZERO)
	draw_map_edge_fog_overlay()
	if probe != null:
		probe.observe_microseconds("presentation.fog.mesh_submit", Time.get_ticks_usec() - submit_started)


func _world_fog_geometry_chunk_bounds(chunk_key: Vector2i) -> Rect2i:
	var start := chunk_key * WORLD_FOG_GEOMETRY_CHUNK_SIZE
	var finish := Vector2i(
		mini(map_size.x, start.x + WORLD_FOG_GEOMETRY_CHUNK_SIZE),
		mini(map_size.y, start.y + WORLD_FOG_GEOMETRY_CHUNK_SIZE)
	)
	start.x = maxi(0, start.x)
	start.y = maxi(0, start.y)
	return Rect2i(start, Vector2i(maxi(0, finish.x - start.x), maxi(0, finish.y - start.y)))


func _prune_world_fog_geometry_cache(retained_bounds: Rect2i) -> int:
	var removed := 0
	for chunk_key_value in cached_world_fog_meshes.keys():
		var chunk_key: Vector2i = chunk_key_value
		if retained_bounds.has_point(chunk_key):
			continue
		cached_world_fog_meshes.erase(chunk_key)
		removed += 1
	return removed


func _build_world_fog_mesh(bounds: Rect2i) -> ArrayMesh:
	# Geometry never depends on fog state. Chunks are created only as the camera
	# reaches them and retained for the current viewport plus one surrounding
	# ring, so exploration cannot grow a history of GPU objects.
	if simulation_world == null or bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var lattice_width := bounds.size.x + 1
	var lattice_height := bounds.size.y + 1
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(lattice_width * lattice_height)
	uvs.resize(vertices.size())
	for y in range(lattice_height):
		for x in range(lattice_width):
			var vertex_index := y * lattice_width + x
			var world := Vector2(bounds.position + Vector2i(x, y))
			var projected: Vector2 = simulation_world.terrain_elevation.world_to_screen(world, 1.0, Vector2.ZERO)
			projected = PixelScaling.snap_screen(projected)
			vertices[vertex_index] = Vector3(projected.x, projected.y, 0.0)
			uvs[vertex_index] = Vector2(clampf(world.x / float(map_size.x), 0.5 / map_size.x, 1.0 - 0.5 / map_size.x), clampf(world.y / float(map_size.y), 0.5 / map_size.y, 1.0 - 0.5 / map_size.y))
	var indices := PackedInt32Array()
	indices.resize(bounds.size.x * bounds.size.y * 6)
	var index_offset := 0
	for y in range(bounds.size.y):
		for x in range(bounds.size.x):
			var top_left := y * lattice_width + x
			var top_right := top_left + 1
			var bottom_left := top_left + lattice_width
			var bottom_right := bottom_left + 1
			indices[index_offset] = top_left
			indices[index_offset + 1] = top_right
			indices[index_offset + 2] = bottom_right
			indices[index_offset + 3] = top_left
			indices[index_offset + 4] = bottom_right
			indices[index_offset + 5] = bottom_left
			index_offset += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sync_world_fog_texture(cells: Variant, fog_revision: int, probe: Variant = null) -> void:
	var expected_cells := map_size.x * map_size.y
	if cells.size() < expected_cells:
		return
	var mask_started := Time.get_ticks_usec() if probe != null else 0
	_ensure_fog_slope_neighbor_cache()
	var full_refresh := cached_world_fog_texture == null or cached_world_fog_texture_data.size() != expected_cells * 4 or cached_world_fog_texture_revision < 0
	var affected: Dictionary = {}
	if full_refresh:
		cached_world_fog_texture_data.resize(expected_cells * 4)
		for index in range(expected_cells):
			affected[index] = true
		if simulation_world != null and simulation_world.has_method("consume_fog_presentation_dirty_cells"):
			simulation_world.consume_fog_presentation_dirty_cells(local_player_team)
	elif fog_revision != cached_world_fog_texture_revision:
		var dirty_cells: Array = simulation_world.consume_fog_presentation_dirty_cells(local_player_team) if simulation_world != null and simulation_world.has_method("consume_fog_presentation_dirty_cells") else []
		# A revision without a queue is possible after loading an older save or in
		# isolated presentation fixtures. Fall back to a complete mask refresh so
		# correctness never depends on the incremental producer being present.
		if dirty_cells.is_empty():
			for index in range(expected_cells):
				affected[index] = true
		else:
			for cell_index_value in dirty_cells:
				var cell_index := int(cell_index_value)
				var cell := Vector2i(cell_index % map_size.x, cell_index / map_size.x)
				for y_offset in range(-1, 2):
					for x_offset in range(-1, 2):
						var affected_cell := cell + Vector2i(x_offset, y_offset)
						if affected_cell.x >= 0 and affected_cell.y >= 0 and affected_cell.x < map_size.x and affected_cell.y < map_size.y:
							affected[affected_cell.y * map_size.x + affected_cell.x] = true
	elif cached_world_fog_texture != null:
		return
	for cell_index_value in affected.keys():
		_write_world_fog_pixel(int(cell_index_value), cells)
	var image := Image.create_from_data(map_size.x, map_size.y, false, Image.FORMAT_RGBA8, cached_world_fog_texture_data)
	if cached_world_fog_texture == null:
		cached_world_fog_texture = ImageTexture.create_from_image(image)
	else:
		cached_world_fog_texture.update(image)
	cached_world_fog_texture_revision = fog_revision
	if probe != null:
		probe.observe_microseconds("presentation.fog.mask_update", Time.get_ticks_usec() - mask_started)
		probe.increment("presentation.fog.mask_cells_updated", affected.size())


func _write_world_fog_pixel(index: int, cells: Variant) -> void:
	var cell := Vector2i(index % map_size.x, index / map_size.x)
	var state := int(cells[index])
	var color := Color.TRANSPARENT
	if state != FogOfWar.VISIBLE and _fog_cell_should_cover(cell, cells):
		color = FogPresentation.color_for_state(state)
	var byte_offset := index * 4
	cached_world_fog_texture_data[byte_offset] = clampi(roundi(color.r * 255.0), 0, 255)
	cached_world_fog_texture_data[byte_offset + 1] = clampi(roundi(color.g * 255.0), 0, 255)
	cached_world_fog_texture_data[byte_offset + 2] = clampi(roundi(color.b * 255.0), 0, 255)
	cached_world_fog_texture_data[byte_offset + 3] = clampi(roundi(color.a * 255.0), 0, 255)


func _world_to_fog_mesh(world: Vector2) -> Vector2:
	if simulation_world != null:
		return simulation_world.terrain_elevation.world_to_screen(world, view_zoom, Vector2.ZERO)
	return Coordinates.world_to_screen(world, view_zoom, Vector2.ZERO)


func _fog_cell_should_cover(cell: Vector2i, cells: Variant) -> bool:
	var index := cell.y * map_size.x + cell.x
	if index < 0 or index >= cells.size() or int(cells[index]) == FogOfWar.VISIBLE:
		return false
	_ensure_fog_slope_neighbor_cache()
	if index >= cached_fog_slope_neighbor_cells.size() or int(cached_fog_slope_neighbor_cells[index]) == 0:
		return true
	if _fog_cell_touches_visible(cell, cells):
		return false
	return true


func _fog_cell_touches_visible(cell: Vector2i, cells: Variant) -> bool:
	for y_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			if x_offset == 0 and y_offset == 0:
				continue
			if _fog_state_at_cell(cells, cell + Vector2i(x_offset, y_offset)) == FogOfWar.VISIBLE:
				return true
	return false


func _fog_state_at_cell(cells: Variant, cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return FogOfWar.UNKNOWN
	var index := cell.y * map_size.x + cell.x
	if index < 0 or index >= cells.size():
		return FogOfWar.UNKNOWN
	return int(cells[index])


func _ensure_fog_slope_neighbor_cache() -> void:
	var expected_size := map_size.x * map_size.y
	if simulation_world == null or cached_fog_slope_neighbor_cells.size() == expected_size:
		return
	cached_fog_slope_neighbor_cells.resize(expected_size)
	for y in range(map_size.y):
		for x in range(map_size.x):
			var cell := Vector2i(x, y)
			var profile: Dictionary = simulation_world.terrain_elevation.cell_profile(cell)
			var uses_slope_art := int(profile.get("slope_index", 0)) > 0 or not bool(profile.get("is_valid", true))
			if uses_slope_art:
				for y_offset in range(-1, 2):
					for x_offset in range(-1, 2):
						var neighbor := cell + Vector2i(x_offset, y_offset)
						if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < map_size.x and neighbor.y < map_size.y:
							cached_fog_slope_neighbor_cells[neighbor.y * map_size.x + neighbor.x] = 1


func _expanded_tile_bounds(bounds: Rect2i, margin: int) -> Rect2i:
	var start := Vector2i(maxi(0, bounds.position.x - margin), maxi(0, bounds.position.y - margin))
	var finish := Vector2i(mini(map_size.x, bounds.end.x + margin), mini(map_size.y, bounds.end.y + margin))
	return Rect2i(start, finish - start)


func _tile_bounds_contains(outer: Rect2i, inner: Rect2i) -> bool:
	return (
		inner.position.x >= outer.position.x
		and inner.position.y >= outer.position.y
		and inner.end.x <= outer.end.x
		and inner.end.y <= outer.end.y
	)


func draw_map_edge_guard() -> void:
	var terrain_revision := int(simulation_world.terrain_revision) if simulation_world != null else -1
	if cached_map_edge_chains.is_empty() or not is_equal_approx(cached_map_edge_zoom, view_zoom) or cached_map_edge_terrain_revision != terrain_revision:
		cached_map_edge_chains = FogPresentation.map_edge_guard_chains(map_size, Callable(self, "_world_to_fog_mesh"))
		cached_map_edge_zoom = view_zoom
		cached_map_edge_terrain_revision = terrain_revision
	draw_set_transform(PixelScaling.snap_screen(view_offset))
	for chain in cached_map_edge_chains:
		if chain.size() >= 2:
			# A two-pixel centered stroke covers the one shared texel outside either
			# rasterized edge orientation while consuming at most one pixel inside.
			draw_polyline(chain, Color.BLACK, maxf(2.0, view_zoom * 2.0), false)
	draw_set_transform(Vector2.ZERO)

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
		if String(item.get("kind", "")) == "objective":
			draw_objective_fallback(item)
		return
	var screen := PixelScaling.snap_screen(item["screen_position"])
	if item["kind"] == "projectile":
		screen.y -= float(item["data"].get("visual_height", 0.0)) * TerrainElevation.ELEVATION_PIXEL_STEP * view_zoom
	var screen_offset: Vector2 = frame_info.get("screen_offset", Vector2.ZERO)
	screen += screen_offset * view_zoom
	if frame_info.has("rotation"):
		draw_set_transform(screen, float(frame_info["rotation"]), Vector2.ONE * view_zoom)
		var texture: Texture2D = frame_info["texture"]
		draw_texture(texture, -Vector2(item["hotspot"]), Color(1, 1, 1, float(item["opacity"]) * float(frame_info.get("fall_opacity", 1.0))))
		draw_set_transform(Vector2.ZERO)
		return
	draw_anchored_texture(frame_info["texture"], frame_info["asset_name"], item["frame"], screen, view_zoom, bool(frame_info.get("mirrored", false)), float(item["opacity"]), item["hotspot"])


func draw_objective_fallback(item: Dictionary) -> void:
	var objective: Dictionary = item.get("data", {})
	if String(objective.get("category", "")) != "ruin":
		return
	var screen := PixelScaling.snap_screen(item["screen_position"])
	var extent := 13.0 * view_zoom
	var owner := int(objective.get("team", 0))
	var fill := Color("747f81") if owner <= 0 else RenderItem.color_for_team(owner)
	var points := PackedVector2Array([
		screen + Vector2(0, -extent),
		screen + Vector2(extent * 0.8, -extent * 0.25),
		screen + Vector2(extent * 0.65, extent * 0.55),
		screen + Vector2(-extent * 0.65, extent * 0.55),
		screen + Vector2(-extent * 0.8, -extent * 0.25),
	])
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, Color("e4d4a7"), maxf(1.0, view_zoom))

func draw_unit_selection(item: Dictionary) -> void:
	var unit: Dictionary = item["data"]
	if resource_feedback_time > 0.0 and int(unit.get("id", -1)) == resource_feedback_id:
		if int(resource_feedback_time * 10.0) % 2 == 0:
			if String(unit.get("entity_type", "")) in ["building", "foundation"] or String(unit.get("footprint", {}).get("shape", "")) == "polygon":
				draw_building_selection_rectangle(unit, Color("ffe56c"))
			else:
				draw_selection_ellipse(unit_selection_center(item), Color("ffe56c"), Vector2(15.0, 6.5))
		return
	var screen := unit_selection_center(item)
	var is_building := String(unit.get("entity_type", "")) in ["building", "foundation"] or String(unit.get("footprint", {}).get("shape", "")) == "polygon"
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
		if is_building:
			draw_building_selection_rectangle(unit, preview_color)
		else:
			draw_selection_ellipse(screen, preview_color, radius)
	elif hovered:
		var hover_color := Color("ef5d55") if interaction_cursor_semantic == "attack" else Color("d6bc63") if interaction_cursor_semantic == "gather" else Color("66e8ff")
		if is_building:
			draw_building_selection_rectangle(unit, hover_color)
		else:
			draw_selection_ellipse(screen, hover_color, radius)
	elif selected:
		if is_building:
			draw_building_selection_rectangle(unit, Color("e8f45b"))
		else:
			draw_selection_ellipse(screen, Color("e8f45b"), radius)


func unit_selection_center(item: Dictionary) -> Vector2:
	# Render-item screen_position is the object's ground anchor. Adding another
	# sprite-height offset detached ship/resource rings from the water or ground.
	return PixelScaling.snap_screen(Vector2(item.get("screen_position", Vector2.ZERO)))


func draw_building_selection_rectangle(building: Dictionary, color: Color) -> void:
	draw_polyline(building_selection_outline(building), color, maxf(1.0, view_zoom), true)


func building_selection_outline(building: Dictionary) -> PackedVector2Array:
	var footprint: Dictionary = building.get("footprint", {})
	var half_size := Vector2(footprint.get("half_size", Vector2(0.5, 0.5)))
	var center := Vector2(building.get("pos", Vector2.ZERO))
	var points := PackedVector2Array()
	for offset in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y), Vector2(-half_size.x, -half_size.y)]:
		points.append(PixelScaling.snap_screen(world_to_screen(center + offset)))
	return points


func building_selection_rectangle(building: Dictionary) -> Rect2:
	var footprint: Dictionary = building.get("footprint", {})
	var half_size := Vector2(footprint.get("half_size", Vector2(0.5, 0.5)))
	var center := Vector2(building.get("pos", Vector2.ZERO))
	var corners := [
		center + Vector2(-half_size.x, -half_size.y),
		center + Vector2(half_size.x, -half_size.y),
		center + Vector2(half_size.x, half_size.y),
		center + Vector2(-half_size.x, half_size.y),
	]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in corners:
		var point := PixelScaling.snap_screen(world_to_screen(corner))
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	# A single unfilled rectangle follows the projected footprint bounds. Unlike
	# the unit ring it has no offset copy or synthetic shadow.
	return Rect2(minimum, maximum - minimum)


func draw_unit_shadow(item: Dictionary) -> void:
	var unit: Dictionary = item["data"]
	var screen := PixelScaling.snap_screen(item["screen_position"])
	var radius := maxf(0.2, float(unit.get("footprint_radius", 0.3)))
	draw_set_transform(screen, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, radius * 34.0 * view_zoom, Color(0.0, 0.0, 0.0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_unit_health(item: Dictionary) -> void:
	var unit: Dictionary = item["data"]
	var screen := PixelScaling.snap_screen(item["screen_position"])
	var hotspot: Vector2 = item["hotspot"]
	var ratio: float = clampf(float(unit["hp"]) / maxf(1.0, float(unit["max_hp"])), 0.0, 1.0)
	# 50745 is the 50x7 selection-card meter. World-space selection bars in
	# RoR are a separate, compact presentation and must not reuse that strip.
	var bar_width := 25.0 * view_zoom
	var bar_height := maxf(3.0, 3.0 * view_zoom)
	var bar_pos := PixelScaling.snap_screen(Vector2(screen.x - bar_width * 0.5, screen.y - hotspot.y * view_zoom - 5.0))
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color(0.02, 0.04, 0.03, 0.95), true)
	draw_rect(Rect2(bar_pos + Vector2(1, 1), Vector2(maxf(0.0, (bar_width - 2.0) * ratio), maxf(1.0, bar_height - 2.0))), Color("21dc4b") if unit["team"] == local_player_team else Color("e44339"), true)

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
	var layout := InterfaceLayout.for_viewport(viewport_size)
	draw_source_hud_shell(layout)
	draw_minimap(layout["minimap"])
	if message_time > 0.0:
		var message_rect := Rect2(0, viewport_size.y - hud_bottom_height() - 18, viewport_size.x, 18)
		draw_rect(message_rect, Color(0, 0, 0, 0.92))
		draw_string(font, message_rect.position + Vector2(5, 13), game_message, HORIZONTAL_ALIGNMENT_LEFT, message_rect.size.x - 10, 10, Color.WHITE)


func draw_source_hud_shell(layout: Dictionary) -> void:
	var bottom: Rect2 = layout["bottom"]
	draw_rect(bottom, Color("393833"))
	var shell: Dictionary = resource_catalog.interface_skin.hud_shell(1024, interface_style_index)
	var texture: Texture2D = shell.get("bottom")
	if texture == null:
		return
	var left_width := 136.0 if bool(layout["narrow"]) else float(layout["wide_split"]["left_width"])
	for row in range(2 if bool(layout["narrow"]) else 1):
		var x := left_width if row == 0 else 0.0
		var y := bottom.position.y + row * 126
		while x < bottom.size.x:
			var piece := minf(376, bottom.size.x - x)
			draw_texture_rect_region(texture, Rect2(x, y, piece, 126), Rect2(416, 0, piece, 126))
			x += piece
	draw_texture_rect_region(texture, Rect2(0, bottom.position.y, left_width, 126), Rect2(0, 0, left_width, 126))
	draw_texture_rect_region(texture, layout["minimap_plane"], Rect2(792, 0, 232, 126))

func living_player_count() -> int:
	return units.filter(func(unit): return unit["team"] == local_player_team and unit["hp"] > 0.0).size()

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
	# Tree depletion changes terrain artwork but not land/water geography. Rebuild
	# the small minimap raster only when navigable surface topology changes.
	var terrain_revision := int(simulation_world.navigation_grid.surface_revision) if simulation_world != null else -1
	if cached_minimap_terrain_texture == null or cached_minimap_terrain_revision != terrain_revision or cached_minimap_terrain_rectangle != rectangle:
		var terrain_image := MinimapTerrainRaster.build(map_size, rectangle, center, scale, Callable(self, "terrain_id_at_cell"))
		cached_minimap_terrain_texture = ImageTexture.create_from_image(terrain_image)
		cached_minimap_terrain_revision = terrain_revision
		cached_minimap_terrain_rectangle = rectangle
	if cached_minimap_terrain_texture != null:
		draw_texture(cached_minimap_terrain_texture, rectangle.position)
	var exploration_revision := int(presentation_snapshot.get("fog_exploration_revision", presentation_snapshot.get("fog_revision", -1)))
	if cached_minimap_fog_texture == null or cached_minimap_exploration_revision != exploration_revision or cached_minimap_fog_rectangle != rectangle:
		var fog_image := MinimapTerrainRaster.build_fog(map_size, rectangle, center, scale, presentation_snapshot.get("fog", {}).get("cells", []))
		# Retain the bounded CPU raster as the authoritative upload payload. This
		# also makes headless verification independent of renderer-specific texture
		# readback behavior while the live view continues reusing one GPU texture.
		cached_minimap_fog_image = fog_image
		if cached_minimap_fog_texture == null or cached_minimap_fog_rectangle != rectangle:
			cached_minimap_fog_texture = ImageTexture.create_from_image(fog_image)
		else:
			cached_minimap_fog_texture.update(fog_image)
		cached_minimap_exploration_revision = exploration_revision
		cached_minimap_fog_rectangle = rectangle
	if cached_minimap_fog_texture != null:
		draw_texture(cached_minimap_fog_texture, rectangle.position)
	var snapshot_tick := int(presentation_snapshot.get("overview_tick", presentation_snapshot.get("tick", -1)))
	# Keep resource and unit markers independent of changing visibility.
	if cached_minimap_mesh == null or cached_minimap_mesh_tick != snapshot_tick or cached_minimap_mesh_rectangle != rectangle:
		cached_minimap_mesh_rectangle = rectangle
		cached_minimap_mesh = _build_minimap_mesh(center, scale)
		cached_minimap_mesh_tick = snapshot_tick
	if cached_minimap_mesh != null:
		draw_mesh(cached_minimap_mesh, null)
	draw_polyline(PackedVector2Array([map_points[0], map_points[1], map_points[2], map_points[3], map_points[0]]), Color("d2bd7d"), 1.0)
	var camera_world := PackedVector2Array([
		Coordinates.clamp_world(screen_to_world(Vector2(0, hud_top_height())), map_size),
		Coordinates.clamp_world(screen_to_world(Vector2(get_viewport_rect().size.x, hud_top_height())), map_size),
		Coordinates.clamp_world(screen_to_world(Vector2(get_viewport_rect().size.x, get_viewport_rect().size.y - hud_bottom_height())), map_size),
		Coordinates.clamp_world(screen_to_world(Vector2(0, get_viewport_rect().size.y - hud_bottom_height())), map_size),
	])
	var camera_points := PackedVector2Array()
	for world_point in camera_world:
		camera_points.append(MinimapProjection.world_to_minimap(world_point, center, scale))
	if camera_points.size() >= 3:
		camera_points.append(camera_points[0])
		draw_polyline(camera_points, Color("f5e28d"), 1.0, true)


func _build_minimap_mesh(center: Vector2, scale: float) -> ArrayMesh:
	var probe: Variant = game_controller.performance_probe if game_controller != null else null
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	# Imported campaigns may contain ten thousand individual trees. At minimap
	# scale many of them land on the same two-pixel cell, so drawing a circle for
	# every source entity only creates hundreds of thousands of overlapping
	# vertices. Collapse them into deterministic screen-space resource pixels.
	for pixel_center in _minimap_resource_pixels(center, scale, cached_minimap_mesh_rectangle):
		_append_colored_quad(vertices, colors, PackedVector2Array([
			pixel_center + Vector2(-1.0, -1.0),
			pixel_center + Vector2(1.0, -1.0),
			pixel_center + Vector2(1.0, 1.0),
			pixel_center + Vector2(-1.0, 1.0),
		]), Color("18591d"))
	if probe != null:
		probe.observe_microseconds("presentation.minimap.resources", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	for unit in overview_units:
		if unit["hp"] > 0.0:
			_append_colored_circle(vertices, colors, minimap_position(unit["pos"], center, scale), 2.0, Color("40b9ff") if unit["team"] == local_player_team else Color("e33d31"))
	for building in overview_buildings:
		if building["hp"] > 0.0:
			_append_colored_circle(vertices, colors, minimap_position(building["pos"], center, scale), 3.0, Color("f0d16d") if building["team"] == local_player_team else Color("e33d31"))
	if probe != null:
		probe.observe_microseconds("presentation.minimap.entities", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if probe != null:
		probe.observe_microseconds("presentation.minimap.surface", Time.get_ticks_usec() - stage_started)
	return mesh


func _minimap_resource_pixels(center: Vector2, scale: float, rectangle: Rect2) -> Array[Vector2]:
	var changes: Variant = simulation_world.consume_known_resource_marker_changes(local_player_team) if simulation_world != null else null
	var probe: Variant = game_controller.performance_probe if game_controller != null else null
	return minimap_resource_index.synchronize(overview_resource_nodes, changes, center, scale, rectangle,
		func(position: Vector2): return presentation_fog_state_at(position) != FogOfWar.UNKNOWN, probe)


func _append_colored_quad(vertices: PackedVector3Array, colors: PackedColorArray, points: PackedVector2Array, color: Color) -> void:
	if points.size() < 4:
		return
	for index in [0, 1, 2, 0, 2, 3]:
		var point := points[index]
		vertices.append(Vector3(point.x, point.y, 0.0))
		colors.append(color)


func _append_colored_circle(vertices: PackedVector3Array, colors: PackedColorArray, center: Vector2, radius: float, color: Color) -> void:
	const SEGMENTS := 8
	for index in range(SEGMENTS):
		var first_angle := TAU * float(index) / float(SEGMENTS)
		var second_angle := TAU * float(index + 1) / float(SEGMENTS)
		for point in [center, center + Vector2(cos(first_angle), sin(first_angle)) * radius, center + Vector2(cos(second_angle), sin(second_angle)) * radius]:
			vertices.append(Vector3(point.x, point.y, 0.0))
			colors.append(color)

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
		screen_to_world(Vector2(0, hud_top_height())),
		screen_to_world(Vector2(viewport_size.x, hud_top_height())),
		screen_to_world(Vector2(viewport_size.x, viewport_size.y - hud_bottom_height())),
		screen_to_world(Vector2(0, viewport_size.y - hud_bottom_height())),
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


func hud_top_height() -> float:
	return 64.0 if get_viewport_rect().size.x < 720.0 else 32.0


func hud_bottom_height() -> float:
	return 252.0 if get_viewport_rect().size.x < 720.0 else 126.0


func select_hud_building(building_id: int) -> void:
	if simulation_world == null:
		return
	var building: Variant = simulation_world.find_building(building_id)
	if building == null or int(building.get("team", 0)) != local_player_team or float(building.get("hp", 0)) <= 0:
		return
	var ids: Array[int] = [building_id]
	player_control_state.replace_or_add(ids, false)
	center_view_on_world(Vector2(building.get("pos", Vector2.ZERO)))
	sync_world_state()
	refresh_hud_model()
	queue_redraw()


func draw_map_edge_fog_overlay() -> void:
	# Crowns can project outside the finite terrain mesh. Continue the boundary
	# cell's fog there, without tinting the black void or drawing across sprites.
	if simulation_world == null or cached_world_fog_texture == null:
		return
	if cached_map_edge_fog_revision != int(simulation_world.terrain_revision):
		cached_map_edge_fog_meshes.clear()
		cached_map_edge_fog_revision = int(simulation_world.terrain_revision)
	var visible := visible_tile_bounds()
	var skirt := 6
	var regions := {
		"top": Rect2i(-skirt, -skirt, map_size.x + skirt * 2, skirt),
		"bottom": Rect2i(-skirt, map_size.y, map_size.x + skirt * 2, skirt),
		"left": Rect2i(-skirt, 0, skirt, map_size.y),
		"right": Rect2i(map_size.x, 0, skirt, map_size.y),
	}
	var needed := []
	if visible.position.y < skirt: needed.append("top")
	if visible.end.y > map_size.y - skirt: needed.append("bottom")
	if visible.position.x < skirt: needed.append("left")
	if visible.end.x > map_size.x - skirt: needed.append("right")
	draw_set_transform(PixelScaling.snap_screen(view_offset), 0.0, Vector2(view_zoom, view_zoom))
	for edge in needed:
		if not cached_map_edge_fog_meshes.has(edge):
			cached_map_edge_fog_meshes[edge] = _build_world_fog_mesh(regions[edge])
		draw_mesh(cached_map_edge_fog_meshes[edge], cached_world_fog_texture, Transform2D.IDENTITY, Color.BLACK)
	draw_set_transform(Vector2.ZERO)
