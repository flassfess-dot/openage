class_name RoRSimulationMovementSystem
extends RefCounted

const NavigationKnowledge := preload("res://scripts/navigation_knowledge.gd")

const Coordinates := preload("res://scripts/coordinates.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const MobileCollision := preload("res://scripts/mobile_collision.gd")
const LocalMovement := preload("res://scripts/local_movement.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const StuckRecovery := preload("res://scripts/stuck_recovery.gd")
const Journal := preload("res://scripts/entity_change_journal.gd")
const EMPTY_ELEVATION_VERTICES: Dictionary = {}

var ordered_gather_controller_enabled := OS.get_environment("ROR_DIAGNOSTIC_GATHER_CONTROLLER") != "0"
var ordered_gather_controller_supported := false
var ordered_gather_controller_tick := false
var profile_ordered_gather_controller := "--profile-gather-controller-alternatives" in OS.get_cmdline_user_args()
var ordered_gather_controller_sequence := 0
var cached_actor_keys_requested := OS.get_environment("ROR_DIAGNOSTIC_CACHED_ACTOR_KEYS") != "0"
var cached_actor_keys_supported := false
var cached_actor_keys_tick_native := false
var profile_cached_actor_keys := "--profile-cached-actor-keys" in OS.get_cmdline_user_args()
var cached_actor_keys_sequence := 0
var cached_actor_key_counts: Dictionary = {}

var knowledge := NavigationKnowledge.new()
var native_integration_enabled := true
var native_local_traffic_enabled := true
var native_work_traffic_enabled := OS.get_environment("ROR_DIAGNOSTIC_DISABLE_NATIVE_WORK_TRAFFIC") != "1"
var work_traffic_tick_native := false
var profile_work_traffic := "--profile-work-traffic-alternatives" in OS.get_cmdline_user_args()
var work_traffic_sequence := 0
var work_traffic_counters: Dictionary = {}
var compare_work_traffic_results := "--compare-work-traffic-results" in OS.get_cmdline_user_args()
var work_traffic_comparison_sequence := 0

var native_mobile_collision_enabled := true
var native_formation_yield_enabled := true
var native_formation_yield_supported := false
var profile_formation_yield_alternatives := "--profile-formation-yield-alternatives" in OS.get_cmdline_user_args()
var formation_yield_profile_sequence := 0
var native_progress_enabled := true
var native_combined_motion_enabled := true
var typed_motion_frame_requested := OS.get_environment("ROR_DIAGNOSTIC_TYPED_MOTION_FRAME") != "0"
var profile_typed_motion_alternatives := "--profile-typed-motion-alternatives" in OS.get_cmdline_user_args()
var typed_motion_frame_sequence := 0
var borrowed_motion_fields_requested := OS.get_environment("ROR_DIAGNOSTIC_BORROWED_MOTION_FIELDS") != "0"
var profile_borrowed_motion_fields := "--profile-borrowed-motion-fields" in OS.get_cmdline_user_args()
var borrowed_motion_fields_sequence := 0
var borrowed_motion_fields_enabled: bool:
	get: return borrowed_motion_fields_requested and (not profile_borrowed_motion_fields or ((borrowed_motion_fields_sequence * 1103515245 + 12345) & 0xffff) >= 32768)
var native_route_preparation_requested := OS.get_environment("ROR_DIAGNOSTIC_NATIVE_ROUTE_PREPARATION") != "0"
var profile_native_route_preparation := "--profile-route-preparation-alternatives" in OS.get_cmdline_user_args()
var native_route_preparation_sequence := 0
var native_route_preparation_enabled: bool:
	get: return native_route_preparation_requested and (not profile_native_route_preparation or ((native_route_preparation_sequence * 1103515245 + 12345) & 0xffff) >= 32768)
var typed_motion_frame_enabled: bool:
	get:
		return typed_motion_frame_requested and (not profile_typed_motion_alternatives or ((typed_motion_frame_sequence * 1103515245 + 12345) & 0xffff) >= 32768)
var compare_typed_motion_frame := "--compare-typed-motion-frame" in OS.get_cmdline_user_args()
var profile_recovery_cache := "--profile-recovery-cache" in OS.get_cmdline_user_args()
var recovery_cache_counters: Dictionary = {}
var native_combined_motion_supported := false
var native_group_combined_enabled := true
var native_group_combined_supported := false
var native_contacts_enabled := OS.get_environment("ROR_DIAGNOSTIC_DISABLE_NATIVE_CONTACTS") != "1"
var native_contacts_supported := false
var native_contact_frame_requested := OS.get_environment("ROR_DIAGNOSTIC_NATIVE_CONTACT_FRAME") != "0"
var native_contact_frame_supported := false
var profile_contact_frame := "--profile-contact-frame-alternatives" in OS.get_cmdline_user_args()
var compare_contact_frame := "--compare-contact-frame" in OS.get_cmdline_user_args()
var contact_frame_sequence := 0
var contact_frame_tick_native := false
var native_checked_moves_enabled := OS.get_environment("ROR_DIAGNOSTIC_DISABLE_CHECKED_MOVES") != "1"
var native_checked_moves_supported := false
var profile_checked_moves := "--profile-checked-move-alternatives" in OS.get_cmdline_user_args()
var checked_move_sequence := 0
var checked_move_tick_native := false
var checked_move_attempts := 0
var checked_move_updates := 0
# Whole-implementation diagnostic switch; no gameplay cases use it.
# The shared stages are ready, but the native coordinator is not accepted yet.
var common_movement_pipeline_enabled := OS.get_environment("ROR_DIAGNOSTIC_ENABLE_MOVEMENT_PIPELINE") == "1" and OS.get_environment("ROR_DIAGNOSTIC_DISABLE_MOVEMENT_PIPELINE") != "1"
var common_movement_pipeline_supported := false
# One common coordinator for all supported actor states. An explicit zero
# retains the reference path for diagnostics; missing native APIs also fall back.
var full_actor_pipeline_enabled := OS.get_environment("ROR_DIAGNOSTIC_ACTOR_PIPELINE") != "0"
var full_actor_pipeline_supported := false
var full_actor_pipeline_tick_native := false
var profile_full_actor_pipeline := "--profile-actor-pipeline-alternatives" in OS.get_cmdline_user_args()
var profile_native_actor_stages := "--profile-native-actor-stages" in OS.get_cmdline_user_args()
var profile_script_boundaries := "--profile-script-boundaries" in OS.get_cmdline_user_args()
var script_boundary_profile: Dictionary = {}
var full_actor_pipeline_sequence := 0
var full_actor_pipeline_counters: Dictionary = {}
var scoped_resource_digest_requested := OS.get_environment("ROR_DIAGNOSTIC_SCOPED_RESOURCE_DIGEST") != "0"
var profile_scoped_resource_digest := "--profile-scoped-resource-digest-alternatives" in OS.get_cmdline_user_args()
var scoped_resource_digest_sequence := 0
var scoped_resource_digest_tick := false

var profile_common_movement_pipeline := "--profile-movement-pipeline-alternatives" in OS.get_cmdline_user_args()
var common_movement_pipeline_tick_native := false
var common_movement_pipeline_sequence := 0
var common_movement_pipeline_calls := 0
var common_movement_batch_operations := 0
var common_movement_batch_refreshes := 0
var native_unit_span_enabled := OS.get_environment("ROR_DIAGNOSTIC_DISABLE_UNIT_SPAN") != "1"
var native_unit_span_supported := false
var profile_unit_span := "--profile-native-unit-span" in OS.get_cmdline_user_args()
var unit_span_sequence := 0
var profile_native_move_fallbacks := "--profile-native-move-fallbacks" in OS.get_cmdline_user_args()
var native_move_fallback_costs: Dictionary = {}
var unit_span_tick_native := false
var unit_span_calls := 0
var unit_span_updates := 0
var actor_order_observer: Callable = Callable()
var native_control_publication_supported := false
var control_publication_batches := 0
var profile_mobile_contacts := "--profile-mobile-contacts-alternatives" in OS.get_cmdline_user_args()
var mobile_contacts_profile_sequence := 0
var profile_group_combined := "--profile-group-combined-alternatives" in OS.get_cmdline_user_args()
var group_combined_profile_sequence := 0
var profile_motion_alternatives := "--profile-motion-alternatives" in OS.get_cmdline_user_args()
var motion_profile_sequence := 0
var profile_progress_alternatives := "--profile-progress-alternatives" in OS.get_cmdline_user_args()
var progress_profile_sequence := 0
var native_integration_supported := false
var native_velocity_write_supported := false
var native_collision_supported := false
var native_progress_supported := false
var integration_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null:
	set(value):
		integration_kernel = value
		_refresh_native_capabilities()
var collision_cursor := -1
var collision_epoch := -1
var overlap_pending: Dictionary = {}
var profiled_detour_checkpoints: Dictionary = {}

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)
	_refresh_native_capabilities()


func _refresh_native_capabilities() -> void:
	cached_actor_keys_supported = integration_kernel != null and integration_kernel.has_method("supports_actor_key_cache")
	full_actor_pipeline_supported = integration_kernel != null and integration_kernel.has_method("get_actor_pipeline_version")
	ordered_gather_controller_supported = integration_kernel != null and integration_kernel.has_method("supports_ordered_gather_controller")
	common_movement_pipeline_supported = integration_kernel != null and integration_kernel.has_method("advance_move_pipeline")
	# Native classes are not reloadable. Recheck only when replacing the kernel,
	# including null/older-extension fallbacks, rather than for every actor/angle.
	native_integration_supported = integration_kernel != null and integration_kernel.has_method("integrate_unit_motion")
	native_velocity_write_supported = native_integration_supported and integration_kernel.has_method("set_motion_velocities")
	native_collision_supported = integration_kernel != null and integration_kernel.has_method("constrain_mobile_velocity")
	native_formation_yield_supported = integration_kernel != null and integration_kernel.has_method("formation_yield_velocity")
	native_progress_supported = integration_kernel != null and integration_kernel.has_method("update_route_progress")
	native_combined_motion_supported = native_integration_supported and native_velocity_write_supported and native_progress_supported and integration_kernel.has_method("advance_native_motion")
	native_group_combined_supported = native_combined_motion_supported and integration_kernel.has_method("advance_native_group_motion")
	native_contacts_supported = integration_kernel != null and integration_kernel.has_method("settle_mobile_contacts")
	native_contact_frame_supported = native_contacts_supported and integration_kernel.has_method("settle_mobile_contacts_flat")
	native_checked_moves_supported = integration_kernel != null and integration_kernel.has_method("advance_checked_move_order")
	native_control_publication_supported = integration_kernel != null and integration_kernel.has_method("publish_active_unit_controls")
	native_unit_span_supported = integration_kernel != null and integration_kernel.has_method("advance_ordered_unit_span") and integration_kernel.get_script() == null


func prepare_unit_span(units: Array, enabled: bool, actor_context: Dictionary) -> Dictionary:
	scoped_resource_digest_tick = scoped_resource_digest_requested and integration_kernel != null and integration_kernel.has_method("supports_scoped_resource_digest")
	if profile_scoped_resource_digest:
		scoped_resource_digest_sequence += 1
		scoped_resource_digest_tick = scoped_resource_digest_tick and ((scoped_resource_digest_sequence * 1103515245 + 12345) & 0xffff) >= 32768
	cached_actor_keys_tick_native = cached_actor_keys_requested and cached_actor_keys_supported
	if profile_cached_actor_keys:
		cached_actor_keys_sequence += 1
		cached_actor_keys_tick_native = cached_actor_keys_tick_native and ((cached_actor_keys_sequence * 1103515245 + 12345) & 0xffff) >= 32768
	unit_span_tick_native = enabled and native_unit_span_enabled and native_unit_span_supported
	if profile_unit_span:
		unit_span_sequence += 1
		unit_span_tick_native = unit_span_tick_native and ((unit_span_sequence * 1103515245 + 12345) & 0xffff) >= 32768
	if not unit_span_tick_native: return {}
	var w = world
	var spatial = w.spatial_index
	var group_enabled: bool = native_group_combined_enabled and native_group_combined_supported and native_mobile_collision_enabled and native_collision_supported and w.pathfinder.uses_native_kernel()
	var direct_neighbors: bool = spatial.native_neighbors_enabled and spatial.native_neighbors_supported and spatial.query_kernel != null and spatial.query_kernel.get_script() == null and spatial.query_kernel.is_class("RoRReadModelKernel")
	return {"cached_actor_keys":cached_actor_keys_tick_native,"profile_cached_actor_keys":profile_cached_actor_keys,"profile_script_boundaries":profile_script_boundaries,"script_boundary_stats":script_boundary_profile,"gather_controller":ordered_gather_controller_tick,"profile_actor_stages":profile_native_actor_stages,"actor_pipeline":full_actor_pipeline_tick_native and not actor_order_observer.is_valid(),"actor_domain":Callable(w,"_advance_actor_domain"),"gather_continue":Callable(w.gathering_system,"_continue_gather_order"),"gathering_system":w.gathering_system,"conversion_system":w.conversion_system,"movement_system":self,"common_pipeline":common_movement_pipeline_tick_native and not actor_order_observer.is_valid(),"continue_prepared":Callable(w,"_continue_actor_order_after_prepare"),"profile_move_fallbacks":profile_native_move_fallbacks,"world":w,"journal":w.entity_changes,"activity":w.unit_activity_registry,"units":units,"orders":w.unit_activity_registry.unit_order_by_id,"unit_ids":w.units_by_id,"envelopes":w.open_movement_envelopes_by_id,"groups":w.formation_groups_view,"movement_shared":w.pathfinder.native_shared_movement_kernel,"movement_by_unit":w.pathfinder.native_movement_kernels_by_unit_id,"vertices":w.terrain_elevation.vertex_levels if w.terrain_elevation.nonzero_vertex_count > 0 else EMPTY_ELEVATION_VERTICES,"map_size":w.map_size,"physical":w.pathfinder,"neighbors":w.movement_neighbor_buffer,"group_enabled":group_enabled,"direct_neighbors":direct_neighbors,"knowledge":knowledge,"spatial":spatial,"elevation":w.terrain_elevation,"fallback":actor_order_observer if actor_order_observer.is_valid() else Callable(w,"_advance_actor_order"),"actor_context":actor_context,"buckets":spatial.unit_buckets,"entities":spatial.unit_entities,"positions":spatial.unit_positions,"radii":spatial.unit_radii,"cell_size":spatial.cell_size,"maximum_radius":spatial.maximum_unit_radius,"maximum_clearance":spatial.maximum_unit_clearance}


func advance_unit_span(context: Dictionary, delta: float) -> Dictionary:
	var progress: Dictionary = integration_kernel.advance_ordered_unit_span(context, delta)
	if progress.is_empty(): return progress
	for key in progress.get("actor_key_counts", {}): cached_actor_key_counts[key] = int(cached_actor_key_counts.get(key, 0)) + int(progress["actor_key_counts"][key])
	var count := int(progress["updates"])
	for key in progress.get("actor_pipeline", {}):
		full_actor_pipeline_counters[key] = int(full_actor_pipeline_counters.get(key, 0)) + int(progress["actor_pipeline"][key])
	if profile_native_move_fallbacks:
		for reason in progress.get("move_fallbacks", {}):
			var measurement: Dictionary = progress["move_fallbacks"][reason]
			if not native_move_fallback_costs.has(reason): native_move_fallback_costs[reason] = {"calls":0,"us":0}
			native_move_fallback_costs[reason]["calls"] += int(measurement["calls"])
			native_move_fallback_costs[reason]["us"] += int(measurement["us"])
	common_movement_pipeline_calls += int(progress.get("pipeline_calls", 0))
	common_movement_batch_operations += int(progress.get("batch_operations", 0))
	common_movement_batch_refreshes += int(progress.get("batch_binding_refreshes", 0))
	unit_span_calls += 1
	unit_span_updates += count
	checked_move_attempts += int(progress["attempts"])
	checked_move_updates += count
	var w = world
	w.movement_native_unit_updates += int(progress.get("motion_updates", count))
	w.movement_native_neighbor_candidates += int(progress["candidates"])
	return progress


func publish_active_controls(active_units: Array) -> bool:
	if not native_control_publication_supported: return false
	var simulation_world = world
	var count: int = integration_kernel.publish_active_unit_controls(active_units, simulation_world.units_by_id, simulation_world.entity_changes, simulation_world.unit_activity_registry)
	if count < 0: return false
	control_publication_batches += 1
	return true


func use_checked_moves() -> bool:
	if profile_native_route_preparation: native_route_preparation_sequence += 1
	if profile_typed_motion_alternatives: typed_motion_frame_sequence += 1
	if profile_borrowed_motion_fields: borrowed_motion_fields_sequence += 1
	work_traffic_tick_native = native_work_traffic_enabled
	if profile_work_traffic:
		work_traffic_sequence += 1
		work_traffic_tick_native = work_traffic_tick_native and ((work_traffic_sequence * 1103515245 + 12345) & 0xffff) >= 32768
	full_actor_pipeline_tick_native = full_actor_pipeline_enabled and full_actor_pipeline_supported and not actor_order_observer.is_valid() and world.tick_pipeline.performance_probe == null
	if profile_full_actor_pipeline:
		full_actor_pipeline_sequence += 1
		full_actor_pipeline_tick_native = full_actor_pipeline_tick_native and ((full_actor_pipeline_sequence * 1103515245 + 12345) & 0xffff) >= 32768
	common_movement_pipeline_tick_native = common_movement_pipeline_enabled and common_movement_pipeline_supported
	if profile_common_movement_pipeline:
		common_movement_pipeline_sequence += 1
		common_movement_pipeline_tick_native = common_movement_pipeline_tick_native and ((common_movement_pipeline_sequence * 1103515245 + 12345) & 0xffff) >= 32768
	common_movement_pipeline_tick_native = common_movement_pipeline_tick_native or full_actor_pipeline_tick_native
	ordered_gather_controller_tick = full_actor_pipeline_tick_native and ordered_gather_controller_enabled and ordered_gather_controller_supported
	if profile_ordered_gather_controller:
		ordered_gather_controller_sequence += 1
		ordered_gather_controller_tick = ordered_gather_controller_tick and ((ordered_gather_controller_sequence * 1103515245 + 12345) & 0xffff) >= 32768
	var enabled := native_checked_moves_enabled and native_checked_moves_supported and native_combined_motion_enabled and native_combined_motion_supported and native_integration_enabled and native_progress_enabled and native_formation_yield_enabled and native_formation_yield_supported and not profile_progress_alternatives and not profile_motion_alternatives and not profile_group_combined and not profile_formation_yield_alternatives
	if profile_checked_moves:
		checked_move_sequence += 1
		enabled = enabled and ((checked_move_sequence * 1103515245 + 12345) & 0xffff) >= 32768
	checked_move_tick_native = enabled
	return enabled


func advance_checked_move(unit: Dictionary, delta: float) -> bool:
	checked_move_attempts += 1
	var simulation_world = world
	var unit_id := int(unit["id"])
	if bool(unit["formation_shared_motion"]) or simulation_world.open_movement_envelopes_by_id.has(unit_id) or not simulation_world.pathfinder.has_native_movement_for(unit_id): return false
	var planner = knowledge.planner(simulation_world, int(unit["team"]))
	var movement_kernel: Variant = simulation_world.pathfinder.native_shared_movement_kernel
	if movement_kernel == null: movement_kernel = simulation_world.pathfinder.native_movement_kernels_by_unit_id.get(unit_id)
	var stop_tick := 30
	if int(unit["formation_group_id"]) >= 0 and int(unit["stuck_ticks"]) >= 4:
		if not native_group_combined_enabled or not native_group_combined_supported or not native_mobile_collision_enabled or not native_collision_supported or not simulation_world.pathfinder.uses_native_kernel(): return false
		var group = simulation_world.formation_groups_view.get(int(unit["formation_group_id"]))
		if group != null: stop_tick += mini(1200, group.member_ids.size() * 20)
		simulation_world.spatial_index.query_neighbors_into(unit, simulation_world.spatial_index.movement_neighbor_radius(unit), "unit", simulation_world.movement_neighbor_buffer)
	var vertices: Dictionary = simulation_world.terrain_elevation.vertex_levels if simulation_world.terrain_elevation.nonzero_vertex_count > 0 else EMPTY_ELEVATION_VERTICES
	assert(simulation_world.read_generation_pins == 0, "Pinned observation generation is immutable")
	var step: Vector4 = integration_kernel.advance_checked_move_order(unit, movement_kernel, delta, simulation_world.map_size, vertices, simulation_world.movement_neighbor_buffer, simulation_world.pathfinder, planner, stop_tick)
	if step.x < 0.0: return false
	var mask := roundi(step.x)
	if mask != 0: simulation_world.notify_entity_changed(unit, mask)
	simulation_world.movement_native_unit_updates += 1
	simulation_world.movement_native_neighbor_candidates += maxi(0, roundi(step.y))
	checked_move_updates += 1
	return true


func settle_mobile_overlaps(active_units: Array, delta: float) -> void:
	if delta <= 0.0: return
	contact_frame_sequence += 1
	contact_frame_tick_native = false
	var use_contact_frame := native_contact_frame_requested and native_contact_frame_supported and (not profile_contact_frame or ((contact_frame_sequence * 1103515245 + 12345) & 0xffff) >= 32768)
	# Steering reads an immutable start-of-tick snapshot. Resolve residual
	# simultaneous contacts using actual positions, including idle actors from
	# old saves. Subsequent ticks visit only changed actors and unsettled pairs.
	var simulation_world = world
	var changes: Dictionary = simulation_world.entity_changes.read_changes_since(collision_cursor if collision_epoch == simulation_world.entity_changes.epoch else -1)
	var probe: Variant = simulation_world.tick_pipeline.performance_probe
	var use_native: bool = native_contacts_enabled and native_contacts_supported and simulation_world.spatial_index.native_neighbors_enabled
	if profile_mobile_contacts and probe != null:
		mobile_contacts_profile_sequence += 1
		use_native = use_native and mobile_contacts_profile_sequence % 2 == 0
	var contacts_started := Time.get_ticks_usec() if probe != null else 0
	var native_count := -1
	if use_native:
		var index = simulation_world.spatial_index
		if use_contact_frame:
			native_count = integration_kernel.settle_mobile_contacts_flat(changes, active_units, simulation_world.units, simulation_world.units_by_id, index.unit_buckets, index.unit_entities, index.unit_positions, index.unit_radii, index.cell_size, index.maximum_unit_radius, delta, overlap_pending, Callable(index, "query_neighbors_into"), Callable(self, "_separate_mobile"), compare_contact_frame)
			contact_frame_tick_native = native_count >= 0
		if native_count < 0:
			native_count = integration_kernel.settle_mobile_contacts(changes, active_units, simulation_world.units, simulation_world.units_by_id, index.unit_buckets, index.unit_entities, index.unit_positions, index.unit_radii, index.cell_size, index.maximum_unit_radius, delta, overlap_pending, Callable(index, "query_neighbors_into"), Callable(self, "_separate_mobile"))
	var settled := native_count >= 0
	if not settled:
		native_count = _settle_mobile_contacts_script(changes, active_units, delta, simulation_world)
	if probe != null:
		probe.observe_microseconds("simulation.contacts.native" if settled else "simulation.contacts.script", Time.get_ticks_usec() - contacts_started)
		probe.increment("simulation.contacts.candidates", native_count)
	collision_cursor = int(changes["revision"])
	collision_epoch = simulation_world.entity_changes.epoch


func _settle_mobile_contacts_script(changes: Dictionary, active_units: Array, delta: float, simulation_world) -> int:
	var candidates := overlap_pending.duplicate()
	overlap_pending.clear()
	if bool(changes["full"]):
		for unit in simulation_world.units: candidates[int(unit["id"])] = unit
	else:
		for unit in active_units:
			if not bool(unit.get("formation_shared_isolated", false)): candidates[int(unit["id"])] = unit
		for id in changes["ids"]:
			if int(changes["masks"][id]) & (Journal.LIFECYCLE | Journal.POSITION):
				var unit: Variant = simulation_world.find_unit(int(id))
				if unit != null and not bool(unit.get("formation_shared_isolated", false)): candidates[int(id)] = unit
	var ids := candidates.keys()
	ids.sort()
	var pairs: Dictionary = {}
	var neighbors: Array = []
	for id in ids:
		var unit: Dictionary = candidates[id]
		if float(unit.get("hp", 0.0)) <= 0.0 or simulation_world.find_unit(id) == null: continue
		simulation_world.spatial_index.query_neighbors_into(unit, float(unit["footprint_radius"]) + 0.25, "unit", neighbors)
		for other in neighbors:
			var other_id := int(other["id"])
			if float(other.get("hp", 0.0)) <= 0.0 or String(other.get("movement_domain", "land")) != String(unit.get("movement_domain", "land")): continue
			var gap: Vector2 = unit["pos"] - other["pos"]
			var radius := float(unit["footprint_radius"]) + float(other["footprint_radius"])
			if gap.length_squared() >= (radius - 0.001) * (radius - 0.001): continue
			var pair := Vector2i(mini(id, other_id), maxi(id, other_id))
			if pairs.has(pair): continue
			pairs[pair] = true
			var distance := gap.length()
			overlap_pending[id] = unit
			overlap_pending[other_id] = other
			var normal := gap / distance if distance > 0.0001 else Vector2(0, -1 if id < other_id else 1)
			var correction := minf(radius - distance + 0.002, maxf(0.01, delta * 2.0))
			var first := _separate_mobile(unit, normal * correction * 0.5)
			var second := _separate_mobile(other, -normal * (correction - first))
			if second < correction * 0.5: _separate_mobile(unit, normal * (correction * 0.5 - second))
	return ids.size()


func _separate_mobile(unit: Dictionary, offset: Vector2) -> float:
	# The contact frame keeps hp, radius and domain fixed for this stage;
	# this correction updates pose/navigation targets only.
	if offset.length_squared() <= 0.000001: return 0.0
	var simulation_world = world
	# A radial push can be blocked at an L-shaped forest corridor even though
	# sliding along either cell edge frees the contact. Every alternative has
	# a nonnegative projection away from the other body and still obeys terrain.
	var directions := [offset, Vector2(offset.x, 0), Vector2(0, offset.y), offset.rotated(PI/4), offset.rotated(-PI/4), offset.orthogonal(), -offset.orthogonal()]
	for direction in directions:
		if Vector2(direction).length_squared() <= 0.000001: continue
		var displacement: Vector2 = Vector2(direction).normalized() * offset.length()
		var position: Vector2 = unit["pos"] + displacement
		if position.x < 0.5 or position.y < 0.5 or position.x > simulation_world.map_size.x - 0.5 or position.y > simulation_world.map_size.y - 0.5: continue
		if not simulation_world.navigation_grid.is_position_walkable_for(position, float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])): continue
		simulation_world.set_entity_field(unit, "pos", position)
		if simulation_world.terrain_elevation.nonzero_vertex_count > 0: simulation_world.set_entity_field(unit, "elevation", simulation_world.elevation_at(position))
		if String(unit["task"]) == "idle" and unit.get("path", []).is_empty():
			simulation_world.set_entity_field(unit, "target", position)
			simulation_world.set_entity_field(unit, "destination", position)
		return displacement.length()
	return 0.0


