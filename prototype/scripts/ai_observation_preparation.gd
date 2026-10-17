class_name RoRAiObservationPreparation
extends RefCounted
const Planning := preload("res://scripts/ai_planning_task.gd")
const Queries := preload("res://scripts/simulation_observation_queries.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const MAX_CAPTURES := 8
const ACTORS_PER_PORTION := 96
const PRODUCERS_PER_PORTION := 1
const CAPTURE_BUDGET_USEC := 7000
var captures: Dictionary = {}

func clear() -> void:
	for pending in captures.values():
		var world: Variant = pending["world"].get_ref()
		if world != null: world.release_read_generation(pending["token"])
	captures.clear()

func capture(world, store, ai, source_tick: int, apply_tick: int, probe: Variant = null, budget_usec: int = CAPTURE_BUDGET_USEC) -> Dictionary:
	var team := int(ai.team)
	var pending: Dictionary = captures.get(team, {})
	if pending.is_empty():
		assert(captures.size() < MAX_CAPTURES)
		var initial_options: Dictionary = ai.presentation_options()
		initial_options["defer_build_sites"] = true
		initial_options["_ai_profile_cache"] = {}
		if probe != null:
			initial_options["performance_probe"] = probe
			initial_options["performance_prefix"] = "presentation.ai.observation"
		pending = {"world": weakref(world), "token": world.pin_read_generation(), "source_tick": source_tick, "apply_tick": apply_tick, "options": initial_options, "phase": "actors", "projection": {}, "snapshot": {}, "unit_cursor": 0, "building_cursor": 0, "units": [], "buildings": [], "owner_us": 0, "prepare_us": 0, "snapshot_us": 0}
		captures[team] = pending
	if int(pending["source_tick"]) != source_tick or int(pending["apply_tick"]) != apply_tick or pending["world"].get_ref() != world or int(pending["token"]["epoch"]) != int(world.entity_changes.epoch):
		clear()
		return {}
	var frame_started := Time.get_ticks_usec()
	# Quotas bound individual operations; elapsed time bounds the whole call.
	# Cheap portions continue on the same pinned generation in this frame.
	while true:
		var started := Time.get_ticks_usec() if probe != null else 0
		var options: Dictionary = pending["options"]
		var phase := String(pending["phase"])
		match phase:
			"actors":
				if store.prepare_projection(world, team, pending["projection"], ACTORS_PER_PORTION): pending["phase"] = "navigation"
			"navigation":
				if not bool(options.get("include_navigation", true)) or world.ai_navigation_knowledge.prepare_snapshot(world, world.get_fog_of_war(), team): pending["phase"] = "resources"
			"resources":
				if world.prepare_known_ai_resource_snapshot(team): pending["phase"] = "facts"
			"facts":
				pending["snapshot"] = store.observe(world, source_tick, team, options)
				pending.erase("projection")
				pending["phase"] = "commands"
			"commands":
				var snapshot: Dictionary = pending["snapshot"]
				var unit_finish := mini(snapshot["units"].size(), int(pending["unit_cursor"]) + ACTORS_PER_PORTION)
				var building_finish := mini(snapshot["buildings"].size(), int(pending["building_cursor"]) + PRODUCERS_PER_PORTION)
				var portion: Dictionary = snapshot.duplicate()
				portion["units"] = snapshot["units"].slice(int(pending["unit_cursor"]), unit_finish)
				portion["buildings"] = snapshot["buildings"].slice(int(pending["building_cursor"]), building_finish)
				var portion_options: Dictionary = options.duplicate()
				portion_options["skip_spatial_queries"] = true
				# Foundation recovery depends on all workers from the pinned facts.
				portion_options["foundation_units"] = snapshot["units"]
				var decorated: Dictionary = Queries.enrich(world, portion, portion_options)
				# Validate/detach this small portion in the existing native kernel.
				# Recursively freezing every actor in GDScript repeated thousands
				# of registry probes on an otherwise already immutable read model.
				var frozen := Data.capture_frozen({"units": decorated["units"], "buildings": decorated["buildings"]})
				if frozen.is_empty():
					clear()
					return {}
				pending["units"].append_array(frozen["units"])
				pending["buildings"].append_array(frozen["buildings"])
				pending["unit_cursor"] = unit_finish
				pending["building_cursor"] = building_finish
				if unit_finish == snapshot["units"].size() and building_finish == snapshot["buildings"].size():
					pending["units"].make_read_only()
					pending["buildings"].make_read_only()
					Data._retain_immutable(pending["units"])
					Data._retain_immutable(pending["buildings"])
					snapshot["units"] = pending["units"]
					snapshot["buildings"] = pending["buildings"]
					pending["phase"] = "queries"
			"queries":
				var query_options: Dictionary = options.duplicate()
				query_options["command_option_entity_ids"] = []
				query_options["defer_site_capture"] = true
				pending["snapshot"] = Queries.enrich(world, pending["snapshot"], query_options)
				pending["phase"] = "sites"
			"sites":
				var snapshot: Dictionary = pending["snapshot"]
				if snapshot.has("_pending_build_site_kinds"):
					var kinds: Array = snapshot["_pending_build_site_kinds"]
					snapshot.erase("_pending_build_site_kinds")
					snapshot["build_site_queries"] = Queries.capture_deferred_sites(world, snapshot, kinds, options)
				pending["phase"] = "publish"
			"publish":
				var knowledge: Dictionary = pending["snapshot"]
				# These exact roots were validated by our resource/navigation
				# producers or by the portion capture above. They stay immutable
				# while this read generation is pinned, even if the LRU evicts them.
				for key in ["units", "buildings", "resources", "navigation"]:
					var publication: Variant = knowledge.get(key)
					if (publication is Array or publication is Dictionary) and publication.is_read_only(): Data._retain_immutable(publication)
				var capture_started := Time.get_ticks_usec() if probe != null else 0
				var captured: Dictionary = Planning.capture(ai, knowledge, apply_tick)
				world.release_read_generation(pending["token"])
				captures.erase(team)
				if probe != null:
					var elapsed := Time.get_ticks_usec() - started
					var capture_us := Time.get_ticks_usec() - capture_started
					probe.observe_microseconds("presentation.ai.portion", elapsed)
					probe.observe_microseconds("presentation.ai.phase.publish", elapsed)
					probe.observe_microseconds("presentation.ai.prepare", int(pending["prepare_us"]))
					probe.observe_microseconds("presentation.ai.snapshot", int(pending["snapshot_us"]) + elapsed - capture_us)
					probe.observe_microseconds("presentation.ai.capture", capture_us)
					probe.observe_microseconds("presentation.ai.owner_total", int(pending["owner_us"]) + elapsed)
					probe.observe_microseconds("presentation.ai.capture_frame", Time.get_ticks_usec() - frame_started)
				return captured
		if probe != null:
			var elapsed := Time.get_ticks_usec() - started
			pending["owner_us"] = int(pending["owner_us"]) + elapsed
			var metric := "prepare_us" if phase in ["actors", "navigation", "resources"] else "snapshot_us"
			pending[metric] = int(pending[metric]) + elapsed
			probe.observe_microseconds("presentation.ai.portion", elapsed)
			probe.observe_microseconds("presentation.ai.phase." + phase, elapsed)
			probe.increment("ai.capture.portions")
		if Time.get_ticks_usec() - frame_started >= maxi(1, budget_usec):
			if probe != null:
				probe.observe_microseconds("presentation.ai.capture_frame", Time.get_ticks_usec() - frame_started)
			return {"pending": true}
	return {}
