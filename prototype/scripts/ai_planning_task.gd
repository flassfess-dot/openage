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
	var planner
	var source_generation := -1
	var source_epoch := -1
	func build_planner(topology: Dictionary):
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
	var ai := AiPlayer.new(input["definition"])
	if not ai.restore_state(input["state"]):
		return {"valid": false}
	var snapshot: Dictionary = input["snapshot"]
	var cache_updates: Array = []
	if snapshot.has("build_site_queries"):
		snapshot = snapshot.duplicate()
		var sites: Dictionary = {}
		var private_planner = null
		for query in snapshot["build_site_queries"]:
			var kind := String(query["kind"])
			var candidates: Array = query.get("cached_sites", [])
			if query.has("input"):
				# Run directly in this worker. Nested pool submissions followed by
				# a wait would turn a saturated worker pool into a deadlock.
				if private_planner == null:
					var base: Dictionary = query["input"]["base"]
					private_planner = executor.build_planner(base["navigation"]) if executor != null else BuildSites.Pathfinder.new(BuildSites.NavigationData.create_grid(base["navigation"]))
				var output: Dictionary = BuildSites.run(query["input"], private_planner)
				candidates = output.get("sites", {}).get(kind, [])
				cache_updates.append({"team": query["team"], "kind": kind, "cache_key": query["cache_key"], "signature": query["signature"], "sites": output.get("sites", {}), "dependency_scope": query.get("dependency_scope", {})})
			if not candidates.is_empty():
				sites[kind] = candidates
				if bool(snapshot.get("build_site_candidate_filter", false)) and ai._has_usable_build_site(kind, candidates, snapshot.get("units", []), snapshot.get("buildings", [])):
					break
		snapshot["build_sites"] = sites
	var commands := ai.collect_commands(snapshot, int(input["tick"]))
	var proposals: Array = []
	var metadata: Array = []
	var codec := Replay.new()
	for command in commands:
		metadata.append(command.params.get("_ai_feedback", {}).duplicate(true))
		proposals.append({"tick": int(command.tick), "type": String(command.command_type()), "unit_ids": command.unit_ids.duplicate(), "params": codec.encode_variant(command.params, false)})
	return {"valid": true, "commands": proposals, "command_metadata": metadata, "state": ai.canonical_state(), "build_site_cache_updates": cache_updates}

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
