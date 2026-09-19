class_name RoRCombatAwarenessSystem
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const PerceptionService := preload("res://scripts/perception_service.gd")

var perception := PerceptionService.new()

const CANDIDATE_BUCKET_SIZE := 4.0
const AGGRESSIVE_SCAN_INTERVAL_TICKS := 4
const GUARDED_SCAN_INTERVAL_TICKS := 2
const ROSTER_REFRESH_INTERVAL_TICKS := 4
const CANDIDATE_INDEX_REFRESH_INTERVAL_TICKS := 2

var cached_attackers: Array = []
var cached_targets: Array = []
var cached_entity_count := -1
var cached_roster_tick := -1
var cached_candidate_index: Dictionary = {}
var cached_candidate_index_tick := -1


func reset() -> void:
	cached_attackers.clear()
	cached_targets.clear()
	cached_entity_count = -1
	cached_roster_tick = -1
	cached_candidate_index.clear()
	cached_candidate_index_tick = -1


func collect_commands(world, tick: int) -> Array:
	if world == null:
		return []
	var probe: Variant = world.tick_pipeline.performance_probe
	var stage_started := Time.get_ticks_usec() if probe != null else 0
	var rosters := _combat_rosters(world, tick)
	var units: Array = rosters["attackers"]
	var has_active_observer := false
	for unit_value in units:
		var unit: Dictionary = unit_value
		if String(unit.get("stance", "passive")) != "passive" and _eligible_for_awareness(world, unit):
			has_active_observer = true
			break
	if not has_active_observer:
		return []
	if probe != null:
		probe.observe_microseconds("controller.autonomy.setup", Time.get_ticks_usec() - stage_started)
	stage_started = Time.get_ticks_usec() if probe != null else 0
	# get_combat_attackers() already guarantees stable entity-ID order. The
	# candidate index does not need a global order because final target ranking
	# includes entity ID, so avoid sorting that temporary projection.
	var attacker_metadata := _attacker_metadata(units)
	var assigned: Dictionary = attacker_metadata["assigned"]
	var retaliation_allies: Dictionary = attacker_metadata["retaliation"]
	var candidate_index := _candidate_index(rosters["targets"], tick)
	if probe != null:
		probe.observe_microseconds("controller.autonomy.index", Time.get_ticks_usec() - stage_started)
	var commands: Array = []
	var combat_candidate_cache: Dictionary = {}
	var relation_cache: Dictionary = {}
	var validation_microseconds := 0
	var assistance_microseconds := 0
	var query_microseconds := 0
	var perception_microseconds := 0

	for unit_value in units:
		var unit: Dictionary = unit_value
		if not _eligible_for_awareness(world, unit):
			continue
		var stance := String(unit.get("stance", "passive"))
		if stance == "passive":
			continue
		stage_started = Time.get_ticks_usec() if probe != null else 0
		var current_target = world.find_combat_target(int(unit.get("target_id", -1)))
		if String(unit.get("task", "idle")) == "attack" and _target_remains_valid(world, unit, current_target):
			if probe != null:
				validation_microseconds += Time.get_ticks_usec() - stage_started
			continue
		if probe != null:
			validation_microseconds += Time.get_ticks_usec() - stage_started
		if not _awareness_due(unit, tick, stance):
			continue

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


func _combat_rosters(world, tick: int) -> Dictionary:
	var entity_count: int = int(world.get_units().size()) + int(world.get_buildings().size())
	var refresh: bool = (
		cached_roster_tick < 0
		or tick < cached_roster_tick
		or tick - cached_roster_tick >= ROSTER_REFRESH_INTERVAL_TICKS
		or entity_count != cached_entity_count
	)
	if refresh:
		cached_attackers = world.get_combat_attackers()
		cached_targets = world.get_combat_targets(false)
		cached_entity_count = entity_count
		cached_roster_tick = tick
	return {"attackers": cached_attackers, "targets": cached_targets}


