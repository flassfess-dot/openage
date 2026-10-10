class_name RoRCombatAwarenessSystem
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const PerceptionService := preload("res://scripts/perception_service.gd")

var perception := PerceptionService.new()

const CANDIDATE_BUCKET_SIZE := 4.0
const AGGRESSIVE_SCAN_INTERVAL_TICKS := 4
const GUARDED_SCAN_INTERVAL_TICKS := 2
const ACTIVE_TARGET_VALIDATION_INTERVAL_TICKS := 2
# Source events maintain live candidates and metadata. Actor wake lanes retain
# the original fixed tick cadence; direct external mutation is unsupported.

const Journal := preload("res://scripts/entity_change_journal.gd")
var cursor := -1
var epoch := -1
var attackers_by_id: Dictionary = {}
var target_membership: Dictionary = {}
var metadata_by_id: Dictionary = {}
var assigned_targets: Dictionary = {}
var retaliation_buckets: Dictionary = {}
var wake_lanes: Array = [{}, {}, {}, {}]
var lane_by_id: Dictionary = {}
var roster_order_dirty := true
var cached_attackers: Array = []
var cached_targets: Array = []
var cached_entity_count := -1
var cached_roster_tick := -1
var cached_roster_revision := -1
var cached_candidate_index: Dictionary = {}
var cached_candidate_index_tick := -1


func reset() -> void:
	cursor = -1
	epoch = -1
	attackers_by_id.clear()
	target_membership.clear()
	metadata_by_id.clear()
	assigned_targets.clear()
	retaliation_buckets.clear()
	wake_lanes = [{}, {}, {}, {}]
	lane_by_id.clear()
	roster_order_dirty = true
	cached_attackers.clear()
	cached_targets.clear()
	cached_entity_count = -1
	cached_roster_tick = -1
	cached_roster_revision = -1
	cached_candidate_index.clear()
	cached_candidate_index_tick = -1


