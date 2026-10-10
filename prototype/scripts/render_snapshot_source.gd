class_name RoRRenderSnapshotSource
extends RefCounted
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Publication := preload("res://scripts/presentation_publication.gd")
const OVERVIEW_REFRESH_TICKS := 4
var publication := Publication.new()
var previous: Dictionary = {}
var overview_tick := -1
var resource_revision := -1
var epoch := -1

func clear() -> void:
	publication.clear()
	previous = {}
	overview_tick = -1
	resource_revision = -1
	epoch = -1

func capture(world, tick: int, team: int, selected_ids: Array, bounds: Rect2, diagnostics: bool, coordinator, probe = null) -> Dictionary:
	if epoch != int(world.entity_changes.epoch):
		clear()
		epoch = int(world.entity_changes.epoch)
	var old_overview: Dictionary = previous.get("overview", {})
	var refresh := overview_tick < 0 or tick < overview_tick or tick - overview_tick >= OVERVIEW_REFRESH_TICKS
	var next_resource_revision := int(world.known_resource_revision(team))
	var refresh_resources := refresh and (old_overview.is_empty() or next_resource_revision != resource_revision)
	var options := {"include_navigation": false, "include_build_sites": false, "include_overview": refresh, "include_overview_resources": refresh_resources, "compact_render_entities": not diagnostics, "include_production_overview": true, "borrow_visible_render_entities": not diagnostics, "borrow_overview_entities": not diagnostics and not coordinator.is_enabled("presentation"), "entity_bounds": bounds, "always_include_entity_ids": selected_ids, "command_option_entity_ids": selected_ids}
	if probe != null:
		options["performance_probe"] = probe
		options["performance_prefix"] = "presentation.local.snapshot"
	var captured: Dictionary = Snapshot.with_queries(world, tick, team, options)
	var result: Dictionary = publication.publish(captured, selected_ids, coordinator) if not diagnostics else captured
	if refresh:
		overview_tick = tick
		if refresh_resources: resource_revision = next_resource_revision
		elif old_overview.has("resources"): result["overview"]["resources"] = old_overview["resources"]
	elif not old_overview.is_empty(): result["overview"] = old_overview
	result["overview_tick"] = overview_tick
	previous = {"overview": result["overview"]}
	return result
