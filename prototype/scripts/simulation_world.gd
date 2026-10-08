class_name RoRSimulationWorld
const BuildSiteTask := preload("res://scripts/build_site_task.gd")
const TaskData := preload("res://scripts/isolated_task_data.gd")
const TaskCoordinator := preload("res://scripts/isolated_task_coordinator.gd")
var task_coordinator := TaskCoordinator.new()

const Coordinates := preload("res://scripts/coordinates.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const EntityIds := preload("res://scripts/entity_id.gd")
const SpatialHash := preload("res://scripts/spatial_hash.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")
const Footprint := preload("res://scripts/footprint.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const NavigationService := preload("res://scripts/navigation_service.gd")
const LocalMovement := preload("res://scripts/local_movement.gd")
const DestinationReservations := preload("res://scripts/destination_reservations.gd")
const StuckRecovery := preload("res://scripts/stuck_recovery.gd")
const FormationCohesion := preload("res://scripts/formation_cohesion.gd")
const FormationCombat := preload("res://scripts/formation_combat.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const ChangeJournal := preload("res://scripts/cell_change_journal.gd")
const CacheDependency := preload("res://scripts/cache_dependency.gd")
const EntityReadContract := preload("res://scripts/entity_read_contract.gd")
const ResourcePublication := preload("res://scripts/immutable_resource_publication.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const CombatRules := preload("res://scripts/combat_rules.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const SimulationVisibilitySystem := preload("res://scripts/simulation_visibility_system.gd")
const RenderEntityProjectionCache := preload("res://scripts/render_entity_projection_cache.gd")
const SimulationGatheringSystem := preload("res://scripts/simulation_gathering_system.gd")
const SimulationConstructionSystem := preload("res://scripts/simulation_construction_system.gd")
const SimulationBuildingPlacementSystem := preload("res://scripts/simulation_building_placement_system.gd")
const SimulationFoundationSystem := preload("res://scripts/simulation_foundation_system.gd")
const SimulationMovementSystem := preload("res://scripts/simulation_movement_system.gd")
const SimulationDeathSystem := preload("res://scripts/simulation_death_system.gd")
const SimulationApproachSystem := preload("res://scripts/simulation_approach_system.gd")
const SimulationEntityFactory := preload("res://scripts/simulation_entity_factory.gd")

const GATHER_UPDATE_IDLE := SimulationGatheringSystem.GATHER_UPDATE_IDLE
const GATHER_UPDATE_MOVE := SimulationGatheringSystem.GATHER_UPDATE_MOVE
const GATHER_UPDATE_ACTION := SimulationGatheringSystem.GATHER_UPDATE_ACTION
const GATHER_UPDATE_CARRY_IDLE := SimulationGatheringSystem.GATHER_UPDATE_CARRY_IDLE
const GATHER_UPDATE_CARRY_MOVE := SimulationGatheringSystem.GATHER_UPDATE_CARRY_MOVE
const GATHER_UPDATE_MOVE_IDLE := SimulationGatheringSystem.GATHER_UPDATE_MOVE_IDLE
const SimulationEconomySystem := preload("res://scripts/simulation_economy_system.gd")
const SimulationProductionSystem := preload("res://scripts/simulation_production_system.gd")
const SimulationCombatSystem := preload("res://scripts/simulation_combat_system.gd")
const AiDistressSystem := preload("res://scripts/ai_distress_system.gd")
const WorkerRoleSystem := preload("res://scripts/worker_role_system.gd")
const ConversionSystem := preload("res://scripts/conversion_system.gd")
const HealingSystem := preload("res://scripts/healing_system.gd")
const TransportSystem := preload("res://scripts/transport_system.gd")
const TradeSystem := preload("res://scripts/trade_system.gd")
const DataRepository := preload("res://scripts/ror_data_repository.gd")
const TechnologySystem := preload("res://scripts/technology_system.gd")
const VictorySystem := preload("res://scripts/victory_system.gd")
const ScenarioSystem := preload("res://scripts/scenario_system.gd")
const PlayerRegistry := preload("res://scripts/player_registry.gd")
const SimulationTickPipeline := preload("res://scripts/simulation_tick_pipeline.gd")
const AiNavigationKnowledge := preload("res://scripts/ai_navigation_knowledge.gd")
const SimulationActivityRegistry := preload("res://scripts/simulation_activity_registry.gd")
const SimulationSpatialSyncSystem := preload("res://scripts/simulation_spatial_sync_system.gd")

var map_size: Vector2i = Vector2i(24, 24)
var map_terrain_ids: Dictionary = {}
var map_reserved_foundation_cells: Dictionary = {}
var forest_resource_counts: Dictionary = {}
const MAX_TERRAIN_CHANGE_HISTORY := 256
var cache_epoch := 0
var terrain_revision: int = 0
var terrain_change_history: Array = []
var units: Array = []
var units_by_id: Dictionary = {}
var unit_activity_registry := SimulationActivityRegistry.new()
var capturable_units: Array[Dictionary] = []
var dying_units: Array[Dictionary] = []
var dying_buildings: Array[Dictionary] = []
var unit_removal_pending: bool = false
var building_removal_pending: bool = false
var resource_nodes: Array = []
var resource_nodes_by_id: Dictionary = {}
var resource_nodes_by_cell: Dictionary = {}
var decaying_resource_nodes: Array = []
# Only actively falling trees are visited by the fixed-tick lifecycle pass.
var falling_resource_nodes: Array = []
var known_resources_by_player: Dictionary = {}
var ai_navigation_knowledge = AiNavigationKnowledge.new()
var known_ai_resources_by_player: Dictionary = {}
const RESOURCE_MEMORY_CHUNK_SIZE := 8
const MAX_MINIMAP_RESOURCE_CHANGES := 4096
var last_known_buildings_by_player: Dictionary = {}
var local_build_site_cache: Dictionary = {}
const MAX_LOCAL_BUILD_SITE_CACHE_ENTRIES := 64
var build_option_catalog_cache: Dictionary = {}
var render_entity_projection_cache := RenderEntityProjectionCache.new()
var static_obstructions: Array = []
var buildings: Array = []
var buildings_by_id: Dictionary = {}
# Monotonic invalidation token for systems that retain live entity capability
# rosters. Entity count alone is not enough because combat roles and archetype
# tags can change in place.
var combat_roster_revision: int = 0
var projectiles: Array = []
var resolved_projectiles: Array = []
var movement_neighbor_query_microseconds: int = 0
var movement_local_calculation_microseconds: int = 0
var movement_integration_microseconds: int = 0
var movement_arrival_microseconds: int = 0
var movement_native_unit_updates: int = 0
var movement_native_neighbor_candidates: int = 0
var formation_cohesion_active: bool = true
var movement_neighbor_buffer: Array = []
var open_movement_envelopes_by_id: Dictionary = {}
var building_navigation_cells_by_id: Dictionary = {}

var entity_id_sequence := EntityIds.new()
var spatial_index := SpatialHash.new(2.0)
var spatial_sync_system := SimulationSpatialSyncSystem.new()
var formation_groups_view: Dictionary = {}
var navigation_grid: NavigationGrid
var pathfinder
var navigation_service: NavigationService
var destination_reservations := DestinationReservations.new()
var terrain_elevation: TerrainElevation
# Compatibility alias for canonical snapshots and old tests. New code uses
# visibility_system through the SimulationWorld query facade.
var fog_of_war: FogOfWar
var visibility_system: SimulationVisibilitySystem
var economy_system: SimulationEconomySystem
var production_system: SimulationProductionSystem
var combat_system: SimulationCombatSystem
var gathering_system: SimulationGatheringSystem
var construction_system: SimulationConstructionSystem
var building_placement_system: SimulationBuildingPlacementSystem
var foundation_system: SimulationFoundationSystem
var movement_system: SimulationMovementSystem
var death_system: SimulationDeathSystem
var approach_system: SimulationApproachSystem
var entity_factory: SimulationEntityFactory
var ai_distress_system := AiDistressSystem.new()
var worker_role_system: WorkerRoleSystem
var conversion_system: ConversionSystem
var healing_system: HealingSystem
var transport_system: TransportSystem
var trade_system: TradeSystem
var data_repository := DataRepository.new()
var technology_system := TechnologySystem.new()
var victory_system := VictorySystem.new()
var scenario_system := ScenarioSystem.new()
var player_registry := PlayerRegistry.new()
var simulation_seed: int = 1337
var simulation_rng := RandomNumberGenerator.new()
var tick_pipeline := SimulationTickPipeline.new()
var capture_domain_events: bool = false
var pending_domain_events: Array[Dictionary] = []
var bulk_load_depth: int = 0

var gamespec_data: Dictionary = {}
var object_catalog_data: Dictionary = {}
var graphics_catalog_data: Dictionary = {}
var attack_animation_spec_cache: Dictionary = {}
var capture_radius_by_kind: Dictionary = {}
var civilization_by_team: Dictionary = {1: 13, 2: 13}
var full_tech_tree_enabled := false
var population_by_team: Dictionary = {}
var population_reserved_by_team: Dictionary = {}
var population_cap_by_team: Dictionary = {}
var resource_approach_slots: Dictionary = {}
var building_approach_slots: Dictionary = {}
var last_build_failure: String = ""
var last_production_failure: String:
	get: return production_system.last_production_failure if production_system != null else ""
	set(value):
		if production_system != null: production_system.last_production_failure = value
var last_research_failure: String:
	get: return production_system.last_research_failure if production_system != null else ""
	set(value):
		if production_system != null: production_system.last_research_failure = value
var last_research_message: String:
	get: return production_system.last_research_message if production_system != null else ""
	set(value):
		if production_system != null: production_system.last_research_message = value
var last_completed_research_id: int:
	get: return production_system.last_completed_research_id if production_system != null else -1
	set(value):
		if production_system != null: production_system.last_completed_research_id = value
var next_production_order_id: int:
	get: return production_system.next_order_id if production_system != null else 1
	set(value):
		if production_system != null: production_system.next_order_id = value
var resource_stockpiles_by_team: Dictionary = {}
var victory_objectives: Array = []
var capturable_victory_objectives: Array[Dictionary] = []
var conquest_counts_by_team: Dictionary = {}
var conquest_tracked_by_id: Dictionary = {}
var score_by_team: Dictionary = {}

var food: int:
	get:
		return economy_system.get_resource_amount(1, 0) if economy_system != null else 180
	set(value):
		if economy_system != null:
			economy_system.set_resource_amount(1, 0, value)
var wood: int:
	get:
		return economy_system.get_resource_amount(1, 1) if economy_system != null else 120
	set(value):
		if economy_system != null:
			economy_system.set_resource_amount(1, 1, value)
var kills: int = 0
var battle_over: bool = false
var battle_message: String = ""

func _init(world_size: Vector2i = Vector2i(24, 24)) -> void:
	map_size = Vector2i(world_size.x, world_size.y)
	terrain_elevation = TerrainElevation.new(map_size)
	economy_system = SimulationEconomySystem.new()
	economy_system.reset()
	production_system = SimulationProductionSystem.new(self)
	combat_system = SimulationCombatSystem.new(self)
	gathering_system = SimulationGatheringSystem.new(self)
	construction_system = SimulationConstructionSystem.new(self)
	building_placement_system = SimulationBuildingPlacementSystem.new(self)
	foundation_system = SimulationFoundationSystem.new(self)
	movement_system = SimulationMovementSystem.new(self)
	death_system = SimulationDeathSystem.new(self)
	approach_system = SimulationApproachSystem.new(self)
	entity_factory = SimulationEntityFactory.new(self)
	worker_role_system = WorkerRoleSystem.new(self)
	conversion_system = ConversionSystem.new(self)
	healing_system = HealingSystem.new(self)
	transport_system = TransportSystem.new(self)
	trade_system = TradeSystem.new(self)
	projectiles = combat_system.projectiles
	resolved_projectiles = combat_system.resolved_projectiles
	population_by_team = economy_system.population_by_team
	population_reserved_by_team = economy_system.population_reserved_by_team
	population_cap_by_team = economy_system.population_cap_by_team
	resource_stockpiles_by_team = economy_system.resource_stockpiles_by_team
	visibility_system = SimulationVisibilitySystem.new(map_size, Callable(self, "get_units"), Callable(self, "get_buildings"))
	fog_of_war = visibility_system.get_fog()
	navigation_grid = NavigationGrid.new(map_size)
	navigation_grid.configure_elevation(Callable(self, "terrain_profile_at"))
	pathfinder = Pathfinder.new(navigation_grid)
	navigation_service = NavigationService.new(pathfinder)
	simulation_rng.seed = simulation_seed
	_configure_tick_pipeline()


func set_simulation_seed(value: int) -> void:
	simulation_seed = value
	simulation_rng.seed = simulation_seed


func set_performance_probe(probe: Variant) -> void:
	tick_pipeline.set_performance_probe(probe)
	pathfinder.set_performance_probe(probe)
	visibility_system.set_performance_probe(probe)

func set_gamespec(data: Dictionary) -> void:
	local_build_site_cache.clear()
	building_placement_system.invalidate_site_cache()
	gamespec_data = data
	data_repository.configure_compatibility_gamespec(data)
	production_system.invalidate_option_catalogs()
	attack_animation_spec_cache.clear()


func set_terrain_catalog(data: Dictionary) -> void:
	navigation_grid.configure_restrictions(data.get("restrictions", []))
	navigation_grid.configure_terrain_ids(Callable(self, "terrain_id_at_cell"))
	pathfinder.clear_cache()
	navigation_service.clear_observations()


func set_object_catalog(data: Dictionary) -> void:
	local_build_site_cache.clear()
	building_placement_system.invalidate_site_cache()
	object_catalog_data = data
	data_repository.configure_objects(data)
	production_system.invalidate_option_catalogs()
	technology_system.configure(data)
	attack_animation_spec_cache.clear()
	for team in civilization_by_team.keys():
		initialize_team_rules(int(team))


func set_graphics_catalog(data: Dictionary) -> void:
	graphics_catalog_data = data
	attack_animation_spec_cache.clear()


func set_runtime_catalog(data: Dictionary) -> void:
	local_build_site_cache.clear()
	building_placement_system.invalidate_site_cache()
	data_repository.configure_runtime(data)
	production_system.invalidate_option_catalogs()
	attack_animation_spec_cache.clear()
	var trade_policy: Dictionary = data_repository.runtime_metadata("trade_boat").get("trade", {})
	for team in civilization_by_team.keys():
		trade_system.initialize_team(int(team), trade_policy)


func set_team_civilization(team: int, civilization_id: int) -> void:
	player_registry.set_civilization(team, civilization_id)
	civilization_by_team[team] = civilization_id
	technology_system.set_team_civilization(team, civilization_id)
	attack_animation_spec_cache.clear()
	trade_system.initialize_team(team, data_repository.runtime_metadata("trade_boat").get("trade", {}))
	if not object_catalog_data.is_empty():
		technology_system.reset_team(team)
		initialize_team_rules(team)


func set_alliance(first_team: int, second_team: int, allied: bool = true) -> void:
	player_registry.set_mutual_relation(first_team, second_team, "ally" if allied else "enemy")
	visibility_system.set_alliance(first_team, second_team, allied)
	_sync_shared_vision(first_team)
	_sync_shared_vision(second_team)
	if allied:
		_reveal_allied_town_centers(first_team, second_team)
		_reveal_allied_town_centers(second_team, first_team)
	if not allied:
		for transport in units:
			if transport_system.is_transport(transport) and int(transport.get("team", 0)) in [first_team, second_team]:
				transport_system.reconcile_ownership(transport)
	if not is_bulk_loading():
		update_fog_of_war()


func set_diplomacy_relation(source_team: int, target_team: int, relation: String) -> bool:
	if source_team <= 0 or target_team <= 0 or source_team == target_team:
		return false
	if not player_registry.players.has(source_team) or not player_registry.players.has(target_team):
		return false
	if relation not in PlayerRegistry.VALID_RELATIONS:
		return false
	player_registry.set_relation(source_team, target_team, relation)
	visibility_system.set_relation(source_team, target_team, relation == PlayerRegistry.ALLY)
	_sync_shared_vision(source_team)
	if relation == PlayerRegistry.ALLY:
		_reveal_allied_town_centers(source_team, target_team)
	if relation != PlayerRegistry.ALLY:
		for transport in units:
			if transport_system.is_transport(transport) and int(transport.get("team", 0)) in [source_team, target_team]:
				transport_system.reconcile_ownership(transport)
	if not is_bulk_loading():
		update_fog_of_war()
		_emit_domain_event("diplomacy_changed", {"source_team": source_team, "target_team": target_team, "relation": relation})
	return true


func _sync_shared_vision(observer_team: int) -> void:
	if observer_team <= 0:
		return
	for source_team_value in player_registry.all_teams():
		var source_team := int(source_team_value)
		if source_team > 0 and source_team != observer_team:
			visibility_system.set_shared_vision(observer_team, source_team, are_teams_allied(observer_team, source_team) and technology_system.grants_shared_vision(observer_team))


func _reveal_allied_town_centers(observer_team: int, ally_team: int) -> void:
	if observer_team <= 0 or ally_team <= 0:
		return
	var memory: Dictionary = last_known_buildings_by_player.get(observer_team, {})
	for building_value in buildings:
		var building: Dictionary = building_value
		if int(building.get("team", 0)) != ally_team or String(building.get("kind", "")) != "town_center" or float(building.get("hp", 0.0)) <= 0.0:
			continue
		var position := Vector2(building.get("pos", Vector2.ZERO))
		fog_of_war.reveal_explored_cell(observer_team, Vector2i(floori(position.x), floori(position.y)))
		if memory.has(int(building.get("id", -1))):
			continue
		memory[int(building.get("id", -1))] = {
			"id": int(building.get("id", -1)),
			"team": ally_team,
			"kind": "town_center",
			"entity_type": "building",
			"pos": position,
			"hp": 1.0,
			"max_hp": 1.0,
			"health_unknown": true,
			"location_only": true,
		}
	last_known_buildings_by_player[observer_team] = memory


func reveal_allied_town_centers(observer_team: int, ally_team: int) -> void:
	_reveal_allied_town_centers(observer_team, ally_team)


func restore_last_known_buildings(encoded: Dictionary) -> void:
	# Save archives stringify dictionary keys; runtime lookups use integer team and entity IDs.
	last_known_buildings_by_player.clear()
	for observer_key in encoded:
		var observer_team := int(observer_key)
		if observer_team <= 0 or not encoded[observer_key] is Dictionary:
			continue
		var restored: Dictionary = {}
		var records: Dictionary = encoded[observer_key]
		for entity_key in records:
			if records[entity_key] is Dictionary:
				restored[int(entity_key)] = records[entity_key].duplicate(true)
		last_known_buildings_by_player[observer_team] = restored


func configure_players(definitions: Array) -> void:
	player_registry.configure(definitions)
	civilization_by_team.clear()
	for player_value in definitions:
		var player: Dictionary = player_value
		var team := int(player.get("team", 0))
		if team > 0:
			civilization_by_team[team] = int(player.get("civilization_id", 13))
			trade_system.initialize_team(team, data_repository.runtime_metadata("trade_boat").get("trade", {}))

func reset_game(include_legacy_default: bool = true, preserve_bulk_load: bool = false) -> void:
	task_coordinator.shutdown()
	if not preserve_bulk_load:
		bulk_load_depth = 0
	units.clear()
	units_by_id.clear()
	unit_activity_registry.clear()
	capturable_units.clear()
	dying_units.clear()
	dying_buildings.clear()
	unit_removal_pending = false
	building_removal_pending = false
	resource_nodes.clear()
	resource_nodes_by_id.clear()
	resource_nodes_by_cell.clear()
	decaying_resource_nodes.clear()
	falling_resource_nodes.clear()
	known_resources_by_player.clear()
	ai_navigation_knowledge.clear()
	last_known_buildings_by_player.clear()
	known_ai_resources_by_player.clear()
	local_build_site_cache.clear()
	build_option_catalog_cache.clear()
	render_entity_projection_cache.clear()
	capture_radius_by_kind.clear()
	static_obstructions.clear()
	movement_system.knowledge.clear()
	forest_resource_counts.clear()
	buildings.clear()
	buildings_by_id.clear()
	mark_combat_roster_dirty()
	combat_system.reset()
	ai_distress_system.reset()
	pending_domain_events.clear()
	capture_domain_events = false
	entity_id_sequence.reset(1)
	spatial_index.clear()
	spatial_sync_system.reset()
	simulation_rng.seed = simulation_seed
	economy_system.reset()
	kills = 0
	battle_over = false
	battle_message = ""
	resource_approach_slots.clear()
	building_approach_slots.clear()
	open_movement_envelopes_by_id.clear()
	building_navigation_cells_by_id.clear()
	last_build_failure = ""
	production_system.reset()
	transport_system.reset()
	trade_system.reset()
	victory_objectives.clear()
	capturable_victory_objectives.clear()
	conquest_counts_by_team.clear()
	conquest_tracked_by_id.clear()
	score_by_team.clear()
	victory_system.reset()
	player_registry.reset_match()
	technology_system.reset()
	for team in civilization_by_team.keys():
		trade_system.initialize_team(int(team), data_repository.runtime_metadata("trade_boat").get("trade", {}))
		apply_civilization_starting_resources(int(team))
		initialize_team_rules(int(team))
	visibility_system.reset()
	pathfinder.clear_cache()
	navigation_service.reset()
	destination_reservations.clear()
	if include_legacy_default:
		add_building(0, "town_center", Coordinates.clamp_world(Vector2(12.0, 12.0), map_size), 0)


func begin_bulk_load() -> void:
	bulk_load_depth += 1


func end_bulk_load() -> void:
	if bulk_load_depth <= 0:
		push_error("end_bulk_load called without matching begin_bulk_load")
		return
	bulk_load_depth -= 1
	if bulk_load_depth > 0:
		return
	refresh_building_connectivity()
	rebuild_spatial_index()
	pathfinder.prepare_native_kernels_for_units(units)
	update_fog_of_war()


func is_bulk_loading() -> bool:
	return bulk_load_depth > 0



func _record_terrain_change(cell: Vector2i = Vector2i(-1, -1)) -> void:
	if cell.x < 0 or cell.y < 0:
		ChangeJournal.record_full(terrain_change_history, terrain_revision, terrain_revision + 1, MAX_TERRAIN_CHANGE_HISTORY)
	else:
		ChangeJournal.record_cell(terrain_change_history, terrain_revision, cell, MAX_TERRAIN_CHANGE_HISTORY)
	terrain_revision += 1

func terrain_changed_cells_since(previous_revision: int) -> Variant:
	var change := cache_changes(CacheDependency.TERRAIN_SURFACE, previous_revision)
	return change["cells"] if not bool(change["full"]) and bool(change["exact"]) else null


func cache_stamp(domain: String, observer_team: int = 0) -> Dictionary:
	return CacheDependency.stamp(self, domain, observer_team)


func cache_changes(domain: String, previous: Variant, observer_team: int = 0) -> Dictionary:
	return CacheDependency.changes(self, domain, previous, observer_team)

func configure_map_data(map_data: Dictionary) -> void:
	_record_terrain_change()
	map_terrain_ids.clear()
	map_reserved_foundation_cells.clear()
	for cell_value in map_data.get("reserved_foundation_cells", []):
		map_reserved_foundation_cells[Vector2i(cell_value)] = true
	var terrain_ids: Array = map_data.get("terrain_ids", [])
	for y in range(map_size.y):
		for x in range(map_size.x):
			var index := y * map_size.x + x
			if index < terrain_ids.size():
				map_terrain_ids[Vector2i(x, y)] = int(terrain_ids[index])
	terrain_elevation.clear()
	var vertex_levels: Array = map_data.get("vertex_levels", [])
	var vertex_width := map_size.x + 1
	for y in range(map_size.y + 1):
		for x in range(map_size.x + 1):
			var index := y * vertex_width + x
			if index < vertex_levels.size():
				terrain_elevation.set_vertex(Vector2i(x, y), int(vertex_levels[index]))
	navigation_grid.configure_terrain(Callable(self, "terrain_kind_at_cell"))
	navigation_grid.configure_terrain_ids(Callable(self, "terrain_id_at_cell"))
	navigation_grid.configure_elevation(Callable(self, "terrain_profile_at"))
	pathfinder.clear_cache()
	navigation_service.clear_observations()
	sync_entity_elevations()
	if not is_bulk_loading():
		rebuild_navigation_grid()


func configure_static_obstructions(obstructions: Array) -> void:
	static_obstructions = obstructions.duplicate(true)
	if not is_bulk_loading():
		rebuild_navigation_grid()


func begin_event_capture() -> void:
	pending_domain_events.clear()
	capture_domain_events = true


func end_event_capture() -> void:
	capture_domain_events = false


func drain_domain_events() -> Array:
	var result: Array = pending_domain_events.duplicate(true)
	pending_domain_events.clear()
	return result


func _emit_domain_event(event_type: String, payload: Dictionary = {}) -> void:
	if not capture_domain_events:
		return
	pending_domain_events.append({
		"type": event_type,
		"payload": payload.duplicate(true),
	})


func emit_domain_event(event_type: String, payload: Dictionary = {}) -> void:
	_emit_domain_event(event_type, payload)


func record_attack_distress(attacker: Dictionary, target: Dictionary) -> void:
	if are_teams_allied(int(attacker.get("team", 0)), int(target.get("team", 0))):
		return
	ai_distress_system.record(attacker, target)


func get_attack_distress_signals(team: int) -> Array:
	return ai_distress_system.presentation_for_team(team)

func add_unit(team: int, kind: String, position: Vector2, selected: bool) -> Dictionary:
	return entity_factory.add_unit(team, kind, position, selected)

func add_resource(kind: String, position: Vector2, amount: int) -> Dictionary:
	return entity_factory.add_resource(kind, position, amount, true)


func add_scenario_resource(kind: String, position: Vector2, amount: int) -> Dictionary:
	return entity_factory.add_resource(kind, Coordinates.clamp_world(position, map_size), amount, false)


func _add_resource(kind: String, position: Vector2, amount: int, resolve_placement: bool) -> Dictionary:
	return entity_factory.add_resource(kind, position, amount, resolve_placement)

func resource_stats(kind: String) -> Dictionary:
	if data_repository.has_archetype(kind):
		return data_repository.object_record(kind, 0)
	var unit_id := 144 if kind == "tree" else 59 if kind == "berries" else -1
	return object_catalog_data.get("objects", {}).get("0:%d" % unit_id, {})


func resource_type_for(kind: String, source: Dictionary) -> int:
	var configured_type := int(data_repository.runtime_metadata(kind).get("resource_type_id", -1))
	if configured_type >= 0:
		return configured_type
	for storage_value in source.get("resources", {}).get("storage", []):
		var storage: Dictionary = storage_value
		if int(storage.get("type", -1)) >= 0 and float(storage.get("amount", 0.0)) > 0.0:
			return int(storage["type"])
	return 0 if kind == "berries" else 1 if kind == "tree" else -1


func find_resource_placement(desired: Vector2, radius: float, movement_domain: String = "land", restriction_id: int = -1) -> Vector2:
	return entity_factory.find_resource_placement(desired, radius, movement_domain, restriction_id)

func add_building(id: int, kind: String, position: Vector2, team: int = 1, completed: bool = true) -> Dictionary:
	return entity_factory.add_building(id, kind, position, team, completed)

func remove_selection_for(team: int) -> void:
	for unit in units:
		if unit["team"] == team:
			unit["selected"] = false

func get_selected_units(team: int) -> Array:
	var selected: Array = []
	for unit in units:
		if unit["team"] == team and unit["selected"] and unit["hp"] > 0.0:
			selected.append(unit)
	selected.sort_custom(func(left, right): return left["id"] < right["id"])
	return selected

func unit_stats(kind: String) -> Dictionary:
	return data_repository.simulation_stats(kind)


func apply_archetype_identity(entity: Dictionary, kind: String) -> void:
	var identifiers := data_repository.identifiers(kind)
	if identifiers.is_empty():
		return
	entity["internal_id"] = String(identifiers.get("internal_id", kind))
	entity["source_unit_id"] = int(identifiers.get("source_unit_id", entity.get("source_unit_id", -1)))
	entity["presentation_id"] = String(identifiers.get("presentation_id", kind))
	entity["behavior_tags"] = data_repository.behavior_tags(kind)
	var identity: Dictionary = entity.get("components", {}).get("identity", {})
	identity["internal_id"] = entity["internal_id"]
	identity["source_unit_id"] = entity["source_unit_id"]
	identity["presentation_id"] = entity["presentation_id"]
	identity["behavior_tags"] = entity["behavior_tags"].duplicate()


func entity_has_behavior_tag(entity: Dictionary, tag: String) -> bool:
	if tag in entity.get("behavior_tags", []):
		return true
	# Compatibility for tests and old saves created before runtime-catalog v1.
	return tag == "drop_site" and String(entity.get("kind", "")) == "town_center"


func entity_is_worker(entity: Dictionary) -> bool:
	if bool(entity.get("components", {}).get("worker", {}).get("enabled", false)):
		return true
	# Compatibility for worlds configured only with gamespec-prototype v4.
	return entity.get("behavior_tags", []).is_empty() and String(entity.get("kind", "")) == "villager"


func combat_source_context(entity: Dictionary) -> Dictionary:
	return {
		"entity_id": int(entity.get("id", -1)),
		"team": int(entity.get("team", 0)),
		"is_worker": entity_is_worker(entity),
	}


func configure_entity_combat_awareness(entity: Dictionary) -> void:
	var previous_combat_enabled := bool(entity.get("combat_enabled", false))
	var combat: Dictionary = entity.get("components", {}).get("combat", {})
	var attacks: Array = combat.get("attacks", [])
	var compatibility_kind := String(entity.get("kind", "")) in ["villager", "clubman", "archer", "enemy_clubman", "enemy_archer", "test_melee"]
	var conversion_enabled := conversion_system != null and conversion_system.is_converter(entity)
	var combat_enabled := not attacks.is_empty() or (float(combat.get("attack_period", 0.0)) > 0.0 and not conversion_enabled) or compatibility_kind
	var vision_range := maxf(0.0, float(entity.get("components", {}).get("vision", {}).get("range", 0.0)))
	if vision_range <= 0.0 and combat_enabled:
		vision_range = 6.0
	var configured_stance := String(data_repository.runtime_metadata(String(entity.get("kind", ""))).get("combat_stance", ""))
	var default_stance := "stand_ground" if entity_is_static(entity) else ("defensive" if entity_is_worker(entity) else ("aggressive" if combat_enabled else "passive"))
	entity["combat_enabled"] = combat_enabled
	entity["stance"] = configured_stance if not configured_stance.is_empty() else default_stance
	entity["acquisition_range"] = vision_range
	entity["chase_range"] = maxf(vision_range, maxf(0.85, float(entity.get("attack_range", 0.0)))) * 2.0
	if previous_combat_enabled != combat_enabled:
		mark_combat_roster_dirty()


func mark_combat_roster_dirty() -> void:
	combat_roster_revision += 1


func configure_unit_combat_awareness(unit: Dictionary) -> void:
	# Compatibility facade for tests and older callers. Combat capability is now
	# an entity component and therefore applies to mobile and static entities.
	configure_entity_combat_awareness(unit)


func entity_is_static(entity: Dictionary) -> bool:
	return String(entity.get("components", {}).get("movement", {}).get("domain", entity.get("movement_domain", "land"))) == "static"


func combat_target_domains(entity: Dictionary) -> Array[String]:
	if not entity_is_static(entity):
		var movement_domain := String(entity.get("movement_domain", entity.get("components", {}).get("movement", {}).get("domain", "land")))
		return [movement_domain] if movement_domain in ["land", "water"] else ["land"]
	var placement: Dictionary = data_repository.runtime_metadata(String(entity.get("kind", ""))).get("placement", {})
	var result: Array[String] = []
	for domain_value in placement.get("required_adjacent_domains", []):
		var domain := String(domain_value)
		if domain in ["land", "water"] and domain not in result:
			result.append(domain)
	if result.is_empty():
		var placement_domain := String(placement.get("domain", "land"))
		if placement_domain in ["land", "water"]:
			result.append(placement_domain)
	if result.is_empty():
		result.append("land")
	result.sort()
	return result


func refresh_building_connectivity() -> void:
	var occupied: Dictionary = {}
	for building_value in buildings:
		var building: Dictionary = building_value
		var group := String(data_repository.runtime_metadata(String(building.get("kind", ""))).get("connectivity_group", ""))
		building["connectivity_group"] = group
		if group.is_empty() or float(building.get("hp", 0.0)) <= 0.0 or String(building.get("state", "complete")) == "destroyed":
			continue
		for cell_value in building.get("occupied_cells", []):
			var cell: Vector2i = cell_value
			occupied["%d:%s:%d:%d" % [int(building.get("team", 0)), group, cell.x, cell.y]] = true
	var offsets := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for building_value in buildings:
		var building: Dictionary = building_value
		var group := String(building.get("connectivity_group", ""))
		var next_mask := 0
		if not group.is_empty() and float(building.get("hp", 0.0)) > 0.0 and String(building.get("state", "complete")) != "destroyed":
			for direction in range(offsets.size()):
				for cell_value in building.get("occupied_cells", []):
					var neighbor: Vector2i = Vector2i(cell_value) + offsets[direction]
					var key := "%d:%s:%d:%d" % [int(building.get("team", 0)), group, neighbor.x, neighbor.y]
					if occupied.has(key):
						next_mask |= 1 << direction
						break
		if int(building.get("connection_mask", 0)) != next_mask:
			building["connection_mask"] = next_mask
			building["connection_revision"] = int(building.get("connection_revision", 0)) + 1


func register_building_victory_objective(building: Dictionary) -> void:
	var category := String(data_repository.runtime_metadata(String(building.get("kind", ""))).get("victory_objective_category", ""))
	if category.is_empty() or int(building.get("victory_objective_id", -1)) >= 0:
		return
	var objective := add_victory_object(category, Vector2(building.get("pos", Vector2.ZERO)), int(building.get("team", 0)), String(building.get("state", "complete")) == "complete")
	objective["source_entity_id"] = int(building.get("id", -1))
	building["victory_objective_id"] = int(objective["id"])


func register_unit_victory_objective(unit: Dictionary) -> void:
	var metadata := data_repository.runtime_metadata(String(unit.get("kind", "")))
	var category := String(metadata.get("victory_objective_category", ""))
	if category.is_empty() or int(unit.get("victory_objective_id", -1)) >= 0:
		return
	var objective := add_victory_object(category, Vector2(unit.get("pos", Vector2.ZERO)), int(unit.get("team", 0)), true)
	objective["source_entity_id"] = int(unit.get("id", -1))
	objective["logical_only"] = true
	unit["victory_objective_id"] = int(objective["id"])


func track_conquest_entity(entity: Dictionary) -> void:
	var entity_id := int(entity.get("id", -1))
	if entity_id < 0:
		return
	var old_team := int(conquest_tracked_by_id.get(entity_id, 0))
	var team := int(entity.get("team", 0))
	var is_building := buildings_by_id.has(entity_id)
	var qualifies := bool(entity.get("counts_for_conquest", true)) if is_building else not entity_has_behavior_tag(entity, "capturable") and not entity_has_behavior_tag(entity, "noncombat_target")
	var new_team := team if team > 0 and float(entity.get("hp", 0.0)) > 0.0 and qualifies else 0
	if old_team == new_team:
		return
	if old_team > 0:
		conquest_counts_by_team[old_team] = maxi(0, int(conquest_counts_by_team.get(old_team, 0)) - 1)
	if new_team > 0:
		conquest_counts_by_team[new_team] = int(conquest_counts_by_team.get(new_team, 0)) + 1
		conquest_tracked_by_id[entity_id] = new_team
	else:
		conquest_tracked_by_id.erase(entity_id)


func rebuild_conquest_presence() -> void:
	conquest_counts_by_team.clear()
	conquest_tracked_by_id.clear()
	for unit in get_all_units_including_embarked():
		track_conquest_entity(unit)
	for building in buildings:
		track_conquest_entity(building)


func sync_unit_victory_objective(unit: Dictionary) -> void:
	var objective_id := int(unit.get("victory_objective_id", -1))
	if objective_id < 0:
		return
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == objective_id:
			objective["team"] = int(unit.get("team", 0))
			objective["completed"] = float(unit.get("hp", 0.0)) > 0.0
			objective["active"] = float(unit.get("hp", 0.0)) > 0.0 and not bool(unit.get("removed", false)) and String(unit.get("cargo_state", "deployed")) != "embarked"
			objective["pos"] = Vector2(unit.get("pos", Vector2.ZERO))
			victory_system.track_objective(objective)
			return


func update_capturable_objectives() -> void:
	for objective_unit_value in capturable_units:
		var objective_unit: Dictionary = objective_unit_value
		if not entity_has_behavior_tag(objective_unit, "capturable") or float(objective_unit.get("hp", 0.0)) <= 0.0:
			continue
		var capture_radius := maxf(0.0, float(capture_radius_for_kind(String(objective_unit.get("kind", "")))))
		var objective_position := Vector2(objective_unit.get("pos", Vector2.ZERO))
		var objective_id := int(objective_unit.get("id", -1))
		# The spatial index bounds the candidate set; the single best candidate
		# is found with one min-scan using the sort's exact (distance, id) order.
		var best_candidate: Dictionary = {}
		var best_distance := INF
		var best_candidate_id := 9223372036854775807
		for candidate_value in query_units_near(objective_position, capture_radius + 1.5):
			var candidate: Dictionary = candidate_value
			var candidate_id := int(candidate.get("id", -1))
			if candidate_id == objective_id or int(candidate.get("team", 0)) <= 0:
				continue
			if float(candidate.get("hp", 0.0)) <= 0.0 or entity_has_behavior_tag(candidate, "capturable"):
				continue
			var distance := objective_position.distance_to(Vector2(candidate.get("pos", Vector2.ZERO)))
			if distance > capture_radius + 0.0001:
				continue
			if not best_candidate.is_empty():
				if not is_equal_approx(distance, best_distance):
					if distance > best_distance:
						continue
				elif candidate_id > best_candidate_id:
					continue
			best_candidate = candidate
			best_distance = distance
			best_candidate_id = candidate_id
		if not best_candidate.is_empty():
			var new_team := int(best_candidate.get("team", 0))
			var old_team := int(objective_unit.get("team", 0))
			if new_team != old_team and (old_team <= 0 or not are_teams_allied(old_team, new_team)):
				transfer_entity_ownership(objective_unit, new_team, -1, "proximity_capture", true)
		sync_unit_victory_objective(objective_unit)
	for objective in capturable_victory_objectives:
		if not bool(objective.get("active", true)):
			continue
		var position := Vector2(objective.get("pos", Vector2.ZERO))
		var best_team := -1
		var best_distance := INF
		var best_id := 9223372036854775807
		for candidate_value in query_units_near(position, 2.5):
			var candidate: Dictionary = candidate_value
			var candidate_id := int(candidate.get("id", -1))
			if int(candidate.get("team", 0)) <= 0 or float(candidate.get("hp", 0.0)) <= 0.0 or entity_has_behavior_tag(candidate, "capturable"):
				continue
			var distance := position.distance_to(Vector2(candidate.get("pos", Vector2.ZERO)))
			if distance > 1.0 + 0.0001 or distance > best_distance or (is_equal_approx(distance, best_distance) and candidate_id >= best_id):
				continue
			best_team = int(candidate.get("team", 0))
			best_distance = distance
			best_id = candidate_id
		if best_team > 0 and best_team != int(objective.get("team", 0)) and (int(objective.get("team", 0)) <= 0 or not are_teams_allied(int(objective.get("team", 0)), best_team)):
			set_victory_object_owner(int(objective.get("id", -1)), best_team)


func capture_radius_for_kind(kind: String) -> float:
	if not capture_radius_by_kind.has(kind):
		capture_radius_by_kind[kind] = data_repository.runtime_metadata(kind).get("capture_radius", 1.0)
	return float(capture_radius_by_kind[kind])


func sync_building_victory_objective(building: Dictionary) -> void:
	var objective_id := int(building.get("victory_objective_id", -1))
	if objective_id < 0:
		return
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == objective_id:
			objective["team"] = int(building.get("team", 0))
			objective["completed"] = String(building.get("state", "complete")) == "complete" and float(building.get("hp", 0.0)) > 0.0
			objective["active"] = float(building.get("hp", 0.0)) > 0.0 and String(building.get("state", "complete")) != "destroyed"
			objective["pos"] = Vector2(building.get("pos", Vector2.ZERO))
			victory_system.track_objective(objective)
			return


func deactivate_building_victory_objective(building: Dictionary) -> void:
	var objective_id := int(building.get("victory_objective_id", -1))
	if objective_id >= 0:
		remove_victory_object(objective_id)


func object_record_for(kind: String, team: int) -> Dictionary:
	if data_repository.has_archetype(kind):
		return data_repository.object_record(kind, int(civilization_by_team.get(team, 13)))
	var stats := unit_stats(kind)
	var unit_id := int(stats.get("unit_id", -1))
	if unit_id < 0:
		return {}
	return object_record_by_id(unit_id, team)


func object_record_by_id(unit_id: int, team: int) -> Dictionary:
	var objects: Dictionary = object_catalog_data.get("objects", {})
	var civilization_id := int(civilization_by_team.get(team, 13))
	var direct: Dictionary = objects.get("%d:%d" % [civilization_id, unit_id], {})
	if not direct.is_empty():
		return direct
	return objects.get("0:%d" % unit_id, {})


func civilization_record(team: int) -> Dictionary:
	var civilization_id := int(civilization_by_team.get(team, 13))
	for value in object_catalog_data.get("civilizations", []):
		var record: Dictionary = value
		if int(record.get("civilization_id", -1)) == civilization_id:
			return record
	return {}


func initialize_team_rules(team: int) -> void:
	var civilization := civilization_record(team)
	technology_system.set_team_civilization(team, int(civilization_by_team.get(team, 13)))
	technology_system.initialize_rule_resources(team, civilization.get("resources", []))
	apply_technology_commands(team, technology_system.initialize_team(team), false)
	apply_technology_commands(team, technology_system.apply_effect_bundle(team, int(civilization.get("tech_tree_id", -1)), not full_tech_tree_enabled), false)
	resolve_automatic_technologies(team)
	if full_tech_tree_enabled:
		# RoR's Full Tech Tree retains civilization bonuses but lifts civilization
		# technology disables. Fire Galley is the explicit global exception.
		technology_system.disable_scenario_object(team, 360)
	_sync_shared_vision(team)


func apply_civilization_starting_resources(team: int) -> void:
	var source: Array = civilization_record(team).get("resources", [])
	for resource_id in range(mini(4, source.size())):
		set_resource_amount(team, resource_id, roundi(float(source[resource_id])))

func _configure_tick_pipeline() -> void:
	tick_pipeline.clear()
	tick_pipeline.add_active("capture_previous_positions", Callable(self, "_tick_capture_previous_positions"))
	tick_pipeline.add_active("ai_distress", Callable(ai_distress_system, "advance"))
	tick_pipeline.add_active("trade_goods", Callable(trade_system, "advance_goods"))
	tick_pipeline.add_active("unit_orders", Callable(self, "_tick_unit_orders"))
	tick_pipeline.add_active("capturable_objectives", Callable(self, "_tick_capturable_objectives"))
	tick_pipeline.add_active("static_combat", Callable(combat_system, "advance_static_combatants"))
	tick_pipeline.add_active("death_lifecycle", Callable(self, "_tick_death_lifecycle"))
	tick_pipeline.add_active("resource_lifecycle", Callable(self, "_tick_resource_lifecycle"))
	tick_pipeline.add_active("production", Callable(production_system, "advance"))
	tick_pipeline.add_active("projectiles", Callable(combat_system, "advance_projectiles"))
	tick_pipeline.add_active("victory", Callable(self, "_tick_victory"))
	tick_pipeline.add_active("purge", Callable(self, "_tick_purge"))
	tick_pipeline.add_active("spatial_index", Callable(self, "_tick_spatial_index"))
	tick_pipeline.add_active("fog", Callable(self, "_tick_fog"))
	tick_pipeline.add_active("component_sync", Callable(self, "_tick_component_sync"))

	tick_pipeline.add_completed("death_lifecycle", Callable(self, "_tick_death_lifecycle"))
	tick_pipeline.add_completed("resource_lifecycle", Callable(self, "_tick_resource_lifecycle"))
	tick_pipeline.add_completed("projectiles", Callable(combat_system, "advance_projectiles"))
	tick_pipeline.add_completed("purge", Callable(self, "_tick_purge"))
	tick_pipeline.add_completed("spatial_index", Callable(self, "_tick_spatial_index"))
	tick_pipeline.add_completed("fog", Callable(self, "_tick_fog"))
	tick_pipeline.add_completed("component_sync", Callable(self, "_tick_component_sync"))


func advance(delta: float, player_team: int, enemy_team: int) -> String:
	var context := {
		"delta": delta,
		"player_team": player_team,
		"enemy_team": enemy_team,
	}
	tick_pipeline.run(battle_over, context)
	return battle_message


func tick_system_order(match_completed: bool = false) -> Array[String]:
	return tick_pipeline.system_order(match_completed)


func _tick_capture_previous_positions(context: Dictionary) -> void:
	unit_activity_registry.begin_tick(units, maxf(0.0, float(context.get("delta", 0.0))))


func _tick_unit_orders(context: Dictionary) -> void:
	update_units(float(context["delta"]), int(context["player_team"]), int(context["enemy_team"]))


func _tick_capturable_objectives(_context: Dictionary) -> void:
	update_capturable_objectives()


func _tick_victory(context: Dictionary) -> void:
	check_battle_state(int(context["player_team"]), int(context["enemy_team"]), float(context["delta"]))


func _tick_death_lifecycle(context: Dictionary) -> void:
	advance_death_only(float(context["delta"]))


func _tick_resource_lifecycle(context: Dictionary) -> void:
	advance_resource_lifecycle(float(context["delta"]))


func _tick_purge(_context: Dictionary) -> void:
	purge_removed_units()


func _tick_spatial_index(_context: Dictionary) -> void:
	if not spatial_sync_system.advance(spatial_index, unit_activity_registry.ordered_units(), units, buildings):
		rebuild_spatial_index(false)


func _tick_component_sync(_context: Dictionary) -> void:
	# Active units, static combatants, resources, construction and damage each
	# synchronize at their mutation site. Only embarked units are outside those
	# normal update loops and need a final compatibility sync here.
	for unit in transport_system.all_embarked_units():
		EntityComponents.sync_dynamic(unit)

func rebuild_spatial_index(rebuild_navigation: bool = true) -> void:
	spatial_index.clear()
	for unit in units:
		if unit["hp"] > 0.0:
			spatial_index.insert(unit, unit["pos"], float(unit.get("footprint_radius", 0.31)), "unit")
	for building in buildings:
		if building["hp"] > 0.0:
			var half_size: Vector2 = building["footprint"]["half_size"]
			spatial_index.insert(building, building["pos"], half_size.length(), "obstacle")
	spatial_sync_system.note_rebuilt()
	if rebuild_navigation:
		rebuild_navigation_grid()

func rebuild_navigation_grid() -> void:
	if navigation_grid != null:
		navigation_grid.configure_terrain_ids(Callable(self, "terrain_id_at_cell"))
		navigation_grid.rebuild(resource_nodes, buildings, static_obstructions)
		for building in buildings:
			building_navigation_cells_by_id[int(building.get("id", -1))] = _building_navigation_cells(building)


func _building_navigation_cells(building: Dictionary) -> Array:
	if float(building.get("hp", 1.0)) <= 0.0:
		return []
	if bool(building.get("passable", false)) or "passable" in building.get("behavior_tags", []):
		return []
	return building.get("occupied_cells", [])


func sync_building_navigation_occupancy(building: Dictionary) -> void:
	_sync_building_navigation_occupancy(building)


func _sync_building_navigation_occupancy(building: Dictionary) -> void:
	# Footprint-local delta against the last synced cells so a single placement,
	# destruction or age-upgrade never pays the full-map reconcile.
	if navigation_grid == null:
		return
	var building_id := int(building.get("id", -1))
	var desired: Array = _building_navigation_cells(building)
	var previous: Array = building_navigation_cells_by_id.get(building_id, [])
	if previous.is_empty() and desired.is_empty():
		return
	var desired_set := {}
	for cell in desired:
		desired_set[cell] = true
	var previous_set := {}
	for cell in previous:
		previous_set[cell] = true
	var released: Array = []
	for cell in previous:
		if not desired_set.has(cell):
			released.append(cell)
	var occupied: Array = []
	for cell in desired:
		if not previous_set.has(cell):
			occupied.append(cell)
	if not released.is_empty():
		navigation_grid.release_occupant(released, "building", building_id)
	if not occupied.is_empty():
		navigation_grid.occupy(occupied, "building", building_id)
	if desired.is_empty():
		building_navigation_cells_by_id.erase(building_id)
	else:
		building_navigation_cells_by_id[building_id] = desired.duplicate()


func release_building_navigation_occupancy(building: Dictionary) -> void:
	_release_building_navigation_occupancy(building)


func _release_building_navigation_occupancy(building: Dictionary) -> void:
	if navigation_grid == null:
		return
	var building_id := int(building.get("id", -1))
	var cells: Array = building_navigation_cells_by_id.get(building_id, building.get("occupied_cells", []))
	if not cells.is_empty():
		navigation_grid.release_occupant(cells, "building", building_id)
	building_navigation_cells_by_id.erase(building_id)


func configure_demo_elevation(center: Vector2i, radius: int = 4, maximum_elevation: int = 2) -> void:
	terrain_elevation.generate_radial_hill(center, radius, maximum_elevation)
	navigation_grid.configure_elevation(Callable(self, "terrain_profile_at"))
	pathfinder.clear_cache()
	sync_entity_elevations()


func terrain_profile_at(cell: Vector2i) -> Dictionary:
	return terrain_elevation.cell_profile(cell)


func terrain_id_at_cell(cell: Vector2i) -> int:
	if int(forest_resource_counts.get(cell, 0)) > 0:
		return _terrain_id_with_forest_resource(cell)
	return int(map_terrain_ids.get(cell, TerrainRules.terrain_id_for_logical(TerrainRules.terrain_at(cell))))


func _register_forest_resource(resource: Dictionary) -> void:
	var cell := Vector2i(floori(float(resource.get("pos", Vector2.ZERO).x)), floori(float(resource.get("pos", Vector2.ZERO).y)))
	var previous := int(forest_resource_counts.get(cell, 0))
	var previous_terrain := terrain_id_at_cell(cell)
	forest_resource_counts[cell] = previous + 1
	# Imported ground is independent of the standing tree. A resource change
	# must not invalidate every terrain/fog mesh unless its surface changed.
	if terrain_id_at_cell(cell) != previous_terrain:
		_record_terrain_change(cell)
	if navigation_grid != null and previous == 0:
		navigation_grid.set_terrain_id(cell, _terrain_id_with_forest_resource(cell))


func register_forest_resource(resource: Dictionary) -> void:
	_register_forest_resource(resource)


func unregister_forest_resource(resource: Dictionary) -> void:
	_unregister_forest_resource(resource)


func _unregister_forest_resource(resource: Dictionary) -> void:
	if String(resource.get("kind", "")) != "tree":
		return
	var position: Vector2 = resource.get("pos", Vector2.ZERO)
	var cell := Vector2i(floori(position.x), floori(position.y))
	var previous_terrain := terrain_id_at_cell(cell)
	var remaining := int(forest_resource_counts.get(cell, 0)) - 1
	if remaining > 0:
		forest_resource_counts[cell] = remaining
	else:
		forest_resource_counts.erase(cell)
		if navigation_grid != null:
			navigation_grid.set_terrain_id(cell, int(map_terrain_ids.get(cell, TerrainRules.terrain_id_for_logical(TerrainRules.terrain_at(cell)))))
	if terrain_id_at_cell(cell) != previous_terrain:
		_record_terrain_change(cell)


func _terrain_id_with_forest_resource(cell: Vector2i) -> int:
	var source_terrain_id := int(map_terrain_ids.get(cell, TerrainRules.terrain_id_for_logical(TerrainRules.terrain_at(cell))))
	if TerrainRules.is_environment_terrain_id(source_terrain_id):
		# A tree must not replace the explicitly selected environment material.
		# Its resource footprint already provides the movement obstruction.
		return source_terrain_id
	return source_terrain_id if TerrainRules.is_source_forest_terrain_id(source_terrain_id) else int(TerrainRules.TERRAIN_IDS["forest_floor"])


func terrain_kind_at_cell(cell: Vector2i) -> String:
	return TerrainRules.logical_for_terrain_id(terrain_id_at_cell(cell))


func create_building(team: int, kind: String, position: Vector2, completed: bool = true) -> Dictionary:
	return add_building(entity_id_sequence.next(), kind, position, team, completed)


func elevation_at(position: Vector2) -> float:
	return terrain_elevation.elevation_at_world(position)


func sync_entity_elevations() -> void:
	for unit in units:
		unit["elevation"] = elevation_at(unit["pos"])
	for resource in resource_nodes:
		resource["elevation"] = elevation_at(resource["pos"])
	for building in buildings:
		building["elevation"] = elevation_at(building["pos"])
	sync_all_components()


func sync_all_components() -> void:
	for unit in units:
		EntityComponents.sync_dynamic(unit)
	for unit in transport_system.all_embarked_units():
		EntityComponents.sync_dynamic(unit)
	for resource in resource_nodes:
		EntityComponents.sync_dynamic(resource)
	for building in buildings:
		EntityComponents.sync_dynamic(building)


func update_fog_of_war() -> void:
	_tick_fog({"force": true})


func _tick_fog(context: Dictionary) -> void:
	visibility_system.advance(context)
	var fog = get_fog_of_war()
	# Sample sight even while units are idle. A planner first created much later
	# must not learn hidden changes to terrain the player saw earlier.
	for observer_value in fog.states_by_player:
		if int(observer_value) > 0:
			movement_system.knowledge.planner(self, int(observer_value))
	# Resource memory is sampled at the exact visibility transition. This keeps
	# hidden state frozen even when an AI snapshot is requested less often than
	# the simulation tick.
	for observer_value in known_resources_by_player.keys():
		var observer_team := int(observer_value)
		var cached: Dictionary = known_resources_by_player[observer_value]
		_refresh_known_resource_cache(observer_team, cached, fog)

func query_units_near(position: Vector2, radius: float) -> Array:
	return spatial_index.query_circle(position, radius, "unit")


func _has_external_formation_unit(bounds: Rect2, formation_group_id: int) -> bool:
	return spatial_index.has_external_unit_in_aabb(bounds, formation_group_id)


func query_combat_entities_near(position: Vector2, radius: float) -> Array:
	var origin := {"pos": position, "footprint_radius": 0.0}
	var result: Array = []
	for entity in spatial_index.query_circle(position, maxf(0.0, radius)):
		if float(entity.get("hp", 0.0)) <= 0.0:
			continue
		if CombatRules.edge_distance(origin, entity) <= maxf(0.0, radius) + 0.0001:
			result.append(entity)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


func update_units(delta: float, player_team: int, enemy_team: int) -> void:
	# The regular fixed-tick pipeline prepares activity before entering this
	# method. Keep the public method self-contained as well: scenarios, tools and
	# compatibility callers are allowed to advance unit orders directly.
	unit_activity_registry.ensure_tick(units, delta)
	var probe: Variant = tick_pipeline.performance_probe
	movement_neighbor_query_microseconds = 0
	movement_local_calculation_microseconds = 0
	movement_integration_microseconds = 0
	movement_arrival_microseconds = 0
	movement_native_unit_updates = 0
	movement_native_neighbor_candidates = 0
	pathfinder.reset_path_query_tick_observation()
	var phase_started := Time.get_ticks_usec() if probe != null else 0
	var active_units: Array = unit_activity_registry.ordered_units()
	if probe != null:
		probe.increment("simulation.unit_orders.active_units", active_units.size())
		probe.increment("simulation.unit_orders.idle_units_skipped", maxi(0, units.size() - active_units.size()))
	if formation_cohesion_active:
		if not formation_groups_view.is_empty():
			FormationCohesion.update_active_groups(
				formation_groups_view,
				units_by_id,
				Callable(self, "_has_external_formation_unit"),
				spatial_index.maximum_unit_radius,
				spatial_index.maximum_unit_clearance
			)
		elif unit_activity_registry.has_active_formation():
			FormationCohesion.update(units)
	if probe != null:
		probe.observe_microseconds("simulation.unit_orders.formation_cohesion", Time.get_ticks_usec() - phase_started)
		phase_started = Time.get_ticks_usec()
	_release_finished_combat_reservations()
	if probe != null:
		probe.observe_microseconds("simulation.unit_orders.combat_reservations", Time.get_ticks_usec() - phase_started)
		phase_started = Time.get_ticks_usec()
	pathfinder.prepare_native_movement_snapshot(units if unit_activity_registry.has_movement_candidate() else [])
	pathfinder.prepare_native_movement_batch(active_units, delta, task_coordinator, open_movement_envelopes_by_id)
	if probe != null:
		probe.observe_microseconds("simulation.unit_orders.native_movement_snapshot", Time.get_ticks_usec() - phase_started)
	var preparation_microseconds := 0
	var task_microseconds := 0
	var task_microseconds_by_kind: Dictionary = {}
	var gather_microseconds_by_stage: Dictionary = {}
	var presentation_microseconds := 0
	var animation_microseconds := 0
	var component_sync_microseconds := 0
	var boarding_ready: Array = []
	var unloading_ready: Array = []
	var task_order_update := {
		"moving": false,
		"animation_state": AnimationController.IDLE,
		"attack_target": null,
	}
	var active_unit_index := 0
	var last_processed_unit_order := -1
	while active_unit_index < active_units.size():
		var unit: Dictionary = active_units[active_unit_index]
		active_unit_index += 1
		var active_unit_id := int(unit.get("id", -1))
		var active_unit_order := unit_activity_registry.order_of(active_unit_id)
		if active_unit_order <= last_processed_unit_order:
			continue
		last_processed_unit_order = active_unit_order
		phase_started = Time.get_ticks_usec() if probe != null else 0
		if unit["hp"] <= 0.0:
			begin_death(unit)
			if probe != null:
				preparation_microseconds += Time.get_ticks_usec() - phase_started
			continue
		var position_before_tick: Vector2 = unit.get("pos", Vector2.ZERO)
		var task_name := String(unit.get("task", "idle"))
		var stable_idle_tick: bool = (
			task_name == "idle"
			and unit.get("path", []).is_empty()
			and int(unit.get("path_index", 0)) == 0
			and Vector2(unit.get("target", position_before_tick)) == position_before_tick
		)
		if float(unit["cooldown"]) > 0.0:
			unit["cooldown"] = maxf(0.0, float(unit["cooldown"]) - delta)
		if float(unit["work"]) > 0.0:
			unit["work"] = maxf(0.0, float(unit["work"]) - delta)
		if bool(unit["components"]["conversion"]["enabled"]):
			conversion_system.advance_faith(unit, delta)
		if int(unit["retaliation_target_id"]) >= 0:
			_update_huntable_reaction(unit)
		if probe != null:
			preparation_microseconds += Time.get_ticks_usec() - phase_started
			phase_started = Time.get_ticks_usec()
		var moving := false
		var animation_state := AnimationController.IDLE
		var attack_target: Variant = null
		var gather_stage_name := String(unit.get("gather_stage", "none")) if task_name == "gather" else ""
		match task_name:
			"board":
				moving = transport_system.advance_board_order(unit, delta, boarding_ready)
			"unload":
				moving = transport_system.advance_unload_order(unit, delta, unloading_ready)
			"trade":
				var trade_update := trade_system.advance_unit(unit, delta)
				moving = bool(trade_update.get("moving", false))
				animation_state = String(trade_update.get("animation_state", AnimationController.IDLE))
			"attack_ground", "attack":
				combat_system.advance_unit_order(unit, delta, task_order_update)
				moving = bool(task_order_update["moving"])
				animation_state = String(task_order_update["animation_state"])
				attack_target = task_order_update["attack_target"]
			"convert":
				conversion_system.advance_unit_order(unit, delta, task_order_update)
				moving = bool(task_order_update["moving"])
				animation_state = String(task_order_update["animation_state"])
			"heal":
				healing_system.advance_unit_order(unit, delta, task_order_update)
				moving = bool(task_order_update["moving"])
				animation_state = String(task_order_update["animation_state"])
			"gather":
				var gather_update := update_gather_order(unit, delta)
				match gather_update:
					GATHER_UPDATE_MOVE:
						moving = true
						animation_state = AnimationController.MOVE
					GATHER_UPDATE_MOVE_IDLE:
						animation_state = AnimationController.MOVE
					GATHER_UPDATE_ACTION:
						animation_state = AnimationController.GATHER
					GATHER_UPDATE_CARRY_IDLE:
						animation_state = AnimationController.CARRY
					GATHER_UPDATE_CARRY_MOVE:
						moving = true
						animation_state = AnimationController.CARRY
			"build", "repair":
				construction_system.advance_unit_order(unit, delta, task_order_update)
				moving = bool(task_order_update["moving"])
				animation_state = String(task_order_update["animation_state"])
			"idle":
				if stable_idle_tick:
					# Preserve the observable effects of move_unit's arrived branch
					# without querying neighbours or rebuilding movement state.
					if Vector2(unit.get("actual_velocity", Vector2.ZERO)) != Vector2.ZERO:
						unit["actual_velocity"] = Vector2.ZERO
					if int(unit.get("stuck_ticks", 0)) != 0 or int(unit.get("push_priority", 0)) != int(unit.get("base_push_priority", unit.get("push_priority", 0))):
						StuckRecovery.reset(unit)
				else:
					moving = movement_system.move_unit(unit, delta)
			_:
				moving = movement_system.move_unit(unit, delta)

		if probe != null:
			var task_elapsed := Time.get_ticks_usec() - phase_started
			task_microseconds += task_elapsed
			task_microseconds_by_kind[task_name] = int(task_microseconds_by_kind.get(task_name, 0)) + task_elapsed
			if task_name == "gather":
				gather_microseconds_by_stage[gather_stage_name] = int(gather_microseconds_by_stage.get(gather_stage_name, 0)) + task_elapsed
			phase_started = Time.get_ticks_usec()
		if moving and animation_state != AnimationController.CARRY:
			animation_state = AnimationController.MOVE
		var restart_attack_clip := animation_state == AnimationController.ATTACK_WINDUP and String(unit.get("anim_state", "")) == AnimationController.ATTACK_RECOVER
		AnimationController.update(unit, animation_state, delta, restart_attack_clip)
		if attack_target != null:
			apply_attack_frame_event(unit, attack_target, player_team)
		if probe != null:
			animation_microseconds += Time.get_ticks_usec() - phase_started
		# Dynamic component mirrors are projected on snapshot/presentation
		# boundaries. Authoritative systems above operate on the unit runtime
		# fields, so rewriting the same nested Dictionaries for every entity on
		# every tick only duplicates state and dominates large moving groups.
	if probe != null:
		presentation_microseconds = animation_microseconds + component_sync_microseconds
		probe.observe_microseconds("simulation.unit_orders.preparation", preparation_microseconds)
		probe.observe_microseconds("simulation.unit_orders.task", task_microseconds)
		var task_kinds := task_microseconds_by_kind.keys()
		task_kinds.sort()
		for task_kind in task_kinds:
			probe.observe_microseconds("simulation.unit_orders.task.%s" % String(task_kind), int(task_microseconds_by_kind[task_kind]))
		var gather_stages := gather_microseconds_by_stage.keys()
		gather_stages.sort()
		for gather_stage in gather_stages:
			probe.observe_microseconds("simulation.unit_orders.task.gather.%s" % String(gather_stage), int(gather_microseconds_by_stage[gather_stage]))
		probe.observe_microseconds("simulation.unit_orders.animation_sync", presentation_microseconds)
		probe.observe_microseconds("simulation.unit_orders.animation", animation_microseconds)
		probe.observe_microseconds("simulation.unit_orders.component_sync", component_sync_microseconds)
		probe.observe_microseconds("simulation.movement.neighbor_query", movement_neighbor_query_microseconds)
		probe.observe_microseconds("simulation.movement.local_calculation", movement_local_calculation_microseconds)
		probe.observe_microseconds("simulation.movement.integration", movement_integration_microseconds)
		probe.observe_microseconds("simulation.movement.arrival", movement_arrival_microseconds)
		probe.observe_microseconds("simulation.navigation.path_queries", pathfinder.path_query_tick_microseconds())
		probe.increment("movement.native_unit_updates", movement_native_unit_updates)
		probe.increment("movement.native_neighbor_candidates", movement_native_neighbor_candidates)
	transport_system.finish_boarding_tick(boarding_ready)
	transport_system.finish_unloading_tick(unloading_ready)
	unit_activity_registry.finish_tick()


func set_formation_cohesion_active(value: bool) -> void:
	formation_cohesion_active = value


func refresh_unit_activity(unit: Dictionary) -> void:
	if units_by_id.has(int(unit.get("id", -1))):
		unit_activity_registry.refresh(unit)


func set_formation_groups_view(groups: Dictionary) -> void:
	formation_groups_view = groups


func apply_attack_frame_event(unit: Dictionary, enemy: Dictionary, player_team: int) -> void:
	combat_system.apply_attack_frame_event(unit, enemy, player_team)


func attack_animation_spec(unit: Dictionary) -> Dictionary:
	var kind := String(unit.get("kind", ""))
	var team := int(unit.get("team", 0))
	var source_id := int(unit.get("source_unit_id", -1))
	var role_source_id := int(unit.get("worker_role_source_unit_id", -1))
	var cache_key := Vector3i(team, source_id, role_source_id)
	var kind_cache: Dictionary = attack_animation_spec_cache.get(kind, {})
	if kind_cache.has(cache_key):
		return kind_cache[cache_key]
	var result: Dictionary
	if role_source_id >= 0:
		var role_source := object_record_by_id(role_source_id, team)
		var graphic_id := int(role_source.get("graphics", {}).get("attack", -1))
		var graphic: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
		var event_frame := int(role_source.get("combat", {}).get("frame_delay", 0))
		result = {
			"damage_frame": event_frame,
			"projectile_release_frame": event_frame,
			"frame_rate": float(graphic.get("frame_rate", 0.1)),
		}
	else:
		var source := object_record_by_id(source_id, team)
		if not source.is_empty():
			var graphic_id := int(source.get("graphics", {}).get("attack", -1))
			var graphic: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
			if not graphic.is_empty():
				var event_frame := int(source.get("combat", {}).get("frame_delay", 0))
				result = {
					"damage_frame": event_frame,
					"projectile_release_frame": event_frame,
					"frame_rate": float(graphic.get("frame_rate", 0.1)),
				}
		if result.is_empty():
			var stats := unit_stats(kind)
			var fallback: Dictionary = stats.get("animations", {}).get("attack", {})
			var default_event_frame := int(stats.get("attack_frame_delay", 0))
			result = {
				"damage_frame": int(fallback.get("damage_frame", default_event_frame)),
				"projectile_release_frame": int(fallback.get("projectile_release_frame", default_event_frame)),
				"frame_rate": float(fallback.get("frame_rate", 0.1)),
			}
	kind_cache[cache_key] = result
	attack_animation_spec_cache[kind] = kind_cache
	return result


func spawn_projectile(attacker: Dictionary, target: Dictionary) -> Dictionary:
	return combat_system.spawn_projectile(attacker, target)


func update_projectiles(delta: float, player_team: int) -> void:
	combat_system.update_projectiles(delta, player_team)


func death_animation_duration(kind: String) -> float:
	return death_system.death_animation_duration(kind)


func building_death_animation_duration(source: Dictionary) -> float:
	return death_system.building_death_animation_duration(source)


func corpse_animation_duration(source: Dictionary, team: int) -> float:
	return death_system.corpse_animation_duration(source, team)


func begin_death(unit: Dictionary) -> void:
	death_system.begin_death(unit)


func begin_entity_death(entity: Dictionary, source_context: Dictionary = {}) -> void:
	death_system.begin_entity_death(entity, source_context)


func begin_building_destruction(building: Dictionary) -> void:
	death_system.begin_building_destruction(building)


func advance_death(unit: Dictionary, delta: float) -> void:
	death_system.advance_death(unit, delta)


func advance_death_only(delta: float) -> void:
	death_system.advance_death_only(delta)


func purge_removed_units() -> void:
	death_system.purge_removed_units()

func move_unit(unit: Dictionary, delta: float) -> bool:
	return movement_system.move_unit(unit, delta)

func face_unit_toward(unit: Dictionary, target: Vector2) -> void:
	movement_system.face_unit_toward(unit, target)

func restore_formation_facing(unit: Dictionary) -> void:
	movement_system.restore_formation_facing(unit)

func facing_for_vector(direction: Vector2) -> int:
	return movement_system.facing_for_vector(direction)

func update_enemy_orders(_player_team: int, _enemy_team: int) -> void:
	# Compatibility facade. Autonomous combat is now emitted as immutable
	# commands by CombatAwarenessSystem in GameController for every team.
	# Keeping this method avoids breaking old callers while removing the former
	# enemy-only direct mutation from the authoritative tick pipeline.
	return

func check_battle_state(player_team: int, enemy_team: int, delta: float = 0.0) -> void:
	if battle_over:
		return
	var teams: Array = player_registry.all_teams()
	if teams.is_empty():
		teams = [player_team, enemy_team]
	var has_conquest_rule := victory_system.rules.any(func(rule): return String(rule.get("type", "conquest")) == "conquest")
	var conquest_presence: Dictionary = {}
	if has_conquest_rule:
		# Explicit checks in fixtures may change HP directly. Fixed-tick gameplay
		# uses the entity lifecycle index and never rescans the full roster here.
		if delta <= 0.0:
			rebuild_conquest_presence()
		for team_value in teams:
			var team := int(team_value)
			conquest_presence[team] = int(conquest_counts_by_team.get(team, 0)) > 0
	if has_conquest_rule:
		for team_value in teams:
			var team := int(team_value)
			if player_registry.status(team) != PlayerRegistry.ACTIVE:
				continue
			if not bool(conquest_presence.get(team, false)) and player_registry.defeat(team):
				_emit_domain_event("player_defeated", {"team": team})
	var resources: Dictionary = {}
	var technologies: Dictionary = {}
	var needs_scenario_rule_state := victory_system.rules.any(func(rule): return String(rule.get("type", "conquest")) == "scenario")
	if needs_scenario_rule_state:
		for team in teams:
			resources[team] = {}
			for resource_id in range(4):
				resources[team][resource_id] = get_resource_amount(team, resource_id)
			technologies[team] = technology_system.researched_ids(team)
	var victory_context := {
		"teams": teams,
		"participant_count": teams.size(),
		"player_states": _player_states_by_team(),
		"objectives": victory_objectives,
		"objective_summary": victory_system.objective_summary,
		"scores": score_by_team,
		"resources": resources,
		"technologies": technologies,
		"relations": _team_relations(),
	}
	if has_conquest_rule:
		victory_context["conquest_presence"] = conquest_presence
	if needs_scenario_rule_state or not scenario_system.definition.is_empty():
		victory_context["units"] = get_all_units_including_embarked()
		victory_context["buildings"] = buildings
		victory_context["resource_nodes"] = get_resources()
	var scenario_update: Dictionary = scenario_system.update(victory_context)
	for event_value in scenario_update.get("events", []):
		var event: Dictionary = event_value
		_emit_domain_event(String(event.get("type", "scenario_event")), event.get("payload", {}))
	victory_context["scenario_result"] = scenario_update.get("result", {})
	var outcome := victory_system.update(delta, victory_context)
	if not bool(outcome.get("over", false)):
		battle_message = ""
		return
	battle_over = true
	var winner_teams: Array = outcome.get("winner_teams", [int(outcome.get("winner_team", -1))])
	player_registry.finalize_side(winner_teams, outcome.get("loser_teams", []))
	var reason := String(outcome.get("reason", "conquest"))
	_emit_domain_event("match_completed", {
		"winner_team": int(outcome.get("winner_team", -1)),
		"winner_teams": winner_teams.duplicate(),
		"loser_teams": outcome.get("loser_teams", []).duplicate(),
		"reason": reason,
	})
	if player_team in winner_teams:
		battle_message = "ПОБЕДА — условие %s выполнено. Нажмите R, чтобы начать снова." % reason
	else:
		battle_message = "ПОРАЖЕНИЕ — противник выполнил условие %s. Нажмите R, чтобы начать снова." % reason


func _player_states_by_team() -> Dictionary:
	var result: Dictionary = {}
	for player_value in player_registry.public_states():
		var player: Dictionary = player_value
		result[int(player.get("team", 0))] = player
	return result


func _team_relations() -> Dictionary:
	var result: Dictionary = {}
	for team in player_registry.all_teams():
		result[team] = player_registry.relations_for(team)
	return result

func find_unit(id: int) -> Variant:
	return units_by_id.get(id)


func detach_unit_for_transport(id: int) -> Variant:
	var unit: Variant = units_by_id.get(id)
	if unit == null:
		return null
	units.erase(unit)
	units_by_id.erase(id)
	spatial_sync_system.mark_roster_dirty()
	mark_combat_roster_dirty()
	unit_activity_registry.forget(id)
	render_entity_projection_cache.erase(id)
	capturable_units.erase(unit)
	return unit


func restore_unit_from_transport(unit: Dictionary) -> bool:
	var id := int(unit.get("id", -1))
	if id < 0 or units_by_id.has(id):
		return false
	units.append(unit)
	units_by_id[id] = unit
	spatial_sync_system.mark_roster_dirty()
	mark_combat_roster_dirty()
	unit_activity_registry.refresh(unit)
	if entity_has_behavior_tag(unit, "capturable") and not capturable_units.has(unit):
		capturable_units.append(unit)
	return true


func find_combat_target(id: int) -> Variant:
	var unit = find_unit(id)
	if unit != null and not entity_has_behavior_tag(unit, "noncombat_target"):
		return unit
	return find_building(id)


func get_combat_targets(stable_order: bool = true) -> Array:
	var result: Array = []
	var last_id := -9223372036854775807
	var already_sorted := true
	for unit in units:
		if float(unit.get("hp", 0.0)) > 0.0 and not entity_has_behavior_tag(unit, "noncombat_target"):
			var unit_id := int(unit["id"])
			if stable_order and unit_id < last_id:
				already_sorted = false
			last_id = unit_id
			result.append(unit)
	for building in buildings:
		if float(building.get("hp", 0.0)) > 0.0:
			var building_id := int(building["id"])
			if stable_order and building_id < last_id:
				already_sorted = false
			last_id = building_id
			result.append(building)
	if stable_order and not already_sorted:
		result.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	return result


func get_combat_attackers() -> Array:
	var result: Array = []
	var last_id := -9223372036854775807
	var already_sorted := true
	for unit in units:
		if float(unit.get("hp", 0.0)) > 0.0 and bool(unit.get("combat_enabled", false)):
			var unit_id := int(unit["id"])
			if unit_id < last_id:
				already_sorted = false
			last_id = unit_id
			result.append(unit)
	for building in buildings:
		if float(building.get("hp", 0.0)) > 0.0 and String(building.get("state", "complete")) == "complete" and bool(building.get("combat_enabled", false)):
			var building_id := int(building["id"])
			if building_id < last_id:
				already_sorted = false
			last_id = building_id
			result.append(building)
	if not already_sorted:
		result.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	return result

func find_resource(id: int) -> Variant:
	if resource_nodes_by_id.has(id):
		return resource_nodes_by_id[id]
	for building in buildings:
		if int(building.get("id", -1)) == id and bool(building.get("harvestable", false)) and String(building.get("state", "complete")) == "complete" and float(building.get("hp", 0.0)) > 0.0:
			return building
	return null


func resource_accessible_to_team(resource: Dictionary, team: int) -> bool:
	return not bool(resource.get("harvestable", false)) or int(resource.get("team", 0)) == team


func resource_allows_worker(resource: Dictionary, worker: Dictionary) -> bool:
	var allowed_domains: Array = resource.get("allowed_gatherer_domains", [])
	if not resource.has("allowed_gatherer_domains"):
		# Compatibility for old saves and narrow hand-written fixtures.
		allowed_domains = data_repository.runtime_metadata(String(resource.get("kind", ""))).get("allowed_gatherer_domains", [])
	if allowed_domains.is_empty():
		allowed_domains = ["land"]
	return String(worker.get("movement_domain", "land")) in allowed_domains

func update_gather_order(worker: Dictionary, delta: float) -> int:
	return gathering_system.update_gather_order(worker, delta)


func update_dropoff_order(worker: Dictionary, delta: float) -> int:
	return gathering_system.update_dropoff_order(worker, delta)


func gather(resource_id: int, worker: Dictionary) -> float:
	return gathering_system.gather(resource_id, worker)


func deposit_carried_resources(worker: Dictionary) -> int:
	return gathering_system.deposit_carried_resources(worker)


func prepare_resource_approach(worker: Dictionary, resource: Dictionary) -> bool:
	return gathering_system.prepare_resource_approach(worker, resource)


func prepare_group_gather_approach(worker: Dictionary, requested_resource: Dictionary) -> bool:
	return gathering_system.prepare_group_gather_approach(worker, requested_resource)


func resource_approach_candidates(worker: Dictionary, resource: Dictionary, runtime_metadata: Dictionary = {}) -> Array[Vector2]:
	return gathering_system.resource_approach_candidates(worker, resource, runtime_metadata)


func release_resource_approach_slot(worker: Dictionary) -> void:
	gathering_system.release_resource_approach_slot(worker)


func begin_resource_return(worker: Dictionary) -> bool:
	return gathering_system.begin_resource_return(worker)


func nearest_dropoff(worker: Dictionary) -> Variant:
	return gathering_system.nearest_dropoff(worker)


func dropoff_accepts_resource(building: Dictionary, resource_type_id: int, worker_allowed_source_ids: Dictionary = {}) -> bool:
	return gathering_system.dropoff_accepts_resource(building, resource_type_id, worker_allowed_source_ids)


func assign_command_return_resources(selected: Array, target_building_id: int = -1) -> bool:
	return gathering_system.assign_command_return_resources(selected, target_building_id)


func find_building(id: int) -> Variant:
	return buildings_by_id.get(id)


func dropoff_approach_position(worker: Dictionary, building: Dictionary) -> Variant:
	return gathering_system.dropoff_approach_position(worker, building)


func building_perimeter_candidates(worker: Dictionary, building: Dictionary) -> Array[Vector2]:
	var half_size: Vector2 = building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5))
	# Keep all mobile-radius probes outside the whole navigation cell occupied by
	# the building. Half-cell clearance is required even when the visual polygon
	# itself ends earlier inside that cell.
	var padding := float(worker.get("footprint_radius", 0.3)) + 0.55
	var side_fractions := [-0.75, -0.25, 0.25, 0.75]
	var offsets: Array[Vector2] = []
	for fraction in side_fractions:
		offsets.append(Vector2(float(fraction) * half_size.x, -half_size.y - padding))
		offsets.append(Vector2(half_size.x + padding, float(fraction) * half_size.y))
		offsets.append(Vector2(float(fraction) * half_size.x, half_size.y + padding))
		offsets.append(Vector2(-half_size.x - padding, float(fraction) * half_size.y))
	var result: Array[Vector2] = []
	for offset in offsets:
		result.append(Coordinates.clamp_world(Vector2(building["pos"]) + offset, map_size))
	return result


func finish_gather_order(worker: Dictionary, reason: String) -> void:
	gathering_system.finish_gather_order(worker, reason)


func building_cost(kind: String, team: int) -> Dictionary:
	var source := object_record_for(kind, team)
	var stats := unit_stats(kind)
	var result: Dictionary = {}
	for cost_value in source.get("resources", {}).get("cost", stats.get("resource_cost", [])):
		var cost: Dictionary = cost_value
		if not bool(cost.get("enabled", false)) or int(cost.get("type_id", -1)) < 0:
			continue
		result[int(cost["type_id"])] = int(cost.get("amount", 0))
	return apply_object_cost_modifiers(result, int(source.get("unit_id", stats.get("unit_id", -1))), team)


func get_build_options(team: int) -> Array:
	var result: Array = []
	if not data_repository.is_configured():
		return result
	for template_value in _build_option_catalog(team).get("ordered", []):
		result.append(_present_build_option(template_value, team))
	return result


func get_build_options_for_kinds(team: int, kinds: Array) -> Array:
	var result: Array = []
	if not data_repository.is_configured():
		return result
	var seen: Dictionary = {}
	var catalog_by_kind: Dictionary = _build_option_catalog(team).get("by_kind", {})
	for kind_value in kinds:
		var kind := String(kind_value)
		if seen.has(kind):
			continue
		seen[kind] = true
		var template: Dictionary = catalog_by_kind.get(kind, {})
		if not template.is_empty():
			result.append(_present_build_option(template, team))
	_sort_build_options(result)
	return result


func _build_option(team: int, kind: String) -> Dictionary:
	var template: Dictionary = _build_option_catalog(team).get("by_kind", {}).get(kind, {})
	return {} if template.is_empty() else _present_build_option(template, team)


func _build_option_catalog(team: int) -> Dictionary:
	var technology_revision := technology_system.revision(team)
	var cached: Dictionary = build_option_catalog_cache.get(team, {})
	if int(cached.get("technology_revision", -1)) == technology_revision:
		return cached
	var ordered: Array = []
	var by_kind: Dictionary = {}
	for kind_value in data_repository.archetype_aliases("building"):
		var kind := String(kind_value)
		var template := _build_option_template(team, kind)
		if template.is_empty():
			continue
		ordered.append(template)
		by_kind[kind] = template
	_sort_build_options(ordered)
	cached = {
		"technology_revision": technology_revision,
		"ordered": ordered,
		"by_kind": by_kind,
	}
	build_option_catalog_cache[team] = cached
	return cached


func _build_option_template(team: int, kind: String) -> Dictionary:
	if not data_repository.has_archetype(kind) or data_repository.category(kind) != "building":
		return {}
	var base_source_id := int(data_repository.identifiers(kind).get("source_unit_id", -1))
	if base_source_id < 0:
		return {}
	var resolved_source_id: int = int(technology_system.resolved_unit_id(team, base_source_id))
	var source: Dictionary = object_record_by_id(resolved_source_id, team)
	var interface: Dictionary = source.get("interface", {})
	if int(interface.get("button_id", -1)) <= 0:
		return {}
	var required_technology_id := int(data_repository.runtime_metadata(kind).get("required_technology_id", -1))
	if required_technology_id >= 0 and not technology_system.is_researched(team, required_technology_id):
		return {}
	if not is_object_available(team, base_source_id):
		return {}
	var cost := building_cost(kind, team)
	var option_footprint := Footprint.building(unit_stats(kind), Vector2.ZERO)
	var option_half_size := Vector2(option_footprint.get("half_size", Vector2.ONE))
	return {
		"kind": kind,
		"source_unit_id": resolved_source_id,
		"icon_id": int(interface.get("icon_id", -1)),
		"button_id": int(interface.get("button_id", -1)),
		"cost": cost,
		"duration": float(source.get("production", {}).get("creation_time", unit_stats(kind).get("creation_time", 0.0))),
		"footprint_radius": maxf(option_half_size.x, option_half_size.y),
	}


func _present_build_option(template: Dictionary, team: int) -> Dictionary:
	var option := template.duplicate()
	var cost: Dictionary = template.get("cost", {})
	var reason := "" if can_afford_resource_cost(team, cost) else "insufficient_resources"
	option["cost"] = cost.duplicate()
	option["accepted"] = reason.is_empty()
	option["reason"] = reason
	return option


func _sort_build_options(options: Array) -> void:
	options.sort_custom(func(left, right):
		if int(left.get("button_id", 0)) != int(right.get("button_id", 0)):
			return int(left.get("button_id", 0)) < int(right.get("button_id", 0))
		return String(left.get("kind", "")) < String(right.get("kind", ""))
	)


func get_mixed_domain_build_sites(team: int, maximum_per_kind: int = 4) -> Dictionary:
	var result: Dictionary = {}
	if not units.any(func(unit): return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0 and entity_is_worker(unit)):
		return result
	var previous_failure := last_build_failure
	for option_value in get_build_options(team):
		var option: Dictionary = option_value
		if not bool(option.get("accepted", false)):
			continue
		var kind := String(option.get("kind", ""))
		var placement: Dictionary = data_repository.runtime_metadata(kind).get("placement", {})
		var required_domains: Array = placement.get("required_adjacent_domains", [])
		if "water" not in required_domains:
			continue
		var sites: Array = []
		for y in range(map_size.y):
			for x in range(map_size.x):
				var position := Vector2(x + 0.5, y + 0.5)
				if visibility_system.state_at_world(team, position) == FogOfWar.UNKNOWN:
					continue
				if can_place_foundation(team, kind, position):
					sites.append(position)
					if sites.size() >= maximum_per_kind:
						break
			if sites.size() >= maximum_per_kind:
				break
		if not sites.is_empty():
			result[kind] = sites
	last_build_failure = previous_failure
	return result


func get_local_build_sites(team: int, kinds: Array, maximum_per_kind: int = 4, search_radius: int = 12, preferred_sites: Dictionary = {}, strict_preferred_kinds: Array = [], minimum_structure_gap: float = 0.0) -> Dictionary:
	var result: Dictionary = {}
	if kinds.is_empty():
		return result
	var workers: Array = units.filter(func(unit):
		return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0 and entity_is_worker(unit) and String(unit.get("movement_domain", "land")) == "land"
	)
	workers.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	if workers.is_empty():
		return result
	if tick_pipeline.performance_probe != null:
		tick_pipeline.performance_probe.increment("ai.build_site_searches")
	# One synchronous query sees fixed unit positions. Index the exact five
	# occupancy probes once, instead of scanning every unit for every site.
	var mobile_occupied_cells := _mobile_foundation_obstructions()
	var previous_failure := last_build_failure
	for kind_value in kinds:
		var kind := String(kind_value)
		var sites: Array = []
		var fallback_sites: Array = []
		var seen_cells: Dictionary = {}
		for preferred_value in preferred_sites.get(kind, []):
			var preferred_position := Vector2(preferred_value)
			var preferred_cell := Vector2i(floori(preferred_position.x), floori(preferred_position.y))
			if seen_cells.has(preferred_cell) or not navigation_grid.contains(preferred_cell):
				continue
			seen_cells[preferred_cell] = true
			if visibility_system.state_at_world(team, preferred_position) == FogOfWar.UNKNOWN:
				continue
			if building_placement_system.cached_map_supports_foundation(kind, preferred_position) and _can_place_foundation(team, kind, preferred_position, mobile_occupied_cells) and workers.any(func(worker): return worker_can_reach_foundation(worker, kind, preferred_position)):
				if foundation_preserves_structure_gap(team, kind, preferred_position, minimum_structure_gap):
					sites.append(preferred_position)
					if sites.size() >= maximum_per_kind:
						break
				elif fallback_sites.size() < maximum_per_kind:
					fallback_sites.append(preferred_position)
		if kind in strict_preferred_kinds:
			_append_bounded_sites(sites, fallback_sites, maximum_per_kind)
			if not sites.is_empty():
				result[kind] = sites
			continue
		for worker_value in workers:
			var worker: Dictionary = worker_value
			var center := Vector2i(floori(float(worker.get("pos", Vector2.ZERO).x)), floori(float(worker.get("pos", Vector2.ZERO).y)))
			for radius in range(1, maxi(1, search_radius) + 1):
				for y in range(center.y - radius, center.y + radius + 1):
					# Preserve row-major ring order without visiting its interior.
					var columns: Array = range(center.x - radius, center.x + radius + 1) if absi(y - center.y) == radius else [center.x - radius, center.x + radius]
					for x in columns:
						var cell := Vector2i(x, y)
						if seen_cells.has(cell) or not navigation_grid.contains(cell):
							continue
						seen_cells[cell] = true
						var position := Vector2(cell) + Vector2(0.5, 0.5)
						if building_placement_system.cached_map_supports_foundation(kind, position) and _can_place_foundation(team, kind, position, mobile_occupied_cells) and worker_can_reach_foundation(worker, kind, position):
							if foundation_preserves_structure_gap(team, kind, position, minimum_structure_gap):
								sites.append(position)
								if sites.size() >= maximum_per_kind:
									break
							elif fallback_sites.size() < maximum_per_kind:
								fallback_sites.append(position)
					if sites.size() >= maximum_per_kind:
						break
				if sites.size() >= maximum_per_kind:
					break
			if sites.size() >= maximum_per_kind:
				break
		_append_bounded_sites(sites, fallback_sites, maximum_per_kind)
		if not sites.is_empty():
			result[kind] = sites
	last_build_failure = previous_failure
	return result


func get_cached_local_build_sites(team: int, kinds: Array, tick: int, maximum_age_ticks: int, maximum_per_kind: int = 4, search_radius: int = 12, preferred_sites: Dictionary = {}, strict_preferred_kinds: Array = [], minimum_structure_gap: float = 0.0) -> Dictionary:
	if not task_coordinator.is_enabled("ai_observation") or kinds.is_empty():
		return _get_cached_local_build_sites_sequential(team, kinds, tick, maximum_age_ticks, maximum_per_kind, search_radius, preferred_sites, strict_preferred_kinds, minimum_structure_gap)
	if kinds.size() < 2:
		return _get_cached_local_build_sites_sequential(team, kinds, tick, maximum_age_ticks, maximum_per_kind, search_radius, preferred_sites, strict_preferred_kinds, minimum_structure_gap)
	var dependencies := _build_site_query_dependencies(team)
	var queries: Array = []
	var records: Array = []
	var result: Dictionary = {}
	var query_cache_hits := 0
	for kind_value in kinds:
		var kind := String(kind_value)
		var preferred: Dictionary = {kind: preferred_sites.get(kind, [])}
		var strict: Array = [kind] if kind in strict_preferred_kinds else []
		var cache_key := hash([team, kind, maximum_per_kind, search_radius, preferred, strict, minimum_structure_gap])
		var signature := hash([dependencies, can_afford_resource_cost(team, building_cost(kind, team))])
		var cached: Dictionary = local_build_site_cache.get(cache_key, {})
		if not cached.is_empty() and tick >= int(cached.get("tick", -1)) and tick - int(cached.get("tick", -1)) <= maxi(0, maximum_age_ticks) and int(cached.get("query_signature", -1)) == signature:
			if cached.get("sites", {}).has(kind):
				result[kind] = cached["sites"][kind].duplicate()
			query_cache_hits += 1
			continue
		queries.append({"team": team, "kind": kind, "maximum": maximum_per_kind, "radius": search_radius, "preferred": preferred, "strict": strict, "gap": minimum_structure_gap})
		records.append({"kind": kind, "key": cache_key, "signature": signature})
	# A single kind keeps the serial early exit at the first sufficient worker.
	# Capturing the full map and speculating over all worker rings costs more
	# than this query, including after a topology revision.
	if queries.size() == 1:
		return _get_cached_local_build_sites_sequential(team, kinds, tick, maximum_age_ticks, maximum_per_kind, search_radius, preferred_sites, strict_preferred_kinds, minimum_structure_gap)
	if tick_pipeline.performance_probe != null:
		tick_pipeline.performance_probe.increment("ai.build_site_cache_hits", query_cache_hits)
	if queries.is_empty():
		return result
	var capture_started := Time.get_ticks_usec()
	var base := BuildSiteTask.capture(self, team, kinds)
	var placement = building_placement_system
	var static_cache_current: bool = placement.site_map_source == navigation_grid and placement.site_map_revision == navigation_grid.revision
	for query in queries:
		query["base"] = base
		query["static_cache"] = TaskData.copy(placement.site_map_cache.get(query["kind"], {})) if static_cache_current else {}
		query["static_profiles"] = {query["kind"]: TaskData.copy(placement.site_footprint_profiles[query["kind"]])} if static_cache_current and placement.site_footprint_profiles.has(query["kind"]) else {}
	if tick_pipeline.performance_probe != null:
		tick_pipeline.performance_probe.observe_microseconds("presentation.ai.capture.build_sites", Time.get_ticks_usec() - capture_started)
	var outputs := BuildSiteTask.calculate_queries(base, queries, task_coordinator, tick, pathfinder, tick_pipeline.performance_probe)
	if placement.site_map_source != navigation_grid or placement.site_map_revision != navigation_grid.revision:
		placement.invalidate_site_cache()
		placement.site_map_source = navigation_grid
		placement.site_map_revision = navigation_grid.revision
	for index in range(records.size()):
		var record: Dictionary = records[index]
		var output: Dictionary = outputs[index]
		var sites: Dictionary = output.get("sites", {})
		_prune_local_build_site_cache(tick, maximum_age_ticks)
		local_build_site_cache[record["key"]] = {"tick": tick, "query_signature": record["signature"], "sites": TaskData.copy(sites)}
		placement.site_map_cache[record["kind"]] = output.get("static_cache", {})
		placement.site_footprint_profiles.merge(output.get("static_profiles", {}), true)
		if sites.has(record["kind"]):
			result[record["kind"]] = sites[record["kind"]].duplicate()
	# Cache hits and worker completion must not change dictionary insertion order.
	var ordered: Dictionary = {}
	for kind_value in kinds:
		var kind := String(kind_value)
		if result.has(kind):
			ordered[kind] = result[kind]
	return ordered

# Advisory placement requests capture immutable input at the AI source tick.
# Searches run inside the AI worker; the owner never waits for placement jobs.
func capture_ai_build_site_queries(team: int, kinds: Array, tick: int, maximum_age_ticks: int, maximum_per_kind: int, search_radius: int, preferred_sites: Dictionary, strict_preferred_kinds: Array, minimum_structure_gap: float) -> Array:
	var requests: Array = []
	if kinds.is_empty():
		return requests
	var dependencies := _build_site_query_dependencies(team)
	var pending_kinds: Array = []
	for kind_value in kinds:
		var kind := String(kind_value)
		var preferred := {kind: preferred_sites.get(kind, [])}
		var strict: Array = [kind] if kind in strict_preferred_kinds else []
		var cache_key := hash([team, kind, maximum_per_kind, search_radius, preferred, strict, minimum_structure_gap])
		var signature := hash([dependencies, can_afford_resource_cost(team, building_cost(kind, team))])
		var cached: Dictionary = local_build_site_cache.get(cache_key, {})
		var request := {"kind": kind, "cache_key": cache_key, "signature": signature, "team": team}
		if not cached.is_empty() and tick >= int(cached.get("tick", -1)) and tick - int(cached.get("tick", -1)) <= maxi(0, maximum_age_ticks) and int(cached.get("query_signature", -1)) == signature:
			request["cached_sites"] = cached.get("sites", {}).get(kind, []).duplicate()
		else:
			request["input"] = {"team": team, "kind": kind, "maximum": maximum_per_kind, "radius": search_radius, "preferred": preferred, "strict": strict, "gap": minimum_structure_gap}
			pending_kinds.append(kind)
		requests.append(request)
	if not pending_kinds.is_empty():
		var base: Dictionary = BuildSiteTask.capture(self, team, pending_kinds)
		if not TaskData.freeze_detached(base):
			push_error("AI build-site capture must be detached")
		for request in requests:
			if request.has("input"):
				request["input"]["base"] = base
	return requests

func commit_ai_build_site_queries(updates: Array, tick: int) -> void:
	var dependencies_by_team: Dictionary = {}
	# A moved worker, changed occupancy, exploration or technology invalidates
	# a captured search. Build commands also validate the live site/worker.
	for update in updates:
		var team := int(update.get("team", 0))
		var kind := String(update.get("kind", ""))
		if not dependencies_by_team.has(team):
			dependencies_by_team[team] = _build_site_query_dependencies(team)
		var signature := hash([dependencies_by_team[team], can_afford_resource_cost(team, building_cost(kind, team))])
		if kind.is_empty() or signature != int(update.get("signature", -1)):
			continue
		local_build_site_cache[int(update["cache_key"])] = {"tick": tick, "query_signature": signature, "sites": TaskData.copy(update.get("sites", {}))}
		_prune_local_build_site_cache(tick, 1200)

func _get_cached_local_build_sites_sequential(team: int, kinds: Array, tick: int, maximum_age_ticks: int, maximum_per_kind: int = 4, search_radius: int = 12, preferred_sites: Dictionary = {}, strict_preferred_kinds: Array = [], minimum_structure_gap: float = 0.0) -> Dictionary:
	if kinds.is_empty():
		return {}
	# Retain each kind independently, including empty searches. Other priorities
	# entering/leaving the request must not discard an unchanged failed dock search.
	var dependencies := _build_site_query_dependencies(team)
	var result: Dictionary = {}
	for kind_value in kinds:
		var kind := String(kind_value)
		var preferred: Dictionary = {kind: preferred_sites.get(kind, [])}
		var strict: Array = [kind] if kind in strict_preferred_kinds else []
		var cache_key := hash([team, kind, maximum_per_kind, search_radius, preferred, strict, minimum_structure_gap])
		var signature := hash([dependencies, can_afford_resource_cost(team, building_cost(kind, team))])
		var cached: Dictionary = local_build_site_cache.get(cache_key, {})
		var sites: Dictionary
		if not cached.is_empty() and tick >= int(cached.get("tick", -1)) and tick - int(cached.get("tick", -1)) <= maxi(0, maximum_age_ticks) and int(cached.get("query_signature", -1)) == signature:
			sites = cached.get("sites", {})
			if tick_pipeline.performance_probe != null:
				tick_pipeline.performance_probe.increment("ai.build_site_cache_hits")
		else:
			sites = get_local_build_sites(team, [kind], maximum_per_kind, search_radius, preferred, strict, minimum_structure_gap)
			_prune_local_build_site_cache(tick, maximum_age_ticks)
			local_build_site_cache[cache_key] = {"tick": tick, "query_signature": signature, "sites": sites.duplicate(true)}
		if sites.has(kind):
			result[kind] = sites[kind].duplicate()
	return result


func _build_site_query_dependencies(team: int) -> Array:
	var workers: Array = []
	for unit_value in units:
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0 and entity_is_worker(unit) and String(unit.get("movement_domain", "land")) == "land":
			workers.append([int(unit.get("id", -1)), unit.get("pos", Vector2.ZERO), unit.get("footprint_radius", 0.3), unit.get("terrain_restriction", -1)])
	var mobile_cells: Array = _mobile_foundation_obstructions().keys()
	mobile_cells.sort_custom(func(left, right): return left.y < right.y or (left.y == right.y and left.x < right.x))
	var structures: Array = []
	for building_value in buildings:
		var building: Dictionary = building_value
		if float(building.get("hp", 0.0)) > 0.0:
			structures.append([building.get("id", -1), building.get("team", 0), building.get("pos", Vector2.ZERO), building.get("footprint", {}), building.get("occupied_cells", []), building.get("footprint_radius", 1.0)])
	return [navigation_grid.get_instance_id(), navigation_grid.revision, technology_system.revision(team), fog_of_war.exploration_revision_for_player(team), workers, mobile_cells, structures]


func _prune_local_build_site_cache(tick: int, maximum_age_ticks: int) -> void:
	for key in local_build_site_cache.keys():
		var cached: Dictionary = local_build_site_cache[key]
		var cached_tick := int(cached.get("tick", -1))
		if cached_tick > tick or tick - cached_tick > maxi(0, maximum_age_ticks):
			local_build_site_cache.erase(key)
	while local_build_site_cache.size() >= MAX_LOCAL_BUILD_SITE_CACHE_ENTRIES:
		var oldest_key = local_build_site_cache.keys()[0]
		var oldest_tick := int(local_build_site_cache[oldest_key].get("tick", -1))
		for key in local_build_site_cache:
			var cached_tick := int(local_build_site_cache[key].get("tick", -1))
			if cached_tick < oldest_tick:
				oldest_key = key
				oldest_tick = cached_tick
		local_build_site_cache.erase(oldest_key)


func _append_bounded_sites(sites: Array, fallback_sites: Array, maximum: int) -> void:
	for fallback_position in fallback_sites:
		if sites.size() >= maximum:
			break
		sites.append(fallback_position)


func foundation_preserves_structure_gap(team: int, kind: String, position: Vector2, minimum_gap: float) -> bool:
	return building_placement_system.foundation_preserves_structure_gap(team, kind, position, minimum_gap)


func can_place_foundation(team: int, kind: String, position: Vector2) -> bool:
	return building_placement_system.can_place_foundation(team, kind, position)


func _can_place_foundation(team: int, kind: String, position: Vector2, mobile_occupied_cells: Variant = null) -> bool:
	return building_placement_system.can_place_foundation(team, kind, position, mobile_occupied_cells)


func _mobile_foundation_obstructions() -> Dictionary:
	return building_placement_system.mobile_foundation_obstructions()


func mobile_footprint_overlaps_cells(unit: Dictionary, occupied_cells: Array) -> bool:
	return building_placement_system.mobile_footprint_overlaps_cells(unit, occupied_cells)


func map_supports_foundation(kind: String, position: Vector2) -> bool:
	return building_placement_system.map_supports_foundation(kind, position)


func foundation_map_audit(kind: String, position: Vector2) -> Dictionary:
	return building_placement_system.foundation_map_audit(kind, position)


func foundation_has_required_domain_access(footprint: Dictionary, placement: Dictionary) -> bool:
	return building_placement_system.foundation_has_required_domain_access(footprint, placement)


func worker_can_reach_foundation(worker: Dictionary, kind: String, position: Vector2) -> bool:
	return building_placement_system.worker_can_reach_foundation(worker, kind, position)


func reachable_builder_ids(building: Dictionary) -> Array[int]:
	return building_placement_system.reachable_builder_ids(building)


func place_foundation(team: int, kind: String, position: Vector2, workers: Array = []) -> Variant:
	return foundation_system.place_foundation(team, kind, position, workers)


func cancel_foundation(building_id: int) -> bool:
	return foundation_system.cancel_foundation(building_id)


func assign_command_build(selected: Array, kind: String, position: Vector2) -> Variant:
	return foundation_system.assign_command_build(selected, kind, position)


func reseed_harvestable_building(building: Dictionary, workers: Array = []) -> Variant:
	return foundation_system.reseed_harvestable_building(building, workers)


func assign_command_repair(selected: Array, building_id: int) -> bool:
	return construction_system.assign_command_repair(selected, building_id)


func can_worker_repair(worker: Dictionary, target: Dictionary) -> bool:
	return construction_system.can_worker_repair(worker, target)


func assign_workers_to_building(selected: Array, building: Dictionary, order_type: String) -> void:
	construction_system.assign_workers_to_building(selected, building, order_type)


func update_building_order(worker: Dictionary, delta: float) -> Dictionary:
	return construction_system.update_building_order(worker, delta)


func advance_repair(worker: Dictionary, target: Dictionary, requested_hp: float) -> float:
	return construction_system.advance_repair(worker, target, requested_hp)


func complete_foundation(building: Dictionary) -> void:
	foundation_system.complete_foundation(building)


func activate_building_completion(building: Dictionary) -> void:
	foundation_system.activate_building_completion(building)


func configure_harvestable_building(building: Dictionary, completed: bool) -> void:
	foundation_system.configure_harvestable_building(building, completed)


func activate_harvestable_building(building: Dictionary) -> void:
	foundation_system.activate_harvestable_building(building)


func harvestable_amount_for(kind: String, team: int) -> int:
	return foundation_system.harvestable_amount_for(kind, team)


func population_support_for(kind: String, team: int) -> int:
	return foundation_system.population_support_for(kind, team)


func activate_population_support(building: Dictionary) -> void:
	foundation_system.activate_population_support(building)


func deactivate_population_support(building: Dictionary) -> void:
	foundation_system.deactivate_population_support(building)


func reserve_building_approach_slot(worker: Dictionary, building: Dictionary) -> Variant:
	return construction_system.reserve_building_approach_slot(worker, building)


func prepare_building_approach(worker: Dictionary, building: Dictionary) -> bool:
	return construction_system.prepare_building_approach(worker, building)


func assign_reachable_approach_slot(worker: Dictionary, candidates: Array[Vector2], reservations: Dictionary, respect_footprints: bool = false) -> Variant:
	return approach_system.assign_reachable_slot(worker, candidates, reservations, respect_footprints)


func _assign_reachable_approach_slot(worker: Dictionary, candidates: Array[Vector2], reservations: Dictionary, respect_footprints: bool = false) -> Variant:
	return approach_system.assign_reachable_slot(worker, candidates, reservations, respect_footprints)


func available_approach_slots(worker: Dictionary, candidates: Array[Vector2], reservations: Dictionary, respect_footprints: bool = false) -> Array[Vector2]:
	return approach_system.available_slots(worker, candidates, reservations, respect_footprints)


func _available_approach_slots(worker: Dictionary, candidates: Array[Vector2], reservations: Dictionary, respect_footprints: bool = false) -> Array[Vector2]:
	return approach_system.available_slots(worker, candidates, reservations, respect_footprints)


func _resource_approach_slot_occupied(worker: Dictionary, candidate: Vector2) -> bool:
	return approach_system.resource_slot_occupied(worker, candidate)


func resume_approach(worker: Dictionary, slot: Vector2) -> bool:
	return approach_system.resume(worker, slot)


func _resume_approach(worker: Dictionary, slot: Vector2) -> bool:
	return approach_system.resume(worker, slot)


func release_building_approach_slot(worker: Dictionary) -> void:
	construction_system.release_building_approach_slot(worker)


func finish_building_order(worker: Dictionary, reason: String) -> void:
	construction_system.finish_building_order(worker, reason)


func update_resource_state(resource: Dictionary) -> void:
	gathering_system.update_resource_state(resource)


func advance_resource_lifecycle(delta: float) -> void:
	gathering_system.advance_resource_lifecycle(delta)


func _update_huntable_reaction(unit: Dictionary) -> void:
	if int(unit.get("retaliation_target_id", -1)) < 0 or not entity_has_behavior_tag(unit, "huntable"):
		return
	var attacker: Variant = find_unit(int(unit.get("retaliation_target_id", -1)))
	if attacker == null or float(attacker.get("hp", 0.0)) <= 0.0:
		unit["retaliation_target_id"] = -1
		return
	match String(data_repository.runtime_metadata(String(unit.get("kind", ""))).get("hunt_behavior", "flee")):
		"retaliate", "predator":
			if String(unit.get("task", "idle")) != "attack":
				assign_command_attack([unit], int(attacker["id"]), {"trigger": "huntable_retaliation"})
		"flee":
			var away := Vector2(unit.get("pos", Vector2.ZERO)) - Vector2(attacker.get("pos", Vector2.ZERO))
			if away.length_squared() <= 0.0001:
				away = Vector2.RIGHT.rotated(float(int(unit.get("id", 0)) % 8) * PI / 4.0)
			var destination := Coordinates.clamp_world(Vector2(unit["pos"]) + away.normalized() * 3.0, map_size)
			assign_command_move([unit], destination)
			unit["diagnostic_reason"] = "huntable_flee"
	unit["retaliation_target_id"] = -1

func assign_command_move(selected: Array, target: Vector2) -> bool:
	return movement_system.assign_command_move(selected, target)


func assign_command_attack_move(selected: Array, target: Vector2) -> bool:
	return movement_system.assign_command_attack_move(selected, target)

func assign_unit_destination(unit: Dictionary, destination: Vector2, reserve_destination: bool = true, prevalidated_direct: bool = false) -> bool:
	return movement_system.assign_unit_destination(unit, destination, reserve_destination, prevalidated_direct)

func assign_unit_waypoints(unit: Dictionary, waypoints: Array[Vector2], destination: Vector2, prevalidated_direct: bool = false, open_envelope: Dictionary = {}) -> bool:
	return movement_system.assign_unit_waypoints(unit, waypoints, destination, prevalidated_direct, open_envelope)

func ensure_navigation_destination(unit: Dictionary, destination: Vector2) -> void:
	movement_system.ensure_navigation_destination(unit, destination)


func can_attack_ground(unit: Dictionary) -> bool:
	return combat_system.can_attack_ground(unit)


func attack_ground_target(position: Vector2) -> Dictionary:
	return combat_system.attack_ground_target(position)


func assign_command_attack_ground(selected: Array, target: Vector2) -> bool:
	return combat_system.assign_command_attack_ground(selected, target)

func assign_command_attack(selected: Array, target_id: int, policy: Dictionary = {}) -> bool:
	return combat_system.assign_command_attack(selected, target_id, policy)


func assign_command_convert(selected: Array, target_id: int) -> String:
	return conversion_system.assign_command(selected, target_id)


func conversion_destination(converter: Dictionary, target: Dictionary) -> Variant:
	return conversion_system.conversion_destination(converter, target)


func finish_conversion(converter: Dictionary, reason: String) -> void:
	conversion_system.finish_conversion(converter, reason)


func assign_command_heal(selected: Array, target_id: int) -> String:
	return healing_system.assign_command(selected, target_id)


func finish_healing(healer: Dictionary, reason: String, completed: bool = false) -> void:
	healing_system.finish_healing(healer, reason, completed)


func apply_martyrdom(selected: Array) -> String:
	return conversion_system.apply_martyrdom(selected)


func board_units(passengers: Array, transport: Dictionary) -> String:
	return transport_system.board(passengers, transport)


func unload_transports(transports: Array, target: Vector2, passenger_ids: Array = []) -> String:
	return transport_system.unload(transports, target, passenger_ids)


func set_trade_resource(traders: Array, resource_type_id: int) -> String:
	return trade_system.set_resource(traders, resource_type_id)


func pay_tribute(sender_team: int, recipient_team: int, resource_type_id: int, amount: int) -> String:
	if sender_team <= 0 or not player_registry.players.has(sender_team):
		return "invalid_issuer"
	if recipient_team <= 0 or recipient_team == sender_team or not player_registry.players.has(recipient_team):
		return "invalid_tribute_recipient"
	if player_registry.status(sender_team) != PlayerRegistry.ACTIVE or player_registry.status(recipient_team) != PlayerRegistry.ACTIVE:
		return "player_not_active"
	if not are_teams_allied(sender_team, recipient_team):
		return "tribute_requires_ally"
	if resource_type_id not in [0, 1, 2, 3]:
		return "invalid_tribute_resource"
	if amount <= 0:
		return "invalid_tribute_amount"
	if economy_system.get_resource_amount(sender_team, resource_type_id) < amount:
		return "insufficient_resources"
	var tax := technology_system.tribute_tax(sender_team)
	var received := clampi(floori(float(amount) * (1.0 - tax) + 0.000001), 0, amount)
	# Validate everything before either balance is changed; the two mutations
	# and one fog-neutral event form one deterministic simulation transaction.
	economy_system.change_resource_amount(sender_team, resource_type_id, -amount)
	economy_system.change_resource_amount(recipient_team, resource_type_id, received)
	_emit_domain_event("tribute_paid", {
		"sender_team": sender_team,
		"recipient_team": recipient_team,
		"resource_type_id": resource_type_id,
		"amount_sent": amount,
		"amount_received": received,
		"tax_lost": amount - received,
	})
	return ""


func assign_builders_to_next_visible_foundation(builder_ids: Array, completed_building_id: int) -> void:
	foundation_system.assign_builders_to_next_visible_foundation(builder_ids, completed_building_id)


func _assign_builders_to_next_visible_foundation(builder_ids: Array, completed_building_id: int) -> void:
	foundation_system.assign_builders_to_next_visible_foundation(builder_ids, completed_building_id)
func assign_command_trade(traders: Array, target_dock: Dictionary) -> String:
	return trade_system.start_route(traders, target_dock)


func get_trade_goods(team: int) -> float:
	return trade_system.trade_goods(team)


func transfer_entity_ownership(entity: Dictionary, new_team: int, converter_id: int = -1, ownership_reason: String = "conversion", allow_neutral_owner: bool = false) -> bool:
	if entity == null or new_team <= 0 or float(entity.get("hp", 0.0)) <= 0.0:
		return false
	var old_team := int(entity.get("team", 0))
	if (old_team <= 0 and not allow_neutral_owner) or (old_team > 0 and are_teams_allied(old_team, new_team)):
		return false
	var entity_id := int(entity.get("id", -1))
	var is_building := find_building(entity_id) != null
	if is_building:
		if bool(entity.get("harvestable", false)):
			resource_approach_slots.erase(entity_id)
			for worker in units:
				if int(worker.get("resource_id", -1)) == entity_id:
					finish_gather_order(worker, "resource_owner_changed")
		production_system.abort_for_building_loss(entity_id)
		deactivate_population_support(entity)
	else:
		halt_unit(entity, "converted" if ownership_reason == "conversion" else ownership_reason)
		if old_team > 0 and not bool(entity.get("population_released", false)):
			var population_points_cost := int(entity.get("population_points_cost", int(entity.get("population_cost", 0)) * SimulationEconomySystem.POPULATION_POINT_SCALE))
			economy_system.add_population_points(old_team, -population_points_cost)
		if not bool(entity.get("population_released", false)):
			entity["population_points_cost"] = expected_population_points_cost(entity, new_team)
			economy_system.add_population_points(new_team, int(entity["population_points_cost"]))
	player_registry.ensure(new_team, int(civilization_by_team.get(new_team, 13)))
	entity["team"] = new_team
	track_conquest_entity(entity)
	if not is_building and transport_system.is_transport(entity):
		transport_system.reconcile_ownership(entity)
	entity["selected"] = false
	var owner_history: Array = entity.get("owner_history", [old_team]).duplicate()
	owner_history.append(new_team)
	entity["owner_history"] = owner_history
	if ownership_reason == "conversion":
		entity["conversion_origin_team"] = int(entity.get("conversion_origin_team", old_team))
		entity["conversion_owner_history"] = owner_history.duplicate()
		entity["technology_locked"] = true
	var ownership: Dictionary = entity.get("components", {}).get("ownership", {})
	ownership["player_id"] = new_team
	ownership["team_id"] = new_team
	# civilization_id and source identity intentionally remain unchanged. RoR
	# conversions preserve the captured object's statistics and appearance.
	if is_building:
		activate_population_support(entity)
		sync_building_victory_objective(entity)
		refresh_building_connectivity()
	else:
		sync_unit_victory_objective(entity)
	EntityComponents.sync_dynamic(entity)
	update_fog_of_war()
	_emit_domain_event("ownership_changed", {
		"entity_id": entity_id,
		"old_team": old_team,
		"new_team": new_team,
		"converter_id": converter_id,
		"ownership_reason": ownership_reason,
		"technology_locked": bool(entity.get("technology_locked", false)),
	})
	return true

func assign_command_gather(selected: Array, target_id: int) -> void:
	gathering_system.assign_command(selected, target_id)

func release_unit_destination(unit: Dictionary) -> void:
	movement_system.release_unit_destination(unit)

func finish_combat(unit: Dictionary, reason: String = "target_unavailable") -> void:
	combat_system.finish_combat(unit, reason)


func _finish_combat(unit: Dictionary, reason: String = "target_unavailable") -> void:
	combat_system.finish_combat(unit, reason)


func stop_unit_motion(unit: Dictionary) -> void:
	movement_system.stop_unit_motion(unit)


func halt_unit(unit: Dictionary, reason: String = "stopped") -> void:
	if reason in ["stop", "hold", "converted", "unit_died"]:
		OrderPipeline.clear_queued(unit)
	conversion_system.cancel(unit, reason)
	healing_system.cancel(unit, reason)
	trade_system.cancel(unit, reason)
	transport_system.clear_pending_order(unit)
	release_resource_approach_slot(unit)
	release_building_approach_slot(unit)
	unit["task"] = "idle"
	unit["target_id"] = -1
	unit["resource_id"] = -1
	unit["gather_stage"] = "none"
	unit["dropoff_id"] = -1
	unit["dropoff_position"] = null
	unit["target_building_id"] = -1
	unit["retaliation_target_id"] = -1
	unit["pending_hunt_target_id"] = -1
	if entity_is_worker(unit):
		worker_role_system.clear(unit)
	_clear_combat_intent(unit)
	stop_unit_motion(unit)
	restore_formation_facing(unit)
	OrderPipeline.complete(unit, reason)
	EntityComponents.sync_dynamic(unit)


func _clear_combat_intent(unit: Dictionary) -> void:
	unit["combat_pursuit"] = false
	unit["attack_autonomous"] = false
	unit["combat_resume"] = {}
	unit["combat_leash_origin"] = unit.get("pos", Vector2.ZERO)


func clear_combat_intent(unit: Dictionary) -> void:
	_clear_combat_intent(unit)

func _release_finished_combat_reservations() -> void:
	combat_system.release_finished_combat_reservations()

func train_unit(team: int, kind: String, near: Vector2) -> bool:
	return production_system.train_unit(team, kind, near)


func unit_resource_cost(kind: String, team: int) -> Dictionary:
	var stats := unit_stats(kind)
	var source := object_record_for(kind, team)
	var result: Dictionary = {}
	for cost_value in source.get("resources", {}).get("cost", stats.get("resource_cost", [])):
		var cost: Dictionary = cost_value
		if bool(cost.get("enabled", false)) and int(cost.get("type_id", -1)) >= 0:
			result[int(cost["type_id"])] = int(cost.get("amount", 0))
	return apply_object_cost_modifiers(result, int(source.get("unit_id", stats.get("unit_id", -1))), team)


func apply_object_cost_modifiers(base_cost: Dictionary, source_unit_id: int, team: int) -> Dictionary:
	var result := base_cost.duplicate(true)
	var source := object_record_by_id(source_unit_id, team)
	var unit_class := int(source.get("unit_class", -1))
	var resolved_id := technology_system.resolved_unit_id(team, source_unit_id)
	for command_value in technology_system.persistent_entity_effects(team):
		var command: Dictionary = command_value
		if int(command.get("attr_c", -1)) != 100:
			continue
		var target_id := int(command.get("attr_a", -1))
		var target_class := int(command.get("attr_b", -1))
		if target_id >= 0 and target_id not in [source_unit_id, resolved_id]:
			continue
		if target_id < 0 and target_class != unit_class:
			continue
		var raw_type := int(command.get("type_id", -1))
		var effect_type := raw_type % 10 if raw_type >= 10 and raw_type < 30 else raw_type
		for resource_id in result.keys():
			result[resource_id] = maxi(0, roundi(apply_effect_operator(float(result[resource_id]), effect_type, float(command.get("attr_d", 0.0)))))
	return result


func unit_population_cost(kind: String, team: int) -> int:
	var stats := unit_stats(kind)
	var source := object_record_for(kind, team)
	for cost_value in source.get("resources", {}).get("cost", stats.get("resource_cost", [])):
		var cost: Dictionary = cost_value
		if int(cost.get("type_id", -1)) == 4:
			return maxi(0, int(cost.get("amount", 0)))
	return 0


func unit_population_points_cost(kind: String, team: int) -> int:
	var source := object_record_for(kind, team)
	var source_id := int(source.get("unit_id", unit_stats(kind).get("unit_id", -1)))
	var probe := {
		"source_unit_id": technology_system.resolved_unit_id(team, source_id),
		"population_base_cost": unit_population_cost(kind, team),
	}
	return expected_population_points_cost(probe, team)


func expected_population_points_cost(entity: Dictionary, team: int) -> int:
	var points := maxi(0, int(entity.get("population_base_cost", entity.get("population_cost", 0)))) * SimulationEconomySystem.POPULATION_POINT_SCALE
	var matching_entity := entity
	if int(entity.get("team", 0)) != team:
		matching_entity = entity.duplicate()
		matching_entity["team"] = team
	for effect_value in technology_system.persistent_entity_effects(team):
		var effect: Dictionary = effect_value
		if int(effect.get("attr_c", -1)) != 101 or not technology_effect_matches_entity(matching_entity, effect):
			continue
		var raw_type := int(effect.get("type_id", -1))
		var effect_type := raw_type % 10 if raw_type >= 10 and raw_type < 30 else raw_type
		var value := float(effect.get("attr_d", 0.0))
		match effect_type:
			0:
				points = roundi(absf(value) * float(SimulationEconomySystem.POPULATION_POINT_SCALE))
			4:
				points += roundi(value * float(SimulationEconomySystem.POPULATION_POINT_SCALE))
			5, 6:
				points = roundi(float(points) * value)
	return maxi(0, points)


func reconcile_unit_population_points(entity: Dictionary) -> void:
	var old_points := int(entity.get("population_points_cost", int(entity.get("population_cost", 0)) * SimulationEconomySystem.POPULATION_POINT_SCALE))
	var new_points := expected_population_points_cost(entity, int(entity.get("team", 0)))
	entity["population_points_cost"] = new_points
	if bool(entity.get("population_accounted", false)) and not bool(entity.get("population_released", false)):
		economy_system.add_population_points(int(entity.get("team", 0)), new_points - old_points)


func production_building_for(team: int, kind: String = "") -> Variant:
	return production_system.production_building_for(team, kind)


func enqueue_unit_production(building_id: int, team: int, kind: String) -> Variant:
	return production_system.enqueue_unit(building_id, team, kind)


func get_unit_production_options(building_id: int, team: int) -> Array:
	return production_system.unit_options(building_id, team)


func get_unit_production_availability(building_id: int, team: int, kind: String) -> Dictionary:
	return production_system.unit_availability(building_id, team, kind)


func get_research_options(building_id: int, team: int) -> Array:
	return production_system.research_options(building_id, team)


func get_research_availability(building_id: int, team: int, technology_id: int) -> Dictionary:
	return production_system.research_availability(building_id, team, technology_id)


func enqueue_research(building_id: int, team: int, technology_id: int) -> Variant:
	return production_system.enqueue_research(building_id, team, technology_id)


func update_production(delta: float) -> void:
	production_system.update(delta)


func cancel_production(building_id: int, queue_index: int = 0) -> bool:
	return production_system.cancel(building_id, queue_index)


func stop_waiting_production(building_id: int) -> bool:
	return production_system.stop_waiting(building_id)


func set_rally_point(building_id: int, target: Vector2) -> bool:
	return production_system.set_rally_point(building_id, target)


func free_spawn_position(building: Dictionary, kind: String) -> Variant:
	return production_system.free_spawn_position(building, kind)


func can_afford_resource_cost(team: int, cost: Dictionary) -> bool:
	return economy_system.can_afford(team, cost)


func spend_resource_cost(team: int, cost: Dictionary) -> void:
	economy_system.spend(team, cost)


func refund_resource_cost(team: int, cost: Dictionary) -> void:
	economy_system.refund(team, cost)


func get_resource_amount(team: int, resource_id: int) -> int:
	return economy_system.get_resource_amount(team, resource_id)


func set_resource_amount(team: int, resource_id: int, amount: int) -> void:
	economy_system.set_resource_amount(team, resource_id, amount)


func change_resource_amount(team: int, resource_id: int, delta: int) -> void:
	economy_system.change_resource_amount(team, resource_id, delta)


func apply_technology_commands(team: int, commands: Array, resolve_automatic: bool = true) -> void:
	attack_animation_spec_cache.clear()
	var upgraded_entities: Array[Dictionary] = []
	var upgraded_entity_ids: Dictionary = {}
	var changes_population_cost := false
	for command_value in commands:
		var command: Dictionary = command_value
		if int(command.get("attr_c", -1)) == 101:
			changes_population_cost = true
		var raw_type := int(command.get("type_id", -1))
		var effect_type := raw_type
		if effect_type in [10, 11, 12, 13, 14, 15, 16]:
			effect_type -= 10
		elif effect_type in [20, 21, 22, 23, 24, 25, 26]:
			effect_type -= 20
		match effect_type:
			0, 4, 5:
				for entity in get_all_units_including_embarked() + buildings:
					if int(entity.get("team", 0)) == team:
						apply_attribute_effect(entity, command)
			1, 6:
				apply_resource_effect(team, command, effect_type)
			3:
				var source_id := int(command.get("attr_a", -1))
				var target_id := int(command.get("attr_b", -1))
				for entity in get_all_units_including_embarked() + buildings:
					if int(entity.get("team", 0)) == team and not bool(entity.get("technology_locked", false)) and entity.get("unit_lineage", []).has(source_id):
						apply_unit_upgrade_to_entity(entity, target_id, false)
						var entity_id := int(entity.get("id", -1))
						if not upgraded_entity_ids.has(entity_id):
							upgraded_entity_ids[entity_id] = true
							upgraded_entities.append(entity)
	# An upgrade replaces the source-owned base values. Rebuild every upgraded
	# entity once after the complete bundle, then apply all persistent modifiers
	# exactly once so pre-existing and newly produced units remain equivalent.
	for entity in upgraded_entities:
		apply_unit_upgrade_to_entity(entity, int(entity.get("source_unit_id", -1)), false)
		for persistent_value in technology_system.persistent_entity_effects(team):
			apply_attribute_effect(entity, persistent_value)
		configure_entity_combat_awareness(entity)
	if changes_population_cost:
		for entity in get_all_units_including_embarked():
			if int(entity.get("team", 0)) == team:
				reconcile_unit_population_points(entity)
	var researched := technology_system.researched_ids(team)
	for entity in get_all_units_including_embarked() + buildings:
		if int(entity.get("team", 0)) == team and not bool(entity.get("technology_locked", false)):
			entity.get("components", {}).get("technology", {})["researched_ids"] = researched.duplicate()
			_sync_building_age_presentation(entity)
	if not is_bulk_loading():
		# Age upgrades can change building footprints (Town Center variants);
		# each upgraded building reconciles only its own cells.
		for entity in upgraded_entities:
			if buildings_by_id.has(int(entity.get("id", -1))):
				_sync_building_navigation_occupancy(entity)
	if resolve_automatic:
		resolve_automatic_technologies(team)
	_sync_shared_vision(team)
	# Faith recharge rate is a team rule, not a per-tick behavior. Refresh it at
	# the rule-change boundary so fully charged idle converters need no update.
	for unit_value in get_all_units_including_embarked():
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) != team or not conversion_system.is_converter(unit):
			continue
		var conversion: Dictionary = unit.get("components", {}).get("conversion", {})
		conversion["recharge_rate"] = conversion_system.recharge_rate_for(unit)


func resolve_automatic_technologies(team: int, emit_events: bool = true) -> Array[int]:
	var completed: Array[int] = []
	while true:
		var available := technology_system.available_automatic_technology_ids(team)
		if available.is_empty():
			break
		for technology_id in available:
			if technology_system.can_research(team, int(technology_id)) != "":
				continue
			apply_technology_commands(team, technology_system.complete_research(team, int(technology_id)), false)
			completed.append(int(technology_id))
			if emit_events:
				_emit_domain_event("automatic_technology_complete", {
					"technology_id": int(technology_id),
					"team": team,
				})
	return completed


func set_starting_age(team: int, technology_id: int, post_iron: bool = false) -> void:
	var target := clampi(technology_id, 100, 103)
	for age_technology_id in range(101, target + 1):
		apply_technology_commands(team, technology_system.complete_research(team, age_technology_id), false)
	var maximum_completed_age := target if post_iron else target - 1
	if maximum_completed_age >= 100:
		for completed_technology_id in technology_system.starting_technology_ids(team, maximum_completed_age):
			apply_technology_commands(team, technology_system.complete_research(team, int(completed_technology_id)), false)
	resolve_automatic_technologies(team, false)


func apply_scenario_technology_nodes(team: int, nodes: Array) -> void:
	for node_value in nodes:
		var node: Dictionary = node_value
		if String(node.get("kind", "")) == "age":
			technology_system.disable_technology(team, int(node.get("technology_id", -1)))
			continue
		var source_object_id := int(node.get("source_object_id", -1))
		if source_object_id < 0:
			continue
		technology_system.disable_scenario_object(team, source_object_id)
		for key in object_catalog_data.get("technologies", {}):
			var technology: Dictionary = object_catalog_data["technologies"][key]
			if int(technology.get("research_location_id", -1)) == source_object_id:
				technology_system.disable_technology(team, int(key))
		for record_value in object_catalog_data.get("objects", {}).values():
			var record: Dictionary = record_value
			if int(record.get("production", {}).get("train_location_id", -1)) == source_object_id:
				technology_system.disable_scenario_object(team, int(record.get("unit_id", -1)))


func apply_technology_state_to_entity(entity: Dictionary, team: int) -> void:
	var source_id := int(entity.get("source_unit_id", -1))
	var resolved_id := technology_system.resolved_unit_id(team, source_id)
	if resolved_id >= 0 and resolved_id != source_id:
		apply_unit_upgrade_to_entity(entity, resolved_id, false)
	for command_value in technology_system.persistent_entity_effects(team):
		# Stone Age's source DAT bundle encodes the base Town Center facet as
		# attribute 17 value 1. The base graphic already represents that facet;
		# retaining it as an explicit override makes a newly created building look
		# age-modified. Later ages still apply their declared facet normally.
		if technology_system.current_age(team) == 100 and int(command_value.get("attr_c", -1)) == 17:
			continue
		apply_attribute_effect(entity, command_value)
	entity.get("components", {}).get("technology", {})["researched_ids"] = technology_system.researched_ids(team)
	_sync_building_age_presentation(entity)


func _sync_building_age_presentation(entity: Dictionary) -> void:
	# Original age technologies use attribute 17 to select the packed building
	# facet. apply_attribute_effect owns that value for every civilization and
	# every affected building; this hook only normalizes restored state.
	if entity.has("presentation_facing"):
		entity["presentation_facing"] = maxi(0, int(entity["presentation_facing"]))


func sync_building_age_presentation(entity: Dictionary) -> void:
	_sync_building_age_presentation(entity)


func apply_unit_upgrade_to_entity(entity: Dictionary, target_unit_id: int, reapply_persistent_effects: bool = true) -> void:
	if bool(entity.get("technology_locked", false)):
		return
	var team := int(entity.get("team", 0))
	var active_worker_profile: Dictionary = entity.get("worker_role_profile", {}).duplicate(true)
	var active_worker_combat := int(entity.get("pending_hunt_target_id", -1)) >= 0
	var source := object_record_by_id(target_unit_id, team)
	if source.is_empty():
		return
	var old_max := maxf(0.001, float(entity.get("max_hp", source.get("health", 1.0))))
	var health_ratio := clampf(float(entity.get("hp", old_max)) / old_max, 0.0, 1.0)
	var combat: Dictionary = source.get("combat", {})
	var resources: Dictionary = source.get("resources", {})
	var production: Dictionary = source.get("production", {})
	entity["source_unit_id"] = target_unit_id
	if entity.has("population_released"):
		for cost_value in source.get("resources", {}).get("cost", []):
			var cost: Dictionary = cost_value
			if int(cost.get("type_id", -1)) == 4:
				entity["population_base_cost"] = maxi(0, int(cost.get("amount", 0)))
				break
	if not entity.get("unit_lineage", []).has(target_unit_id):
		entity["unit_lineage"].append(target_unit_id)
	entity["display_graphic_id"] = int(source.get("graphics", {}).get("idle", entity.get("display_graphic_id", -1)))
	entity["max_hp"] = float(source.get("health", old_max))
	entity["hp"] = float(entity["max_hp"]) * health_ratio
	entity["speed"] = float(source.get("speed", entity.get("speed", 0.0)))
	entity["attack_period"] = float(combat.get("attack_period", entity.get("attack_period", 0.0)))
	entity["attack_range_min"] = float(combat.get("range_min", entity.get("attack_range_min", 0.0)))
	entity["attack_range"] = float(combat.get("range_max", entity.get("attack_range", 0.0)))
	entity["blast_range"] = float(combat.get("blast_range", entity.get("blast_range", 0.0)))
	entity["projectile_id"] = int(combat.get("projectile_id", entity.get("projectile_id", -1)))
	var attacks: Array = combat.get("attacks", []).duplicate(true)
	if not attacks.is_empty():
		entity["attack_damage"] = CombatRules.primary_attack_damage(attacks, float(entity.get("attack_damage", 0.0)))
	entity["carry_capacity"] = float(resources.get("capacity", entity.get("carry_capacity", 0.0)))
	entity["corpse_source_id"] = int(source.get("links", {}).get("dead_unit_id", entity.get("corpse_source_id", -1)))
	var components: Dictionary = entity.get("components", {})
	components.get("identity", {})["source_unit_id"] = target_unit_id
	components.get("identity", {})["source_key"] = String(source.get("key", ""))
	components.get("vision", {})["range"] = float(source.get("line_of_sight", components.get("vision", {}).get("range", 0.0)))
	components.get("combat", {})["attacks"] = attacks
	components.get("combat", {})["armors"] = combat.get("armors", []).duplicate(true)
	components.get("combat", {})["base_armor"] = float(combat.get("base_armor", 0.0))
	components.get("combat", {})["attack_period"] = entity["attack_period"]
	components.get("combat", {})["range_min"] = entity["attack_range_min"]
	components.get("combat", {})["range_max"] = entity["attack_range"]
	components.get("combat", {})["blast_range"] = entity["blast_range"]
	components.get("combat", {})["accuracy"] = int(combat.get("accuracy", 0))
	components.get("combat", {})["projectile_id"] = entity["projectile_id"]
	components.get("combat", {})["frame_delay"] = int(combat.get("frame_delay", 0))
	components.get("combat", {})["weapon_offset"] = combat.get("weapon_offset", [0.0, 0.0, 0.0]).duplicate()
	components.get("resource_carrier", {})["capacity"] = entity["carry_capacity"]
	var cargo: Dictionary = components.get("cargo", {})
	if bool(cargo.get("enabled", false)):
		cargo["capacity"] = maxi(cargo.get("passenger_ids", []).size(), roundi(entity["carry_capacity"]))
	components.get("worker", {})["work_rate"] = float(source.get("work_rate", components.get("worker", {}).get("work_rate", 0.0)))
	components.get("production", {})["creation_time"] = int(production.get("creation_time", components.get("production", {}).get("creation_time", 0)))
	components.get("production", {})["train_location_id"] = int(production.get("train_location_id", components.get("production", {}).get("train_location_id", -1)))
	components.get("animation_state", {})["source_graphics"] = source.get("graphics", {}).duplicate(true)
	if not active_worker_profile.is_empty():
		worker_role_system.apply(entity, active_worker_profile, active_worker_combat)
	if reapply_persistent_effects:
		for persistent_value in technology_system.persistent_entity_effects(team):
			apply_attribute_effect(entity, persistent_value)
	if entity.has("population_released"):
		reconcile_unit_population_points(entity)
	configure_entity_combat_awareness(entity)


func apply_attribute_effect(entity: Dictionary, command: Dictionary) -> void:
	if bool(entity.get("technology_locked", false)):
		return
	if not technology_effect_matches_entity(entity, command):
		return
	var raw_type := int(command.get("type_id", -1))
	var effect_type := raw_type % 10 if raw_type >= 10 and raw_type < 30 else raw_type
	var attribute_id := int(command.get("attr_c", -1))
	var value := float(command.get("attr_d", 0.0))
	var components: Dictionary = entity.get("components", {})
	match attribute_id:
		0:
			var old_max := maxf(0.001, float(entity.get("max_hp", 1.0)))
			var ratio := clampf(float(entity.get("hp", old_max)) / old_max, 0.0, 1.0)
			entity["max_hp"] = maxf(1.0, apply_effect_operator(old_max, effect_type, value))
			entity["hp"] = float(entity["max_hp"]) * ratio
		1:
			var vision: Dictionary = components.get("vision", {})
			vision["range"] = maxf(0.0, apply_effect_operator(float(vision.get("range", 0.0)), effect_type, value))
		5:
			entity["speed"] = maxf(0.0, apply_effect_operator(float(entity.get("speed", 0.0)), effect_type, value))
		8:
			modify_combat_class_value(components.get("combat", {}).get("armors", []), effect_type, value)
		9:
			var attacks: Array = components.get("combat", {}).get("attacks", [])
			modify_combat_class_value(attacks, effect_type, value)
			if not attacks.is_empty():
				entity["attack_damage"] = CombatRules.primary_attack_damage(attacks, float(entity.get("attack_damage", 0.0)))
		10:
			entity["attack_period"] = maxf(0.01, apply_effect_operator(float(entity.get("attack_period", 0.0)), effect_type, value))
			components.get("combat", {})["attack_period"] = entity["attack_period"]
		11:
			var combat: Dictionary = components.get("combat", {})
			combat["accuracy"] = clampi(roundi(apply_effect_operator(float(combat.get("accuracy", 0)), effect_type, value)), 0, 100)
		12:
			entity["attack_range"] = maxf(0.0, apply_effect_operator(float(entity.get("attack_range", 0.0)), effect_type, value))
			components.get("combat", {})["range_max"] = entity["attack_range"]
		13:
			var worker: Dictionary = components.get("worker", {})
			worker["work_rate"] = maxf(0.01, apply_effect_operator(float(worker.get("work_rate", 0.0)), effect_type, value))
			entity["gather_interval"] = 1.0 / float(worker["work_rate"])
			var conversion: Dictionary = components.get("conversion", {})
			if bool(conversion.get("enabled", false)):
				conversion["chance_multiplier"] = maxf(0.01, apply_effect_operator(float(conversion.get("chance_multiplier", 1.0)), effect_type, value))
			var healing: Dictionary = components.get("healing", {})
			if bool(healing.get("enabled", false)):
				healing["rate_multiplier"] = maxf(0.01, apply_effect_operator(float(healing.get("rate_multiplier", 1.0)), effect_type, value))
		14:
			entity["carry_capacity"] = maxf(0.0, apply_effect_operator(float(entity.get("carry_capacity", 0.0)), effect_type, value))
			components.get("resource_carrier", {})["capacity"] = entity["carry_capacity"]
		15:
			var combat: Dictionary = components.get("combat", {})
			combat["base_armor"] = apply_effect_operator(float(combat.get("base_armor", 0.0)), effect_type, value)
		16:
			entity["projectile_id"] = roundi(apply_effect_operator(float(entity.get("projectile_id", -1)), effect_type, value))
			components.get("combat", {})["projectile_id"] = entity["projectile_id"]
		17:
			var presentation_facing := roundi(apply_effect_operator(float(entity.get("presentation_facing", 0)), effect_type, value))
			entity["graphic_angle_count"] = presentation_facing
			entity["presentation_facing"] = maxi(0, presentation_facing)
		19:
			components.get("combat", {})["ballistics"] = value > 0.0
		100:
			components.get("production", {})["resource_cost_modifier"] = {"operator": effect_type, "value": value}
		101:
			reconcile_unit_population_points(entity)


func technology_effect_matches_entity(entity: Dictionary, command: Dictionary) -> bool:
	var unit_id := int(command.get("attr_a", -1))
	if unit_id >= 0:
		if int(command.get("attr_c", -1)) == 17:
			# Age display-facet effects target the original DAT line and must
			# survive the source-record replacement performed by the same age.
			return entity.get("unit_lineage", []).has(unit_id)
		# Genie effects address a concrete current DAT record. Upgrade bundles
		# commonly contain one command per variant, so matching every historical
		# lineage ID would stack the same research bonus after an upgrade.
		return int(entity.get("source_unit_id", -1)) == unit_id
	var class_id := int(command.get("attr_b", -1))
	if class_id < 0:
		return false
	var source := object_record_by_id(int(entity.get("source_unit_id", -1)), int(entity.get("team", 0)))
	return int(source.get("unit_class", -2)) == class_id


func apply_resource_effect(team: int, command: Dictionary, effect_type: int) -> void:
	var resource_id := int(command.get("attr_a", -1))
	var value := float(command.get("attr_d", 0.0))
	if resource_id == 6:
		return
	if resource_id == 4:
		set_population_cap(team, roundi(apply_effect_operator(float(get_population_cap(team)), effect_type if effect_type == 6 else (0 if int(command.get("attr_b", 0)) == 0 else 4), value)))
		return
	if resource_id in [-1, 21, 30]:
		return
	var operator := effect_type
	if effect_type == 1:
		operator = 0 if int(command.get("attr_b", 0)) == 0 else 4
	if resource_id in [0, 1, 2, 3]:
		var previous_stockpile := get_resource_amount(team, resource_id)
		set_resource_amount(team, resource_id, roundi(apply_effect_operator(float(previous_stockpile), operator, value)))
		return
	var previous_value := technology_system.rule_resource_value(team, resource_id)
	var updated_value := technology_system.apply_rule_resource_effect(team, resource_id, operator, value)
	# Keep the old integer query facade for existing consumers while rule systems
	# use the precise DAT value (faith and tribute modifiers are fractional).
	set_resource_amount(team, resource_id, roundi(updated_value))
	apply_harvestable_amount_delta(team, resource_id, roundi(updated_value) - roundi(previous_value))


func apply_harvestable_amount_delta(team: int, resource_amount_id: int, delta: int) -> void:
	if delta == 0:
		return
	for building in buildings:
		if int(building.get("team", 0)) != team or int(building.get("resource_amount_id", -1)) != resource_amount_id or String(building.get("state", "complete")) != "complete" or String(building.get("resource_state", "")) == "depleted" or float(building.get("hp", 0.0)) <= 0.0:
			continue
		building["max_amount"] = maxi(0, int(building.get("max_amount", 0)) + delta)
		building["amount"] = clampi(int(building.get("amount", 0)) + delta, 0, int(building["max_amount"]))
		building.get("components", {}).get("resource_carrier", {})["capacity"] = float(building["max_amount"])
		update_resource_state(building)
		_emit_domain_event("harvestable_capacity_changed", {
			"building_id": int(building.get("id", -1)),
			"resource_amount_id": resource_amount_id,
			"delta": delta,
			"amount": int(building.get("amount", 0)),
			"maximum": int(building.get("max_amount", 0)),
		})


func apply_effect_operator(current: float, effect_type: int, value: float) -> float:
	match effect_type:
		0:
			return value
		4:
			return current + value
		5, 6:
			return current * value
	return current


func modify_combat_class_value(entries: Array, effect_type: int, packed_value: float) -> void:
	var packed := roundi(packed_value)
	var class_id := (packed >> 8) & 0xff
	var amount := packed & 0xff
	if amount >= 128:
		amount -= 256
	for entry_value in entries:
		var entry: Dictionary = entry_value
		if int(entry.get("type_id", -1)) == class_id:
			entry["amount"] = roundi(apply_effect_operator(float(entry.get("amount", 0)), effect_type, float(amount)))
			return
	entries.append({"type_id": class_id, "amount": amount})


func get_current_age(team: int) -> int:
	return technology_system.current_age(team)


func get_researched_technologies(team: int) -> Array[int]:
	return technology_system.researched_ids(team)


func get_available_technologies(team: int, research_location_id: int = -1) -> Array[int]:
	return technology_system.available_technology_ids(team, research_location_id)


func is_object_available(team: int, object_id: int) -> bool:
	var source := object_record_by_id(object_id, team)
	return technology_system.is_object_enabled(team, object_id, bool(source.get("enabled", true)))


func grant_technology(team: int, technology_id: int) -> void:
	apply_technology_commands(team, technology_system.complete_research(team, technology_id))
	last_completed_research_id = technology_id
	last_research_message = "research_complete:%d" % technology_id
	_emit_domain_event("research_complete", {
		"technology_id": technology_id,
		"team": team,
		"building_id": -1,
	})

func living_count(team: int) -> int:
	return get_all_units_including_embarked().filter(func(unit): return unit["team"] == team and unit["hp"] > 0.0).size()


func get_all_units_including_embarked() -> Array:
	return units + transport_system.all_embarked_units()


func get_embarked_units() -> Array:
	return transport_system.all_embarked_units()

func get_units() -> Array:
	return units


func get_units_in_bounds(bounds: Rect2) -> Array:
	var result: Array = spatial_index.query_aabb(bounds, "unit")
	# The movement index intentionally contains living mobile entities only;
	# presentation still needs short-lived dying/corpse records.
	for unit_value in dying_units:
		var unit: Dictionary = unit_value
		if bounds.has_point(Vector2(unit.get("pos", Vector2.ZERO))):
			result.append(unit)
	if not dying_units.is_empty():
		result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result

func get_resources() -> Array:
	return resource_nodes


func known_resource_memory_state() -> Dictionary:
	var result: Dictionary = {}
	var observers: Array = known_resources_by_player.keys()
	for observer_value in observers:
		var observer_team := int(observer_value)
		get_known_resources(observer_team)
		var cached: Dictionary = known_resources_by_player[observer_value]
		result[observer_team] = cached.get("resources", []).duplicate(true)
	return result


func known_resource_revision(observer_team: int) -> int:
	get_known_resources(observer_team)
	return int(known_resources_by_player.get(observer_team, {}).get("revision", 0))


# One presentation consumer per observer. The queue contains only legal resource
# memory changes that can alter a marker, not every decrement of a tree's wood.
# null requests an initial/bulk rebuild; an empty dictionary means no work.
func consume_known_resource_marker_changes(observer_team: int) -> Variant:
	get_known_resources(observer_team)
	var cached: Dictionary = known_resources_by_player.get(observer_team, {})
	if cached.is_empty():
		return null
	var rebuild := not bool(cached.get("marker_changes_tracked", false)) or bool(cached.get("marker_changes_overflow", false))
	cached["marker_changes_tracked"] = true
	cached["marker_changes_overflow"] = false
	var pending: Dictionary = cached.get("marker_changes", {})
	var changes: Dictionary = {}
	if not rebuild:
		var ids: Dictionary = cached.get("ids", {})
		for resource_id in pending:
			changes[resource_id] = ids.get(resource_id)
	pending.clear()
	return null if rebuild else changes


func _mark_known_resource_marker_changed(cached: Dictionary, resource_id: int) -> void:
	if not bool(cached.get("marker_changes_tracked", false)) or bool(cached.get("marker_changes_overflow", false)):
		return
	var pending: Dictionary = cached["marker_changes"]
	pending[resource_id] = true
	if pending.size() > MAX_MINIMAP_RESOURCE_CHANGES:
		pending.clear()
		cached["marker_changes_overflow"] = true


func restore_known_resource_memory(encoded: Dictionary) -> void:
	known_resources_by_player.clear()
	known_ai_resources_by_player.clear()
	var fog = get_fog_of_war()
	for observer_key in encoded.keys():
		var observer_team := int(observer_key)
		if observer_team <= 0 or not encoded[observer_key] is Array:
			continue
		fog.ensure_player(observer_team)
		var ally_ids: Array = fog.shared_vision_by_player.get(observer_team, {}).keys()
		ally_ids.sort()
		var cached := _empty_known_resource_cache(hash(ally_ids))
		for record_value in encoded[observer_key]:
			if record_value is Dictionary:
				_remember_known_resource(cached, record_value, true)
		cached["revision"] = 1
		known_resources_by_player[observer_team] = cached
		fog.consume_newly_explored_cells(observer_team)
		fog.consume_newly_visible_cells(observer_team)


func compact_render_projection(entity: Dictionary) -> Dictionary:
	return render_entity_projection_cache.project(entity)


func get_known_resources(observer_team: int) -> Array:
	if observer_team <= 0:
		return resource_nodes
	var fog = get_fog_of_war()
	fog.ensure_player(observer_team)
	var ally_ids: Array = fog.shared_vision_by_player.get(observer_team, {}).keys()
	ally_ids.sort()
	var alliance_signature := hash(ally_ids)
	var cached: Dictionary = known_resources_by_player.get(observer_team, {})
	if not cached.is_empty() and int(cached.get("alliance_signature", 0)) == alliance_signature:
		_refresh_known_resource_cache(observer_team, cached, fog)
		return cached.get("resources", [])
	var states: PackedByteArray = fog.states_by_player[observer_team]
	var allies: Dictionary = fog.shared_vision_by_player.get(observer_team, {})
	cached = _empty_known_resource_cache(alliance_signature)
	for resource_value in resource_nodes:
		var resource: Dictionary = resource_value
		var owner := int(resource.get("team", 0))
		if owner > 0 and bool(allies.get(owner, false)):
			_remember_known_resource(cached, resource)
			continue
		var position: Vector2 = resource.get("pos", Vector2.ZERO)
		var cell_x := floori(position.x)
		var cell_y := floori(position.y)
		if cell_x < 0 or cell_y < 0 or cell_x >= fog.map_size.x or cell_y >= fog.map_size.y:
			continue
		if int(states[cell_y * fog.map_size.x + cell_x]) != FogOfWar.UNKNOWN:
			_remember_known_resource(cached, resource)
	fog.consume_newly_explored_cells(observer_team)
	fog.consume_newly_visible_cells(observer_team)
	cached["revision"] = 1
	known_resources_by_player[observer_team] = cached
	return cached.get("resources", [])


func get_known_ai_resources(observer_team: int) -> Array:
	# Strategic planners only read a small, stable projection of resource nodes.
	# Reuse those dictionaries between decisions instead of allocating and
	# populating thousands of copies for every AI player every two seconds.
	var known: Array = get_known_resources(observer_team)
	if observer_team <= 0:
		return known
	var known_cache: Dictionary = known_resources_by_player.get(observer_team, {})
	if known_cache.has("ai_projection"):
		return known_cache["ai_projection"]["resources"]
	var projected := {"resources": [], "ids": {}}
	for resource in known:
		var item := _compact_ai_resource(resource)
		projected["resources"].append(item)
		projected["ids"][int(item["id"])] = item
	known_cache["ai_projection"] = projected
	known_ai_resources_by_player[observer_team] = projected
	return projected["resources"]


# Warm the immutable resource publication alongside incremental AI navigation.
# A restored large forest must not produce a single long frame on first use.
func prepare_known_ai_resource_snapshot(observer_team: int, max_records: int = 64) -> bool:
	var known := get_known_resources(observer_team)
	var cache: Dictionary = known_resources_by_player.get(observer_team, {})
	if observer_team <= 0 or cache.has("ai_projection"):
		return true
	var revision := int(cache.get("revision", 0))
	var pending: Dictionary = cache.get("ai_projection_preparing", {})
	if pending.is_empty() or int(pending["revision"]) != revision:
		pending = {"revision": revision, "resources": [], "ids": {}, "publication": ResourcePublication.new()}
		cache["ai_projection_preparing"] = pending
	var end := mini(known.size(), pending["resources"].size() + maxi(1, max_records))
	for index in range(pending["resources"].size(), end):
		var item := _compact_ai_resource(known[index])
		if not pending["publication"].upsert(item):
			cache.erase("ai_projection_preparing")
			return false
		pending["resources"].append(item)
		pending["ids"][int(item["id"])] = item
	if end < known.size():
		return false
	pending.erase("revision")
	cache["ai_projection"] = pending
	known_ai_resources_by_player[observer_team] = pending
	cache.erase("ai_projection_preparing")
	return true

func get_known_ai_resource_snapshot(observer_team: int) -> Array:
	var resources := get_known_ai_resources(observer_team)
	var cache: Dictionary = known_resources_by_player.get(observer_team, {})
	var projection: Dictionary = cache.get("ai_projection", {})
	if projection.is_empty():
		return resources.duplicate()
	if not projection.has("publication"):
		var publication := ResourcePublication.new()
		for record in resources:
			if not publication.upsert(record):
				return resources.duplicate()
		projection["publication"] = publication
	return projection["publication"].snapshot()


func _update_ai_resource_projection(cached: Dictionary, memory: Dictionary) -> void:
	if not cached.has("ai_projection"):
		return
	var projection: Dictionary = cached["ai_projection"]
	var id := int(memory["id"])
	var item := _compact_ai_resource(memory)
	if projection["ids"].get(id) == item:
		return
	if projection.has("publication") and not projection["publication"].upsert(item):
		projection.erase("publication")
	if projection["ids"].has(id):
		_replace_known_resource(projection["resources"], item)
		projection["ids"][id] = item
	else:
		projection["ids"][id] = item
		_insert_known_resource_sorted(projection["resources"], item)


func _compact_ai_resource(resource: Dictionary) -> Dictionary:
	return EntityReadContract.resource(resource)


func _empty_known_resource_cache(alliance_signature: int) -> Dictionary:
	return {
		"alliance_signature": alliance_signature,
		"resources": [],
		"ids": {},
		"by_cell": {},
		"by_chunk": {},
		"dirty_ids": {},
		"marker_changes": {},
		"marker_changes_tracked": false,
		"marker_changes_overflow": false,
		"revision": 0,
	}


func _refresh_known_resource_cache(observer_team: int, cached: Dictionary, fog) -> void:
	var changed := false
	var allies: Dictionary = fog.shared_vision_by_player.get(observer_team, {})
	var candidate_cells: Dictionary = {}
	for cell_index_value in fog.consume_newly_explored_cells(observer_team):
		candidate_cells[int(cell_index_value)] = true
	for cell_index_value in fog.consume_newly_visible_cells(observer_team):
		candidate_cells[int(cell_index_value)] = true
	for cell_index_value in candidate_cells.keys():
		var cell_index := int(cell_index_value)
		var cell := Vector2i(cell_index % map_size.x, cell_index / map_size.x)
		if fog.state_at_cell(observer_team, cell) != FogOfWar.VISIBLE:
			continue
		var live_ids: Dictionary = {}
		for resource_value in resource_nodes_by_cell.get(cell_index, []):
			var resource: Dictionary = resource_value
			var resource_id := int(resource.get("id", -1))
			live_ids[resource_id] = true
			changed = _remember_known_resource(cached, resource) or changed
		var remembered_in_cell: Dictionary = cached.get("by_cell", {}).get(cell_index, {})
		for resource_id_value in remembered_in_cell.keys():
			var resource_id := int(resource_id_value)
			if not live_ids.has(resource_id):
				changed = _forget_known_resource(cached, resource_id) or changed
	var dirty_ids: Dictionary = cached.get("dirty_ids", {})
	for resource_id_value in dirty_ids.keys():
		var resource_id := int(resource_id_value)
		var live: Variant = resource_nodes_by_id.get(resource_id)
		var remembered: Variant = cached.get("ids", {}).get(resource_id)
		var position := Vector2.ZERO
		if live is Dictionary:
			position = Vector2(live.get("pos", Vector2.ZERO))
		elif remembered is Dictionary:
			position = Vector2(remembered.get("pos", Vector2.ZERO))
		else:
			continue
		var ownership_source: Dictionary = live if live is Dictionary else remembered
		var owner := int(ownership_source.get("team", 0))
		var allied_resource := owner > 0 and bool(allies.get(owner, false))
		if not allied_resource and fog.state_at_world(observer_team, position) != FogOfWar.VISIBLE:
			continue
		if live is Dictionary:
			changed = _remember_known_resource(cached, live) or changed
		else:
			changed = _forget_known_resource(cached, resource_id) or changed
	dirty_ids.clear()
	if changed:
		cached["revision"] = int(cached.get("revision", 0)) + 1


func mark_known_resource_dirty(resource: Dictionary) -> void:
	_mark_known_resource_dirty(resource)


func _mark_known_resource_dirty(resource: Dictionary) -> void:
	var resource_id := int(resource.get("id", -1))
	if resource_id < 0:
		return
	for observer_value in known_resources_by_player.keys():
		var cached: Dictionary = known_resources_by_player[observer_value]
		var dirty_ids: Dictionary = cached.get("dirty_ids", {})
		dirty_ids[resource_id] = true
		cached["dirty_ids"] = dirty_ids


func _remember_known_resource(cached: Dictionary, resource: Dictionary, compact_source: bool = false) -> bool:
	var resource_id := int(resource.get("id", -1))
	if resource_id < 0:
		return false
	if int(resource.get("amount", 0)) <= 0 and not bool(resource.get("visible_when_depleted", false)):
		return _forget_known_resource(cached, resource_id)
	var memory: Dictionary = EntityReadContract.render(resource) if compact_source else render_entity_projection_cache.project(resource)
	var ids: Dictionary = cached.get("ids", {})
	var existing: Variant = ids.get(resource_id)
	if existing is Dictionary:
		if existing == memory:
			return false
		if existing.get("pos") != memory.get("pos") or (int(existing.get("amount", 0)) > 0) != (int(memory.get("amount", 0)) > 0):
			_mark_known_resource_marker_changed(cached, resource_id)
		if existing.get("pos") == memory.get("pos"):
			_replace_known_resource(cached["resources"], memory)
			ids[resource_id] = memory
			_update_ai_resource_projection(cached, memory)
			return true
		# Moving a remembered resource must also migrate its spatial indices.
		_forget_known_resource(cached, resource_id)
	var known: Array = cached.get("resources", [])
	_insert_known_resource_sorted(known, memory)
	ids[resource_id] = memory
	_update_ai_resource_projection(cached, memory)
	_mark_known_resource_marker_changed(cached, resource_id)
	var cell_index := _resource_cell_index(memory)
	var by_cell: Dictionary = cached.get("by_cell", {})
	var cell_ids: Dictionary = by_cell.get(cell_index, {})
	cell_ids[resource_id] = true
	by_cell[cell_index] = cell_ids
	var chunk_key := _resource_chunk_key(memory)
	var by_chunk: Dictionary = cached.get("by_chunk", {})
	var chunk_ids: Dictionary = by_chunk.get(chunk_key, {})
	chunk_ids[resource_id] = true
	by_chunk[chunk_key] = chunk_ids
	cached["resources"] = known
	cached["ids"] = ids
	cached["by_cell"] = by_cell
	cached["by_chunk"] = by_chunk
	return true


func _forget_known_resource(cached: Dictionary, resource_id: int) -> bool:
	var ids: Dictionary = cached.get("ids", {})
	var memory: Variant = ids.get(resource_id)
	if not memory is Dictionary:
		return false
	var known: Array = cached.get("resources", [])
	known.erase(memory)
	if cached.has("ai_projection"):
		var projected: Dictionary = cached["ai_projection"]
		projected["resources"].erase(projected["ids"].get(resource_id))
		projected["ids"].erase(resource_id)
		if projected.has("publication"):
			projected["publication"].erase(resource_id)
	ids.erase(resource_id)
	_mark_known_resource_marker_changed(cached, resource_id)
	var cell_index := _resource_cell_index(memory)
	var by_cell: Dictionary = cached.get("by_cell", {})
	var cell_ids: Dictionary = by_cell.get(cell_index, {})
	cell_ids.erase(resource_id)
	if cell_ids.is_empty():
		by_cell.erase(cell_index)
	else:
		by_cell[cell_index] = cell_ids
	var chunk_key := _resource_chunk_key(memory)
	var by_chunk: Dictionary = cached.get("by_chunk", {})
	var chunk_ids: Dictionary = by_chunk.get(chunk_key, {})
	chunk_ids.erase(resource_id)
	if chunk_ids.is_empty():
		by_chunk.erase(chunk_key)
	else:
		by_chunk[chunk_key] = chunk_ids
	return true


func _resource_cell_index(resource: Dictionary) -> int:
	var position := Vector2(resource.get("pos", Vector2.ZERO))
	return floori(position.y) * map_size.x + floori(position.x)


func _resource_chunk_key(resource: Dictionary) -> Vector2i:
	var position := Vector2(resource.get("pos", Vector2.ZERO))
	return Vector2i(
		floori(position.x / float(RESOURCE_MEMORY_CHUNK_SIZE)),
		floori(position.y / float(RESOURCE_MEMORY_CHUNK_SIZE))
	)


func get_known_resources_in_bounds(observer_team: int, bounds: Rect2) -> Array:
	if observer_team <= 0:
		return resource_nodes.filter(func(resource): return bounds.has_point(Vector2(resource.get("pos", Vector2.ZERO))))
	# Ensure the incremental exploration cache is current, then traverse only
	# remembered resource cells intersecting the camera. Reading the live cell
	# index here would leak hidden depletion/removal through the fog.
	get_known_resources(observer_team)
	var cached: Dictionary = known_resources_by_player.get(observer_team, {})
	var known_ids: Dictionary = cached.get("ids", {})
	var known_by_chunk: Dictionary = cached.get("by_chunk", {})
	var start_x := clampi(floori(bounds.position.x), 0, map_size.x)
	var start_y := clampi(floori(bounds.position.y), 0, map_size.y)
	var end_x := clampi(ceili(bounds.end.x), 0, map_size.x)
	var end_y := clampi(ceili(bounds.end.y), 0, map_size.y)
	var result: Array = []
	if end_x <= start_x or end_y <= start_y:
		return result
	var first_chunk_x := floori(float(start_x) / float(RESOURCE_MEMORY_CHUNK_SIZE))
	var first_chunk_y := floori(float(start_y) / float(RESOURCE_MEMORY_CHUNK_SIZE))
	var last_chunk_x := floori(float(end_x - 1) / float(RESOURCE_MEMORY_CHUNK_SIZE))
	var last_chunk_y := floori(float(end_y - 1) / float(RESOURCE_MEMORY_CHUNK_SIZE))
	for chunk_y in range(first_chunk_y, last_chunk_y + 1):
		for chunk_x in range(first_chunk_x, last_chunk_x + 1):
			var chunk_ids: Dictionary = known_by_chunk.get(Vector2i(chunk_x, chunk_y), {})
			for resource_id_value in chunk_ids.keys():
				var resource: Variant = known_ids.get(int(resource_id_value))
				if not resource is Dictionary:
					continue
				var position := Vector2(resource.get("pos", Vector2.ZERO))
				var cell_x := floori(position.x)
				var cell_y := floori(position.y)
				if cell_x >= start_x and cell_x < end_x and cell_y >= start_y and cell_y < end_y:
					result.append(resource)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


func _replace_known_resource(known: Array, replacement: Dictionary) -> void:
	var id := int(replacement["id"])
	var low := 0
	var high := known.size()
	while low < high:
		var middle := (low + high) / 2
		if int(known[middle]["id"]) < id:
			low = middle + 1
		else:
			high = middle
	if low < known.size() and int(known[low]["id"]) == id:
		known[low] = replacement
	else:
		known.insert(low, replacement)


func _insert_known_resource_sorted(known: Array, resource: Dictionary) -> void:
	var resource_id := int(resource.get("id", -1))
	var lower := 0
	var upper := known.size()
	while lower < upper:
		var middle := (lower + upper) / 2
		if resource_id < int(known[middle].get("id", -1)):
			upper = middle
		else:
			lower = middle + 1
	known.insert(lower, resource)

func get_static_obstructions() -> Array:
	return static_obstructions

func get_buildings() -> Array:
	return buildings


func get_projectiles() -> Array:
	return projectiles


func get_resolved_projectiles() -> Array:
	return resolved_projectiles

func get_navigation_grid() -> NavigationGrid:
	return navigation_grid

func get_food() -> int:
	return economy_system.get_resource_amount(1, 0)

func get_wood() -> int:
	return economy_system.get_resource_amount(1, 1)

func get_kills() -> int:
	return kills


func get_population(team: int) -> int:
	return economy_system.get_population(team)


func get_population_points(team: int) -> int:
	return economy_system.get_population_points(team)


func get_reserved_population(team: int) -> int:
	return economy_system.get_reserved_population(team)


func get_population_cap(team: int) -> int:
	return economy_system.get_population_cap(team)


func set_population_cap(team: int, value: int) -> void:
	economy_system.set_population_cap(team, value)


func set_population_housing(team: int, value: int) -> void:
	economy_system.set_population_housing(team, value)


func get_economy_snapshot() -> Dictionary:
	return economy_system.snapshot()


func get_fog_of_war() -> FogOfWar:
	return visibility_system.get_fog()


func get_fog_state_at(team: int, position: Vector2) -> int:
	return visibility_system.state_at_world(team, position)


func consume_fog_presentation_dirty_cells(team: int) -> Array:
	if team <= 0:
		return []
	return get_fog_of_war().consume_presentation_dirty_cells(team)


func get_fog_state_name_at(team: int, position: Vector2) -> String:
	return visibility_system.state_name(get_fog_state_at(team, position))


func is_entity_visible_to(team: int, entity: Dictionary, allow_explored_static: bool = false) -> bool:
	return visibility_system.is_entity_visible(team, entity, allow_explored_static)


func are_teams_allied(first_team: int, second_team: int) -> bool:
	return player_registry.are_allied(first_team, second_team)


func team_relation(first_team: int, second_team: int) -> String:
	return player_registry.relation(first_team, second_team)


func get_allied_teams(team: int) -> Array[int]:
	return player_registry.allied_teams(team)


func get_team_relations(team: int) -> Dictionary:
	return player_registry.relations_for(team)


func can_autonomously_target(observer: Dictionary, candidate: Dictionary) -> bool:
	var observer_team := int(observer.get("team", 0))
	var candidate_team := int(candidate.get("team", 0))
	var relation := team_relation(observer_team, candidate_team)
	if relation == PlayerRegistry.ENEMY:
		return true
	if relation != PlayerRegistry.NEUTRAL:
		return false
	if entity_is_static(candidate):
		return true
	var tags: Array = candidate.get("behavior_tags", [])
	return "military" in tags or ("combatant" in tags and "worker" not in tags)


func resign_team(team: int) -> bool:
	if not player_registry.resign(team):
		return false
	_emit_domain_event("player_resigned", {"team": team})
	return true


func can_unit_reach_entity(unit: Dictionary, target: Dictionary) -> bool:
	if CombatRules.is_in_range(unit, target):
		return true
	if entity_is_static(unit):
		return false
	var start := Vector2(unit.get("pos", Vector2.ZERO))
	var goal := Vector2(target.get("pos", Vector2.ZERO))
	var route: Array[Vector2] = pathfinder.find_path(start, goal, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), float(unit.get("footprint_radius", 0.3)))
	return not route.is_empty()


