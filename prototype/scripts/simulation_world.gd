class_name RoRSimulationWorld

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
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const CombatRules := preload("res://scripts/combat_rules.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const SimulationVisibilitySystem := preload("res://scripts/simulation_visibility_system.gd")
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

var map_size: Vector2i = Vector2i(24, 24)
var map_terrain_ids: Dictionary = {}
var map_reserved_foundation_cells: Dictionary = {}
var forest_resource_counts: Dictionary = {}
var terrain_revision: int = 0
var units: Array = []
var resource_nodes: Array = []
var resource_nodes_by_id: Dictionary = {}
var decaying_resource_nodes: Array = []
var static_obstructions: Array = []
var buildings: Array = []
var projectiles: Array = []
var resolved_projectiles: Array = []

var entity_id_sequence := EntityIds.new()
var spatial_index := SpatialHash.new(2.0)
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
var civilization_by_team: Dictionary = {1: 13, 2: 13}
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

func set_gamespec(data: Dictionary) -> void:
	gamespec_data = data
	data_repository.configure_compatibility_gamespec(data)


func set_terrain_catalog(data: Dictionary) -> void:
	navigation_grid.configure_restrictions(data.get("restrictions", []))
	navigation_grid.configure_terrain_ids(Callable(self, "terrain_id_at_cell"))
	pathfinder.clear_cache()
	navigation_service.clear_observations()


func set_object_catalog(data: Dictionary) -> void:
	object_catalog_data = data
	data_repository.configure_objects(data)
	technology_system.configure(data)
	for team in civilization_by_team.keys():
		initialize_team_rules(int(team))


func set_graphics_catalog(data: Dictionary) -> void:
	graphics_catalog_data = data


func set_runtime_catalog(data: Dictionary) -> void:
	data_repository.configure_runtime(data)
	var trade_policy: Dictionary = data_repository.runtime_metadata("trade_boat").get("trade", {})
	for team in civilization_by_team.keys():
		trade_system.initialize_team(int(team), trade_policy)


func set_team_civilization(team: int, civilization_id: int) -> void:
	player_registry.set_civilization(team, civilization_id)
	civilization_by_team[team] = civilization_id
	trade_system.initialize_team(team, data_repository.runtime_metadata("trade_boat").get("trade", {}))
	if not object_catalog_data.is_empty():
		technology_system.reset_team(team)
		initialize_team_rules(team)


func set_alliance(first_team: int, second_team: int, allied: bool = true) -> void:
	player_registry.set_mutual_relation(first_team, second_team, "ally" if allied else "enemy")
	visibility_system.set_alliance(first_team, second_team, allied)
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
	if not is_bulk_loading():
		update_fog_of_war()
		_emit_domain_event("diplomacy_changed", {"source_team": source_team, "target_team": target_team, "relation": relation})
	return true


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
	if not preserve_bulk_load:
		bulk_load_depth = 0
	units.clear()
	resource_nodes.clear()
	resource_nodes_by_id.clear()
	decaying_resource_nodes.clear()
	static_obstructions.clear()
	forest_resource_counts.clear()
	buildings.clear()
	combat_system.reset()
	ai_distress_system.reset()
	pending_domain_events.clear()
	capture_domain_events = false
	entity_id_sequence.reset(1)
	spatial_index.clear()
	simulation_rng.seed = simulation_seed
	economy_system.reset()
	kills = 0
	battle_over = false
	battle_message = ""
	resource_approach_slots.clear()
	building_approach_slots.clear()
	last_build_failure = ""
	production_system.reset()
	transport_system.reset()
	trade_system.reset()
	victory_objectives.clear()
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
	update_fog_of_war()


func is_bulk_loading() -> bool:
	return bulk_load_depth > 0


func configure_map_data(map_data: Dictionary) -> void:
	terrain_revision += 1
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
	if team > 0:
		player_registry.ensure(team, int(civilization_by_team.get(team, 13)))
	var stats := unit_stats(kind)
	var source := object_record_for(kind, team)
	var terrain_restriction := int(source.get("links", {}).get("terrain_restriction", stats.get("terrain_restriction", -1)))
	var movement_domain := "water" if terrain_restriction == 3 else "land"
	if movement_domain == "water":
		var placement_cell: Vector2i = pathfinder.nearest_walkable(Vector2i(floori(position.x), floori(position.y)), movement_domain, terrain_restriction)
		if placement_cell.x >= 0:
			position = Vector2(placement_cell) + Vector2(0.5, 0.5)
	var footprint := Footprint.mobile(kind, stats)
	var initial_facing := facing_for_vector(Vector2(12.0, 12.0) - position)
	var entity_id := entity_id_sequence.next()
	var civilization_id := int(civilization_by_team.get(team, 13))
	var components := EntityComponents.for_unit(entity_id, team, civilization_id, kind, position, elevation_at(position), stats, source, footprint, initial_facing)
	var health: Dictionary = components["health"]
	var combat: Dictionary = components["combat"]
	var production: Dictionary = components["production"]
	var worker_component: Dictionary = components["worker"]
	var carrier_component: Dictionary = components["resource_carrier"]
	var worker_enabled: bool = bool(worker_component.get("enabled", false)) or (stats.get("behavior_tags", []).is_empty() and kind == "villager")
	var attacks: Array = combat["attacks"]
	var attack_damage := CombatRules.primary_attack_damage(attacks, 3.0)
	var unit := {
		"id": entity_id,
		"team": team,
		"kind": kind,
		"pos": position,
		"previous_pos": position,
		"elevation": elevation_at(position),
		"target": position,
		"destination": position,
		"path": [],
		"path_index": 0,
		"path_request_id": 0,
		"path_status": "idle",
		"path_grid_revision": navigation_grid.revision,
		"diagnostic_reason": "",
		"reserved_destination": null,
		"desired_velocity": Vector2.ZERO,
		"actual_velocity": Vector2.ZERO,
		"cohesion_speed_scale": 1.0,
		"selected": selected,
		"hp": health["current"],
		"max_hp": health["maximum"],
		"task": "idle",
		"target_id": -1,
		"resource_id": -1,
		"cooldown": 0.0,
		"work": 0.0,
		"gather_stage": "none",
		"gather_interval": 1.0 / maxf(0.01, float(worker_component.get("work_rate", 1.0))),
		"resource_approach_slot": null,
		"dropoff_id": -1,
		"dropoff_position": null,
		"carried_amount": 0.0,
		"carried_resource_type_id": -1,
		"worker_role_source_unit_id": -1,
		"worker_role_name": "",
		"worker_role_profile": {},
		"presentation_state_overrides": {},
		"pending_hunt_target_id": -1,
		"carry_capacity": maxf(0.0, float(carrier_component.get("capacity", 0.0))),
		"gather_cycles": 0,
		"deposit_cycles": 0,
		"target_building_id": -1,
		"building_approach_slot": null,
		"speed": components["movement"]["speed"],
		"terrain_restriction": terrain_restriction,
		"movement_domain": movement_domain,
		"footprint_radius": footprint["movement_radius"],
		"footprint": footprint,
		"selection_radius": footprint["selection_radius"],
		"selection_height": footprint["selection_height"],
		"minimum_clearance": footprint["minimum_clearance"],
		"push_priority": footprint["push_priority"],
		"base_push_priority": footprint["push_priority"],
		"stuck_ticks": 0,
		"attack_damage": attack_damage,
		"attack_period": combat["attack_period"],
		"attack_range_min": combat["range_min"],
		"attack_range": combat["range_max"],
		"blast_range": combat["blast_range"],
		"projectile_id": combat["projectile_id"],
		"combat_enabled": false,
		"stance": "passive",
		"acquisition_range": 0.0,
		"chase_range": 0.0,
		"retaliation_target_id": -1,
		"attack_autonomous": false,
		"combat_leash_origin": position,
		"combat_resume": {},
		"attack_move_destination": null,
		"facing": initial_facing,
		"movement_facing": initial_facing,
		"desired_facing": initial_facing,
		"action_facing": initial_facing,
		"formation_forward": Vector2.ZERO,
		"formation_facing": initial_facing,
		"formation_group_id": -1,
		"formation_slot_id": -1,
		"formation_home": null,
		"formation_slot_mode": "none",
		"combat_role": "",
		"combat_slot_index": -1,
		"combat_slot_count": 0,
		"combat_approach": Vector2.ZERO,
		"combat_destination": null,
		"anim": simulation_rng.randf(),
		"anim_state": AnimationController.IDLE,
		"animation_events_fired": {},
		"population_cost": int(production.get("population_cost", 0)),
		"population_released": false,
		"victory_objective_id": -1,
		"source_unit_id": int(source.get("unit_id", stats.get("unit_id", -1))),
		"unit_lineage": [int(source.get("unit_id", stats.get("unit_id", -1)))],
		"display_graphic_id": int(source.get("graphics", {}).get("idle", -1)),
		"death_phase": "alive",
		"death_elapsed": 0.0,
		"death_duration": death_animation_duration(kind),
		"corpse_elapsed": 0.0,
		"corpse_duration": corpse_animation_duration(source, team),
		"corpse_source_id": int(source.get("links", {}).get("dead_unit_id", -1)),
		"death_complete": false,
		"removed": false,
		"components": components,
	}
	apply_archetype_identity(unit, kind)
	configure_unit_combat_awareness(unit)
	units.append(unit)
	register_unit_victory_objective(unit)
	apply_technology_state_to_entity(unit, team)
	economy_system.add_population(team, int(unit["population_cost"]))
	spatial_index.insert(unit, position, unit["footprint_radius"], "unit")
	if not is_bulk_loading():
		update_fog_of_war()
	_emit_domain_event("entity_created", {
		"entity_id": entity_id,
		"entity_category": "unit",
		"kind": kind,
		"team": team,
	})
	return unit

func add_resource(kind: String, position: Vector2, amount: int) -> Dictionary:
	return _add_resource(kind, position, amount, true)


func add_scenario_resource(kind: String, position: Vector2, amount: int) -> Dictionary:
	return _add_resource(kind, Coordinates.clamp_world(position, map_size), amount, false)


func _add_resource(kind: String, position: Vector2, amount: int, resolve_placement: bool) -> Dictionary:
	var source := resource_stats(kind)
	var footprint := Footprint.resource(kind, source)
	var runtime_metadata: Dictionary = data_repository.runtime_metadata(kind)
	var terrain_restriction := int(runtime_metadata.get("placement_terrain_restriction_id", source.get("links", {}).get("terrain_restriction", -1)))
	var placement_domain := String(runtime_metadata.get("placement_domain", "water" if terrain_restriction == 3 else "land"))
	if resolve_placement:
		position = find_resource_placement(position, float(footprint["movement_radius"]), placement_domain, terrain_restriction)
	footprint["occupied_cells"] = [Vector2i(floori(position.x), floori(position.y))]
	var safe_amount := maxi(0, amount)
	var resource_type_id := resource_type_for(kind, source)
	var entity_id := entity_id_sequence.next()
	var components := EntityComponents.for_resource(entity_id, kind, position, elevation_at(position), safe_amount, source, footprint)
	var resource := {
		"id": entity_id,
		"kind": kind,
		"pos": position,
		"elevation": elevation_at(position),
		"amount": safe_amount,
		"max_amount": safe_amount,
		"resource_type_id": resource_type_id,
		"placement_domain": placement_domain,
		"allowed_gatherer_domains": runtime_metadata.get("allowed_gatherer_domains", []).duplicate(),
		"terrain_restriction": terrain_restriction,
		"state": "available" if safe_amount > 0 else "depleted",
		"depletion_stage": 0 if safe_amount > 0 else 2,
		"visible_when_depleted": bool(data_repository.runtime_metadata(kind).get("visible_when_depleted", kind == "tree")),
		"decay_rate": maxf(0.0, float(runtime_metadata.get("decay_rate", 0.0))),
		"decay_accumulator": 0.0,
		"footprint": footprint,
		"footprint_radius": footprint["movement_radius"],
		"selection_radius": footprint["selection_radius"],
		"selection_height": footprint["selection_height"],
		"components": components,
	}
	apply_archetype_identity(resource, kind)
	resource_nodes.append(resource)
	resource_nodes_by_id[entity_id] = resource
	if float(resource.get("decay_rate", 0.0)) > 0.0:
		decaying_resource_nodes.append(resource)
	if safe_amount > 0 and kind == "tree":
		_register_forest_resource(resource)
	if not is_bulk_loading():
		rebuild_navigation_grid()
	_emit_domain_event("entity_created", {
		"entity_id": entity_id,
		"entity_category": "resource",
		"kind": kind,
		"team": 0,
	})
	return resource


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
	var candidates: Array[Vector2] = [Coordinates.clamp_world(desired, map_size)]
	for ring in range(1, maxi(map_size.x, map_size.y) * 2 + 1):
		var distance := float(ring) * 0.5
		for offset in [Vector2(distance, 0), Vector2(0, distance), Vector2(-distance, 0), Vector2(0, -distance), Vector2(distance, distance), Vector2(-distance, distance), Vector2(-distance, -distance), Vector2(distance, -distance)]:
			candidates.append(Coordinates.clamp_world(desired + offset, map_size))
	for candidate in candidates:
		var cell := Vector2i(floori(candidate.x), floori(candidate.y))
		if map_reserved_foundation_cells.has(cell):
			continue
		if not navigation_grid.is_walkable_for(cell, movement_domain, restriction_id):
			continue
		var blocked_by_building := navigation_grid.occupants(cell).any(func(item): return String(item.get("category", "")) == "building")
		if blocked_by_building:
			continue
		var overlaps := false
		for existing in resource_nodes:
			if int(existing.get("amount", 0)) <= 0:
				continue
			var minimum_distance := radius + float(existing.get("footprint_radius", 0.2)) + 0.02
			if candidate.distance_squared_to(existing["pos"]) < minimum_distance * minimum_distance:
				overlaps = true
				break
		if not overlaps:
			return candidate
	return Coordinates.clamp_world(desired, map_size)

func add_building(id: int, kind: String, position: Vector2, team: int = 1, completed: bool = true) -> Dictionary:
	if team > 0:
		player_registry.ensure(team, int(civilization_by_team.get(team, 13)))
	var stats := unit_stats(kind)
	var source := object_record_for(kind, team)
	var footprint := Footprint.building(stats, position)
	var obstruction_type := int(source.get("geometry", {}).get("obstruction_type", stats.get("obstruction_type", 2)))
	var civilization_id := int(civilization_by_team.get(team, 13))
	var components := EntityComponents.for_building(id, team, civilization_id, kind, position, elevation_at(position), stats, source, footprint)
	var health: Dictionary = components["health"]
	var combat: Dictionary = components["combat"]
	var attacks: Array = combat.get("attacks", [])
	var construction_required := maxf(1.0, float(components.get("production", {}).get("creation_time", 1.0)))
	var starting_health := float(health["maximum"]) if completed else maxf(1.0, float(health["maximum"]) * 0.1)
	var production_queue: Array = []
	var building := {
		"id": id,
		"team": team,
		"kind": kind,
		"pos": position,
		"previous_pos": position,
		"elevation": elevation_at(position),
		"selected": false,
		"hp": starting_health,
		"max_hp": health["maximum"],
		"footprint": footprint,
		"footprint_radius": maxf(float(footprint["half_size"].x), float(footprint["half_size"].y)),
		"occupied_cells": footprint["occupied_cells"],
		"obstruction_type": obstruction_type,
		"passable": obstruction_type == 0 or "passable" in stats.get("behavior_tags", []),
		"harvestable": "harvestable" in stats.get("behavior_tags", []),
		"state": "complete" if completed else "foundation",
		"construction_progress": 1.0 if completed else 0.0,
		"construction_required": construction_required,
		"construction_stage": 3 if completed else 0,
		"reserved_cost": {},
		"builders": {},
		"production_queue": production_queue,
		"production_progress": 0.0,
		"population_support": population_support_for(kind, team),
		"population_support_applied": false,
		"task": "idle",
		"target_id": -1,
		"cooldown": 0.0,
		"speed": 0.0,
		"movement_domain": "static",
		"attack_damage": CombatRules.primary_attack_damage(attacks, 0.0),
		"attack_period": float(combat.get("attack_period", 0.0)),
		"attack_range_min": float(combat.get("range_min", 0.0)),
		"attack_range": float(combat.get("range_max", 0.0)),
		"blast_range": float(combat.get("blast_range", 0.0)),
		"projectile_id": int(combat.get("projectile_id", -1)),
		"combat_enabled": false,
		"stance": "passive",
		"acquisition_range": 0.0,
		"chase_range": 0.0,
		"retaliation_target_id": -1,
		"attack_autonomous": false,
		"combat_leash_origin": position,
		"combat_resume": {},
		"combat_destination": null,
		"facing": 0,
		"movement_facing": 0,
		"desired_facing": 0,
		"action_facing": 0,
		"anim": 0.0,
		"anim_state": AnimationController.IDLE,
		"animation_events_fired": {},
		"connection_mask": 0,
		"connection_revision": 0,
		"victory_objective_id": -1,
		"source_unit_id": int(source.get("unit_id", stats.get("unit_id", -1))),
		"unit_lineage": [int(source.get("unit_id", stats.get("unit_id", -1)))],
		"display_graphic_id": int(source.get("graphics", {}).get("idle", -1)),
		"death_phase": "alive",
		"death_elapsed": 0.0,
		"death_duration": building_death_animation_duration(source),
		"removed": false,
		"rally_point": position,
		"components": components,
	}
	apply_archetype_identity(building, kind)
	configure_harvestable_building(building, completed)
	building["components"]["production"]["queue"] = production_queue
	apply_technology_state_to_entity(building, team)
	configure_entity_combat_awareness(building)
	EntityComponents.sync_dynamic(building)
	buildings.append(building)
	var spatial_half_size: Vector2 = footprint.get("half_size", Vector2.ONE * float(building["footprint_radius"]))
	spatial_index.insert(building, position, spatial_half_size.length(), "obstacle")
	register_building_victory_objective(building)
	if completed:
		activate_building_completion(building)
	if not is_bulk_loading():
		refresh_building_connectivity()
		rebuild_navigation_grid()
		update_fog_of_war()
	_emit_domain_event("entity_created", {
		"entity_id": int(building["id"]),
		"entity_category": "building",
		"kind": kind,
		"team": team,
		"completed": completed,
	})
	return building

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


func configure_entity_combat_awareness(entity: Dictionary) -> void:
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


func sync_unit_victory_objective(unit: Dictionary) -> void:
	var objective_id := int(unit.get("victory_objective_id", -1))
	if objective_id < 0:
		return
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == objective_id:
			objective["team"] = int(unit.get("team", 0))
			objective["completed"] = float(unit.get("hp", 0.0)) > 0.0
			objective["active"] = float(unit.get("hp", 0.0)) > 0.0 and not bool(unit.get("removed", false))
			objective["pos"] = Vector2(unit.get("pos", Vector2.ZERO))
			return


func update_capturable_objectives() -> void:
	for objective_unit_value in units:
		var objective_unit: Dictionary = objective_unit_value
		if not entity_has_behavior_tag(objective_unit, "capturable") or float(objective_unit.get("hp", 0.0)) <= 0.0:
			continue
		var capture_radius := maxf(0.0, float(data_repository.runtime_metadata(String(objective_unit.get("kind", ""))).get("capture_radius", 1.0)))
		var candidates: Array = []
		for candidate_value in units:
			var candidate: Dictionary = candidate_value
			if int(candidate.get("id", -1)) == int(objective_unit.get("id", -1)) or int(candidate.get("team", 0)) <= 0:
				continue
			if float(candidate.get("hp", 0.0)) <= 0.0 or entity_has_behavior_tag(candidate, "capturable"):
				continue
			var distance := Vector2(candidate.get("pos", Vector2.ZERO)).distance_to(Vector2(objective_unit.get("pos", Vector2.ZERO)))
			if distance <= capture_radius + 0.0001:
				candidates.append({"unit": candidate, "distance": distance})
		candidates.sort_custom(func(left, right):
			if not is_equal_approx(float(left["distance"]), float(right["distance"])):
				return float(left["distance"]) < float(right["distance"])
			return int(left["unit"].get("id", -1)) < int(right["unit"].get("id", -1))
		)
		if not candidates.is_empty():
			var new_team := int(candidates[0]["unit"].get("team", 0))
			var old_team := int(objective_unit.get("team", 0))
			if new_team != old_team and (old_team <= 0 or not are_teams_allied(old_team, new_team)):
				transfer_entity_ownership(objective_unit, new_team, -1, "proximity_capture", true)
		sync_unit_victory_objective(objective_unit)


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
	technology_system.initialize_rule_resources(team, civilization.get("resources", []))
	apply_technology_commands(team, technology_system.initialize_team(team), false)
	apply_technology_commands(team, technology_system.apply_effect_bundle(team, int(civilization.get("tech_tree_id", -1))), false)
	resolve_automatic_technologies(team)


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
	tick_pipeline.add_active("static_combat", Callable(self, "_tick_static_combat"))
	tick_pipeline.add_active("death_lifecycle", Callable(self, "_tick_death_lifecycle"))
	tick_pipeline.add_active("resource_lifecycle", Callable(self, "_tick_resource_lifecycle"))
	tick_pipeline.add_active("production", Callable(production_system, "advance"))
	tick_pipeline.add_active("projectiles", Callable(combat_system, "advance_projectiles"))
	tick_pipeline.add_active("victory", Callable(self, "_tick_victory"))
	tick_pipeline.add_active("purge", Callable(self, "_tick_purge"))
	tick_pipeline.add_active("spatial_index", Callable(self, "_tick_spatial_index"))
	tick_pipeline.add_active("fog", Callable(visibility_system, "advance"))
	tick_pipeline.add_active("component_sync", Callable(self, "_tick_component_sync"))

	tick_pipeline.add_completed("death_lifecycle", Callable(self, "_tick_death_lifecycle"))
	tick_pipeline.add_completed("resource_lifecycle", Callable(self, "_tick_resource_lifecycle"))
	tick_pipeline.add_completed("projectiles", Callable(combat_system, "advance_projectiles"))
	tick_pipeline.add_completed("purge", Callable(self, "_tick_purge"))
	tick_pipeline.add_completed("spatial_index", Callable(self, "_tick_spatial_index"))
	tick_pipeline.add_completed("fog", Callable(visibility_system, "advance"))
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


func _tick_capture_previous_positions(_context: Dictionary) -> void:
	for unit in units:
		unit["previous_pos"] = unit["pos"]


func _tick_unit_orders(context: Dictionary) -> void:
	update_units(float(context["delta"]), int(context["player_team"]), int(context["enemy_team"]))


func _tick_capturable_objectives(_context: Dictionary) -> void:
	update_capturable_objectives()


func _tick_static_combat(context: Dictionary) -> void:
	update_static_combatants(float(context["delta"]), int(context["player_team"]))


func _tick_victory(context: Dictionary) -> void:
	check_battle_state(int(context["player_team"]), int(context["enemy_team"]), float(context["delta"]))


func _tick_death_lifecycle(context: Dictionary) -> void:
	advance_death_only(float(context["delta"]))


func _tick_resource_lifecycle(context: Dictionary) -> void:
	advance_resource_lifecycle(float(context["delta"]))


func _tick_purge(_context: Dictionary) -> void:
	purge_removed_units()


func _tick_spatial_index(_context: Dictionary) -> void:
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
	if rebuild_navigation:
		rebuild_navigation_grid()

func rebuild_navigation_grid() -> void:
	if navigation_grid != null:
		navigation_grid.configure_terrain_ids(Callable(self, "terrain_id_at_cell"))
		navigation_grid.rebuild(resource_nodes, buildings, static_obstructions)


func configure_demo_elevation(center: Vector2i, radius: int = 4, maximum_elevation: int = 2) -> void:
	terrain_elevation.generate_radial_hill(center, radius, maximum_elevation)
	navigation_grid.configure_elevation(Callable(self, "terrain_profile_at"))
	pathfinder.clear_cache()
	sync_entity_elevations()


func terrain_profile_at(cell: Vector2i) -> Dictionary:
	return terrain_elevation.cell_profile(cell)


func terrain_id_at_cell(cell: Vector2i) -> int:
	if int(forest_resource_counts.get(cell, 0)) > 0:
		return TerrainRules.TERRAIN_IDS["forest_floor"]
	return int(map_terrain_ids.get(cell, TerrainRules.terrain_id_for_logical(TerrainRules.terrain_at(cell))))


func _register_forest_resource(resource: Dictionary) -> void:
	var cell := Vector2i(floori(float(resource.get("pos", Vector2.ZERO).x)), floori(float(resource.get("pos", Vector2.ZERO).y)))
	forest_resource_counts[cell] = int(forest_resource_counts.get(cell, 0)) + 1
	terrain_revision += 1


func _unregister_forest_resource(resource: Dictionary) -> void:
	if String(resource.get("kind", "")) != "tree":
		return
	var position: Vector2 = resource.get("pos", Vector2.ZERO)
	var cell := Vector2i(floori(position.x), floori(position.y))
	var remaining := int(forest_resource_counts.get(cell, 0)) - 1
	if remaining > 0:
		forest_resource_counts[cell] = remaining
	else:
		forest_resource_counts.erase(cell)
	terrain_revision += 1


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
	visibility_system.advance()

func query_units_near(position: Vector2, radius: float) -> Array:
	return spatial_index.query_circle(position, radius, "unit")


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
	FormationCohesion.update(units)
	_release_finished_combat_reservations()
	for unit in units:
		if unit["hp"] <= 0.0:
			begin_death(unit)
			continue
		unit["cooldown"] = maxf(0.0, unit["cooldown"] - delta)
		unit["work"] = maxf(0.0, unit["work"] - delta)
		conversion_system.advance_faith(unit, delta)
		_update_huntable_reaction(unit)
		var moving := false
		var animation_state := AnimationController.IDLE
		var attack_target: Variant = null
		match unit["task"]:
			"trade":
				var trade_update := trade_system.advance_unit(unit, delta)
				moving = bool(trade_update.get("moving", false))
				animation_state = String(trade_update.get("animation_state", AnimationController.IDLE))
			"attack":
				var enemy = find_combat_target(unit["target_id"])
				if enemy == null or enemy["hp"] <= 0.0:
					_finish_combat(unit)
				elif are_teams_allied(int(unit.get("team", 0)), int(enemy.get("team", 0))):
					_finish_combat(unit, "target_became_allied")
				elif bool(unit.get("attack_autonomous", false)) and not is_entity_visible_to(int(unit.get("team", 0)), enemy):
					_finish_combat(unit, "target_lost")
				elif String(unit.get("stance", "passive")) == "stand_ground" and not CombatRules.is_in_range(unit, enemy):
					_finish_combat(unit, "stand_ground_range")
				elif bool(unit.get("attack_autonomous", false)) and Vector2(unit.get("combat_leash_origin", unit["pos"])).distance_to(Vector2(enemy["pos"])) > float(unit.get("chase_range", 0.0)) + 0.0001:
					_finish_combat(unit, "leash_exceeded")
				else:
					if OrderPipeline.phase(unit) == OrderPipeline.RECOVER and unit["cooldown"] <= 0.0:
						OrderPipeline.restart(unit)
					var combat_destination := FormationCombat.destination(unit, enemy)
					unit["combat_destination"] = combat_destination
					var too_close := CombatRules.is_too_close(unit, enemy)
					if not CombatRules.is_in_range(unit, enemy) or too_close:
						ensure_navigation_destination(unit, combat_destination)
						moving = move_unit(unit, delta)
					else:
						OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
						face_unit_toward(unit, enemy["pos"])
						if unit["cooldown"] <= 0.0:
							OrderPipeline.transition(unit, OrderPipeline.PERFORM_ACTION)
							animation_state = AnimationController.ATTACK_WINDUP
							attack_target = enemy
						else:
							OrderPipeline.transition(unit, OrderPipeline.RECOVER)
							animation_state = AnimationController.ATTACK_RECOVER
			"convert":
				var conversion_target = find_combat_target(unit["target_id"])
				var conversion_rejection := conversion_system.validate_target(unit, conversion_target, false)
				if not conversion_rejection.is_empty():
					_finish_conversion(unit, conversion_rejection)
				elif not is_entity_visible_to(int(unit.get("team", 0)), conversion_target):
					_finish_conversion(unit, "target_lost")
				elif not conversion_system.is_in_range(unit, conversion_target):
					var conversion_destination: Variant = _conversion_destination(unit, conversion_target)
					if conversion_destination == null:
						_finish_conversion(unit, "target_unreachable")
					else:
						ensure_navigation_destination(unit, conversion_destination)
						moving = move_unit(unit, delta)
				else:
					release_unit_destination(unit)
					OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
					face_unit_toward(unit, conversion_target["pos"])
					OrderPipeline.transition(unit, OrderPipeline.PERFORM_ACTION)
					animation_state = AnimationController.CONVERT
					var conversion_result := conversion_system.advance_conversion(unit, conversion_target, delta)
					if conversion_result == "success":
						_finish_conversion(unit, "conversion_succeeded")
					elif conversion_result != "pending":
						_finish_conversion(unit, conversion_result)
			"heal":
				var healing_target = find_unit(unit["target_id"])
				var healing_rejection := healing_system.validate_target(unit, healing_target)
				if healing_rejection == "target_fully_healed":
					_finish_healing(unit, "healing_complete", true)
				elif not healing_rejection.is_empty():
					_finish_healing(unit, healing_rejection)
				elif not is_entity_visible_to(int(unit.get("team", 0)), healing_target):
					_finish_healing(unit, "target_lost")
				elif not healing_system.is_in_range(unit, healing_target):
					ensure_navigation_destination(unit, healing_target["pos"])
					moving = move_unit(unit, delta)
				else:
					release_unit_destination(unit)
					OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
					face_unit_toward(unit, healing_target["pos"])
					OrderPipeline.transition(unit, OrderPipeline.PERFORM_ACTION)
					animation_state = AnimationController.HEAL
					var healing_result := healing_system.advance_healing(unit, healing_target, delta)
					if healing_result == "complete":
						_finish_healing(unit, "healing_complete", true)
					elif healing_result != "pending":
						_finish_healing(unit, healing_result)
			"gather":
				var gather_update := update_gather_order(unit, delta)
				moving = bool(gather_update.get("moving", false))
				animation_state = String(gather_update.get("animation_state", AnimationController.IDLE))
			"build", "repair":
				var building_update := update_building_order(unit, delta)
				moving = bool(building_update.get("moving", false))
				animation_state = String(building_update.get("animation_state", AnimationController.IDLE))
			_:
				moving = move_unit(unit, delta)

		if moving and animation_state != AnimationController.CARRY:
			animation_state = AnimationController.MOVE
		var restart_attack_clip := animation_state == AnimationController.ATTACK_WINDUP and String(unit.get("anim_state", "")) == AnimationController.ATTACK_RECOVER
		AnimationController.update(unit, animation_state, delta, restart_attack_clip)
		if attack_target != null:
			apply_attack_frame_event(unit, attack_target, player_team)
		EntityComponents.sync_dynamic(unit)


func update_static_combatants(delta: float, player_team: int) -> void:
	for building_value in buildings:
		var building: Dictionary = building_value
		if float(building.get("hp", 0.0)) <= 0.0 or String(building.get("state", "complete")) != "complete" or not bool(building.get("combat_enabled", false)):
			continue
		building["cooldown"] = maxf(0.0, float(building.get("cooldown", 0.0)) - delta)
		var animation_state := AnimationController.IDLE
		var attack_target: Variant = null
		if String(building.get("task", "idle")) == "attack":
			var target = find_combat_target(int(building.get("target_id", -1)))
			if target == null or float(target.get("hp", 0.0)) <= 0.0:
				_finish_combat(building)
			elif are_teams_allied(int(building.get("team", 0)), int(target.get("team", 0))):
				_finish_combat(building, "target_became_allied")
			elif bool(building.get("attack_autonomous", false)) and not is_entity_visible_to(int(building.get("team", 0)), target):
				_finish_combat(building, "target_lost")
			elif not CombatRules.is_in_range(building, target):
				_finish_combat(building, "stand_ground_range")
			else:
				if OrderPipeline.phase(building) == OrderPipeline.RECOVER and float(building.get("cooldown", 0.0)) <= 0.0:
					OrderPipeline.restart(building)
				OrderPipeline.transition(building, OrderPipeline.FACE_TARGET)
				face_unit_toward(building, Vector2(target.get("pos", building.get("pos", Vector2.ZERO))))
				if float(building.get("cooldown", 0.0)) <= 0.0:
					OrderPipeline.transition(building, OrderPipeline.PERFORM_ACTION)
					animation_state = AnimationController.ATTACK_WINDUP
					attack_target = target
				else:
					OrderPipeline.transition(building, OrderPipeline.RECOVER)
					animation_state = AnimationController.ATTACK_RECOVER
		var restart_attack_clip := animation_state == AnimationController.ATTACK_WINDUP and String(building.get("anim_state", "")) == AnimationController.ATTACK_RECOVER
		AnimationController.update(building, animation_state, delta, restart_attack_clip)
		if attack_target != null:
			apply_attack_frame_event(building, attack_target, player_team)
		EntityComponents.sync_dynamic(building)

func apply_attack_frame_event(unit: Dictionary, enemy: Dictionary, player_team: int) -> void:
	combat_system.apply_attack_frame_event(unit, enemy, player_team)


func attack_animation_spec(unit: Dictionary) -> Dictionary:
	var role_source_id := int(unit.get("worker_role_source_unit_id", -1))
	if role_source_id >= 0:
		var role_source := object_record_by_id(role_source_id, int(unit.get("team", 0)))
		var graphic_id := int(role_source.get("graphics", {}).get("attack", -1))
		var graphic: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {}).duplicate(true)
		var event_frame := int(role_source.get("combat", {}).get("frame_delay", 0))
		graphic["damage_frame"] = event_frame
		graphic["projectile_release_frame"] = event_frame
		return graphic
	var source := object_record_by_id(int(unit.get("source_unit_id", -1)), int(unit.get("team", 0)))
	if not source.is_empty():
		var graphic_id := int(source.get("graphics", {}).get("attack", -1))
		var graphic: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {}).duplicate(true)
		if not graphic.is_empty():
			var event_frame := int(source.get("combat", {}).get("frame_delay", 0))
			graphic["damage_frame"] = event_frame
			graphic["projectile_release_frame"] = event_frame
			return graphic
	return unit_stats(String(unit.get("kind", ""))).get("animations", {}).get("attack", {})


