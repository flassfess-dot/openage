class_name RoRAiPlanningTask
extends RefCounted

const AiPlayer := preload("res://scripts/ai_player.gd")
const Replay := preload("res://scripts/replay_system.gd")
const BuildSites := preload("res://scripts/build_site_task.gd")
const Data := preload("res://scripts/isolated_task_data.gd")

static func capture(ai, snapshot: Dictionary, tick: int) -> Dictionary:
	var frozen_snapshot := Data.capture_frozen(snapshot)
	if not snapshot.is_empty() and frozen_snapshot.is_empty():
		return {}
	var settings: Dictionary = Data.copy(ai.economic_policy)
	for field in ["enabled", "formation_name", "profile", "initial_attack_delay", "attack_separation", "minimum_attack_group_size", "maximum_attack_group_size", "enemy_response_distance", "use_workers_in_attack_groups"]:
		var key := String(field)
		if key == "formation_name":
			key = "formation"
		elif key in ["initial_attack_delay", "attack_separation"]:
			key += "_ticks"
		settings[key] = ai.get(field)
	settings["economic_interval_ticks"] = ai.economic_interval
	settings["military_interval_ticks"] = ai.military_interval
	return {"definition": {"team": ai.team, "ai": settings, "source_ai": Data.copy(ai.source_contract)}, "state": Data.copy(ai.canonical_state()), "snapshot": frozen_snapshot, "tick": tick}

# One private build planner per queued AI, retained between non-overlapping jobs.
# It owns mutable derived caches; no live world or previous DTO is mutated.
class Executor extends RefCounted:
	const MAX_REACHABLE_CELLS := 262144
	var static_audits := BuildSites.StaticAuditCache.new()
	var resource_index := AiPlayer.AdaptiveEconomy.Resources.new()
	var reachable_cache: Dictionary = {}
	var retained_reachable_cells := 0
	var last_metrics: Dictionary = {}
	var trace_navigation := "--trace-ai-navigation" in OS.get_cmdline_user_args()
	func performance_metrics() -> Dictionary:
		return last_metrics
	var planner
	var source_generation := -1
	var source_epoch := -1
	func reachable_lookup(navigation: Dictionary) -> Dictionary:
		var result: Dictionary = {}
		for domain in ["land", "water"]:
			var points: Array = navigation.get("reachable", {}).get(domain, [])
			var retained: Dictionary = reachable_cache.get(domain, {})
			if not retained.is_empty() and is_same(retained["source"], points):
				result[domain] = retained["cells"]
				continue
			if not retained.is_empty(): retained_reachable_cells -= retained["cells"].size()
			reachable_cache.erase(domain)
			if points.is_empty(): continue
			var calculated := AiPlayer.EconomicPlanner._reachable_cells_by_domain({"reachable":{domain:points}})
			var cells: Dictionary = calculated[domain]
			result[domain] = cells
			# Only typed, readonly value arrays provide an immutable identity.
			# The two current domains share a hard cell cap per private executor.
			if points.is_read_only() and points.is_typed() and points.get_typed_builtin() in [TYPE_VECTOR2,TYPE_VECTOR2I] and cells.size() <= MAX_REACHABLE_CELLS:
				if retained_reachable_cells + cells.size() > MAX_REACHABLE_CELLS:
					reachable_cache.clear()
					retained_reachable_cells = 0
				cells.make_read_only()
				reachable_cache[domain] = {"source":points,"cells":cells}
				retained_reachable_cells += cells.size()
		return result
	func build_planner(topology: Dictionary):
		static_audits.begin(topology)
		if not topology.has("cell_pages"):
			return BuildSites.Pathfinder.new(BuildSites.NavigationData.create_grid(topology))
		if planner == null or source_generation != int(topology["source_generation"]) or source_epoch != int(topology["epoch"]):
			planner = BuildSites.Pathfinder.new(BuildSites.NavigationData.create_grid(topology))
			source_generation = int(topology["source_generation"])
			source_epoch = int(topology["epoch"])
		else:
			BuildSites.NavigationData.update_chunked_grid(planner.grid, topology)
		return planner
	func run(input: Dictionary) -> Dictionary:
		return RoRAiPlanningTask.run(input, self)