func move_unit(unit: Dictionary, delta: float) -> bool:
	var simulation_world = world
	var planner = knowledge.planner(simulation_world, int(unit.get("team", 0)))
	if common_movement_pipeline_tick_native and simulation_world.tick_pipeline.performance_probe == null:
		var step: Vector4 = integration_kernel.advance_move_pipeline(unit, delta, simulation_world, self, planner)
		if step.x >= 0.0:
			simulation_world.movement_native_unit_updates += maxi(0, roundi(step.y))
			simulation_world.movement_native_neighbor_candidates += maxi(0, roundi(step.z))
			common_movement_pipeline_calls += 1
			return step.x > 0.0
	return _move_unit_reference(unit, delta, planner)


func _move_unit_reference(unit: Dictionary, delta: float, planner) -> bool:
	var simulation_world = world
	var probe: Variant = simulation_world.tick_pipeline.performance_probe
	var started := Time.get_ticks_usec() if probe != null else 0
	_prepare_move_route(unit, planner, simulation_world)
	if probe != null: probe.observe_microseconds("simulation.movement.path_refresh", Time.get_ticks_usec() - started)
	if Vector2(unit["target"]).distance_squared_to(Vector2(unit["pos"])) < 0.001225:
		return _advance_move_arrival(unit, delta, simulation_world)
	return _advance_motion_body(unit, delta, planner, simulation_world, probe, true)