func spawn_projectile(attacker: Dictionary, target: Dictionary) -> Dictionary:
	return combat_system.spawn_projectile(attacker, target)


func update_projectiles(delta: float, player_team: int) -> void:
	combat_system.update_projectiles(delta, player_team)


func death_animation_duration(kind: String) -> float:
	var spec: Dictionary = unit_stats(kind).get("animations", {}).get("death", {})
	return maxf(0.05, float(spec.get("frames_per_angle", 1)) * float(spec.get("frame_rate", 0.1)))


func building_death_animation_duration(source: Dictionary) -> float:
	var graphic_id := int(source.get("graphics", {}).get("death", -1))
	var graphic: Dictionary = graphics_catalog_data.get("graphics", {}).get(str(graphic_id), {})
	return maxf(0.05, float(graphic.get("frames_per_angle", 1)) * float(graphic.get("frame_rate", 0.1)))


func corpse_animation_duration(source: Dictionary, team: int) -> float:
	var corpse_id := int(source.get("links", {}).get("dead_unit_id", -1))
	if corpse_id < 0:
		return 0.0
	var corpse_source := object_record_by_id(corpse_id, team)
	var corpse_graphic_id := int(corpse_source.get("graphics", {}).get("idle", -1))
	var graphic: Dictionary = graphics_catalog_data.get("graphics", {}).get(str(corpse_graphic_id), {})
	if graphic.is_empty():
		return maxf(0.0, float(corpse_source.get("resources", {}).get("decay", 0.0)))
	return maxf(0.0, float(graphic.get("frames_per_angle", 1)) * float(graphic.get("frame_rate", 0.0)))