static func run(input: Dictionary, executor: Variant = null) -> Dictionary:
	var phase_started := Time.get_ticks_usec()
	var metrics := {"placement": 0, "placement_context": 0, "placement_search": 0, "demand": 0}
	var navigation_probe: Variant = BuildSites.Pathfinder.PerformanceProbe.new(2048) if executor != null and executor.trace_navigation else null
	var ai := AiPlayer.new(input["definition"])
	if executor != null: ai.economic_resource_index = executor.resource_index
	if not ai.restore_state(input["state"]):
		return {"valid": false}
	metrics["restore"] = Time.get_ticks_usec() - phase_started
	var snapshot: Dictionary = input["snapshot"]
	var cache_updates: Array = []
	if snapshot.has("build_site_queries"):
		snapshot = snapshot.duplicate()
		var sites: Dictionary = {}
		var private_planner = null
		phase_started = Time.get_ticks_usec()
		var queries := _build_site_queries(ai, snapshot)
		metrics["demand"] = Time.get_ticks_usec() - phase_started
		for query in queries:
			var kind := String(query["kind"])
			var candidates: Array = query.get("cached_sites", [])
			if query.has("input"):
				phase_started = Time.get_ticks_usec()
				# Run directly in this worker. Nested pool submissions followed by
				# a wait would turn a saturated worker pool into a deadlock.
				if private_planner == null:
					var base: Dictionary = query["input"]["base"]
					private_planner = executor.build_planner(base["navigation"]) if executor != null else BuildSites.Pathfinder.new(BuildSites.NavigationData.create_grid(base["navigation"]))
					if navigation_probe != null: private_planner.set_performance_probe(navigation_probe)
				metrics["placement_context"] = int(metrics["placement_context"])+Time.get_ticks_usec()-phase_started
				var search_started := Time.get_ticks_usec()
				var output: Dictionary = BuildSites.run(query["input"], private_planner, executor.static_audits if executor != null else null)
				candidates = output.get("sites", {}).get(kind, [])
				metrics["placement_search"] = int(metrics["placement_search"])+Time.get_ticks_usec()-search_started
				metrics["placement"] = int(metrics["placement"])+Time.get_ticks_usec()-phase_started
				cache_updates.append({"team": query["team"], "kind": kind, "cache_key": query["cache_key"], "signature": query["signature"], "sites": output.get("sites", {}), "dependency_scope": query.get("dependency_scope", {})})
			if not candidates.is_empty():
				sites[kind] = candidates
				if bool(snapshot.get("build_site_candidate_filter", false)) and ai._has_usable_build_site(kind, candidates, snapshot.get("units", []), snapshot.get("buildings", [])):
					break
		snapshot["build_sites"] = sites
	phase_started = Time.get_ticks_usec()
	if executor != null:
		snapshot = snapshot.duplicate()
		snapshot["_economy_reachable_cells"] = executor.reachable_lookup(snapshot.get("navigation", {}))
	metrics["reachability"] = Time.get_ticks_usec() - phase_started
	phase_started = Time.get_ticks_usec()
	var commands := ai.collect_commands(snapshot, int(input["tick"]))
	metrics["planning"] = Time.get_ticks_usec() - phase_started
	for stage in ai.planning_metrics: metrics["plan." + stage] = ai.planning_metrics[stage]
	phase_started = Time.get_ticks_usec()
	var proposals: Array = []
	var metadata: Array = []
	var codec := Replay.new()
	for command in commands:
		metadata.append(command.params.get("_ai_feedback", {}).duplicate(true))
		proposals.append({"tick": int(command.tick), "type": String(command.command_type()), "unit_ids": command.unit_ids.duplicate(), "params": codec.encode_variant(command.params, false)})
	var result := {"valid": true, "commands": proposals, "command_metadata": metadata, "state": ai.canonical_state(), "build_site_cache_updates": cache_updates}
	metrics["encoding"] = Time.get_ticks_usec() - phase_started
	if navigation_probe != null:
		for key in navigation_probe.samples_by_metric:
			var total := 0
			for sample in navigation_probe.samples_by_metric[key]: total += int(sample)
			metrics["nav."+key] = total
		if executor.planner != null: executor.planner.set_performance_probe(null)
	if executor != null: executor.last_metrics = metrics
	return result

# A private AI instance has the same state as the source-boundary filter. Only
# useful kinds reach placement; speculative envelopes never run extra searches.
static func _build_site_queries(ai, snapshot: Dictionary) -> Array:
	var queries: Array = snapshot["build_site_queries"]
	if not bool(snapshot.get("build_site_filter_in_worker", false)):
		return queries
	var kinds: Array = []
	var by_kind: Dictionary = {}
	for query in queries:
		kinds.append(query["kind"])
		by_kind[query["kind"]] = query
	if ai.profile == "source_campaign_v1":
		kinds = ai._source_construction_site_kinds(kinds, snapshot["units"], snapshot["buildings"], snapshot["player_state"])
	else:
		kinds = ai._construction_site_kinds(kinds, snapshot["units"], snapshot["buildings"], snapshot["player_state"], snapshot.get("navigation", {}), snapshot)
	var selected: Array = []
	for kind in kinds:
		if by_kind.has(kind): selected.append(by_kind[kind])
	return selected

static func decode_commands(output: Dictionary) -> Array:
	var codec := Replay.new()
	var commands: Array = []
	for record in output.get("commands", []):
		var command = codec.command_from_record(record)
		if command == null:
			return []
		var metadata: Array = output.get("command_metadata", [])
		if commands.size() < metadata.size() and not metadata[commands.size()].is_empty(): command.params["_ai_feedback"] = metadata[commands.size()].duplicate(true)
		commands.append(command)
	return commands
