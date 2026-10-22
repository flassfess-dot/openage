extends Node2D

const MatchMinimapRenderer := preload("res://scripts/match_minimap_renderer.gd")
var minimap_renderer := MatchMinimapRenderer.new()

const MatchFogRenderer := preload("res://scripts/match_fog_renderer.gd")
var fog_renderer := MatchFogRenderer.new()

const MatchCommandActions := preload("res://scripts/match_command_actions.gd")
var command_actions := MatchCommandActions.new()

const Coordinates := preload("res://scripts/coordinates.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationOwner := preload("res://scripts/simulation_owner.gd")
const RenderTerrainView := preload("res://scripts/render_terrain_view.gd")
var simulation_owner := SimulationOwner.new()
var simulation_owner_enabled := DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-simulation-owner")
var render_terrain_view
var owner_delta := 0.0
var owner_state: Dictionary = {}
var owner_message := ""
var owner_alpha_started := 0
var owner_speed := 1.0
var owner_formation_groups: Dictionary = {}

const RoRCommands = preload("res://scripts/commands.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const Diagnostics := preload("res://scripts/diagnostics.gd")
const InputAdapter := preload("res://scripts/input_adapter.gd")
const PointerController := preload("res://scripts/pointer_controller.gd")
const PickingService := preload("res://scripts/picking_service.gd")
const CommandFeedbackRouter := preload("res://scripts/command_feedback_router.gd")
const FishShoalSelection := preload("res://scripts/fish_shoal_selection.gd")
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
const NavigationLoading := preload("res://scripts/navigation_loading.gd")
var navigation_loading := NavigationLoading.new()
var navigation_loading_label: Label
const PresentationPublication := preload("res://scripts/presentation_publication.gd")
var presentation_publication := PresentationPublication.new()
const BackgroundSaveTask := preload("res://scripts/background_save_task.gd")
const BackgroundSaveQueue := preload("res://scripts/background_save_queue.gd")
const TaskData := preload("res://scripts/isolated_task_data.gd")
var background_saves := BackgroundSaveQueue.new()
const BackgroundAutosave := preload("res://scripts/background_autosave.gd")
var autosave := BackgroundAutosave.new()
const TaskCoordinator := preload("res://scripts/isolated_task_coordinator.gd")
const AiPlanningTask := preload("res://scripts/ai_planning_task.gd")
const CacheDependency := preload("res://scripts/cache_dependency.gd")
const AiDecisionQueue := preload("res://scripts/ai_decision_queue.gd")
var ai_decision_queue := AiDecisionQueue.new()
var task_coordinator := TaskCoordinator.new()
const AiPlayer := preload("res://scripts/ai_player.gd")
const AiObservationStore := preload("res://scripts/ai_observation_store.gd")
const AiObservationPreparation := preload("res://scripts/ai_observation_preparation.gd")
const AiRuntimeCoordinator := preload("res://scripts/ai_runtime_coordinator.gd")
const MatchLifecycle := preload("res://scripts/match_lifecycle_service.gd")
const RenderSnapshotSource := preload("res://scripts/render_snapshot_source.gd")
const InputCommandRouter := preload("res://scripts/input_command_router.gd")
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
const FormationSelection := preload("res://scripts/formation_selection.gd")
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
var ai_runtime := AiRuntimeCoordinator.new()
var match_lifecycle := MatchLifecycle.new()
var render_snapshot_source := RenderSnapshotSource.new()
var input_adapter := InputAdapter.new()
var picking_service := PickingService.new()
var selection_preview_ids: Array[int] = []
var command_feedback_router := CommandFeedbackRouter.new()
var command_marker_presentation := CommandMarkerPresentation.new()
var minimap_right_pressed := false
var cached_rally_drawables: Array = []
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
var pending_build_kind: String:
	get:
		return command_actions.pending_build_kind
	set(value):
		command_actions.pending_build_kind = value
var pending_gate_axis: int:
	get:
		return command_actions.pending_gate_axis
	set(value):
		command_actions.pending_gate_axis = value
var pending_build_started: bool:
	get:
		return command_actions.pending_build_started
	set(value):
		command_actions.pending_build_started = value
var resource_feedback_id: int:
	get:
		return command_actions.resource_feedback_id
	set(value):
		command_actions.resource_feedback_id = value
var resource_feedback_time: float:
	get:
		return command_actions.resource_feedback_time
	set(value):
		command_actions.resource_feedback_time = value
var placement_preview_key: String:
	get:
		return command_actions.placement_preview_key
	set(value):
		command_actions.placement_preview_key = value
var placement_preview_valid: bool:
	get:
		return command_actions.placement_preview_valid
	set(value):
		command_actions.placement_preview_valid = value
var wall_placement_preview_key: String:
	get:
		return command_actions.wall_placement_preview_key
	set(value):
		command_actions.wall_placement_preview_key = value
var wall_placement_preview: Dictionary:
	get:
		return command_actions.wall_placement_preview
	set(value):
		command_actions.wall_placement_preview = value
var wall_preview_renderer: RenderWorld:
	get:
		return command_actions.wall_preview_renderer
	set(value):
		command_actions.wall_preview_renderer = value
var pending_target_command: String:
	get:
		return command_actions.pending_target_command
	set(value):
		command_actions.pending_target_command = value
var pending_target_queue_order: bool:
	get:
		return command_actions.pending_target_queue_order
	set(value):
		command_actions.pending_target_queue_order = value
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
var match_preferences := preload("res://scripts/match_preferences.gd").new()
var menu_details_tick := -1
var viewport_focus := Vector2.ZERO
var launcher_quit_confirmation: ConfirmationDialog
var launcher_suspended := false
var launcher_restore_paused := false
var launcher_audio_states: Array[Dictionary] = []
var last_save_error := ""
var hud_view_model := HudViewModel.new()
var hud_model: Dictionary = {}
var cached_hud_signature: Variant = null
var scenario_overlay: ScenarioOverlay
var terrain_canvas: TerrainCanvas
var cached_fog_revision: int:
	get:
		return fog_renderer.cached_fog_revision
	set(value):
		fog_renderer.cached_fog_revision = value
var cached_fog_runs: Array:
	get:
		return fog_renderer.cached_fog_runs
	set(value):
		fog_renderer.cached_fog_runs = value
var cached_world_fog_meshes: Dictionary:
	get:
		return fog_renderer.cached_world_fog_meshes
	set(value):
		fog_renderer.cached_world_fog_meshes = value
var cached_world_fog_mesh_terrain_revision: int:
	get:
		return fog_renderer.cached_world_fog_mesh_terrain_revision
	set(value):
		fog_renderer.cached_world_fog_mesh_terrain_revision = value
var cached_world_fog_texture: ImageTexture:
	get:
		return fog_renderer.cached_world_fog_texture
	set(value):
		fog_renderer.cached_world_fog_texture = value
var cached_world_fog_texture_data: PackedByteArray:
	get:
		return fog_renderer.cached_world_fog_texture_data
	set(value):
		fog_renderer.cached_world_fog_texture_data = value
var cached_world_fog_texture_revision: int:
	get:
		return fog_renderer.cached_world_fog_texture_revision
	set(value):
		fog_renderer.cached_world_fog_texture_revision = value
var cached_world_fog_stamp: Dictionary:
	get:
		return fog_renderer.cached_world_fog_stamp
	set(value):
		fog_renderer.cached_world_fog_stamp = value
var cached_fog_slope_neighbor_cells: PackedByteArray:
	get:
		return fog_renderer.cached_fog_slope_neighbor_cells
	set(value):
		fog_renderer.cached_fog_slope_neighbor_cells = value
var cached_fog_slope_neighbor_terrain_revision: int:
	get:
		return fog_renderer.cached_fog_slope_neighbor_terrain_revision
	set(value):
		fog_renderer.cached_fog_slope_neighbor_terrain_revision = value
var cached_map_edge_chains: Array[PackedVector2Array]:
	get:
		return fog_renderer.cached_map_edge_chains
	set(value):
		fog_renderer.cached_map_edge_chains = value
var cached_map_edge_fog_meshes: Dictionary:
	get:
		return fog_renderer.cached_map_edge_fog_meshes
	set(value):
		fog_renderer.cached_map_edge_fog_meshes = value
var cached_map_edge_fog_revision: int:
	get:
		return fog_renderer.cached_map_edge_fog_revision
	set(value):
		fog_renderer.cached_map_edge_fog_revision = value
var cached_map_edge_zoom: float:
	get:
		return fog_renderer.cached_map_edge_zoom
	set(value):
		fog_renderer.cached_map_edge_zoom = value
var cached_map_edge_terrain_revision: int:
	get:
		return fog_renderer.cached_map_edge_terrain_revision
	set(value):
		fog_renderer.cached_map_edge_terrain_revision = value
var cached_minimap_mesh: ArrayMesh:
	get:
		return minimap_renderer.cached_minimap_mesh
	set(value):
		minimap_renderer.cached_minimap_mesh = value
var cached_minimap_terrain_texture: ImageTexture:
	get:
		return minimap_renderer.cached_minimap_terrain_texture
	set(value):
		minimap_renderer.cached_minimap_terrain_texture = value
var cached_minimap_terrain_revision: int:
	get:
		return minimap_renderer.cached_minimap_terrain_revision
	set(value):
		minimap_renderer.cached_minimap_terrain_revision = value
var cached_minimap_terrain_rectangle: Rect2:
	get:
		return minimap_renderer.cached_minimap_terrain_rectangle
	set(value):
		minimap_renderer.cached_minimap_terrain_rectangle = value
var cached_minimap_fog_texture: ImageTexture:
	get:
		return minimap_renderer.cached_minimap_fog_texture
	set(value):
		minimap_renderer.cached_minimap_fog_texture = value
var cached_minimap_fog_image: Image:
	get:
		return minimap_renderer.cached_minimap_fog_image
	set(value):
		minimap_renderer.cached_minimap_fog_image = value
var cached_minimap_exploration_revision: int:
	get:
		return minimap_renderer.cached_minimap_exploration_revision
	set(value):
		minimap_renderer.cached_minimap_exploration_revision = value
var cached_minimap_fog_tick: int:
	get:
		return minimap_renderer.cached_minimap_fog_tick
	set(value):
		minimap_renderer.cached_minimap_fog_tick = value
var cached_minimap_fog_rectangle: Rect2:
	get:
		return minimap_renderer.cached_minimap_fog_rectangle
	set(value):
		minimap_renderer.cached_minimap_fog_rectangle = value
var cached_minimap_mesh_tick: int:
	get:
		return minimap_renderer.cached_minimap_mesh_tick
	set(value):
		minimap_renderer.cached_minimap_mesh_tick = value
var cached_minimap_mesh_rectangle: Rect2:
	get:
		return minimap_renderer.cached_minimap_mesh_rectangle
	set(value):
		minimap_renderer.cached_minimap_mesh_rectangle = value
var minimap_resource_index: MinimapResourceIndex:
	get:
		return minimap_renderer.minimap_resource_index
	set(value):
		minimap_renderer.minimap_resource_index = value
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

func join_simulation_owner() -> void:
	if not simulation_owner.pending: return
	owner_state = simulation_owner.take()
	owner_message = String(owner_state.get("message", ""))
	if bool(owner_state.get("failed", false)):
		simulation_owner_enabled = false
		game_controller.set_paused(true)
	if not String(owner_state.get("error", "")).is_empty():
		game_message = owner_state["error"]
		message_time = 8.0

func simulation_frame_state() -> Dictionary:
	if simulation_owner.pending: return owner_state.duplicate()
	return {"tick":game_controller.tick_index,"waiting":game_controller.preparation_waiting,"ai_capture":ai_decision_queue.active and not ai_decision_queue.is_prepared(),"ai_active":ai_decision_queue.active,"apply_tick":ai_decision_queue.apply_tick,"source_tick":ai_decision_queue.source_tick,"capture_phase":ai_runtime.preparation.captures.values()[0]["phase"] if not ai_runtime.preparation.captures.is_empty() else "","debt":game_controller.accumulator_seconds}

func _render_terrain():
	return render_terrain_view if render_terrain_view != null else simulation_world

func _presentation_probe():
	return null if simulation_owner.pending else game_controller.performance_probe if game_controller != null else null

func _can_use_simulation_owner() -> bool:
	if not simulation_owner_enabled or not network_role.is_empty() or network_session != null:
		return false
	if game_controller == null or game_controller.performance_probe != null or diagnostics_enabled:
		return false
	if navigation_loading.is_loading() or not pending_build_kind.is_empty():
		return false
	return not (scenario_overlay != null and scenario_overlay.is_blocking()) and not (hud_modal_overlay != null and hud_modal_overlay.is_blocking())

func _prepare_owner_presentation() -> void:
	_refresh_render_terrain()
	_sync_terrain_canvas()
	_sync_fog_geometry_revision()
	_sync_world_fog_texture(presentation_snapshot.get("fog", {}).get("cells", []), int(presentation_snapshot.get("fog_revision", -1)))
	var geometry := minimap_geometry()
	_minimap_resource_pixels(geometry["center"], geometry["scale"], geometry["rectangle"])
	owner_state = simulation_frame_state()
	owner_state["alpha"] = game_controller.get_interpolation_alpha()
	owner_alpha_started = Time.get_ticks_usec()
	owner_speed = game_controller.get_speed_multiplier()
	owner_formation_groups = {}
	for group_id in game_controller.formation_groups:
		owner_formation_groups[group_id] = {"preferred_formation_type":game_controller.formation_groups[group_id].preferred_formation_type}

func _refresh_render_terrain() -> void:
	if not simulation_owner_enabled: return
	if not network_role.is_empty() or network_session != null:
		render_terrain_view = null
		if terrain_canvas != null: terrain_canvas.simulation_world = simulation_world
		return
	if render_terrain_view == null: render_terrain_view = RenderTerrainView.new()
	render_terrain_view.synchronize(simulation_world)
	if terrain_canvas != null: terrain_canvas.simulation_world = render_terrain_view

func _owner_interpolation_alpha() -> float:
	return clampf(float(owner_state.get("alpha", 1.0)) + float(Time.get_ticks_usec() - owner_alpha_started) * 0.000001 * owner_speed / GameController.FIXED_STEP_SECONDS, 0.0, 1.0)

func _process_owner_presentation(delta: float) -> void:
	if resource_catalog != null: resource_catalog.unit_presentations.poll_background_loading()
	presentation_audio_router.advance(delta)
	presentation_effect_timeline.advance(delta)
	_sync_effect_snapshot()
	update_camera(delta)
	_sync_terrain_canvas()
	message_time = maxf(0.0, message_time - delta)
	command_marker_presentation.advance(delta)
	resource_feedback_time = maxf(0.0, resource_feedback_time - delta)
	queue_redraw()

func _ready() -> void:
	match_preferences.load_settings()
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_request_window_quit)
	preload("res://scripts/rendering_configuration.gd").apply_window_presentation()
	font = ThemeDB.fallback_font
	resource_catalog = ResourceCatalog.new()
	resource_catalog.load()
	resource_catalog.unit_presentations.background_loading_enabled = task_coordinator.is_enabled("animation_loading")
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
	resource_catalog.configure_player_colors(match_definition.get("players", []))
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
	render_world.player_palette = resource_catalog.player_palette
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
	hud_modal_overlay.restart_requested.connect(_restart_from_menu)
	hud_modal_overlay.quit_requested.connect(func(): get_tree().quit())
	hud_modal_overlay.preferences_requested.connect(_apply_menu_preferences)
	hud_modal_overlay.details_requested.connect(_refresh_menu_details)
	hud_modal_overlay.diplomacy_relation_requested.connect(_change_diplomacy_from_hud)
	hud_modal_overlay.tribute_requested.connect(_pay_tribute_from_hud)
	scenario_overlay = ScenarioOverlay.new()
	add_child(scenario_overlay)
	scenario_overlay.configure(match_definition, resource_catalog.localization, resource_catalog.object_catalog_data)
	scenario_overlay.restart_requested.connect(_restart_from_scenario_overlay)
	scenario_overlay.menu_requested.connect(_request_return_to_launcher)
	scenario_overlay.statistics_requested.connect(func():
		_open_hud_modal(HUDModalOverlay.MODE_MENU)
		hud_modal_overlay.show_section("achievements")
	)

	navigation_loading_label = Label.new()
	navigation_loading_label.text = "Подготовка карты…"
	navigation_loading_label.position = Vector2(20, 80)
	navigation_loading_label.z_index = 4096
	navigation_loading_label.hide()
	add_child(navigation_loading_label)
	reset_game()
	_apply_audio_preferences()
	get_node("/root/WindowMode").mode_changed.connect(_on_window_mode_changed)
	if not network_role.is_empty():
		_start_network_match()
		if network_session != null:
			_create_network_chat_input()
	setup_audio()
	setup_sfx()
	get_viewport().size_changed.connect(func(): center_initial_view(false))
	center_initial_view()
func unit_stats(kind: String) -> Dictionary:
	join_simulation_owner()
	if simulation_world == null:
		return gamespec_data.get("units", {}).get(kind, {})
	return simulation_world.unit_stats(kind)


func _new_simulation_world(size_override: Vector2i = Vector2i.ZERO):
	join_simulation_owner()
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

func center_initial_view(recenter: bool = true) -> void:
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
	var focus := Vector2(size.x * 0.5, (size.y - hud_bottom_height() + hud_top_height()) * 0.48)
	if not recenter and viewport_focus != Vector2.ZERO:
		view_offset += focus - viewport_focus
	else:
		var initial_world := Vector2(map_size.x / 2.0, map_size.y / 2.0)
		var local_team := local_player_team
		for player_value in match_definition.get("players", []):
			var player: Dictionary = player_value
			if int(player.get("team", 0)) == local_team:
				initial_world = player.get("start", initial_world)
				break
		var initial_screen := iso_raw(initial_world) * view_zoom
		view_offset = focus - initial_screen
	viewport_focus = focus
	_sync_terrain_canvas()
	queue_redraw()

func reset_game() -> void:
	join_simulation_owner()
	render_terrain_view = null
	owner_delta = 0.0
	owner_message = ""
	autosave.shutdown()
	PickingService.SelectionResolver.clear_hit_images()
	navigation_loading.shutdown()
	background_saves.drain()
	presentation_publication.clear()
	match_lifecycle.retire_runtime(simulation_world, ai_runtime, render_snapshot_source, ai_decision_queue, task_coordinator)
	if simulation_world == null:
		return
	var bootstrap: Dictionary = MatchBootstrap.apply(simulation_world, match_definition, map_definition)
	resource_catalog.unit_presentations.shutdown_loading()
	resource_catalog.prewarm_match_entities(simulation_world.get_units(), simulation_world.get_buildings())
	game_controller.reset_timing()
	game_controller.start_recording(map_seed, false)
	game_controller.set_command_result_limit(1024)
	configure_ai_players()
	# Full-map masks and surface connectivity are loading work, not work for
	# the first AI decision or the first unit movement after the match opens.
	navigation_loading.begin(simulation_world, match_definition.get("players", []))
	game_controller.set_before_fixed_tick(Callable(self, "queue_ai_commands"))
	control_groups.clear()
	player_control_state.clear()
	sound_cue_history.reset()
	compact_status_visible = false
	local_spectator = false
	_reset_command_feedback()
	_reset_world_fog_cache()
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
	_reset_minimap_fog_cache()
	cached_minimap_mesh_tick = -1
	cached_minimap_mesh_rectangle = Rect2()
	minimap_resource_index.clear()
	_reset_overview_cache()
	cached_environment_bounds = Rect2i()
	cached_environment_items.clear()
	if render_world != null:
		render_world.clear_caches()
	command_marker_presentation.reset()
	minimap_right_pressed = false
	cached_rally_drawables.clear()
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

	_refresh_render_terrain()
	sync_world_state()
	# The initial fog mask scans the whole map; prepare it while the match is
	# loading, so the first visible frame only submits cached presentation.
	cached_fog_slope_neighbor_terrain_revision = _terrain_geometry_revision()
	_sync_world_fog_texture(presentation_snapshot.get("fog", {}).get("cells", []), int(presentation_snapshot.get("fog_revision", -1)))
	if scenario_overlay != null:
		scenario_overlay.reset_presentation()
		scenario_overlay.set_snapshot(presentation_snapshot)
	if hud_modal_overlay != null:
		hud_modal_overlay.close()
	game_message = String(bootstrap.get("message", "Матч начат"))
	message_time = 7.0
	_seed_autosave()
	queue_redraw()

func add_unit(team: int, kind: String, position: Vector2, selected: bool) -> Dictionary:
	join_simulation_owner()
	if simulation_world == null:
		return {"id": -1}
	var unit: Dictionary = simulation_world.add_unit(team, kind, position, false)
	if selected and team == local_player_team:
		player_control_state.replace_or_add([int(unit["id"])], true)
	return unit

func add_resource(kind: String, position: Vector2, amount: int) -> void:
	join_simulation_owner()
	if simulation_world == null:
		return
	simulation_world.add_resource(kind, position, amount)
func _process(delta: float) -> void:
	owner_delta += delta
	if simulation_owner.pending:
		if not simulation_owner.ready():
			_process_owner_presentation(delta)
			return
		join_simulation_owner()
	var probe: Variant = _presentation_probe()
	var frame_started := Time.get_ticks_usec() if probe != null else 0
	if navigation_loading.is_loading():
		if navigation_loading_label != null:
			navigation_loading_label.show()
		if not navigation_loading.poll(simulation_world):
			owner_delta = 0.0
			queue_redraw()
			return

		if navigation_loading_label != null:
			navigation_loading_label.hide()
	task_coordinator.reap_abandoned()
	_poll_save_jobs()
	_poll_autosave(owner_delta)
	if resource_catalog != null:
		resource_catalog.unit_presentations.poll_background_loading()
	if probe != null: probe.observe_microseconds("presentation.process.background_loading", Time.get_ticks_usec() - frame_started)
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	presentation_audio_router.advance(delta)
	presentation_effect_timeline.advance(delta)
	_sync_effect_snapshot()
	if network_session != null:
		_network_update(delta)
	if probe != null:
		probe.observe_microseconds("presentation.process.audio_effects", Time.get_ticks_usec() - stage_started)
	if scenario_overlay != null and scenario_overlay.is_blocking():
		owner_delta = 0.0
		return
	if hud_modal_overlay != null and hud_modal_overlay.is_blocking():
		if network_session != null and hud_modal_overlay.active_section in ["achievements", "timeline", "instructions"] and game_controller.tick_index % 20 == 0 and menu_details_tick != game_controller.tick_index:
			_refresh_menu_details()
		owner_delta = 0.0
		return
	stage_started = Time.get_ticks_usec() if probe != null else 0
	update_camera(delta)
	_sync_terrain_canvas()
	if probe != null:
		probe.observe_microseconds("presentation.process.camera_terrain", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	if network_session == null:
		update_units(owner_delta)
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
	if _can_use_simulation_owner() and not game_controller.paused:
		_prepare_owner_presentation()
		_configure_ai_runtime()
		game_controller.set_before_fixed_tick(Callable(ai_runtime, "queue_commands"))
		if not simulation_owner.submit(game_controller, ai_runtime, owner_delta, local_player_team, ENEMY_TEAM, Engine.get_process_frames()):
			simulation_owner_enabled = false
			game_controller.advance_frame(owner_delta, local_player_team, ENEMY_TEAM)
	owner_delta = 0.0

func update_camera(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y -= 1.0
	if get_window().has_focus():
		var window := get_window()
		direction += PointerController.window_edge_scroll_direction(Vector2(DisplayServer.mouse_get_position()), Rect2(Vector2(window.position), Vector2(window.size)))
	if direction != Vector2.ZERO:
		view_offset += direction.normalized() * 430.0 * float(match_preferences.values["scroll"]) * delta

func update_units(delta: float) -> void:
	if game_controller == null or simulation_world == null:
		return
	var probe: Variant = game_controller.performance_probe
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	var battle_text := owner_message
	owner_message = ""
	if not _can_use_simulation_owner():
		game_controller.set_before_fixed_tick(Callable(self, "queue_ai_commands"))
		battle_text = game_controller.advance_frame(delta, local_player_team, ENEMY_TEAM)
	if render_terrain_view != null: render_terrain_view.synchronize(simulation_world)
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
	join_simulation_owner()
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
	join_simulation_owner()
	InputCommandRouter.route(command, game_controller, local_player_team, network_session, pending_network_commands, network_frame_submitted_tick)


func _register_local_feedback(command, accepted_message: String, sound_name: String, marker: Variant) -> void:
	if network_session == null:
		command_feedback_router.register(command, accepted_message, sound_name, marker)
	else:
		network_feedback_by_command[command.get_instance_id()] = {"accepted_message": accepted_message, "sound_name": sound_name, "marker": marker}


func _network_update(delta: float) -> void:
	join_simulation_owner()
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
	join_simulation_owner()
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
	join_simulation_owner()
	ai_runtime.shutdown()
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


func _configure_ai_runtime() -> void:
	join_simulation_owner()
	ai_runtime.configure(simulation_world, game_controller, ai_players, ai_decision_queue, ai_observation_store, task_coordinator)

func _capture_ai_decision(ai, next_tick: int) -> Dictionary:
	join_simulation_owner()
	_configure_ai_runtime()
	return ai_runtime.capture_ai(ai, next_tick)

func _next_ai_decision_tick(ai, next_tick: int) -> int:
	join_simulation_owner()
	_configure_ai_runtime()
	return ai_runtime.next_decision_tick(ai, next_tick)


func queue_ai_commands(next_tick: int = -1) -> Variant:
	join_simulation_owner()
	_configure_ai_runtime()
	var status: Variant = ai_runtime.queue_commands(next_tick)
	if not ai_runtime.error.is_empty():
		game_message = ai_runtime.error
		message_time = 8.0
	return status


func _poll_ai_decisions(next_tick: int) -> Dictionary:
	join_simulation_owner()
	_configure_ai_runtime()
	return ai_runtime._poll(next_tick)


func enqueue_with_feedback(command: Variant, accepted_message: String, sound_name: String, marker: Variant = null) -> void:
	if local_spectator or battle_over:
		return
	_queue_local_command(command)
	_register_local_feedback(command, accepted_message, sound_name, marker)


func process_presentation_events() -> void:
	join_simulation_owner()
	var new_events := game_controller.events_after(command_feedback_router.event_cursor)
	for feedback in command_feedback_router.consume(new_events, local_player_team):
		var quiet_order := bool(feedback["accepted"]) and String(feedback.get("command_type", "")) in ["train", "research", "cancel_production"]
		if not quiet_order:
			game_message = String(feedback["message"])
		if bool(feedback["accepted"]):
			var sound_name := String(feedback["sound_name"])
			if not sound_name.is_empty():
				play_sfx(sound_name)
			if not quiet_order and feedback["marker"] is Vector2:
				command_marker_presentation.trigger(feedback["marker"])
			elif not quiet_order and feedback["marker"] is Dictionary:
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
		presentation_snapshot = presentation_snapshot.duplicate()
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
	join_simulation_owner()
	if simulation_world == null:
		for unit in units:
			if unit["id"] == id:
				return unit
		return null
	return simulation_world.find_unit(id)

func find_resource(id: int):
	join_simulation_owner()
	if simulation_world == null:
		for resource in resource_nodes:
			if resource["id"] == id:
				return resource
		return null
	return simulation_world.find_resource(id)

func iso_raw(world: Vector2) -> Vector2:
	return Coordinates.iso_raw(world)

var projected_height_source: Variant = null
var projected_height_revision := -1
var projected_height_epoch := -1
var projected_heights: Dictionary = {}
const MAX_PROJECTED_HEIGHTS := 4096

func world_to_screen(world: Vector2) -> Vector2:
	if _render_terrain() == null:
		return Coordinates.world_to_screen(world, view_zoom, view_offset)
	var elevation = _render_terrain().terrain_elevation
	if projected_height_source != elevation or projected_height_revision != elevation.revision or projected_height_epoch != elevation.cache_epoch:
		projected_heights.clear()
		projected_height_source = elevation
		projected_height_revision = elevation.revision
		projected_height_epoch = elevation.cache_epoch
	var height := 0.0
	if elevation.nonzero_vertex_count > 0:
		if projected_heights.has(world): height = float(projected_heights[world])
		else:
			height = elevation.elevation_at_world(world)
			if projected_heights.size() >= MAX_PROJECTED_HEIGHTS: projected_heights.clear()
			projected_heights[world] = height
	# Keep the reference arithmetic order, including pixel rounding boundaries.
	return Coordinates.world_to_screen(world, view_zoom, view_offset) + elevation.screen_offset(height, view_zoom)

func screen_to_world(screen: Vector2) -> Vector2:
	if _render_terrain() != null:
		return _render_terrain().terrain_elevation.screen_to_world(screen, view_zoom, view_offset)
	return Coordinates.screen_to_world(screen, view_zoom, view_offset)

func _input(event: InputEvent) -> void:
	# Placement rotation must precede Control focus navigation on Tab.
	if pending_build_kind == "gate" and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB and (network_chat_input == null or not network_chat_input.visible):
		pending_gate_axis = 1 - pending_gate_axis
		placement_preview_key = ""
		queue_redraw()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if navigation_loading.is_loading():
		return
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
	return command_actions.handle_minimap_input(self, event)


func handle_input_action(action: Dictionary) -> void:
	command_actions.handle_input_action(self, action)


func _show_diplomacy_summary() -> void:
	_open_hud_modal(HUDModalOverlay.MODE_DIPLOMACY)


func _change_diplomacy_from_hud(target_team: int, relation: String) -> void:
	join_simulation_owner()
	if game_controller == null or local_spectator or battle_over or not RoRCommands.is_valid_diplomacy_relation(relation):
		return
	var command = RoRCommands.DiplomacyCommand.new(game_controller.tick_index + 1, target_team, relation)
	_queue_local_command(command)
	_register_local_feedback(command, "Дипломатия изменена", "", null)


func _pay_tribute_from_hud(target_team: int, resource_type_id: int, amount: int) -> void:
	join_simulation_owner()
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
	join_simulation_owner()
	if hud_modal_overlay == null or game_controller == null:
		return
	if not hud_modal_overlay.is_blocking():
		modal_restore_paused = game_controller.paused
	if network_session == null:
		game_controller.set_paused(true)
	hud_modal_overlay.set_snapshot(presentation_snapshot)
	hud_modal_overlay.set_capabilities(network_session != null)
	if mode == HUDModalOverlay.MODE_DIPLOMACY:
		hud_modal_overlay.show_diplomacy()
	else:
		hud_modal_overlay.set_save_available(FileAccess.file_exists(GameSaveArchive.SAVE_PATH))
		hud_modal_overlay.set_named_saves(GameSaveArchive.list_saves())
		hud_modal_overlay.set_menu_status("")
		hud_modal_overlay.show_menu()


func _close_hud_modal() -> void:
	join_simulation_owner()
	if hud_modal_overlay == null or not hud_modal_overlay.is_blocking():
		return
	hud_modal_overlay.close()
	if game_controller != null and network_session == null:
		game_controller.set_paused(modal_restore_paused)
	game_message = "Пауза" if modal_restore_paused else "Игра продолжена"
	message_time = 1.5


func _resign_from_hud_modal() -> void:
	join_simulation_owner()
	if hud_modal_overlay != null:
		hud_modal_overlay.close()
	if game_controller == null or local_spectator or battle_over:
		return
	game_controller.set_paused(false)
	var command = RoRCommands.ResignCommand.new(game_controller.tick_index + 1)
	_queue_local_command(command)
	_register_local_feedback(command, "Вы сдались", "", null)

func _restart_from_menu() -> void:
	join_simulation_owner()
	if network_session != null: return
	_close_hud_modal()
	game_controller.set_paused(false)
	reset_game()

func _request_window_quit() -> void:
	if launcher_suspended:
		if not is_instance_valid(launcher_quit_confirmation):
			launcher_quit_confirmation = ConfirmationDialog.new()
			launcher_quit_confirmation.theme = preload("res://scripts/match_menu_theme.gd").shared_theme()
			launcher_quit_confirmation.title = "Выйти из игры?"
			launcher_quit_confirmation.dialog_text = "Текущий матч хранится в памяти. При закрытии игры несохранённый прогресс будет потерян."
			launcher_quit_confirmation.ok_button_text = "Выйти"
			launcher_quit_confirmation.cancel_button_text = "Отмена"
			launcher_quit_confirmation.confirmed.connect(func(): get_tree().quit())
			get_tree().current_scene.add_child(launcher_quit_confirmation)
		launcher_quit_confirmation.popup_centered(Vector2i(480, 180))
		launcher_quit_confirmation.get_cancel_button().grab_focus()
		return
	if hud_modal_overlay == null: return
	_open_hud_modal(HUDModalOverlay.MODE_MENU)
	hud_modal_overlay.request_confirmation("quit")

func _request_return_to_launcher() -> void:
	_open_hud_modal(HUDModalOverlay.MODE_MENU)
	hud_modal_overlay.request_confirmation("launcher")

func _apply_audio_preferences() -> void:
	if audio_player != null: audio_player.volume_db = linear_to_db(maxf(0.00001, float(match_preferences.values["music"]))) - 14.0
	for player in sfx_players:
		if is_instance_valid(player): player.volume_db = linear_to_db(maxf(0.00001, float(match_preferences.values["sound"]))) - 3.0

func _apply_menu_preferences(values: Dictionary) -> void:
	join_simulation_owner()
	var error := match_preferences.save_settings(values)
	_apply_audio_preferences()
	if network_session == null and values.has("speed"): game_controller.set_speed_multiplier(float(values["speed"]))
	if get_viewport() == get_tree().root:
		get_node("/root/WindowMode").apply_settings(bool(values.get("fullscreen", false)), values.get("screen_size", get_window().size))
	hud_modal_overlay.set_menu_status("Настройки применены" if error == OK else "Настройки применены, но не удалось сохранить их на диск", error != OK)

func _on_window_mode_changed(fullscreen: bool) -> void:
	match_preferences.values["fullscreen"] = fullscreen
	match_preferences.values["screen_size"] = get_node("/root/WindowMode").windowed_size
	if hud_modal_overlay != null:
		hud_modal_overlay.preference_controls["fullscreen"].set_pressed_no_signal(fullscreen)

func _refresh_menu_details() -> void:
	join_simulation_owner()
	if simulation_world == null or game_controller == null: return
	var recorder = simulation_world.match_statistics
	var tick := mini(game_controller.tick_index, recorder.finished_tick) if recorder.finished_tick >= 0 else game_controller.tick_index
	menu_details_tick = game_controller.tick_index
	recorder.begin(simulation_world, tick)
	var history: Dictionary = recorder.state()
	var participants: Array = simulation_world.player_registry.all_teams()
	history["current_tick"] = tick
	history["reveal_all"] = true
	var rows := {}
	var current_values := {}
	for team_value in participants:
		var team := int(team_value)
		var row: Dictionary = history["teams"].get(team, {}).duplicate(true)
		row["population"] = simulation_world.get_population(team)
		row["peak_population"] = maxi(int(row.get("peak_population", 0)), int(row["population"]))
		row["age"] = simulation_world.get_current_age(team)
		row["status"] = simulation_world.player_registry.status(team)
		var identity: Dictionary = simulation_world.player_registry.players.get(team, {})
		row["color_index"] = int(identity.get("color_index", team))
		row["name"] = "Игрок %d · %s" % [team, hud_modal_overlay._civilization_name(int(identity.get("civilization_id", -1)))]
		row["temples"] = 0
		row["ruins"] = 0
		row["artifacts"] = 0
		for building in simulation_world.get_buildings():
			if int(building.get("team", 0)) == team and float(building.get("hp", 0)) > 0 and String(building.get("state", "complete")) == "complete" and String(building.get("kind", "")) == "temple": row["temples"] += 1
		for objective in simulation_world.victory_objectives:
			if int(objective.get("team", 0)) == team and bool(objective.get("active", true)) and bool(objective.get("completed", true)):
				var category := String(objective.get("category", ""))
				if category == "artifact": row["artifacts"] += 1
				elif category == "ruin": row["ruins"] += 1
		rows[team] = row
		current_values[team] = {"population": row["population"], "age": row["age"]}
	history["teams"] = rows
	if history["samples"].is_empty() or int(history["samples"][-1]["tick"]) != tick: history["samples"].append({"tick": tick, "teams": current_values})
	hud_modal_overlay.set_statistics(history)
	var model: Dictionary = scenario_overlay.presentation_model.duplicate(true) if scenario_overlay != null else {}
	for key in ["title", "briefing", "start_message", "hints", "history"]:
		if match_definition.has(key): model[key] = match_definition[key]
	hud_modal_overlay.set_instructions(model)
	var values: Dictionary = match_preferences.values.duplicate(true)
	values["screen_size"] = get_node("/root/WindowMode").windowed_size if get_node("/root/WindowMode").is_fullscreen() else get_window().size
	values["fullscreen"] = get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	hud_modal_overlay.set_preferences(values, game_controller.get_speed_multiplier())


func _save_quick_game() -> void:
	if request_save_game_to_path(GameSaveArchive.SAVE_PATH):
		hud_modal_overlay.set_menu_status("Сохранение…")
	else:
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)


func _load_quick_game() -> void:
	if not load_game_from_path(GameSaveArchive.SAVE_PATH):
		if hud_modal_overlay != null:
			hud_modal_overlay.show_section("load")
			hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)


func _save_named_game(name: String) -> void:
	if GameSaveArchive.normalized_slot_name(name) == GameSaveArchive.AUTOSAVE_NAME:
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message("slot_name_reserved"), true)
		return
	var path: String = GameSaveArchive.named_path(name)
	if path.is_empty():
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message("slot_name_invalid"), true)
		return
	if request_save_game_to_path(path, GameSaveArchive.normalized_slot_name(name)):
		hud_modal_overlay.set_named_saves(GameSaveArchive.list_saves())
		hud_modal_overlay.set_menu_status("Сохранение…")
	else:
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)