func is_unit_in_attack_range(unit: Dictionary, target: Dictionary) -> bool:
	return CombatRules.is_in_range(unit, target)


func configure_victory_rules(rules: Array, allied_victory_enabled: bool = true) -> void:
	victory_system.configure(rules, allied_victory_enabled)
	for objective in victory_objectives:
		victory_system.track_objective(objective)
	player_registry.reset_statuses()
	battle_over = false
	battle_message = ""


func configure_scenario_definition(definition: Dictionary) -> void:
	scenario_system.configure(definition)


func add_victory_object(category: String, position: Vector2, team: int = 0, completed: bool = true) -> Dictionary:
	var objective := {
		"id": entity_id_sequence.next(),
		"category": category,
		"pos": Coordinates.clamp_world(position, map_size),
		"team": team,
		"completed": completed,
		"active": true,
	}
	victory_objectives.append(objective)
	victory_system.track_objective(objective)
	if category == "ruin":
		capturable_victory_objectives.append(objective)
	return objective


func set_victory_object_owner(object_id: int, team: int) -> bool:
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == object_id:
			if int(objective.get("team", 0)) == team:
				return true
			objective["team"] = team
			victory_system.track_objective(objective)
			_emit_domain_event("victory_object_captured", {"object_id": object_id, "category": String(objective.get("category", "")), "team": team})
			return true
	return false


func set_victory_object_completed(object_id: int, completed: bool) -> bool:
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == object_id:
			objective["completed"] = completed
			victory_system.track_objective(objective)
			return true
	return false


func remove_victory_object(object_id: int) -> bool:
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == object_id:
			objective["active"] = false
			victory_system.track_objective(objective)
			return true
	return false


func set_score(team: int, value: int) -> void:
	score_by_team[team] = maxi(0, value)


func add_score(team: int, value: int) -> void:
	set_score(team, int(score_by_team.get(team, 0)) + value)


func get_score(team: int) -> int:
	return int(score_by_team.get(team, 0))


func get_victory_result() -> Dictionary:
	return victory_system.result.duplicate(true)

func is_battle_over() -> bool:
	return battle_over

func get_map_size() -> Vector2i:
	return map_size

func get_last_battle_message() -> String:
	return battle_message
