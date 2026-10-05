class_name RoRSimulationObservationQueries
extends RefCounted

# Explicit owner-thread queries. Snapshot projection never calls these services.
# Only IDs already present in an observer's legal read model may be enriched.
# Command/control rows are copied before decoration, so retained rows and live
# authoritative dictionaries are never modified by query results.
static func enrich(world, snapshot: Dictionary, options: Dictionary = {}) -> Dictionary:
	var result := snapshot.duplicate()
	var team := int(snapshot.get("observer_team", 0))
	if team <= 0:
		return result
	var tick := int(snapshot.get("tick", 0))
	var probe: Variant = options.get("performance_probe")
	var prefix := String(options.get("performance_prefix", "observation")) + ".queries"
	var started := Time.get_ticks_usec() if probe != null else 0
	var requested_kinds: Array = options.get("requested_build_site_kinds", [])
	var requested_options: Array = []
	var available_kinds: Array = []
	if not requested_kinds.is_empty():
		var build_options: Array = world.get_build_options_for_kinds(team, requested_kinds) if world.has_method("get_build_options_for_kinds") else world.get_build_options(team)
		for option in build_options:
			var kind := String(option.get("kind", ""))
			if kind in requested_kinds:
				requested_options.append(option)
				if bool(option.get("accepted", false)):
					available_kinds.append(kind)
	var restricted := options.has("command_option_entity_ids")
	var command_ids: Dictionary = {}
	for id in options.get("command_option_entity_ids", []):
		command_ids[int(id)] = true
	var replacements: Dictionary = {}
	var units: Array = []
	var worker_options: Array = []
	var worker_options_ready := false
	for row_value in snapshot.get("units", []):
		var row: Dictionary = row_value
		if int(row.get("team", 0)) == team and (not restricted or command_ids.has(int(row.get("id", -1)))) and world.entity_is_worker(row):
			row = row.duplicate()
			if not requested_options.is_empty():
				row["command_options"] = {"build": requested_options}
			elif bool(options.get("include_worker_command_options", true)):
				if not worker_options_ready:
					worker_options = world.get_build_options(team)
					worker_options_ready = true
				row["command_options"] = {"build": worker_options}
			replacements[int(row.get("id", -1))] = row
		units.append(row)
	result["units"] = units
	var buildings: Array = []
	for row_value in snapshot.get("buildings", []):
		var row: Dictionary = row_value
		if int(row.get("team", 0)) == team and not bool(row.get("last_known", false)) and (not restricted or command_ids.has(int(row.get("id", -1)))):
			var source: Variant = world.find_building(int(row.get("id", -1)))
			if source != null:
				row = row.duplicate()
				row["builder_count"] = source.get("builders", {}).size()
				if String(source.get("state", "complete")) == "foundation" and (not bool(options.get("recover_abandoned_foundations_only", false)) or foundation_needs_recovery(source, units)):
					row["reachable_builder_ids"] = world.reachable_builder_ids(source)
				if bool(options.get("requested_production_only", false)):
					row["command_options"] = requested_production_options(world, source, team, options.get("production_requests", []))
				elif bool(options.get("economic_production_options_only", false)):
					row["command_options"] = economic_production_options(world, source, team)
				else:
					row["command_options"] = {
						"train": world.get_unit_production_options(int(source.get("id", -1)), team),
						"research": world.get_research_options(int(source.get("id", -1)), team),
					}
				var technologies: Array = options.get("planning_technology_ids", [])
				if not technologies.is_empty():
					append_planning_research_options(world, row, source, team, technologies)
				replacements[int(row.get("id", -1))] = row
		buildings.append(row)
	result["buildings"] = buildings
	for category in ["control_units", "control_buildings"]:
		if snapshot.has(category):
			var controls: Array = []
			for row in snapshot[category]:
				controls.append(replacements.get(int(row.get("id", -1)), row))
			result[category] = controls
	_observe(probe, prefix + ".commands", started)
	started = Time.get_ticks_usec() if probe != null else 0
	var navigation: Dictionary = world.ai_navigation_knowledge.snapshot(world, world.get_fog_of_war(), team, probe) if bool(options.get("include_navigation", true)) else {}
	result["navigation"] = navigation
	_observe(probe, prefix + ".navigation", started)
	started = Time.get_ticks_usec() if probe != null else 0
	var site_filter: Callable = options.get("build_site_filter", Callable())
	if site_filter.is_valid() and not available_kinds.is_empty():
		if bool(options.get("build_site_filter_navigation", false)):
			available_kinds = site_filter.call(available_kinds, units, buildings, result.get("player_state", {}), navigation)
		else:
			available_kinds = site_filter.call(available_kinds, units, buildings, result.get("player_state", {}))
	_observe(probe, prefix + ".demand_filter", started)
	started = Time.get_ticks_usec() if probe != null else 0
	var sites: Dictionary = {}
	if not requested_kinds.is_empty():
		sites = requested_build_sites(world, tick, team, available_kinds, options, units, buildings)
	elif bool(options.get("include_build_sites", true)):
		sites = world.get_mixed_domain_build_sites(team)
	result["build_sites"] = sites
	_observe(probe, prefix + ".build_sites", started)
	return result