func _load_named_game(path: String) -> void:
	if not load_game_from_path(path):
		hud_modal_overlay.show_section("load")
		hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)


func _capture_save_input(path: String, slot_name: String = "Быстрое сохранение", metadata_only: bool = false) -> Dictionary:
	join_simulation_owner()
	last_save_error = ""
	if network_session != null:
		last_save_error = "network_save_unsupported"
		return {}
	if not GameSaveArchive.valid_slot_name(slot_name):
		last_save_error = "slot_name_invalid"
		return {}
	if game_controller == null or simulation_world == null or game_controller.replay_recorder == null:
		last_save_error = "runtime_not_ready"
		return {}
	var view_state := {
		"view_offset": view_offset,
		"view_zoom": view_zoom,
		"selection": player_control_state.selected_ids(),
		"formation": formation,
		"control_groups": control_groups.groups.duplicate(true),
		"last_recalled_group": control_groups.last_recalled_group,
		"compact_status_visible": compact_status_visible,
		"sound_cue_history": sound_cue_history.canonical_state(),
	}
	var controller_state := {
		"ai_decisions": ai_decision_queue.canonical_state(),
		"speed": game_controller.get_speed_multiplier(),
		"paused": launcher_restore_paused if launcher_suspended else modal_restore_paused if hud_modal_overlay != null and hud_modal_overlay.is_blocking() else game_controller.paused,
	}
	if metadata_only:
		return match_lifecycle.capture_save_header(game_controller, ai_players, ai_decision_queue, path, slot_name, match_path, match_definition, view_state, controller_state, false)
	var input: Dictionary = match_lifecycle.capture_save(simulation_world, game_controller, ai_players, ai_decision_queue, path, slot_name, match_path, match_definition, map_definition, view_state, controller_state)
	if not TaskData.is_detached(input):
		last_save_error = "capture_not_isolated"
		return {}
	return input