func begin_death(unit: Dictionary) -> void:
	if String(unit.get("death_phase", "alive")) != "alive":
		return
	transport_system.destroy_cargo(unit)
	conversion_system.cancel(unit, "unit_died")
	healing_system.cancel(unit, "unit_died")
	_emit_domain_event("death", {
		"entity_id": int(unit.get("id", -1)),
		"entity_category": "unit",
		"kind": String(unit.get("kind", "")),
		"team": int(unit.get("team", 0)),
	})
	unit["hp"] = minf(0.0, float(unit.get("hp", 0.0)))
	unit["selected"] = false
	unit["task"] = "die"
	unit["target_id"] = -1
	release_resource_approach_slot(unit)
	release_building_approach_slot(unit)
	unit["resource_id"] = -1
	unit["target_building_id"] = -1
	unit["death_phase"] = "dying"
	unit["death_elapsed"] = 0.0
	unit["death_complete"] = false
	release_unit_destination(unit)
	OrderPipeline.complete(unit, "unit_died")
	unit["formation_group_id"] = -1
	unit["formation_slot_id"] = -1
	unit["formation_home"] = null
	unit["formation_slot_mode"] = "none"
	unit["combat_destination"] = null
	if not bool(unit.get("population_released", false)):
		var team := int(unit.get("team", 0))
		economy_system.add_population(team, -int(unit.get("population_cost", 0)))
		unit["population_released"] = true
	AnimationController.update(unit, AnimationController.DIE, 0.0)
	EntityComponents.sync_dynamic(unit)


func begin_entity_death(entity: Dictionary) -> void:
	if find_unit(int(entity.get("id", -1))) != null:
		begin_death(entity)
		return
	begin_building_destruction(entity)


func begin_building_destruction(building: Dictionary) -> void:
	if building == null or String(building.get("death_phase", "alive")) != "alive":
		return
	_emit_domain_event("death", {
		"entity_id": int(building.get("id", -1)),
		"entity_category": "building",
		"kind": String(building.get("kind", "")),
		"team": int(building.get("team", 0)),
	})
	while not building.get("production_queue", []).is_empty():
		production_system.cancel(int(building.get("id", -1)), 0)
	deactivate_population_support(building)
	deactivate_building_victory_objective(building)
	if bool(building.get("harvestable", false)):
		var building_id := int(building.get("id", -1))
		resource_approach_slots.erase(building_id)
		for unit in units:
			if int(unit.get("resource_id", -1)) == building_id:
				finish_gather_order(unit, "resource_destroyed")
		building["resource_state"] = "destroyed"
	building["hp"] = 0.0
	building["state"] = "destroyed"
	building["builders"] = {}
	building["production_progress"] = 0.0
	building["death_phase"] = "dying"
	building["death_elapsed"] = 0.0
	building["removed"] = false
	EntityComponents.sync_dynamic(building)
	refresh_building_connectivity()
	rebuild_navigation_grid()


func advance_death(unit: Dictionary, delta: float) -> void:
	match String(unit.get("death_phase", "alive")):
		"dying":
			AnimationController.update(unit, AnimationController.DIE, delta)
			unit["death_elapsed"] = float(unit.get("anim", 0.0))
			if float(unit["death_elapsed"]) + 0.000001 >= float(unit.get("death_duration", 0.1)):
				unit["death_phase"] = "corpse"
				unit["death_complete"] = true
				unit["animation_events_fired"]["death_complete_frame"] = true
				unit["anim_state"] = AnimationController.DECAY
				unit["anim"] = 0.0
		"corpse":
			unit["corpse_elapsed"] = float(unit.get("corpse_elapsed", 0.0)) + maxf(0.0, delta)
			unit["anim"] = unit["corpse_elapsed"]
			if float(unit["corpse_elapsed"]) + 0.000001 >= float(unit.get("corpse_duration", 0.0)):
				unit["death_phase"] = "removed"
				unit["removed"] = true
	if String(unit.get("death_phase", "")) == "corpse" and entity_has_behavior_tag(unit, "huntable"):
		_complete_huntable_death(unit)
	EntityComponents.sync_dynamic(unit)


func _complete_huntable_death(huntable: Dictionary) -> void:
	if bool(huntable.get("huntable_carcass_spawned", false)):
		return
	var metadata: Dictionary = data_repository.runtime_metadata(String(huntable.get("kind", "")))
	var carcass_alias := String(metadata.get("carcass_alias", ""))
	var harvest_amount := maxi(0, int(metadata.get("harvest_amount", 0)))
	if carcass_alias.is_empty() or harvest_amount <= 0:
		return
	huntable["huntable_carcass_spawned"] = true
	var carcass := add_resource(carcass_alias, Vector2(huntable.get("pos", Vector2.ZERO)), harvest_amount)
	carcass["origin_entity_id"] = int(huntable.get("id", -1))
	carcass["origin_source_unit_id"] = int(huntable.get("source_unit_id", -1))
	huntable["death_phase"] = "removed"
	huntable["removed"] = true
	var hunters: Array = []
	for candidate in units:
		if float(candidate.get("hp", 0.0)) > 0.0 and entity_is_worker(candidate) and int(candidate.get("pending_hunt_target_id", -1)) == int(huntable.get("id", -1)):
			hunters.append(candidate)
	if not hunters.is_empty():
		assign_command_gather(hunters, int(carcass["id"]))
	_emit_domain_event("huntable_became_resource", {
		"huntable_id": int(huntable.get("id", -1)),
		"carcass_id": int(carcass["id"]),
		"carcass_kind": carcass_alias,
		"amount": harvest_amount,
	})


func advance_death_only(delta: float) -> void:
	for unit in units:
		if float(unit.get("hp", 0.0)) <= 0.0:
			begin_death(unit)
			advance_death(unit, delta)
	for building in buildings:
		if float(building.get("hp", 0.0)) <= 0.0:
			begin_building_destruction(building)
			building["death_elapsed"] = float(building.get("death_elapsed", 0.0)) + maxf(0.0, delta)
			if float(building["death_elapsed"]) + 0.000001 >= float(building.get("death_duration", 0.05)):
				building["death_phase"] = "removed"
				building["removed"] = true
			EntityComponents.sync_dynamic(building)


func purge_removed_units() -> void:
	for index in range(units.size() - 1, -1, -1):
		if bool(units[index].get("removed", false)):
			units.remove_at(index)
	for index in range(buildings.size() - 1, -1, -1):
		if bool(buildings[index].get("removed", false)):
			buildings.remove_at(index)

func move_unit(unit: Dictionary, delta: float) -> bool:
	var difference: Vector2 = unit["target"] - unit["pos"]
	if difference.length() < 0.035:
		var arrival_displacement := difference
		unit["pos"] = unit["target"]
		unit["elevation"] = elevation_at(unit["pos"])
		unit["actual_velocity"] = arrival_displacement / delta if delta > 0.0 else Vector2.ZERO
		if arrival_displacement.length_squared() > 0.000001:
			var arrival_facing := facing_for_vector(arrival_displacement)
			unit["movement_facing"] = arrival_facing
			unit["desired_facing"] = arrival_facing
			unit["facing"] = arrival_facing
		var path: Array = unit.get("path", [])
		var next_index := int(unit.get("path_index", 0)) + 1
		if next_index < path.size():
			unit["path_index"] = next_index
			unit["target"] = path[next_index]
			OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
			return true
		unit["path"] = []
		unit["path_index"] = 0
		StuckRecovery.reset(unit)
		if unit["task"] in ["move", "attack_move"]:
			if destination_reservations.is_occupied(unit):
				unit["task"] = "idle"
				OrderPipeline.complete(unit, "destination_reached")
				restore_formation_facing(unit)
			else:
				assign_unit_destination(unit, unit["reserved_destination"], false)
		elif unit["task"] in ["attack", "gather"]:
			OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
		return false

	var start_position: Vector2 = unit["pos"]
	var search_radius := float(unit.get("footprint_radius", 0.3)) + 1.0
	var neighbors := spatial_index.query_neighbors(unit, search_radius, "unit")
	var movement: Dictionary = LocalMovement.calculate(unit, unit["target"], neighbors, navigation_grid, delta)
	unit["desired_velocity"] = movement["desired_velocity"]
	unit["actual_velocity"] = movement["actual_velocity"]
	if Vector2(unit["desired_velocity"]).length_squared() > 0.000001:
		unit["desired_facing"] = facing_for_vector(unit["desired_velocity"])
	if movement["reason"] != "":
		unit["diagnostic_reason"] = movement["reason"]
	var step: Vector2 = unit["actual_velocity"] * delta
	if step.length() >= difference.length() and step.dot(difference) > 0.0:
		unit["pos"] = unit["target"]
	else:
		unit["pos"] += step
	unit["pos"] = Coordinates.clamp_world(unit["pos"], map_size)
	unit["elevation"] = elevation_at(unit["pos"])
	var actual_displacement: Vector2 = unit["pos"] - start_position
	unit["actual_velocity"] = actual_displacement / delta if delta > 0.0 else Vector2.ZERO
	if actual_displacement.length_squared() > 0.000001:
		var movement_facing := facing_for_vector(actual_displacement)
		unit["movement_facing"] = movement_facing
		unit["facing"] = movement_facing
	var recovery_action := StuckRecovery.update(unit, actual_displacement.length())
	match recovery_action:
		"local_repath":
			assign_unit_destination(unit, unit["destination"], false)
		"global_repath":
			pathfinder.clear_cache()
			assign_unit_destination(unit, unit["destination"], false)
		"stop":
			unit["path"] = []
			unit["path_index"] = 0
			unit["target"] = unit["pos"]
			unit["task"] = "idle"
			OrderPipeline.complete(unit, "stuck")
			release_unit_destination(unit)
			restore_formation_facing(unit)
			return false
	return true