func collect_commands(world, tick: int) -> Array:
	if world == null:
		return []
	var probe: Variant = world.tick_pipeline.performance_probe
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	_refresh_combat_rosters(world, tick)
	var units: Array = wake_lanes[posmod(tick, 4)].values()
	units.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	var due_units: Array = []
	for unit_value in units:
		var unit: Dictionary = unit_value
		var task := String(unit.get("task", "idle"))
		if task not in ["idle", "attack_move"] and not (task == "attack" and bool(unit.get("attack_autonomous", false))):
			continue
		var stance := "aggressive" if bool(unit.get("combat_pursuit", false)) else String(unit.get("stance", "passive"))
		if stance == "passive":
			continue
		# Task and stance are cheap fields and reject the overwhelming majority
		# of marching/working units. Run metadata/tag eligibility only for actors
		# that can actually acquire or validate a target on this tick.
		if not unit.get("components", {}).get("order", {}).get("queued", []).is_empty():
			continue
		if not _awareness_due(unit, tick, stance) or not _eligible_for_awareness(world, unit):
			continue
		due_units.append(unit)
	if due_units.is_empty():
		return []
	if probe != null:
		probe.observe_microseconds("controller.autonomy.setup", Time.get_ticks_usec() - stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0
	var acquisition_units: Array = []
	var validation_microseconds := 0
	for unit_value in due_units:
		var unit: Dictionary = unit_value
		var validation_started := Time.get_ticks_usec() if probe != null else 0
		var current_target = world.find_combat_target(int(unit.get("target_id", -1)))
		if String(unit.get("task", "idle")) == "attack" and _target_remains_valid(world, unit, current_target):
			if probe != null:
				validation_microseconds += Time.get_ticks_usec() - validation_started
			continue
		if probe != null:
			validation_microseconds += Time.get_ticks_usec() - validation_started
		acquisition_units.append(unit)
	if acquisition_units.is_empty():
		if probe != null:
			probe.observe_microseconds("controller.autonomy.validation", validation_microseconds)
		return []
	# The retained attacker roster already has stable entity-ID order. The
	# candidate index does not need a global order because final target ranking
	# includes entity ID, so avoid sorting that temporary projection.
	var attacker_metadata := _attacker_metadata(units)
	var assigned: Dictionary = attacker_metadata["assigned"]
	var retaliation_allies: Dictionary = attacker_metadata["retaliation"]
	var candidate_index := _candidate_index(cached_targets, tick)
	if probe != null:
		probe.observe_microseconds("controller.autonomy.index", Time.get_ticks_usec() - stage_started)
	var commands: Array = []
	var combat_candidate_cache: Dictionary = {}
	var relation_cache: Dictionary = {}
	var assistance_microseconds := 0
	var query_microseconds := 0
	var perception_microseconds := 0

	for unit_value in acquisition_units:
		var unit: Dictionary = unit_value
		var stance := "aggressive" if bool(unit.get("combat_pursuit", false)) else String(unit.get("stance", "passive"))
		var query_range := _query_range(unit, stance)
		var allowed_target_id := -1
		if stance == "defensive":
			var retaliation_target_id := int(unit.get("retaliation_target_id", -1))
			if retaliation_target_id < 0:
				stage_started = Time.get_ticks_usec() if probe != null else 0
				retaliation_target_id = _assistance_target_id(world, unit, retaliation_allies)
				if probe != null:
					assistance_microseconds += Time.get_ticks_usec() - stage_started
			if retaliation_target_id < 0:
				continue
			allowed_target_id = retaliation_target_id
		elif stance == "stand_ground":
			pass
		elif String(unit.get("task", "idle")) not in ["idle", "move", "attack_move", "attack"]:
			continue

		stage_started = Time.get_ticks_usec() if probe != null else 0
		var nearby_targets: Array = _cached_combat_entities_near(
			world,
			combat_candidate_cache,
			candidate_index,
			Vector2(unit.get("pos", Vector2.ZERO)),
			query_range + float(unit.get("footprint_radius", 0.0)),
			int(unit.get("team", 0)),
			relation_cache
		)
		if probe != null:
			query_microseconds += Time.get_ticks_usec() - stage_started
			stage_started = Time.get_ticks_usec()
		var target = perception.best_combat_target(world, unit, nearby_targets, assigned, query_range, stance, allowed_target_id, true)
		if probe != null:
			perception_microseconds += Time.get_ticks_usec() - stage_started
		if target == null:
			continue
		var target_id := int(target["id"])
		var policy := {
			"autonomous": true,
			"trigger": "retaliation" if stance == "defensive" else "stance",
			"leash_origin": Vector2(unit.get("combat_leash_origin", unit.get("pos", Vector2.ZERO))) if bool(unit.get("attack_autonomous", false)) else Vector2(unit.get("pos", Vector2.ZERO)),
			"chase_range": float(unit.get("chase_range", _query_range(unit, stance))),
		}
		commands.append(Commands.AttackCommand.new(tick, [int(unit["id"])], target_id, policy))
		assigned[target_id] = int(assigned.get(target_id, 0)) + 1
	if probe != null:
		probe.observe_microseconds("controller.autonomy.validation", validation_microseconds)
		probe.observe_microseconds("controller.autonomy.assistance", assistance_microseconds)
		probe.observe_microseconds("controller.autonomy.spatial_query", query_microseconds)
		probe.observe_microseconds("controller.autonomy.perception", perception_microseconds)
		probe.increment("controller.autonomy.combat_candidate_buckets", combat_candidate_cache.size())
	return commands


func tracked_attackers() -> Array:
	# Read-only live-reference view for adjacent controller bookkeeping. The
	# roster is refreshed at the start of collect_commands on every fixed tick.
	return cached_attackers


func _refresh_combat_rosters(world, tick: int) -> void:
	var delta: Dictionary = world.entity_changes.changes_since(cursor if epoch == world.entity_changes.epoch else -1)
	if bool(delta["full"]):
		reset()
		cached_candidate_index = {"buckets": {}, "maximum_radius": 0.0}
		for row in world.get_units(): _update_record(row, world)
		for row in world.get_buildings(): _update_record(row, world)
	else:
		for id in delta["ids"]:
			if not (int(delta["masks"][id]) & (Journal.LIFECYCLE | Journal.POSITION | Journal.ACTIVITY | Journal.COMBAT | Journal.OWNERSHIP)): continue
			_remove_record(int(id), true)
			var row: Variant = world.find_unit(int(id))
			if row == null: row = world.find_building(int(id))
			if row != null: _update_record(row, world)
			elif attackers_by_id.erase(int(id)): roster_order_dirty = true
	cursor = int(delta["revision"])
	epoch = world.entity_changes.epoch
	cached_roster_tick = tick
	if roster_order_dirty:
		cached_attackers = attackers_by_id.values()
		cached_attackers.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
		roster_order_dirty = false

func _remove_record(id: int, retain_attacker: bool = false) -> void:
	if target_membership.has(id):
		var old: Array = target_membership[id]
		var bucket: Dictionary = cached_candidate_index["buckets"][old[0]]
		bucket[old[1]].erase(old[2])
		if bucket[old[1]].is_empty(): bucket.erase(old[1])
		if bucket.is_empty(): cached_candidate_index["buckets"].erase(old[0])
		target_membership.erase(id)
	if attackers_by_id.has(id) and not retain_attacker:
		attackers_by_id.erase(id)
		roster_order_dirty = true
	if metadata_by_id.has(id):
		var metadata: Dictionary = metadata_by_id[id]
		var target_id := int(metadata["assigned"])
		if target_id >= 0:
			assigned_targets[target_id] = int(assigned_targets[target_id]) - 1
			if int(assigned_targets[target_id]) <= 0: assigned_targets.erase(target_id)
		if metadata["retaliation"]:
			retaliation_buckets[metadata["cell"]].erase(metadata["row"])
			if retaliation_buckets[metadata["cell"]].is_empty(): retaliation_buckets.erase(metadata["cell"])
		metadata_by_id.erase(id)
	for lane in lane_by_id.get(id, []): wake_lanes[lane].erase(id)
	lane_by_id.erase(id)

func _update_record(row: Dictionary, world) -> void:
	var id := int(row["id"])
	var cell := _awareness_cell(Vector2(row.get("pos", Vector2.ZERO)))
	var team := int(row.get("team", 0))
	if float(row.get("hp", 0.0)) <= 0.0:
		attackers_by_id.erase(id)
		roster_order_dirty = true
		return
	if not world.entity_has_behavior_tag(row, "noncombat_target"):
		if not cached_candidate_index["buckets"].has(cell): cached_candidate_index["buckets"][cell] = {}
		var bucket: Dictionary = cached_candidate_index["buckets"][cell]
		if not bucket.has(team): bucket[team] = []
		bucket[team].append(row)
		target_membership[id] = [cell, team, row]
		cached_candidate_index["maximum_radius"] = maxf(float(cached_candidate_index["maximum_radius"]), float(row.get("footprint_radius", 0.0)))
	if not bool(row.get("combat_enabled", false)):
		if attackers_by_id.erase(id): roster_order_dirty = true
		return
	if not attackers_by_id.has(id): roster_order_dirty = true
	attackers_by_id[id] = row
	var task := String(row.get("task", "idle"))
	var assigned := int(row.get("target_id", -1)) if task == "attack" else -1
	if assigned >= 0: assigned_targets[assigned] = int(assigned_targets.get(assigned, 0)) + 1
	var retaliating := int(row.get("retaliation_target_id", -1)) >= 0
	if retaliating:
		if not retaliation_buckets.has(cell): retaliation_buckets[cell] = []
		retaliation_buckets[cell].append(row)
	metadata_by_id[id] = {"assigned": assigned, "retaliation": retaliating, "cell": cell, "row": row}
	var stance := "aggressive" if bool(row.get("combat_pursuit", false)) else String(row.get("stance", "passive"))
	if stance == "passive" or task not in ["idle", "attack_move", "attack"] or (task == "attack" and not bool(row.get("attack_autonomous", false))): return
	var lanes: Array = []
	for phase in range(4):
		if _awareness_due(row, phase, stance):
			wake_lanes[phase][id] = row
			lanes.append(phase)
	lane_by_id[id] = lanes


func _combat_observers(world) -> Array:
	# Keep capable entities in the live-reference roster even while dead or a
	# building is unfinished. Eligibility is checked at use time, so completion
	# and death take effect immediately without forcing another global rebuild.
	var result: Array = []
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if bool(unit.get("combat_enabled", false)):
			result.append(unit)
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if bool(building.get("combat_enabled", false)):
			result.append(building)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


func _candidate_index(_targets: Array, _tick: int) -> Dictionary:
	return cached_candidate_index


func _eligible_for_awareness(world, unit: Dictionary) -> bool:
	if int(unit.get("team", 0)) <= 0 or world.battle_over or float(unit.get("hp", 0.0)) <= 0.0 or not bool(unit.get("combat_enabled", false)):
		return false
	if world.entity_has_behavior_tag(unit, "scout") and int(unit.get("retaliation_target_id", -1)) < 0 and not bool(unit.get("combat_pursuit", false)):
		return false
	if world.entity_is_static(unit) and String(unit.get("state", "complete")) != "complete":
		return false
	return true


func _target_remains_valid(world, unit: Dictionary, target: Variant) -> bool:
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return false
	if world.are_teams_allied(int(unit.get("team", 0)), int(target.get("team", 0))):
		return false
	if bool(unit.get("attack_autonomous", false)) and not world.can_autonomously_target(unit, target):
		return false
	if not world.is_entity_visible_to(int(unit.get("team", 0)), target):
		return false
	if not bool(unit.get("combat_pursuit", false)) and String(unit.get("stance", "passive")) == "stand_ground" and not world.is_unit_in_attack_range(unit, target):
		return false
	if bool(unit.get("attack_autonomous", false)):
		var origin := Vector2(unit.get("combat_leash_origin", unit.get("pos", Vector2.ZERO)))
		if origin.distance_to(Vector2(target.get("pos", Vector2.ZERO))) > float(unit.get("chase_range", 0.0)) + 0.0001:
			return false
	return true


func _assistance_target_id(world, unit: Dictionary, retaliation_index: Dictionary) -> int:
	var best_target_id := -1
	var best_ally_id := 2147483647
	var best_distance_squared := INF
	var unit_team := int(unit.get("team", 0))
	var unit_position := Vector2(unit.get("pos", Vector2.ZERO))
	var assist_range := float(unit.get("acquisition_range", 0.0))
	var minimum := _awareness_cell(unit_position - Vector2.ONE * assist_range)
	var maximum := _awareness_cell(unit_position + Vector2.ONE * assist_range)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for ally_value in retaliation_index.get(Vector2i(x, y), []):
				var ally: Dictionary = ally_value
				if int(ally.get("id", -1)) == int(unit.get("id", -1)) or float(ally.get("hp", 0.0)) <= 0.0:
					continue
				if not world.are_teams_allied(unit_team, int(ally.get("team", 0))):
					continue
				var retaliation_target_id := int(ally.get("retaliation_target_id", -1))
				if retaliation_target_id < 0 or unit_position.distance_to(Vector2(ally.get("pos", Vector2.ZERO))) > assist_range:
					continue
				if world.find_combat_target(retaliation_target_id) == null:
					continue
				var ally_id := int(ally.get("id", -1))
				var distance_squared := unit_position.distance_squared_to(Vector2(ally.get("pos", Vector2.ZERO)))
				var same_distance := is_equal_approx(distance_squared, best_distance_squared)
				if (not same_distance and distance_squared < best_distance_squared) or (same_distance and ally_id < best_ally_id):
					best_target_id = retaliation_target_id
					best_ally_id = ally_id
					best_distance_squared = distance_squared
	return best_target_id


func _attacker_metadata(_units: Array) -> Dictionary:
	return {"assigned": assigned_targets.duplicate(), "retaliation": retaliation_buckets}


func _combat_candidate_index(targets: Array) -> Dictionary:
	var buckets: Dictionary = {}
	var maximum_radius := 0.0
	for target_value in targets:
		var target: Dictionary = target_value
		var cell := _awareness_cell(Vector2(target.get("pos", Vector2.ZERO)))
		if not buckets.has(cell):
			buckets[cell] = {}
		var team := int(target.get("team", 0))
		if not buckets[cell].has(team):
			buckets[cell][team] = []
		buckets[cell][team].append(target)
		maximum_radius = maxf(maximum_radius, float(target.get("footprint_radius", 0.0)))
	return {"buckets": buckets, "maximum_radius": maximum_radius}


func _cached_combat_entities_near(world, cache: Dictionary, candidate_index: Dictionary, position: Vector2, radius: float, observer_team: int, relation_cache: Dictionary) -> Array:
	var query := _bucket_query(position, radius)
	var spatial_key: Vector3i = query["key"]
	var key := Vector4i(spatial_key.x, spatial_key.y, spatial_key.z, observer_team)
	if not cache.has(key):
		var candidates: Array = []
		var extent := float(query["radius"]) + float(candidate_index.get("maximum_radius", 0.0))
		var minimum := _awareness_cell(Vector2(query["center"]) - Vector2.ONE * extent)
		var maximum := _awareness_cell(Vector2(query["center"]) + Vector2.ONE * extent)
		for y in range(minimum.y, maximum.y + 1):
			for x in range(minimum.x, maximum.x + 1):
				var teams: Dictionary = candidate_index.get("buckets", {}).get(Vector2i(x, y), {})
				for candidate_team_value in teams.keys():
					var candidate_team := int(candidate_team_value)
					if candidate_team <= 0 or candidate_team == observer_team:
						continue
					var relation_key := Vector2i(observer_team, candidate_team)
					if not relation_cache.has(relation_key):
						relation_cache[relation_key] = String(world.team_relation(observer_team, candidate_team))
					var relation := String(relation_cache[relation_key])
					if relation == "enemy":
						candidates.append_array(teams[candidate_team_value])
					elif relation == "neutral":
						for candidate_value in teams[candidate_team_value]:
							var candidate: Dictionary = candidate_value
							var tags: Array = candidate.get("behavior_tags", [])
							if world.entity_is_static(candidate) or "military" in tags or ("combatant" in tags and "worker" not in tags):
								candidates.append(candidate)
		cache[key] = candidates
	return cache[key]


func _bucket_query(position: Vector2, radius: float) -> Dictionary:
	# All observers in one spatial bucket may safely share a conservative
	# candidate set. Perception and assistance still apply exact observer ranges,
	# visibility, hostility and deterministic tie-breaking afterwards.
	var cell_size := CANDIDATE_BUCKET_SIZE
	var cell := _awareness_cell(position)
	var radius_milli := maxi(0, ceili(maxf(0.0, radius) * 1000.0))
	return {
		"key": Vector3i(cell.x, cell.y, radius_milli),
		"center": (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size,
		"radius": float(radius_milli) / 1000.0 + cell_size * sqrt(2.0) * 0.5,
	}


func _awareness_cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CANDIDATE_BUCKET_SIZE), floori(position.y / CANDIDATE_BUCKET_SIZE))