func _seed_autosave() -> void:
	join_simulation_owner()
	if not autosave.enabled or network_session != null or not network_role.is_empty(): return
	autosave.seed_from(simulation_world, game_controller, match_definition, map_definition, {"gamespec": gamespec_data, "terrain": resource_catalog.terrain_catalog_data, "objects": resource_catalog.object_catalog_data, "graphics": resource_catalog.graphics_catalog_data, "runtime": resource_catalog.runtime_catalog_data})

func _poll_autosave(delta: float) -> bool:
	join_simulation_owner()
	var result := autosave.poll()
	if not result.is_empty() and int(result["error"]) == OK and hud_modal_overlay != null:
		hud_modal_overlay.set_named_saves(GameSaveArchive.with_autosave_result(hud_modal_overlay.named_saves, result))
	var playable := network_session == null and not launcher_suspended and game_controller != null and simulation_world != null and not game_controller.paused and not simulation_world.battle_over and not (scenario_overlay != null and scenario_overlay.is_blocking()) and not (hud_modal_overlay != null and hud_modal_overlay.is_blocking())
	var committed := not result.is_empty() and int(result["error"]) == OK
	if not result.is_empty() and not committed:
		game_message = "Не удалось выполнить автосохранение. Повторим попытку."
		message_time = 6.0
	if not autosave.advance(delta, playable): return committed
	# A pending AI observation can contain a whole navigation map. Wait for its
	# normal publication instead of encoding it on the render thread.
	if ai_decision_queue.active or background_saves.active_request >= 0 or not background_saves.waiting.is_empty(): return committed
	var started := Time.get_ticks_usec()
	var input := _capture_save_input(GameSaveArchive.AUTOSAVE_PATH, GameSaveArchive.AUTOSAVE_NAME, true)
	if not input.is_empty(): autosave.submit(input, simulation_world, game_controller)
	autosave.last_capture_us = Time.get_ticks_usec() - started
	return committed

