class_name RoRGameController

const RoRCommands = preload("res://scripts/commands.gd")
const FormationGroup := preload("res://scripts/formation_group.gd")
const FormationCorridor := preload("res://scripts/formation_corridor.gd")
const FormationLifecycle := preload("res://scripts/formation_lifecycle.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const CommandResult := preload("res://scripts/command_result.gd")
const SimulationEventStream := preload("res://scripts/simulation_event_stream.gd")
const CombatAwarenessSystem := preload("res://scripts/combat_awareness_system.gd")
const WildlifeBehaviorSystem := preload("res://scripts/wildlife_behavior_system.gd")

# Existing openage simulation clock data limits an iteration to 50 ms.
# See libopenage/time/clock.cpp. Game-speed multipliers are documented in
# doc/reverse_engineering/networking/13-other.md.
const FIXED_STEP_SECONDS: float = 0.05
const GAME_SPEEDS := [1.0, 1.5, 2.0]
const MAX_STEPS_PER_FRAME: int = 12

var simulation_world
var tick_index: int = 0
var command_queue: Array = []
var next_command_sequence: int = 1
var command_results: Dictionary = {}
var event_stream := SimulationEventStream.new()
var combat_awareness := CombatAwarenessSystem.new()
var wildlife_behavior := WildlifeBehaviorSystem.new()
var accumulator_seconds: float = 0.0
var speed_index: int = 1
var paused: bool = false
var formation_groups: Dictionary = {}
var next_formation_group_id: int = 1
var replay_recorder: Variant = null
var replay_source: Variant = null
var record_replay_state_hashes := true
var last_replay_mismatch: String = ""
var performance_probe: Variant = null
var before_fixed_tick: Callable = Callable()

func _init(world = null) -> void:
	simulation_world = world

func set_world(world) -> void:
	simulation_world = world
	if simulation_world != null and simulation_world.has_method("set_performance_probe"):
		simulation_world.set_performance_probe(performance_probe)
	if simulation_world != null and simulation_world.has_method("set_formation_cohesion_active"):
		simulation_world.set_formation_cohesion_active(not formation_groups.is_empty())


func set_performance_probe(probe: Variant) -> void:
	performance_probe = probe
	if simulation_world != null and simulation_world.has_method("set_performance_probe"):
		simulation_world.set_performance_probe(probe)


func set_before_fixed_tick(callback: Callable) -> void:
	before_fixed_tick = callback

func enqueue_command(command, record: bool = true, issuer_id: int = 0) -> void:
	if command == null:
		return
	if int(command.sequence_id) <= 0:
		command.assign_envelope(issuer_id, next_command_sequence)
	else:
		# Replayed commands already own their original envelope.
		command.assign_envelope(int(command.issuer_id), int(command.sequence_id))
	next_command_sequence = maxi(next_command_sequence, int(command.sequence_id) + 1)
	command_queue.append(command)
	if record and replay_recorder != null:
		replay_recorder.record_command(command, tick_index)


func start_recording(seed_value: int = 1337, capture_state_hashes: bool = true):
	replay_recorder = ReplaySystem.new()
	replay_recorder.begin(seed_value)
	replay_source = null
	record_replay_state_hashes = capture_state_hashes
	if simulation_world != null:
		simulation_world.set_simulation_seed(seed_value)
	return replay_recorder


func stop_recording():
	var completed = replay_recorder
	replay_recorder = null
	return completed


func install_recording_history(replay_data: Dictionary, capture_state_hashes: bool = false) -> bool:
	var history := ReplaySystem.new()
	if not history.load_dictionary(replay_data):
		return false
	history.state_hashes.clear()
	history.playback_cursor = 0
	replay_recorder = history
	record_replay_state_hashes = capture_state_hashes
	return true


func load_replay(data: Variant) -> bool:
	var source = ReplaySystem.new()
	var loaded := source.load_dictionary(data) if data is Dictionary else source.load_json(String(data))
	if not loaded:
		return false
	replay_source = source
	replay_source.reset_playback()
	last_replay_mismatch = ""
	clear_queue()
	command_results.clear()
	event_stream.clear()
	next_command_sequence = 1
	_inject_replay_commands_for_current_tick()
	if simulation_world != null:
		simulation_world.set_simulation_seed(source.simulation_seed)
	return true

func clear_queue() -> void:
	command_queue.clear()

func reset_timing() -> void:
	tick_index = 0
	accumulator_seconds = 0.0
	next_command_sequence = 1
	clear_queue()
	command_results.clear()
	event_stream.clear()
	formation_groups.clear()
	next_formation_group_id = 1
	last_replay_mismatch = ""
	combat_awareness.reset()
	wildlife_behavior.reset()
	if replay_source != null:
		replay_source.reset_playback()

func set_paused(value: bool) -> void:
	paused = value

func toggle_paused() -> bool:
	paused = not paused
	return paused

func set_speed_multiplier(value: float) -> void:
	var nearest_index := 0
	var nearest_distance := INF
	for index in range(GAME_SPEEDS.size()):
		var distance: float = absf(float(GAME_SPEEDS[index]) - value)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	speed_index = nearest_index

func cycle_speed(direction: int) -> float:
	speed_index = clampi(speed_index + direction, 0, GAME_SPEEDS.size() - 1)
	return get_speed_multiplier()

func get_speed_multiplier() -> float:
	return float(GAME_SPEEDS[speed_index])

func get_interpolation_alpha() -> float:
	return clampf(accumulator_seconds / FIXED_STEP_SECONDS, 0.0, 1.0)


func replay_until_tick(target_tick: int, player_team: int, enemy_team: int) -> bool:
	if replay_source == null or simulation_world == null or target_tick < tick_index:
		return false
	var was_paused := paused
	paused = false
	while tick_index < target_tick:
		_run_fixed_tick(player_team, enemy_team)
	# A live player may issue a future command after the last completed tick and
	# save before another tick begins. Restore that pending queue as well.
	_inject_replay_commands_for_current_tick()
	paused = was_paused
	accumulator_seconds = 0.0
	return tick_index == target_tick and last_replay_mismatch.is_empty()

func process_commands() -> void:
	command_queue.sort_custom(_command_less)
	var pending: Array = []
	for command in command_queue:
		if command.tick > tick_index:
			pending.append(command)
			continue
		var previous_tasks := _unit_task_states(command.unit_ids)
		var result: Dictionary = _dispatch_command(command)
		command_results[int(command.sequence_id)] = result
		var event_type := "command_accepted" if bool(result["accepted"]) else "command_rejected"
		event_stream.emit(tick_index, event_type, result)
		if bool(result["accepted"]):
			_emit_command_task_changes(command, previous_tasks)
	command_queue = pending


func _dispatch_command(command) -> Dictionary:
	var rejection_reason := "unsupported_command"
	if int(command.issuer_id) > 0 and simulation_world.player_registry.status(int(command.issuer_id)) != "active":
		return CommandResult.rejected(command, tick_index, "player_not_active")
	match command.command_type():
		"move":
			rejection_reason = _apply_move(command)
		"attack_move":
			rejection_reason = _apply_attack_move(command)
		"formation_move":
			rejection_reason = _apply_formation_move(command)
		"attack":
			rejection_reason = _apply_attack(command)
		"convert":
			rejection_reason = _apply_convert(command)
		"heal":
			rejection_reason = _apply_heal(command)
		"martyrdom":
			rejection_reason = _apply_martyrdom(command)
		"gather":
			rejection_reason = _apply_gather(command)
		"return_resources":
			rejection_reason = _apply_return_resources(command)
		"board":
			rejection_reason = _apply_board(command)
		"unload":
			rejection_reason = _apply_unload(command)
		"set_trade_resource":
			rejection_reason = _apply_set_trade_resource(command)
		"trade":
			rejection_reason = _apply_trade(command)
		"build":
			rejection_reason = _apply_build(command)
		"repair":
			rejection_reason = _apply_repair(command)
		"train":
			rejection_reason = _apply_train(command)
		"research":
			rejection_reason = _apply_research(command)
		"cancel_production":
			rejection_reason = _apply_cancel_production(command)
		"stance":
			rejection_reason = _apply_stance(command)
		"stop", "hold":
			rejection_reason = _apply_halt(command)
		"diplomacy":
			rejection_reason = _apply_diplomacy(command)
		"resign":
			rejection_reason = _apply_resign(command)
	if rejection_reason.is_empty():
		return CommandResult.accepted(command, tick_index)
	return CommandResult.rejected(command, tick_index, rejection_reason)


func get_command_result(sequence_id: int) -> Dictionary:
	return command_results.get(sequence_id, {}).duplicate(true)


func events_after(sequence_id: int = 0) -> Array:
	return event_stream.events_after(sequence_id)


func _unit_task_states(unit_ids: Array[int]) -> Dictionary:
	var result: Dictionary = {}
	for unit_id in unit_ids:
		var unit = simulation_world.find_combat_target(unit_id)
		if unit != null:
			result[int(unit_id)] = String(unit.get("task", "idle"))
	return result


func _emit_command_task_changes(command, previous_tasks: Dictionary) -> void:
	var ids: Array = previous_tasks.keys()
	ids.sort()
	for unit_id_value in ids:
		var unit_id := int(unit_id_value)
		var unit = simulation_world.find_combat_target(unit_id)
		if unit == null:
			continue
		var previous_task := String(previous_tasks[unit_id])
		var current_task := String(unit.get("task", "idle"))
		if previous_task == current_task:
			continue
		event_stream.emit(tick_index, "task_changed", {
			"entity_id": unit_id,
			"previous_task": previous_task,
			"current_task": current_task,
			"issuer_id": int(command.issuer_id),
			"command_sequence_id": int(command.sequence_id),
		})


func _all_unit_task_states() -> Array:
	# get_combat_attackers() already guarantees stable entity-ID order. Keep the
	# entity reference beside its task instead of building a Dictionary, sorting
	# its keys and resolving every entity a second time after the world tick.
	var result: Array = []
	for unit in simulation_world.get_combat_attackers():
		result.append(unit)
		result.append(String(unit.get("task", "idle")))
	return result


func _emit_runtime_task_changes(previous_tasks: Array) -> void:
	for index in range(0, previous_tasks.size(), 2):
		var unit: Dictionary = previous_tasks[index]
		if bool(unit.get("removed", false)):
			continue
		var unit_id := int(unit.get("id", -1))
		var previous_task := String(previous_tasks[index + 1])
		var current_task := String(unit.get("task", "idle"))
		if previous_task == current_task:
			continue
		event_stream.emit(tick_index, "task_changed", {
			"entity_id": unit_id,
			"previous_task": previous_task,
			"current_task": current_task,
			"issuer_id": 0,
			"command_sequence_id": 0,
		})


func _forward_domain_events() -> void:
	for domain_event in simulation_world.drain_domain_events():
		event_stream.emit(tick_index, String(domain_event.get("type", "unknown")), domain_event.get("payload", {}))


func _command_less(left, right) -> bool:
	if int(left.tick) != int(right.tick):
		return int(left.tick) < int(right.tick)
	if int(left.sequence_id) != int(right.sequence_id):
		return int(left.sequence_id) < int(right.sequence_id)
	if int(left.issuer_id) != int(right.issuer_id):
		return int(left.issuer_id) < int(right.issuer_id)
	return String(left.command_type()) < String(right.command_type())

func _apply_move(command) -> String:
	var target = command.target
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	if selected.is_empty():
		return "no_eligible_units"
	_detach_units_from_formations(selected)
	return "" if simulation_world.assign_command_move(selected, target) else "no_path"

func _apply_attack_move(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	if selected.is_empty():
		return "no_eligible_units"
	_detach_units_from_formations(selected)
	return "" if simulation_world.assign_command_attack_move(selected, command.target) else "no_path"

func _apply_formation_move(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	if selected.is_empty():
		return "no_eligible_units"
	var target = command.target
	var formation_name := "RECTANGLE"
	var forward := Vector2.ZERO
	if command.params != null and command.params.has("formation"):
		formation_name = String(command.params["formation"])
	if command.params != null and command.params.has("forward"):
		forward = command.params["forward"]
	return "" if _assign_formation(selected, target, formation_name, forward) else "no_path"

func _apply_attack(command) -> String:
	var selected = _combat_entities_for_ids(command.unit_ids, command.issuer_id)
	var attackers: Array = selected.filter(func(unit): return bool(unit.get("combat_enabled", false)))
	if attackers.is_empty():
		return "no_eligible_units"
	var target = simulation_world.find_combat_target(command.target_entity_id)
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_target"
	if attackers.all(func(unit): return simulation_world.are_teams_allied(int(unit.get("team", 0)), int(target.get("team", 0)))):
		return "friendly_target"
	return "" if simulation_world.assign_command_attack(attackers, command.target_entity_id, command.params) else "unreachable_target"


func _apply_convert(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	var converters: Array = selected.filter(func(unit): return simulation_world.conversion_system.is_converter(unit))
	if converters.is_empty():
		return "no_eligible_converters"
	var target = simulation_world.find_combat_target(command.target_entity_id)
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_target"
	var rejection: String = simulation_world.conversion_system.validate_target(converters[0], target)
	if not rejection.is_empty():
		return rejection
	_detach_units_from_formations(converters)
	return simulation_world.assign_command_convert(converters, command.target_entity_id)


func _apply_heal(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	var healers: Array = selected.filter(func(unit): return simulation_world.healing_system.is_healer(unit))
	if healers.is_empty():
		return "no_eligible_healers"
	var target = simulation_world.find_unit(command.target_entity_id)
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_healing_target"
	var rejection: String = simulation_world.healing_system.validate_target(healers[0], target)
	if not rejection.is_empty():
		return rejection
	_detach_units_from_formations(healers)
	return simulation_world.assign_command_heal(healers, command.target_entity_id)


func _apply_martyrdom(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	if selected.is_empty():
		return "no_eligible_martyr"
	return simulation_world.apply_martyrdom(selected)

func _apply_gather(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	var workers: Array = selected.filter(func(unit): return simulation_world.entity_is_worker(unit))
	if workers.is_empty():
		return "no_eligible_workers"
	var resource = simulation_world.find_resource(command.resource_id)
	if resource == null or int(resource.get("amount", 0)) <= 0:
		return "resource_unavailable"
	if workers.any(func(worker): return not simulation_world.resource_accessible_to_team(resource, int(worker.get("team", 0)))):
		return "resource_not_owned"
	if workers.any(func(worker): return not simulation_world.resource_allows_worker(resource, worker)):
		return "incompatible_gatherer"
	_detach_units_from_formations(workers)
	simulation_world.assign_command_gather(workers, command.resource_id)
	return ""


func _apply_return_resources(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	var workers: Array = selected.filter(func(unit): return simulation_world.entity_is_worker(unit) and float(unit.get("carried_amount", 0.0)) > 0.0)
	if workers.is_empty():
		return "no_carried_resources"
	_detach_units_from_formations(workers)
	return "" if simulation_world.assign_command_return_resources(workers, int(command.target_building_id)) else "invalid_dropoff"


func _apply_board(command) -> String:
	var passengers := _units_for_ids(command.unit_ids, command.issuer_id)
	if passengers.is_empty():
		return "no_eligible_passengers"
	var transport = simulation_world.find_unit(int(command.transport_id))
	if transport == null or (int(command.issuer_id) > 0 and int(transport.get("team", 0)) != int(command.issuer_id)):
		return "invalid_transport"
	_detach_units_from_formations(passengers)
	return simulation_world.board_units(passengers, transport)


func _apply_unload(command) -> String:
	var transports := _units_for_ids(command.unit_ids, command.issuer_id)
	if transports.is_empty():
		return "invalid_transport"
	return simulation_world.unload_transports(transports, command.target, command.passenger_ids)


func _apply_set_trade_resource(command) -> String:
	var selected := _units_for_ids(command.unit_ids, command.issuer_id)
	var traders: Array = selected.filter(func(unit): return simulation_world.trade_system.is_trader(unit))
	if traders.is_empty() or traders.size() != selected.size():
		return "no_eligible_traders"
	return simulation_world.set_trade_resource(traders, int(command.resource_type_id))


func _apply_trade(command) -> String:
	var selected := _units_for_ids(command.unit_ids, command.issuer_id)
	var traders: Array = selected.filter(func(unit): return simulation_world.trade_system.is_trader(unit))
	if traders.is_empty() or traders.size() != selected.size():
		return "no_eligible_traders"
	var target = simulation_world.find_building(int(command.target_dock_id))
	if target == null:
		return "invalid_trade_dock"
	_detach_units_from_formations(traders)
	return simulation_world.assign_command_trade(traders, target)


func _apply_build(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	var workers: Array = selected.filter(func(unit): return simulation_world.entity_is_worker(unit))
	if workers.is_empty():
		return "no_eligible_workers"
	_detach_units_from_formations(workers)
	var foundation = simulation_world.assign_command_build(workers, command.building_type, command.target)
	return "" if foundation != null else String(simulation_world.last_build_failure if not simulation_world.last_build_failure.is_empty() else "build_rejected")


func _apply_repair(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	var workers: Array = selected.filter(func(unit): return simulation_world.entity_is_worker(unit))
	if workers.is_empty():
		return "no_eligible_workers"
	_detach_units_from_formations(workers)
	return "" if simulation_world.assign_command_repair(workers, command.target_building_id) else "repair_rejected"

func _apply_train(command) -> String:
	if int(command.issuer_id) > 0 and int(command.team) != int(command.issuer_id):
		return "issuer_team_mismatch"
	if not command.unit_ids.is_empty():
		var building = simulation_world.find_building(int(command.unit_ids[0]))
		if building == null or float(building.get("hp", 0.0)) <= 0.0:
			return "invalid_production_building"
		if int(command.issuer_id) > 0 and int(building.get("team", 0)) != int(command.issuer_id):
			return "issuer_team_mismatch"
		var order = simulation_world.enqueue_unit_production(int(building["id"]), int(command.team), String(command.unit_type))
		return "" if order != null else String(simulation_world.last_production_failure if not simulation_world.last_production_failure.is_empty() else "train_rejected")
	return "" if simulation_world.train_unit(command.team, command.unit_type, command.target) else String(simulation_world.last_production_failure if not simulation_world.last_production_failure.is_empty() else "train_rejected")


func _apply_research(command) -> String:
	if command.unit_ids.is_empty():
		return "missing_research_building"
	var building = simulation_world.find_building(int(command.unit_ids[0]))
	if building == null:
		return "invalid_research_building"
	if int(command.issuer_id) > 0 and int(building.get("team", 0)) != int(command.issuer_id):
		return "issuer_team_mismatch"
	var order = simulation_world.enqueue_research(int(building["id"]), int(building.get("team", 0)), int(command.technology))
	return "" if order != null else String(simulation_world.last_research_failure if not simulation_world.last_research_failure.is_empty() else "research_rejected")


func _apply_cancel_production(command) -> String:
	if command.unit_ids.is_empty():
		return "invalid_production_building"
	var building = simulation_world.find_building(int(command.unit_ids[0]))
	if building == null or float(building.get("hp", 0.0)) <= 0.0:
		return "invalid_production_building"
	if int(command.issuer_id) > 0 and int(building.get("team", 0)) != int(command.issuer_id):
		return "issuer_team_mismatch"
	return "" if simulation_world.cancel_production(int(building["id"]), int(command.queue_index)) else "invalid_queue_item"


func _apply_halt(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	if selected.is_empty():
		return "no_eligible_units"
	_detach_units_from_formations(selected)
	for unit in selected:
		if unit == null:
			continue
		simulation_world.halt_unit(unit, command.command_type())
		if command.command_type() == "hold":
			unit["stance"] = "stand_ground"
			unit["diagnostic_reason"] = "hold_position"
	return ""


func _apply_resign(command) -> String:
	if int(command.issuer_id) <= 0:
		return "invalid_issuer"
	return "" if simulation_world.resign_team(int(command.issuer_id)) else "player_not_active"


func _apply_diplomacy(command) -> String:
	var issuer := int(command.issuer_id)
	if issuer <= 0:
		return "invalid_issuer"
	if int(command.target_team) == issuer:
		return "diplomacy_self_target"
	if not simulation_world.player_registry.players.has(int(command.target_team)):
		return "diplomacy_player_missing"
	if not RoRCommands.is_valid_diplomacy_relation(String(command.relation)):
		return "diplomacy_relation_invalid"
	return "" if simulation_world.set_diplomacy_relation(issuer, int(command.target_team), String(command.relation)) else "diplomacy_rejected"


func _apply_stance(command) -> String:
	var selected = _units_for_ids(command.unit_ids, command.issuer_id)
	if selected.is_empty():
		return "no_eligible_units"
	var stance := String(command.params.get("stance", ""))
	if not RoRCommands.is_valid_stance(stance):
		return "invalid_stance"
	for unit in selected:
		unit["stance"] = stance
		unit["diagnostic_reason"] = "stance:%s" % stance
	return ""

func _units_for_ids(unit_ids: Array[int], issuer_id: int = 0) -> Array:
	var selected: Array = []
	for id in unit_ids:
		var unit = simulation_world.find_unit(id)
		if unit != null and (issuer_id <= 0 or int(unit.get("team", 0)) == issuer_id):
			selected.append(unit)
	return selected


func _combat_entities_for_ids(entity_ids: Array[int], issuer_id: int = 0) -> Array:
	var selected: Array = []
	for entity_id in entity_ids:
		var entity = simulation_world.find_combat_target(entity_id)
		if entity != null and (issuer_id <= 0 or int(entity.get("team", 0)) == issuer_id):
			selected.append(entity)
	return selected

func _assign_formation(selected: Array, anchor: Vector2, formation_name: String, requested_forward: Vector2 = Vector2.ZERO) -> bool:
	if selected.is_empty():
		return false
	var formation_probe_started := Time.get_ticks_usec() if performance_probe != null else 0
	var clamped_anchor := anchor
	clamped_anchor.x = clampf(clamped_anchor.x, 1.0, simulation_world.get_map_size().x - 1.0)
	clamped_anchor.y = clampf(clamped_anchor.y, 1.0, simulation_world.get_map_size().y - 1.0)

	var center := Vector2.ZERO
	for unit in selected:
		center += unit["pos"]
	center /= float(selected.size())

	# A short RMB move keeps the group's current front. Only an explicit drag
	# rotates it; a new group without a front initially faces along its route.
	var forward := requested_forward.normalized() if requested_forward.length_squared() > 0.0001 else Vector2.ZERO
	if forward == Vector2.ZERO:
		var existing_forward: Vector2 = selected[0].get("formation_forward", Vector2.ZERO)
		if existing_forward.length_squared() > 0.0001:
			forward = existing_forward.normalized()
	if forward == Vector2.ZERO:
		forward = (clamped_anchor - center).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2(0.0, -1.0)
	var formation_facing: int = simulation_world.facing_for_vector(forward)
	var ordered := selected.duplicate()
	ordered.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	var member_ids: Array[int] = []
	var previous_assignments: Dictionary = {}
	var previous_group_id := -1
	var resolved_count := 0
	for unit in ordered:
		member_ids.append(int(unit["id"]))
		var unit_group_id := int(unit.get("formation_group_id", -1))
		if previous_group_id < 0:
			previous_group_id = unit_group_id
		elif previous_group_id != unit_group_id:
			previous_group_id = -2
	var previous_group = formation_groups.get(previous_group_id)
	if previous_group != null and previous_group.formation_type == formation_name and previous_group.member_ids == member_ids:
		for unit in ordered:
			if int(unit.get("formation_slot_id", -1)) >= 0:
				previous_assignments[int(unit["id"])] = int(unit["formation_slot_id"])
	var replaced_group_ids: Dictionary = {}
	for unit in ordered:
		var replaced_group_id := int(unit.get("formation_group_id", -1))
		if replaced_group_id >= 0:
			replaced_group_ids[replaced_group_id] = true
	var group = FormationGroup.new(next_formation_group_id, member_ids, clamped_anchor, forward, formation_name, 1.0)
	group.policy["orientation"] = "command" if requested_forward.length_squared() > 0.0001 else "route"
	if performance_probe != null:
		performance_probe.observe_microseconds("formation.group_setup", Time.get_ticks_usec() - formation_probe_started)
		formation_probe_started = Time.get_ticks_usec()
	group.assign_units(ordered, previous_assignments)
	if performance_probe != null:
		performance_probe.observe_microseconds("formation.assignment", Time.get_ticks_usec() - formation_probe_started)
		formation_probe_started = Time.get_ticks_usec()
	var corridor_plan := _configure_group_route(group, ordered, center)
	if performance_probe != null:
		performance_probe.observe_microseconds("formation.corridor", Time.get_ticks_usec() - formation_probe_started)
		formation_probe_started = Time.get_ticks_usec()
	formation_groups[group.group_id] = group
	next_formation_group_id += 1
	var member_waypoint_sets := FormationCorridor.member_waypoint_sets(corridor_plan, ordered.size(), formation_name, group.spacing, forward)
	var route_envelope := _formation_route_envelope(ordered, member_waypoint_sets)
	var prevalidated_direct_routes := bool(route_envelope.get("open", false))
	for unit in ordered:
		var assigned_slot: Dictionary = group.slot_for(int(unit["id"]))
		unit["task"] = "move"
		unit["target_id"] = -1
		unit["resource_id"] = -1
		unit["formation_group_id"] = group.group_id
		unit["formation_slot_id"] = assigned_slot["slot_id"]
		unit["formation_slot_capacity"] = assigned_slot["capacity_radius"]
		unit["formation_forward"] = forward
		unit["formation_facing"] = formation_facing
		unit["formation_home"] = assigned_slot["world"]
		unit["formation_slot_mode"] = "soft"
		var member_waypoints: Array[Vector2] = []
		member_waypoints.assign(member_waypoint_sets[int(assigned_slot["slot_id"])])
		if simulation_world.assign_unit_waypoints(unit, member_waypoints, assigned_slot["world"], prevalidated_direct_routes, route_envelope):
			resolved_count += 1
	if performance_probe != null:
		performance_probe.observe_microseconds("formation.member_routes", Time.get_ticks_usec() - formation_probe_started)
	_set_group_lifecycle_state(group, FormationLifecycle.TRAVEL if resolved_count > 0 else FormationLifecycle.ASSEMBLE, "formation_command" if resolved_count > 0 else "route_blocked")
	for replaced_group_id in replaced_group_ids.keys():
		if int(replaced_group_id) != group.group_id:
			_reconcile_formation_group(int(replaced_group_id))
	return resolved_count > 0

func update_formation_group_members(group_id: int, requested_member_ids: Array[int]) -> void:
	if not formation_groups.has(group_id):
		return
	var requested: Dictionary = {}
	var affected_groups: Dictionary = {}
	for member_id in requested_member_ids:
		requested[int(member_id)] = true
	for unit in simulation_world.get_units():
		var current_group_id := int(unit.get("formation_group_id", -1))
		if current_group_id == group_id and not requested.has(int(unit["id"])):
			_clear_unit_formation(unit)
		elif requested.has(int(unit["id"])) and float(unit.get("hp", 0.0)) > 0.0:
			if current_group_id >= 0 and current_group_id != group_id:
				affected_groups[current_group_id] = true
			unit["formation_group_id"] = group_id
	_reconcile_formation_group(group_id, requested_member_ids)
	for affected_group_id in affected_groups.keys():
		_reconcile_formation_group(int(affected_group_id))

func reconcile_formation_groups() -> void:
	var group_ids: Array = formation_groups.keys()
	group_ids.sort()
	for group_id in group_ids:
		_reconcile_formation_group(int(group_id))

func _reconcile_formation_group(group_id: int, requested_member_ids: Variant = null) -> void:
	if not formation_groups.has(group_id):
		return
	var group = formation_groups[group_id]
	var members: Array = []
	var candidate_ids: Array = group.member_ids
	if requested_member_ids is Array:
		candidate_ids = requested_member_ids.duplicate()
		candidate_ids.sort()
	for member_id_value in candidate_ids:
		var unit = simulation_world.find_unit(int(member_id_value))
		if unit == null:
			continue
		if int(unit.get("formation_group_id", -1)) != group_id:
			continue
		if float(unit.get("hp", 0.0)) <= 0.0:
			_clear_unit_formation(unit)
		else:
			members.append(unit)
	if members.is_empty():
		_set_group_lifecycle_state(group, FormationLifecycle.DISBAND, "no_members")
		formation_groups.erase(group_id)
		return
	var current_ids: Array[int] = []
	for unit in members:
		current_ids.append(int(unit["id"]))
	if current_ids == group.member_ids:
		_update_group_lifecycle(group, members)
		return
	var previous_assignments: Dictionary = group.assignments.duplicate(true)
	group.member_ids = current_ids
	group.rebuild_slots()
	group.assign_units(members, previous_assignments)
	var center := Vector2.ZERO
	for unit in members:
		center += unit["pos"]
	center /= float(members.size())
	var corridor_plan := _configure_group_route(group, members, center)
	var formation_facing: int = simulation_world.facing_for_vector(group.forward)
	for unit in members:
		var assigned_slot: Dictionary = group.slot_for(int(unit["id"]))
		unit["formation_slot_id"] = assigned_slot["slot_id"]
		unit["formation_slot_capacity"] = assigned_slot["capacity_radius"]
		unit["formation_forward"] = group.forward
		unit["formation_facing"] = formation_facing
		unit["formation_home"] = assigned_slot["world"]
		if String(unit.get("task", "idle")) in ["idle", "move"]:
			unit["task"] = "move"
			var member_waypoints := FormationCorridor.member_waypoints(corridor_plan, members.size(), group.formation_type, group.spacing, group.forward, int(assigned_slot["slot_id"]))
			simulation_world.assign_unit_waypoints(unit, member_waypoints, assigned_slot["world"])
	_update_group_lifecycle(group, members)


func _update_group_lifecycle(group, members: Array) -> void:
	var transition: Dictionary = FormationLifecycle.evaluate(group, members, Callable(simulation_world, "find_combat_target"))
	for unit in members:
		unit["formation_slot_mode"] = String(group.slot_constraint_mode)
	if bool(transition["changed"]):
		event_stream.emit(tick_index, "formation_state_changed", {
			"group_id": int(group.group_id),
			"previous_state": String(transition["previous"]),
			"current_state": String(transition["current"]),
			"reason": String(transition["reason"]),
			"revision": int(group.lifecycle_revision),
		})


func _set_group_lifecycle_state(group, state: String, reason: String) -> void:
	var transition: Dictionary = FormationLifecycle.transition(group, state, reason)
	group.slot_constraint_mode = FormationLifecycle.slot_mode_for(state)
	if bool(transition["changed"]):
		event_stream.emit(tick_index, "formation_state_changed", {
			"group_id": int(group.group_id),
			"previous_state": String(transition["previous"]),
			"current_state": String(transition["current"]),
			"reason": reason,
			"revision": int(group.lifecycle_revision),
		})

func _configure_group_route(group, members: Array, start_center: Vector2) -> Dictionary:
	var maximum_radius := 0.0
	for unit in members:
		maximum_radius = maxf(maximum_radius, float(unit.get("footprint_radius", 0.3)))
	var corridor_plan := FormationCorridor.plan(start_center, group.anchor, group.formation_type, members.size(), group.spacing, maximum_radius, simulation_world.pathfinder, simulation_world.navigation_grid)
	group.route.assign(corridor_plan["route"])
	group.corridor_modes.assign(corridor_plan["modes"])
	group.required_corridor_width = int(corridor_plan["required_width"])
	group.has_compression = bool(corridor_plan["has_compression"])
	return corridor_plan


func _formation_route_envelope(members: Array, waypoint_sets: Array) -> Dictionary:
	if members.is_empty() or waypoint_sets.size() != members.size():
		return {"open": false}
	var movement_domain := String(members[0].get("movement_domain", "land"))
	var restriction_id := int(members[0].get("terrain_restriction", -1))
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var maximum_radius := 0.0
	for member in members:
		if String(member.get("movement_domain", "land")) != movement_domain or int(member.get("terrain_restriction", -1)) != restriction_id:
			return {"open": false}
		var position: Vector2 = member.get("pos", Vector2.ZERO)
		minimum = Vector2(minf(minimum.x, position.x), minf(minimum.y, position.y))
		maximum = Vector2(maxf(maximum.x, position.x), maxf(maximum.y, position.y))
		maximum_radius = maxf(maximum_radius, float(member.get("footprint_radius", 0.3)))
	for waypoints in waypoint_sets:
		if waypoints.is_empty():
			return {"open": false}
		for waypoint in waypoints:
			minimum = Vector2(minf(minimum.x, waypoint.x), minf(minimum.y, waypoint.y))
			maximum = Vector2(maxf(maximum.x, waypoint.x), maxf(maximum.y, waypoint.y))
	var open: bool = simulation_world.navigation_grid.is_world_rect_walkable_for(minimum, maximum, maximum_radius, movement_domain, restriction_id)
	return {
		"open": open,
		"minimum": minimum,
		"maximum": maximum,
		"grid_revision": simulation_world.navigation_grid.revision,
	}

func _detach_units_from_formations(selected: Array) -> void:
	var affected_groups: Dictionary = {}
	for unit in selected:
		var group_id := int(unit.get("formation_group_id", -1))
		if group_id >= 0:
			affected_groups[group_id] = true
		_clear_unit_formation(unit)
	for group_id in affected_groups.keys():
		_reconcile_formation_group(int(group_id))

func _clear_unit_formation(unit: Dictionary) -> void:
	unit["formation_group_id"] = -1
	unit["formation_slot_id"] = -1
	unit["formation_slot_capacity"] = 0.0
	unit["formation_forward"] = Vector2.ZERO
	unit["formation_home"] = null
	unit["formation_slot_mode"] = "none"
	unit["formation_shared_motion"] = false
	unit["formation_shared_isolated"] = false
	unit["cohesion_speed_scale"] = 1.0

func advance_frame(frame_delta: float, player_team: int, enemy_team: int) -> String:
	if paused or simulation_world == null:
		return simulation_world.get_last_battle_message() if simulation_world != null else ""

	accumulator_seconds += minf(frame_delta, 0.25) * get_speed_multiplier()
	var steps := 0
	while accumulator_seconds + 0.000001 >= FIXED_STEP_SECONDS and steps < MAX_STEPS_PER_FRAME:
		var expensive_planning_tick := _run_fixed_tick(player_team, enemy_team)
		accumulator_seconds -= FIXED_STEP_SECONDS
		steps += 1
		# Do not let several independent AI planning phases accumulate inside
		# one rendered frame. The remaining fixed-step debt is retained and is
		# recovered by the following cheap ticks, preserving exact tick order.
		if expensive_planning_tick:
			break
	return simulation_world.get_last_battle_message()

func _run_fixed_tick(player_team: int, enemy_team: int) -> bool:
	var fixed_tick_started := Time.get_ticks_usec() if performance_probe != null else 0
	var expensive_planning_tick := false
	if replay_source == null and before_fixed_tick.is_valid():
		expensive_planning_tick = bool(before_fixed_tick.call(tick_index + 1))
	_inject_replay_commands_for_current_tick()
	tick_index += 1
	simulation_world.begin_event_capture()
	var command_started := Time.get_ticks_usec() if performance_probe != null else 0
	process_commands()
	var command_microseconds := Time.get_ticks_usec() - command_started if performance_probe != null else 0
	var autonomy_started := Time.get_ticks_usec() if performance_probe != null else 0
	var wildlife_started := autonomy_started
	for wildlife_command in wildlife_behavior.collect_commands(simulation_world, tick_index):
		enqueue_command(wildlife_command, false, 0)
	var wildlife_microseconds := Time.get_ticks_usec() - wildlife_started if performance_probe != null else 0
	var awareness_started := Time.get_ticks_usec() if performance_probe != null else 0
	for autonomous_command in combat_awareness.collect_commands(simulation_world, tick_index):
		var attacker = simulation_world.find_combat_target(int(autonomous_command.unit_ids[0]))
		if attacker != null:
			enqueue_command(autonomous_command, false, int(attacker.get("team", 0)))
	var awareness_microseconds := Time.get_ticks_usec() - awareness_started if performance_probe != null else 0
	var autonomy_microseconds := Time.get_ticks_usec() - autonomy_started if performance_probe != null else 0
	command_started = Time.get_ticks_usec() if performance_probe != null else 0
	process_commands()
	if performance_probe != null:
		command_microseconds += Time.get_ticks_usec() - command_started
	var task_states_after_commands := _all_unit_task_states()
	var world_started := Time.get_ticks_usec() if performance_probe != null else 0
	if simulation_world.has_method("set_formation_cohesion_active"):
		simulation_world.set_formation_cohesion_active(not formation_groups.is_empty())
	simulation_world.advance(FIXED_STEP_SECONDS, player_team, enemy_team)
	var world_microseconds := Time.get_ticks_usec() - world_started if performance_probe != null else 0
	var formation_started := Time.get_ticks_usec() if performance_probe != null else 0
	reconcile_formation_groups()
	var formation_microseconds := Time.get_ticks_usec() - formation_started if performance_probe != null else 0
	var event_started := Time.get_ticks_usec() if performance_probe != null else 0
	simulation_world.end_event_capture()
	_forward_domain_events()
	_emit_runtime_task_changes(task_states_after_commands)
	if replay_recorder != null and record_replay_state_hashes:
		replay_recorder.record_state(tick_index, simulation_world, self)
	if replay_source != null:
		var expected: String = replay_source.expected_hash_at(tick_index)
		if not expected.is_empty():
			var actual: String = replay_source.world_state_hash(simulation_world, tick_index, self)
			if actual != expected:
				last_replay_mismatch = "tick:%d expected:%s actual:%s" % [tick_index, expected, actual]
	if performance_probe != null:
		performance_probe.observe_microseconds("controller.commands", command_microseconds)
		performance_probe.observe_microseconds("controller.autonomy", autonomy_microseconds)
		performance_probe.observe_microseconds("controller.autonomy.wildlife", wildlife_microseconds)
		performance_probe.observe_microseconds("controller.autonomy.combat", awareness_microseconds)
		performance_probe.observe_microseconds("controller.world_advance", world_microseconds)
		performance_probe.observe_microseconds("controller.formation_reconcile", formation_microseconds)
		performance_probe.observe_microseconds("controller.events_replay", Time.get_ticks_usec() - event_started)
		performance_probe.observe_microseconds("controller.fixed_tick", Time.get_ticks_usec() - fixed_tick_started)
	return expensive_planning_tick


func _inject_replay_commands_for_current_tick() -> void:
	if replay_source == null:
		return
	for replay_command in replay_source.commands_issued_through_tick(tick_index):
		enqueue_command(replay_command, false)



