extends Node
const BaseProbe := preload("res://scripts/performance_probe.gd")
const Ready := preload("res://tests/support/match_ready.gd")
const DiagnosticCommands := preload("res://scripts/commands.gd")
const DiagnosticReplay := preload("res://scripts/replay_system.gd")
class TerrainReferenceCanvas extends Node2D:
	var meshes: Array = []
	var atlas: Texture2D
	var view_offset := Vector2.ZERO
	var view_zoom := 1.0
	var viewport_size := Vector2.ZERO
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color.BLACK)
		draw_set_transform(view_offset, 0.0, Vector2.ONE * view_zoom)
		for mesh in meshes: draw_mesh(mesh, atlas)
class FrameProbe extends BaseProbe:
	var metrics: Dictionary = {}
	var profile_unit_poses := "--profile-unit-pose-cache" in OS.get_cmdline_user_args()
	var unit_pose_cached := false
	func observe_microseconds(metric: String, us: int) -> void:
		super.observe_microseconds(metric, us)
		metrics[metric] = int(metrics.get(metric, 0)) + us
		if profile_unit_poses and metric in ["presentation.draw.world_prepare.units", "presentation.draw.total", "presentation.draw.world_prepare", "presentation.sync.hud"]:
			super.observe_microseconds(metric + (".unit_pose_cached" if unit_pose_cached else ".unit_pose_fresh"), us)
class OwnerWindowProbe extends BaseProbe:
	var controller_ref: WeakRef
	var rows: Array = []
	var trace_enabled := false
	var profile_typed_motion_alternatives := "--profile-typed-motion-alternatives" in OS.get_cmdline_user_args()
	var profile_borrowed_motion_fields := "--profile-borrowed-motion-fields" in OS.get_cmdline_user_args()
	var profile_contact_frame := "--profile-contact-frame-alternatives" in OS.get_cmdline_user_args()
	var profile_movement_delta := "--profile-movement-delta-alternatives" in OS.get_cmdline_user_args()
	var profile_cached_actor_keys := "--profile-cached-actor-keys" in OS.get_cmdline_user_args()
	var profile_native_journal_readers := "--profile-native-journal-readers" in OS.get_cmdline_user_args()
	var profile_native_route_preparation := "--profile-route-preparation-alternatives" in OS.get_cmdline_user_args()
	var gather_portion_totals: Dictionary = {}
	var profile_gather_totals := "--profile-gather-portions" in OS.get_cmdline_user_args() or "--profile-gather-continuations" in OS.get_cmdline_user_args()
	func observe_microseconds(metric: String, us: int) -> void:
		super.observe_microseconds(metric, us)
		if profile_cached_actor_keys and metric in ["controller.fixed_tick.total", "simulation.unit_orders.actors"]:
			var keys_controller = controller_ref.get_ref() if controller_ref != null else null
			if keys_controller != null:
				var cached_keys: bool = keys_controller.simulation_world.movement_system.cached_actor_keys_tick_native
				var keys_prefix := "controller.fixed_tick" if metric == "controller.fixed_tick.total" else metric
				super.observe_microseconds(keys_prefix + (".cached_actor_keys" if cached_keys else ".fresh_actor_keys"), us)
		if profile_movement_delta and metric == "controller.fixed_tick.total":
			var delta_controller = controller_ref.get_ref() if controller_ref != null else null
			if delta_controller != null:
				var native_delta: bool = delta_controller.simulation_world.pathfinder.movement_delta_tick_native
				super.observe_microseconds("controller.fixed_tick.movement_delta_native" if native_delta else "controller.fixed_tick.movement_delta_script", us)
		if profile_native_route_preparation and metric == "controller.fixed_tick.total":
			var route_controller = controller_ref.get_ref() if controller_ref != null else null
			if route_controller != null:
				var native_route: bool = route_controller.simulation_world.movement_system.native_route_preparation_enabled
				super.observe_microseconds("controller.fixed_tick.route_preparation_native" if native_route else "controller.fixed_tick.route_preparation_reference", us)
		if profile_typed_motion_alternatives and metric == "controller.fixed_tick.total":
			var typed_controller = controller_ref.get_ref() if controller_ref != null else null
			if typed_controller != null:
				var typed_enabled: bool = typed_controller.simulation_world.movement_system.typed_motion_frame_enabled
				super.observe_microseconds("controller.fixed_tick.typed_motion_native" if typed_enabled else "controller.fixed_tick.typed_motion_reference", us)
		if profile_borrowed_motion_fields and metric == "controller.fixed_tick.total":
			var movement_controller = controller_ref.get_ref() if controller_ref != null else null
			if movement_controller != null:
				var borrowed_enabled: bool = movement_controller.simulation_world.movement_system.borrowed_motion_fields_enabled
				super.observe_microseconds("controller.fixed_tick.borrowed_motion_fields" if borrowed_enabled else "controller.fixed_tick.copied_motion_fields", us)
		if profile_contact_frame and metric == "controller.fixed_tick.total":
			var contacts_controller = controller_ref.get_ref() if controller_ref != null else null
			if contacts_controller != null:
				var flat_contacts: bool = contacts_controller.simulation_world.movement_system.contact_frame_tick_native
				super.observe_microseconds("controller.fixed_tick.flat_contact_frame" if flat_contacts else "controller.fixed_tick.dictionary_contact_frame", us)
		if profile_native_journal_readers and metric == "controller.fixed_tick.total":
			var journal_controller = controller_ref.get_ref() if controller_ref != null else null
			if journal_controller != null:
				var direct: bool = journal_controller.simulation_world.entity_changes.native_direct_readers
				super.observe_microseconds("controller.fixed_tick.journal_readers_native" if direct else "controller.fixed_tick.journal_readers_compatibility", us)
		if profile_gather_totals and metric.begins_with("simulation.gather."):
			if not gather_portion_totals.has(metric): gather_portion_totals[metric] = {"calls":0,"us":0}
			gather_portion_totals[metric]["calls"] += 1
			gather_portion_totals[metric]["us"] += us
		if not trace_enabled or rows.size() >= 4096: return
		if not (metric.begins_with("controller.") or metric.begins_with("simulation.system.") or metric.begins_with("simulation.unit_orders.") or metric.begins_with("simulation.gather.command.") or metric.begins_with("simulation.approach.") or metric.begins_with("presentation.ai.") or metric.begins_with("ai.owner") or metric.begins_with("ai.capture") or metric.begins_with("autosave.")): return
		var controller = controller_ref.get_ref() if controller_ref != null else null
		if controller != null: rows.append({"tick":controller.tick_index,"metric":metric,"us":us,"ended_us":Time.get_ticks_usec()})
class ProfileGame:
	extends "res://main.gd"
	# Presentation and the simulation owner must never write one probe at once.
	var graphical_probe: Variant = null
	var freeze_sprite_reference := false
	var sprite_reference_drawables: Array = []
	var profile_unit_poses := "--profile-unit-pose-cache" in OS.get_cmdline_user_args()
	func _draw() -> void:
		if profile_unit_poses and resource_catalog != null:
			var cached := (Engine.get_frames_drawn() / 32) % 2 == 0
			resource_catalog.unit_presentations.pose_cache_enabled = cached
			if graphical_probe != null: graphical_probe.unit_pose_cached = cached
		super._draw()
	var profile_grouped_hud := "--profile-grouped-hud-signature" in OS.get_cmdline_user_args()
	var compare_grouped_hud := "--compare-grouped-hud-model" in OS.get_cmdline_user_args()
	var hud_model_comparisons := 0
	var hud_model_mismatches := 0
	var last_hud_compare_tick := -1
	var compare_compact_ui := "--compare-compact-ui-controls" in OS.get_cmdline_user_args()
	var compact_ui_model_comparisons := 0
	var compact_ui_context_comparisons := 0
	var compact_ui_mismatches := 0
	var last_compact_ui_tick := -1
	func refresh_hud_model() -> void:
		if profile_grouped_hud:
			hud_view_model.grouped_signature_enabled = (Engine.get_frames_drawn() / 32) % 2 == 0
		super.refresh_hud_model()
		if compare_compact_ui: _compare_compact_ui_model()
		if profile_grouped_hud and graphical_probe != null:
			graphical_probe.observe_microseconds("presentation.hud.structural_signature" + (".grouped" if hud_view_model.grouped_signature_enabled else ".full"), hud_view_model.last_signature_us)
		if compare_grouped_hud and hud_view_model.grouped_signature_enabled and not player_control_state.selected_ids().is_empty() and hud_model_comparisons < 64:
			var tick := int(presentation_snapshot.get("tick", -1))
			if tick != last_hud_compare_tick and tick % 16 == 0:
				last_hud_compare_tick = tick
				hud_model_comparisons += 1
				var expected: Dictionary = hud_view_model.build(presentation_snapshot, player_control_state.selected_ids(), formation, "ru")
				if expected != hud_model:
					hud_model_mismatches += 1
					push_error("Grouped HUD dependencies missed an update: tick=%d" % tick)
	func _compare_compact_ui_model() -> void:
		var references: Dictionary = presentation_snapshot.get("_diagnostic_full_unit_controls", {})
		var tick := int(presentation_snapshot.get("tick", -1))
		if references.is_empty() or tick == last_compact_ui_tick or player_control_state.selected_ids().is_empty(): return
		last_compact_ui_tick = tick
		var expected_snapshot := presentation_snapshot.duplicate()
		var expected_units: Array = []
		for row in presentation_snapshot.get("units", []):
			if references.has(int(row["id"])):
				var complete: Dictionary = row.duplicate()
				complete.merge(references[int(row["id"])], true)
				expected_units.append(complete)
			else: expected_units.append(row)
		expected_snapshot["units"] = expected_units
		var expected_controls: Array = []
		var selected: Array[int] = player_control_state.selected_ids()
		for row in expected_units:
			if int(row["id"]) in selected: expected_controls.append(row)
		expected_snapshot["control_units"] = expected_controls
		compact_ui_model_comparisons += 1
		var expected: Dictionary = hud_view_model.build(expected_snapshot, selected, formation, "ru")
		if expected != hud_model:
			compact_ui_mismatches += 1
			print("COMPACT_UI_MODEL_DIFF tick=", tick, " differences=", JSON.stringify(_ui_model_differences(hud_model, expected)))
			push_error("Compact UI controls changed the HUD model: tick=%d" % tick)
		var actual_units: Array = selected_units()
		var reference_units: Array = []
		for row in expected_controls:
			if int(row.get("team", 0)) == local_player_team and float(row.get("hp", 0.0)) > 0.0: reference_units.append(row)
		reference_units.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
		var targets: Array = [null]
		var target_kinds: Dictionary = {}
		for collection in ["units", "buildings", "resources"]:
			for row in presentation_snapshot.get(collection, []):
				var kind: String = String(collection) + ":" + String(row.get("kind", ""))
				if targets.size() < 12 and not target_kinds.has(kind):
					target_kinds[kind] = true
					targets.append(row)
		for target in targets:
			var reference_target: Variant = target
			if target is Dictionary and String(target.get("entity_type", "")) == "unit" and references.has(int(target["id"])):
				reference_target = target.duplicate()
				reference_target.merge(references[int(target["id"])], true)
			var ground := screen_to_world(get_viewport_rect().size * 0.5)
			var actual_action: Dictionary = ContextResolver.resolve(actual_units, target, ground, local_player_team, command_context_allies())
			var reference_action: Dictionary = ContextResolver.resolve(reference_units, reference_target, ground, local_player_team, command_context_allies())
			compact_ui_context_comparisons += 1
			if actual_action != reference_action:
				compact_ui_mismatches += 1
				push_error("Compact UI controls changed a context action: tick=%d" % tick)
	func _ui_model_differences(actual: Variant, expected: Variant, path: String = "") -> Array:
		var result: Array = []
		if actual is Dictionary and expected is Dictionary:
			var keys: Dictionary = {}
			for key in actual: keys[key] = true
			for key in expected: keys[key] = true
			for key in keys:
				if actual.get(key) != expected.get(key):
					result.append_array(_ui_model_differences(actual.get(key), expected.get(key), path + "." + str(key)))
					if result.size() >= 8: break
		elif actual is Array and expected is Array and actual.size() == expected.size():
			for index in range(actual.size()):
				if actual[index] != expected[index]:
					result.append_array(_ui_model_differences(actual[index], expected[index], path + "[" + str(index) + "]"))
					if result.size() >= 8: break
		else:
			result.append({"path":path,"actual":str(actual).left(256),"expected":str(expected).left(256)})
		return result
	func current_world_drawables() -> Array:
		return sprite_reference_drawables if freeze_sprite_reference else super.current_world_drawables()
	func _presentation_probe():
		return graphical_probe if graphical_probe != null else super._presentation_probe()
	func _can_use_simulation_owner() -> bool:
		if game_controller == null: return false
		var previous_probe = game_controller.performance_probe
		game_controller.performance_probe = null
		var allowed: bool = super._can_use_simulation_owner()
		game_controller.performance_probe = previous_probe
		return allowed
