extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Wildlife := preload("res://scripts/wildlife_behavior_system.gd")
const Awareness := preload("res://scripts/combat_awareness_system.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
var failures: Array[String] = []

class MetadataGuard:
	extends RefCounted
	var battle_over := false
	var calls := 0
	func entity_has_behavior_tag(_unit: Dictionary, _tag: String) -> bool:
		calls += 1
		return false
	func entity_is_static(_unit: Dictionary) -> bool:
		calls += 1
		return false

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load_generated_data()
	var world = World.new(Vector2i(96, 64))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	for index in range(200):
		world.add_unit(0, "gazelle" if index % 2 == 0 else "lion", Vector2(5 + index % 80, 5 + index / 80 * 15), false)
	var wildlife := Wildlife.new()
	var probe := Probe.new()
	world.set_performance_probe(probe)
	wildlife.collect_commands(world, 1)
	check(int(probe.counters.get("wildlife.scheduled_visits", 0)) == 200, "startup keeps eager predator decisions")
	probe.clear()
	for tick in range(2, 22):
		wildlife.collect_commands(world, tick)
	check(int(probe.counters.get("wildlife.scheduled_visits", 0)) == 200, "a scan window visits each land animal once instead of 4000 times")
	# A behavioral oracle deliberately scans the full roster; its decisions and
	# order must agree with the scheduled implementation at every phase.
	for tick in range(22, 62):
		var expected: Array = []
		for animal in wildlife.cached_wildlife:
			var command: Variant = wildlife._gazelle_flee_command(world, animal, tick) if String(animal["kind"]) == "gazelle" else wildlife._predator_command(world, animal, tick)
			if command != null:
				expected.append([command.command_type(), command.unit_ids, command.params])
		var actual: Array = []
		for command in wildlife.collect_commands(world, tick):
			actual.append([command.command_type(), command.unit_ids, command.params])
		check(actual == expected, "scheduled wildlife preserves commands and their order at tick %d" % tick)
	var newcomer: Dictionary = world.add_unit(0, "gazelle", Vector2(40, 40), false)
	wildlife.collect_commands(world, 62)
	check(wildlife.cached_wildlife.has(newcomer), "new wildlife immediately enters the due schedule")
	wildlife.reset()
	check(wildlife.cached_due_wildlife.is_empty(), "reset discards the old schedule")
	var guard := MetadataGuard.new()
	check(not Awareness.new()._eligible_for_awareness(guard, {"team": 0, "hp": 20.0, "combat_enabled": true}) and guard.calls == 0, "neutral animals avoid metadata lookups in player combat awareness")
	for failure in failures:
		push_error(failure)
	print("Wildlife scheduled work: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