static func _observe(probe, metric: String, started: int) -> void:
	if probe != null:
		probe.observe_microseconds(metric, Time.get_ticks_usec() - started)


static func requested_production_options(world, building: Dictionary, team: int, requests: Array) -> Dictionary:
	var result := {"train": [], "research": []}
	var lineage: Array = building.get("unit_lineage", [int(building.get("source_unit_id", -1))])
	var building_id := int(building.get("id", -1))
	var seen_units: Dictionary = {}
	var seen_technologies: Dictionary = {}
	for request_value in requests:
		var request: Dictionary = request_value
		if not lineage.has(int(request.get("producer_source_unit_id", -1))):
			continue
		if String(request.get("type", "")) == "unit":
			var kind := String(request.get("runtime_alias", ""))
			if not kind.is_empty() and not seen_units.has(kind):
				result["train"].append(world.get_unit_production_availability(building_id, team, kind))
				seen_units[kind] = true
		elif String(request.get("type", "")) == "technology":
			var technology_id := int(request.get("source_id", -1))
			if technology_id >= 0 and not seen_technologies.has(technology_id):
				result["research"].append(world.get_research_availability(building_id, team, technology_id))
				seen_technologies[technology_id] = true
	return result


static func append_planning_research_options(world, presentation_building: Dictionary, source_building: Dictionary, team: int, technology_ids: Array) -> void:
	var command_options: Dictionary = presentation_building.get("command_options", {})
	var research_options: Array = command_options.get("research", [])
	var known: Dictionary = {}
	for option_value in research_options:
		known[int(option_value.get("technology_id", -1))] = true
	for technology_id_value in technology_ids:
		var technology_id := int(technology_id_value)
		if technology_id <= 0 or known.has(technology_id):
			continue
		var option: Dictionary = world.get_research_availability(int(source_building.get("id", -1)), team, technology_id)
		if String(option.get("reason", "")) in ["wrong_research_location", "invalid_research_building", "technology_disabled", "already_researched", "already_researching"]:
			continue
		research_options.append(option)
		known[technology_id] = true
	command_options["research"] = research_options
	presentation_building["command_options"] = command_options


static func foundation_needs_recovery(building: Dictionary, units: Array) -> bool:
	if not building.get("builders", {}).is_empty():
		return false
	var building_id := int(building.get("id", -1))
	var team := int(building.get("team", 0))
	return not units.any(func(unit): return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0 and String(unit.get("task", "")) == "build" and int(unit.get("target_building_id", -1)) == building_id)


static func economic_production_options(world, building: Dictionary, team: int) -> Dictionary:
	var empty := {"train": [], "research": []}
	if String(building.get("state", "complete")) != "complete" or not world.data_repository.is_configured():
		return empty
	var queue: Array = building.get("production_queue", [])
	if queue.size() >= 2 or (not queue.is_empty() and (String(queue[0].get("order_type", "unit")) != "unit" or String(queue[0].get("status", "")) == "blocked_population")):
		return empty
	var building_id := int(building.get("id", -1))
	if not queue.is_empty():
		# The economic planner can only extend a unit queue with the same kind.
		var option: Dictionary = world.get_unit_production_availability(building_id, team, String(queue[0].get("kind", "")))
		return {"train": [option] if String(option.get("reason", "")) not in ["unit_replaced", "unit_unavailable"] else [], "research": []}
	return {"train": world.get_unit_production_options(building_id, team), "research": world.get_research_options(building_id, team)}


static func requested_build_sites(world, tick: int, team: int, kinds: Array, options: Dictionary, units: Array = [], buildings: Array = []) -> Dictionary:
	if kinds.is_empty():
		return {}
	var maximum := maxi(1, int(options.get("maximum_build_sites_per_kind", 4)))
	var radius := maxi(1, int(options.get("build_site_search_radius", 12)))
	var age := maxi(0, int(options.get("build_site_cache_ticks", 0)))
	var preferred: Dictionary = options.get("preferred_build_sites", {})
	var strict: Array = options.get("strict_preferred_build_site_kinds", [])
	var gap := maxf(0.0, float(options.get("minimum_structure_gap", 0.0)))
	var candidate_filter: Callable = options.get("build_site_candidate_filter", Callable())
	if not candidate_filter.is_valid():
		return world.get_cached_local_build_sites(team, kinds, tick, age, maximum, radius, preferred, strict, gap) if age > 0 and world.has_method("get_cached_local_build_sites") else world.get_local_build_sites(team, kinds, maximum, radius, preferred, strict, gap)
	var result: Dictionary = {}
	for kind_value in kinds:
		var kind := String(kind_value)
		var sites: Dictionary = world.get_cached_local_build_sites(team, [kind], tick, age, maximum, radius, preferred, strict, gap) if age > 0 and world.has_method("get_cached_local_build_sites") else world.get_local_build_sites(team, [kind], maximum, radius, preferred, strict, gap)
		if sites.has(kind):
			result[kind] = sites[kind]
			if bool(candidate_filter.call(kind, sites[kind], units, buildings)):
				break
	return result