class InstrumentedOwner:
	extends "res://scripts/simulation_owner.gd"
	const Probe := preload("res://scripts/performance_probe.gd")
	var measurement_enabled := false
	var measurements := OwnerWindowProbe.new(40000)
	var window_from := -1
	var window_to := -1
	var measured_controller
	var previous_probe
	var previous_tick_observer
	var previous_stage_observer
	var previous_system_observer
	var measure_systems_only := false
	var measure_actor_costs := false
	var previous_actor_observer: Callable
	var actor_costs: Dictionary = {}
	var measure_ticks_only := false
	var diagnostic_end_tick := -1
	var fixed_trace_enabled := "--fixed-state-trace" in OS.get_cmdline_user_args()
	var fixed_state_trace: Array = []
	var fixed_trace_last_tick := -1
	var fixed_trace_kernel = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
	func capture_fixed_state(controller) -> void:
		if not fixed_trace_enabled or controller.tick_index == fixed_trace_last_tick or fixed_state_trace.size() >= 4096: return
		fixed_trace_last_tick = controller.tick_index
		var w = controller.simulation_world
		var commands: Array = []
		for command in controller.command_queue: commands.append({"tick":command.tick,"issuer":command.issuer_id,"sequence":command.sequence_id,"type":command.command_type(),"units":command.unit_ids.duplicate(),"params_hash":hash(command.params)})
		var unit_digests: PackedInt64Array = fixed_trace_kernel.autosave_entity_digests(w.units)
		fixed_state_trace.append({"tick":controller.tick_index,"units":Array(unit_digests),"commands":commands,"rng":str(w.simulation_rng.state),"grid":w.navigation_grid.revision,"fog":w.fog_of_war.revision})
	func submit(controller,runtime,delta: float,player: int,enemy: int,frame: int) -> bool:
		if pending: return false
		if diagnostic_end_tick >= 0:
			var stop_tick := diagnostic_end_tick
			var prior_preparation: Callable = controller.before_fixed_tick
			controller.set_before_fixed_tick(func(tick: int):
				if controller.simulation_world.entity_changes.profile_native_readers: controller.simulation_world.entity_changes.native_reader_phase = tick
				capture_fixed_state(controller)
				if tick > stop_tick: return {"ready":false}
				return prior_preparation.call(tick) if prior_preparation.is_valid() else null
			)
		if measurement_enabled and (window_from < 0 or (controller.tick_index >= window_from and controller.tick_index <= window_to)):
			measured_controller=controller
			measurements.controller_ref = weakref(controller)
			measurements.trace_enabled = window_from >= 0
			previous_probe=controller.performance_probe
			previous_tick_observer=controller.fixed_tick_observer
			previous_stage_observer=controller.stage_observer
			previous_system_observer=controller.simulation_world.tick_pipeline.stage_observer
			previous_actor_observer=controller.simulation_world.movement_system.actor_order_observer
			if measure_actor_costs: controller.simulation_world.movement_system.actor_order_observer=Callable(self,"observe_actor_order")
			if measure_systems_only:
				controller.stage_observer=measurements
				controller.simulation_world.tick_pipeline.stage_observer=measurements
			if measure_ticks_only:
				controller.set_performance_probe(null)
				controller.fixed_tick_observer=measurements
			else: controller.set_performance_probe(measurements)
		var accepted: bool=super.submit(controller,runtime,delta,player,enemy,frame)
		if not accepted: _restore_probe()
		return accepted
	func take() -> Dictionary:
		var result: Dictionary=super.take()
		_restore_probe()
		return result
	func observe_actor_order(unit: Dictionary, delta: float, actor_context: Dictionary, checked_already: bool = false) -> bool:
		var task := String(unit.get("task", "idle"))
		var stage := String(unit.get("gather_stage", "none")) if task == "gather" else ""
		var actor_started := Time.get_ticks_usec()
		var accepted: bool = measured_controller.simulation_world._advance_actor_order(unit, delta, actor_context, checked_already)
		var elapsed := Time.get_ticks_usec() - actor_started
		var key := task + ("." + stage if not stage.is_empty() else "")
		if not actor_costs.has(key): actor_costs[key] = {"us":0,"count":0}
		actor_costs[key]["us"] += elapsed
		actor_costs[key]["count"] += 1
		return accepted
	func _restore_probe() -> void:
		if measured_controller!=null:
			measured_controller.set_performance_probe(previous_probe)
			measured_controller.fixed_tick_observer=previous_tick_observer
			measured_controller.stage_observer=previous_stage_observer
			measured_controller.simulation_world.tick_pipeline.stage_observer=previous_system_observer
			measured_controller.simulation_world.movement_system.actor_order_observer=previous_actor_observer
			measured_controller=null
			previous_probe=null
			previous_tick_observer=null
var owner_stages := false
var owner_ticks_only := false
var owner_systems_only := false
var owner_actor_costs := false
var owner_window := Vector2i(-1, -1)
var visual_hold := false
var capture_sprite_reference := false
var capture_selection_mesh_reference := false
var capture_environment_archive_reference := false
var diagnostic_speed_multiplier := -1.0
var initial_environment_loading_frames := 0
var initial_environment_loading_max_tick := -1
var capture_planar_terrain_reference := false
var measure_render_times := false
var profiler_overhead_us: Array = []
var render_cpu_us: Array = []
var render_gpu_us: Array = []
var game
var loading_diagnostic: Dictionary = {}
var loading_frames: Array = []
var loading_previous := 0
var log_slow_frames := false
var probe := FrameProbe.new(16000)
var measuring := false
var previous := 0
var started := 0
const MAX_FRAME_SAMPLES := 120000
var frames: Array = []
var slow: Array = []
var timeline: Array = []
var memory_peak := 0
var previous_anchors: Dictionary = {}
var previous_animations: Dictionary = {}
var previous_pose_pairs: Dictionary = {}
var human_motion: Dictionary = {}
var gameplay_start: Dictionary = {}
var memory_load_phases: Array = []


func capture_gameplay_progress() -> Dictionary:
	var teams: Dictionary = {}
	for unit in game.simulation_world.units:
		if float(unit.get("hp", 0.0)) <= 0.0: continue
		var team := int(unit.get("team", 0))
		if not teams.has(team): teams[team] = {"units":0,"gather_cycles":0,"cargo":0.0,"gather_stages":{},"stalled_gatherers":0,"move_orders_without_path":0,"tasks":{},"stalled_movers":0,"moving_destination_distance":0.0,"human_motion":[]}
		var row: Dictionary = teams[team]
		row["units"] += 1
		row["gather_cycles"] += int(unit.get("gather_cycles", 0))
		row["cargo"] += float(unit.get("carried_amount", 0.0))
		var task := String(unit.get("task", "idle"))
		row["tasks"][task] = int(row["tasks"].get(task, 0)) + 1
		if task in ["move", "attack_move"]:
			row["moving_destination_distance"] += Vector2(unit["pos"]).distance_to(Vector2(unit.get("destination", unit["pos"])))
			if int(unit.get("stuck_ticks", 0)) >= 30: row["stalled_movers"] += 1
		if team == game.local_player_team and row["human_motion"].size() < 128:
			row["human_motion"].append({"id":int(unit["id"]),"task":task,"pos":unit["pos"],"destination":unit.get("destination",unit["pos"]),"stuck_ticks":int(unit.get("stuck_ticks",0)),"group":int(unit.get("formation_group_id",-1))})
		if task == "gather":
			var stage := String(unit.get("gather_stage", ""))
			row["gather_stages"][stage] = int(row["gather_stages"].get(stage, 0)) + 1
			if stage in ["approaching", "returning"] and int(unit.get("stuck_ticks", 0)) >= 30: row["stalled_gatherers"] += 1
		elif task in ["move", "attack_move"] and unit.get("path", []).is_empty():
			row["move_orders_without_path"] += 1
	return {"tick":game.game_controller.tick_index,"teams":teams,"stockpiles":game.simulation_world.economy_system.resource_stockpiles_by_team.duplicate(true)}