func request_save_game_to_path(path: String, slot_name: String = "Быстрое сохранение") -> bool:
	if background_saves.waiting.size() >= BackgroundSaveQueue.MAX_WAITING:
		last_save_error = "save_busy"
		return false
	var input := _capture_save_input(path, slot_name)
	if input.is_empty():
		return false
	if not background_saves.enqueue(input):
		last_save_error = "save_busy"
		return false
	return true

# Retain the synchronous public API used by tools and explicit callers.
func save_game_to_path(path: String, slot_name: String = "Быстрое сохранение") -> bool:
	background_saves.drain()
	var input := _capture_save_input(path, slot_name)
	if input.is_empty():
		return false
	var result := BackgroundSaveTask.run(input)
	if int(result["error"]) != OK:
		last_save_error = "write_failed:%d" % int(result["error"])
		return false
	return true

func _poll_save_jobs() -> void:
	for result in background_saves.poll():
		if int(result["error"]) != OK:
			last_save_error = "write_failed:%d" % int(result["error"])
			if hud_modal_overlay != null:
				hud_modal_overlay.set_menu_status(GameSaveArchive.error_message(last_save_error), true)
			continue
		last_save_error = ""
		if hud_modal_overlay != null:
			hud_modal_overlay.set_save_available(true)
			hud_modal_overlay.set_named_saves(GameSaveArchive.list_saves())
			hud_modal_overlay.set_menu_status("Игра сохранена" if String(result["path"]) == GameSaveArchive.SAVE_PATH else "Именованное сохранение создано")