func _prepare_move_route(unit: Dictionary, planner, simulation_world) -> void:
	var old_revision := int(unit.get("path_knowledge_revision", planner.grid.revision))
	if old_revision != planner.grid.revision and not unit.get("path", []).is_empty():
		var changed_region: Variant = planner.grid.change_region_since(old_revision)
		var segment_bounds := Rect2(Vector2(unit["pos"]), Vector2.ZERO).expand(Vector2(unit["target"])).grow(float(unit["footprint_radius"]) + 1.0)
		if changed_region == null or segment_bounds.intersects(changed_region):
			if not planner.has_direct_cell_path(Vector2i(Vector2(unit["pos"]).floor()), Vector2i(Vector2(unit["target"]).floor()), String(unit["movement_domain"]), int(unit["terrain_restriction"]), float(unit["footprint_radius"])):
				assign_unit_destination(unit, unit["destination"], false)
		simulation_world.set_entity_field(unit, "path_knowledge_revision", planner.grid.revision)
	_advance_formation_corner(unit, planner)


func _advance_move_arrival(unit: Dictionary, delta: float, simulation_world) -> bool:
	var probe: Variant = simulation_world.tick_pipeline.performance_probe
	var movement_phase_started := Time.get_ticks_usec() if probe != null else 0
	var difference: Vector2 = unit["target"] - unit["pos"]
	var arrival_displacement := difference
	simulation_world.set_entity_field(unit, "pos", unit["target"])
	if simulation_world.terrain_elevation.nonzero_vertex_count > 0:
		simulation_world.set_entity_field(unit, "elevation", simulation_world.elevation_at(unit["pos"]))
	elif float(unit["elevation"]) != 0.0:
		simulation_world.set_entity_field(unit, "elevation", 0.0)
	simulation_world.set_entity_field(unit, "actual_velocity", arrival_displacement / delta if delta > 0.0 else Vector2.ZERO)
	if arrival_displacement.length_squared() > 0.000001:
		var arrival_facing := facing_for_vector(arrival_displacement)
		simulation_world.set_entity_field(unit, "movement_facing", arrival_facing)
		simulation_world.set_entity_field(unit, "desired_facing", arrival_facing)
		simulation_world.set_entity_field(unit, "facing", arrival_facing)
	var path: Array = unit.get("path", [])
	var next_index := int(unit.get("path_index", 0)) + 1
	if unit.has("formation_traffic_prefix") and next_index >= int(unit["formation_traffic_prefix"]):
		unit.erase("formation_traffic_prefix")
	if next_index < path.size():
		StuckRecovery.reset(unit)
		simulation_world.set_entity_field(unit, "path_index", next_index)
		simulation_world.set_entity_field(unit, "target", path[next_index])
		simulation_world.set_entity_field(unit, "path_knowledge_revision", -1)
		simulation_world.transition_entity_order(unit, OrderPipeline.MOVE_INTO_RANGE)
		if probe != null:
			simulation_world.movement_arrival_microseconds += Time.get_ticks_usec() - movement_phase_started
		return true
	simulation_world.set_entity_field(unit, "path", [])
	simulation_world.set_entity_field(unit, "path_index", 0)
	StuckRecovery.reset(unit)
	if unit["task"] in ["move", "attack_move"]:
		if simulation_world.destination_reservations.is_occupied(unit):
			simulation_world.set_entity_field(unit, "task", "idle")
			simulation_world.complete_entity_order(unit, "destination_reached")
			restore_formation_facing(unit)
		else:
			assign_unit_destination(unit, unit["reserved_destination"], false)
	elif unit["task"] in ["attack", "gather"]:
		simulation_world.transition_entity_order(unit, OrderPipeline.FACE_TARGET)
	if probe != null:
		simulation_world.movement_arrival_microseconds += Time.get_ticks_usec() - movement_phase_started
	return false


