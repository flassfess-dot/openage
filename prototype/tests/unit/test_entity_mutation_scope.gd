extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Journal := preload("res://scripts/entity_change_journal.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var world := World.new(Vector2i(16, 16))
	world.reset_game(false)
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(4.5, 4.5), false)
	var id := int(unit["id"])
	var previous: Dictionary = world.compact_render_projection(unit)
	var previous_hp := float(unit["hp"])
	var cursor: int = world.entity_changes.revision
	var result: Variant = world.mutate_entity(unit, _damage.bind(unit), Journal.COMBAT | Journal.CONTROL)
	var current: Dictionary = world.compact_render_projection(unit)
	check(result == 17, "a synchronous domain mutation returns its result")
	check(float(current["hp"]) == previous_hp - 1.0, "a raw domain write invalidates the retained render projection")
	check(float(previous["hp"]) == previous_hp, "the old publication remains immutable")
	var delta: Dictionary = world.entity_changes.changes_since(cursor)
	check(int(delta["masks"].get(id, 0)) == (Journal.COMBAT | Journal.CONTROL), "the operation publishes its declared groups")
	world.set_entity_fields(unit, {"hp": 7, "pos": Vector2(6.5, 4.5)})
	check(typeof(unit["hp"]) == TYPE_INT and unit["pos"] == Vector2(6.5, 4.5), "batched setters preserve exact scalar types and values")
	world.entity_changes.flush()
	cursor = world.entity_changes.revision
	world.set_entity_fields(unit, {"hp": 7, "pos": Vector2(6.5, 4.5)})
	check(world.entity_changes.changes_since(cursor)["ids"].is_empty(), "unchanged scalar batches do not invalidate readers")
	var retained_roster: Array = world.get_units()
	world.reset_game(false)
	check(retained_roster.is_empty() and world.find_unit(id) == null, "reset clears both the shared roster and lookup")
	check(world.entity_changes.changes_since(cursor)["full"], "reset rejects a cursor from the previous match")
	for failure in failures:
		push_error(failure)
	print("Entity mutation scope: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _damage(unit: Dictionary) -> int:
	unit["hp"] = float(unit["hp"]) - 1.0
	return 17


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
