class_name RoRWildlifeBehaviorSystem
extends RefCounted

const Commands := preload("res://scripts/commands.gd")

const PREDATOR_SCAN_INTERVAL_TICKS := 20
const GAZELLE_FLEE_SCAN_INTERVAL_TICKS := 20
const COAST_RETURN_INTERVAL_TICKS := 10
const ROSTER_REFRESH_INTERVAL_TICKS := 40
const GAZELLE_FLEE_RANGE := 2.0
const GAZELLE_FLEE_DISTANCE := 3.0
const COAST_HOME_SEARCH_RADIUS_CELLS := 16
const COAST_PROXIMITY_CELLS := 2
const COAST_ATTACK_LEASH_RANGE := 5.0
const DIRECTION_COUNT := 16
const FLEE_TURN_STEPS := [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8]
const HASH_MODULUS := 2_147_483_647

var cached_wildlife: Array = []
var cached_unit_count := -1
var cached_roster_tick := -1
var coastal_homes: Dictionary = {}


func reset() -> void:
	cached_wildlife.clear()
	cached_unit_count = -1
	cached_roster_tick = -1
	coastal_homes.clear()


func collect_commands(world, tick: int) -> Array:
	if world == null or world.battle_over:
		return []
	var commands: Array = []
	for animal_value in _wildlife_roster(world, tick):
		var animal: Dictionary = animal_value
		if float(animal.get("hp", 0.0)) <= 0.0:
			continue
		var task := String(animal.get("task", "idle"))
		if task == "attack":
			var current_target = world.find_unit(int(animal.get("target_id", -1)))
			if current_target != null and float(current_target.get("hp", 0.0)) > 0.0:
				if _is_coastal_predator(animal) and _decision_due(tick, int(animal.get("id", 0)), COAST_RETURN_INTERVAL_TICKS, 41) and (not _is_near_water(world, Vector2(animal.get("pos", Vector2.ZERO)), COAST_PROXIMITY_CELLS) or not _is_near_water(world, Vector2(current_target.get("pos", Vector2.ZERO)), COAST_PROXIMITY_CELLS)):
					var coastal_home := _coastal_home(world, animal)
					if coastal_home.distance_squared_to(Vector2(animal.get("pos", Vector2.ZERO))) > 0.25:
						commands.append(Commands.MoveCommand.new(tick, [int(animal.get("id", -1))], coastal_home))
					else:
						commands.append(Commands.StopCommand.new(tick, [int(animal.get("id", -1))]))
				continue
		if _is_coastal_predator(animal) and task in ["idle", "hold", "move"] and _decision_due(tick, int(animal.get("id", 0)), COAST_RETURN_INTERVAL_TICKS, 41):
			var return_command = _coast_return_command(world, animal, tick)
			if return_command != null:
				commands.append(return_command)
				continue
		if String(animal.get("kind", "")) == "gazelle" and task in ["idle", "hold"]:
			var flee_command = _gazelle_flee_command(world, animal, tick)
			if flee_command != null:
				commands.append(flee_command)
				continue
		if world.entity_has_behavior_tag(animal, "predator") and task in ["idle", "hold"]:
			var attack_command = _predator_command(world, animal, tick)
			if attack_command != null:
				commands.append(attack_command)
	return commands


static func _decision_due(tick: int, entity_id: int, interval: int, salt: int) -> bool:
	if tick <= 0 or interval <= 0:
		return false
	var phase := _deterministic_roll(entity_id, 0, salt, interval)
	return posmod(tick + phase, interval) == 0


static func _deterministic_roll(entity_id: int, tick: int, salt: int, limit: int) -> int:
	if limit <= 1:
		return 0
	var state := posmod(entity_id * 48_271 + tick * 69_621 + salt * 17, HASH_MODULUS)
	state = posmod(state * 48_271 + 1, HASH_MODULUS)
	return posmod(state, limit)