func _advance_motion_body(unit: Dictionary, delta: float, planner, simulation_world, probe: Variant, attempt_combined: bool = true) -> bool:
	var movement_phase_started := Time.get_ticks_usec() if probe != null else 0
	var unit_id := int(unit["id"])
	var shared_motion_requested := bool(unit["formation_shared_motion"])
	var open_envelope: Variant = null
	if shared_motion_requested or not simulation_world.open_movement_envelopes_by_id.is_empty():
		open_envelope = simulation_world.open_movement_envelopes_by_id.get(unit_id)
	if open_envelope != null and int(open_envelope.get("grid_revision", -1)) != simulation_world.navigation_grid.revision:
		if not _envelope_survives_grid_change(open_envelope):
			simulation_world.open_movement_envelopes_by_id.erase(unit_id)
			open_envelope = null
	var shared_motion := shared_motion_requested and open_envelope != null
	var native_movement: bool = not shared_motion and open_envelope == null and simulation_world.pathfinder.has_native_movement_for(unit_id)
	var script_step_started := 0
	var profile_script_step := false
	var group_script_started := 0
	var profile_group_script_step := false
	var stalled_ticks := int(unit["stuck_ticks"])
	var combined_stop_tick := 30
	var group_combined := false
	if native_movement and stalled_ticks >= 4 and int(unit["formation_group_id"]) >= 0 and native_group_combined_enabled and native_group_combined_supported and native_formation_yield_enabled and native_formation_yield_supported and native_mobile_collision_enabled and native_collision_supported and not profile_formation_yield_alternatives and simulation_world.pathfinder.uses_native_kernel() and (String(unit["task"]) != "gather" or stalled_ticks < 29):
		var combined_group = simulation_world.formation_groups_view.get(int(unit["formation_group_id"]))
		if combined_group != null: combined_stop_tick += mini(1200, combined_group.member_ids.size() * 20)
		group_combined = stalled_ticks < combined_stop_tick - 1
	var use_combined: bool = attempt_combined and simulation_world.unit_activity_registry.tick_prepared and native_movement and native_combined_motion_enabled and native_combined_motion_supported and native_integration_enabled and native_progress_enabled and not profile_progress_alternatives and (stalled_ticks < 4 or (stalled_ticks < 29 and int(unit["formation_group_id"]) < 0) or group_combined)
	if use_combined and group_combined and profile_group_combined and probe != null:
		group_combined_profile_sequence += 1
		use_combined = group_combined_profile_sequence % 2 == 0
		if not use_combined: group_script_started = Time.get_ticks_usec()
	if use_combined and profile_motion_alternatives and probe != null:
		motion_profile_sequence += 1
		use_combined = motion_profile_sequence % 2 == 0
		if not use_combined: script_step_started = Time.get_ticks_usec()
	if use_combined:
		var step_started := Time.get_ticks_usec() if probe != null else 0
		var stalled_before := int(unit["stuck_ticks"]) if probe != null else 0
		var movement_kernel: Variant = simulation_world.pathfinder.native_shared_movement_kernel
		if movement_kernel == null: movement_kernel = simulation_world.pathfinder.native_movement_kernels_by_unit_id.get(unit_id)
		assert(simulation_world.read_generation_pins == 0, "Pinned observation generation is immutable")
		var vertices: Dictionary = simulation_world.terrain_elevation.vertex_levels if simulation_world.terrain_elevation.nonzero_vertex_count > 0 else EMPTY_ELEVATION_VERTICES
		var step: Vector4
		if group_combined:
			simulation_world.spatial_index.query_neighbors_into(unit, simulation_world.spatial_index.movement_neighbor_radius(unit), "unit", simulation_world.movement_neighbor_buffer)
			step = integration_kernel.advance_native_group_motion(unit, movement_kernel, delta, simulation_world.map_size, vertices, simulation_world.movement_neighbor_buffer, simulation_world.pathfinder, combined_stop_tick)
		else:
			step = integration_kernel.advance_native_motion(unit, movement_kernel, delta, simulation_world.map_size, vertices)
		if step.x >= 0.0:
			var mask := roundi(step.x)
			if mask != 0: simulation_world.notify_entity_changed(unit, mask)
			_finish_native_move(unit, planner, step, group_combined, probe, stalled_ticks)
			simulation_world.movement_native_unit_updates += 1
			simulation_world.movement_native_neighbor_candidates += maxi(0, roundi(step.y))
			if probe != null:
				if group_combined:
					probe.increment("movement.native_group_combined_updates")
					probe.observe_microseconds("simulation.movement.group_combined.native", Time.get_ticks_usec()-step_started)
				probe.increment("movement.native_combined_unit_updates")
				if stalled_before >= 4: probe.increment("movement.native_combined_recovery_updates")
				if roundi(step.w) != 0: probe.increment("movement.native_combined_repaths")
				probe.observe_microseconds("simulation.movement.native_step", Time.get_ticks_usec() - step_started)
			return true
	if shared_motion and bool(unit["formation_shared_isolated"]):
		simulation_world.movement_neighbor_buffer.clear()
		if probe != null:
			probe.increment("movement.shared_formation_units")
			probe.increment("movement.isolated_shared_formation_units")
	elif shared_motion:
		var search_radius: float = simulation_world.spatial_index.movement_neighbor_radius(unit)
		simulation_world.spatial_index.query_external_neighbors_into(unit, search_radius, int(unit["formation_group_id"]), simulation_world.movement_neighbor_buffer)
		if probe != null:
			probe.increment("movement.shared_formation_units")
	elif native_movement:
		pass
	else:
		var search_radius: float = simulation_world.spatial_index.movement_neighbor_radius(unit)
		simulation_world.spatial_index.query_neighbors_into(unit, search_radius, "unit", simulation_world.movement_neighbor_buffer)
	if probe != null:
		simulation_world.movement_neighbor_query_microseconds += Time.get_ticks_usec() - movement_phase_started
		movement_phase_started = Time.get_ticks_usec()
	var steering_target: Vector2 = unit.get("formation_steering_target", unit["target"]) if open_envelope != null else unit["target"]
	var movement_reason := ""
	var motion_write_mask := 0
	if shared_motion and bool(unit["formation_shared_isolated"]):
		LocalMovement.calculate_shared_translation_into(unit, steering_target)
	elif native_movement:
		var native_result: Vector4 = simulation_world.pathfinder.calculate_native_movement(unit, unit["target"], delta)
		var native_state := roundi(native_result.z)
		profile_script_step = script_step_started > 0 and native_state >= 0 and native_state < 2
		profile_group_script_step = group_script_started > 0 and native_state >= 0 and native_state < 2
		var native_difference: Vector2 = unit["target"] - unit["pos"]
		var native_speed := maxf(0.0, float(unit["speed"]) * float(unit["cohesion_speed_scale"]))
		var desired_velocity := native_difference.normalized() * native_speed if native_difference.length_squared() > 0.000001 else Vector2.ZERO
		var actual_velocity := Vector2(native_result.x, native_result.y)
		if native_integration_enabled and native_velocity_write_supported:
			assert(simulation_world.read_generation_pins == 0, "Pinned observation generation is immutable")
			motion_write_mask = integration_kernel.set_motion_velocities(unit, desired_velocity, actual_velocity)
		else:
			simulation_world.set_entity_field(unit, "desired_velocity", desired_velocity)
			simulation_world.set_entity_field(unit, "actual_velocity", actual_velocity)
		if native_state == 1:
			movement_reason = "local_obstacle"
		elif native_state == 2:
			movement_reason = "local_blocked"
		simulation_world.movement_native_unit_updates += 1
		simulation_world.movement_native_neighbor_candidates += maxi(0, roundi(native_result.w))
	else:
		movement_reason = LocalMovement.calculate_runtime_unit_into(unit, steering_target, simulation_world.movement_neighbor_buffer, simulation_world.navigation_grid, delta, open_envelope)
	if probe != null: probe.observe_microseconds("simulation.movement.solve", Time.get_ticks_usec() - movement_phase_started)
	var formation_yielding := false
	if int(unit["formation_group_id"]) >= 0 and int(unit["stuck_ticks"]) >= 4:
		var yield_started := Time.get_ticks_usec() if probe != null else 0
		if native_movement:
			simulation_world.spatial_index.query_neighbors_into(unit, simulation_world.spatial_index.movement_neighbor_radius(unit), "unit", simulation_world.movement_neighbor_buffer)
		var yielding: Variant = _formation_yield_velocity(unit, simulation_world.movement_neighbor_buffer, delta)
		if yielding is Vector2:
			simulation_world.set_entity_field(unit, "actual_velocity", yielding)
			formation_yielding = true
		if probe != null: probe.observe_microseconds("simulation.movement.formation_yield", Time.get_ticks_usec() - yield_started)
	if movement_reason == "local_blocked":
		var escape_started := Time.get_ticks_usec() if probe != null else 0
		var escape_velocity := _escape_invalid_footprint(unit, delta)
		if escape_velocity.length_squared() > 0.000001:
			simulation_world.set_entity_field(unit, "actual_velocity", escape_velocity)
			movement_reason = "escaping_invalid_footprint"
		if probe != null: probe.observe_microseconds("simulation.movement.footprint_escape", Time.get_ticks_usec() - escape_started)
	if probe != null:
		simulation_world.movement_local_calculation_microseconds += Time.get_ticks_usec() - movement_phase_started
		movement_phase_started = Time.get_ticks_usec()
	if shared_motion and not bool(unit["formation_shared_isolated"]):
		simulation_world.set_entity_field(unit, "actual_velocity", MobileCollision.constrain(unit, unit["actual_velocity"], simulation_world.movement_neighbor_buffer, delta))
		if not simulation_world.navigation_grid.is_position_walkable_for(Vector2(unit["pos"]) + Vector2(unit["actual_velocity"]) * delta, float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])):
			simulation_world.set_entity_field(unit, "actual_velocity", Vector2.ZERO)
	if native_integration_enabled and native_integration_supported:
		assert(simulation_world.read_generation_pins == 0, "Pinned observation generation is immutable")
		var vertices: Dictionary = simulation_world.terrain_elevation.vertex_levels if simulation_world.terrain_elevation.nonzero_vertex_count > 0 else EMPTY_ELEVATION_VERTICES
		var changed_mask: int = integration_kernel.integrate_unit_motion(unit, delta, simulation_world.map_size, vertices, movement_reason)
		changed_mask |= motion_write_mask
		if changed_mask != 0: simulation_world.notify_entity_changed(unit, changed_mask)
	else:
		_integrate_unit_motion(unit, delta, movement_reason, simulation_world)
	var recovery_started := Time.get_ticks_usec() if probe != null else 0
	if probe != null: probe.observe_microseconds("simulation.movement.commit", recovery_started - movement_phase_started)
	var stop_tick := StuckRecovery.STOP_TICK
	if String(unit["task"]) == "gather" and int(unit["stuck_ticks"]) >= StuckRecovery.STOP_TICK - 1:
		# Harvesting takes longer than the ordinary 1.5-second stall window.
		# Give traffic at a shared resource/drop site time to clear, retaining
		# the same bounded local/global replans and a terminal deadlock limit.
		if simulation_world.spatial_index.has_friendly_gatherer(unit, float(unit["footprint_radius"]) + 2.0): stop_tick = 600
	var group = simulation_world.formation_groups_view.get(int(unit["formation_group_id"]))
	if group != null:
		# Waiting in a convoy can outlast the ordinary 1.5-second stall window.
		# Initial local/global retries and later deployment checks stay bounded. Columns
		# and final deployment receive a finite size-dependent waiting budget.
		stop_tick += mini(1200, group.member_ids.size() * 20)
	var recovery_action := ""
	if not formation_yielding:
		var native_progress: bool = native_progress_enabled and native_progress_supported
		if profile_progress_alternatives and probe != null:
			progress_profile_sequence += 1
			native_progress = native_progress and progress_profile_sequence % 2 == 0
		var kernel_started := Time.get_ticks_usec() if probe != null else 0
		recovery_action = integration_kernel.update_route_progress(unit, stop_tick) if native_progress else StuckRecovery.update_route_progress(unit, stop_tick)
		if probe != null: probe.observe_microseconds("simulation.movement.native_progress_kernel" if native_progress else "simulation.movement.script_progress_kernel", Time.get_ticks_usec() - kernel_started)
	if probe != null:
		probe.observe_microseconds("simulation.movement.progress", Time.get_ticks_usec() - recovery_started)
		recovery_started = Time.get_ticks_usec()
	match recovery_action:
		"local_repath":
			_recover_route(unit, planner, false)
		"global_repath":
			_recover_route(unit, planner, true)
		"stop":
			# Release work and formation reservations as well as movement slots;
			# an abandoned approach must not block every following worker.
			if String(unit["task"]) == "board":
				simulation_world.set_entity_field(unit, "task", "idle")
				stop_unit_motion(unit, false)
				simulation_world.complete_entity_order(unit, "stuck")
			else:
				simulation_world.halt_unit(unit, "stuck_stopped_nearest_valid")
				simulation_world.set_entity_field(unit, "diagnostic_reason", "stuck_stopped_nearest_valid")
			simulation_world.set_entity_field(unit, "formation_shared_motion", false)
			simulation_world.set_entity_field(unit, "formation_slot_mode", "released")
			simulation_world.set_entity_field(unit, "formation_group_id", -1)
			simulation_world.set_entity_field(unit, "formation_home", null)
			if probe != null:
				probe.observe_microseconds("simulation.movement.recovery_routes", Time.get_ticks_usec() - recovery_started)
				simulation_world.movement_integration_microseconds += Time.get_ticks_usec() - movement_phase_started
			return false
	if (group != null or String(unit["task"])=="gather") and recovery_action.is_empty() and int(unit["stuck_ticks"]) != stalled_ticks and int(unit["stuck_ticks"]) in [60, 180, 360, 720]:
		# Deployment changes as earlier ranks take their homes. Retry the local
		# body detour at a bounded set of later checkpoints, not every fixed tick.
		_run_late_work_detour(unit, planner, formation_yielding, probe)
	if probe != null:
		probe.observe_microseconds("simulation.movement.recovery_routes", Time.get_ticks_usec() - recovery_started)
		simulation_world.movement_integration_microseconds += Time.get_ticks_usec() - movement_phase_started
		if profile_script_step: probe.observe_microseconds("simulation.movement.script_step", Time.get_ticks_usec() - script_step_started)
		if profile_group_script_step: probe.observe_microseconds("simulation.movement.group_combined.script", Time.get_ticks_usec()-group_script_started)
	return true


func _finish_native_move(unit: Dictionary, planner, step: Vector4, group_combined: bool, probe: Variant = null, previous_stuck: int = -1) -> void:
	if roundi(step.w) == 1: _recover_route(unit, planner, false)
	elif roundi(step.w) == 2: _recover_route(unit, planner, true)
	elif group_combined and int(unit["stuck_ticks"]) != previous_stuck and int(unit["stuck_ticks"]) in [60, 180, 360, 720]: _run_late_work_detour(unit, planner, (roundi(step.z) & 4) != 0, probe)


func _run_late_work_detour(unit: Dictionary, planner, yielding: bool, probe) -> void:
	var checkpoint_started := Time.get_ticks_usec() if probe != null else 0
	if probe != null:
		var unit_id := int(unit["id"])
		var point := Vector3i(int(unit["stuck_ticks"]), int(unit.get("navigation_progress", {}).get("order_revision", 0)), probe.sample_count("controller.fixed_tick"))
		var previous: Vector3i = profiled_detour_checkpoints.get(unit_id, Vector3i(-1,-1,-1))
		if previous.x == point.x and previous.y == point.y and previous.z == point.z-1: probe.increment("movement.traffic_checkpoint_consecutive_repeats")
		if profiled_detour_checkpoints.size() >= 4096: profiled_detour_checkpoints.clear()
		profiled_detour_checkpoints[unit_id] = point
		probe.increment("movement.traffic_checkpoint_calls")
		if yielding: probe.increment("movement.traffic_checkpoint_yielding")
	if not _try_formation_transit_detour(unit, planner):
		_try_work_traffic_detour(unit, planner)
	if probe != null: probe.observe_microseconds("simulation.movement.traffic_checkpoint_detour", Time.get_ticks_usec()-checkpoint_started)


