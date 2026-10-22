extends RefCounted

# Owns this state; the world is passed per operation to avoid a reference cycle.
const BuildSiteTask := preload("res://scripts/build_site_task.gd")
const TaskData := preload("res://scripts/isolated_task_data.gd")
const Footprint := preload("res://scripts/footprint.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const MAX_BUILD_QUERY_SCOPE_BYTES := 4 * 1024 * 1024
const MAX_LOCAL_BUILD_SITE_CACHE_BYTES := 4 * 1024 * 1024
const MAX_LOCAL_BUILD_SITE_CACHE_ENTRIES := 64

var local_build_site_cache: Dictionary = {}
var build_query_scopes: Dictionary = {}
var ai_build_capture_cache: Dictionary = {}
var build_query_scope_bytes := 0
var local_build_site_cache_bytes := 0
var build_option_catalog_cache: Dictionary = {}

func clear_derived_queries() -> void:
	ai_build_capture_cache.clear()
	build_query_scopes.clear()
	build_query_scope_bytes = 0
	local_build_site_cache.clear()
	local_build_site_cache_bytes = 0


func get_build_options(world, team: int) -> Array:
	var result: Array = []
	if not world.data_repository.is_configured():
		return result
	for template_value in world._build_option_catalog(team).get("ordered", []):
		result.append(world._present_build_option(template_value, team))
	return result


func get_build_options_for_kinds(world, team: int, kinds: Array) -> Array:
	var result: Array = []
	if not world.data_repository.is_configured():
		return result
	var seen: Dictionary = {}
	var catalog_by_kind: Dictionary = world._build_option_catalog(team).get("by_kind", {})
	for kind_value in kinds:
		var kind = String(kind_value)
		if seen.has(kind):
			continue
		seen[kind] = true
		var template: Dictionary = catalog_by_kind.get(kind, {})
		if not template.is_empty():
			result.append(world._present_build_option(template, team))
	world._sort_build_options(result)
	return result


func _build_option(world, team: int, kind: String) -> Dictionary:
	var template: Dictionary = world._build_option_catalog(team).get("by_kind", {}).get(kind, {})
	return {} if template.is_empty() else world._present_build_option(template, team)


func _build_option_catalog(world, team: int) -> Dictionary:
	var technology_revision = world.technology_system.revision(team)
	var cached: Dictionary = build_option_catalog_cache.get(team, {})
	if int(cached.get("technology_revision", -1)) == technology_revision:
		return cached
	var ordered: Array = []
	var by_kind: Dictionary = {}
	for kind_value in world.data_repository.archetype_aliases("building"):
		var kind = String(kind_value)
		var template = world._build_option_template(team, kind)
		if template.is_empty():
			continue
		ordered.append(template)
		by_kind[kind] = template
	world._sort_build_options(ordered)
	cached = {
		"technology_revision": technology_revision,
		"ordered": ordered,
		"by_kind": by_kind,
	}
	build_option_catalog_cache[team] = cached
	return cached


func _build_option_template(world, team: int, kind: String) -> Dictionary:
	if not world.data_repository.has_archetype(kind) or world.data_repository.category(kind) != "building":
		return {}
	var base_source_id = int(world.data_repository.identifiers(kind).get("source_unit_id", -1))
	if base_source_id < 0:
		return {}
	var resolved_source_id: int = int(world.technology_system.resolved_unit_id(team, base_source_id))
	var source: Dictionary = world.object_record_by_id(resolved_source_id, team)
	var interface: Dictionary = source.get("interface", {})
	if int(interface.get("button_id", -1)) <= 0:
		return {}
	var required_technology_id = int(world.data_repository.runtime_metadata(kind).get("required_technology_id", -1))
	if required_technology_id >= 0 and not world.technology_system.is_researched(team, required_technology_id):
		return {}
	if not world.is_object_available(team, base_source_id):
		return {}
	var cost = world.building_cost(kind, team)
	var option_footprint = Footprint.building(world.unit_stats(kind), Vector2.ZERO)
	var option_half_size = Vector2(option_footprint.get("half_size", Vector2.ONE))
	return {
		"kind": kind,
		"source_unit_id": resolved_source_id,
		"icon_id": world._build_option_icon_id(team, base_source_id, resolved_source_id, source),
		"button_id": int(interface.get("button_id", -1)),
		"cost": cost,
		"duration": float(source.get("production", {}).get("creation_time", world.unit_stats(kind).get("creation_time", 0.0))),
		"footprint_radius": maxf(option_half_size.x, option_half_size.y),
	}


func _build_option_icon_id(world, team: int, base_source_id: int, resolved_source_id: int, source: Dictionary) -> int:
	var icon_id = int(source.get("interface", {}).get("icon_id", -1))
	if icon_id < 0 or world.technology_system.current_age(team) == 100:
		return icon_id
	# Use the same DAT attribute-17 effects as a newly created building. This
	# also handles ages that only change the facet, without replacing its ID.
	var preview = {"team": team, "source_unit_id": resolved_source_id,
		"unit_lineage": [base_source_id, resolved_source_id], "components": {}}
	for effect in world.technology_system.persistent_entity_effects(team):
		if int(effect.get("attr_c", -1)) == 17 and world.technology_effect_matches_entity(preview, effect):
			var raw_type = int(effect.get("type_id", -1))
			var operator = raw_type % 10 if raw_type >= 10 and raw_type < 30 else raw_type
			if operator in [0, 4, 5]:
				preview["presentation_facing"] = maxi(0, roundi(world.apply_effect_operator(float(preview.get("presentation_facing", 0)), operator, float(effect.get("attr_d", 0.0)))))
	return icon_id + maxi(0, int(preview.get("presentation_facing", 0)))


func _present_build_option(world, template: Dictionary, team: int) -> Dictionary:
	var option = template.duplicate()
	var cost: Dictionary = template.get("cost", {})
	var reason = "" if world.can_afford_resource_cost(team, cost) else "insufficient_resources"
	option["cost"] = cost.duplicate()
	option["accepted"] = reason.is_empty()
	option["reason"] = reason
	return option


func _sort_build_options(world, options: Array) -> void:
	options.sort_custom(func(left, right):
		if int(left.get("button_id", 0)) != int(right.get("button_id", 0)):
			return int(left.get("button_id", 0)) < int(right.get("button_id", 0))
		return String(left.get("kind", "")) < String(right.get("kind", ""))
	)


func get_mixed_domain_build_sites(world, team: int, maximum_per_kind: int = 4) -> Dictionary:
	var result: Dictionary = {}
	if not world.units.any(func(unit): return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0 and world.entity_is_worker(unit)):
		return result
	var previous_failure = world.last_build_failure
	for option_value in world.get_build_options(team):
		var option: Dictionary = option_value
		if not bool(option.get("accepted", false)):
			continue
		var kind = String(option.get("kind", ""))
		var placement: Dictionary = world.data_repository.runtime_metadata(kind).get("placement", {})
		var required_domains: Array = placement.get("required_adjacent_domains", [])
		if "water" not in required_domains:
			continue
		var sites: Array = []
		for y in range(world.map_size.y):
			for x in range(world.map_size.x):
				var position = Vector2(x + 0.5, y + 0.5)
				if world.visibility_system.state_at_world(team, position) == FogOfWar.UNKNOWN:
					continue
				if world.can_place_foundation(team, kind, position):
					sites.append(position)
					if sites.size() >= maximum_per_kind:
						break
			if sites.size() >= maximum_per_kind:
				break
		if not sites.is_empty():
			result[kind] = sites
	world.last_build_failure = previous_failure
	return result


func get_local_build_sites(world, team: int, kinds: Array, maximum_per_kind: int = 4, search_radius: int = 12, preferred_sites: Dictionary = {}, strict_preferred_kinds: Array = [], minimum_structure_gap: float = 0.0) -> Dictionary:
	var result: Dictionary = {}
	if kinds.is_empty():
		return result
	var workers: Array = world.units.filter(func(unit):
		return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0 and world.entity_is_worker(unit) and String(unit.get("movement_domain", "land")) == "land"
	)
	workers.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	if workers.is_empty():
		return result
	if world.tick_pipeline.performance_probe != null:
		world.tick_pipeline.performance_probe.increment("ai.build_site_searches")
	# One synchronous query sees fixed unit positions. Index the exact five
	# occupancy probes once, instead of scanning every unit for every site.
	var mobile_occupied_cells = world._mobile_foundation_obstructions()
	var previous_failure = world.last_build_failure
	for kind_value in kinds:
		var kind = String(kind_value)
		var sites: Array = []
		var fallback_sites: Array = []
		var seen_cells: Dictionary = {}
		for preferred_value in preferred_sites.get(kind, []):
			var preferred_position = Vector2(preferred_value)
			var preferred_cell = Vector2i(floori(preferred_position.x), floori(preferred_position.y))
			if seen_cells.has(preferred_cell) or not world.navigation_grid.contains(preferred_cell):
				continue
			seen_cells[preferred_cell] = true
			if world.visibility_system.state_at_world(team, preferred_position) == FogOfWar.UNKNOWN:
				continue
			if world.building_placement_system.cached_map_supports_foundation(kind, preferred_position) and world.building_placement_system.known_foundation(team, kind, preferred_position) and world._can_place_foundation(team, kind, preferred_position, mobile_occupied_cells) and workers.any(func(worker): return world.worker_can_reach_foundation(worker, kind, preferred_position)):
				if world.foundation_preserves_structure_gap(team, kind, preferred_position, minimum_structure_gap):
					sites.append(preferred_position)
					if sites.size() >= maximum_per_kind:
						break
				elif fallback_sites.size() < maximum_per_kind:
					fallback_sites.append(preferred_position)
		if kind in strict_preferred_kinds:
			world._append_bounded_sites(sites, fallback_sites, maximum_per_kind)
			if not sites.is_empty():
				result[kind] = sites
			continue
		for worker_value in workers:
			var worker: Dictionary = worker_value
			var center = Vector2i(floori(float(worker.get("pos", Vector2.ZERO).x)), floori(float(worker.get("pos", Vector2.ZERO).y)))
			for radius in range(1, maxi(1, search_radius) + 1):
				for y in range(center.y - radius, center.y + radius + 1):
					# Preserve row-major ring order without visiting its interior.
					var columns: Array = range(center.x - radius, center.x + radius + 1) if absi(y - center.y) == radius else [center.x - radius, center.x + radius]
					for x in columns:
						var cell = Vector2i(x, y)
						if seen_cells.has(cell) or not world.navigation_grid.contains(cell):
							continue
						seen_cells[cell] = true
						var position = Vector2(cell) + Vector2(0.5, 0.5)
						if world.building_placement_system.cached_map_supports_foundation(kind, position) and world.building_placement_system.known_foundation(team, kind, position) and world._can_place_foundation(team, kind, position, mobile_occupied_cells) and world.worker_can_reach_foundation(worker, kind, position):
							if world.foundation_preserves_structure_gap(team, kind, position, minimum_structure_gap):
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
		world._append_bounded_sites(sites, fallback_sites, maximum_per_kind)
		if not sites.is_empty():
			result[kind] = sites
	world.last_build_failure = previous_failure
	return result


func get_cached_local_build_sites(world, team: int, kinds: Array, tick: int, maximum_age_ticks: int, maximum_per_kind: int = 4, search_radius: int = 12, preferred_sites: Dictionary = {}, strict_preferred_kinds: Array = [], minimum_structure_gap: float = 0.0) -> Dictionary:
	if not world.task_coordinator.is_enabled("ai_observation") or kinds.is_empty():
		return world._get_cached_local_build_sites_sequential(team, kinds, tick, maximum_age_ticks, maximum_per_kind, search_radius, preferred_sites, strict_preferred_kinds, minimum_structure_gap)
	if kinds.size() < 2:
		return world._get_cached_local_build_sites_sequential(team, kinds, tick, maximum_age_ticks, maximum_per_kind, search_radius, preferred_sites, strict_preferred_kinds, minimum_structure_gap)
	var dependencies = world._build_site_query_dependencies(team, search_radius, preferred_sites)
	var queries: Array = []
	var records: Array = []
	var result: Dictionary = {}
	var query_cache_hits = 0
	for kind_value in kinds:
		var kind = String(kind_value)
		var preferred: Dictionary = {kind: preferred_sites.get(kind, [])}
		var strict: Array = [kind] if kind in strict_preferred_kinds else []
		var cache_key = hash([team, kind, maximum_per_kind, search_radius, preferred, strict, minimum_structure_gap])
		var signature = hash([dependencies, world.can_afford_resource_cost(team, world.building_cost(kind, team))])
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
		return world._get_cached_local_build_sites_sequential(team, kinds, tick, maximum_age_ticks, maximum_per_kind, search_radius, preferred_sites, strict_preferred_kinds, minimum_structure_gap)
	if world.tick_pipeline.performance_probe != null:
		world.tick_pipeline.performance_probe.increment("ai.build_site_cache_hits", query_cache_hits)
	if queries.is_empty():
		return result
	var capture_started = Time.get_ticks_usec()
	var base = BuildSiteTask.capture(world, team, kinds)
	var placement = world.building_placement_system
	var static_cache_current: bool = placement.site_map_source == world.navigation_grid and placement.site_map_revision == world.navigation_grid.revision
	for query in queries:
		query["base"] = base
		query["static_cache"] = TaskData.copy(placement.site_map_cache.get(query["kind"], {})) if static_cache_current else {}
		query["static_profiles"] = {query["kind"]: TaskData.copy(placement.site_footprint_profiles[query["kind"]])} if static_cache_current and placement.site_footprint_profiles.has(query["kind"]) else {}
	if world.tick_pipeline.performance_probe != null:
		world.tick_pipeline.performance_probe.observe_microseconds("presentation.ai.capture.build_sites", Time.get_ticks_usec() - capture_started)
	var outputs = BuildSiteTask.calculate_queries(base, queries, world.task_coordinator, tick, world.pathfinder, world.tick_pipeline.performance_probe)
	if placement.site_map_source != world.navigation_grid or placement.site_map_revision != world.navigation_grid.revision:
		placement.invalidate_site_cache()
		placement.site_map_source = world.navigation_grid
		placement.site_map_revision = world.navigation_grid.revision
	for index in range(records.size()):
		var record: Dictionary = records[index]
		var output: Dictionary = outputs[index]
		var sites: Dictionary = output.get("sites", {})
		world._prune_local_build_site_cache(tick, maximum_age_ticks)
		world._store_local_build_site_cache(record["key"], {"tick": tick, "query_signature": record["signature"], "sites": TaskData.copy(sites)})
		placement.site_map_cache[record["kind"]] = output.get("static_cache", {})
		placement.site_footprint_profiles.merge(output.get("static_profiles", {}), true)
		if sites.has(record["kind"]):
			result[record["kind"]] = sites[record["kind"]].duplicate()
	# Cache hits and worker completion must not change dictionary insertion order.
	var ordered: Dictionary = {}
	for kind_value in kinds:
		var kind = String(kind_value)
		if result.has(kind):
			ordered[kind] = result[kind]
	return ordered

# Advisory placement requests capture immutable input at the AI source tick.
# Searches run inside the AI worker; the owner never waits for placement jobs.


func capture_ai_build_site_queries(world, team: int, kinds: Array, tick: int, maximum_age_ticks: int, maximum_per_kind: int, search_radius: int, preferred_sites: Dictionary, strict_preferred_kinds: Array, minimum_structure_gap: float) -> Array:
	var requests: Array = []
	if kinds.is_empty():
		return requests
	var dependencies = world._build_site_query_dependencies(team, search_radius, preferred_sites)
	var pending_kinds: Array = []
	for kind_value in kinds:
		var kind = String(kind_value)
		var preferred = {kind: preferred_sites.get(kind, [])}
		var strict: Array = [kind] if kind in strict_preferred_kinds else []
		var cache_key = hash([team, kind, maximum_per_kind, search_radius, preferred, strict, minimum_structure_gap])
		var signature = hash([dependencies, world.can_afford_resource_cost(team, world.building_cost(kind, team))])
		var cached: Dictionary = local_build_site_cache.get(cache_key, {})
		var request = {"kind": kind, "cache_key": cache_key, "signature": signature, "team": team, "dependency_scope": {"radius": search_radius, "preferred": preferred_sites}}
		if not cached.is_empty() and tick >= int(cached.get("tick", -1)) and tick - int(cached.get("tick", -1)) <= maxi(0, maximum_age_ticks) and int(cached.get("query_signature", -1)) == signature:
			request["cached_sites"] = cached.get("sites", {}).get(kind, []).duplicate()
		else:
			request["input"] = {"team": team, "kind": kind, "maximum": maximum_per_kind, "radius": search_radius, "preferred": preferred, "strict": strict, "gap": minimum_structure_gap}
			pending_kinds.append(kind)
		requests.append(request)
	if not pending_kinds.is_empty():
		var base: Dictionary = TaskData.capture_frozen(BuildSiteTask.capture(world, team, pending_kinds))
		if base.is_empty():
			push_error("AI build-site capture must be detached")
		for request in requests:
			if request.has("input"):
				request["input"]["base"] = base
	return requests


func commit_ai_build_site_queries(world, updates: Array, tick: int) -> void:
	var dependencies_by_scope: Dictionary = {}
	# A moved worker, changed occupancy, exploration or technology invalidates
	# a captured search. Build commands also validate the live site/worker.
	for update in updates:
		var team = int(update.get("team", 0))
		var kind = String(update.get("kind", ""))
		var scope: Dictionary = update["dependency_scope"]
		var scope_key = hash([team, scope["radius"], scope["preferred"]])
		if not dependencies_by_scope.has(scope_key):
			dependencies_by_scope[scope_key] = world._build_site_query_dependencies(team, int(scope["radius"]), scope["preferred"])
		var signature = hash([dependencies_by_scope[scope_key], world.can_afford_resource_cost(team, world.building_cost(kind, team))])
		if kind.is_empty() or signature != int(update.get("signature", -1)):
			continue
		world._store_local_build_site_cache(int(update["cache_key"]), {"tick": tick, "query_signature": signature, "sites": TaskData.copy(update.get("sites", {}))})
		world._prune_local_build_site_cache(tick, 1200)


func _get_cached_local_build_sites_sequential(world, team: int, kinds: Array, tick: int, maximum_age_ticks: int, maximum_per_kind: int = 4, search_radius: int = 12, preferred_sites: Dictionary = {}, strict_preferred_kinds: Array = [], minimum_structure_gap: float = 0.0) -> Dictionary:
	if kinds.is_empty():
		return {}
	# Retain each kind independently, including empty searches. Other priorities
	# entering/leaving the request must not discard an unchanged failed dock search.
	var dependencies = world._build_site_query_dependencies(team, search_radius, preferred_sites)
	var result: Dictionary = {}
	for kind_value in kinds:
		var kind = String(kind_value)
		var preferred: Dictionary = {kind: preferred_sites.get(kind, [])}
		var strict: Array = [kind] if kind in strict_preferred_kinds else []
		var cache_key = hash([team, kind, maximum_per_kind, search_radius, preferred, strict, minimum_structure_gap])
		var signature = hash([dependencies, world.can_afford_resource_cost(team, world.building_cost(kind, team))])
		var cached: Dictionary = local_build_site_cache.get(cache_key, {})
		var sites: Dictionary
		if not cached.is_empty() and tick >= int(cached.get("tick", -1)) and tick - int(cached.get("tick", -1)) <= maxi(0, maximum_age_ticks) and int(cached.get("query_signature", -1)) == signature:
			sites = cached.get("sites", {})
			if world.tick_pipeline.performance_probe != null:
				world.tick_pipeline.performance_probe.increment("ai.build_site_cache_hits")
		else:
			sites = world.get_local_build_sites(team, [kind], maximum_per_kind, search_radius, preferred, strict, minimum_structure_gap)
			world._prune_local_build_site_cache(tick, maximum_age_ticks)
			world._store_local_build_site_cache(cache_key, {"tick": tick, "query_signature": signature, "sites": sites.duplicate(true)})
		if sites.has(kind):
			result[kind] = sites[kind].duplicate()
	return result


func _build_site_query_dependencies(world, team: int, search_radius: int = 12, preferred_sites: Dictionary = {}) -> Array:
	var scope: Dictionary = world.entity_read_index.build_query_scope(world, team, search_radius, preferred_sites)
	var planner = world.movement_system.knowledge.planner(world, team)
	var key = hash([team, search_radius, preferred_sites])
	var cached: Dictionary = build_query_scopes.get(key, {})
	var local_revision = int(cached.get("local_revision", 0))
	var changes: Variant = planner.grid.changed_cells_since(int(cached.get("grid_revision", -1))) if not cached.is_empty() else null
	var changed: bool = changes == null or cached.get("workers") != scope["workers"] or cached.get("versions") != scope["versions"]
	if not changed:
		for cell in changes:
			var sector = Vector2i(floori(float(cell.x) / 4.0), floori(float(cell.y) / 4.0))
			if scope["keys"].has(sector):
				changed = true
				break
	if changed: local_revision += 1
	var record = {"local_revision": local_revision, "grid_revision": planner.grid.revision, "workers": scope["workers"], "versions": scope["versions"]}
	var bytes = var_to_bytes(record).size() + 64
	if build_query_scopes.has(key):
		build_query_scope_bytes -= int(build_query_scopes[key].get("bytes", 0))
		build_query_scopes.erase(key)
	if bytes <= MAX_BUILD_QUERY_SCOPE_BYTES:
		while not build_query_scopes.is_empty() and (build_query_scopes.size() >= 64 or build_query_scope_bytes + bytes > MAX_BUILD_QUERY_SCOPE_BYTES):
			var oldest: Variant = build_query_scopes.keys()[0]
			build_query_scope_bytes -= int(build_query_scopes[oldest].get("bytes", 0))
			build_query_scopes.erase(oldest)
		record["bytes"] = bytes
		build_query_scopes[key] = record
		build_query_scope_bytes += bytes
	else:
		local_revision = hash([scope["workers"], scope["versions"], planner.grid.revision])
	return [world.cache_epoch, team, key, local_revision, world.technology_system.revision(team), world.fog_of_war.exploration_revision_for_player(team)]


func _prune_local_build_site_cache(world, tick: int, maximum_age_ticks: int) -> void:
	for key in local_build_site_cache.keys():
		var cached: Dictionary = local_build_site_cache[key]
		var cached_tick = int(cached.get("tick", -1))
		if cached_tick > tick or tick - cached_tick > maxi(0, maximum_age_ticks):
			world._erase_local_build_site_cache(key)
	while local_build_site_cache.size() >= MAX_LOCAL_BUILD_SITE_CACHE_ENTRIES:
		var oldest_key = local_build_site_cache.keys()[0]
		var oldest_tick = int(local_build_site_cache[oldest_key].get("tick", -1))
		for key in local_build_site_cache:
			var cached_tick = int(local_build_site_cache[key].get("tick", -1))
			if cached_tick < oldest_tick:
				oldest_key = key
				oldest_tick = cached_tick
		world._erase_local_build_site_cache(oldest_key)


func _append_bounded_sites(world, sites: Array, fallback_sites: Array, maximum: int) -> void:
	for fallback_position in fallback_sites:
		if sites.size() >= maximum:
			break
		sites.append(fallback_position)


func _erase_local_build_site_cache(world, key: Variant) -> void:
	if local_build_site_cache.has(key):
		local_build_site_cache_bytes -= int(local_build_site_cache[key].get("bytes", 0))
		local_build_site_cache.erase(key)


func _store_local_build_site_cache(world, key: Variant, record: Dictionary) -> void:
	world._erase_local_build_site_cache(key)
	var bytes = var_to_bytes(record).size() + 64
	if bytes > MAX_LOCAL_BUILD_SITE_CACHE_BYTES: return
	while not local_build_site_cache.is_empty() and (local_build_site_cache.size() >= MAX_LOCAL_BUILD_SITE_CACHE_ENTRIES or local_build_site_cache_bytes + bytes > MAX_LOCAL_BUILD_SITE_CACHE_BYTES): world._erase_local_build_site_cache(local_build_site_cache.keys()[0])
	record["bytes"] = bytes
	local_build_site_cache[key] = record
	local_build_site_cache_bytes += bytes
