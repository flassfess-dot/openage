class_name RoRAiObservationStore
extends RefCounted

const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")
const ObservationQueries := preload("res://scripts/simulation_observation_queries.gd")
const ReadContract := preload("res://scripts/entity_read_contract.gd")
const ProjectileObservation := preload("res://scripts/ai_projectile_observation.gd")

# AI consumes legal simulation knowledge, not render state. Keep that projection
# on its own lifecycle and retain compact entity records between decisions. The
# unchanged records are reused; changed records are replaced without modifying
# earlier observations. Each observer retains its own fog-filtered entity set.

var observer_caches: Dictionary = {}
var active_world
var active_team := -1
var active_versions: Dictionary = {}
var active_cache: Dictionary = {}
var prepared_projection_enabled := true
const MAX_OBSERVERS := 8
const MAX_PROJECTION_BYTES := 8 * 1024 * 1024
const MAX_PROJECTIONS := 16384
const PROJECTION_CATEGORIES := ["units", "buildings", "objectives"]
const PROJECTION_SCHEMA := {
	"categories": PROJECTION_CATEGORIES,
	"fields": ReadContract.AI_FIELDS, "visible_fields": ReadContract.VISIBLE_AI_FIELDS,
	"array_fields": ReadContract.ARRAY_FIELDS, "private_trade_fields": ReadContract.PRIVATE_TRADE_FIELDS,
	"render_key": ReadContract.RENDER_SCHEMA_KEY, "render_version": ReadContract.SCHEMA_VERSION,
	"max_records": MAX_PROJECTIONS, "max_bytes": MAX_PROJECTION_BYTES,
}
var projection_kernel: Variant = null
var projection_capture_sequence := 0
var profile_projection := "--profile-ai-projection-alternatives" in OS.get_cmdline_user_args()
var compare_projection := "--compare-ai-projection-results" in OS.get_cmdline_user_args()
var projection_counters: Dictionary = {}


func clear() -> void:
	observer_caches.clear()
	active_world = null
	active_versions.clear()
	active_cache = {}


func observe_with_queries(world, tick: int, observer_team: int, options: Dictionary = {}) -> Dictionary:
	return ObservationQueries.enrich(world, observe(world, tick, observer_team, options), options)