func load_game_from_path(path: String, inspected: Dictionary = {}) -> bool:
	join_simulation_owner()
	background_saves.drain()
	last_save_error = ""
	if network_session != null:
		return _load_failed("network_load_unsupported")
	# Release the worker world before allocating the replacement match. A
	# failed explicit load reseeds the still-running original match below.
	autosave.shutdown()
	var restored: Dictionary = match_lifecycle.restore(path, Callable(self, "_new_simulation_world"), Callable(self, "_new_ai_players"), Callable(self, "_configure_runtime_ai_cadence"), Callable(self, "_capture_ai_decision"), inspected)
	if not String(restored["error"]).is_empty():
		_seed_autosave()
		return _load_failed(String(restored["error"]))
	var archive: Dictionary = restored["archive"]
	var restored_definition: Dictionary = restored["definition"]
	var restored_map: Dictionary = restored["map"]
	var restored_world = restored["world"]
	var restored_controller = restored["controller"]
	var restored_ai_players: Array = restored["players"]
	var restored_decisions = restored["decisions"]
	var restored_sound_history = restored["sound_history"]
	var saved_controller: Dictionary = archive["controller_state"]
	var saved_view: Dictionary = archive["view_state"]

	PickingService.SelectionResolver.clear_hit_images()
	match_definition = restored_definition
	resource_catalog.configure_player_colors(restored_definition.get("players", []))
	map_definition = restored_map
	if String(restored_map.get("environment_pack", "")) == "aoe2_temperate":
		resource_catalog.enable_environment_pack()
	interface_style_index = resource_catalog.interface_skin.style_index_for_match(restored_definition, resource_catalog.object_catalog_data)
	interface_panel_texture = resource_catalog.interface_skin.panel_texture(interface_style_index)
	hud_controls.configure_interface_skin(resource_catalog.interface_skin, interface_style_index)
	top_bar_controls.configure(resource_catalog.interface_skin, interface_style_index)
	hud_modal_overlay.configure(resource_catalog.interface_skin, restored_definition, interface_style_index, resource_catalog.localization)
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
	match_lifecycle.retire_runtime(simulation_world, ai_runtime, render_snapshot_source, ai_decision_queue, task_coordinator)
	navigation_loading.shutdown()
	render_terrain_view = null
	owner_delta = 0.0
	owner_message = ""
	simulation_world = restored_world
	game_controller = restored_controller
	game_controller.set_command_result_limit(1024)
	ai_observation_store.clear()
	presentation_publication.clear()
	ai_players = restored_ai_players
	ai_decision_queue = restored_decisions
	resource_catalog.unit_presentations.shutdown_loading()
	resource_catalog.prewarm_match_entities(simulation_world.get_units(), simulation_world.get_buildings())
	game_controller.set_before_fixed_tick(Callable(self, "queue_ai_commands"))
	game_controller.set_speed_multiplier(float(saved_controller.get("speed", 1.5)))
	game_controller.set_paused(bool(saved_controller.get("paused", false)))
	modal_restore_paused = game_controller.paused
	navigation_loading.begin(simulation_world, match_definition.get("players", []))
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
	_reset_command_feedback()
	command_marker_presentation.reset()
	minimap_right_pressed = false
	cached_rally_drawables.clear()
	_reset_world_fog_cache()
	_reset_minimap_fog_cache()
	_reset_overview_cache()
	pending_build_kind = ""
	pending_target_command = ""
	local_spectator = false
	_refresh_render_terrain()
	terrain_canvas.configure(map_size, map_seed, resource_catalog, _render_terrain(), Callable(self, "terrain_id_at_cell"), Callable(self, "visible_tile_bounds"))
	_sync_terrain_canvas()
	sync_world_state()
	# The initial fog mask scans the whole map; prepare it while the match is
	# loading, so the first visible frame only submits cached presentation.
	cached_fog_slope_neighbor_terrain_revision = _terrain_geometry_revision()
	_sync_world_fog_texture(presentation_snapshot.get("fog", {}).get("cells", []), int(presentation_snapshot.get("fog_revision", -1)))
	_seed_autosave()
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
	command_actions.assign_control_group(self, group_number)

func recall_control_group(group_number: int, additive: bool) -> void:
	command_actions.recall_control_group(self, group_number, additive)