func _recover_route(unit: Dictionary, planner, global_repath: bool) -> void:
	var started := Time.get_ticks_usec() if profile_recovery_cache else 0
	var invalidated := 0
	var local_route := _try_formation_transit_detour(unit, planner)
	if global_repath and not local_route:
		if profile_recovery_cache: invalidated = planner.cache.size() + planner.cell_cache.size() + planner.smoothed_cell_cache.size()
		planner.clear_route_cache()
	var cleared := Time.get_ticks_usec() if profile_recovery_cache else 0
	if not local_route and not _try_formation_slot_exchange(unit, planner) and not _try_work_traffic_detour(unit, planner):
		if not (global_repath and String(unit["task"]) == "gather" and world.gathering_system.replan_work_approach(unit)):
			assign_unit_destination(unit, unit["destination"], false)
	if profile_recovery_cache:
		var mode := "global" if global_repath else "local"
		if not recovery_cache_counters.has(mode): recovery_cache_counters[mode] = {"calls":0,"invalidated":0,"clear_us":0,"total_us":0}
		var measurement: Dictionary = recovery_cache_counters[mode]
		measurement["calls"] += 1
		measurement["invalidated"] += invalidated
		measurement["clear_us"] += cleared - started
		measurement["total_us"] += Time.get_ticks_usec() - started


func _try_work_traffic_detour(unit: Dictionary, planner) -> bool:
	if String(unit["task"]) != "gather" and not (int(unit["formation_group_id"]) >= 0 and String(unit["task"]) in ["move", "attack_move"] and Vector2(unit["pos"]).distance_squared_to(unit["destination"]) < 64.0): return false
	var simulation_world = world
	var origin := Vector2(unit["pos"])
	var destination := Vector2(unit["destination"])
	var radius := float(unit["footprint_radius"])
	var domain := String(unit["movement_domain"])
	var restriction := int(unit["terrain_restriction"])
	var neighbors: Array = simulation_world.query_units_near(origin, maxf(4.0, radius * 6.0)).filter(func(other): return int(other["id"]) != int(unit["id"]) and String(other.get("movement_domain", "land")) == domain and float(other.get("hp", 0.0)) > 0.0)
	if neighbors.is_empty(): return false
	var yielding:=false
	if String(unit["task"])=="gather":
		var own_returning:=String(unit.get("gather_stage",""))=="returning"
		for other in neighbors:
			if int(other.get("team",0))!=int(unit["team"]) or String(other.get("task",""))!="gather" or String(other.get("gather_stage",""))=="harvesting" or other.get("path",[]).is_empty(): continue
			var other_returning:=String(other.get("gather_stage",""))=="returning"
			if (other_returning and not own_returning) or (other_returning==own_returning and int(unit["id"])>int(other["id"])): yielding=true; break
	if String(unit["task"])=="gather" and _try_local_work_route(unit,planner,neighbors): return true
	var tail_obstacles: Array=neighbors
	if yielding:
		# A carrier/older worker has right of way. The first retreat/side step
		# must clear every body, while its future return route may cross the
		# current position of the peer that will pass through the freed lane.
		tail_obstacles=neighbors.filter(func(other): return int(other.get("team",0))!=int(unit["team"]) or String(other.get("task",""))!="gather" or String(other.get("gather_stage",""))=="harvesting" or other.get("path",[]).is_empty())
	# Static A* cannot see working units. Repeating the same route through them
	# strands loaded boats and workers. Try a bounded local detour whose whole
	# route clears the nearby bodies, without changing the gather/deposit goal.
	var candidates: Array[Vector2] = []
	var forward := (destination - origin).normalized()
	for distance in ([1.0, 2.0, 3.0, 4.0, 6.0] if int(unit["formation_group_id"]) >= 0 else [1.0, 2.0, 3.0]):
		for angle in range(8):
			candidates.append(origin + forward.rotated(TAU * float(angle) / 8.0) * float(distance) * maxf(1.0, radius * 2.0))
	candidates.sort_custom(func(a, b): return origin.distance_to(a) + a.distance_to(destination) < origin.distance_to(b) + b.distance_to(destination))
	var kernel: Variant = null
	var planner_script: Variant = planner.get_script() if work_traffic_tick_native else null
	if planner_script != null and planner_script.resource_path == "res://scripts/pathfinder.gd" and planner.uses_native_kernel():
		var candidate_kernel = planner._native_kernel_for(domain, restriction)
		if candidate_kernel.get_script() == null and candidate_kernel.has_method("select_work_traffic_route"):
			kernel = candidate_kernel
	var first_candidate := 0
	var route_query := Callable(planner, "find_path").bind(domain, restriction, radius)
	while first_candidate < candidates.size():
		var started := Time.get_ticks_usec() if profile_work_traffic or compare_work_traffic_results else 0
		var selected: Dictionary = {}
		var native := kernel != null
		if native:
			selected = kernel.select_work_traffic_route(origin, destination, radius, float(unit.get("minimum_clearance", 0.06)), candidates, first_candidate, neighbors, tail_obstacles, route_query)
			if not bool(selected.get("supported", false)):
				work_traffic_counters["unsupported"] = int(work_traffic_counters.get("unsupported", 0)) + 1
				native = false
				kernel = null
		if not native:
			selected = _select_work_traffic_route_reference(unit, planner, origin, destination, radius, domain, restriction, candidates, first_candidate, neighbors, tail_obstacles)
		var prefix := "native" if native else "reference"
		work_traffic_counters[prefix + "_calls"] = int(work_traffic_counters.get(prefix + "_calls", 0)) + 1
		if started > 0:
			work_traffic_counters[prefix + "_us"] = int(work_traffic_counters.get(prefix + "_us", 0)) + Time.get_ticks_usec() - started
		for counter in ["candidate_tests", "tail_queries", "body_tests"]:
			work_traffic_counters[prefix + "_" + counter] = int(work_traffic_counters.get(prefix + "_" + counter, 0)) + int(selected.get(counter, 0))
		if native and compare_work_traffic_results:
			work_traffic_comparison_sequence += 1
			if work_traffic_comparison_sequence <= 8 or work_traffic_comparison_sequence % 64 == 0:
				var comparison_started := Time.get_ticks_usec()
				var reference := _select_work_traffic_route_reference(unit, planner, origin, destination, radius, domain, restriction, candidates, first_candidate, neighbors, tail_obstacles)
				work_traffic_counters["comparison_calls"] = int(work_traffic_counters.get("comparison_calls", 0)) + 1
				work_traffic_counters["comparison_us"] = int(work_traffic_counters.get("comparison_us", 0)) + Time.get_ticks_usec() - comparison_started
				if selected["path"] != reference["path"] or int(selected["index"]) != int(reference["index"]):
					work_traffic_counters["comparison_mismatches"] = int(work_traffic_counters.get("comparison_mismatches", 0)) + 1
					if not work_traffic_counters.has("first_mismatch"):
						work_traffic_counters["first_mismatch"] = {"unit":int(unit["id"]),"native_index":int(selected["index"]),"reference_index":int(reference["index"]),"native_path":selected["path"].duplicate(),"reference_path":reference["path"].duplicate()}
					selected = reference
					prefix = "reference_mismatch"
		var route: Array = selected["path"]
		if route.is_empty(): return false
		first_candidate = int(selected["index"]) + 1
		var prepared: Dictionary = simulation_world.navigation_service.register_resolved_path(int(unit["id"]), origin, destination, route, domain, restriction, "work_traffic_detour", radius)
		if assign_unit_destination(unit, destination, false, false, prepared):
			StuckRecovery.reset(unit)
			simulation_world.set_entity_field(unit, "diagnostic_reason", "work_traffic_detour")
			work_traffic_counters[prefix + "_routes"] = int(work_traffic_counters.get(prefix + "_routes", 0)) + 1
			return true
	return false


# The selector is pure with respect to the world. Both implementations return
# a route to the same caller, which applies it once and resumes after rejection.
func _select_work_traffic_route_reference(unit: Dictionary, planner, origin: Vector2, destination: Vector2, radius: float, domain: String, restriction: int, candidates: Array, first_candidate: int, neighbors: Array, tail_obstacles: Array) -> Dictionary:
	var candidate_tests := 0
	var tail_queries := 0
	for index in range(first_candidate, candidates.size()):
		candidate_tests += 1
		var point: Vector2 = candidates[index]
		if not planner.is_segment_walkable(origin, point, radius, domain, restriction) or not _work_segment_clear(unit, origin, point, neighbors): continue
		tail_queries += 1
		var route: Array[Vector2] = planner.find_path(point, destination, domain, restriction, radius)
		if route.is_empty() or route.back().distance_squared_to(destination) > 0.0144: continue
		var cursor := point
		var clear := true
		for waypoint in route:
			if not _work_segment_clear(unit, cursor, waypoint, tail_obstacles):
				clear = false
				break
			cursor = waypoint
		if not clear: continue
		route.push_front(point)
		return {"path":route, "index":index, "candidate_tests":candidate_tests, "tail_queries":tail_queries}
	return {"path":[], "index":candidates.size(), "candidate_tests":candidate_tests, "tail_queries":tail_queries}



static func _traffic_before(left: Array,right: Array) -> bool:
	if not is_equal_approx(float(left[2]),float(right[2])): return float(left[2])<float(right[2])
	var a:=Vector2i(left[0]); var b:=Vector2i(right[0])
	return a.y<b.y if a.y!=b.y else a.x<b.x

static func _traffic_push(heap: Array,entry: Array) -> void:
	heap.append(entry)
	var index:=heap.size()-1
	while index>0:
		var parent: int=(index-1)/2
		if not _traffic_before(entry,heap[parent]): break
		heap[index]=heap[parent]; index=parent
	heap[index]=entry

static func _traffic_pop(heap: Array) -> Array:
	var result: Array=heap[0]
	var tail: Array=heap.pop_back()
	if heap.is_empty(): return result
	var index:=0
	while index*2+1<heap.size():
		var child:=index*2+1
		if child+1<heap.size() and _traffic_before(heap[child+1],heap[child]): child+=1
		if not _traffic_before(heap[child],tail): break
		heap[index]=heap[child]; index=child
	heap[index]=tail
	return result

func _try_local_work_route(unit: Dictionary,planner,neighbors: Array) -> bool:
	# Search only the immediate traffic neighbourhood. Static A* alone routes
	# through harvesting bodies; one straight detour waypoint cannot get around
	# a concave group of workers in a forest/mineral passage.
	var origin:=Vector2(unit["pos"]); var destination:=Vector2(unit["destination"])
	var radius:=float(unit["footprint_radius"]); var domain:=String(unit["movement_domain"]); var restriction:=int(unit["terrain_restriction"])
	var goal:=destination
	if origin.distance_to(goal)>5.0:
		var leg:=Vector2(unit["target"])-origin
		if leg.length()<0.2: return false
		goal=origin+leg.normalized()*minf(5.0,leg.length())
	var local := _local_traffic_path(unit, planner, neighbors, goal)
	if local.is_empty(): return false
	if goal.distance_squared_to(destination)>0.0001:
		var tail: Array[Vector2]=planner.find_path(goal,destination,domain,restriction,radius)
		if tail.is_empty() or tail.back().distance_squared_to(destination)>0.0144: return false
		local.append_array(tail)
	var prepared: Dictionary=world.navigation_service.register_resolved_path(int(unit["id"]),origin,destination,local,domain,restriction,"work_traffic_local",radius)
	if assign_unit_destination(unit,destination,false,false,prepared):
		StuckRecovery.reset(unit); world.set_entity_field(unit,"diagnostic_reason","work_traffic_local"); return true
	return false


func _local_traffic_path(unit: Dictionary, planner, neighbors: Array, goal: Vector2) -> Array[Vector2]:
	var origin := Vector2(unit["pos"])
	var radius := float(unit["footprint_radius"])
	var domain := String(unit["movement_domain"])
	var restriction := int(unit["terrain_restriction"])
	var probe: Variant=world.tick_pipeline.performance_probe
	var started:=Time.get_ticks_usec() if probe!=null else 0
	var local: Array[Vector2]=[]
	var native_used:=false
	if native_local_traffic_enabled and planner.uses_native_kernel():
		var kernel=planner._native_kernel_for(domain,restriction)
		if kernel.has_method("find_local_traffic_path"):
			native_used=true
			for point in kernel.find_local_traffic_path(origin,goal,radius,float(unit.get("minimum_clearance",0.06)),neighbors): local.append(point)
	if not native_used: local=_local_work_path_reference(unit,planner,neighbors,goal)
	if probe!=null: probe.observe_microseconds("navigation.local_traffic.search",Time.get_ticks_usec()-started)
	return local