func face_unit_toward(unit: Dictionary, target: Vector2) -> void:
	var difference: Vector2 = target - unit["pos"]
	if difference.length_squared() > 0.0001:
		var action_facing := facing_for_vector(difference)
		unit["desired_facing"] = action_facing
		unit["action_facing"] = action_facing
		unit["facing"] = action_facing

func restore_formation_facing(unit: Dictionary) -> void:
	var forward: Vector2 = unit.get("formation_forward", Vector2.ZERO)
	if forward.length_squared() > 0.0001:
		var formation_front := int(unit.get("formation_facing", facing_for_vector(forward)))
		unit["desired_facing"] = formation_front
		unit["action_facing"] = formation_front
		unit["facing"] = formation_front

func facing_for_vector(direction: Vector2) -> int:
	return FacingConvention.logical_for_world(direction)

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
	if victory_system.rules.any(func(rule): return String(rule.get("type", "conquest")) == "conquest"):
		for team_value in teams:
			var team := int(team_value)
			if player_registry.status(team) != PlayerRegistry.ACTIVE:
				continue
			var has_units := get_all_units_including_embarked().any(func(unit): return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0)
			var has_buildings := buildings.any(func(building): return int(building.get("team", 0)) == team and float(building.get("hp", 0.0)) > 0.0 and bool(building.get("counts_for_conquest", true)))
			if not has_units and not has_buildings and player_registry.defeat(team):
				_emit_domain_event("player_defeated", {"team": team})
	var resources: Dictionary = {}
	var technologies: Dictionary = {}
	for team in teams:
		resources[team] = {}
		for resource_id in range(4):
			resources[team][resource_id] = get_resource_amount(team, resource_id)
		technologies[team] = technology_system.researched_ids(team)
	var victory_context := {
		"teams": teams,
		"participant_count": teams.size(),
		"player_states": _player_states_by_team(),
		"units": get_all_units_including_embarked(),
		"buildings": buildings,
		"resource_nodes": get_resources(),
		"objectives": victory_objectives,
		"scores": score_by_team,
		"resources": resources,
		"technologies": technologies,
		"relations": _team_relations(),
	}
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
	for unit in units:
		if unit["id"] == id:
			return unit
	return null


func find_combat_target(id: int) -> Variant:
	var unit = find_unit(id)
	if unit != null and not entity_has_behavior_tag(unit, "noncombat_target"):
		return unit
	return find_building(id)


func get_combat_targets() -> Array:
	var result: Array = []
	for unit in units:
		if float(unit.get("hp", 0.0)) > 0.0 and not entity_has_behavior_tag(unit, "noncombat_target"):
			result.append(unit)
	for building in buildings:
		if float(building.get("hp", 0.0)) > 0.0:
			result.append(building)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


func get_combat_attackers() -> Array:
	var result: Array = []
	for unit in units:
		if float(unit.get("hp", 0.0)) > 0.0 and bool(unit.get("combat_enabled", false)):
			result.append(unit)
	for building in buildings:
		if float(building.get("hp", 0.0)) > 0.0 and String(building.get("state", "complete")) == "complete" and bool(building.get("combat_enabled", false)):
			result.append(building)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
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
	var allowed_domains: Array = data_repository.runtime_metadata(String(resource.get("kind", ""))).get("allowed_gatherer_domains", [])
	if allowed_domains.is_empty():
		allowed_domains = ["land"]
	return String(worker.get("movement_domain", "land")) in allowed_domains

func update_gather_order(worker: Dictionary, delta: float) -> Dictionary:
	if not entity_is_worker(worker):
		finish_gather_order(worker, "not_a_worker")
		return {"moving": false, "animation_state": AnimationController.IDLE}
	if String(worker.get("gather_stage", "none")) == "returning":
		return update_dropoff_order(worker, delta)

	var resource: Variant = find_resource(int(worker.get("resource_id", -1)))
	if resource == null or int(resource.get("amount", 0)) <= 0 or not resource_accessible_to_team(resource, int(worker.get("team", 0))) or not resource_allows_worker(resource, worker):
		release_resource_approach_slot(worker)
		if float(worker.get("carried_amount", 0.0)) > 0.0:
			begin_resource_return(worker)
			return {"moving": false, "animation_state": AnimationController.CARRY}
		finish_gather_order(worker, "resource_unavailable")
		return {"moving": false, "animation_state": AnimationController.IDLE}

	var capacity := maxf(0.0, float(worker.get("carry_capacity", 0.0)))
	if capacity > 0.0 and float(worker.get("carried_amount", 0.0)) >= capacity - 0.0001:
		begin_resource_return(worker)
		return {"moving": false, "animation_state": AnimationController.CARRY}

	if not worker.get("resource_approach_slot") is Vector2:
		if not prepare_resource_approach(worker, resource):
			finish_gather_order(worker, "no_approach_slot")
			return {"moving": false, "animation_state": AnimationController.IDLE}
	var approach: Vector2 = worker["resource_approach_slot"]
	if worker["pos"].distance_squared_to(approach) > 0.0144:
		worker["gather_stage"] = "approaching"
		ensure_navigation_destination(worker, approach)
		return {"moving": move_unit(worker, delta), "animation_state": AnimationController.MOVE}

	worker["gather_stage"] = "harvesting"
	OrderPipeline.transition(worker, OrderPipeline.FACE_TARGET)
	face_unit_toward(worker, resource["pos"])
	if float(worker.get("work", 0.0)) > 0.0:
		OrderPipeline.transition(worker, OrderPipeline.RECOVER)
		return {"moving": false, "animation_state": AnimationController.GATHER}

	OrderPipeline.restart(worker)
	OrderPipeline.transition(worker, OrderPipeline.FACE_TARGET)
	OrderPipeline.transition(worker, OrderPipeline.PERFORM_ACTION)
	gather(int(resource["id"]), worker)
	worker["work"] = maxf(0.05, float(worker.get("gather_interval", 1.0)))
	worker["gather_cycles"] = int(worker.get("gather_cycles", 0)) + 1
	OrderPipeline.transition(worker, OrderPipeline.RECOVER)
	if int(resource.get("amount", 0)) <= 0 or (capacity > 0.0 and float(worker.get("carried_amount", 0.0)) >= capacity - 0.0001):
		begin_resource_return(worker)
	return {"moving": false, "animation_state": AnimationController.GATHER}


func update_dropoff_order(worker: Dictionary, delta: float) -> Dictionary:
	if float(worker.get("carried_amount", 0.0)) <= 0.0:
		var empty_resource: Variant = find_resource(int(worker.get("resource_id", -1)))
		if empty_resource != null and int(empty_resource.get("amount", 0)) > 0 and resource_accessible_to_team(empty_resource, int(worker.get("team", 0))) and prepare_resource_approach(worker, empty_resource):
			OrderPipeline.restart(worker)
			return {"moving": false, "animation_state": AnimationController.IDLE}
		finish_gather_order(worker, "cycle_complete")
		return {"moving": false, "animation_state": AnimationController.IDLE}

	var dropoff: Variant = find_building(int(worker.get("dropoff_id", -1)))
	if dropoff == null or float(dropoff.get("hp", 0.0)) <= 0.0:
		if not begin_resource_return(worker):
			finish_gather_order(worker, "no_dropoff")
			return {"moving": false, "animation_state": AnimationController.IDLE}
		dropoff = find_building(int(worker.get("dropoff_id", -1)))
	var destination: Variant = worker.get("dropoff_position")
	if not destination is Vector2:
		destination = dropoff_approach_position(worker, dropoff)
		worker["dropoff_position"] = destination
	if worker["pos"].distance_squared_to(destination) > 0.0144:
		ensure_navigation_destination(worker, destination)
		return {"moving": move_unit(worker, delta), "animation_state": AnimationController.CARRY}

	OrderPipeline.transition(worker, OrderPipeline.FACE_TARGET)
	face_unit_toward(worker, dropoff["pos"])
	OrderPipeline.transition(worker, OrderPipeline.PERFORM_ACTION)
	deposit_carried_resources(worker)
	worker["deposit_cycles"] = int(worker.get("deposit_cycles", 0)) + 1
	OrderPipeline.transition(worker, OrderPipeline.RECOVER)
	var resource: Variant = find_resource(int(worker.get("resource_id", -1)))
	if resource != null and int(resource.get("amount", 0)) > 0:
		OrderPipeline.restart(worker)
		if prepare_resource_approach(worker, resource):
			return {"moving": false, "animation_state": AnimationController.IDLE}
	finish_gather_order(worker, "resource_depleted")
	return {"moving": false, "animation_state": AnimationController.IDLE}


func gather(resource_id: int, worker: Dictionary) -> float:
	var resource: Variant = find_resource(resource_id)
	if resource == null or int(resource.get("amount", 0)) <= 0:
		return 0.0
	var capacity := maxf(0.0, float(worker.get("carry_capacity", 0.0)))
	var remaining_capacity := maxf(0.0, capacity - float(worker.get("carried_amount", 0.0)))
	if remaining_capacity <= 0.0:
		return 0.0
	var amount := minf(1.0, minf(float(resource["amount"]), remaining_capacity))
	var resource_type_id := int(resource.get("resource_type_id", resource_type_for(String(resource.get("kind", "")), resource_stats(String(resource.get("kind", ""))))))
	var carried_type := int(worker.get("carried_resource_type_id", -1))
	if carried_type >= 0 and carried_type != resource_type_id and float(worker.get("carried_amount", 0.0)) > 0.0:
		return 0.0
	resource["amount"] = maxi(0, int(resource["amount"]) - int(amount))
	worker["carried_amount"] = float(worker.get("carried_amount", 0.0)) + amount
	worker["carried_resource_type_id"] = resource_type_id
	_emit_domain_event("resource_gathered", {
		"worker_id": int(worker.get("id", -1)),
		"resource_id": int(resource.get("id", -1)),
		"resource_type_id": resource_type_id,
		"amount": amount,
		"remaining": int(resource["amount"]),
		"carried": float(worker["carried_amount"]),
	})
	update_resource_state(resource)
	EntityComponents.sync_dynamic(worker)
	return amount


func deposit_carried_resources(worker: Dictionary) -> int:
	var amount := maxi(0, roundi(float(worker.get("carried_amount", 0.0))))
	var team := int(worker.get("team", 0))
	var resource_type_id := int(worker.get("carried_resource_type_id", -1))
	if resource_type_id >= 0:
		economy_system.change_resource_amount(team, resource_type_id, amount)
	if amount > 0:
		_emit_domain_event("resources_deposited", {
			"worker_id": int(worker.get("id", -1)),
			"team": team,
			"resource_type_id": resource_type_id,
			"amount": amount,
			"stockpile": economy_system.get_resource_amount(team, resource_type_id),
		})
	worker["carried_amount"] = 0.0
	worker["carried_resource_type_id"] = -1
	worker["dropoff_id"] = -1
	worker["dropoff_position"] = null
	EntityComponents.sync_dynamic(worker)
	return amount


func prepare_resource_approach(worker: Dictionary, resource: Dictionary) -> bool:
	var slot: Variant = reserve_resource_approach_slot(worker, resource)
	if not slot is Vector2:
		return false
	worker["gather_stage"] = "approaching"
	worker["dropoff_id"] = -1
	worker["dropoff_position"] = null
	return assign_unit_destination(worker, slot, false) or worker["pos"].distance_squared_to(slot) <= 0.0144


func reserve_resource_approach_slot(worker: Dictionary, resource: Dictionary) -> Variant:
	if worker.get("resource_approach_slot") is Vector2:
		return worker["resource_approach_slot"]
	var resource_id := int(resource["id"])
	var reservations: Dictionary = resource_approach_slots.get(resource_id, {})
	var runtime_metadata: Dictionary = data_repository.runtime_metadata(String(resource.get("kind", "")))
	var maximum_gatherers := maxi(0, int(runtime_metadata.get("max_gatherers", 0)))
	if maximum_gatherers > 0 and reservations.size() >= maximum_gatherers:
		return null
	var candidates := resource_approach_candidates(worker, resource, runtime_metadata)
	for offset in range(candidates.size()):
		var slot_index := posmod(int(worker["id"]) + offset, candidates.size())
		var candidate: Vector2 = candidates[slot_index]
		if not navigation_grid.is_position_walkable_for(candidate, float(worker.get("footprint_radius", 0.3)), String(worker.get("movement_domain", "land")), int(worker.get("terrain_restriction", -1))):
			continue
		var occupied := false
		for existing_value in reservations.values():
			if Vector2(existing_value).distance_squared_to(candidate) < 0.09:
				occupied = true
				break
		if occupied:
			continue
		reservations[int(worker["id"])] = candidate
		resource_approach_slots[resource_id] = reservations
		worker["resource_approach_slot"] = candidate
		return candidate
	return null


func resource_approach_candidates(worker: Dictionary, resource: Dictionary, runtime_metadata: Dictionary = {}) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if String(runtime_metadata.get("approach_mode", "perimeter")) == "interior":
		var half_size: Vector2 = resource.get("footprint", {}).get("half_size", Vector2(0.5, 0.5))
		var margin := float(worker.get("footprint_radius", 0.3)) + 0.08
		var extent := Vector2(maxf(0.0, half_size.x - margin), maxf(0.0, half_size.y - margin))
		for offset in [Vector2.ZERO, Vector2(-0.65, -0.65), Vector2(0.65, -0.65), Vector2(0.65, 0.65), Vector2(-0.65, 0.65), Vector2(0.0, -0.75), Vector2(0.75, 0.0), Vector2(0.0, 0.75), Vector2(-0.75, 0.0)]:
			result.append(Coordinates.clamp_world(Vector2(resource["pos"]) + offset * extent, map_size))
		return result
	var distance := float(resource.get("footprint_radius", 0.2)) + float(worker.get("footprint_radius", 0.3)) + 0.12
	for slot_index in range(16):
		var angle := PI + TAU * float(slot_index) / 16.0
		result.append(Coordinates.clamp_world(Vector2(resource["pos"]) + Vector2(cos(angle), sin(angle)) * distance, map_size))
	return result