func _query_range(unit: Dictionary, stance: String) -> float:
	if bool(unit.get("combat_pursuit", false)):
		return maxf(float(unit.get("acquisition_range", 0.0)), float(unit.get("components", {}).get("vision", {}).get("range", 0.0)))
	if stance == "stand_ground":
		return maxf(0.85, float(unit.get("attack_range", 0.0)))
	return maxf(0.0, float(unit.get("acquisition_range", 0.0)))


func _awareness_due(unit: Dictionary, tick: int, stance: String) -> bool:
	var task := String(unit.get("task", "idle"))
	if int(unit.get("retaliation_target_id", -1)) >= 0 or task == "attack_move":
		return true
	if task == "attack":
		return posmod(tick + int(unit.get("id", 0)), ACTIVE_TARGET_VALIDATION_INTERVAL_TICKS) == 0
	var interval := AGGRESSIVE_SCAN_INTERVAL_TICKS if stance == "aggressive" else GUARDED_SCAN_INTERVAL_TICKS
	var cell := Vector2i(floori(float(unit.get("pos", Vector2.ZERO).x) / CANDIDATE_BUCKET_SIZE), floori(float(unit.get("pos", Vector2.ZERO).y) / CANDIDATE_BUCKET_SIZE))
	var stance_offset := 0 if stance == "defensive" else 1
	var phase := posmod(cell.x * 31 + cell.y * 17 + stance_offset, interval)
	return posmod(tick, interval) == phase