func _try_formation_transit_detour(unit: Dictionary, planner) -> bool:
	if int(unit["formation_group_id"]) < 0 or String(unit["task"]) not in ["move", "attack_move"]: return false
	var origin := Vector2(unit["pos"])
	var destination := Vector2(unit["destination"])
	if origin.distance_squared_to(destination) < 64.0: return false
	var route: Array = unit["path"]
	var next := int(unit["path_index"])
	if next < 0 or next >= route.size(): return false
	var radius := float(unit["footprint_radius"])
	var domain := String(unit["movement_domain"])
	var blockers: Array = []
	for peer in world.query_units_near(origin, 6.0 + radius):
		if int(peer["id"]) == int(unit["id"]) or float(peer["hp"]) <= 0.0 or String(peer.get("movement_domain", "land")) != domain: continue
		if not peer.get("path", []).is_empty() or Vector2(peer.get("actual_velocity", Vector2.ZERO)).length_squared() > 0.0001: continue
		if int(peer["team"]) == int(unit["team"]) or world.is_entity_visible_to(int(unit["team"]), peer):
			blockers.append(peer)
	if blockers.is_empty() or _work_segment_clear(unit, origin, unit["target"], blockers): return false

	# Rejoin the existing corridor beyond the obstruction. The untouched
	# remainder still leads through the same gates to the same reserved slot.
	var rejoin := origin
	var remaining := 5.0
	while next < route.size() and remaining > 0.001:
		var waypoint := Vector2(route[next])
		var length := rejoin.distance_to(waypoint)
		if length > remaining:
			rejoin = rejoin.move_toward(waypoint, remaining)
			break
		rejoin = waypoint
		remaining -= length
		next += 1
	var local := _local_traffic_path(unit, planner, blockers, rejoin)
	if local.is_empty(): return false
	var prefix_length := local.size()
	for index in range(next, route.size()): local.append(Vector2(route[index]))
	var prepared: Dictionary = world.navigation_service.register_resolved_path(int(unit["id"]), origin, destination, local, domain, int(unit["terrain_restriction"]), "formation_traffic", radius)
	if not assign_unit_destination(unit, destination, false, false, prepared): return false
	unit["formation_traffic_prefix"] = prefix_length
	StuckRecovery.reset(unit)
	return true


func resume_failed_formation_members(group, members: Array) -> void:
	if String(group.order_kind) not in ["move", "attack_move"]: return
	var attempts := 0
	var planner: Variant = null
	var planner_team := -1
	for peer in members:
		var order: Dictionary = peer.get("components", {}).get("order", {})
		if not order.get("queued", []).is_empty() or not bool(order.get("completed", false)): continue
		if order.get("completion_reason", "") not in ["no_path", "no_group_route"] or order.get("type", "") not in ["move", "attack_move"]: continue
		var slot: Dictionary = group.slot_for(int(peer["id"]))
		var home: Variant = peer.get("formation_home")
		if slot.is_empty() or not home is Vector2: continue
		var team := int(peer["team"])
		if planner == null or planner_team != team:
			planner = knowledge.planner(world, team)
			planner_team = team
		var stamp := Vector2i(planner.grid.cache_epoch, planner.grid.revision)
		var reservations = world.destination_reservations
		if peer.get("formation_recovery_grid") == stamp and peer.has("formation_recovery_blockers") and not reservations.released_blocker(peer["formation_recovery_blockers"]): continue
		attempts += 1
		var radius := float(peer["footprint_radius"])
		var domain := String(peer["movement_domain"])
		var restriction := int(peer["terrain_restriction"])
		var origin := Vector2(peer["pos"])
		var blockers := {}
		var goal: Variant = reservations.reachable_slot(int(peer["id"]), origin, home, radius, planner, domain, restriction, blockers)
		world.set_entity_fields(peer, {"formation_recovery_grid":stamp, "formation_recovery_blockers":blockers if goal == null else {}})
		if goal is Vector2 and origin.distance_squared_to(goal) > 0.001225:
			var route: Array[Vector2] = planner.find_path(origin, goal, domain, restriction, radius)
			if not route.is_empty() and route.back().distance_squared_to(goal) <= 0.001225:
				var prepared: Dictionary = world.navigation_service.register_resolved_path(int(peer["id"]), origin, goal, route, domain, restriction, "formation_recovery", radius)
				world.set_entity_field(peer, "task", group.order_kind)
				world.begin_entity_order(peer, group.order_kind, -1, goal, false)
				if assign_unit_destination(peer, goal, true, false, prepared):
					world.set_entity_field(peer, "formation_home", goal)
					slot["world"] = goal
					if group.order_kind == "attack_move": world.set_entity_field(peer, "attack_move_destination", goal)
		if attempts >= 2: break


func _local_work_path_reference(unit: Dictionary,planner,neighbors: Array,goal: Vector2) -> Array[Vector2]:
	var origin:=Vector2(unit["pos"])
	var radius:=float(unit["footprint_radius"]); var domain:=String(unit["movement_domain"]); var restriction:=int(unit["terrain_restriction"])
	var step:=maxf(0.5,radius)
	var open: Array=[[Vector2i.ZERO,0.0,origin.distance_to(goal)]]; var previous: Dictionary={}; var costs: Dictionary={Vector2i.ZERO:0.0}; var expanded:=0
	var directions: Array=[Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1),Vector2i(1,-1)]
	while not open.is_empty() and expanded<256:
		var entry:=_traffic_pop(open)
		var cell:=Vector2i(entry[0])
		# Improved cells receive a new immutable heap entry. An obsolete entry
		# does not spend the same 256-expansion budget a second time.
		if float(entry[1])!=float(costs[cell]): continue
		var point:=origin+Vector2(cell)*step; expanded+=1
		if cell!=Vector2i.ZERO and point.distance_to(goal)<=1.5 and planner.is_segment_walkable(point,goal,radius,domain,restriction) and _work_segment_clear(unit,point,goal,neighbors):
			var local: Array[Vector2]=[goal]
			var cursor:=cell
			while cursor!=Vector2i.ZERO:
				local.push_front(origin+Vector2(cursor)*step); cursor=previous[cursor]
			return local
		for direction in directions:
			var next: Vector2i=cell+direction
			if abs(next.x)>12 or abs(next.y)>12: continue
			var candidate:=origin+Vector2(next)*step; var cost:=float(costs[cell])+Vector2(direction).length()*step
			if costs.has(next) and float(costs[next])<=cost: continue
			if not planner.is_segment_walkable(point,candidate,radius,domain,restriction) or not _work_segment_clear(unit,point,candidate,neighbors): continue
			costs[next]=cost; previous[next]=cell
			_traffic_push(open,[next,cost,cost+candidate.distance_to(goal)])
	return []


func _work_segment_clear(unit: Dictionary, start: Vector2, finish: Vector2, neighbors: Array) -> bool:
	for other in neighbors:
		var center := Vector2(other["pos"])
		var separation := float(unit["footprint_radius"]) + float(other["footprint_radius"]) + maxf(float(unit.get("minimum_clearance",0.06)),float(other.get("minimum_clearance",0.06)))
		# A previously touching body may retreat, but must not penetrate farther.
		var minimum := minf(separation * separation, start.distance_squared_to(center))
		if center.distance_squared_to(Geometry2D.get_closest_point_to_segment(center, start, finish)) < minimum - 0.0001: return false
	return true


func _integrate_unit_motion(unit: Dictionary, delta: float, movement_reason: String, simulation_world) -> void:
	var start_position: Vector2 = unit["pos"]
	var difference: Vector2 = unit["target"] - start_position
	if Vector2(unit["desired_velocity"]).length_squared() > 0.000001:
		simulation_world.set_entity_field(unit, "desired_facing", facing_for_vector(unit["desired_velocity"]))
	if movement_reason != "":
		simulation_world.set_entity_field(unit, "diagnostic_reason", movement_reason)
	var step: Vector2 = unit["actual_velocity"] * delta
	if step.length_squared() >= difference.length_squared() and step.dot(difference) > 0.0:
		simulation_world.set_entity_field(unit, "pos", unit["target"])
	else:
		simulation_world.set_entity_field(unit, "pos", unit["pos"] + (step))
	var position: Vector2 = unit["pos"]
	if position.x < 0.5 or position.y < 0.5 or position.x > float(simulation_world.map_size.x) - 0.5 or position.y > float(simulation_world.map_size.y) - 0.5:
		simulation_world.set_entity_field(unit, "pos", Coordinates.clamp_world(position, simulation_world.map_size))
	if simulation_world.terrain_elevation.nonzero_vertex_count > 0:
		simulation_world.set_entity_field(unit, "elevation", simulation_world.elevation_at(unit["pos"]))
	elif float(unit["elevation"]) != 0.0:
		simulation_world.set_entity_field(unit, "elevation", 0.0)
	var actual_displacement: Vector2 = unit["pos"] - start_position
	simulation_world.set_entity_field(unit, "actual_velocity", actual_displacement / delta if delta > 0.0 else Vector2.ZERO)
	var actual_displacement_squared := actual_displacement.length_squared()
	if actual_displacement_squared > 0.000001:
		var movement_facing := facing_for_vector(actual_displacement)
		simulation_world.set_entity_field(unit, "movement_facing", movement_facing)
		simulation_world.set_entity_field(unit, "facing", movement_facing)


func _advance_formation_corner(unit: Dictionary, planner) -> void:
	if int(unit["formation_group_id"]) < 0 or String(unit["task"]) not in ["move", "attack_move"]: return
	var path: Array = unit["path"]
	var next_index := int(unit["path_index"]) + 1
	if next_index <= int(unit.get("formation_traffic_prefix", 0)): return
	if next_index >= path.size() or Vector2(unit["pos"]).distance_squared_to(unit["target"]) > 2.0 * 2.0: return
	# Intermediate gates must not require every rank to touch the same exact
	# point. Advance only when the entire swept footprint to the next leg is
	# clear; the final reserved destination still uses the precise arrival rule.
	if not planner.is_segment_walkable(unit["pos"], path[next_index], float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])): return
	if next_index == path.size() - 1 and Vector2(unit["pos"]).distance_squared_to(unit["destination"]) < 64.0:
		# Preserve an actual detour around members already standing at home.
		# Terrain visibility alone would cut the corner back through their bodies.
		var neighbors: Array = world.query_units_near(unit["pos"], 8.0 + float(unit["footprint_radius"]))
		neighbors = neighbors.filter(func(other): return int(other["id"]) != int(unit["id"]) and String(other["movement_domain"]) == String(unit["movement_domain"]))
		if not _work_segment_clear(unit, unit["pos"], path[next_index], neighbors): return
	world.set_entity_field(unit, "path_index", next_index)
	world.set_entity_field(unit, "target", path[next_index])


# Legacy saves can contain a ship whose centre is legal but whose hull
# overlaps the shore. Permit a gradual retreat only through already-overlapped
# cells; this cannot cross a new wall, terrain boundary or mobile obstacle.
func _escape_invalid_footprint(unit: Dictionary, delta: float) -> Vector2:
	var simulation_world = world
	var grid = simulation_world.navigation_grid
	var planner = simulation_world.pathfinder
	var origin := Vector2(unit["pos"])
	var radius := float(unit["footprint_radius"])
	var domain := String(unit["movement_domain"])
	var restriction := int(unit["terrain_restriction"])
	if not planner.is_position_walkable(origin, 0.0, domain, restriction) or planner.is_position_walkable(origin, radius, domain, restriction):
		return Vector2.ZERO
	var difference := Vector2(unit["target"]) - origin
	var velocity := difference.normalized() * minf(float(unit["speed"]), difference.length() / maxf(0.0001, delta))
	var neighbors: Array = simulation_world.query_units_near(origin, radius + 2.0).filter(func(other): return int(other["id"]) != int(unit["id"]))
	velocity = MobileCollision.constrain(unit, velocity, neighbors, delta)
	var next := origin + velocity * delta
	if not grid.is_footprint_escape_walkable_for(origin, next, radius, domain, restriction): return Vector2.ZERO
	return velocity


func face_unit_toward(unit: Dictionary, target: Vector2) -> void:
	var difference: Vector2 = target - unit["pos"]
	if difference.length_squared() > 0.0001:
		var action_facing := facing_for_vector(difference)
		world.set_entity_field(unit, "desired_facing", action_facing)
		world.set_entity_field(unit, "action_facing", action_facing)
		world.set_entity_field(unit, "facing", action_facing)


func restore_formation_facing(unit: Dictionary) -> void:
	var forward: Vector2 = unit.get("formation_forward", Vector2.ZERO)
	if forward.length_squared() > 0.0001:
		var formation_front := int(unit.get("formation_facing", facing_for_vector(forward)))
		world.set_entity_field(unit, "desired_facing", formation_front)
		world.set_entity_field(unit, "action_facing", formation_front)
		world.set_entity_field(unit, "facing", formation_front)