func release_resource_approach_slot(worker: Dictionary) -> void:
	var resource_id := int(worker.get("resource_id", -1))
	if resource_approach_slots.has(resource_id):
		var reservations: Dictionary = resource_approach_slots[resource_id]
		reservations.erase(int(worker.get("id", -1)))
		if reservations.is_empty():
			resource_approach_slots.erase(resource_id)
		else:
			resource_approach_slots[resource_id] = reservations
	worker["resource_approach_slot"] = null


func begin_resource_return(worker: Dictionary) -> bool:
	release_resource_approach_slot(worker)
	var dropoff: Variant = nearest_dropoff(worker)
	if dropoff == null:
		return false
	worker["gather_stage"] = "returning"
	worker["dropoff_id"] = int(dropoff["id"])
	worker["dropoff_position"] = dropoff_approach_position(worker, dropoff)
	assign_unit_destination(worker, worker["dropoff_position"], false)
	return true


func nearest_dropoff(worker: Dictionary) -> Variant:
	var drop_site_ids: Array = worker.get("components", {}).get("worker", {}).get("drop_site_ids", [])
	var carried_resource_type := int(worker.get("carried_resource_type_id", -1))
	var allowed: Dictionary = {}
	for value in drop_site_ids:
		if int(value) >= 0:
			allowed[int(value)] = true
	var candidates: Array = []
	for building in buildings:
		if int(building.get("team", 0)) != int(worker.get("team", 0)) or float(building.get("hp", 0.0)) <= 0.0:
			continue
		if not dropoff_accepts_resource(building, carried_resource_type, allowed):
			continue
		candidates.append(building)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left, right):
		var left_distance: float = worker["pos"].distance_squared_to(left["pos"])
		var right_distance: float = worker["pos"].distance_squared_to(right["pos"])
		return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and int(left["id"]) < int(right["id"]))
	)
	return candidates[0]


func dropoff_accepts_resource(building: Dictionary, resource_type_id: int, worker_allowed_source_ids: Dictionary = {}) -> bool:
	if building == null or String(building.get("state", "complete")) != "complete" or float(building.get("hp", 0.0)) <= 0.0:
		return false
	var source_id := int(building.get("components", {}).get("identity", {}).get("source_unit_id", -1))
	# A task form's original drop-site list is more specific than the building's
	# generic stockpile categories (Hunter food is delivered to Storage Pit).
	if not worker_allowed_source_ids.is_empty():
		var lineage: Array = building.get("unit_lineage", [source_id])
		return lineage.any(func(value): return worker_allowed_source_ids.has(int(value)))
	var accepted_resource_ids: Array = data_repository.runtime_metadata(String(building.get("kind", ""))).get("accepted_resource_type_ids", [])
	if not accepted_resource_ids.is_empty():
		return accepted_resource_ids.any(func(value): return int(value) == resource_type_id)
	return entity_has_behavior_tag(building, "drop_site")


func assign_command_return_resources(selected: Array, target_building_id: int = -1) -> bool:
	var assigned := 0
	for worker in selected:
		if not entity_is_worker(worker) or float(worker.get("carried_amount", 0.0)) <= 0.0:
			continue
		if int(worker.get("worker_role_source_unit_id", -1)) < 0:
			worker_role_system.apply(worker, worker_role_system.profile_for_resource_type(worker, int(worker.get("carried_resource_type_id", -1))), false)
		var drop_site_ids: Array = worker.get("components", {}).get("worker", {}).get("drop_site_ids", [])
		var allowed: Dictionary = {}
		for value in drop_site_ids:
			if int(value) >= 0:
				allowed[int(value)] = true
		var dropoff: Variant = find_building(target_building_id) if target_building_id >= 0 else nearest_dropoff(worker)
		if dropoff == null or int(dropoff.get("team", 0)) != int(worker.get("team", 0)) or not dropoff_accepts_resource(dropoff, int(worker.get("carried_resource_type_id", -1)), allowed):
			continue
		release_resource_approach_slot(worker)
		release_building_approach_slot(worker)
		release_unit_destination(worker)
		worker["task"] = "gather"
		worker["gather_stage"] = "returning"
		worker["dropoff_id"] = int(dropoff["id"])
		worker["dropoff_position"] = dropoff_approach_position(worker, dropoff)
		OrderPipeline.begin(worker, "return_resources", int(dropoff["id"]), worker["dropoff_position"], false)
		assign_unit_destination(worker, worker["dropoff_position"], false)
		assigned += 1
	return assigned > 0


func find_building(id: int) -> Variant:
	for building in buildings:
		if int(building.get("id", -1)) == id:
			return building
	return null


func dropoff_approach_position(worker: Dictionary, building: Dictionary) -> Vector2:
	var candidates := building_perimeter_candidates(worker, building)
	for offset in range(candidates.size()):
		# Stable entity-derived starting slots prevent a crowd of carriers from
		# converging on the same point and deadlocking around a drop site.
		var candidate: Vector2 = candidates[posmod(int(worker.get("id", 0)) + offset, candidates.size())]
		if navigation_grid.is_position_walkable_for(candidate, float(worker.get("footprint_radius", 0.3)), String(worker.get("movement_domain", "land")), int(worker.get("terrain_restriction", -1))):
			return candidate
	return Vector2(building["pos"])


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
	release_resource_approach_slot(worker)
	release_unit_destination(worker)
	worker["task"] = "idle"
	worker["resource_id"] = -1
	worker["gather_stage"] = "none"
	worker["dropoff_id"] = -1
	worker["dropoff_position"] = null
	worker["pending_hunt_target_id"] = -1
	worker_role_system.clear(worker)
	OrderPipeline.complete(worker, reason)
	EntityComponents.sync_dynamic(worker)


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
	for kind in data_repository.archetype_aliases("building"):
		var base_source_id := int(data_repository.identifiers(kind).get("source_unit_id", -1))
		if base_source_id < 0:
			continue
		var resolved_source_id: int = int(technology_system.resolved_unit_id(team, base_source_id))
		var source: Dictionary = object_record_by_id(resolved_source_id, team)
		var interface: Dictionary = source.get("interface", {})
		if int(interface.get("button_id", -1)) <= 0:
			continue
		var reason := ""
		var required_technology_id := int(data_repository.runtime_metadata(kind).get("required_technology_id", -1))
		if required_technology_id >= 0 and not technology_system.is_researched(team, required_technology_id):
			reason = "building_unavailable"
		elif not is_object_available(team, base_source_id):
			reason = "building_unavailable"
		if reason == "building_unavailable":
			continue
		var cost := building_cost(kind, team)
		var option_footprint := Footprint.building(unit_stats(kind), Vector2.ZERO)
		var option_half_size := Vector2(option_footprint.get("half_size", Vector2.ONE))
		if reason.is_empty() and not can_afford_resource_cost(team, cost):
			reason = "insufficient_resources"
		result.append({
			"kind": kind,
			"source_unit_id": resolved_source_id,
			"icon_id": int(interface.get("icon_id", -1)),
			"button_id": int(interface.get("button_id", -1)),
			"cost": cost.duplicate(true),
			"duration": float(source.get("production", {}).get("creation_time", unit_stats(kind).get("creation_time", 0.0))),
			"footprint_radius": maxf(option_half_size.x, option_half_size.y),
			"accepted": reason.is_empty(),
			"reason": reason,
		})
	result.sort_custom(func(left, right):
		if int(left.get("button_id", 0)) != int(right.get("button_id", 0)):
			return int(left.get("button_id", 0)) < int(right.get("button_id", 0))
		return String(left.get("kind", "")) < String(right.get("kind", ""))
	)
	return result


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
	var workers: Array = units.filter(func(unit):
		return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0 and entity_is_worker(unit) and String(unit.get("movement_domain", "land")) == "land"
	)
	workers.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	if workers.is_empty():
		return result
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
			if can_place_foundation(team, kind, preferred_position) and workers.any(func(worker): return worker_can_reach_foundation(worker, kind, preferred_position)):
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
					for x in range(center.x - radius, center.x + radius + 1):
						if maxi(absi(x - center.x), absi(y - center.y)) != radius:
							continue
						var cell := Vector2i(x, y)
						if seen_cells.has(cell) or not navigation_grid.contains(cell):
							continue
						seen_cells[cell] = true
						var position := Vector2(cell) + Vector2(0.5, 0.5)
						if can_place_foundation(team, kind, position) and worker_can_reach_foundation(worker, kind, position):
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


func _append_bounded_sites(sites: Array, fallback_sites: Array, maximum: int) -> void:
	for fallback_position in fallback_sites:
		if sites.size() >= maximum:
			break
		sites.append(fallback_position)


func foundation_preserves_structure_gap(team: int, kind: String, position: Vector2, minimum_gap: float) -> bool:
	if minimum_gap <= 0.0:
		return true
	var footprint := Footprint.building(unit_stats(kind), position)
	var new_radius := maxf(0.5, maxf(float(footprint.get("half_size", Vector2.ONE).x), float(footprint.get("half_size", Vector2.ONE).y)))
	for building in buildings:
		if int(building.get("team", 0)) != team or float(building.get("hp", 0.0)) <= 0.0:
			continue
		var existing_radius := maxf(0.5, float(building.get("footprint_radius", 1.0)))
		var clearance := new_radius + existing_radius + minimum_gap
		if position.distance_squared_to(Vector2(building.get("pos", Vector2.ZERO))) < clearance * clearance:
			return false
	return true


func can_place_foundation(team: int, kind: String, position: Vector2) -> bool:
	last_build_failure = ""
	if data_repository.is_configured() and (not data_repository.has_archetype(kind) or data_repository.category(kind) != "building"):
		last_build_failure = "unknown_building_type"
		return false
	var required_technology_id := int(data_repository.runtime_metadata(kind).get("required_technology_id", -1))
	if required_technology_id >= 0 and not technology_system.is_researched(team, required_technology_id):
		last_build_failure = "building_unavailable"
		return false
	var footprint := Footprint.building(unit_stats(kind), position)
	var placement: Dictionary = data_repository.runtime_metadata(kind).get("placement", {})
	var placement_restriction := int(placement.get("terrain_restriction_id", -1))
	var placement_domain := String(placement.get("domain", "land"))
	if not navigation_grid.can_build_for(footprint.get("occupied_cells", []), placement_domain, placement_restriction):
		last_build_failure = "blocked_or_sloped"
		return false
	if not foundation_has_required_domain_access(footprint, placement):
		last_build_failure = "missing_domain_access"
		return false
	for building in buildings:
		if float(building.get("hp", 0.0)) <= 0.0:
			continue
		for cell in footprint.get("occupied_cells", []):
			if cell in building.get("occupied_cells", []):
				last_build_failure = "blocked_or_sloped"
				return false
	var occupied_cells: Array = footprint.get("occupied_cells", [])
	for unit in units:
		if float(unit.get("hp", 0.0)) <= 0.0 or bool(unit.get("removed", false)):
			continue
		if mobile_footprint_overlaps_cells(unit, occupied_cells):
			last_build_failure = "occupied_by_unit"
			return false
	if visibility_system.state_at_world(team, position) == FogOfWar.UNKNOWN:
		last_build_failure = "unexplored"
		return false
	var new_radius: float = Vector2(footprint.get("half_size", Vector2.ONE)).length()
	for building in buildings:
		if int(building.get("team", 0)) == team or float(building.get("hp", 0.0)) <= 0.0:
			continue
		var existing_radius: float = Vector2(building.get("footprint", {}).get("half_size", Vector2.ONE)).length()
		if Vector2(building["pos"]).distance_to(position) < new_radius + existing_radius + 1.0:
			last_build_failure = "enemy_territory"
			return false
	var cost := building_cost(kind, team)
	if not can_afford_resource_cost(team, cost):
		last_build_failure = "insufficient_resources"
		return false
	return true


func mobile_footprint_overlaps_cells(unit: Dictionary, occupied_cells: Array) -> bool:
	var position: Vector2 = unit.get("pos", Vector2.ZERO)
	var radius := maxf(0.0, float(unit.get("footprint_radius", 0.3)))
	for probe in [position, position + Vector2(radius, 0.0), position + Vector2(-radius, 0.0), position + Vector2(0.0, radius), position + Vector2(0.0, -radius)]:
		if Vector2i(floori(probe.x), floori(probe.y)) in occupied_cells:
			return true
	return false


func map_supports_foundation(kind: String, position: Vector2) -> bool:
	if data_repository.is_configured() and (not data_repository.has_archetype(kind) or data_repository.category(kind) != "building"):
		return false
	var footprint := Footprint.building(unit_stats(kind), position)
	var placement: Dictionary = data_repository.runtime_metadata(kind).get("placement", {})
	var placement_restriction := int(placement.get("terrain_restriction_id", -1))
	var placement_domain := String(placement.get("domain", "land"))
	return navigation_grid.can_build_for(footprint.get("occupied_cells", []), placement_domain, placement_restriction) and foundation_has_required_domain_access(footprint, placement)


func foundation_map_audit(kind: String, position: Vector2) -> Dictionary:
	if data_repository.is_configured() and (not data_repository.has_archetype(kind) or data_repository.category(kind) != "building"):
		return {"valid": false, "reason": "unknown_building_type"}
	var footprint := Footprint.building(unit_stats(kind), position)
	var placement: Dictionary = data_repository.runtime_metadata(kind).get("placement", {})
	var placement_restriction := int(placement.get("terrain_restriction_id", -1))
	var placement_domain := String(placement.get("domain", "land"))
	var cell_audit: Array = []
	for cell_value in footprint.get("occupied_cells", []):
		var cell: Vector2i = cell_value
		cell_audit.append({
			"cell": cell,
			"terrain_id": navigation_grid.terrain_id(cell),
			"terrain": navigation_grid.terrain(cell),
			"surface": navigation_grid.surface_accessible(cell, placement_domain, placement_restriction),
			"occupied": navigation_grid.occupied_cells.has(cell),
			"occupants": navigation_grid.occupants(cell),
			"slope": navigation_grid.is_slope(cell),
		})
	return {
		"valid": navigation_grid.can_build_for(footprint.get("occupied_cells", []), placement_domain, placement_restriction) and foundation_has_required_domain_access(footprint, placement),
		"cells": cell_audit,
		"domain_access": foundation_has_required_domain_access(footprint, placement),
	}


