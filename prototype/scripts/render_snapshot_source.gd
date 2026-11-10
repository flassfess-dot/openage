class_name RoRRenderSnapshotSource
extends RefCounted
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Publication := preload("res://scripts/presentation_publication.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const RetainedControls := preload("res://scripts/retained_control_projection.gd")
var controls_projection := RetainedControls.new()
const OVERVIEW_REFRESH_TICKS := 4
var publication := Publication.new()
var previous: Dictionary = {}
var overview_tick := -1
var resource_revision := -1
var epoch := -1
var published_overview: Dictionary = {}
var scene_rule_signature: Array = []
var scene_rules: Dictionary = {}
var scene_worker_menu: Dictionary = {}
var scene_worker_price_bounds: Dictionary = {}
var scene_menu_counters: Dictionary = {}
var profile_capture_identity := "--profile-capture-identity-alternatives" in OS.get_cmdline_user_args()
var capture_identity_sequence := 0

func clear() -> void:
	publication.clear()
	previous = {}
	overview_tick = -1
	resource_revision = -1
	epoch = -1
	published_overview = {}
	controls_projection.clear()
	scene_rule_signature = []
	scene_rules = {}
	scene_worker_menu = {}
	scene_worker_price_bounds.clear()
	scene_menu_counters.clear()


func _retained_scene_rules(world, team: int) -> Dictionary:
	# Availability rules use these same catalog/technology versions as the
	# production/build-option services. Per-building validity and queue shape
	# remain in the existing rule key. Stocks are repriced on every capture.
	var signature := [world.get_instance_id(), world.entity_changes.epoch, world.cache_epoch, world.data_repository.get_instance_id(), world.data_repository.revision, world.technology_system.revision(team), team, world.civilization_by_team.get(team, 13), world.full_tech_tree_enabled]
	if signature != scene_rule_signature:
		scene_menu_counters["schema_rebuilds"] = int(scene_menu_counters.get("schema_rebuilds", 0)) + 1
		scene_rule_signature = signature
		scene_rules = {"entries":{},"sizes":{},"bytes":0}
		scene_worker_menu = {}
		scene_worker_price_bounds.clear()
	return scene_rules


func _scene_worker_commands(world, team: int) -> Dictionary:
	if scene_worker_menu.is_empty():
		scene_menu_counters["worker_menu_captures"] = int(scene_menu_counters.get("worker_menu_captures", 0)) + 1
		scene_worker_menu = Data.capture_frozen({"build":world.get_build_options(team)})
	else:
		scene_menu_counters["worker_menu_reprices"] = int(scene_menu_counters.get("worker_menu_reprices", 0)) + 1
		scene_worker_menu = preload("res://scripts/simulation_observation_queries.gd").price_command_rules(world, team, scene_worker_menu, ["build"], scene_worker_price_bounds)
		scene_menu_counters["worker_price_bounds_hits"] = int(scene_worker_price_bounds.get("hits", 0))
		scene_menu_counters["worker_price_bounds_captures"] = int(scene_worker_price_bounds.get("captures", 0))
	return scene_worker_menu

func capture(world, tick: int, team: int, selected_ids: Array, bounds: Rect2, diagnostics: bool, coordinator, probe = null, full_scene: bool = false) -> Dictionary:
	var capture_started := Time.get_ticks_usec() if probe != null else 0
	var identity_override := -1
	if full_scene and profile_capture_identity:
		capture_identity_sequence += 1
		identity_override = int(((capture_identity_sequence * 1103515245 + 12345) & 0xffff) >= 32768)
	if epoch != int(world.entity_changes.epoch):
		clear()
		epoch = int(world.entity_changes.epoch)
	var old_overview: Dictionary = previous.get("overview", {})
	var refresh := overview_tick < 0 or tick < overview_tick or tick - overview_tick >= OVERVIEW_REFRESH_TICKS
	var next_resource_revision := int(world.known_resource_revision(team))
	var refresh_resources := refresh and (old_overview.is_empty() or next_resource_revision != resource_revision)
	var camera_bounds := bounds
	if full_scene:
		controls_projection.begin(world, tick)
		bounds = Rect2(Vector2.ZERO, Vector2(world.map_size))
	var options := {"include_navigation": false, "include_build_sites": false, "include_overview": refresh, "include_overview_resources": refresh_resources, "compact_render_entities": not diagnostics, "include_production_overview": true, "borrow_visible_render_entities": not diagnostics, "borrow_sampled_building_memory": not diagnostics, "borrow_overview_entities": not diagnostics and not coordinator.is_enabled("presentation"), "entity_bounds": bounds, "always_include_entity_ids": selected_ids, "command_option_entity_ids": selected_ids}
	options["full_render_scene"] = full_scene
	# UI availability does not need AI reachability/assignment queries.
	if full_scene: options["skip_builder_reachability_queries"] = true
	if full_scene: options["_ai_command_options_cache"] = {}
	if full_scene: options["_scene_rule_counters"] = scene_menu_counters
	if full_scene:
		# The projection collects living, legally observable actors during its
		# normal traversal. Command enrichment uses exactly that same set.
		options["_scene_control_ids"] = {}
		options["_ai_command_rule_cache"] = _retained_scene_rules(world, team)
		options["_scene_worker_publication"] = {"commands":_scene_worker_commands(world, team)}
	if full_scene and controls_projection.supported: options["_scene_controls"] = controls_projection
	if full_scene and controls_projection.supported: options["_scene_unit_metadata"] = true
	if full_scene and controls_projection.supported and camera_bounds.has_area(): options["_scene_clocks"] = {"bounds":camera_bounds, "samples":{}}
	if full_scene and controls_projection.certified: options["_scene_worker_publication"]["publish_rows"] = true
	if full_scene and controls_projection.building_rows_native: options["_scene_building_fields"] = {}
	if probe != null:
		options["performance_probe"] = probe
		options["performance_prefix"] = "presentation.local.snapshot"
	var captured: Dictionary = Snapshot.with_queries(world, tick, team, options)
	var result: Dictionary = publication.publish(captured, selected_ids, coordinator) if not diagnostics else captured
	if options.has("_scene_clocks"):
		var clocks: Dictionary = options["_scene_clocks"]["samples"]
		if not clocks.is_empty():
			clocks.make_read_only()
			result["unit_animation_clocks"] = clocks
			if probe != null: probe.increment("presentation.scene.deferred_animation_clocks", clocks.size())
	if full_scene and not controls_projection.ui_reference_units.is_empty():
		result["_diagnostic_full_unit_controls"] = controls_projection.ui_reference_units.duplicate()
	if refresh:
		overview_tick = tick
		if refresh_resources: resource_revision = next_resource_revision
		elif old_overview.has("resources"): result["overview"]["resources"] = old_overview["resources"]
	elif not old_overview.is_empty(): result["overview"] = old_overview
	result["overview_tick"] = overview_tick
	result["overview_resource_revision"] = resource_revision
	if full_scene:
		var transfer_started := Time.get_ticks_usec() if probe != null else 0
		var legal_resources: Array = result["resources"]
		if legal_resources.is_read_only(): Data._retain_immutable(legal_resources)
		if refresh and refresh_resources:
			result["overview"]["resources"] = legal_resources
		result["resource_chunks"] = world.observer_memory.publish_resource_chunks(world, team)
		if probe != null: probe.observe_microseconds("presentation.scene.resource_chunks", Time.get_ticks_usec() - transfer_started)
		result["resources"] = []
		result["resource_delta"] = {}
		# The camera query derives these small selection arrays from scene rows.
		# Sending them here repeats the same actor graphs during isolation.
		for key in ["control_units", "control_buildings", "control_resources"]: result.erase(key)
		# This producer already validated this exact overview graph when it was
		# published. Its lifetime proof is independent of the shared LRU, which
		# AI/navigation publications may evict between render generations.
		if not published_overview.is_empty():
			Data._retain_immutable(published_overview)
			var overview_resources: Array = published_overview.get("resources", [])
			if overview_resources.is_read_only(): Data._retain_immutable(overview_resources)
		var worker_publication: Dictionary = options.get("_scene_worker_publication", {})
		if worker_publication.has("commands"): Data._retain_immutable(worker_publication["commands"])
		controls_projection.retain_units(result["units"])
		controls_projection.retain_buildings(result["buildings"])
		if bool(result.get("split_unit_metadata", false)):
			# A new outer array over certified immutable render-cache records.
			Data._retain_immutable(result["render_units"])
		transfer_started = Time.get_ticks_usec() if probe != null else 0
		result = Data.freeze_owned(result, identity_override)
		if probe != null: probe.observe_microseconds("presentation.scene.freeze", Time.get_ticks_usec() - transfer_started)
		if probe != null and profile_capture_identity: probe.observe_microseconds("presentation.scene.freeze.identity_tracking" if identity_override == 1 else "presentation.scene.freeze.identity_queries", Time.get_ticks_usec() - transfer_started)
		if result.is_empty():
			push_error("Render scene contains values that cannot cross the owner boundary")
			return {}
		published_overview = result["overview"]
		controls_projection.finish()
	previous = {"overview": result["overview"]}
	if full_scene and probe != null and controls_projection.profile_compact_ui:
		# Comparisons deliberately build a second graph; keep those samples out
		# of the performance pair while still exercising their normal transfer.
		var sample_kind := "comparison" if not controls_projection.ui_reference_units.is_empty() else "compact" if controls_projection.compact_ui_tick else "full"
		probe.observe_microseconds("presentation.scene.total.ui_controls." + sample_kind, Time.get_ticks_usec() - capture_started)
	if full_scene and probe != null and controls_projection.profile_building_rows:
		probe.observe_microseconds("presentation.scene.total.retained_buildings" if controls_projection.building_rows_native else "presentation.scene.total.walked_buildings", Time.get_ticks_usec() - capture_started)
	if full_scene and probe != null and profile_capture_identity:
		probe.observe_microseconds("presentation.scene.total.identity_tracking" if identity_override == 1 else "presentation.scene.total.identity_queries", Time.get_ticks_usec() - capture_started)
	return result
