class_name RoRGameCheckpoint
extends RefCounted

const EntityComponents := preload("res://scripts/entity_components.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Formation := preload("res://scripts/formation_group.gd")
const KnowledgeGrid := preload("res://scripts/navigation_knowledge_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const VERSION := 1
const MAX_BYTES := 268435456
# Durable state is explicit. Catalogs, projections, spatial indices and native
# objects are reconstructed rather than serialized as implementation objects.
const WORLD_FIELDS := ["map_size", "map_terrain_ids", "map_reserved_foundation_cells", "forest_resource_counts", "terrain_revision", "units", "resource_nodes", "buildings", "static_obstructions", "civilization_by_team", "full_tech_tree_enabled", "resource_approach_slots", "building_approach_slots", "last_build_failure", "victory_objectives", "score_by_team", "conquest_counts_by_team", "conquest_tracked_by_id", "unit_removal_pending", "building_removal_pending", "kills", "battle_over", "battle_message", "simulation_seed"]
const LIST_INDICES := ["capturable_units", "dying_units", "dying_buildings", "decaying_resource_nodes", "falling_resource_nodes", "capturable_victory_objectives"]
const GRID_FIELDS := ["size", "terrain_cells", "terrain_ids", "occupied_cells", "elevation_cells", "slope_cells", "revision", "surface_revision", "_change_log"]
const FOG_FIELDS := ["map_size", "states_by_player", "personally_explored_by_player", "visible_counts_by_player", "revisions_by_player", "exploration_revisions_by_player", "newly_explored_cells_by_player", "newly_visible_cells_by_player", "allies_by_player", "shared_vision_by_player", "visibility_topology_dirty", "revision", "source_scan_generation", "path_dirty_by_player"]
const SYSTEM_FIELDS := {
	"economy_system": ["resource_stockpiles_by_team", "population_by_team", "population_points_by_team", "population_reserved_by_team", "population_cap_by_team", "population_limit_by_team", "population_housing_by_team", "population_housing_enabled_by_team"],
	"production_system": ["next_order_id", "last_production_failure", "last_research_failure", "last_research_message", "last_completed_research_id", "active_building_ids", "building_order_by_id", "next_building_order"],
	"combat_system": ["projectiles", "resolved_projectiles"],
	"technology_system": ["team_states", "revision_by_team"],
	"player_registry": ["players", "relations"],
	"ai_distress_system": ["next_sequence", "signals_by_target_id"],
	"transport_system": ["embarked_units", "last_failure"],
	"trade_system": ["trade_goods_by_team", "pool_policies_by_team", "last_failure"],
	"victory_system": ["rules", "allied_victory_enabled", "elapsed_seconds", "hold_seconds", "objective_summary", "tracked_objectives", "result"],
	"scenario_system": ["definition", "condition_states", "group_states", "result"],
	"visibility_system": ["movement_refresh_bucket"],
	"destination_reservations": ["reservations"],
	"terrain_elevation": ["vertex_levels"],
}

static func _capture_fields(owner, fields: Array) -> Dictionary:
	var result := {}
	for field in fields: result[field] = owner.get(field)
	return result.duplicate(true)

static func _restore_fields(owner, values: Dictionary, fields: Array) -> void:
	for field in fields:
		if not values.has(field): continue
		var current: Variant = owner.get(field)
		if current is Array and current.is_typed():
			current.assign(values[field])
		else:
			owner.set(field, values[field])

static func _entity_ids(source: Array) -> Array:
	var result := []
	for entity in source: result.append(int(entity["id"]))
	return result

static func _entity_refs(ids: Array, entities: Dictionary) -> Array:
	var result := []
	for id in ids:
		if entities.has(id): result.append(entities[id])
	return result

static func _capture_runtime(world, controller) -> Dictionary:
	# These retained indices also carry timing or historical bucket membership.
	# Rebuilding them at a different tick can change autonomous decisions.
	var awareness = controller.combat_awareness
	var combat := _capture_fields(awareness, ["cached_entity_count", "cached_roster_tick", "cached_roster_revision", "cached_candidate_index_tick"])
	combat["attackers"] = _entity_ids(awareness.cached_attackers)
	combat["targets"] = _entity_ids(awareness.cached_targets)
	combat["index"] = {"maximum_radius": awareness.cached_candidate_index.get("maximum_radius", 0.0), "buckets": {}}
	for cell in awareness.cached_candidate_index.get("buckets", {}):
		combat["index"]["buckets"][cell] = {}
		for team in awareness.cached_candidate_index["buckets"][cell]:
			combat["index"]["buckets"][cell][team] = _entity_ids(awareness.cached_candidate_index["buckets"][cell][team])
	var wildlife = controller.wildlife_behavior
	var animals := _capture_fields(wildlife, ["cached_unit_count", "cached_roster_tick", "cached_world_roster_revision"])
	animals["roster"] = _entity_ids(wildlife.cached_wildlife)
	animals["due"] = []
	for bucket in wildlife.cached_due_wildlife: animals["due"].append(_entity_ids(bucket))
	var activity := _capture_fields(world.unit_activity_registry, ["unit_order_by_id", "order_dirty", "roster_dirty", "compatibility_ticks", "movement_candidate_active", "formation_active", "tick_prepared"])
	activity["active"] = _entity_ids(world.unit_activity_registry.active_units)
	return {"open_movement_envelopes": world.open_movement_envelopes_by_id.duplicate(true), "activity": activity, "combat": combat, "wildlife": animals, "roster_revision": world.combat_roster_revision, "activity_ticks": world.unit_activity_registry.compatibility_ticks, "spatial_ticks": world.spatial_sync_system.compatibility_ticks}

static func _restore_runtime(runtime: Dictionary, world, controller, entities: Dictionary) -> void:
	if runtime.is_empty(): return
	world.open_movement_envelopes_by_id = runtime.get("open_movement_envelopes", {}).duplicate(true)
	world.combat_roster_revision = int(runtime["roster_revision"])
	var activity = world.unit_activity_registry
	if runtime.has("activity"):
		_restore_fields(activity, runtime["activity"], ["unit_order_by_id", "order_dirty", "roster_dirty", "compatibility_ticks", "movement_candidate_active", "formation_active", "tick_prepared"])
		activity.active_units = _entity_refs(runtime["activity"]["active"], entities)
		activity.active_units_by_id.clear()
		for unit in activity.active_units: activity.active_units_by_id[int(unit["id"])] = unit
		activity._rebuild_active_indices()
	else: activity.compatibility_ticks = int(runtime["activity_ticks"])
	world.spatial_sync_system.compatibility_ticks = int(runtime["spatial_ticks"])
	var saved: Dictionary = runtime["combat"]
	var combat = controller.combat_awareness
	_restore_fields(combat, saved, ["cached_entity_count", "cached_roster_tick", "cached_roster_revision", "cached_candidate_index_tick"])
	combat.cached_attackers = _entity_refs(saved["attackers"], entities)
	combat.cached_targets = _entity_refs(saved["targets"], entities)
	combat.cached_candidate_index = {"maximum_radius": saved["index"]["maximum_radius"], "buckets": {}}
	for cell in saved["index"]["buckets"]:
		combat.cached_candidate_index["buckets"][cell] = {}
		for team in saved["index"]["buckets"][cell]:
			combat.cached_candidate_index["buckets"][cell][team] = _entity_refs(saved["index"]["buckets"][cell][team], entities)
	saved = runtime["wildlife"]
	var wildlife = controller.wildlife_behavior
	_restore_fields(wildlife, saved, ["cached_unit_count", "cached_roster_tick", "cached_world_roster_revision"])
	wildlife.cached_wildlife = _entity_refs(saved["roster"], entities)
	wildlife.cached_due_wildlife.clear()
	for bucket in saved["due"]: wildlife.cached_due_wildlife.append(_entity_refs(bucket, entities))

static func capture(world, controller, definition: Dictionary, map: Dictionary) -> Dictionary:
	var systems := {}
	for name in SYSTEM_FIELDS: systems[name] = _capture_fields(world.get(name), SYSTEM_FIELDS[name])
	var indices := {}
	for name in LIST_INDICES:
		indices[name] = []
		for entity in world.get(name): indices[name].append(int(entity["id"]))
	var fog := _capture_fields(world.fog_of_war, FOG_FIELDS)
	fog["sources"] = {}
	for key in world.fog_of_war.vision_sources:
		var source: Dictionary = world.fog_of_war.vision_sources[key].duplicate(true)
		source["entity_id"] = int(source.get("entity", {}).get("id", -1))
		source.erase("entity")
		fog["sources"][key] = source
	var knowledge := {}
	for team in world.movement_system.knowledge.entries:
		var entry: Dictionary = world.movement_system.knowledge.entries[team]
		var grid := _capture_fields(entry["grid"], GRID_FIELDS)
		grid["learned"] = entry["grid"].learned
		knowledge[team] = {"grid": grid, "source_revision": entry["source_revision"], "fog_revision": entry.get("fog_revision", -1)}
	var world_state := _capture_fields(world, WORLD_FIELDS)
	for unit in world_state["units"]:
		unit.erase("_formation_path_cache")
		unit.erase("formation_steering_target")
	return {"version": VERSION, "runtime": _capture_runtime(world, controller), "match_definition": definition.duplicate(true), "map_definition": map.duplicate(true), "world": world_state, "systems": systems, "indices": indices, "fog": fog, "grid": _capture_fields(world.navigation_grid, GRID_FIELDS), "knowledge": knowledge, "controller": Snapshot._controller_state(controller), "rng_state": world.simulation_rng.state, "next_entity_id": world.entity_id_sequence.peek(), "next_path_request": world.navigation_service.next_request_id, "event_sequence": controller.event_stream.latest_sequence(), "wildlife_homes": controller.wildlife_behavior.coastal_homes.duplicate(true)}

static func _digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

static func pack(checkpoint: Dictionary) -> Dictionary:
	var bytes := var_to_bytes(checkpoint)
	return {"version": VERSION, "size": bytes.size(), "sha256": _digest(bytes), "data": Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}

static func unpack(blob: Dictionary) -> Dictionary:
	if int(blob.get("version", -1)) != VERSION or int(blob.get("size", 0)) <= 0 or int(blob["size"]) > MAX_BYTES: return {}
	var bytes := Marshalls.base64_to_raw(String(blob.get("data", ""))).decompress(int(blob["size"]), FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != int(blob["size"]) or _digest(bytes) != String(blob.get("sha256", "")): return {}
	var decoded: Variant = bytes_to_var(bytes)
	return decoded if decoded is Dictionary and validate(decoded) else {}

static func validate(data: Dictionary) -> bool:
	if int(data.get("version", -1)) != VERSION: return false
	for name in ["match_definition", "map_definition", "world", "systems", "fog", "grid", "knowledge", "controller", "indices"]:
		if not data.get(name) is Dictionary: return false
	for field in WORLD_FIELDS:
		if not data["world"].has(field): return false
	var size: Variant = data["world"]["map_size"]
	if not size is Vector2i or size.x <= 0 or size.y <= 0 or size.x > 1024 or size.y > 1024: return false
	for group in ["units", "resource_nodes", "buildings", "static_obstructions"]:
		if not data["world"][group] is Array: return false
		for entity in data["world"][group]:
			if not entity is Dictionary: return false
			if group == "static_obstructions":
				if not entity.get("pos") is Vector2 and not entity.get("occupied_cells") is Array: return false
			elif not entity.get("pos") is Vector2: return false
	var all_ids := {}
	for group in ["units", "resource_nodes", "buildings"]:
		for entity in data["world"][group]:
			if not entity.get("id") is int or int(entity["id"]) < 0 or all_ids.has(entity["id"]): return false
			all_ids[entity["id"]] = true
	for system in SYSTEM_FIELDS:
		if not data["systems"].get(system) is Dictionary: return false
		for field in SYSTEM_FIELDS[system]:
			if not data["systems"][system].has(field): return false
	for section in [["grid", GRID_FIELDS], ["fog", FOG_FIELDS]]:
		for field in section[1]:
			if field == "path_dirty_by_player": continue # Earlier checkpoint migration rebuilds this journal.
			if not data[section[0]].has(field): return false
	if data["grid"]["size"] != size or data["fog"]["map_size"] != size or data["map_definition"].get("size", size) != size: return false
	if not data["fog"].get("sources") is Dictionary: return false
	for team in data["fog"]["states_by_player"]:
		var states: Variant = data["fog"]["states_by_player"][team]
		if not states is PackedByteArray or states.size() != size.x * size.y: return false
	for name in LIST_INDICES:
		if not data["indices"].get(name) is Array: return false
	for field in ["tick", "next_command_sequence", "next_formation_group_id"]:
		if not data["controller"].get(field) is int or int(data["controller"][field]) < 0: return false
	for field in ["pending_commands", "formation_groups"]:
		if not data["controller"].get(field) is Array: return false
	var replay := Replay.new()
	for record in data["controller"]["pending_commands"]:
		if not record is Dictionary or replay.command_from_record(record) == null: return false
	for field in ["rng_state", "next_entity_id", "next_path_request", "event_sequence"]:
		if not data.get(field) is int: return false
	if not data.get("wildlife_homes") is Dictionary: return false
	return true

static func restore(data: Dictionary, world, controller) -> bool:
	if not validate(data) or world.map_size != data["world"]["map_size"]: return false
	_restore_fields(world, data["world"], WORLD_FIELDS)
	# Derived cache cursors never survive a state replacement, including a
	# restore into the same objects with coincident saved revisions.
	world.cache_epoch += 1
	world.terrain_change_history.clear()
	world.navigation_grid.cache_epoch += 1
	world.terrain_elevation.cache_epoch += 1
	for name in SYSTEM_FIELDS: _restore_fields(world.get(name), data["systems"][name], SYSTEM_FIELDS[name])
	# Reconnect shared records: serialized values never retain object aliases.
	world.destination_reservations.restore_state(world.destination_reservations.reservations)
	world.population_by_team = world.economy_system.population_by_team
	world.population_reserved_by_team = world.economy_system.population_reserved_by_team
	world.population_cap_by_team = world.economy_system.population_cap_by_team
	world.resource_stockpiles_by_team = world.economy_system.resource_stockpiles_by_team
	world.projectiles = world.combat_system.projectiles
	world.resolved_projectiles = world.combat_system.resolved_projectiles
	world.units_by_id.clear()
	world.buildings_by_id.clear()
	world.resource_nodes_by_id.clear()
	world.resource_nodes_by_cell.clear()
	var entities := {}
	for pair in [[world.units, world.units_by_id], [world.buildings, world.buildings_by_id], [world.resource_nodes, world.resource_nodes_by_id]]:
		for entity in pair[0]:
			EntityComponents.sync_dynamic(entity)
			var id := int(entity["id"])
			pair[1][id] = entity
			entities[id] = entity
	for entity in world.get_embarked_units():
		EntityComponents.sync_dynamic(entity)
	for entity in world.victory_objectives:
		if not entities.has(int(entity["id"])): entities[int(entity["id"])] = entity
	for resource in world.resource_nodes:
		var index: int = world._resource_cell_index(resource)
		if not world.resource_nodes_by_cell.has(index): world.resource_nodes_by_cell[index] = []
		world.resource_nodes_by_cell[index].append(resource)
	for name in LIST_INDICES:
		var list: Array = world.get(name)
		list.clear()
		for id in data["indices"].get(name, []):
			if entities.has(id): list.append(entities[id])
	for building in world.buildings:
		building["components"]["production"]["queue"] = building["production_queue"]
	world.building_navigation_cells_by_id.clear()
	for building in world.buildings:
		world.building_navigation_cells_by_id[int(building["id"])] = world._building_navigation_cells(building)
	world.open_movement_envelopes_by_id.clear()
	world.known_resources_by_player.clear()
	world.known_ai_resources_by_player.clear()
	world.last_known_buildings_by_player.clear()
	world.ai_navigation_knowledge.clear()
	world.local_build_site_cache.clear()
	world.render_entity_projection_cache.clear()
	world.terrain_elevation.revision += 1
	world.terrain_elevation.nonzero_vertex_count = 0
	world.terrain_elevation.maximum_vertex_level = 0
	for level in world.terrain_elevation.vertex_levels.values():
		if int(level) != 0: world.terrain_elevation.nonzero_vertex_count += 1
		world.terrain_elevation.maximum_vertex_level = maxi(world.terrain_elevation.maximum_vertex_level, int(level))
	world.terrain_elevation.maximum_vertex_level_dirty = false
	world.unit_activity_registry.clear()
	world.mark_combat_roster_dirty()
	_restore_fields(world.navigation_grid, data["grid"], GRID_FIELDS)
	world.navigation_grid.surface_component_cache.clear()
	world.rebuild_spatial_index(false)
	world.pathfinder.clear_cache()
	world.movement_system.knowledge.clear()
	var fog = world.fog_of_war
	fog.cache_epoch += 1
	fog.visibility_change_history.clear()
	fog.exploration_change_history.clear()
	_restore_fields(fog, data["fog"], FOG_FIELDS)
	fog.vision_sources.clear()
	for key in data["fog"]["sources"]:
		var source: Dictionary = data["fog"]["sources"][key].duplicate(true)
		if entities.has(int(source["entity_id"])):
			source["entity"] = entities[int(source["entity_id"])]
			fog.vision_sources[key] = source
	# Projection cursors are new consumers and need fresh tracking journals.
	fog.navigation_newly_explored_by_player.clear()
	if not data["fog"].has("path_dirty_by_player"):
		fog.path_dirty_by_player.clear()
	fog.presentation_dirty_tracked_players.clear()
	for team in data["knowledge"]:
		var saved: Dictionary = data["knowledge"][team]
		var grid := KnowledgeGrid.new(world.map_size)
		_restore_fields(grid, saved["grid"], GRID_FIELDS)
		grid.learned = saved["grid"]["learned"]
		grid.terrain_restrictions = world.navigation_grid.terrain_restrictions
		var planner := Pathfinder.new(grid)
		planner.set_native_enabled(world.pathfinder.native_enabled)
		world.movement_system.knowledge.entries[team] = {"source": world.navigation_grid, "grid": grid, "planner": planner, "source_revision": saved["source_revision"], "fog_revision": saved["fog_revision"]}
		fog.track_path_knowledge(int(team))
		if not data["fog"].has("path_dirty_by_player"):
			var states: PackedByteArray = fog.states_by_player[team]
			for index in range(states.size()):
				if states[index] == 2: fog.path_dirty_by_player[team][index] = true
	world.simulation_rng.state = int(data["rng_state"])
	world.entity_id_sequence.reset(int(data["next_entity_id"]))
	world.navigation_service.reset()
	world.navigation_service.next_request_id = int(data["next_path_request"])
	controller.reset_timing()
	var saved: Dictionary = data["controller"]
	controller.tick_index = int(saved["tick"])
	controller.next_command_sequence = int(saved["next_command_sequence"])
	controller.next_formation_group_id = int(saved["next_formation_group_id"])
	controller.formation_groups.clear()
	for record in saved["formation_groups"]:
		var members: Array[int] = []
		members.assign(record["member_ids"])
		var group := Formation.new(int(record["group_id"]), members, record["anchor"], record["forward"], record["formation_type"], record["spacing"])
		_restore_fields(group, record, record.keys())
		controller.formation_groups[group.group_id] = group
	controller.command_queue.clear()
	var codec := Replay.new()
	for record in saved["pending_commands"]:
		var command = codec.command_from_record(record)
		if command == null: return false
		controller.command_queue.append(command)
	controller._rebuild_queued_unit_index()
	controller.set_world(world)
	controller.event_stream._events.clear()
	controller.event_stream._next_sequence = int(data["event_sequence"]) + 1
	controller.event_stream._first_sequence = controller.event_stream._next_sequence
	controller.wildlife_behavior.coastal_homes = data["wildlife_homes"]
	_restore_runtime(data.get("runtime", {}), world, controller, entities)
	return true