func foundation_has_required_domain_access(footprint: Dictionary, placement: Dictionary) -> bool:
	var required_domains: Array = placement.get("required_adjacent_domains", [])
	if required_domains.is_empty():
		return true
	var occupied: Array = footprint.get("occupied_cells", [])
	var occupied_lookup: Dictionary = {}
	for cell_value in occupied:
		occupied_lookup[cell_value] = true
	var found: Dictionary = {}
	for cell_value in occupied:
		var cell: Vector2i = cell_value
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if occupied_lookup.has(neighbor) or not navigation_grid.contains(neighbor):
				continue
			for domain_value in required_domains:
				var domain := String(domain_value)
				if navigation_grid.surface_accessible(neighbor, domain):
					found[domain] = true
	for domain_value in required_domains:
		if not found.has(String(domain_value)):
			return false
	return true


func worker_can_reach_foundation(worker: Dictionary, kind: String, position: Vector2) -> bool:
	var footprint := Footprint.building(unit_stats(kind), position)
	var occupied: Array = footprint.get("occupied_cells", [])
	var preview := {"pos": position, "footprint": footprint}
	var domain := String(worker.get("movement_domain", "land"))
	var restriction := int(worker.get("terrain_restriction", -1))
	for candidate in building_perimeter_candidates(worker, preview):
		if not navigation_grid.is_position_walkable_for(candidate, float(worker.get("footprint_radius", 0.3)), domain, restriction):
			continue
		var path: Array[Vector2] = pathfinder.find_path(Vector2(worker.get("pos", Vector2.ZERO)), candidate, domain, restriction)
		if path.is_empty():
			continue
		var crosses_future_footprint := path.any(func(point): return Vector2i(floori(point.x), floori(point.y)) in occupied)
		if not crosses_future_footprint:
			return true
	return false