func _gazelle_flee_command(world, gazelle: Dictionary, tick: int):
	var gazelle_id := int(gazelle.get("id", 0))
	if not _decision_due(tick, gazelle_id, GAZELLE_FLEE_SCAN_INTERVAL_TICKS, 53):
		return null
	var position := Vector2(gazelle.get("pos", Vector2.ZERO))
	var threats: Array = []
	for candidate_value in world.query_units_near(position, GAZELLE_FLEE_RANGE):
		var candidate: Dictionary = candidate_value
		if int(candidate.get("id", -1)) == gazelle_id or float(candidate.get("hp", 0.0)) <= 0.0:
			continue
		if int(candidate.get("team", 0)) <= 0 and String(candidate.get("kind", "")) != "lion":
			continue
		threats.append(candidate)
	if threats.is_empty():
		return null
	threats.sort_custom(func(left, right):
		var left_distance := position.distance_squared_to(Vector2(left.get("pos", Vector2.ZERO)))
		var right_distance := position.distance_squared_to(Vector2(right.get("pos", Vector2.ZERO)))
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return int(left.get("id", -1)) < int(right.get("id", -1))
	)
	var away := position - Vector2(threats[0].get("pos", Vector2.ZERO))
	if away.length_squared() <= 0.0001:
		var direction_index := _deterministic_roll(gazelle_id, tick, 67, DIRECTION_COUNT)
		away = Vector2.RIGHT.rotated(TAU * float(direction_index) / float(DIRECTION_COUNT))
	var target := _flee_target(world, gazelle, away.normalized())
	if target == null:
		return null
	return Commands.MoveCommand.new(tick, [gazelle_id], target)


static func _flee_target(world, gazelle: Dictionary, away: Vector2) -> Variant:
	var position := Vector2(gazelle.get("pos", Vector2.ZERO))
	var footprint_radius := float(gazelle.get("footprint_radius", 0.3))
	var movement_domain := String(gazelle.get("movement_domain", "land"))
	var restriction_id := int(gazelle.get("terrain_restriction", -1))
	var angle_step := TAU / float(DIRECTION_COUNT)
	for distance_scale in [1.0, 0.75, 0.5]:
		for turn_steps in FLEE_TURN_STEPS:
			var direction := away.rotated(float(turn_steps) * angle_step)
			var candidate := position + direction * GAZELLE_FLEE_DISTANCE * float(distance_scale)
			if world.navigation_grid.is_position_walkable_for(candidate, footprint_radius, movement_domain, restriction_id):
				return candidate
	return null


func _predator_command(world, predator: Dictionary, tick: int):
	var predator_id := int(predator.get("id", 0))
	# Tick one remains eager for deterministic startup and campaign fixtures.
	# Afterwards each predator owns one phase of the one-second scan window.
	if tick != 1 and not _decision_due(tick, predator_id, PREDATOR_SCAN_INTERVAL_TICKS, 19):
		return null
	var metadata: Dictionary = world.data_repository.runtime_metadata(String(predator.get("kind", "")))
	var aggression_range := maxf(0.0, float(metadata.get("aggression_range", predator.get("acquisition_range", 0.0))))
	if aggression_range <= 0.0:
		return null
	var predator_position := Vector2(predator.get("pos", Vector2.ZERO))
	var coastal_predator := _is_coastal_predator(predator)
	var hunts_gazelles := String(predator.get("kind", "")) == "lion"
	var candidates: Array = []
	for candidate_value in world.query_units_near(predator_position, aggression_range):
		var candidate: Dictionary = candidate_value
		if int(candidate.get("id", -1)) == predator_id or float(candidate.get("hp", 0.0)) <= 0.0:
			continue
		var player_creature := int(candidate.get("team", 0)) > 0
		var wildlife_prey := hunts_gazelles and String(candidate.get("kind", "")) == "gazelle"
		if coastal_predator:
			wildlife_prey = false
			if not _is_near_water(world, Vector2(candidate.get("pos", Vector2.ZERO)), COAST_PROXIMITY_CELLS):
				continue
		if not player_creature and not wildlife_prey:
			continue
		candidates.append(candidate)
	candidates.sort_custom(func(left, right):
		var left_distance := predator_position.distance_squared_to(Vector2(left.get("pos", Vector2.ZERO)))
		var right_distance := predator_position.distance_squared_to(Vector2(right.get("pos", Vector2.ZERO)))
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return int(left.get("id", -1)) < int(right.get("id", -1))
	)
	var target: Variant = null
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var reachable := _can_reach_along_coast(world, predator, Vector2(candidate.get("pos", Vector2.ZERO))) if coastal_predator else world.can_unit_reach_entity(predator, candidate)
		if reachable:
			target = candidate
			break
	if target == null:
		return null
	var leash_origin := Vector2(predator.get("combat_leash_origin", predator_position))
	var chase_range := maxf(aggression_range, float(metadata.get("leash_range", aggression_range * 2.0)))
	if coastal_predator:
		leash_origin = _coastal_home(world, predator)
		chase_range = COAST_ATTACK_LEASH_RANGE
	return Commands.AttackCommand.new(tick, [predator_id], int(target.get("id", -1)), {
		"autonomous": true,
		"trigger": "wildlife_predator",
		"leash_origin": leash_origin,
		"chase_range": chase_range,
	})