func facing_for_vector(direction: Vector2) -> int:
	return FacingConvention.logical_for_world(direction)


func assign_command_move(selected: Array, target: Vector2) -> bool:
	var resolved_count := 0
	for unit in selected:
		world.conversion_system.cancel(unit, "new_order")
		world.healing_system.cancel(unit, "new_order")
		if world.entity_is_worker(unit):
			world.worker_role_system.clear(unit)
			world.set_entity_field(unit, "pending_hunt_target_id", -1)
		world.release_resource_approach_slot(unit)
		world.release_building_approach_slot(unit)
		world.set_entity_field(unit, "gather_stage", "none")
		world.set_entity_field(unit, "resource_id", -1)
		world.set_entity_field(unit, "target_building_id", -1)
		world.set_entity_field(unit, "task", "move")
		world.set_entity_field(unit, "target_id", -1)
		world.clear_combat_intent(unit)
		world.begin_entity_order(unit, "move", -1, target, false)
	# Release the complete selection before assigning new endpoints so obsolete
	# slots cannot fragment a mass command.
	for unit in selected:
		world.destination_reservations.release(int(unit["id"]))
	var reserved_by_id: Dictionary = {}
	for unit in selected:
		var requested := Coordinates.clamp_world(target, world.map_size)
		var reserved: Vector2 = world.destination_reservations.reserve(int(unit["id"]), requested, float(unit.get("footprint_radius", 0.3)), knowledge.planner(world, int(unit.get("team", 0))).grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
		world.set_entity_field(unit, "reserved_destination", reserved)
		reserved_by_id[int(unit["id"])] = reserved
	var prevalidated_direct := _group_move_envelope_is_open(selected, reserved_by_id)
	var prepared: Array = []
	# Reserve the same ordered request IDs in live and sequential/replay worlds.
	# find_paths_batch itself selects workers or the sequential implementation;
	# bypassing this stage interleaves fallback queries with later units' IDs.
	if not prevalidated_direct and selected.size() >= 4:
		var planner = knowledge.planner(world, int(selected[0].get("team", 0)))
		var same_planner := true
		var requests: Array = []
		for unit in selected:
			if knowledge.planner(world, int(unit.get("team", 0))) != planner:
				same_planner = false
				break
			requests.append({"entity_id": int(unit["id"]), "start": unit["pos"], "goal": Vector2(reserved_by_id[int(unit["id"])]), "domain": String(unit.get("movement_domain", "land")), "restriction": int(unit.get("terrain_restriction", -1)), "clearance": float(unit.get("footprint_radius", 0.3)), "purpose": "replan" if not unit.get("path", []).is_empty() else String(unit.get("task", "move"))})
		if same_planner:
			prepared = world.navigation_service.request_paths(requests, planner, world.task_coordinator)
	var selected_index := 0
	for unit in selected:
		var prepared_result: Dictionary = prepared[selected_index] if not prepared.is_empty() else {}
		selected_index += 1
		if not assign_unit_destination(unit, Vector2(reserved_by_id[int(unit["id"])]), false, prevalidated_direct, prepared_result):
			world.complete_entity_order(unit, "no_path")
		else:
			resolved_count += 1
	return resolved_count > 0


func _group_move_envelope_is_open(selected: Array, reserved_by_id: Dictionary) -> bool:
	if selected.size() < 2 or reserved_by_id.size() != selected.size():
		return false
	var movement_domain := String(selected[0].get("movement_domain", "land"))
	var restriction_id := int(selected[0].get("terrain_restriction", -1))
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var maximum_radius := 0.0
	for unit in selected:
		if String(unit.get("movement_domain", "land")) != movement_domain or int(unit.get("terrain_restriction", -1)) != restriction_id:
			return false
		var destination: Vector2 = reserved_by_id[int(unit["id"])]
		for position in [Vector2(unit["pos"]), destination]:
			minimum = Vector2(minf(minimum.x, position.x), minf(minimum.y, position.y))
			maximum = Vector2(maxf(maximum.x, position.x), maxf(maximum.y, position.y))
		maximum_radius = maxf(maximum_radius, float(unit.get("footprint_radius", 0.3)))
	return world.navigation_grid.is_world_rect_walkable_for(minimum, maximum, maximum_radius, movement_domain, restriction_id)


func _envelope_survives_grid_change(open_envelope: Dictionary) -> bool:
	var envelope_revision := int(open_envelope.get("grid_revision", -1))
	var region: Variant = world.navigation_grid.change_region_since(envelope_revision)
	if region == null:
		return false
	var changed_region: Rect2 = region
	if changed_region.has_area():
		var margin := 3.0
		var minimum := Vector2(open_envelope.get("minimum", Vector2.ZERO))
		var maximum := Vector2(open_envelope.get("maximum", Vector2.ZERO))
		var envelope_rect := Rect2(minimum - Vector2.ONE * margin, (maximum - minimum) + Vector2.ONE * 2.0 * margin)
		if envelope_rect.intersects(changed_region):
			return false
	open_envelope["grid_revision"] = world.navigation_grid.revision
	return true


func assign_command_attack_move(selected: Array, target: Vector2) -> bool:
	var resolved_count := 0
	for unit in selected:
		world.conversion_system.cancel(unit, "new_order")
		world.healing_system.cancel(unit, "new_order")
		if world.entity_is_worker(unit):
			world.worker_role_system.clear(unit)
			world.set_entity_field(unit, "pending_hunt_target_id", -1)
		world.release_resource_approach_slot(unit)
		world.release_building_approach_slot(unit)
		world.set_entity_field(unit, "gather_stage", "none")
		world.set_entity_field(unit, "resource_id", -1)
		world.set_entity_field(unit, "target_building_id", -1)
		world.set_entity_field(unit, "task", "attack_move")
		world.set_entity_field(unit, "target_id", -1)
		world.clear_combat_intent(unit)
		world.set_entity_field(unit, "attack_move_destination", target)
		world.begin_entity_order(unit, "attack_move", -1, target, false)
		if not assign_unit_destination(unit, target):
			world.set_entity_field(unit, "task", "idle")
			world.complete_entity_order(unit, "no_path")
		else:
			resolved_count += 1
	return resolved_count > 0


func assign_unit_destination(unit: Dictionary, destination: Vector2, reserve_destination: bool = true, prevalidated_direct: bool = false, prepared_result: Dictionary = {}) -> bool:
	unit.erase("formation_traffic_prefix")
	unit.erase("formation_recovery_grid")
	unit.erase("formation_recovery_blockers")
	world.erase_entity_field(unit, "formation_steering_target")
	unit.erase("_formation_path_cache")
	world.open_movement_envelopes_by_id.erase(int(unit["id"]))
	if not OrderPipeline.is_active(unit):
		world.begin_entity_order(unit, String(unit.get("task", "move")), int(unit.get("target_id", -1)), destination, String(unit.get("task", "")) in ["attack", "gather"])
	world.transition_entity_order(unit, OrderPipeline.PLAN_PATH)
	var planner = knowledge.planner(world, int(unit.get("team", 0)))
	var clamped_destination := Coordinates.clamp_world(destination, world.map_size)
	if reserve_destination:
		clamped_destination = world.destination_reservations.reserve(int(unit["id"]), clamped_destination, float(unit.get("footprint_radius", 0.3)), planner.grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
		world.set_entity_field(unit, "reserved_destination", clamped_destination)
	world.set_entity_field(unit, "destination", clamped_destination)
	var path_purpose := "replan" if not unit.get("path", []).is_empty() else String(unit.get("task", "move"))
	var path_result: Dictionary
	if not prepared_result.is_empty():
		path_result = prepared_result
	elif prevalidated_direct:
		path_result = world.navigation_service.register_prevalidated_direct_path(int(unit["id"]), unit["pos"], unit["destination"], String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), path_purpose, float(unit.get("footprint_radius", 0.3)))
	else:
		path_result = world.navigation_service.request_path(int(unit["id"]), unit["pos"], unit["destination"], String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), path_purpose, float(unit.get("footprint_radius", 0.3)), planner)
	if path_result["path"].is_empty() and String(unit.get("task", "")) in ["move", "attack_move"]:
		var domain := String(unit.get("movement_domain", "land"))
		var restriction := int(unit.get("terrain_restriction", -1))
		var radius := float(unit.get("footprint_radius", 0.3))
		var group_id := int(unit.get("formation_group_id", -1))
		var reachable: Variant = null
		if group_id >= 0:
			reachable = world.destination_reservations.reachable_slot(int(unit["id"]), unit["pos"], clamped_destination, radius, planner, domain, restriction)
		else:
			var cell: Vector2i = planner.nearest_reachable(Vector2i(Vector2(unit["pos"]).floor()), Vector2i(clamped_destination.floor()), domain, restriction, radius)
			if cell.x >= 0: reachable = Vector2(cell) + Vector2(0.5, 0.5)
		if reachable is Vector2:
			clamped_destination = reachable
			world.destination_reservations.release(int(unit["id"]))
			if group_id >= 0:
				clamped_destination = world.destination_reservations.reserve(int(unit["id"]), clamped_destination, radius, planner.grid, group_id, domain, restriction)
			world.set_entity_field(unit, "destination", clamped_destination)
			world.set_entity_field(unit, "reserved_destination", clamped_destination)
			path_result = world.navigation_service.request_path(int(unit["id"]), unit["pos"], clamped_destination, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), path_purpose, float(unit.get("footprint_radius", 0.3)), planner)
	world.set_entity_field(unit, "path_knowledge_revision", planner.grid.revision)
	world.set_entity_field(unit, "path_request_id", int(path_result["request_id"]))
	world.set_entity_field(unit, "path_status", String(path_result["status"]))
	world.set_entity_field(unit, "path_grid_revision", int(path_result["grid_revision"]))
	world.set_entity_field(unit, "path", path_result["path"])
	world.set_entity_field(unit, "path_index", 0)
	if unit["path"].is_empty():
		world.set_entity_field(unit, "target", unit["pos"])
		if Vector2(unit["pos"]).distance_squared_to(clamped_destination) <= 0.001225:
			world.set_entity_field(unit, "path_status", "arrived")
			if String(unit["task"]) in ["move", "attack_move"]:
				world.set_entity_field(unit, "task", "idle")
				release_unit_destination(unit)
				world.complete_entity_order(unit, "destination_reached")
				restore_formation_facing(unit)
			else:
				world.transition_entity_order(unit, OrderPipeline.FACE_TARGET)
			return true
		# Newly explored obstacles can invalidate one optimistic work slot while
		# other positions around the known resource remain reachable.
		if String(unit["task"]) == "gather" and String(unit.get("gather_stage", "")) == "approaching" and prepared_result.is_empty():
			var resource: Variant = world.find_resource(int(unit.get("resource_id", -1)))
			if resource != null:
				world.release_resource_approach_slot(unit)
				if world.gathering_system.prepare_group_gather_approach(unit, resource):
					return true
		# Work orders need the same terminal failure as movement orders. Leaving
		# a failed gather/build active retries A* every tick and holds its slot.
		world.halt_unit(unit, "no_path")
		world.set_entity_field(unit, "path_status", "unreachable")
		world.set_entity_field(unit, "diagnostic_reason", "no_path")
		return false
	world.set_entity_field(unit, "target", unit["path"][0])
	world.set_entity_field(unit, "diagnostic_reason", "")
	world.transition_entity_order(unit, OrderPipeline.MOVE_INTO_RANGE)
	return true