func _candidate_index(targets: Array, tick: int) -> Dictionary:
	if (
		cached_candidate_index_tick < 0
		or tick < cached_candidate_index_tick
		or tick - cached_candidate_index_tick >= CANDIDATE_INDEX_REFRESH_INTERVAL_TICKS
		or cached_candidate_index.is_empty()
	):
		cached_candidate_index = _combat_candidate_index(targets)
		cached_candidate_index_tick = tick
	return cached_candidate_index


func _eligible_for_awareness(world, unit: Dictionary) -> bool:
	if float(unit.get("hp", 0.0)) <= 0.0 or not bool(unit.get("combat_enabled", false)):
		return false
	if world.entity_is_static(unit) and String(unit.get("state", "complete")) != "complete":
		return false
	var team := int(unit.get("team", 0))
	return team > 0 and not world.battle_over


func _target_remains_valid(world, unit: Dictionary, target: Variant) -> bool:
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return false
	if world.are_teams_allied(int(unit.get("team", 0)), int(target.get("team", 0))):
		return false
	if bool(unit.get("attack_autonomous", false)) and not world.can_autonomously_target(unit, target):
		return false
	if not world.is_entity_visible_to(int(unit.get("team", 0)), target):
		return false
	if String(unit.get("stance", "passive")) == "stand_ground" and not world.is_unit_in_attack_range(unit, target):
		return false
	if bool(unit.get("attack_autonomous", false)):
		var origin := Vector2(unit.get("combat_leash_origin", unit.get("pos", Vector2.ZERO)))
		if origin.distance_to(Vector2(target.get("pos", Vector2.ZERO))) > float(unit.get("chase_range", 0.0)) + 0.0001:
			return false
	return true


func _assistance_target_id(world, unit: Dictionary, retaliation_index: Dictionary) -> int:
	var allies: Array = []
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
				allies.append({"ally_id": int(ally.get("id", -1)), "target_id": retaliation_target_id, "distance_squared": unit_position.distance_squared_to(Vector2(ally.get("pos", Vector2.ZERO)))})
	allies.sort_custom(func(left, right):
		if not is_equal_approx(float(left["distance_squared"]), float(right["distance_squared"])):
			return float(left["distance_squared"]) < float(right["distance_squared"])
		return int(left["ally_id"]) < int(right["ally_id"])
	)
	return -1 if allies.is_empty() else int(allies[0]["target_id"])


func _attacker_metadata(units: Array) -> Dictionary:
	var assigned: Dictionary = {}
	var retaliation: Dictionary = {}
	for unit_value in units:
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0:
			continue
		if String(unit.get("task", "")) == "attack":
			var target_id := int(unit.get("target_id", -1))
			if target_id >= 0:
				assigned[target_id] = int(assigned.get(target_id, 0)) + 1
		if float(unit.get("hp", 0.0)) > 0.0 and int(unit.get("retaliation_target_id", -1)) >= 0:
			var cell := _awareness_cell(Vector2(unit.get("pos", Vector2.ZERO)))
			if not retaliation.has(cell):
				retaliation[cell] = []
			retaliation[cell].append(unit)
	return {"assigned": assigned, "retaliation": retaliation}


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
	if stance == "stand_ground":
		return maxf(0.85, float(unit.get("attack_range", 0.0)))
	return maxf(0.0, float(unit.get("acquisition_range", 0.0)))


func _awareness_due(unit: Dictionary, tick: int, stance: String) -> bool:
	var task := String(unit.get("task", "idle"))
	if int(unit.get("retaliation_target_id", -1)) >= 0 or task in ["attack", "attack_move"]:
		return true
	var interval := AGGRESSIVE_SCAN_INTERVAL_TICKS if stance == "aggressive" else GUARDED_SCAN_INTERVAL_TICKS
	var cell := Vector2i(floori(float(unit.get("pos", Vector2.ZERO).x) / CANDIDATE_BUCKET_SIZE), floori(float(unit.get("pos", Vector2.ZERO).y) / CANDIDATE_BUCKET_SIZE))
	var stance_offset := 0 if stance == "defensive" else 1
	var phase := posmod(cell.x * 31 + cell.y * 17 + stance_offset, interval)
	return posmod(tick, interval) == phase