func _coast_return_command(world, animal: Dictionary, tick: int):
	var position := Vector2(animal.get("pos", Vector2.ZERO))
	if _is_near_water(world, position, 1):
		return null
	var home := _coastal_home(world, animal)
	if home.distance_squared_to(position) <= 0.25:
		return null
	if String(animal.get("task", "idle")) == "move" and Vector2(animal.get("destination", position)).distance_squared_to(home) <= 0.25:
		return null
	return Commands.MoveCommand.new(tick, [int(animal.get("id", -1))], home)


func _can_reach_along_coast(world, animal: Dictionary, target: Vector2) -> bool:
	if world.is_unit_in_attack_range(animal, {"pos": target, "footprint_radius": 0.0}):
		return _is_near_water(world, target, COAST_PROXIMITY_CELLS)
	var route: Array[Vector2] = world.pathfinder.find_path(
		Vector2(animal.get("pos", Vector2.ZERO)),
		target,
		String(animal.get("movement_domain", "land")),
		int(animal.get("terrain_restriction", -1)),
		float(animal.get("footprint_radius", 0.3))
	)
	if route.is_empty():
		return false
	var previous := Vector2(animal.get("pos", Vector2.ZERO))
	for waypoint_value in route:
		var waypoint: Vector2 = waypoint_value
		var segment_length := previous.distance_to(waypoint)
		var sample_count := maxi(1, ceili(segment_length * 2.0))
		for sample_index in range(1, sample_count + 1):
			var sample := previous.lerp(waypoint, float(sample_index) / float(sample_count))
			if not _is_near_water(world, sample, COAST_PROXIMITY_CELLS):
				return false
		previous = waypoint
	return true


func _coastal_home(world, animal: Dictionary) -> Vector2:
	var entity_id := int(animal.get("id", -1))
	if coastal_homes.has(entity_id):
		return coastal_homes[entity_id]
	var origin := Vector2(animal.get("pos", Vector2.ZERO))
	var origin_cell := Vector2i(floori(origin.x), floori(origin.y))
	var footprint_radius := float(animal.get("footprint_radius", 0.3))
	var movement_domain := String(animal.get("movement_domain", "land"))
	var restriction_id := int(animal.get("terrain_restriction", -1))
	var home := origin
	for search_radius in range(COAST_HOME_SEARCH_RADIUS_CELLS + 1):
		var best: Variant = null
		var best_distance := INF
		for y in range(origin_cell.y - search_radius, origin_cell.y + search_radius + 1):
			for x in range(origin_cell.x - search_radius, origin_cell.x + search_radius + 1):
				if search_radius > 0 and maxi(absi(x - origin_cell.x), absi(y - origin_cell.y)) != search_radius:
					continue
				var candidate := Vector2(x, y) + Vector2(0.5, 0.5)
				if not world.navigation_grid.is_position_walkable_for(candidate, footprint_radius, movement_domain, restriction_id) or not _is_near_water(world, candidate, 1):
					continue
				var distance := candidate.distance_squared_to(origin)
				if distance < best_distance:
					best = candidate
					best_distance = distance
		if best is Vector2:
			home = best
			break
	coastal_homes[entity_id] = home
	return home


static func _is_near_water(world, position: Vector2, cell_radius: int) -> bool:
	var center := Vector2i(floori(position.x), floori(position.y))
	for y in range(center.y - cell_radius, center.y + cell_radius + 1):
		for x in range(center.x - cell_radius, center.x + cell_radius + 1):
			var cell := Vector2i(x, y)
			if world.navigation_grid.contains(cell) and String(world.terrain_kind_at_cell(cell)) == "water":
				return true
	return false


static func _is_coastal_predator(animal: Dictionary) -> bool:
	return String(animal.get("kind", "")) in ["alligator", "crocodile"]


func _wildlife_roster(world, tick: int) -> Array:
	var source: Array = world.get_units()
	if (
		cached_roster_tick < 0
		or tick < cached_roster_tick
		or tick - cached_roster_tick >= ROSTER_REFRESH_INTERVAL_TICKS
		or source.size() != cached_unit_count
	):
		cached_wildlife = source.filter(func(unit):
			return int(unit.get("team", -1)) == 0 \
				and world.entity_has_behavior_tag(unit, "mobile") \
				and (String(unit.get("kind", "")) == "gazelle" or world.entity_has_behavior_tag(unit, "predator"))
		)
		cached_wildlife.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
		var active_ids: Dictionary = {}
		for animal in cached_wildlife:
			active_ids[int(animal.get("id", -1))] = true
			if _is_coastal_predator(animal):
				_coastal_home(world, animal)
		for entity_id in coastal_homes.keys():
			if not active_ids.has(int(entity_id)):
				coastal_homes.erase(entity_id)
		cached_unit_count = source.size()
		cached_roster_tick = tick
	return cached_wildlife