func center_view_on_units(entity_ids: Array[int]) -> void:
	join_simulation_owner()
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
	var viewport := get_viewport_rect() if is_inside_tree() else Rect2()
	var interpolation_alpha := _owner_interpolation_alpha() if simulation_owner.pending else game_controller.get_interpolation_alpha() if game_controller != null else 1.0
	var highlighted_ids: Array[int] = selection_preview_ids.duplicate()
	if interaction_highlight_id >= 0 and not highlighted_ids.has(interaction_highlight_id):
		highlighted_ids.append(interaction_highlight_id)
	if resource_feedback_time > 0.0 and resource_feedback_id >= 0 and not highlighted_ids.has(resource_feedback_id):
		highlighted_ids.append(resource_feedback_id)
	highlighted_ids.sort()
	var selected_ids := player_control_state.selected_ids()
	var control_signature := hash([highlighted_ids, selected_ids])
	if cached_world_drawables_revision != presentation_revision or cached_world_drawables_control_signature != control_signature or not render_world.camera_cache_ready or ((cached_projection_offset != view_offset or cached_projection_zoom != view_zoom) and not render_world.can_refresh_camera()):
		var retained_snapshot := presentation_snapshot.duplicate()
		retained_snapshot["effects"] = []
		render_world.performance_probe = _presentation_probe()
		cached_world_drawables = render_world.create_world_drawables(retained_snapshot, Callable(self, "world_to_screen"), interpolation_alpha, Callable(self, "render_item_frame_info"), highlighted_ids, local_player_team, selected_ids, view_zoom, viewport)
		# The new queue already contains interpolated positions and current depth.
		# Refresh it only on later frames that reuse this publication.
		cached_rally_drawables = render_world.rally_drawables
		cached_world_drawables_revision = presentation_revision
		cached_world_drawables_control_signature = control_signature
	elif (cached_projection_offset != view_offset or cached_projection_zoom != view_zoom) and render_world.can_refresh_camera():
		cached_world_drawables = render_world.refresh_camera_drawables(Callable(self, "world_to_screen"), interpolation_alpha, view_zoom, viewport)
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
	var effect_drawables: Array = render_world.create_effect_drawables(effects, Callable(self, "world_to_screen"), Callable(self, "render_item_frame_info"))
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
	var ambient_time := float(presentation_snapshot.get("tick", 0)) * GameController.FIXED_STEP_SECONDS
	if animation_state == "idle" and String(unit.get("death_phase", "alive")) == "alive":
		var entity_id := int(unit.get("id", 0))
		var period := 7.0 + float(posmod(entity_id * 17, 61)) * 0.1
		var phase := fposmod(ambient_time + float(posmod(entity_id * 37, 100)) * 0.13, period)
		return resource_catalog.unit_frame_info(unit, animation_state, phase if phase < 0.8 else 0.0, ambient_time)
	return resource_catalog.unit_frame_info(unit, animation_state, -1.0, ambient_time)

func issue_order(mouse: Vector2, direction_end: Variant = null, queue_order: bool = false) -> void:
	command_actions.issue_order(self, mouse, direction_end, queue_order)


func issue_ground_order(target: Vector2, queue_order: bool = false) -> void:
	command_actions.issue_ground_order(self, target, queue_order)


func issue_martyrdom() -> void:
	command_actions.issue_martyrdom(self)


func issue_delete_context() -> void:
	command_actions.issue_delete_context(self)


func issue_unload_at_pointer(queue_order: bool = false) -> void:
	command_actions.issue_unload_at_pointer(self, queue_order)


func issue_unit_action(action_name: String) -> void:
	command_actions.issue_unit_action(self, action_name)


func repair_workers() -> Array:
	return command_actions.repair_workers(self)


func begin_repair() -> void:
	command_actions.begin_repair(self)


func cancel_pending_targeting() -> bool:
	return command_actions.cancel_pending_targeting(self)


func repair_target_at(screen_position: Vector2, workers: Array) -> Dictionary:
	return command_actions.repair_target_at(self, screen_position, workers)


func commit_repair_target(screen_position: Vector2) -> void:
	command_actions.commit_repair_target(self, screen_position)


func begin_attack_move() -> void:
	command_actions.begin_attack_move(self)


func begin_attack_ground() -> void:
	command_actions.begin_attack_ground(self)


func commit_pending_target(screen_position: Vector2, queue_order: bool = false) -> void:
	command_actions.commit_pending_target(self, screen_position, queue_order)


func stance_name(value: String) -> String:
	return command_actions.stance_name(self, value)


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
			if collection_name == "resources" and not PickingService.resource_is_selectable(entity):
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
		if not PickingService.resource_is_selectable(resource):
			continue
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
	command_actions.set_formation(self, value)
func formation_name() -> String:
	return command_actions.formation_name(self)

func request_primary_train_command() -> void:
	command_actions.request_primary_train_command(self)


func request_train_shortcut(unit_kind: String) -> void:
	command_actions.request_train_shortcut(self, unit_kind)


func begin_build_placement(building_kind: String) -> void:
	command_actions.begin_build_placement(self, building_kind)


func commit_build_placement(screen_position: Vector2, queue_order: bool = false, start_screen_position: Vector2 = Vector2.INF) -> void:
	command_actions.commit_build_placement(self, screen_position, queue_order, start_screen_position)


func queue_wall_line(workers: Array, cells: Array[Vector2i], queue_order: bool = false) -> void:
	command_actions.queue_wall_line(self, workers, cells, queue_order)


func train_unit_from_hud(unit_kind: String, building_id: int) -> void:
	command_actions.train_unit_from_hud(self, unit_kind, building_id)


func research_from_hud(technology_id: int, building_id: int) -> void:
	command_actions.research_from_hud(self, technology_id, building_id)


func cancel_production_from_hud(building_id: int, queue_index: int) -> void:
	command_actions.cancel_production_from_hud(self, building_id, queue_index)


func set_trade_resource_from_hud(resource_type_id: int) -> void:
	command_actions.set_trade_resource_from_hud(self, resource_type_id)


func refresh_hud_model() -> void:
	join_simulation_owner()
	formation = FormationSelection.selected_type(selected_units(), game_controller.formation_groups if game_controller != null else {})
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
		var probe: Variant = _presentation_probe()
		if probe != null:
			probe.increment("presentation.hud.skipped")
		return
	hud_model = update.get("model", {})
	if hud_controls != null:
		hud_controls.set_view_model(hud_model)
	if top_bar_controls != null:
		top_bar_controls.set_view_model(hud_model)


func sync_world_state(force: bool = true) -> void:
	join_simulation_owner()
	if simulation_world == null:
		return
	var probe: Variant = _presentation_probe()
	var current_tick := game_controller.tick_index if game_controller != null else 0
	var selected_ids := player_control_state.selected_ids()
	var selection_signature := hash(selected_ids)
	var required_view_bounds := visible_tile_bounds(8)
	if not force and not presentation_snapshot.is_empty() and current_tick == cached_presentation_tick and selection_signature == cached_presentation_selection_signature and diagnostics_enabled == cached_presentation_diagnostics and _tile_bounds_contains(cached_presentation_bounds, required_view_bounds):
		if probe != null:
			probe.increment("presentation.sync.skipped")
		return
	var sync_started := Time.get_ticks_usec() if probe != null else 0
	var stage_started := sync_started
	var requested_bounds := required_view_bounds
	# Keep the camera query stable within eight-tile windows while preserving
	# the full sprite margin on every side, including tall crowns/buildings.
	var query_start := Vector2i((Vector2(requested_bounds.position) / 8.0).floor()) * 8
	var query_end := Vector2i((Vector2(requested_bounds.end) / 8.0).ceil()) * 8
	var snapshot_bounds := Rect2i(query_start, query_end - query_start).intersection(Rect2i(Vector2i.ZERO, map_size))
	presentation_snapshot = render_snapshot_source.capture(simulation_world, current_tick, local_player_team, selected_ids, Rect2(Vector2(snapshot_bounds.position), Vector2(snapshot_bounds.size)), diagnostics_enabled, task_coordinator, probe)
	if probe != null:
		probe.observe_microseconds("presentation.sync.snapshot", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	cached_overview_tick = render_snapshot_source.overview_tick
	cached_overview_resource_revision = render_snapshot_source.resource_revision
	cached_presentation_tick = current_tick
	cached_presentation_bounds = snapshot_bounds
	cached_presentation_selection_signature = selection_signature
	cached_presentation_diagnostics = diagnostics_enabled
	presentation_revision += 1
	_sync_effect_snapshot()
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
	if not selected_ids.is_empty():
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
		_open_hud_modal(HUDModalOverlay.MODE_MENU)
		hud_modal_overlay.request_confirmation("restart")
	else:
		game_message = "Для новой сетевой игры вернитесь в лобби"


func _return_to_launcher() -> void:
	join_simulation_owner()
	if launcher_suspended:
		return
	if network_session != null or not network_role.is_empty():
		get_tree().auto_accept_quit = true
		if network_relay != null:
			network_relay.close()
		get_tree().change_scene_to_file("res://launcher.tscn")
		return
	launcher_restore_paused = modal_restore_paused if hud_modal_overlay != null and hud_modal_overlay.is_blocking() else game_controller.paused
	if hud_modal_overlay != null:
		hud_modal_overlay.close()
	game_controller.set_paused(true)
	launcher_suspended = true
	launcher_audio_states.clear()
	for player in [audio_player] + sfx_players:
		if is_instance_valid(player):
			launcher_audio_states.append({"player": player, "paused": player.stream_paused})
			player.stream_paused = true
	cancel_pending_targeting()
	input_adapter.reset()
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_CAN_DROP, Input.CURSOR_MOVE, Input.CURSOR_CROSS, Input.CURSOR_FORBIDDEN]:
		Input.set_custom_mouse_cursor(null, shape)
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	# Resolve at runtime: the launcher already preloads this game scene.
	var launcher = load("res://launcher.tscn").instantiate()
	launcher.active_game = self
	get_tree().root.add_child(launcher)
	get_tree().current_scene = launcher