func reachable_builder_ids(building: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if String(building.get("state", "complete")) != "foundation" or float(building.get("hp", 0.0)) <= 0.0:
		return result
	for worker_value in units:
		var worker: Dictionary = worker_value
		if int(worker.get("team", 0)) != int(building.get("team", 0)) or float(worker.get("hp", 0.0)) <= 0.0 or not entity_is_worker(worker) or String(worker.get("movement_domain", "land")) != "land":
			continue
		var domain := String(worker.get("movement_domain", "land"))
		var restriction := int(worker.get("terrain_restriction", -1))
		for candidate in building_perimeter_candidates(worker, building):
			if not navigation_grid.is_position_walkable_for(candidate, float(worker.get("footprint_radius", 0.3)), domain, restriction):
				continue
			if not pathfinder.find_path(Vector2(worker.get("pos", Vector2.ZERO)), candidate, domain, restriction).is_empty():
				result.append(int(worker.get("id", -1)))
				break
	result.sort()
	return result


func place_foundation(team: int, kind: String, position: Vector2, workers: Array = []) -> Variant:
	position = Coordinates.clamp_world(position, map_size)
	if not can_place_foundation(team, kind, position):
		return null
	var cost := building_cost(kind, team)
	spend_resource_cost(team, cost)
	var building := add_building(entity_id_sequence.next(), kind, position, team, false)
	building["reserved_cost"] = cost.duplicate(true)
	assign_workers_to_building(workers, building, "build")
	_emit_domain_event("foundation_placed", {
		"building_id": int(building.get("id", -1)),
		"kind": kind,
		"team": team,
		"position": position,
		"reserved_cost": cost.duplicate(true),
	})
	return building


func cancel_foundation(building_id: int) -> bool:
	var building: Variant = find_building(building_id)
	if building == null or String(building.get("state", "complete")) != "foundation":
		return false
	var cost: Dictionary = building.get("reserved_cost", {})
	refund_resource_cost(int(building.get("team", 0)), cost)
	for unit in units:
		if int(unit.get("target_building_id", -1)) == building_id:
			finish_building_order(unit, "foundation_cancelled")
	var was_reseed := bool(building.get("reseed_from_depleted", false))
	if was_reseed:
		building["state"] = "complete"
		building["construction_progress"] = 1.0
		building["construction_stage"] = 3
		building["hp"] = building["max_hp"]
		building["amount"] = 0
		building["max_amount"] = maxi(0, int(building.get("reseed_previous_max_amount", building.get("max_amount", 0))))
		building["resource_state"] = "depleted"
		building["resource_depletion_stage"] = 2
		building["reserved_cost"] = {}
		building["builders"] = {}
		building.erase("reseed_from_depleted")
		building.erase("reseed_previous_max_amount")
		EntityComponents.sync_dynamic(building)
	else:
		deactivate_building_victory_objective(building)
		for index in range(buildings.size() - 1, -1, -1):
			if int(buildings[index].get("id", -1)) == building_id:
				buildings.remove_at(index)
				break
	building_approach_slots.erase(building_id)
	refresh_building_connectivity()
	rebuild_navigation_grid()
	update_fog_of_war()
	_emit_domain_event("foundation_cancelled", {
		"building_id": building_id,
		"kind": String(building.get("kind", "")),
		"team": int(building.get("team", 0)),
		"refunded_cost": cost.duplicate(true),
		"reseed": was_reseed,
	})
	return true


func assign_command_build(selected: Array, kind: String, position: Vector2) -> Variant:
	var foundation: Variant = null
	var team := int(selected[0].get("team", 0)) if not selected.is_empty() else 0
	for building in buildings:
		if int(building.get("team", 0)) != team or String(building.get("kind", "")) != kind or Vector2(building["pos"]).distance_squared_to(position) >= 0.01:
			continue
		if String(building.get("state", "complete")) == "foundation":
			foundation = building
			break
		if bool(building.get("harvestable", false)) and String(building.get("resource_state", "")) == "depleted":
			return reseed_harvestable_building(building, selected)
	if foundation == null:
		foundation = place_foundation(team, kind, position)
	if foundation != null:
		assign_workers_to_building(selected, foundation, "build")
	return foundation


func reseed_harvestable_building(building: Dictionary, workers: Array = []) -> Variant:
	last_build_failure = ""
	if building == null or not bool(building.get("harvestable", false)) or String(building.get("state", "complete")) != "complete" or String(building.get("resource_state", "")) != "depleted" or float(building.get("hp", 0.0)) <= 0.0:
		last_build_failure = "reseed_unavailable"
		return null
	var team := int(building.get("team", 0))
	var required_technology_id := int(data_repository.runtime_metadata(String(building.get("kind", ""))).get("required_technology_id", -1))
	if required_technology_id >= 0 and not technology_system.is_researched(team, required_technology_id):
		last_build_failure = "building_unavailable"
		return null
	var cost := building_cost(String(building.get("kind", "")), team)
	if not can_afford_resource_cost(team, cost):
		last_build_failure = "insufficient_resources"
		return null
	spend_resource_cost(team, cost)
	resource_approach_slots.erase(int(building.get("id", -1)))
	building["reseed_from_depleted"] = true
	building["reseed_previous_max_amount"] = int(building.get("max_amount", 0))
	building["state"] = "foundation"
	building["construction_progress"] = 0.0
	building["construction_stage"] = 0
	building["hp"] = maxf(1.0, float(building.get("max_hp", 1.0)) * 0.1)
	building["amount"] = 0
	building["resource_state"] = "planting"
	building["resource_depletion_stage"] = 0
	building["reserved_cost"] = cost.duplicate(true)
	building["builders"] = {}
	EntityComponents.sync_dynamic(building)
	assign_workers_to_building(workers, building, "build")
	rebuild_navigation_grid()
	_emit_domain_event("foundation_placed", {
		"building_id": int(building.get("id", -1)),
		"kind": String(building.get("kind", "")),
		"team": team,
		"position": building.get("pos", Vector2.ZERO),
		"reserved_cost": cost.duplicate(true),
		"reseed": true,
	})
	return building


func assign_command_repair(selected: Array, building_id: int) -> bool:
	var building: Variant = find_building(building_id)
	if building == null or float(building.get("hp", 0.0)) <= 0.0:
		return false
	assign_workers_to_building(selected, building, "repair")
	return true


func assign_workers_to_building(selected: Array, building: Dictionary, order_type: String) -> void:
	for worker in selected:
		if not entity_is_worker(worker) or int(worker.get("team", 0)) != int(building.get("team", 0)):
			continue
		worker_role_system.apply(worker, worker_role_system.profile_for_task(worker, order_type), false)
		worker["pending_hunt_target_id"] = -1
		release_resource_approach_slot(worker)
		release_building_approach_slot(worker)
		release_unit_destination(worker)
		worker["resource_id"] = -1
		worker["gather_stage"] = "none"
		worker["task"] = order_type
		worker["target_building_id"] = int(building["id"])
		OrderPipeline.begin(worker, order_type, int(building["id"]), building["pos"], true)
		var slot: Variant = reserve_building_approach_slot(worker, building)
		if slot is Vector2:
			assign_unit_destination(worker, slot, false)
		else:
			finish_building_order(worker, "no_approach_slot")


func update_building_order(worker: Dictionary, delta: float) -> Dictionary:
	var building: Variant = find_building(int(worker.get("target_building_id", -1)))
	if building == null or float(building.get("hp", 0.0)) <= 0.0:
		finish_building_order(worker, "building_unavailable")
		return {"moving": false, "animation_state": AnimationController.IDLE}
	if worker["task"] == "build" and String(building.get("state", "complete")) != "foundation":
		finish_building_order(worker, "construction_complete")
		return {"moving": false, "animation_state": AnimationController.IDLE}
	if worker["task"] == "repair" and float(building["hp"]) >= float(building["max_hp"]) - 0.0001:
		finish_building_order(worker, "repair_complete")
		return {"moving": false, "animation_state": AnimationController.IDLE}
	if not worker.get("building_approach_slot") is Vector2:
		var slot: Variant = reserve_building_approach_slot(worker, building)
		if not slot is Vector2:
			finish_building_order(worker, "no_approach_slot")
			return {"moving": false, "animation_state": AnimationController.IDLE}
		assign_unit_destination(worker, slot, false)
	var destination: Vector2 = worker["building_approach_slot"]
	if worker["pos"].distance_squared_to(destination) > 0.0144:
		ensure_navigation_destination(worker, destination)
		return {"moving": move_unit(worker, delta), "animation_state": AnimationController.MOVE}

	var was_building := String(worker.get("task", "")) == "build"
	OrderPipeline.transition(worker, OrderPipeline.FACE_TARGET)
	face_unit_toward(worker, building["pos"])
	OrderPipeline.transition(worker, OrderPipeline.PERFORM_ACTION)
	var worker_rate := maxf(0.01, float(worker.get("components", {}).get("worker", {}).get("work_rate", 1.0)))
	if worker["task"] == "build":
		building["builders"][int(worker["id"])] = true
		var progress_delta := delta * worker_rate / maxf(0.05, float(building.get("construction_required", 1.0)))
		building["construction_progress"] = minf(1.0, float(building.get("construction_progress", 0.0)) + progress_delta)
		building["construction_stage"] = clampi(floori(float(building["construction_progress"]) * 4.0), 0, 3)
		building["hp"] = maxf(float(building["hp"]), float(building["max_hp"]) * maxf(0.1, float(building["construction_progress"])))
		EntityComponents.sync_dynamic(building)
		if float(building["construction_progress"]) >= 1.0 - 0.000001:
			complete_foundation(building)
	else:
		var repair_amount := minf(float(building["max_hp"]) - float(building["hp"]), delta * worker_rate * 10.0)
		var repair_cost := repair_amount * 0.1
		var repair_team := int(worker.get("team", building.get("team", 0)))
		var available_fraction := float(economy_system.get_resource_amount(repair_team, 1)) + float(building.get("repair_cost_fraction", 0.0))
		if repair_amount > 0.0 and available_fraction > 0.0:
			building["hp"] += repair_amount
			building["repair_cost_fraction"] = float(building.get("repair_cost_fraction", 0.0)) + repair_cost
			var whole_cost := floori(float(building["repair_cost_fraction"]))
			if whole_cost > 0:
				economy_system.change_resource_amount(repair_team, 1, -whole_cost)
				building["repair_cost_fraction"] = float(building["repair_cost_fraction"]) - whole_cost
			EntityComponents.sync_dynamic(building)
		if float(building["hp"]) >= float(building["max_hp"]) - 0.0001:
			building["hp"] = building["max_hp"]
			finish_building_order(worker, "repair_complete")
	OrderPipeline.transition(worker, OrderPipeline.RECOVER)
	return {"moving": false, "animation_state": AnimationController.BUILD if was_building else AnimationController.REPAIR}


func complete_foundation(building: Dictionary) -> void:
	var completing_builder_ids: Array = building.get("builders", {}).keys()
	completing_builder_ids.sort()
	building["state"] = "complete"
	building["construction_progress"] = 1.0
	building["construction_stage"] = 3
	building["hp"] = building["max_hp"]
	building["reserved_cost"] = {}
	building["builders"] = {}
	building.erase("reseed_from_depleted")
	building.erase("reseed_previous_max_amount")
	activate_harvestable_building(building)
	EntityComponents.sync_dynamic(building)
	activate_building_completion(building)
	sync_building_victory_objective(building)
	refresh_building_connectivity()
	var building_id := int(building["id"])
	for unit in units:
		if int(unit.get("target_building_id", -1)) == building_id and String(unit.get("task", "")) == "build":
			finish_building_order(unit, "construction_complete")
	var runtime_metadata: Dictionary = data_repository.runtime_metadata(String(building.get("kind", "")))
	if bool(runtime_metadata.get("auto_gather_on_complete", false)) and int(building.get("amount", 0)) > 0:
		for builder_id in completing_builder_ids:
			var builder: Variant = find_unit(int(builder_id))
			if builder != null and float(builder.get("hp", 0.0)) > 0.0 and entity_is_worker(builder):
				assign_command_gather([builder], building_id)
				break
	building_approach_slots.erase(building_id)
	rebuild_navigation_grid()
	update_fog_of_war()
	_emit_domain_event("build_complete", {
		"building_id": building_id,
		"kind": String(building.get("kind", "")),
		"team": int(building.get("team", 0)),
	})


func activate_building_completion(building: Dictionary) -> void:
	var kind := String(building.get("kind", ""))
	if not data_repository.has_archetype(kind):
		return
	var team := int(building.get("team", 0))
	activate_population_support(building)
	var civilization_id := int(civilization_by_team.get(team, 13))
	var technology_id: int = data_repository.completion_technology_id(kind, civilization_id)
	if technology_id < 0 or technology_system.technology(technology_id).is_empty() or technology_system.is_researched(team, technology_id):
		return
	apply_technology_commands(team, technology_system.complete_research(team, technology_id))
	_emit_domain_event("building_technology_unlocked", {
		"building_id": int(building.get("id", -1)),
		"building_kind": kind,
		"team": team,
		"technology_id": technology_id,
	})


func configure_harvestable_building(building: Dictionary, completed: bool) -> void:
	if not bool(building.get("harvestable", false)):
		return
	var runtime_metadata: Dictionary = data_repository.runtime_metadata(String(building.get("kind", "")))
	var maximum := harvestable_amount_for(String(building.get("kind", "")), int(building.get("team", 0)))
	building["resource_type_id"] = int(runtime_metadata.get("resource_type_id", -1))
	building["resource_amount_id"] = int(runtime_metadata.get("resource_amount_id", -1))
	building["max_amount"] = maximum
	building["amount"] = maximum if completed else 0
	building["resource_state"] = "available" if completed and maximum > 0 else "depleted" if completed else "planting"
	building["resource_depletion_stage"] = 0 if maximum > 0 else 2
	var carrier: Dictionary = building.get("components", {}).get("resource_carrier", {})
	carrier["capacity"] = float(maximum)
	carrier["amount"] = float(building["amount"])
	carrier["resource_type_id"] = int(building["resource_type_id"])


func activate_harvestable_building(building: Dictionary) -> void:
	if not bool(building.get("harvestable", false)):
		return
	configure_harvestable_building(building, true)
	_emit_domain_event("harvestable_activated", {
		"building_id": int(building.get("id", -1)),
		"resource_type_id": int(building.get("resource_type_id", -1)),
		"amount": int(building.get("amount", 0)),
	})


func harvestable_amount_for(kind: String, team: int) -> int:
	var amount_resource_id := int(data_repository.runtime_metadata(kind).get("resource_amount_id", -1))
	if amount_resource_id < 0:
		return 0
	return maxi(0, roundi(technology_system.rule_resource_value(team, amount_resource_id)))


func population_support_for(kind: String, team: int) -> int:
	var source := object_record_for(kind, team)
	for storage_value in source.get("resources", {}).get("storage", []):
		var storage: Dictionary = storage_value
		if int(storage.get("type", -1)) == 4 and float(storage.get("amount", 0.0)) > 0.0:
			return maxi(0, roundi(float(storage.get("amount", 0.0))))
	return 0


func activate_population_support(building: Dictionary) -> void:
	if bool(building.get("population_support_applied", false)):
		return
	var support := maxi(0, int(building.get("population_support", 0)))
	if support <= 0:
		return
	var team := int(building.get("team", 0))
	economy_system.add_population_housing(team, support)
	building["population_support_applied"] = true
	_emit_domain_event("population_cap_changed", {
		"building_id": int(building.get("id", -1)),
		"team": team,
		"delta": support,
		"housing": economy_system.get_population_housing(team),
		"cap": economy_system.get_population_cap(team),
	})


func deactivate_population_support(building: Dictionary) -> void:
	if not bool(building.get("population_support_applied", false)):
		return
	var support := maxi(0, int(building.get("population_support", 0)))
	var team := int(building.get("team", 0))
	economy_system.add_population_housing(team, -support)
	building["population_support_applied"] = false
	_emit_domain_event("population_cap_changed", {
		"building_id": int(building.get("id", -1)),
		"team": team,
		"delta": -support,
		"housing": economy_system.get_population_housing(team),
		"cap": economy_system.get_population_cap(team),
	})


func reserve_building_approach_slot(worker: Dictionary, building: Dictionary) -> Variant:
	if worker.get("building_approach_slot") is Vector2:
		return worker["building_approach_slot"]
	var building_id := int(building["id"])
	var reservations: Dictionary = building_approach_slots.get(building_id, {})
	var candidates := building_perimeter_candidates(worker, building)
	for offset in range(candidates.size()):
		var slot_index := posmod(int(worker["id"]) + offset, candidates.size())
		var candidate: Vector2 = candidates[slot_index]
		if not navigation_grid.is_position_walkable_for(candidate, float(worker.get("footprint_radius", 0.3)), String(worker.get("movement_domain", "land")), int(worker.get("terrain_restriction", -1))):
			continue
		var route: Array[Vector2] = pathfinder.find_path(Vector2(worker.get("pos", Vector2.ZERO)), candidate, String(worker.get("movement_domain", "land")), int(worker.get("terrain_restriction", -1)))
		if route.is_empty():
			continue
		if reservations.values().any(func(existing): return Vector2(existing).distance_squared_to(candidate) < 0.09):
			continue
		reservations[int(worker["id"])] = candidate
		building_approach_slots[building_id] = reservations
		worker["building_approach_slot"] = candidate
		return candidate
	return null


func release_building_approach_slot(worker: Dictionary) -> void:
	var building_id := int(worker.get("target_building_id", -1))
	if building_approach_slots.has(building_id):
		var reservations: Dictionary = building_approach_slots[building_id]
		reservations.erase(int(worker.get("id", -1)))
		if reservations.is_empty():
			building_approach_slots.erase(building_id)
		else:
			building_approach_slots[building_id] = reservations
	worker["building_approach_slot"] = null


func finish_building_order(worker: Dictionary, reason: String) -> void:
	release_building_approach_slot(worker)
	release_unit_destination(worker)
	worker["target_building_id"] = -1
	worker["task"] = "idle"
	worker_role_system.clear(worker)
	OrderPipeline.complete(worker, reason)
	EntityComponents.sync_dynamic(worker)


func update_resource_state(resource: Dictionary) -> void:
	var amount := int(resource.get("amount", 0))
	var maximum := maxi(1, int(resource.get("max_amount", amount)))
	var harvestable_building := bool(resource.get("harvestable", false))
	var state_key := "resource_state" if harvestable_building else "state"
	var stage_key := "resource_depletion_stage" if harvestable_building else "depletion_stage"
	var previous_state := String(resource.get(state_key, ""))
	if amount <= 0:
		resource[state_key] = "depleted"
		resource[stage_key] = 2
	elif float(amount) / float(maximum) <= 0.5:
		resource[state_key] = "low"
		resource[stage_key] = 1
	else:
		resource[state_key] = "available"
		resource[stage_key] = 0
	EntityComponents.sync_dynamic(resource)
	if previous_state != "depleted" and String(resource.get(state_key, "")) == "depleted":
		if not harvestable_building:
			_unregister_forest_resource(resource)
			navigation_grid.release_occupant(resource.get("footprint", {}).get("occupied_cells", []), "resource", int(resource.get("id", -1)))
		_emit_domain_event("resource_depleted", {
			"resource_id": int(resource.get("id", -1)),
			"kind": String(resource.get("kind", "")),
			"building": harvestable_building,
		})


func advance_resource_lifecycle(delta: float) -> void:
	var navigation_changed := false
	for resource in decaying_resource_nodes:
		if int(resource.get("amount", 0)) <= 0:
			continue
		var decay_rate := maxf(0.0, float(resource.get("decay_rate", 0.0)))
		if decay_rate <= 0.0:
			continue
		var accumulator := float(resource.get("decay_accumulator", 0.0)) + decay_rate * maxf(0.0, delta)
		var lost := mini(int(resource.get("amount", 0)), floori(accumulator))
		resource["decay_accumulator"] = accumulator - float(lost)
		if lost <= 0:
			continue
		resource["amount"] = maxi(0, int(resource["amount"]) - lost)
		update_resource_state(resource)
		_emit_domain_event("resource_decayed", {
			"resource_id": int(resource.get("id", -1)),
			"amount": lost,
			"remaining": int(resource.get("amount", 0)),
		})
		if int(resource.get("amount", 0)) <= 0:
			navigation_changed = true
	if navigation_changed:
		rebuild_navigation_grid()


func _update_huntable_reaction(unit: Dictionary) -> void:
	if not entity_has_behavior_tag(unit, "huntable") or int(unit.get("retaliation_target_id", -1)) < 0:
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
	var resolved_count := 0
	for unit in selected:
		conversion_system.cancel(unit, "new_order")
		healing_system.cancel(unit, "new_order")
		if entity_is_worker(unit):
			worker_role_system.clear(unit)
			unit["pending_hunt_target_id"] = -1
		release_resource_approach_slot(unit)
		release_building_approach_slot(unit)
		unit["gather_stage"] = "none"
		unit["resource_id"] = -1
		unit["target_building_id"] = -1
		unit["task"] = "move"
		unit["target_id"] = -1
		_clear_combat_intent(unit)
		OrderPipeline.begin(unit, "move", -1, target, false)
		if not assign_unit_destination(unit, target):
			OrderPipeline.complete(unit, "no_path")
		else:
			resolved_count += 1
	return resolved_count > 0

func assign_command_attack_move(selected: Array, target: Vector2) -> bool:
	var resolved_count := 0
	for unit in selected:
		conversion_system.cancel(unit, "new_order")
		healing_system.cancel(unit, "new_order")
		if entity_is_worker(unit):
			worker_role_system.clear(unit)
			unit["pending_hunt_target_id"] = -1
		release_resource_approach_slot(unit)
		release_building_approach_slot(unit)
		unit["gather_stage"] = "none"
		unit["resource_id"] = -1
		unit["target_building_id"] = -1
		unit["task"] = "attack_move"
		unit["target_id"] = -1
		_clear_combat_intent(unit)
		unit["attack_move_destination"] = target
		OrderPipeline.begin(unit, "attack_move", -1, target, false)
		if not assign_unit_destination(unit, target):
			unit["task"] = "idle"
			OrderPipeline.complete(unit, "no_path")
		else:
			resolved_count += 1
	return resolved_count > 0

func assign_unit_destination(unit: Dictionary, destination: Vector2, reserve_destination: bool = true) -> bool:
	if not OrderPipeline.is_active(unit):
		OrderPipeline.begin(unit, String(unit.get("task", "move")), int(unit.get("target_id", -1)), destination, String(unit.get("task", "")) in ["attack", "gather"])
	OrderPipeline.transition(unit, OrderPipeline.PLAN_PATH)
	var clamped_destination := Coordinates.clamp_world(destination, map_size)
	if reserve_destination:
		clamped_destination = destination_reservations.reserve(int(unit["id"]), clamped_destination, float(unit.get("footprint_radius", 0.3)), navigation_grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
		unit["reserved_destination"] = clamped_destination
	unit["destination"] = clamped_destination
	var path_result := navigation_service.request_path(int(unit["id"]), unit["pos"], unit["destination"], String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), "replan" if not unit.get("path", []).is_empty() else String(unit.get("task", "move")))
	unit["path_request_id"] = int(path_result["request_id"])
	unit["path_status"] = String(path_result["status"])
	unit["path_grid_revision"] = int(path_result["grid_revision"])
	unit["path"] = path_result["path"]
	unit["path_index"] = 0
	if unit["path"].is_empty():
		unit["target"] = unit["pos"]
		unit["diagnostic_reason"] = "no_path"
		if unit["task"] in ["move", "attack_move"]:
			unit["task"] = "idle"
		return false
	unit["target"] = unit["path"][0]
	unit["diagnostic_reason"] = ""
	OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
	return true

func assign_unit_waypoints(unit: Dictionary, waypoints: Array[Vector2], destination: Vector2) -> bool:
	if not OrderPipeline.is_active(unit, "move"):
		OrderPipeline.begin(unit, "move", -1, destination, false)
	OrderPipeline.transition(unit, OrderPipeline.PLAN_PATH)
	var reserved_destination := destination_reservations.reserve(int(unit["id"]), Coordinates.clamp_world(destination, map_size), float(unit.get("footprint_radius", 0.3)), navigation_grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
	unit["reserved_destination"] = reserved_destination
	unit["destination"] = reserved_destination
	var targets := waypoints.duplicate()
	if targets.is_empty() or targets[targets.size() - 1].distance_squared_to(reserved_destination) > 0.0001:
		targets.append(reserved_destination)
	else:
		targets[targets.size() - 1] = reserved_destination
	var combined: Array[Vector2] = []
	var cursor: Vector2 = unit["pos"]
	for target in targets:
		var path_result := navigation_service.request_path(int(unit["id"]), cursor, Coordinates.clamp_world(target, map_size), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), "formation_segment")
		unit["path_request_id"] = int(path_result["request_id"])
		unit["path_status"] = String(path_result["status"])
		unit["path_grid_revision"] = int(path_result["grid_revision"])
		var segment: Array[Vector2] = path_result["path"]
		if segment.is_empty() and cursor.distance_squared_to(target) > 0.0001:
			continue
		for waypoint in segment:
			if combined.is_empty() or combined[combined.size() - 1].distance_squared_to(waypoint) > 0.0001:
				combined.append(waypoint)
		cursor = target
	unit["path"] = combined
	unit["path_index"] = 0
	if combined.is_empty():
		unit["target"] = unit["pos"]
		unit["diagnostic_reason"] = "no_group_route"
		unit["task"] = "idle"
		return false
	unit["target"] = combined[0]
	unit["diagnostic_reason"] = "group_corridor" if waypoints.size() > 1 else ""
	OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
	return true

func ensure_navigation_destination(unit: Dictionary, destination: Vector2) -> void:
	var previous_destination: Vector2 = unit.get("destination", unit["pos"])
	if previous_destination.distance_squared_to(destination) > 0.25 or unit.get("path", []).is_empty():
		assign_unit_destination(unit, destination, false)

func assign_command_attack(selected: Array, target_id: int, policy: Dictionary = {}) -> bool:
	var target: Variant = find_combat_target(target_id)
	if target == null or target["hp"] <= 0.0:
		return false
	var huntable := entity_has_behavior_tag(target, "huntable")
	for candidate in selected:
		if not entity_is_worker(candidate):
			continue
		if huntable:
			worker_role_system.apply(candidate, worker_role_system.profile_for_hunt(candidate, target), true)
			candidate["pending_hunt_target_id"] = target_id
			configure_unit_combat_awareness(candidate)
		else:
			worker_role_system.clear(candidate)
			candidate["pending_hunt_target_id"] = -1
	var mobile_attackers: Array = selected.filter(func(entity): return not entity_is_static(entity))
	if not mobile_attackers.is_empty():
		FormationCombat.assign_slots(mobile_attackers, target)
	var resolved_count := 0
	for unit in selected:
		var static_attacker := entity_is_static(unit)
		if not static_attacker:
			conversion_system.cancel(unit, "new_order")
			healing_system.cancel(unit, "new_order")
		var autonomous := bool(policy.get("autonomous", false))
		var previous_task := String(unit.get("task", "idle"))
		if autonomous and previous_task != "attack" and previous_task in ["move", "attack_move"]:
			unit["combat_resume"] = {
				"task": previous_task,
				"destination": unit.get("destination", unit.get("pos", Vector2.ZERO)),
			}
		elif not autonomous:
			unit["combat_resume"] = {}
		release_resource_approach_slot(unit)
		release_building_approach_slot(unit)
		unit["gather_stage"] = "none"
		unit["resource_id"] = -1
		unit["target_building_id"] = -1
		destination_reservations.release(int(unit["id"]))
		unit["reserved_destination"] = null
		unit["task"] = "attack"
		unit["target_id"] = target_id
		unit["attack_autonomous"] = autonomous
		if int(unit.get("formation_group_id", -1)) >= 0:
			unit["formation_slot_mode"] = "released"
		unit["combat_leash_origin"] = Vector2(policy.get("leash_origin", unit.get("pos", Vector2.ZERO)))
		unit["chase_range"] = maxf(0.0, float(policy.get("chase_range", unit.get("chase_range", 0.0))))
		unit["retaliation_target_id"] = -1
		unit["diagnostic_reason"] = "target:%s" % String(policy.get("trigger", "explicit"))
		if static_attacker:
			unit["combat_destination"] = unit.get("pos", Vector2.ZERO)
		var target_direction: Vector2 = target["pos"] - unit["pos"]
		if target_direction.length_squared() > 0.0001:
			unit["action_facing"] = facing_for_vector(target_direction)
		OrderPipeline.begin(unit, "attack", target_id, target["pos"], true)
		if CombatRules.is_in_range(unit, target):
			# Even an adjacent target passes through the same semantic phases; only
			# the expensive path request is elided.
			OrderPipeline.transition(unit, OrderPipeline.PLAN_PATH)
			OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
			OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
			resolved_count += 1
		elif not static_attacker and assign_unit_destination(unit, unit["combat_destination"]):
			resolved_count += 1
		else:
			_finish_combat(unit, "target_unreachable")
	if resolved_count > 0:
		_emit_domain_event("target_acquired", {
			"target_id": target_id,
			"unit_ids": selected.map(func(unit): return int(unit.get("id", -1))),
			"autonomous": bool(policy.get("autonomous", false)),
			"trigger": String(policy.get("trigger", "explicit")),
		})
	return resolved_count > 0


func assign_command_convert(selected: Array, target_id: int) -> String:
	var target: Variant = find_combat_target(target_id)
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_target"
	var resolved_count := 0
	var last_rejection := "no_eligible_converters"
	for unit in selected:
		if not conversion_system.is_converter(unit):
			continue
		var rejection := conversion_system.validate_target(unit, target)
		if not rejection.is_empty():
			last_rejection = rejection
			continue
		conversion_system.cancel(unit, "new_conversion")
		healing_system.cancel(unit, "new_conversion")
		release_resource_approach_slot(unit)
		release_building_approach_slot(unit)
		unit["resource_id"] = -1
		unit["gather_stage"] = "none"
		unit["target_building_id"] = int(target_id) if find_building(target_id) != null else -1
		unit["target_id"] = target_id
		unit["task"] = "convert"
		unit["retaliation_target_id"] = -1
		_clear_combat_intent(unit)
		var target_direction: Vector2 = Vector2(target["pos"]) - Vector2(unit["pos"])
		if target_direction.length_squared() > 0.0001:
			unit["action_facing"] = facing_for_vector(target_direction)
		OrderPipeline.begin(unit, "convert", target_id, target["pos"], true)
		rejection = conversion_system.begin(unit, target)
		if not rejection.is_empty():
			last_rejection = rejection
			halt_unit(unit, rejection)
			continue
		if conversion_system.is_in_range(unit, target):
			OrderPipeline.transition(unit, OrderPipeline.PLAN_PATH)
			OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
			OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
			resolved_count += 1
		else:
			var destination: Variant = _conversion_destination(unit, target)
			if destination != null and assign_unit_destination(unit, destination, false):
				resolved_count += 1
			else:
				last_rejection = "target_unreachable"
				_finish_conversion(unit, last_rejection)
	return "" if resolved_count > 0 else last_rejection


func _conversion_destination(converter: Dictionary, target: Dictionary) -> Variant:
	if find_building(int(target.get("id", -1))) != null:
		converter["target_building_id"] = int(target.get("id", -1))
		return reserve_building_approach_slot(converter, target)
	return Vector2(target.get("pos", converter.get("pos", Vector2.ZERO)))


func _finish_conversion(converter: Dictionary, reason: String) -> void:
	conversion_system.cancel(converter, reason)
	release_building_approach_slot(converter)
	release_unit_destination(converter)
	converter["target_id"] = -1
	converter["target_building_id"] = -1
	converter["task"] = "idle"
	converter["diagnostic_reason"] = "conversion_complete:%s" % reason
	OrderPipeline.complete(converter, reason)
	restore_formation_facing(converter)


func assign_command_heal(selected: Array, target_id: int) -> String:
	var target: Variant = find_unit(target_id)
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_healing_target"
	var resolved_count := 0
	var last_rejection := "no_eligible_healers"
	for unit in selected:
		if not healing_system.is_healer(unit):
			continue
		var rejection := healing_system.validate_target(unit, target)
		if not rejection.is_empty():
			last_rejection = rejection
			continue
		conversion_system.cancel(unit, "new_healing")
		healing_system.cancel(unit, "new_healing")
		release_resource_approach_slot(unit)
		release_building_approach_slot(unit)
		unit["resource_id"] = -1
		unit["gather_stage"] = "none"
		unit["target_building_id"] = -1
		unit["target_id"] = target_id
		unit["task"] = "heal"
		unit["retaliation_target_id"] = -1
		_clear_combat_intent(unit)
		var target_direction: Vector2 = Vector2(target["pos"]) - Vector2(unit["pos"])
		if target_direction.length_squared() > 0.0001:
			unit["action_facing"] = facing_for_vector(target_direction)
		OrderPipeline.begin(unit, "heal", target_id, target["pos"], true)
		rejection = healing_system.begin(unit, target)
		if not rejection.is_empty():
			last_rejection = rejection
			halt_unit(unit, rejection)
			continue
		if healing_system.is_in_range(unit, target):
			OrderPipeline.transition(unit, OrderPipeline.PLAN_PATH)
			OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
			OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
			resolved_count += 1
		elif assign_unit_destination(unit, target["pos"], false):
			resolved_count += 1
		else:
			last_rejection = "target_unreachable"
			_finish_healing(unit, last_rejection)
	return "" if resolved_count > 0 else last_rejection


func _finish_healing(healer: Dictionary, reason: String, completed: bool = false) -> void:
	if completed:
		healing_system.complete(healer, reason)
	else:
		healing_system.cancel(healer, reason)
	release_unit_destination(healer)
	healer["target_id"] = -1
	healer["task"] = "idle"
	healer["diagnostic_reason"] = "healing_complete:%s" % reason
	OrderPipeline.complete(healer, reason)
	restore_formation_facing(healer)


func apply_martyrdom(selected: Array) -> String:
	var completed := 0
	var last_rejection := "no_eligible_martyr"
	for unit in selected:
		if not conversion_system.is_converter(unit):
			continue
		var rejection := conversion_system.perform_martyrdom(unit)
		if rejection.is_empty():
			completed += 1
		else:
			last_rejection = rejection
	return "" if completed > 0 else last_rejection


func board_units(passengers: Array, transport: Dictionary) -> String:
	return transport_system.board(passengers, transport)


func unload_transports(transports: Array, target: Vector2, passenger_ids: Array = []) -> String:
	return transport_system.unload(transports, target, passenger_ids)


func set_trade_resource(traders: Array, resource_type_id: int) -> String:
	return trade_system.set_resource(traders, resource_type_id)


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
		while not entity.get("production_queue", []).is_empty():
			production_system.cancel(entity_id, 0)
		deactivate_population_support(entity)
	else:
		halt_unit(entity, "converted" if ownership_reason == "conversion" else ownership_reason)
		if old_team > 0 and not bool(entity.get("population_released", false)):
			var population_cost := int(entity.get("population_cost", 0))
			economy_system.add_population(old_team, -population_cost)
		if not bool(entity.get("population_released", false)):
			economy_system.add_population(new_team, int(entity.get("population_cost", 0)))
	player_registry.ensure(new_team, int(civilization_by_team.get(new_team, 13)))
	entity["team"] = new_team
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
	for unit in selected:
		if not entity_is_worker(unit):
			continue
		conversion_system.cancel(unit, "new_order")
		healing_system.cancel(unit, "new_order")
		release_resource_approach_slot(unit)
		release_building_approach_slot(unit)
		unit["target_building_id"] = -1
		destination_reservations.release(int(unit["id"]))
		unit["reserved_destination"] = null
		unit["task"] = "gather"
		unit["resource_id"] = target_id
		var resource: Variant = find_resource(target_id)
		if resource != null and int(resource.get("amount", 0)) > 0 and resource_accessible_to_team(resource, int(unit.get("team", 0))) and resource_allows_worker(resource, unit):
			worker_role_system.apply(unit, worker_role_system.profile_for_resource(unit, resource), false)
			unit["pending_hunt_target_id"] = -1
			OrderPipeline.begin(unit, "gather", target_id, resource["pos"], true)
			var carried_type := int(unit.get("carried_resource_type_id", -1))
			var target_type := int(resource.get("resource_type_id", -1))
			if float(unit.get("carried_amount", 0.0)) > 0.0 and carried_type != target_type:
				if not begin_resource_return(unit):
					finish_gather_order(unit, "no_dropoff")
			elif not prepare_resource_approach(unit, resource):
				finish_gather_order(unit, "no_approach_slot")
		else:
			finish_gather_order(unit, "incompatible_gatherer" if resource != null and not resource_allows_worker(resource, unit) else "resource_unavailable")

func release_unit_destination(unit: Dictionary) -> void:
	destination_reservations.release(int(unit.get("id", -1)))
	unit["reserved_destination"] = null

func _finish_combat(unit: Dictionary, reason: String = "target_unavailable") -> void:
	var completed_target_id := int(unit.get("target_id", -1))
	var completed_target: Variant = find_combat_target(completed_target_id)
	var waiting_for_carcass := entity_is_worker(unit) and int(unit.get("pending_hunt_target_id", -1)) == completed_target_id and completed_target != null and float(completed_target.get("hp", 0.0)) <= 0.0
	var resume: Dictionary = unit.get("combat_resume", {}).duplicate(true)
	OrderPipeline.complete(unit, reason)
	unit["diagnostic_reason"] = "combat_complete:%s" % reason
	unit["target_id"] = -1
	unit["combat_role"] = ""
	unit["combat_slot_index"] = -1
	unit["combat_slot_count"] = 0
	unit["combat_destination"] = null
	unit["attack_autonomous"] = false
	unit["combat_resume"] = {}
	if entity_is_static(unit):
		unit["task"] = "idle"
		EntityComponents.sync_dynamic(unit)
		return
	if waiting_for_carcass:
		unit["task"] = "idle"
		release_unit_destination(unit)
		return
	if entity_is_worker(unit):
		unit["pending_hunt_target_id"] = -1
		worker_role_system.clear(unit)
	var formation_home: Variant = unit.get("formation_home")
	if formation_home is Vector2 and int(unit.get("formation_group_id", -1)) >= 0:
		unit["task"] = "move"
		unit["formation_slot_mode"] = "soft"
		OrderPipeline.begin(unit, "move", -1, formation_home, false)
		if not assign_unit_destination(unit, formation_home):
			restore_formation_facing(unit)
	elif String(resume.get("task", "")) in ["move", "attack_move"] and resume.get("destination") is Vector2:
		var resume_task := String(resume["task"])
		var resume_destination: Vector2 = resume["destination"]
		unit["task"] = resume_task
		OrderPipeline.begin(unit, resume_task, -1, resume_destination, false)
		if not assign_unit_destination(unit, resume_destination):
			unit["task"] = "idle"
			OrderPipeline.complete(unit, "resume_unreachable")
	else:
		unit["task"] = "idle"
		release_unit_destination(unit)
		restore_formation_facing(unit)


func halt_unit(unit: Dictionary, reason: String = "stopped") -> void:
	conversion_system.cancel(unit, reason)
	healing_system.cancel(unit, reason)
	trade_system.cancel(unit, reason)
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
	release_unit_destination(unit)
	restore_formation_facing(unit)
	OrderPipeline.complete(unit, reason)
	EntityComponents.sync_dynamic(unit)


func _clear_combat_intent(unit: Dictionary) -> void:
	unit["attack_autonomous"] = false
	unit["combat_resume"] = {}
	unit["combat_leash_origin"] = unit.get("pos", Vector2.ZERO)

func _release_finished_combat_reservations() -> void:
	# Release the whole finished engagement before any member reserves its home.
	# Otherwise stale contact slots can displace early returners from exact slots.
	for unit in units:
		if String(unit.get("task", "")) != "attack":
			continue
		var target = find_combat_target(int(unit.get("target_id", -1)))
		if target == null or float(target.get("hp", 0.0)) <= 0.0:
			release_unit_destination(unit)

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
	var upgraded_entities: Array[Dictionary] = []
	var upgraded_entity_ids: Dictionary = {}
	for command_value in commands:
		var command: Dictionary = command_value
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
	var researched := technology_system.researched_ids(team)
	for entity in get_all_units_including_embarked() + buildings:
		if int(entity.get("team", 0)) == team and not bool(entity.get("technology_locked", false)):
			entity.get("components", {}).get("technology", {})["researched_ids"] = researched.duplicate()
	if not is_bulk_loading():
		rebuild_navigation_grid()
	if resolve_automatic:
		resolve_automatic_technologies(team)


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
		apply_attribute_effect(entity, command_value)
	entity.get("components", {}).get("technology", {})["researched_ids"] = technology_system.researched_ids(team)


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
	components.get("health", {})["maximum"] = entity["max_hp"]
	components.get("health", {})["current"] = entity["hp"]
	components.get("vision", {})["range"] = float(source.get("line_of_sight", components.get("vision", {}).get("range", 0.0)))
	components.get("movement", {})["speed"] = entity["speed"]
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
			components.get("health", {})["maximum"] = entity["max_hp"]
			components.get("health", {})["current"] = entity["hp"]
		1:
			var vision: Dictionary = components.get("vision", {})
			vision["range"] = maxf(0.0, apply_effect_operator(float(vision.get("range", 0.0)), effect_type, value))
		5:
			entity["speed"] = maxf(0.0, apply_effect_operator(float(entity.get("speed", 0.0)), effect_type, value))
			components.get("movement", {})["speed"] = entity["speed"]
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
			entity["graphic_angle_count"] = roundi(apply_effect_operator(float(entity.get("graphic_angle_count", 0)), effect_type, value))
		19:
			components.get("combat", {})["ballistics"] = value > 0.0
		100:
			components.get("production", {})["resource_cost_modifier"] = {"operator": effect_type, "value": value}
		101:
			entity["population_cost"] = maxi(0, roundi(apply_effect_operator(float(entity.get("population_cost", 0)), effect_type, value)))


func technology_effect_matches_entity(entity: Dictionary, command: Dictionary) -> bool:
	var unit_id := int(command.get("attr_a", -1))
	if unit_id >= 0:
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

func get_resources() -> Array:
	return resource_nodes

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
	var route: Array[Vector2] = pathfinder.find_path(start, goal, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
	return not route.is_empty()


func is_unit_in_attack_range(unit: Dictionary, target: Dictionary) -> bool:
	return CombatRules.is_in_range(unit, target)


func configure_victory_rules(rules: Array) -> void:
	victory_system.configure(rules)
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
	return objective


func set_victory_object_owner(object_id: int, team: int) -> bool:
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == object_id:
			objective["team"] = team
			return true
	return false


func set_victory_object_completed(object_id: int, completed: bool) -> bool:
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == object_id:
			objective["completed"] = completed
			return true
	return false


func remove_victory_object(object_id: int) -> bool:
	for objective in victory_objectives:
		if int(objective.get("id", -1)) == object_id:
			objective["active"] = false
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

