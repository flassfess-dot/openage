class_name RoRWildlifeBehaviorSystem
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const IDLE_SCAN_INTERVAL_TICKS := 4
const ROSTER_REFRESH_INTERVAL_TICKS := 4

var cached_predators: Array = []
var cached_unit_count := -1
var cached_roster_tick := -1


func reset() -> void:
	cached_predators.clear()
	cached_unit_count = -1
	cached_roster_tick = -1


func collect_commands(world, tick: int) -> Array:
	if world == null or world.battle_over:
		return []
	var commands: Array = []
	var predators := _predator_roster(world, tick)
	for predator_value in predators:
		var predator: Dictionary = predator_value
		if float(predator.get("hp", 0.0)) <= 0.0:
			continue
		var current_target = world.find_unit(int(predator.get("target_id", -1)))
		if String(predator.get("task", "idle")) == "attack" and current_target != null and float(current_target.get("hp", 0.0)) > 0.0:
			continue
		if String(predator.get("task", "idle")) not in ["idle", "hold"]:
			continue
		# Predator acquisition is perception, not movement or combat resolution.
		# Phase idle scans over four fixed ticks (200 ms) so forty campaign
		# predators do not all perform spatial/path queries every simulation tick.
		# Tick one remains eager for deterministic fixtures and immediate startup.
		if tick > 1 and posmod(tick + int(predator.get("id", 0)), IDLE_SCAN_INTERVAL_TICKS) != 0:
			continue
		var metadata: Dictionary = world.data_repository.runtime_metadata(String(predator.get("kind", "")))
		var aggression_range := maxf(0.0, float(metadata.get("aggression_range", predator.get("acquisition_range", 0.0))))
		if aggression_range <= 0.0:
			continue
		var candidates: Array = world.query_units_near(Vector2(predator.get("pos", Vector2.ZERO)), aggression_range).filter(func(candidate):
			return int(candidate.get("team", 0)) > 0 \
				and float(candidate.get("hp", 0.0)) > 0.0 \
				and world.can_unit_reach_entity(predator, candidate)
		)
		candidates.sort_custom(func(left, right):
			var left_distance := Vector2(predator.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(left.get("pos", Vector2.ZERO)))
			var right_distance := Vector2(predator.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(right.get("pos", Vector2.ZERO)))
			if not is_equal_approx(left_distance, right_distance):
				return left_distance < right_distance
			return int(left.get("id", -1)) < int(right.get("id", -1))
		)
		if candidates.is_empty():
			continue
		var target: Dictionary = candidates[0]
		commands.append(Commands.AttackCommand.new(tick, [int(predator.get("id", -1))], int(target.get("id", -1)), {
			"autonomous": true,
			"trigger": "wildlife_predator",
			"leash_origin": Vector2(predator.get("combat_leash_origin", predator.get("pos", Vector2.ZERO))),
			"chase_range": maxf(aggression_range, float(metadata.get("leash_range", aggression_range * 2.0))),
		}))
	return commands


func _predator_roster(world, tick: int) -> Array:
	var source: Array = world.get_units()
	if (
		cached_roster_tick < 0
		or tick < cached_roster_tick
		or tick - cached_roster_tick >= ROSTER_REFRESH_INTERVAL_TICKS
		or source.size() != cached_unit_count
	):
		cached_predators = source.filter(func(unit):
			return int(unit.get("team", -1)) == 0 \
				and world.entity_has_behavior_tag(unit, "predator")
		)
		cached_predators.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
		cached_unit_count = source.size()
		cached_roster_tick = tick
	return cached_predators