func resume_from_launcher() -> void:
	join_simulation_owner()
	get_tree().auto_accept_quit = false
	if launcher_suspended:
		game_controller.set_paused(launcher_restore_paused)
		for state in launcher_audio_states:
			if is_instance_valid(state["player"]):
				state["player"].stream_paused = bool(state["paused"])
		launcher_audio_states.clear()
		launcher_suspended = false
	process_mode = Node.PROCESS_MODE_INHERIT
	show()
	input_adapter.reset()
	source_cursor_frame_applied = -1
	_install_source_control_cursors()
	_apply_source_cursor("default")
	queue_redraw()

func _exit_tree() -> void:
	join_simulation_owner()
	autosave.shutdown()
	PickingService.SelectionResolver.clear_hit_images()
	navigation_loading.shutdown()
	background_saves.shutdown()
	if resource_catalog != null:
		resource_catalog.unit_presentations.shutdown_loading()
	simulation_owner.shutdown()
	match_lifecycle.retire_runtime(simulation_world, ai_runtime, render_snapshot_source, ai_decision_queue, task_coordinator, false)
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
	preload("res://scripts/shoreline_presentation.gd").begin_frame(self)
	var probe: Variant = _presentation_probe()
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
	draw_rally_flags()
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
	if terrain_canvas != null and _render_terrain() != null:
		terrain_canvas.set_view_state(view_zoom, view_offset, get_viewport_rect().size, int(_render_terrain().terrain_revision))

func draw_formation_ghost() -> void:
	var gesture := input_adapter.formation_gesture()
	if gesture.is_empty():
		return
	var selected := selected_units()
	if selected.is_empty():
		return
	var destination := screen_to_world(gesture["position"])
	var direction_end := screen_to_world(gesture["direction_end"])
	var groups: Dictionary = owner_formation_groups if simulation_owner.pending else game_controller.formation_groups
	var preview := FormationPreview.build_selection(selected, groups, destination, direction_end - destination)
	if preview.is_empty():
		return
	for slot in preview["slots"]:
		draw_formation_ghost_slot(slot)
	# One heading for the entire placement gesture, including selections that
	# retain several old groups. Individual ghosts only show occupied slots.
	var heading: Array = preview["heading"]
	var arrow_points := PackedVector2Array()
	for point in heading:
		arrow_points.append(world_to_screen(point))
	draw_line(arrow_points[0], arrow_points[1], Color(1.0, 0.88, 0.25, 0.95), 2.0, true)
	draw_polyline(PackedVector2Array([arrow_points[2], arrow_points[1], arrow_points[3]]), Color(1.0, 0.88, 0.25, 0.95), 2.0, true)

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
			var drawable := TerrainRenderer.tile_drawable(cell, terrain_id, terrain_provider, resource_catalog, _render_terrain().terrain_elevation, view_zoom, view_offset, map_seed)
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
	if _render_terrain() != null:
		return _render_terrain().terrain_id_at_cell(cell)
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

var native_sprite_submission := true

func draw_world_objects() -> void:
	if render_world != null:
		var probe: Variant = _presentation_probe()
		var stage_started := Time.get_ticks_usec() if probe != null else 0
		var drawables := current_world_drawables()
		if probe != null:
			probe.observe_microseconds("presentation.draw.world_prepare", Time.get_ticks_usec() - stage_started)
			stage_started = Time.get_ticks_usec()
		var kernel: Variant = render_world.native_render_kernel
		var direct: bool = native_sprite_submission and kernel != null and kernel.has_method("submit_sprite_run")
		var index := 0
		while index < drawables.size():
			if direct and drawables[index].has("sprite_command"):
				var next: int = kernel.submit_sprite_run(get_canvas_item(), drawables, index)
				if next > index:
					index = next
					continue
			draw_world_item(drawables[index])
			index += 1
		if probe != null:
			probe.observe_microseconds("presentation.draw.world_submit", Time.get_ticks_usec() - stage_started)
	return


func draw_world_item(drawable: Dictionary) -> void:
	if drawable.has("sprite_command"):
		var command: Array = drawable["sprite_command"]
		draw_texture_rect(command[0], command[1], false, command[2])
		return
	match drawable["kind"]:
		"building", "building_part", "resource", "resource_shadow", "unit", "unit_part", "projectile", "effect", "marker", "environment": draw_render_body(drawable)
		"shadow": draw_unit_shadow(drawable)
		"selection": draw_unit_selection(drawable)
		"health_bar": draw_unit_health(drawable)


func draw_rally_flags() -> void:
	# A rally point is the player's own command, so its flag stays visible over fog.
	if presentation_snapshot.is_empty(): return
	for item in cached_rally_drawables:
		draw_render_body(item)


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
	join_simulation_owner()
	var center := Coordinates.clamp_world(screen_to_world(input_adapter.pointer_position).round(), map_size)
	if pending_build_kind == "wall":
		var start := Coordinates.clamp_world(screen_to_world(input_adapter.pointer.anchor).round(), map_size) if input_adapter.pointer.is_selecting() else center
		var key := str([start, center, local_player_team, game_controller.tick_index, simulation_world.navigation_grid.revision])
		if key != wall_placement_preview_key:
			wall_placement_preview_key = key
			wall_placement_preview = simulation_world.plan_wall_line(local_player_team, WallPlacement.cells(Vector2i(start), Vector2i(center)))
		var ghosts: Array = []
		for entry in wall_placement_preview.get("previews", []):
			draw_foundation_preview_at("wall", entry["position"], entry, false)
			var ghost: Dictionary = entry["ghost"].duplicate()
			ghost["id"] = -1 - ghosts.size()
			ghost["elevation"] = simulation_world.elevation_at(ghost["pos"])
			ghosts.append(ghost)
		var provider := func(_kind, data): return resource_catalog.building_frame_info(data, 0.0)
		for item in wall_preview_renderer.create_world_drawables({"buildings": ghosts}, Callable(self, "world_to_screen"), 1.0, provider):
			item["opacity"] = 0.55
			draw_render_body(item)
		return
	draw_foundation_preview_at(pending_build_kind, center)


func draw_foundation_preview_at(kind: String, center: Vector2, wall_entry: Dictionary = {}, draw_sprite: bool = true) -> void:
	join_simulation_owner()
	var key := "%s:%d:%d:%d:%d" % [kind, roundi(center.x), roundi(center.y), game_controller.tick_index, simulation_world.navigation_grid.revision]
	if wall_entry.is_empty() and key != placement_preview_key:
		placement_preview_key = key
		placement_preview_valid = simulation_world.can_place_foundation(local_player_team, kind, center, {"gate_axis": pending_gate_axis})
	var footprint := Footprint.building(simulation_world.building_placement_stats(kind, pending_gate_axis), center)
	var ghost := {"kind": kind, "team": local_player_team, "pos": center, "state": "foundation", "construction_stage": 0, "footprint": footprint}
	if kind == "gate":
		ghost["state"] = "complete"
		ghost["gate_axis"] = pending_gate_axis
		ghost["gate_open_fraction"] = 0.0
		ghost["components"] = {"ownership": {"civilization_id": int(simulation_world.civilization_by_team.get(local_player_team, 13))}}
		ghost["source_unit_id"] = simulation_world.technology_system.resolved_unit_id(local_player_team, 10072)
	if not wall_entry.is_empty():
		ghost = wall_entry["ghost"].duplicate()
		ghost["footprint"] = footprint
	var valid := bool(wall_entry.get("valid", placement_preview_valid))
	var color := Color(0.45, 0.95, 0.5, 0.75) if valid else Color(1.0, 0.3, 0.25, 0.75)
	var points := building_selection_outline(ghost)
	draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.16))
	draw_polyline(points, color, maxf(1.0, view_zoom), true)
	if not draw_sprite:
		return
	var frame_info := resource_catalog.building_frame_info(ghost, 0.0)
	var layers: Array = [frame_info]
	layers.append_array(frame_info.get("composite_parts", []))
	layers.sort_custom(func(a, b): return int(a.get("graphic_layer", 20)) < int(b.get("graphic_layer", 20)))
	for layer in layers:
		if layer.has("gate_polygon"):
			draw_render_body({"frame_info": layer, "screen_position": world_to_screen(center), "opacity": 0.55})
			continue
		var texture: Texture2D = layer.get("texture")
		if texture == null:
			continue
		var offset: Vector2 = layer.get("screen_offset", Vector2.ZERO)
		draw_anchored_texture(texture, String(layer.get("asset_name", "")), int(layer.get("frame_index", 0)), PixelScaling.snap_screen(world_to_screen(center) + offset * view_zoom), view_zoom, bool(layer.get("mirrored", false)), 0.55, layer.get("hotspot"))


func _terrain_geometry_revision() -> int:
	return fog_renderer._terrain_geometry_revision(self)


func _sync_fog_geometry_revision() -> void:
	fog_renderer._sync_fog_geometry_revision(self)


func draw_fog_overlay() -> void:
	fog_renderer.draw_fog_overlay(self)


func _world_fog_geometry_chunk_bounds(chunk_key: Vector2i) -> Rect2i:
	return fog_renderer._world_fog_geometry_chunk_bounds(self, chunk_key)


func _prune_world_fog_geometry_cache(retained_bounds: Rect2i) -> int:
	return fog_renderer._prune_world_fog_geometry_cache(self, retained_bounds)