func prepare_human_motion(attack: bool = false) -> Dictionary:
	game.join_simulation_owner()
	var ids: Array[int] = []
	var center := Vector2.ZERO
	var representative: Dictionary = {}
	for unit in game.simulation_world.units:
		if int(unit["team"]) != game.local_player_team or float(unit["hp"]) <= 0.0 or String(unit["movement_domain"]) != "land": continue
		ids.append(int(unit["id"]))
		center += Vector2(unit["pos"])
		if representative.is_empty(): representative = unit
		if ids.size() >= 100: break
	if ids.is_empty(): return {"error":"no_owned_land_units"}
	center /= float(ids.size())
	if attack:
		var enemies: Array = []
		for row in game.simulation_world.units:
			if int(row.get("team",0)) <= 0 or float(row.get("hp",0.0)) <= 0.0 or String(row.get("movement_domain","land")) != "land": continue
			if game.simulation_world.team_relation(game.local_player_team,int(row["team"])) == "enemy": enemies.append(row)
		enemies.sort_custom(func(a,b): return center.distance_squared_to(Vector2(a["pos"])) < center.distance_squared_to(Vector2(b["pos"])) if center.distance_squared_to(Vector2(a["pos"])) != center.distance_squared_to(Vector2(b["pos"])) else int(a["id"]) < int(b["id"]))
		for enemy in enemies:
			var enemy_position := Vector2(enemy["pos"])
			var route: Array = game.simulation_world.pathfinder.find_path(representative["pos"],enemy_position,"land",int(representative["terrain_restriction"]),float(representative["footprint_radius"]))
			if route.is_empty() or Vector2(route.back()).distance_squared_to(enemy_position) > 0.0144: continue
			game.player_control_state.replace_or_add(ids,false)
			game.center_view_on_units(ids)
			return {"mode":"attack_move","unit_count":ids.size(),"unit_ids":ids,"targets":[enemy_position,enemy_position],"enemy_team":int(enemy["team"]),"orders":[]}
		return {"mode":"attack_move","error":"no_reachable_enemy","unit_count":ids.size()}
	var target: Variant = null
	for distance in [12.0, 8.0]:
		for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			var point: Vector2 = center + direction * distance
			var route: Array = game.simulation_world.pathfinder.find_path(representative["pos"], point, "land", int(representative["terrain_restriction"]), float(representative["footprint_radius"]))
			if not route.is_empty() and Vector2(route.back()).distance_squared_to(point) <= 0.0144:
				target = point
				break
		if target != null: break
	if target == null: return {"error":"no_reachable_motion_target","unit_count":ids.size()}
	game.player_control_state.replace_or_add(ids, false)
	game.center_view_on_units(ids)
	return {"unit_count":ids.size(),"unit_ids":ids,"targets":[target,center],"orders":[]}