# Retain legal factual records only; placement and command queries are explicit.
func observe(world, tick: int, observer_team: int, options: Dictionary = {}, prepared: Dictionary = {}) -> Dictionary:
	if observer_team <= 0 or not _supports_retained_projection(options):
		return SimulationSnapshot.presentation(world, tick, observer_team, options)
	var probe: Variant = options.get("performance_probe")
	var prefix := String(options.get("performance_prefix", "presentation.ai.snapshot"))
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	var fog = world.get_fog_of_war()
	fog.ensure_player(observer_team)
	var observer_states: PackedByteArray = fog.states_by_player[observer_team]
	var fog_map_size: Vector2i = fog.map_size
	var cache: Dictionary = _cache_for(observer_team)
	if int(cache.get("epoch", -1)) != int(world.entity_changes.epoch):
		cache = {"units": {}, "buildings": {}, "objectives": {}, "versions": {}, "epoch": int(world.entity_changes.epoch)}
		observer_caches[observer_team] = cache
	active_cache = cache
	active_world = world
	active_team = observer_team
	active_versions = cache.get("versions", {})
	cache["versions"] = active_versions
	var prepared_ready: bool = (
		prepared_projection_enabled
		and not prepared.is_empty()
		and int(world.read_generation_pins) > 0
		and prepared.get("world") is WeakRef
		and prepared["world"].get_ref() == world
		and int(prepared.get("team", -1)) == observer_team
		and int(prepared.get("epoch", -1)) == int(world.entity_changes.epoch)
		and int(prepared.get("revision", -1)) == int(world.entity_changes.revision)
		and int(prepared.get("fog_revision", -1)) == int(fog.revision)
		and bool(prepared.get("complete", false))
		and is_same(prepared.get("cache"), cache)
	)

	var units: Array = []
	var seen_unit_ids: Dictionary = {}
	# These owner-local rows were selected with the observer's fog at the
	# pinned revision above. The live references expire with this capture.
	var legal: Dictionary = prepared.get("legal", {}) if prepared_ready else {}
	var unit_rows: Array = legal["units"] if legal.has("units") else world.entity_read_index.legal_entities(world, observer_team, "units")
	for unit_value in unit_rows:
		var unit: Dictionary = unit_value
		if not prepared_ready and not _entity_visible(unit, observer_team, observer_states, fog_map_size):
			continue
		var unit_id := int(unit.get("id", -1))
		var projected := _project_entity(cache["units"], unit, observer_team, prepared_ready)
		# Alliance shares vision, not the transport's private cargo manifest/count.
		units.append(projected)
		seen_unit_ids[unit_id] = true
	_prune_entity_cache(cache["units"], seen_unit_ids)
	_sort_by_entity_id_if_needed(units)
	_observe_stage(probe, prefix + ".units", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	# Resource knowledge already has an incremental fog-memory cache in the
	# world. Reuse its immutable AI projection rather than introducing another
	# owner for the same data.
	var resources: Array
	if world.has_method("get_known_ai_resource_snapshot"):
		resources = world.get_known_ai_resource_snapshot(observer_team)
	else:
		resources = world.get_known_ai_resources(observer_team).duplicate() if world.has_method("get_known_ai_resources") else _project_resources(world.get_known_resources(observer_team), observer_team)
	_observe_stage(probe, prefix + ".resources", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	var objectives: Array = []
	var seen_objective_ids: Dictionary = {}
	var objective_rows: Array = legal["objectives"] if legal.has("objectives") else world.entity_read_index.legal_entities(world, observer_team, "objectives")
	for objective_value in objective_rows:
		var objective: Dictionary = objective_value
		if not bool(objective.get("active", true)) or (not prepared_ready and not _entity_visible(objective, observer_team, observer_states, fog_map_size)):
			continue
		var objective_id := int(objective.get("id", -1))
		objectives.append(_project_entity(cache["objectives"], objective, observer_team, prepared_ready))
		seen_objective_ids[objective_id] = true
	_prune_entity_cache(cache["objectives"], seen_objective_ids)
	_sort_by_entity_id_if_needed(objectives)
	_observe_stage(probe, prefix + ".objectives", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	var buildings: Array = []
	var seen_building_ids: Dictionary = {}
	var remembered_buildings: Dictionary = world.last_known_buildings_by_player.get(observer_team, {})
	var blocked_population_queues := 0
	var building_rows: Array = legal["buildings"] if legal.has("buildings") else world.entity_read_index.legal_entities(world, observer_team, "buildings")
	for building_value in building_rows:
		var building: Dictionary = building_value
		var building_id := int(building.get("id", -1))
		var own_building := int(building.get("team", 0)) == observer_team
		if own_building:
			var own_queue: Array = building.get("production_queue", [])
			if not own_queue.is_empty() and String(own_queue[0].get("status", "")) == "blocked_population":
				blocked_population_queues += 1
		var visible_now := prepared_ready or _entity_visible(building, observer_team, observer_states, fog_map_size)
		var knowledge: Dictionary = building
		if visible_now:
			_remember_visible_building(remembered_buildings, building_id, building)
		else:
			knowledge = remembered_buildings.get(building_id, {})
			if knowledge.is_empty():
				continue
			var remembered_position := Vector2(knowledge.get("pos", Vector2.ZERO))
			var remembered_cell := Vector2i(floori(remembered_position.x), floori(remembered_position.y))
			var remembered_state := int(fog.state_at_cell(observer_team, remembered_cell))
			if remembered_state != 1:
				if remembered_state == 2:
					remembered_buildings.erase(building_id)
				continue
		var projected := _project_entity(cache["buildings"], knowledge, observer_team, prepared_ready)
		if not visible_now:
			projected = projected.duplicate()
			projected["last_known"] = true
		else:
			projected = projected.duplicate()
			projected["target_domains"] = world.combat_target_domains(building)
			if world.trade_system.is_trade_dock(building):
				projected["trade"] = world.trade_system.presentation_for_dock(building)
		if visible_now and own_building:
			_add_population_point_costs(world, projected, observer_team)
		buildings.append(projected)
		seen_building_ids[building_id] = true

	var remembered_ids: Array = remembered_buildings.keys()
	remembered_ids.sort()
	for missing_id_value in remembered_ids:
		var missing_id := int(missing_id_value)
		if seen_building_ids.has(missing_id):
			continue
		var memory: Dictionary = remembered_buildings[missing_id]
		var memory_position := Vector2(memory.get("pos", Vector2.ZERO))
		var memory_state := int(fog.state_at_world(observer_team, memory_position))
		if memory_state == 2:
			remembered_buildings.erase(missing_id)
			continue
		if memory_state != 1:
			continue
		var projected_memory := _project_entity(cache["buildings"], memory, observer_team, prepared_ready)
		projected_memory = projected_memory.duplicate()
		projected_memory["last_known"] = true
		buildings.append(projected_memory)
		seen_building_ids[missing_id] = true
	world.last_known_buildings_by_player[observer_team] = remembered_buildings
	_prune_entity_cache(cache["buildings"], seen_building_ids)
	_sort_by_entity_id_if_needed(buildings)
	_observe_stage(probe, prefix + ".buildings", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0

	var player_state: Dictionary = SimulationSnapshot.presentation_player_state(world, observer_team)
	player_state["blocked_population_queues"] = blocked_population_queues
	_observe_stage(probe, prefix + ".player_state", stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0
	var include_fog_cells := bool(options.get("include_fog_cells", false))
	var presented_fog: Dictionary = SimulationSnapshot.presentation_fog(fog, observer_team) if include_fog_cells else {"observer_team": observer_team, "cells": []}
	var tactical_projectiles: Array = []
	if bool(options.get("include_ai_projectiles",false)):
		for projectile in world.get_projectiles():
			if _entity_visible(projectile,observer_team,observer_states,fog_map_size): tactical_projectiles.append(ProjectileObservation.project(projectile,observer_team))
		tactical_projectiles = ProjectileObservation.select_visible(tactical_projectiles,units,observer_team)
	_observe_stage(probe, prefix + ".state", stage_started)
	return {
		"format_version": SimulationSnapshot.FORMAT_VERSION,
		"tick": tick,
		"match_seed": world.simulation_seed,
		"tactical_only": bool(options.get("tactical_only",false)),
		"observer_team": observer_team,
		"map_size": world.map_size,
		"units": units,
		"resources": resources,
		"objectives": objectives,
		"buildings": buildings,
		"projectiles": tactical_projectiles,
		"overview": {"units": [], "resources": [], "buildings": []},
		"ai_distress_signals": world.get_attack_distress_signals(observer_team),
		"team_intents": world.ai_distress_system.intents_for_team(world,observer_team),
		"navigation": {},
		"build_sites": {},
		"fog_revision": int(fog.revision_for_player(observer_team)),
		"fog_exploration_revision": int(fog.exploration_revision_for_player(observer_team)),
		"resource_memory_revision": int(world.known_resource_revision(observer_team)) if world.has_method("known_resource_revision") else 0,
		"fog": presented_fog,
		"player_state": player_state,
		"battle_over": bool(world.battle_over),
		"battle_message": String(world.battle_message),
		"match_result": world.get_victory_result(),
		"victory_rules": world.victory_system.rules.duplicate(true),
		"match_elapsed_seconds": float(world.victory_system.elapsed_seconds),
		"scenario": {},
	}


func _supports_retained_projection(options: Dictionary) -> bool:
	# The retained store intentionally implements the compact planner contract.
	# Rich render/scenario projections keep using the general snapshot path so a
	# future caller cannot silently receive a narrower payload than requested.
	return (
		bool(options.get("compact_entities", false))
		and not bool(options.get("compact_render_entities", false))
		and not bool(options.get("include_projectiles", true))
		and not bool(options.get("include_scenario", true))
		and not bool(options.get("include_overview", false))
		and not bool(options.get("include_overview_resources", false))
		and not options.has("entity_bounds")
		and options.get("always_include_entity_ids", []).is_empty()
	)


func _cache_for(observer_team: int) -> Dictionary:
	var cache: Dictionary = observer_caches.get(observer_team, {})
	if cache.is_empty():
		if observer_caches.size() >= MAX_OBSERVERS: observer_caches.erase(observer_caches.keys()[0])
		cache = {"units": {}, "buildings": {}, "objectives": {}}
		observer_caches[observer_team] = cache
	return cache


func _project_entity(entity_cache: Dictionary, source: Dictionary, observer_team: int, prepared: bool = false) -> Dictionary:
	var entity_id := int(source.get("id", -1))
	var immutable: Dictionary
	var memory := ReadContract.is_render_record(source)
	# A completed preparation owns this cache at the same pinned world/fog
	# generation. Capacity eviction may still miss a row; retain the normal path.
	if prepared and not memory and entity_cache.has(entity_id): return entity_cache[entity_id]
	var version: int = active_world.entity_changes.revision_for(entity_id, 255) if active_world != null and not memory else -1
	var key := Vector2i(entity_id, 1 if memory else 0)
	if not memory and entity_cache.has(entity_id) and active_versions.get(key, -2) == version:
		immutable = entity_cache[entity_id]
	else:
		immutable = ReadContract.ai(source, observer_team, entity_cache.get(entity_id, {}))
		active_versions[key] = version
	if entity_id >= 0 and not active_cache.is_empty():
		var category := "units"
		for key_name in ["units", "buildings", "objectives"]:
			if is_same(entity_cache, active_cache[key_name]):
				category = key_name
				break
		var bookkeeping: Dictionary = active_cache.get("retained", {})
		active_cache["retained"] = bookkeeping
		var old: Dictionary = bookkeeping.get(entity_id, {})
		if not is_same(entity_cache.get(entity_id), immutable):
			var bytes := var_to_bytes(immutable).size() + 96
			var total := int(active_cache.get("bytes", 0)) - int(old.get("bytes", 0))
			bookkeeping.erase(entity_id)
			entity_cache.erase(entity_id)
			while not bookkeeping.is_empty() and (bookkeeping.size() >= MAX_PROJECTIONS or total + bytes > MAX_PROJECTION_BYTES):
				var evicted: Variant = bookkeeping.keys()[0]
				var record: Dictionary = bookkeeping[evicted]
				active_cache[record["category"]].erase(evicted)
				total -= int(record["bytes"])
				bookkeeping.erase(evicted)
				active_versions.erase(Vector2i(int(evicted), 0))
				active_versions.erase(Vector2i(int(evicted), 1))
			if bytes <= MAX_PROJECTION_BYTES:
				entity_cache[entity_id] = immutable
				bookkeeping[entity_id] = {"bytes": bytes, "category": category}
				total += bytes
			active_cache["bytes"] = total
			if not entity_cache.has(entity_id):
				active_versions.erase(Vector2i(entity_id, 0))
				active_versions.erase(Vector2i(entity_id, 1))
	# Retained records are immutable. Callers that add observation-local fields
	# copy only those rows, instead of shallow-copying every moving actor twice
	# (projection preparation and factual publication) on every AI decision.
	return immutable


func _remember_visible_building(memories: Dictionary, building_id: int, building: Dictionary) -> void:
	memories[building_id] = active_world.compact_render_projection(building)


func _add_population_point_costs(world, projected: Dictionary, observer_team: int) -> void:
	projected["production_queue"] = projected.get("production_queue", []).duplicate(true)
	for order_value in projected.get("production_queue", []):
		var order: Dictionary = order_value
		if String(order.get("order_type", "unit")) == "unit":
			order["population_points_cost"] = world.unit_population_points_cost(String(order.get("kind", "")), observer_team)


func _project_resources(source: Array, observer_team: int) -> Array:
	var result: Array = []
	for resource_value in source:
		result.append(SimulationSnapshot.compact_ai_entity(resource_value, observer_team))
	return result


func _prune_entity_cache(entity_cache: Dictionary, seen_ids: Dictionary) -> void:
	for entity_id_value in entity_cache.keys():
		if not seen_ids.has(int(entity_id_value)):
			entity_cache.erase(entity_id_value)
			var retained: Dictionary = active_cache.get("retained", {})
			if retained.has(entity_id_value):
				active_cache["bytes"] = int(active_cache.get("bytes", 0)) - int(retained[entity_id_value]["bytes"])
				retained.erase(entity_id_value)
			active_versions.erase(Vector2i(int(entity_id_value), 0))
			active_versions.erase(Vector2i(int(entity_id_value), 1))


func _sync_array_field(target: Dictionary, source: Dictionary, field: String) -> void:
	if source.has(field):
		_sync_array_value(target, field, source.get(field, []))
	else:
		target.erase(field)


func _sync_array_value(target: Dictionary, field: String, source_value: Array) -> void:
	var current: Array = target.get(field, [])
	if current != source_value:
		target[field] = source_value.duplicate()


func _id_lookup(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for entity_id_value in ids:
		result[int(entity_id_value)] = true
	return result


func _sort_by_entity_id_if_needed(entities: Array) -> void:
	var previous_id := -9223372036854775807
	for entity_value in entities:
		var entity_id := int(entity_value.get("id", -1))
		if entity_id < previous_id:
			entities.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
			return
		previous_id = entity_id


func _entity_visible(entity: Dictionary, observer_team: int, states: PackedByteArray, map_size: Vector2i) -> bool:
	if int(entity.get("team", 0)) == observer_team:
		return true
	var position := Vector2(entity.get("pos", entity.get("position", Vector2.ZERO)))
	var cell_x := floori(position.x)
	var cell_y := floori(position.y)
	if cell_x < 0 or cell_y < 0 or cell_x >= map_size.x or cell_y >= map_size.y:
		return false
	return int(states[cell_y * map_size.x + cell_x]) == 2


func _observe_stage(probe: Variant, metric: String, started: int) -> void:
	if probe != null:
		probe.observe_microseconds(metric, Time.get_ticks_usec() - started)

func _projection_counter(key: String, value: int = 1) -> void:
	projection_counters[key] = int(projection_counters.get(key, 0)) + value

func _projection_rows_reference(legal_sets: Array, cache: Dictionary, world) -> Array:
	var rows: Array = []
	for category_index in range(PROJECTION_CATEGORIES.size()):
		var category: String = PROJECTION_CATEGORIES[category_index]
		for row in legal_sets[category_index]:
			var entity_id := int(row.get("id", -1))
			if not ReadContract.is_render_record(row) and cache[category].has(entity_id) and cache["versions"].get(Vector2i(entity_id, 0), -2) == world.entity_changes.revision_for(entity_id, 255):
				continue
			rows.append({"source": row, "category": category})
	return rows

func _projection_cache_copy(cache: Dictionary) -> Dictionary:
	# Copy mutable cache containers, retaining the exact immutable DTO islands.
	var copy := cache.duplicate()
	for category in PROJECTION_CATEGORIES:
		copy[category] = cache[category].duplicate()
	copy["versions"] = cache["versions"].duplicate()
	if cache.has("retained"): copy["retained"] = cache["retained"].duplicate()
	return copy

func _compare_projection_portion(cache: Dictionary, before: Dictionary, rows: Array, begin: int, finish: int, team: int) -> void:
	var started := Time.get_ticks_usec()
	active_cache = before
	active_versions = before["versions"]
	for index in range(begin, finish):
		var item: Dictionary = rows[index]
		_project_entity(before[item["category"]], item["source"], team)
	active_cache = cache
	active_versions = cache["versions"]
	_projection_counter("compared_portions")
	_projection_counter("comparison_us", Time.get_ticks_usec() - started)
	if cache != before:
		_projection_counter("mismatches")
		push_error("Native AI retained projection differs from the canonical cache")
	# Also sample the independent field/privacy contract on the actual legal
	# source. The normal cache comparison deliberately uses the existing kernel.
	var record_started := Time.get_ticks_usec()
	for index in range(begin, finish, 16):
		var item: Dictionary = rows[index]
		var source: Dictionary = item["source"]
		var entity_id := int(source.get("id", -1))
		if not cache[item["category"]].has(entity_id): continue
		var expected := ReadContract.ai_reference(source, team)
		_projection_counter("compared_records")
		if cache[item["category"]][entity_id] != expected:
			_projection_counter("mismatches")
			push_error("Native AI projection differs from the independent field contract")
	_projection_counter("record_comparison_us", Time.get_ticks_usec() - record_started)

func prepare_projection(world, team: int, pending: Dictionary, maximum: int = 96) -> bool:
	var cache: Dictionary = _cache_for(team)
	if int(cache.get("epoch", -1)) != int(world.entity_changes.epoch):
		cache = {"units": {}, "buildings": {}, "objectives": {}, "versions": {}, "epoch": int(world.entity_changes.epoch)}
		observer_caches[team] = cache
	# Projection portions may alternate between observers. Bookkeeping and
	# eviction must belong to the same cache as the rows being prepared.
	active_cache = cache
	active_world = world
	active_team = team
	active_versions = cache.get("versions", {})
	cache["versions"] = active_versions
	if not pending.has("rows"):
		projection_capture_sequence += 1
		var native := ReadContract.native_enabled and ReadContract.native_ai_enabled and ClassDB.class_exists("RoRReadModelKernel")
		if native and projection_kernel == null: projection_kernel = ClassDB.instantiate("RoRReadModelKernel")
		native = native and projection_kernel.has_method("collect_ai_projection_changes") and projection_kernel.has_method("retain_ai_projection_portion")
		if profile_projection: native = native and projection_capture_sequence % 2 == 1
		pending["native"] = native
		pending["compare"] = native and compare_projection and (projection_capture_sequence <= 16 or projection_capture_sequence % 64 == 1)
		var legal_started := Time.get_ticks_usec() if profile_projection or compare_projection else 0
		var legal_sets: Array = []
		var legal := {}
		for category in PROJECTION_CATEGORIES:
			var rows: Array = world.entity_read_index.legal_entities(world, team, category)
			legal_sets.append(rows)
			legal[category] = rows
		pending["legal"] = legal
		if legal_started > 0: _projection_counter("legal_sources_us", Time.get_ticks_usec() - legal_started)
		var started := Time.get_ticks_usec() if profile_projection or compare_projection else 0
		var collected: Dictionary = projection_kernel.collect_ai_projection_changes(legal_sets, PROJECTION_CATEGORIES, cache, world.entity_changes.version_source(), PROJECTION_SCHEMA) if native else {}
		if native and not bool(collected.get("supported", false)):
			native = false
			pending["native"] = false
			pending["compare"] = false
		pending["rows"] = collected["rows"] if native else _projection_rows_reference(legal_sets, cache, world)
		if started > 0:
			_projection_counter("collect_native_us" if native else "collect_reference_us", Time.get_ticks_usec() - started)
			_projection_counter("native_captures" if native else "reference_captures")
		if bool(pending["compare"]):
			var comparison_started := Time.get_ticks_usec()
			var expected := _projection_rows_reference(legal_sets, cache, world)
			var actual: Array = pending["rows"]
			var matches := actual.size() == expected.size()
			for index in range(mini(actual.size(), expected.size())):
				matches = matches and actual[index]["category"] == expected[index]["category"] and is_same(actual[index]["source"], expected[index]["source"])
			_projection_counter("compared_collections")
			_projection_counter("comparison_us", Time.get_ticks_usec() - comparison_started)
			if not matches:
				_projection_counter("mismatches")
				push_error("Native AI projection change set differs from legal source collection")
		pending["cursor"] = 0
	var finish := mini(pending["rows"].size(), int(pending["cursor"]) + maxi(1, maximum))
	var before := _projection_cache_copy(cache) if bool(pending["compare"]) else {}
	var started := Time.get_ticks_usec() if profile_projection or compare_projection else 0
	var native: bool = pending["native"]
	if native: native = projection_kernel.retain_ai_projection_portion(pending["rows"], int(pending["cursor"]), finish, team, cache, world.entity_changes.version_source(), PROJECTION_SCHEMA)
	if not native:
		for index in range(int(pending["cursor"]), finish):
			var item: Dictionary = pending["rows"][index]
			_project_entity(cache[item["category"]], item["source"], team)
	if started > 0:
		_projection_counter("native_us" if native else "reference_us", Time.get_ticks_usec() - started)
		_projection_counter("native_portions" if native else "reference_portions")
		_projection_counter("native_rows" if native else "reference_rows", finish - int(pending["cursor"]))
	if bool(pending["compare"]): _compare_projection_portion(cache, before, pending["rows"], int(pending["cursor"]), finish, team)
	pending["cursor"] = finish
	var complete: bool = finish == pending["rows"].size()
	if complete:
		pending["world"] = weakref(world)
		pending["team"] = team
		pending["epoch"] = int(world.entity_changes.epoch)
		pending["revision"] = int(world.entity_changes.revision)
		pending["fog_revision"] = int(world.get_fog_of_war().revision)
		pending["cache"] = cache
		pending["complete"] = true
	return complete