func _build_world_fog_mesh(bounds: Rect2i) -> ArrayMesh:
	return fog_renderer._build_world_fog_mesh(self, bounds)


func _sync_world_fog_texture(cells: Variant, fog_revision: int, probe: Variant = null) -> void:
	fog_renderer._sync_world_fog_texture(self, cells, fog_revision, probe)

func _write_world_fog_pixel(index: int, cells: Variant) -> void:
	fog_renderer._write_world_fog_pixel(self, index, cells)


func _world_to_fog_mesh(world: Vector2) -> Vector2:
	return fog_renderer._world_to_fog_mesh(self, world)


func _fog_cell_should_cover(cell: Vector2i, cells: Variant) -> bool:
	return fog_renderer._fog_cell_should_cover(self, cell, cells)


func _fog_cell_touches_visible(cell: Vector2i, cells: Variant) -> bool:
	return fog_renderer._fog_cell_touches_visible(self, cell, cells)


func _fog_state_at_cell(cells: Variant, cell: Vector2i) -> int:
	return fog_renderer._fog_state_at_cell(self, cells, cell)


func _ensure_fog_slope_neighbor_cache() -> void:
	fog_renderer._ensure_fog_slope_neighbor_cache(self)


func _expanded_tile_bounds(bounds: Rect2i, margin: int) -> Rect2i:
	return fog_renderer._expanded_tile_bounds(self, bounds, margin)


func _tile_bounds_contains(outer: Rect2i, inner: Rect2i) -> bool:
	return fog_renderer._tile_bounds_contains(self, outer, inner)


func draw_map_edge_guard() -> void:
	fog_renderer.draw_map_edge_guard(self)

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
			return resource_catalog.building_frame_info(data, animation_time, true)
		"projectile":
			return resource_catalog.projectile_frame_info(data)
		"effect":
			return resource_catalog.effect_frame_info(data)
		"rally_flag":
			var animation_time := float(presentation_snapshot.get("tick", 0)) * GameController.FIXED_STEP_SECONDS
			return resource_catalog.rally_flag_frame_info(int(data.get("team", 1)), animation_time)
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
	if frame_info.has("shore_geometry"):
		preload("res://scripts/shoreline_presentation.gd").draw(self,frame_info,item["screen_position"],view_zoom,float(item.get("opacity",1.0)))
		return
	if frame_info.has("river_geometry"):
		preload("res://scripts/river_feature_presentation.gd").draw(self,frame_info,item["screen_position"],view_zoom,float(item.get("opacity",1.0)))
		return
	if frame_info.has("gate_polygon"):
		var gate_screen := PixelScaling.snap_screen(item["screen_position"])
		draw_set_transform(gate_screen, 0, Vector2.ONE * view_zoom)
		var gate_color: Color = frame_info.get("gate_color", Color.WHITE)
		gate_color.a *= float(item.get("opacity", 1.0))
		draw_polygon(frame_info["gate_polygon"], PackedColorArray([gate_color]), frame_info.get("gate_uv", PackedVector2Array()), frame_info.get("texture"))
		draw_set_transform(Vector2.ZERO)
		return
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
	var fill := Color("747f81") if owner <= 0 else resource_catalog.player_palette.color_for_team(owner)
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
	if resource_feedback_time > 0.0 and unit.get("selection_member_ids", [int(unit.get("id", -1))]).has(resource_feedback_id):
		if int(resource_feedback_time * 10.0) % 2 == 0:
			if String(unit.get("entity_type", "")) in ["building", "foundation"] or String(unit.get("footprint", {}).get("shape", "")) == "polygon":
				draw_building_selection_rectangle(unit, Color("ffe56c"))
			else:
				draw_selection_ellipse(unit_selection_center(item), Color("ffe56c"), unit_selection_radius(unit))
		return
	var screen := unit_selection_center(item)
	var is_building := String(unit.get("entity_type", "")) in ["building", "foundation"] or String(unit.get("footprint", {}).get("shape", "")) == "polygon"
	var radius := unit_selection_radius(unit)
	var members: Array = unit.get("selection_member_ids", [int(unit["id"])])
	var previewed := members.any(func(id): return selection_preview_ids.has(int(id)))
	var hovered := members.has(interaction_highlight_id)
	var selected := members.any(func(id): return player_control_state.is_selected(int(id)))
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


func unit_selection_radius(entity: Dictionary) -> Vector2:
	if entity.has("selection_members"):
		var geometry := FishShoalSelection.geometry(entity, Callable(self, "world_to_screen"), view_zoom)
		return Vector2(geometry["radius"]) / maxf(0.001, view_zoom)
	var footprint: Dictionary = entity.get("footprint", {})
	var half_size: Variant = footprint.get("half_size")
	if half_size is Vector2:
		var span: float = half_size.x + half_size.y
		return Vector2(maxf(15.0, span * 17.0), maxf(6.5, span * 8.5))
	if String(entity.get("entity_type", "")) == "resource":
		# DAT selection radii are world-space extents, independent of obstruction.
		# A sea shoal is one tile wide; shore fish have a much smaller footprint.
		var selection: Variant = entity.get("selection_radius", footprint.get("selection_radius", 0.0))
		var extent: float = maxf(selection.x, selection.y) if selection is Vector2 else float(selection)
		return Vector2(maxf(15.0, extent * 32.0), maxf(6.5, extent * 16.0))
	return Vector2(15.0, 6.5)


func unit_selection_center(item: Dictionary) -> Vector2:
	var entity: Dictionary = item.get("data", {})
	if entity.has("selection_members"):
		return PixelScaling.snap_screen(FishShoalSelection.geometry(entity, Callable(self, "world_to_screen"), view_zoom)["center"])
	# Render-item screen_position is the object's ground anchor. Adding another
	# sprite-height offset detached ship/resource rings from the water or ground.
	return PixelScaling.snap_screen(Vector2(item.get("screen_position", Vector2.ZERO)))


func draw_building_selection_rectangle(building: Dictionary, color: Color) -> void:
	draw_polyline(building_selection_outline(building), color, maxf(1.0, view_zoom), true)


func building_selection_outline(building: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in WallPlacement.selection_polygon(building):
		points.append(PixelScaling.snap_screen(world_to_screen(point)))
	if not points.is_empty():
		points.append(points[0])
	return points


func building_selection_rectangle(building: Dictionary) -> Rect2:
	var corners := WallPlacement.selection_polygon(building)
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
	minimap_renderer.draw_minimap(self, rectangle)


func _build_minimap_mesh(center: Vector2, scale: float) -> ArrayMesh:
	return minimap_renderer._build_minimap_mesh(self, center, scale)


func _minimap_resource_pixels(center: Vector2, scale: float, rectangle: Rect2) -> Array[Vector2]:
	return minimap_renderer._minimap_resource_pixels(self, center, scale, rectangle)


func _append_colored_quad(vertices: PackedVector3Array, colors: PackedColorArray, points: PackedVector2Array, color: Color) -> void:
	minimap_renderer._append_colored_quad(self, vertices, colors, points, color)


func _append_colored_circle(vertices: PackedVector3Array, colors: PackedColorArray, center: Vector2, radius: float, color: Color) -> void:
	minimap_renderer._append_colored_circle(self, vertices, colors, center, radius, color)

func minimap_position(world: Vector2, center: Vector2, scale: float) -> Vector2:
	return minimap_renderer.minimap_position(self, world, center, scale)


func fog_runs() -> Array:
	return fog_renderer.fog_runs(self)


var visible_corner_key: Array = []
var visible_world_corners: Array[Vector2] = []

func visible_tile_bounds(margin: int = 4) -> Rect2i:
	var viewport_size := get_viewport_rect().size
	var elevation: Variant = _render_terrain().terrain_elevation if _render_terrain() != null else null
	var key := [elevation, elevation.revision if elevation != null else -1, elevation.cache_epoch if elevation != null else -1, map_size, view_offset, view_zoom, viewport_size]
	if visible_corner_key != key:
		visible_corner_key = key
		visible_world_corners = [
			screen_to_world(Vector2(0, hud_top_height())),
			screen_to_world(Vector2(viewport_size.x, hud_top_height())),
			screen_to_world(Vector2(viewport_size.x, viewport_size.y - hud_bottom_height())),
			screen_to_world(Vector2(0, viewport_size.y - hud_bottom_height())),
		]
	return ViewportCulling.tile_bounds(map_size, visible_world_corners, margin)


func minimap_rectangle() -> Rect2:
	return minimap_renderer.minimap_rectangle(self)


func minimap_geometry(rectangle: Rect2 = Rect2()) -> Dictionary:
	return minimap_renderer.minimap_geometry(self, rectangle)


func hud_top_height() -> float:
	return 64.0 if get_viewport_rect().size.x < 720.0 else 32.0


func hud_bottom_height() -> float:
	return 252.0 if get_viewport_rect().size.x < 720.0 else 126.0


func select_hud_building(building_id: int) -> void:
	command_actions.select_hud_building(self, building_id)


func draw_map_edge_fog_overlay() -> void:
	fog_renderer.draw_map_edge_fog_overlay(self)


func _reset_command_feedback() -> void:
	input_adapter.reset()
	command_feedback_router.reset()
	command_feedback_router.event_cursor = game_controller.event_stream.latest_sequence()
	game_controller.event_stream.prune_through(command_feedback_router.event_cursor)
	presentation_effect_timeline.reset()


func _reset_world_fog_cache() -> void:
	fog_renderer._reset_world_fog_cache(self)


func _reset_minimap_fog_cache() -> void:
	minimap_renderer._reset_minimap_fog_cache(self)


func _reset_overview_cache() -> void:
	cached_overview_tick = -1
	cached_overview_resource_revision = -1
	cached_hud_signature = null