func _process(_delta: float) -> void:
	if is_instance_valid(game) and game.initial_environment_preparing and game.game_controller != null:
		initial_environment_loading_frames += 1
		initial_environment_loading_max_tick = maxi(initial_environment_loading_max_tick, game.game_controller.tick_index)
	if loading_previous > 0:
		var loading_now := Time.get_ticks_usec()
		loading_frames.append(loading_now - loading_previous)
		loading_previous = loading_now
	if not measuring: return
	var now := Time.get_ticks_usec()
	if previous > 0:
		var elapsed := now - previous
		if frames.size() >= MAX_FRAME_SAMPLES:
			push_error("Frame probe sample limit reached; use a shorter duration")
			measuring=false;game.free();get_tree().quit(1);return
		frames.append(elapsed)
		if game.profile_unit_poses: probe.observe_microseconds("diagnostic.frame.unit_pose_cached" if probe.unit_pose_cached else "diagnostic.frame.unit_pose_fresh", elapsed)
		if game.profile_selection_runs: probe.observe_microseconds("diagnostic.frame.selection_run_native" if game.selection_run_frame_native else "diagnostic.frame.selection_run_script", elapsed)
		if game.profile_world_runs: probe.observe_microseconds("diagnostic.frame.world_run_native" if game.world_run_frame_native else "diagnostic.frame.world_run_script", elapsed)
		var row: Dictionary = game.simulation_frame_state()
		row.merge(motion_sample())
		row.merge({"seconds":float(now-started)/1000000.0,"frame_us":elapsed,"autosave":game.autosave.busy})
		timeline.append(row)
		if elapsed > 35000:
			var stages: Array = []
			for key in probe.metrics:
				if probe.metrics[key] > 1000: stages.append({"name": key, "us": probe.metrics[key]})
			stages.sort_custom(func(a,b): return a["us"] > b["us"])
			var entry := {"seconds": float(now-started)/1000000.0,"tick":row["tick"],"frame_us":elapsed,"busy":game.autosave.busy,"stages":stages.slice(0,20)}
			slow.append(entry)
			# Console/file flushing can itself create the next slow frame on a
			# busy disk. Keep samples in memory unless live logging is requested.
			if elapsed > 80000 and log_slow_frames: print("SLOW ", JSON.stringify(entry))
	probe.metrics.clear()
	if measure_render_times:
		var viewport_rid := get_viewport().get_viewport_rid()
		render_cpu_us.append(roundi(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) * 1000.0))
		render_gpu_us.append(roundi(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid) * 1000.0))
	previous = now
	memory_peak = maxi(memory_peak, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	profiler_overhead_us.append(Time.get_ticks_usec() - now)
func _ready() -> void: call_deferred("run")
func run() -> void:
	var output := ""
	var save := ""
	var seconds := 90.0
	var end_tick := -1
	var fixed_human_ticks: Array[int] = []
	var pan := false
	var camera_jumps := false
	var move_human_group := false
	var attack_human_group := false
	var bootstrap_match := ""
	var enabled := true
	var disable_ai := false
	var uncapped := false
	var no_probe := false
	var presentation_probe_only := false
	var frame_limit := 60
	var default_frame_limit := false
	var size := Vector2i(1280, 720)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--save="): save = arg.trim_prefix("--save=")
		elif arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--end-tick="): end_tick = int(arg.trim_prefix("--end-tick="))
		elif arg.begins_with("--fixed-human-orders="):
			for value in arg.trim_prefix("--fixed-human-orders=").split(",", false): fixed_human_ticks.append(int(value))
		elif arg == "--pan": pan = true
		elif arg == "--camera-jumps": camera_jumps = true
		elif arg == "--move-human-group": move_human_group = true
		elif arg == "--attack-human-group":
			move_human_group = true
			attack_human_group = true
		elif arg.begins_with("--bootstrap-match="): bootstrap_match = arg.trim_prefix("--bootstrap-match=")
		elif arg == "--owner-stages": owner_stages = true
		elif arg == "--owner-ticks-only": owner_stages = true; owner_ticks_only = true
		elif arg == "--owner-system-stages": owner_stages = true; owner_ticks_only = true; owner_systems_only = true
		elif arg == "--owner-actor-costs": owner_stages = true; owner_ticks_only = true; owner_systems_only = true; owner_actor_costs = true
		elif arg.begins_with("--owner-window="):
			var bounds := arg.trim_prefix("--owner-window=").split(":")
			if bounds.size() == 2:
				owner_window = Vector2i(int(bounds[0]), int(bounds[1]))
				owner_stages = true
		elif arg == "--visual-hold": visual_hold = true
		elif arg == "--capture-sprite-reference": capture_sprite_reference = true
		elif arg == "--capture-selection-mesh-reference": capture_selection_mesh_reference = true
		elif arg == "--capture-environment-archive-reference": capture_environment_archive_reference = true
		elif arg.begins_with("--speed-multiplier="): diagnostic_speed_multiplier = float(arg.trim_prefix("--speed-multiplier="))
		elif arg == "--capture-planar-terrain-reference": capture_planar_terrain_reference = true
		elif arg == "--render-times": measure_render_times = true
		elif arg == "--no-autosave": enabled = false
		elif arg == "--no-ai": disable_ai = true
		elif arg == "--uncapped": uncapped = true
		elif arg == "--no-probe": no_probe = true
		elif arg == "--presentation-probe": presentation_probe_only = true
		elif arg == "--log-slow-frames": log_slow_frames = true
		elif arg == "--default-frame-limit": default_frame_limit = true
		elif arg.begins_with("--frame-limit="): frame_limit = clampi(int(arg.trim_prefix("--frame-limit=")),1,240)
		elif arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
	if output.is_empty() or save.is_empty() or FileAccess.file_exists(output) or DisplayServer.get_name() == "headless":
		push_error("Pass a save, a new output path and a graphical runtime")
		get_tree().quit(1); return
	if not default_frame_limit: Engine.max_fps = 0 if uncapped else frame_limit
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = size
	# Only this diagnostic window is isolated. Scripted orders, camera paths
	# and normal simulation processing keep running; OS input cannot add orders.
	get_window().gui_disable_input = true
	if "--profile-memory-retirement" in OS.get_cmdline_user_args(): memory_load_phases.append({"stage":"before_scene","static_bytes":OS.get_static_memory_usage()})
	game = load("res://main.tscn").instantiate()
	if owner_stages:
		game.set_script(ProfileGame)
		game.graphical_probe = probe if presentation_probe_only or not no_probe else null
		game.simulation_owner = InstrumentedOwner.new()
		game.simulation_owner.diagnostic_end_tick = end_tick
		game.simulation_owner.measurement_enabled = true
		game.simulation_owner.measure_ticks_only = owner_ticks_only
		game.simulation_owner.measure_systems_only = owner_systems_only
		game.simulation_owner.measure_actor_costs = owner_actor_costs
		game.simulation_owner.window_from = owner_window.x
		game.simulation_owner.window_to = owner_window.y
	game.autosave.enabled = false
	game.autosave.save_path = output + ".autosave.json"
	game.match_path = bootstrap_match if not bootstrap_match.is_empty() else "res://tests/fixtures/e3_save_state_matrix_match.json"
	var async_saved_load := "--profile-async-saved-load" in OS.get_cmdline_user_args()
	if async_saved_load:
		game.prepared_load_bootstrap = true
		game.process_mode = Node.PROCESS_MODE_DISABLED
		game.hide()
	get_tree().root.add_child(game)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.set_process_unhandled_key_input(false)
	if async_saved_load:
		# The production launcher's worker and main-thread preparation, with an
		# isolated autosave destination. Record actual progress, not assertions.
		var load_started := Time.get_ticks_usec()
		loading_previous = load_started
		var load_job = load("res://scripts/match_load_job.gd").new()
		if not load_job.start(save, enabled, output + ".autosave.json"): get_tree().quit(1); return
		while not bool(load_job.snapshot()["complete"]): await get_tree().process_frame
		var restored: Dictionary = load_job.take_result()
		if not String(restored.get("error", "load_worker_failed")).is_empty(): push_error(restored.get("error")); get_tree().quit(1); return
		var progress_rows: Array = []
		var load_progress := func(value: float, stage: String):
			progress_rows.append({"us":Time.get_ticks_usec() - load_started,"progress":value,"stage":stage})
		if not await game.initialize_prepared_load_async(restored, load_progress): push_error(game.last_save_error); get_tree().quit(1); return
		loading_previous = 0
		loading_diagnostic = {"duration_us":Time.get_ticks_usec() - load_started,"progress":progress_rows,"frames_us":BaseProbe.summarize(loading_frames)}
		game.prepared_load_bootstrap = false
		game.resume_from_launcher()
	else:
		if not await Ready.wait_for_ready(get_tree(),game,120000): get_tree().quit(1); return
		if "--profile-memory-retirement" in OS.get_cmdline_user_args(): memory_load_phases.append({"stage":"bootstrap_ready","static_bytes":OS.get_static_memory_usage()})
		game.autosave.enabled = enabled
		game.autosave.save_path = output + ".autosave.json"
		if bootstrap_match.is_empty() and not game.load_game_from_path(save): push_error(game.last_save_error); get_tree().quit(1); return
	if not await Ready.wait_for_ready(get_tree(),game,120000): get_tree().quit(1); return
	if "--profile-memory-retirement" in OS.get_cmdline_user_args(): memory_load_phases.append({"stage":"saved_world_ready","static_bytes":OS.get_static_memory_usage()})
	if not bootstrap_match.is_empty() and enabled: game._seed_autosave()
	if owner_stages: game.simulation_owner.measurements.clear()
	if disable_ai:
		game.ai_decision_queue.cancel(game.task_coordinator)
		game.ai_players.clear()
	game.game_controller.set_paused(false)
	if diagnostic_speed_multiplier > 0.0: game.game_controller.set_speed_multiplier(diagnostic_speed_multiplier)
	game.game_controller.set_performance_probe(null if no_probe else probe)
	if move_human_group: human_motion = prepare_human_motion(attack_human_group)
	if "--profile-native-motion-portions" in OS.get_cmdline_user_args():
		game.join_simulation_owner()
		game.simulation_world.movement_system.integration_kernel.set_motion_profiling(true)
	var initial: int = game.game_controller.tick_index
	var speed: float = game.game_controller.get_speed_multiplier()
	var offset: Vector2 = game.view_offset
	var max_static_camera_drift := 0.0
	probe.clear()
	probe.metrics.clear()
	if measure_render_times: RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	game.join_simulation_owner()
	initial = game.game_controller.tick_index
	gameplay_start = capture_gameplay_progress()
	if not fixed_human_ticks.is_empty() and human_motion.has("targets"):
		var scheduled: Array = []
		var fixed_ids: Array[int] = []
		fixed_ids.assign(human_motion["unit_ids"])
		for index in range(fixed_human_ticks.size()):
			var target: Vector2 = human_motion["targets"][index % 2]
			var command: Variant = DiagnosticCommands.AttackMoveCommand.new(fixed_human_ticks[index], fixed_ids, target) if human_motion.get("mode", "") == "attack_move" else DiagnosticCommands.FormationMoveCommand.new(fixed_human_ticks[index], fixed_ids, target, game.formation)
			game.game_controller.enqueue_command(command, true, game.local_player_team)
			scheduled.append({"tick":int(command.tick),"sequence":int(command.sequence_id),"type":command.command_type(),"target":target})
		human_motion["scheduled_orders"] = scheduled
	if owner_stages: game.simulation_owner.actor_costs.clear()
	if owner_stages: game.simulation_owner.measurements.gather_portion_totals.clear()
	game.simulation_world.movement_system.script_boundary_profile.clear()
	var read_index_start = game.simulation_world.entity_read_index
	read_index_start.native_sync_comparisons = 0
	read_index_start.native_query_comparisons = 0
	read_index_start.native_bounds_comparisons = 0
	read_index_start.native_sync_sequence = 0
	read_index_start.native_query_sequence = 0
	game.simulation_world.fog_of_war.observer_batch_comparisons = 0
	game.simulation_world.fog_of_war.observer_batch_mismatches = 0
	game.simulation_world.fog_of_war.observer_batch_native_usec = 0
	game.simulation_world.fog_of_war.observer_batch_reference_usec = 0
	if "--compare-native-entity-journal" in OS.get_cmdline_user_args(): game.simulation_world.entity_changes.begin_native_comparison()
	game.simulation_world.render_entity_projection_cache.native_version_queries = 0
	game.simulation_world.render_entity_projection_cache.native_version_comparisons = 0
	game.simulation_world.render_entity_projection_cache.native_version_mismatches = 0
	var resource_assets_at_start: Array = game.resource_catalog.source_resource_textures.keys()
	var environment_textures_at_start: Array = game.resource_catalog.environment_pack.textures.keys()
	if "--native-stack-beacon" in OS.get_cmdline_user_args():
		var beacon := FileAccess.open(output + ".ready.json", FileAccess.WRITE)
		if beacon != null:
			beacon.store_string(JSON.stringify({"pid":OS.get_process_id(),"tick":initial,"release":not OS.is_debug_build()}))
			beacon.close()
	started = Time.get_ticks_usec()
	previous = started
	measuring = true
	print("READY tick=",initial," size=",game.map_size," units=",game.simulation_world.units.size()," resources=",game.simulation_world.resource_nodes.size()," speed=",speed," release=",not OS.is_debug_build())
	var next_human_order := 2.0
	while Time.get_ticks_usec()-started < int(seconds*1000000) and (end_tick < 0 or int(game.simulation_frame_state().get("tick", initial)) < end_tick):
		await get_tree().process_frame
		if not pan: max_static_camera_drift = maxf(max_static_camera_drift, Vector2(game.view_offset).distance_to(offset))
		if fixed_human_ticks.is_empty() and human_motion.has("targets") and float(Time.get_ticks_usec()-started)/1000000.0 >= next_human_order:
			var orders: Array = human_motion["orders"]
			var target: Vector2 = human_motion["targets"][orders.size() % 2]
			var owner_pending_before: bool = game.simulation_owner.pending
			var dispatch_started := Time.get_ticks_usec()
			if human_motion.get("mode","") == "attack_move":
				var ids: Array[int] = []
				ids.assign(human_motion["unit_ids"])
				game._queue_local_command(DiagnosticCommands.AttackMoveCommand.new(game.next_local_command_tick(), ids, target))
			else:
				game.issue_ground_order(target)
			var dispatch_us := Time.get_ticks_usec() - dispatch_started
			orders.append({"seconds":float(Time.get_ticks_usec()-started)/1000000.0,"tick":int(game.simulation_frame_state().get("tick",0)),"target":target,"dispatch_us":dispatch_us,"owner_pending_before":owner_pending_before,"owner_pending_after":game.simulation_owner.pending})
			next_human_order += 60.0
		if pan:
			var t := float(Time.get_ticks_usec()-started)/1000000.0
			var jump := Vector2.ZERO
			if camera_jumps:
				var phase := int(t / 20.0) % 4
				if phase == 1: jump = Vector2(1280,0)
				elif phase == 2: jump = Vector2(-1280,0)
			game.view_offset = offset + jump + Vector2(sin(t*0.4)*480.0,cos(t*0.3)*240.0)
	measuring = false
	game.join_simulation_owner()
	var measured_seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	game.game_controller.set_paused(true)
	game.set_process(false)
	if capture_sprite_reference and owner_stages:
		game.profile_selection_ellipses = false
		game.profile_selection_runs = false
		game.profile_world_runs = false
		game.sprite_reference_drawables = game.current_world_drawables()
		game.freeze_sprite_reference = true
		game.queue_redraw()
	var steady := timeline.filter(func(row):return row["seconds"]>=15.0)
	var result := {"release":not OS.is_debug_build(),"uncapped":uncapped,"frame_limit":Engine.max_fps,"default_frame_limit":default_frame_limit,"simulation_owner_started":game.simulation_owner.thread.is_started(),"probe_enabled":not no_probe,"resolution":[get_window().size.x,get_window().size.y],"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"native_visibility_deltas":game.simulation_world.get_fog_of_war().native_kernel.has_method("apply_source_deltas"),"native_visibility_sources":game.simulation_world.get_fog_of_war().native_kernel.has_method("collect_source_deltas"),"native_controls":ClassDB.instantiate("RoRReadModelKernel").has_method("project_control"),"native_terrain_chunks":ClassDB.instantiate("RoRTerrainKernel").has_method("split_mesh_arrays"),"native_resource_bounds":ClassDB.instantiate("RoRReadModelKernel").has_method("known_resources_in_bounds"),"terrain_peak_chunk_upload_us":game.terrain_canvas.peak_chunk_upload_us,"terrain_mesh_metrics":game.terrain_canvas.last_mesh_build_metrics.duplicate(),"native_resource_buckets":ClassDB.instantiate("RoRReadModelKernel").has_method("build_resource_buckets"),"native_walkability_masks":ClassDB.instantiate("RoRReadModelKernel").has_method("walkability_mask"),"save":save,"autosave":enabled,"pan":pan,"seconds":seconds,"speed":speed,"frame_us":BaseProbe.summarize(frames),"steady_frame_us":BaseProbe.summarize(steady.map(func(row):return row["frame_us"])),"simulation_pauses":simulation_pause_summary(steady),"initial_tick":initial,"final_tick":game.game_controller.tick_index,"slow":slow,"timeline":timeline,"probe":probe.report(),"memory_peak":memory_peak if memory_peak > 0 else null,"capture_us":game.autosave.last_capture_us,"saved_tick":game.autosave.last_tick,"autosave_error":game.autosave.last_error, "autosave_process_isolated":game.autosave.worker_process_isolated}
	result["render_submission"] = render_submission_summary(game.current_world_drawables())
	result["native_world_runs"] = {"enabled":game.native_world_runs_enabled,"native_frames":game.native_world_run_frames,"script_frames":game.script_world_run_frames,"items":game.native_world_run_items,"fallback_items":game.native_world_run_fallback_items}
	result["native_selection_runs"] = {"enabled":game.native_selection_runs_enabled,"supported":game.native_selection_runs_supported,"native_frames":game.native_selection_run_frames,"script_frames":game.script_selection_run_frames,"items":game.native_selection_run_items}
	result["loading_diagnostic"] = loading_diagnostic
	result["prewarmed_resource_assets"] = resource_assets_at_start
	result["prewarmed_environment_textures"] = environment_textures_at_start
	result["resource_assets_loaded_during_gameplay"] = game.resource_catalog.source_resource_textures.keys().filter(func(key): return not resource_assets_at_start.has(key))
	result["environment_textures_loaded_during_gameplay"] = game.resource_catalog.environment_pack.textures.keys().filter(func(key): return not environment_textures_at_start.has(key))
	result["camera_jumps"] = camera_jumps
	result["camera_control"] = {"interactive_input_disabled":game.diagnostic_camera_input_disabled,"initial":[offset.x,offset.y],"final":[game.view_offset.x,game.view_offset.y],"max_static_drift_pixels":max_static_camera_drift}
	result["human_motion"] = human_motion
	result["presentation_probe_enabled"] = presentation_probe_only or not no_probe
	result["resource_record_archive"] = {"entries":game.render_world.resource_record_archive.size(),"estimated_bytes":game.render_world.resource_record_archive_bytes,"hits":game.render_world.resource_record_archive_hits,"warmups":game.render_world.resource_record_warmups}
	result["environment_record_archive"] = {"enabled":game.render_world.environment_record_archive_enabled,"entries":game.render_world.environment_record_archive.size(),"estimated_bytes":game.render_world.environment_record_archive_bytes,"hits":game.render_world.environment_record_archive_hits,"warmups":game.render_world.environment_record_warmups,"prewarm_us":game.render_world.environment_record_prewarm_us}
	result["unit_pose_cache"] = {"alternating":game.profile_unit_poses,"enabled":game.resource_catalog.unit_presentations.pose_cache_enabled,"entries":game.resource_catalog.unit_presentations.pose_records.size(),"hits":game.resource_catalog.unit_presentations.pose_cache_hits,"misses":game.resource_catalog.unit_presentations.pose_cache_misses}
	result["grouped_hud_signature"] = {"alternating":game.profile_grouped_hud,"enabled":game.hud_view_model.grouped_signature_enabled,"calls":game.hud_view_model.grouped_signature_calls,"model_comparisons":game.hud_model_comparisons,"model_mismatches":game.hud_model_mismatches}
	result["initial_environment_loading"] = {"frames":initial_environment_loading_frames,"max_tick":initial_environment_loading_max_tick}
	result["terrain_loading_draws"] = {"preparing":game.terrain_canvas.preparation_draws,"fallback":game.terrain_canvas.fallback_draws,"fallback_material_meshes":game.terrain_canvas.fallback_material_meshes}
	result["resource_frame_descriptors"] = {"source_entries":game.resource_catalog.source_resource_descriptors.size(),"source_hits":game.resource_catalog.source_resource_descriptor_hits,"source_misses":game.resource_catalog.source_resource_descriptor_misses,"environment_entries":game.resource_catalog.environment_pack.object_frame_cache.size(),"environment_hits":game.resource_catalog.environment_pack.object_frame_cache_hits,"environment_misses":game.resource_catalog.environment_pack.object_frame_cache_misses,"sprite_templates":game.render_world.sprite_template_cache.get("entries", {}).size(),"sprite_template_bytes":game.render_world.sprite_template_cache.get("bytes", 0)}
	result["gameplay_progress"] = {"initial":gameplay_start,"final":capture_gameplay_progress()}
	if end_tick >= 0:
		game.simulation_owner.capture_fixed_state(game.game_controller)
		if game.simulation_owner.fixed_trace_enabled:
			var state_trace_file := FileAccess.open(output + ".state-trace.json", FileAccess.WRITE)
			state_trace_file.store_string(JSON.stringify(game.simulation_owner.fixed_state_trace))
			state_trace_file.close()
		result["seconds_requested"] = seconds
		result["seconds"] = measured_seconds
		var scheduled_results: Array = []
		for order in human_motion.get("scheduled_orders", []):
			scheduled_results.append({"order":order,"result":game.game_controller.command_results.get(int(order["sequence"]), {})})
		var capture_state_hash := "--fixed-state-hash" in OS.get_cmdline_user_args()
		result["fixed_tick_capture"] = {"requested_end_tick":end_tick,"completed":game.game_controller.tick_index == end_tick,"scheduled_results":scheduled_results,"state_hash_captured":capture_state_hash,"state_sha256":DiagnosticReplay.new().world_state_hash(game.simulation_world, game.game_controller.tick_index, game.game_controller) if capture_state_hash else ""}
	result["local_command_ingress"] = game.local_command_inbox.report()
	result["producer_render_scene"] = {"enabled":game.producer_scene_enabled,"publications":game.producer_scene_publications,"bootstraps":game.producer_scene_bootstraps,"camera_queries":game.producer_scene_camera_queries,"queries":game.published_render_scene.queries,"resource_queries":game.published_render_scene.resource_queries,"comparisons":game.producer_scene_comparisons,"mismatches":game.producer_scene_mismatches}
	result["retained_scene_controls"] = game.render_snapshot_source.controls_projection.counters.duplicate()
	result["compact_ui_controls"] = {"requested":game.render_snapshot_source.controls_projection.compact_ui_requested,"supported":game.render_snapshot_source.controls_projection.compact_ui_supported,"alternating":game.render_snapshot_source.controls_projection.profile_compact_ui,"model_comparisons":game.compact_ui_model_comparisons,"context_comparisons":game.compact_ui_context_comparisons,"mismatches":game.compact_ui_mismatches}
	result["capture_identity_tracking"] = {"supported":RoRIsolatedTaskData.capture_identity_tracking_support,"enabled":RoRIsolatedTaskData.capture_identity_tracking_enabled,"alternating":game.render_snapshot_source.profile_capture_identity}
	result["cached_actor_keys"] = {"enabled":game.simulation_world.movement_system.cached_actor_keys_requested,"supported":game.simulation_world.movement_system.cached_actor_keys_supported,"alternating":game.simulation_world.movement_system.profile_cached_actor_keys,"counts":game.simulation_world.movement_system.cached_actor_key_counts.duplicate()}
	result["retained_scene_menus"] = game.render_snapshot_source.scene_menu_counters.duplicate()
	result["script_boundary_profile"] = game.simulation_world.movement_system.script_boundary_profile.duplicate(true)
	var read_index = game.simulation_world.entity_read_index
	result["persistent_native_read_index"] = {"enabled":read_index.native_enabled,"active":read_index.uses_native(),"sync_comparisons":read_index.native_sync_comparisons,"query_comparisons":read_index.native_query_comparisons,"bounds_comparisons":read_index.native_bounds_comparisons,"mismatches":read_index.native_mismatches,"stats":read_index.native_index.stats() if read_index.native_index != null else {}}
	result["checked_move_orders"] = {"attempts":game.simulation_world.movement_system.checked_move_attempts,"updates":game.simulation_world.movement_system.checked_move_updates,"control_publication_batches":game.simulation_world.movement_system.control_publication_batches,"enabled":game.simulation_world.movement_system.native_checked_moves_enabled}
	var recovery_knowledge = game.simulation_world.ai_navigation_knowledge
	result["native_ai_recovery"] = {"enabled":recovery_knowledge.native_recovery_enabled,"native_calls":recovery_knowledge.native_recovery_calls,"script_calls":recovery_knowledge.script_recovery_calls,"unsupported":recovery_knowledge.unsupported_recovery_calls,"reference_checks":recovery_knowledge.recovery_reference_checks,"reference_mismatches":recovery_knowledge.recovery_reference_mismatches,"reference_nonempty":recovery_knowledge.recovery_reference_nonempty}
	result["work_traffic"] = {"enabled":game.simulation_world.movement_system.native_work_traffic_enabled,"alternating":game.simulation_world.movement_system.profile_work_traffic,"comparison_enabled":game.simulation_world.movement_system.compare_work_traffic_results,"counters":game.simulation_world.movement_system.work_traffic_counters.duplicate()}
	result["ai_projection"] = {"alternating":game.ai_observation_store.profile_projection,"comparison_enabled":game.ai_observation_store.compare_projection,"counters":game.ai_observation_store.projection_counters.duplicate()}
	result["full_actor_pipeline"] = {"enabled":game.simulation_world.movement_system.full_actor_pipeline_enabled,"supported":game.simulation_world.movement_system.full_actor_pipeline_supported,"alternating":game.simulation_world.movement_system.profile_full_actor_pipeline,"counters":game.simulation_world.movement_system.full_actor_pipeline_counters.duplicate()}
	result["common_movement_pipeline"] = {"alternating":game.simulation_world.movement_system.profile_common_movement_pipeline,"enabled":game.simulation_world.movement_system.common_movement_pipeline_enabled,"supported":game.simulation_world.movement_system.common_movement_pipeline_supported,"calls":game.simulation_world.movement_system.common_movement_pipeline_calls,"batch_operations":game.simulation_world.movement_system.common_movement_batch_operations,"batch_binding_refreshes":game.simulation_world.movement_system.common_movement_batch_refreshes}
	result["movement_dispatch"] = {"enabled":game.simulation_world.pathfinder.owner_movement_dispatch_enabled,"alternating":game.simulation_world.pathfinder.profile_owner_movement_dispatch,"counts":game.simulation_world.pathfinder.owner_movement_dispatch_counts.duplicate()}
	result["scoped_resource_digest"] = {"requested":game.simulation_world.movement_system.scoped_resource_digest_requested,"alternating":game.simulation_world.movement_system.profile_scoped_resource_digest}
	result["owner_presentation_publication"] = {"enabled":game.owner_presentation_enabled,"alternating":game.owner_presentation_alternating,"adoptions":game.owner_presentation_adoptions,"rejections":game.owner_presentation_rejections.duplicate()}
	result["native_unit_span"] = {"enabled":game.simulation_world.movement_system.native_unit_span_enabled,"supported":game.simulation_world.movement_system.native_unit_span_supported,"calls":game.simulation_world.movement_system.unit_span_calls,"updates":game.simulation_world.movement_system.unit_span_updates}
	# Availability is not execution: intrusive probes can disable the native
	# entry while both enabled and supported remain true.
	result["native_unit_span"]["executed"] = game.simulation_world.movement_system.unit_span_calls > 0
	result["full_actor_pipeline"]["executed"] = int(game.simulation_world.movement_system.full_actor_pipeline_counters.get("actors", 0)) > 0
	result["full_actor_pipeline"]["native_gather_executed"] = int(game.simulation_world.movement_system.full_actor_pipeline_counters.get("gather_recoveries", 0)) + int(game.simulation_world.movement_system.full_actor_pipeline_counters.get("gather_continuations", 0)) > 0
	result["actor_replay_comparison"] = {"requested":"--compare-actor-owner-replay" in OS.get_cmdline_user_args(),"native_owner_executed":result["full_actor_pipeline"]["executed"]}
	result["gather_continuation_profile"] = game.simulation_world.gathering_system.profile_gather_continuations
	result["combat_awareness_native"] = {"enabled":game.game_controller.combat_awareness.native_awareness_enabled,"executed":int(game.game_controller.combat_awareness.native_awareness_stats.get("calls",0))>0,"alternating":game.game_controller.combat_awareness.profile_native_awareness,"counters":game.game_controller.combat_awareness.native_awareness_stats.duplicate(),"comparisons":game.game_controller.combat_awareness.native_awareness_comparisons,"mismatches":game.game_controller.combat_awareness.native_awareness_mismatches}
	result["ordered_gather_controller"] = {"enabled":game.simulation_world.movement_system.ordered_gather_controller_enabled,"supported":game.simulation_world.movement_system.ordered_gather_controller_supported,"alternating":game.simulation_world.movement_system.profile_ordered_gather_controller,"executed":int(game.simulation_world.movement_system.full_actor_pipeline_counters.get("gather_controller_calls",0)) > 0}
	if "--profile-native-motion-portions" in OS.get_cmdline_user_args():
		result["native_motion_portions"] = game.simulation_world.movement_system.integration_kernel.motion_profile()
	result["bootstrap_match"] = bootstrap_match
	result["autosave_diagnostic"] = game.autosave.last_diagnostic
	result["diagnostic_native_switches"] = {"contacts":OS.get_environment("ROR_DIAGNOSTIC_DISABLE_NATIVE_CONTACTS") != "1","world_finish":OS.get_environment("ROR_DIAGNOSTIC_DISABLE_WORLD_FINISH") != "1"}
	var prepared = game.terrain_canvas.prepared_scene
	result["prepared_terrain_scene"] = {"enabled":game.terrain_canvas.prepared_scene_enabled,"ready":prepared.ready if prepared != null else false,"failed":prepared.failed if prepared != null else false,"chunks":prepared.records.size() if prepared != null else 0,"built_rows":prepared.completed_jobs if prepared != null else 0,"generation":prepared.generation if prepared != null else 0,"vertices":prepared.vertices if prepared != null else 0,"discarded_transparent_triangles":prepared.discarded_transparent_triangles if prepared != null else 0,"avoided_vertices":prepared.avoided_vertices if prepared != null else 0,"buffer_bytes":prepared.buffer_bytes if prepared != null else 0,"preparation_us":prepared.preparation_us if prepared != null else 0,"visible_chunks":prepared.visible_chunks if prepared != null else 0,"visible_meshes":prepared.visible_meshes if prepared != null else 0,"visible_vertices":prepared.visible_vertices if prepared != null else 0}
	result["terrain_coverage_parts"] = game.terrain_canvas.coverage_parts.size()
	result["terrain_peak_coverage_parts"] = game.terrain_canvas.peak_coverage_parts
	result["terrain_coverage_cache_pressure_frames"] = game.terrain_canvas.coverage_cache_pressure_frames
	result["terrain_retired_meshes"] = game.terrain_canvas.retired_meshes.size()
	result["terrain_retired_cpu_chunks"] = game.terrain_canvas._retired_cpu_chunk_count()
	result["terrain_peak_retired_cpu_chunks"] = game.terrain_canvas.peak_retired_cpu_chunks
	result["terrain_peak_coverage_jobs"] = game.terrain_canvas.peak_coverage_jobs
	var environment_field = game.environment_presentation_field
	result["environment_prepared_index"] = {"enabled":environment_field.native_index != null,"static_rows":environment_field.static_items.size(),"ambient_rows":environment_field.ambient_items.size(),"cell_buckets":environment_field.items_by_cell.size()}
	var resource_pool = game.simulation_world.resource_component_pool
	result["resource_component_pool"] = {"enabled":resource_pool.enabled,"templates":resource_pool.template_count,"encoded_bytes":resource_pool.retained_bytes,"shared_components":resource_pool.shared_components,"location_templates_enabled":resource_pool.location_templates_enabled,"location_binding_records":resource_pool.location_binding_records}
	result["owned_visibility_buffers"] = {"enabled":game.simulation_world.fog_of_war.native_owned_buffers_enabled,"updates":game.simulation_world.fog_of_war.owned_buffer_updates,"states_reused":game.simulation_world.fog_of_war.owned_states_reused,"counts_reused":game.simulation_world.fog_of_war.owned_counts_reused}
	var measured_fog = game.simulation_world.fog_of_war
	var measured_motion_kernel = game.simulation_world.movement_system.integration_kernel
	result["typed_motion_frame"] = measured_motion_kernel.typed_motion_stats() if measured_motion_kernel != null and measured_motion_kernel.has_method("typed_motion_stats") else {}
	result["typed_motion_frame"]["enabled"] = game.simulation_world.movement_system.typed_motion_frame_requested
	result["typed_motion_frame"]["alternating"] = game.simulation_world.movement_system.profile_typed_motion_alternatives
	result["typed_motion_frame"]["borrowed_fields"] = game.simulation_world.movement_system.borrowed_motion_fields_requested
	result["typed_motion_frame"]["borrowed_fields_alternating"] = game.simulation_world.movement_system.profile_borrowed_motion_fields
	result["contact_frame"] = measured_motion_kernel.contact_frame_stats() if measured_motion_kernel != null and measured_motion_kernel.has_method("contact_frame_stats") else {}
	result["movement_delta"] = {"enabled":game.simulation_world.pathfinder.native_movement_delta_enabled,"alternating":game.simulation_world.pathfinder.profile_movement_delta,"counts":game.simulation_world.pathfinder.movement_delta_counts.duplicate(),"total_us":game.simulation_world.pathfinder.movement_delta_us.duplicate()}
	result["selection_meshes"] = {"alternating":game.profile_selection_meshes,"requested":game.native_selection_meshes_requested,"kernels":[]}
	for selection_kernel in [game.selection_ellipse_kernel, game.render_world.native_render_kernel]:
		if selection_kernel != null and selection_kernel.has_method("selection_mesh_stats"): result["selection_meshes"]["kernels"].append(selection_kernel.selection_mesh_stats())
	if game.render_world.native_render_kernel != null and game.render_world.native_render_kernel.has_method("control_batch_stats"):
		result["control_batches"] = game.render_world.native_render_kernel.control_batch_stats()
	result["route_recovery_cache"] = game.simulation_world.movement_system.recovery_cache_counters.duplicate(true)
	result["native_route_preparation"] = {"enabled":game.simulation_world.movement_system.native_route_preparation_requested,"alternating":game.simulation_world.movement_system.profile_native_route_preparation}
	result["cluster_route_search"] = {"exhaustive":game.simulation_world.gathering_system.exhaustive_cluster_routes,"stats":game.simulation_world.gathering_system.cluster_route_search_stats.duplicate()}
	var price_bounds_totals := {"hits":0,"captures":0,"comparisons":0,"mismatches":0,"entries":0}
	var price_bound_sets: Array = [game.render_snapshot_source.scene_rules.get("price_bounds", {}).values()]
	price_bound_sets.append([game.render_snapshot_source.scene_worker_price_bounds])
	for rule_cache in game.ai_runtime.preparation.command_rule_caches.values(): price_bound_sets.append(rule_cache.get("price_bounds", {}).values())
	for certificates in price_bound_sets:
		for certificate in certificates:
			if certificate.is_empty(): continue
			price_bounds_totals["entries"] += 1
			for counter in ["hits", "captures", "comparisons", "mismatches"]: price_bounds_totals[counter] += int(certificate.get(counter, 0))
	result["command_price_bounds"] = price_bounds_totals
	result["observer_visibility_batch"] = {"enabled":measured_fog.native_observer_batch_enabled,"calls":measured_fog.observer_batch_calls,"cell_operations":measured_fog.observer_batch_cell_operations,"footprint_cells":measured_fog.observer_batch_footprint_cells,"observer_applications":measured_fog.observer_batch_applications,"comparisons":measured_fog.observer_batch_comparisons,"mismatches":measured_fog.observer_batch_mismatches}
	result["observer_visibility_batch"]["paired_native_us"] = measured_fog.observer_batch_native_usec
	result["observer_visibility_batch"]["paired_reference_us"] = measured_fog.observer_batch_reference_usec
	result["physical_input_blocked"] = get_window().gui_disable_input and not game.is_processing_input() and not game.is_processing_unhandled_input() and not game.is_processing_unhandled_key_input()
	var measured_journal = game.simulation_world.entity_changes
	result["native_entity_journal"] = {"active":measured_journal.native_active,"comparisons":measured_journal.native_reference_checks,"mismatches":measured_journal.native_reference_mismatches,"reference_resets":measured_journal.native_reference_resets,"stats":measured_journal.native_journal.stats() if measured_journal.native_active else {}}
	var measured_render_cache = game.simulation_world.render_entity_projection_cache
	result["native_entity_journal"]["render_comparisons"] = measured_render_cache.native_version_comparisons
	result["native_entity_journal"]["render_mismatches"] = measured_render_cache.native_version_mismatches
	result["native_entity_journal"]["direct_readers_requested"] = measured_journal.native_direct_readers_requested
	result["native_entity_journal"]["alternating_readers"] = measured_journal.profile_native_readers
	result["owner_stage_probe_enabled"] = owner_stages
	result["owner_ticks_only"] = owner_ticks_only
	result["owner_systems_only"] = owner_systems_only
	result["owner_actor_costs"] = game.simulation_owner.actor_costs if owner_stages else {}
	result["ai_actor_catalog"] = game.ai_runtime.preparation.actor_catalog_stats.duplicate()
	result["gather_portion_totals"] = game.simulation_owner.measurements.gather_portion_totals if owner_stages else {}
	result["profiler_overhead_us"] = BaseProbe.summarize(profiler_overhead_us)
	result["render_cpu_us"] = BaseProbe.summarize(render_cpu_us)
	result["render_gpu_us"] = BaseProbe.summarize(render_gpu_us)
	result["owner_stage_probe"] = game.simulation_owner.measurements.report() if owner_stages else {}
	var activity = game.simulation_world.unit_activity_registry
	var eviction_stats := {"physical":game.simulation_world.pathfinder.cache_eviction_stats.duplicate()}
	for team in game.simulation_world.movement_system.knowledge.entries:
		var entry: Dictionary = game.simulation_world.movement_system.knowledge.entries[team]
		eviction_stats[String.num_int64(int(team))] = entry["planner"].cache_eviction_stats.duplicate()
	result["route_cache_eviction"] = eviction_stats
	result["native_move_fallbacks"] = {"costs":game.simulation_world.movement_system.native_move_fallback_costs.duplicate(true),"reasons":{1:"unsupported_actor",2:"task",3:"conversion",4:"near_arrival",5:"recovery_tick",6:"formation_corner",7:"grid",8:"native_disabled",9:"stale_kernel",10:"water_footprint",11:"blocked_segment",12:"motion_guard_or_arrival",13:"shared_motion",14:"movement_envelope",15:"missing_kernel",16:"group_policy",17:"missing_planner",18:"other"}}
	var raw_route_stats := {}
	var route_planners := {"physical":game.simulation_world.pathfinder}
	for team in game.simulation_world.movement_system.knowledge.entries:
		route_planners[String.num_int64(int(team))] = game.simulation_world.movement_system.knowledge.entries[team]["planner"]
	for planner_name in route_planners:
		var route_planner = route_planners[planner_name]
		var kernels := {}
		for configuration in route_planner.native_kernels:
			var route_kernel = route_planner.native_kernels[configuration]
			if route_kernel.has_method("route_cache_stats"): kernels[configuration] = route_kernel.route_cache_stats()
		raw_route_stats[planner_name] = kernels
	result["native_raw_route_cache"] = raw_route_stats
	result["control_component_copy"] = preload("res://scripts/simulation_presentation_projection.gd").control_copy_stats.duplicate()
	result["native_activity_refresh"] = {"coalesced_boundaries":activity.coalesced_boundaries_enabled,"boundary_synchronizations":activity.boundary_synchronizations,"boundary_pending_fallbacks":activity.boundary_pending_fallbacks,"enabled":activity.native_refresh_enabled,"native_calls":activity.native_refresh_calls,"native_units":activity.native_refresh_units,"reference_checks":activity.refresh_reference_checks,"reference_mismatches":activity.refresh_reference_mismatches}
	result["native_activity_order"] = {"enabled":activity.native_order_enabled,"supported":activity.native_order_supported,"native_calls":activity.native_order_calls,"script_calls":activity.script_order_calls,"native_units":activity.native_order_units}
	var spatial = game.simulation_world.spatial_index
	result["native_spatial_sync"] = {"enabled":spatial.native_sync_enabled,"supported":spatial.native_sync_supported,"native_calls":spatial.native_sync_calls,"native_units":spatial.native_sync_units,"script_calls":spatial.script_sync_calls,"fallbacks":spatial.native_sync_fallbacks}
	result["owner_tick_window"] = {"from":owner_window.x,"to":owner_window.y,"rows":game.simulation_owner.measurements.rows} if owner_stages and owner_window.x >= 0 else {}
	result["motion"] = motion_summary(steady)
	result["autosave_initialization_us"] = game.autosave.last_initialization_us
	result["autosave_worker_us"] = game.autosave.last_worker_us
	result["slow_frame_logging"] = log_slow_frames
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot write frame report"); game.free(); get_tree().quit(1); return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("RESULT ",JSON.stringify(result["frame_us"]))
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png(output + ".png")
	if capture_planar_terrain_reference: await capture_planar_terrain_pair(output)
	if capture_environment_archive_reference:
		var retained_items: Array = game.current_world_drawables()
		game.sprite_reference_drawables = retained_items
		game.freeze_sprite_reference = true
		game.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + ".environment-archive.png")
		var fresh_items: Array = []
		var fresh_environment: Array = []
		for item in retained_items:
			var source: Dictionary = item.get("data", {})
			if String(item.get("kind", "")) == "environment" and not bool(source.get("animated", false)) and String(source.get("presentation_layer", "scenery")) != "ambient_actor":
				var info: Dictionary = game.render_item_frame_info("environment", source)
				var position: Vector2 = source.get("position", Vector2.ZERO)
				var fresh: Dictionary = preload("res://scripts/render_item.gd").create("environment", preload("res://scripts/render_world.gd").environment_layer(source), position, game.world_to_screen(position), int(item["stable_id"]), source, info, float(source.get("source_elevation", 0.0)), Color.WHITE, 1.0, int(info.get("graphic_layer", 0)) * 1000)
				fresh_environment.append(fresh)
				fresh_items.append(fresh)
			else: fresh_items.append(item)
		game.render_world._cache_sprite_batch(fresh_environment)
		game.sprite_reference_drawables = game.render_world.native_render_kernel.sort_render_items(fresh_items)
		game.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + ".environment-fresh.png")
		game.freeze_sprite_reference = false
		game.sprite_reference_drawables = []
	if capture_selection_mesh_reference:
		var previous_meshes: bool = game.native_selection_meshes_requested
		var previous_mesh_profile: bool = game.profile_selection_meshes
		game.profile_selection_meshes = false
		game.sprite_reference_drawables = game.current_world_drawables()
		game.freeze_sprite_reference = true
		for use_meshes in [true, false]:
			game.native_selection_meshes_requested = use_meshes
			game.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output + (".selection-mesh.png" if use_meshes else ".selection-polyline.png"))
		game.native_selection_meshes_requested = previous_meshes
		game.profile_selection_meshes = previous_mesh_profile
		game.freeze_sprite_reference = false
		game.sprite_reference_drawables = []
	if capture_sprite_reference and owner_stages:
		var previous_world_runs: bool = game.native_world_runs_enabled
		game.native_world_runs_enabled = false
		game.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + ".world.scalar.png")
		var previous_runs: bool = game.native_selection_runs_enabled
		game.native_selection_runs_enabled = false
		game.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + ".selection.scalar.png")
		game.native_selection_runs_enabled = previous_runs
		# Capture the previous submission path from the same frozen world/pose.
		# This is visual profiling output; it does not advance or replace a match.
		var previous_batches: bool = game.native_sprite_batches
		var previous_ellipses: bool = game.native_selection_ellipses_enabled
		game.native_sprite_batches = false
		game.native_selection_ellipses_enabled = false
		var reference_items: Array = []
		for item in game.sprite_reference_drawables:
			var reference: Dictionary = item.duplicate(false)
			if String(item.get("kind", "")) in ["unit", "unit_part"]: reference.erase("sprite_command")
			reference_items.append(reference)
		game.sprite_reference_drawables = reference_items
		game.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + ".scalar.png")
		game.native_sprite_batches = previous_batches
		game.native_selection_ellipses_enabled = previous_ellipses
		game.native_world_runs_enabled = previous_world_runs
		game.freeze_sprite_reference = false
		game.sprite_reference_drawables = []
	if visual_hold:
		# Recording happens after the measured interval in the same real match.
		game.game_controller.set_paused(false)
		game.set_process(true)
		get_window().grab_focus()
		var ready_file := FileAccess.open(output + ".visual-ready", FileAccess.WRITE)
		ready_file.store_string("performance measurement finished\n")
		ready_file.close()
		var hold_until := Time.get_ticks_usec() + 30000000
		while Time.get_ticks_usec() < hold_until: await get_tree().process_frame
	if "--profile-memory-retirement" in OS.get_cmdline_user_args():
		screenshot = null
		resource_pool = null
		environment_field = null
		await profile_memory_retirement(output)
	else: game.free()
	get_tree().quit(0)