func assign_unit_waypoints(unit: Dictionary, waypoints: Array[Vector2], destination: Vector2, prevalidated_direct: bool = false, open_envelope: Dictionary = {}) -> bool:
	unit.erase("formation_traffic_prefix")
	unit.erase("formation_recovery_grid")
	unit.erase("formation_recovery_blockers")
	var simulation_world = world
	simulation_world.open_movement_envelopes_by_id.erase(int(unit["id"]))
	if not OrderPipeline.is_active(unit, "move"):
		simulation_world.begin_entity_order(unit, "move", -1, destination, false)
	simulation_world.transition_entity_order(unit, OrderPipeline.PLAN_PATH)
	var planner = knowledge.planner(simulation_world, int(unit.get("team", 0)))
	var requested_destination := Coordinates.clamp_world(destination, simulation_world.map_size)
	var reserved_destination: Vector2 = simulation_world.destination_reservations.reserve(int(unit["id"]), requested_destination, float(unit.get("footprint_radius", 0.3)), planner.grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
	var direct_segments_allowed: bool = prevalidated_direct and reserved_destination.is_equal_approx(requested_destination)
	simulation_world.set_entity_field(unit, "reserved_destination", reserved_destination)
	simulation_world.set_entity_field(unit, "destination", reserved_destination)
	var targets := waypoints.duplicate()
	if targets.is_empty() or targets[targets.size() - 1].distance_squared_to(reserved_destination) > 0.0001:
		targets.append(reserved_destination)
	else:
		targets[targets.size() - 1] = reserved_destination
	var combined: Array[Vector2] = []
	var cursor: Vector2 = unit["pos"]
	for target in targets:
		var clamped_target := Coordinates.clamp_world(target, simulation_world.map_size)
		# A duplicate waypoint needs no query. An empty zero-length query would
		# otherwise overwrite the last successful segment's navigation status.
		if cursor.distance_squared_to(clamped_target) <= 0.0001:
			continue
		var path_result: Dictionary
		if direct_segments_allowed:
			path_result = simulation_world.navigation_service.register_prevalidated_direct_path(int(unit["id"]), cursor, clamped_target, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), "formation_segment", float(unit.get("footprint_radius", 0.3)))
		else:
			path_result = simulation_world.navigation_service.request_path(int(unit["id"]), cursor, clamped_target, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), "formation_segment", float(unit.get("footprint_radius", 0.3)), planner)
		simulation_world.set_entity_field(unit, "path_knowledge_revision", planner.grid.revision)
		simulation_world.set_entity_field(unit, "path_request_id", int(path_result["request_id"]))
		simulation_world.set_entity_field(unit, "path_status", String(path_result["status"]))
		simulation_world.set_entity_field(unit, "path_grid_revision", int(path_result["grid_revision"]))
		var segment: Array[Vector2] = path_result["path"]
		if segment.is_empty():
			return _fail_group_route(unit)
		for waypoint in segment:
			if combined.is_empty() or combined[combined.size() - 1].distance_squared_to(waypoint) > 0.0001:
				combined.append(waypoint)
		# Endpoint resolution may move a blocked intermediate target. The next
		# segment must start at the actual endpoint to keep the route continuous.
		cursor = segment.back()
	# Publish only complete routes. A reachable prefix or a substituted final
	# endpoint cannot fulfil the member's reserved formation destination.
	if cursor.distance_squared_to(reserved_destination) > 0.001225:
		return _fail_group_route(unit)
	simulation_world.set_entity_field(unit, "path", combined)
	simulation_world.set_entity_field(unit, "path_index", 0)
	if combined.is_empty():
		simulation_world.set_entity_field(unit, "target", unit["pos"])
		simulation_world.set_entity_field(unit, "task", "idle")
		simulation_world.set_entity_field(unit, "path_status", "arrived")
		simulation_world.set_entity_field(unit, "diagnostic_reason", "")
		simulation_world.complete_entity_order(unit, "destination_reached")
		restore_formation_facing(unit)
		return true
	if direct_segments_allowed and bool(open_envelope.get("open", false)):
		simulation_world.open_movement_envelopes_by_id[int(unit["id"])] = open_envelope
	simulation_world.set_entity_field(unit, "target", combined[0])
	simulation_world.set_entity_field(unit, "diagnostic_reason", "group_corridor" if waypoints.size() > 1 else "")
	simulation_world.transition_entity_order(unit, OrderPipeline.MOVE_INTO_RANGE)
	return true


func _fail_group_route(unit: Dictionary) -> bool:
	# A formation slot can lie beyond an impassable edge. Keep the manual move
	# intent and approach its reachable boundary instead of dropping the order.
	if String(unit.get("task", "")) in ["move", "attack_move"]:
		return assign_unit_destination(unit, Vector2(unit["destination"]), false)
	world.halt_unit(unit, "no_group_route")
	world.set_entity_field(unit, "path_status", "unreachable")
	world.set_entity_field(unit, "diagnostic_reason", "no_group_route")
	return false


func ensure_navigation_destination(unit: Dictionary, destination: Vector2) -> void:
	var previous_destination: Vector2 = unit.get("destination", unit["pos"])
	if previous_destination.distance_squared_to(destination) <= 0.25 and not unit.get("path", []).is_empty():
		return
	var path: Array = unit.get("path", [])
	var path_index := int(unit.get("path_index", 0))
	if not path.is_empty() and path_index >= 0 and path_index < path.size() and int(unit.get("formation_group_id", -1)) < 0 and not bool(unit.get("formation_shared_motion", false)) and Vector2i(previous_destination.floor()) == Vector2i(destination.floor()) and Vector2i(Vector2(path.back()).floor()) == Vector2i(destination.floor()):
		var planner = knowledge.planner(world, int(unit.get("team", 0)))
		var final_segment_origin: Vector2 = unit["pos"] if path_index == path.size() - 1 else path[-2]
		if int(unit.get("path_knowledge_revision", -1)) == int(planner.grid.revision) and planner.is_segment_walkable(final_segment_origin, destination, float(unit.get("footprint_radius", 0.3)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))):
			# A same-cell endpoint adjustment can still cut an obstacle corner.
			# Reuse the route only when its new incoming segment remains clear.
			var updated: Array = path.duplicate()
			updated[updated.size() - 1] = destination
			world.set_entity_field(unit, "path", updated)
			world.set_entity_field(unit, "destination", destination)
			if path_index == updated.size() - 1:
				world.set_entity_field(unit, "target", destination)
			world.open_movement_envelopes_by_id.erase(int(unit["id"]))
			unit.erase("_formation_path_cache")
			return
	assign_unit_destination(unit, destination, false)


func stop_unit_motion(unit: Dictionary, reset_progress: bool = true) -> void:
	world.open_movement_envelopes_by_id.erase(int(unit["id"]))
	release_unit_destination(unit)
	world.set_entity_field(unit, "path", [])
	unit.erase("_formation_path_cache")
	world.erase_entity_field(unit, "formation_steering_target")
	world.set_entity_field(unit, "path_index", 0)
	world.set_entity_field(unit, "path_status", "idle")
	world.set_entity_field(unit, "target", unit["pos"])
	world.set_entity_field(unit, "destination", unit["pos"])
	world.set_entity_field(unit, "actual_velocity", Vector2.ZERO)
	world.set_entity_field(unit, "desired_velocity", Vector2.ZERO)
	if reset_progress:
		StuckRecovery.reset(unit)


func release_unit_destination(unit: Dictionary) -> void:
	world.destination_reservations.release(int(unit.get("id", -1)))
	world.open_movement_envelopes_by_id.erase(int(unit.get("id", -1)))
	world.set_entity_field(unit, "reserved_destination", null)


func _formation_yield_velocity(unit: Dictionary, neighbors: Array, delta: float) -> Variant:
	var simulation_world = world
	var probe: Variant = simulation_world.tick_pipeline.performance_probe
	var use_native: bool = native_formation_yield_enabled and native_formation_yield_supported and native_mobile_collision_enabled and native_collision_supported and simulation_world.pathfinder.uses_native_kernel()
	if profile_formation_yield_alternatives and probe != null:
		formation_yield_profile_sequence += 1
		use_native = use_native and formation_yield_profile_sequence % 2 == 0
	var started := Time.get_ticks_usec() if probe != null else 0
	if use_native:
		assert(simulation_world.read_generation_pins == 0, "Pinned observation generation is immutable")
		var result: Vector3 = integration_kernel.formation_yield_velocity(unit, neighbors, delta, simulation_world.pathfinder)
		if result.z >= 0.0:
			if probe != null: probe.observe_microseconds("simulation.movement.yield.native", Time.get_ticks_usec() - started)
			return Vector2(result.x, result.y) if result.z > 0.0 else null
	var result: Variant = _formation_yield_velocity_script(unit, neighbors, delta)
	if probe != null: probe.observe_microseconds("simulation.movement.yield.script", Time.get_ticks_usec() - started)
	return result


func _formation_yield_velocity_script(unit: Dictionary, neighbors: Array, delta: float) -> Variant:
	var blocker: Variant = null
	for other in neighbors:
		if int(other["formation_group_id"]) != int(unit["formation_group_id"]) or int(other["id"]) >= int(unit["id"]) or int(other["stuck_ticks"]) < 4: continue
		if Vector2(other["pos"]).distance_to(unit["pos"]) > 1.5: continue
		if blocker == null or int(other["id"]) < int(blocker["id"]): blocker = other
	if blocker == null: return null
	var watch: Dictionary = unit.get("navigation_progress", {})
	if watch.is_empty() or int(watch.get("formation_yield_ticks", 0)) >= 1200: return null
	var backwards := (Vector2(unit["pos"]) - Vector2(unit["destination"])).normalized()
	var speed := float(unit["speed"]) * float(unit["cohesion_speed_scale"])
	var simulation_world = world
	var planner = simulation_world.pathfinder
	for angle in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0]:
		var requested := backwards.rotated(angle) * speed
		var velocity: Vector2 = integration_kernel.constrain_mobile_velocity(unit, requested, neighbors, delta) if native_mobile_collision_enabled and native_collision_supported else MobileCollision.constrain(unit, requested, neighbors, delta)
		if velocity.length_squared() < speed * speed * 0.1: continue
		var finish := Vector2(unit["pos"]) + velocity * delta
		if planner.is_segment_walkable(unit["pos"], finish, float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])):
			watch["formation_yield_ticks"] = int(watch.get("formation_yield_ticks", 0)) + 1
			return velocity
	return null


func _try_formation_slot_exchange(unit: Dictionary, planner) -> bool:
	var group = world.formation_groups_view.get(int(unit["formation_group_id"]))
	if group == null or unit.get("formation_home") == null or Vector2(unit["pos"]).distance_squared_to(unit["formation_home"]) > 64.0: return false
	var home := Vector2(unit["formation_home"])
	var candidates: Array = world.query_units_near(home, 8.0)
	candidates.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	for other in candidates:
		if int(other["id"]) == int(unit["id"]) or float(other["hp"]) <= 0.0 or int(other["formation_group_id"]) != group.group_id or String(other["task"]) != "idle" or String(other["kind"]) != String(unit["kind"]): continue
		if other.get("formation_home") == null or Vector2(other["pos"]).distance_squared_to(other["formation_home"]) > 0.0016: continue
		if not is_equal_approx(float(unit["footprint_radius"]), float(other["footprint_radius"])): continue
		var other_home := Vector2(other["formation_home"])
		var before := Vector2(unit["pos"]).distance_squared_to(home)
		var after := Vector2(unit["pos"]).distance_squared_to(other_home) + Vector2(other["pos"]).distance_squared_to(home)
		if after >= before - 0.01: continue
		if not planner.is_segment_walkable(other["pos"], home, float(other["footprint_radius"]), String(other["movement_domain"]), int(other["terrain_restriction"])): continue
		var blockers: Array = candidates.filter(func(actor): return int(actor["id"]) not in [int(unit["id"]), int(other["id"])] and String(actor["movement_domain"]) == String(unit["movement_domain"]))
		if not _work_segment_clear(other, other["pos"], home, blockers): continue
		# A settled outer rank can enclose an empty inner slot. Exchange only
		# identical unit kinds/radii, and only when total travel strictly falls.
		# The formation keeps every slot; both actors walk at their ordinary speed.
		world.destination_reservations.release(int(unit["id"]))
		world.destination_reservations.release(int(other["id"]))
		group.exchange_assignments(int(unit["id"]), int(other["id"]))
		for actor in [other, unit]:
			var slot: Dictionary = group.slot_for(int(actor["id"]))
			var destination := Vector2(slot["world"])
			var reserved: Vector2 = world.destination_reservations.reserve(int(actor["id"]), destination, float(actor["footprint_radius"]), planner.grid, group.group_id, String(actor["movement_domain"]), int(actor["terrain_restriction"]))
			world.set_entity_fields(actor, {"formation_home":destination, "formation_slot_id":slot["slot_id"], "formation_slot_capacity":slot["capacity_radius"], "reserved_destination":reserved, "task":group.order_kind})
			if group.order_kind == "attack_move": world.set_entity_field(actor, "attack_move_destination", destination)
			world.begin_entity_order(actor, group.order_kind, -1, destination, false)
			StuckRecovery.reset(actor)
			assign_unit_destination(actor, reserved, false)
		return true
	return false