func capture_planar_terrain_pair(output: String) -> void:
	# The measured gameplay interval has ended. Both images use one frozen
	# world/pose and one detached numeric request; only the base mesh differs.
	var source = game.terrain_canvas
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, source.map_size).intersection(Rect2i(source.bounds_provider.call()).grow(4))
	var mesh_job = preload("res://scripts/native_terrain_mesh.gd")
	var request: Dictionary = mesh_job.capture(bounds, source.map_seed, source.terrain_id_provider, source.simulation_world.terrain_elevation, source.resource_catalog.environment_pack, source.terrain_atlas_regions, source.terrain_atlas_size, {}, {}, source.native_kernel)
	var kernel = ClassDB.instantiate("RoRTerrainKernel")
	if not kernel.has_method("supports_planar_base_compaction"): return
	var previous_frozen: bool = game.freeze_sprite_reference
	var previous_drawables: Array = game.sprite_reference_drawables
	game.sprite_reference_drawables = game.current_world_drawables()
	game.freeze_sprite_reference = true
	var reference := TerrainReferenceCanvas.new()
	reference.atlas = source.terrain_atlas
	reference.view_offset = preload("res://scripts/pixel_scaling.gd").snap_screen(source.view_offset)
	reference.view_zoom = source.view_zoom
	reference.viewport_size = source.viewport_size
	reference.transform = source.transform
	reference.z_index = source.z_index
	reference.texture_filter = source.texture_filter
	reference.texture_repeat = source.texture_repeat
	var was_visible: bool = source.visible
	source.get_parent().add_child(reference)
	source.hide()
	var rows: Array = []
	for compact in [false, true]:
		request["compact_planar_base"] = compact
		var metrics: Dictionary = {}
		var arrays: Array = mesh_job.build_request(kernel, request, 16, metrics)
		var vertices: int = arrays[Mesh.ARRAY_VERTEX].size()
		var indices: int = arrays[Mesh.ARRAY_INDEX].size()
		var chunks: Array = kernel.split_mesh_arrays(arrays, 16384)
		reference.meshes = []
		for chunk in chunks:
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk)
			reference.meshes.append(mesh)
		rows.append({"compact":compact,"bounds":bounds,"vertices":vertices,"indices":indices,"timings":metrics})
		reference.queue_redraw()
		game.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + (".terrain-compacted.png" if compact else ".terrain-original.png"))
	source.visible = was_visible
	reference.free()
	game.freeze_sprite_reference = previous_frozen
	game.sprite_reference_drawables = previous_drawables
	var file := FileAccess.open(output + ".terrain-reference.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(rows, "\t")); file.close()

func profile_memory_retirement(output: String) -> void:
	# Teardown attribution runs after the gameplay samples and PNG capture.
	# Only this diagnostic match is consumed; no live user match is attached.
	var rows: Array = []
	var owners := {"world":weakref(game.simulation_world),"controller":weakref(game.game_controller),"catalog":weakref(game.resource_catalog),"units":weakref(game.resource_catalog.unit_presentations),"buildings":weakref(game.resource_catalog.building_presentations),"effects":weakref(game.resource_catalog.effect_presentations),"palette":weakref(game.resource_catalog.player_palette),"texture_queue":weakref(game.resource_catalog.unit_presentations.texture_queue),"render_world":weakref(game.render_world),"atlas":weakref(game.render_world.sprite_atlas),"ai_runtime":weakref(game.ai_runtime),"observations":weakref(game.ai_observation_store)}
	var sample := func(stage: String):
		var alive := {}
		for key in owners: alive[key] = owners[key].get_ref() != null
		rows.append({"stage":stage,"static_bytes":OS.get_static_memory_usage(),"video_bytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"immutable_roots":RoRIsolatedTaskData.immutable_roots.size(),"sealed_roots":RoRIsolatedTaskData.sealed_roots.size(),"alive":alive})
	var atlas := {"pages":game.render_world.sprite_atlas.pages.size(),"entries":game.render_world.sprite_atlas.entries.size(),"page_image_bytes":0}
	for page in game.render_world.sprite_atlas.pages:
		atlas["page_image_bytes"] += page["image"].get_data_size()
	var counts := {"units":game.simulation_world.units.size(),"resources":game.simulation_world.resource_nodes.size(),"ai_observers":game.ai_observation_store.observer_caches.size(),"palette_cache_entries":game.resource_catalog.player_palette.cached_textures.size(),"atlas":atlas}
	sample.call("loaded_match")
	game.autosave.shutdown()
	game.background_saves.drain()
	game.navigation_loading.shutdown()
	game.resource_catalog.unit_presentations.shutdown_loading()
	game.match_lifecycle.retire_runtime(game.simulation_world, game.ai_runtime, game.render_snapshot_source, game.ai_decision_queue, game.task_coordinator, false)
	sample.call("jobs_and_ai_views_released")
	var location_sharing := {}
	if "--measure-resource-location-sharing" in OS.get_cmdline_user_args():
		location_sharing = measure_resource_location_sharing()
		sample.call("resource_locations_shared")
	var storage_graph := {}
	if "--profile-memory-graph" in OS.get_cmdline_user_args(): storage_graph = profile_owned_storage_graph()
	game.presentation_snapshot = {}
	game.units = []
	game.resource_nodes = []
	game.overview_units = []
	game.overview_resource_nodes = []
	game.overview_buildings = []
	game.cached_world_drawables = []
	game.cached_environment_items = []
	game.cached_rally_drawables = []
	game.render_world.clear_caches()
	game.environment_presentation_field.configure([])
	game.presentation_publication.clear()
	sample.call("presentation_cpu_caches_released")
	game.simulation_world.shutdown_derived_state()
	sample.call("world_derived_state_released")
	game.terrain_canvas.free()
	game.terrain_canvas = null
	sample.call("terrain_canvas_released")
	game.render_terrain_view = null
	game.game_controller = null
	game.simulation_world = null
	sample.call("world_and_controller_owners_released")
	game.resource_catalog = null
	sample.call("resource_catalog_owner_released")
	game.free()
	game = null
	probe.clear()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	sample.call("match_freed_and_render_flushed")
	for index in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	sample.call("four_more_render_frames")
	# No world or producers remain. Quantify the process-wide trust registries
	# independently; clearing these only occurs in this terminating diagnostic.
	RoRIsolatedTaskData.seal_mutex.lock()
	RoRIsolatedTaskData.immutable_roots.clear()
	RoRIsolatedTaskData.sealed_roots.clear()
	RoRIsolatedTaskData.seal_mutex.unlock()
	sample.call("trust_registries_released")
	var file := FileAccess.open(output + ".memory.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"counts":counts,"load_phases":memory_load_phases,"retirement":rows,"storage_graph":storage_graph,"location_sharing":location_sharing},"\t"))
		file.close()
	print("MEMORY_RETIREMENT ", JSON.stringify(rows))


func measure_resource_location_sharing() -> Dictionary:
	# Compare detached presentation values around conversion after this match's
	# producers have stopped. The measurements never feed back into gameplay.
	var components_script = preload("res://scripts/entity_components.gd")
	var samples: Array = []
	var sampled_kinds := {}
	for resource in game.simulation_world.resource_nodes:
		var kind := String(resource.get("kind", resource.get("type", "")))
		if int(sampled_kinds.get(kind, 0)) >= 4: continue
		sampled_kinds[kind] = int(sampled_kinds.get(kind, 0)) + 1
		samples.append({"resource":resource,"view":components_script.view(resource)})
	var before := OS.get_static_memory_usage()
	var started := Time.get_ticks_usec()
	var pool = game.simulation_world.resource_component_pool
	pool.location_templates_enabled = true
	for resource in game.simulation_world.resource_nodes: pool.intern(resource)
	var elapsed := Time.get_ticks_usec() - started
	var after := OS.get_static_memory_usage()
	var differences := 0
	for sample in samples:
		if sample["view"] != components_script.view(sample["resource"]): differences += 1
	return {"memory_before":before,"memory_after":after,"elapsed_us":elapsed,"sample_count":samples.size(),"sample_value_differences":differences,"templates":pool.template_count,"encoded_bytes":pool.retained_bytes,"location_binding_records":pool.location_binding_records}


func profile_owned_storage_graph() -> Dictionary:
	var checkpoint_script = preload("res://scripts/game_checkpoint.gd")
	var roots := {}
	for name in ["identity","transform","movement","order","trade","footprint","combat","conversion","healing","worker","resource_carrier","ownership","production","technology","vision","animation_state","health","cargo"]:
		var records: Array = []
		for resource in game.simulation_world.resource_nodes:
			var component: Variant = resource.get("components", {}).get(name)
			if component is Dictionary: records.append(component)
		roots["resource_component." + name] = records
	roots["resources"] = game.simulation_world.resource_nodes
	roots["units"] = game.simulation_world.units
	roots["buildings"] = game.simulation_world.buildings
	roots["world"] = checkpoint_script._capture_fields(game.simulation_world, checkpoint_script.WORLD_FIELDS, false)
	roots["grid"] = checkpoint_script._capture_fields(game.simulation_world.navigation_grid, checkpoint_script.GRID_FIELDS, false)
	roots["fog"] = checkpoint_script._capture_fields(game.simulation_world.fog_of_war, checkpoint_script.FOG_FIELDS, false)
	for name in checkpoint_script.SYSTEM_FIELDS:
		roots["system." + name] = checkpoint_script._capture_fields(game.simulation_world.get(name), checkpoint_script.SYSTEM_FIELDS[name], false)
	for team in game.simulation_world.movement_system.knowledge.entries:
		roots["knowledge." + str(team)] = checkpoint_script._capture_fields(game.simulation_world.movement_system.knowledge.entries[team]["grid"], checkpoint_script.GRID_FIELDS, false)
	roots["known_resources"] = game.simulation_world.known_resources_by_player
	roots["known_ai_resources"] = game.simulation_world.known_ai_resources_by_player
	roots["catalogs"] = {"assets":game.resource_catalog.asset_records,"objects":game.resource_catalog.object_catalog_data,"graphics":game.resource_catalog.graphics_catalog_data,"runtime":game.resource_catalog.runtime_catalog_data,"terrain":game.resource_catalog.terrain_catalog_data}
	var result: Dictionary = game.simulation_world.movement_system.integration_kernel.profile_storage_graph(roots)
	result["category_note"] = "Component categories include temporary array wrappers; shared storage is charged to the first category. Counts and string/packed payloads are not total allocator bytes."
	return result


func simulation_pause_summary(rows: Array) -> Dictionary:
	var waits: Array = []
	var gaps: Array = []
	var held := 0
	var previous_tick := -1
	var previous_advance := 0.0
	for row in rows:
		if row["waiting"]: held += int(row["frame_us"])
		elif held > 0: waits.append(held);held=0
		if int(row["tick"]) != previous_tick:
			if previous_tick >= 0: gaps.append(roundi((float(row["seconds"])-previous_advance)*1000000.0))
			previous_tick=int(row["tick"])
			previous_advance=float(row["seconds"])
	if held > 0: waits.append(held)
	var result := {"waits_us":BaseProbe.summarize(waits),"tick_gaps_us":BaseProbe.summarize(gaps),"total_wait_us":0}
	for value in waits: result["total_wait_us"] += int(value)
	return result


func motion_sample() -> Dictionary:
	var moving:=0
	var stationary:=0
	var stop_pixels:=0.0
	var next_animations: Dictionary={}
	var reversed:=0
	var pose_pairs: Dictionary={}
	var present: Dictionary={}
	# Retained render items belong to the main thread and contain the actual
	# interpolated world anchors used by the last draw. Do not read live actors.
	for item in game.cached_world_drawables:
		if String(item.get("kind",""))!="unit": continue
		var data: Dictionary=item.get("data",{})
		if int(data.get("team",0))!=game.local_player_team: continue
		var id:=int(item["stable_id"])
		var position:=Vector2(item["world_anchor"])
		present[id]=position
		var animation:=String(data.get("anim_state",""))
		next_animations[id]=animation
		if previous_anchors.has(id) and previous_animations.get(id,"") in ["Move","Carry"] and animation not in ["Move","Carry"]:
			stop_pixels=maxf(stop_pixels,game.world_to_screen(Vector2(previous_anchors[id])).distance_to(game.world_to_screen(position)))
		var pair: Array=[Vector2(data.get("previous_pos",data["pos"])),Vector2(data["pos"])]
		pose_pairs[id]=pair
		if Vector2(data.get("previous_pos",data["pos"])).distance_squared_to(Vector2(data["pos"]))<0.00000001: continue
		if String(data.get("anim_state","")) not in ["Move","Carry"]: continue
		moving+=1
		if previous_anchors.has(id):
			var shown_delta:=position-Vector2(previous_anchors[id])
			if shown_delta.length_squared()<0.00000001: stationary+=1
			if previous_pose_pairs.get(id)==pair and shown_delta.dot(Vector2(pair[1])-Vector2(pair[0])) < -0.00000001: reversed+=1
	previous_anchors=present
	previous_pose_pairs=pose_pairs
	previous_animations=next_animations
	return {"moving_units":moving,"stationary_moving_units":stationary,"rewinding_moving_units":reversed,"stop_correction_millipixels":roundi(stop_pixels*1000.0)}

func motion_summary(rows: Array) -> Dictionary:
	var moving_samples:=0
	var stalled_samples:=0
	var reversed_samples:=0
	var all_still_us:=0
	var durations: Array=[]
	var stop_corrections: Array=[]
	for row in rows:
		if int(row.get("stop_correction_millipixels",0))>0: stop_corrections.append(int(row["stop_correction_millipixels"]))
		moving_samples+=int(row.get("moving_units",0))
		stalled_samples+=int(row.get("stationary_moving_units",0))
		reversed_samples+=int(row.get("rewinding_moving_units",0))
		if int(row.get("moving_units",0))>=2 and int(row.get("moving_units",0))==int(row.get("stationary_moving_units",0)):
			all_still_us+=int(row["frame_us"])
		elif all_still_us>0:
			durations.append(all_still_us);all_still_us=0
	if all_still_us>0:durations.append(all_still_us)
	return {"moving_actor_frame_samples":moving_samples,"stationary_moving_actor_frame_samples":stalled_samples,"rewinding_moving_actor_frame_samples":reversed_samples,"all_moving_still_us":BaseProbe.summarize(durations),"stop_correction_millipixels":BaseProbe.summarize(stop_corrections)}


func render_submission_summary(items: Array) -> Dictionary:
	var kinds: Dictionary = {}
	var atlas_rids: Dictionary = {}
	var atlas_by_kind: Dictionary = {}
	var sprite_atlas = game.render_world.sprite_atlas
	for page in sprite_atlas.pages: atlas_rids[page["texture"].get_rid()] = true
	var fallback_kinds: Dictionary = {}
	var fallback_features: Dictionary = {}
	var textures: Dictionary = {}
	var runs: Array = []
	var current_rid := RID()
	var run := 0
	var sprites := 0
	var immutable_stationary_units := 0
	for item in items:
		var kind := String(item.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var source: Dictionary = item.get("data", {})
		if kind == "unit" and source.is_read_only() and source.has("pos") and source.has("previous_pos") and source["pos"] == source["previous_pos"]: immutable_stationary_units += 1
		var command: Array = item.get("sprite_command", [])
		if command.size() < 5:
			fallback_kinds[kind] = int(fallback_kinds.get(kind, 0)) + 1
			var info: Dictionary = item.get("frame_info", {})
			var feature := "shore" if info.has("shore_geometry") else ("river" if info.has("river_geometry") else ("mirrored" if bool(info.get("mirrored", false)) else kind))
			fallback_features[feature] = int(fallback_features.get(feature, 0)) + 1
			if run > 0: runs.append(run)
			run = 0
			current_rid = RID()
			continue
		sprites += 1
		var rid: RID = command[3]
		if not atlas_by_kind.has(kind): atlas_by_kind[kind] = {"sprites":0,"atlased":0,"textures":{}}
		atlas_by_kind[kind]["sprites"] += 1
		atlas_by_kind[kind]["atlased"] += int(atlas_rids.has(rid))
		atlas_by_kind[kind]["textures"][rid] = true
		textures[rid] = true
		if rid != current_rid and run > 0:
			runs.append(run)
			run = 0
		current_rid = rid
		run += 1
	if run > 0: runs.append(run)
	var batches := 0
	for length in runs: batches += ceili(float(length) / 512.0) if length >= 4 else length
	for kind in atlas_by_kind: atlas_by_kind[kind]["textures"] = atlas_by_kind[kind]["textures"].size()
	return {"immutable_stationary_units":immutable_stationary_units, "items":items.size(), "sprites":sprites, "kinds":kinds, "fallback_kinds":fallback_kinds, "fallback_features":fallback_features, "textures":textures.size(), "runs":BaseProbe.summarize(runs), "estimated_sprite_submissions":batches,"atlas_pages":sprite_atlas.pages.size(),"atlas_entries":sprite_atlas.entries.size(),"atlas_by_kind":atlas_by_kind}
