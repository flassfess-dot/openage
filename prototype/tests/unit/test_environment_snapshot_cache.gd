extends SceneTree
const Game := preload("res://main.gd")
const Field := preload("res://scripts/environment_presentation_field.gd")
class CountingField extends Field:
	var queries := 0
	func query(bounds: Rect2i) -> Array:
		queries += 1
		return super.query(bounds)
var failures: Array[String] = []
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _initialize() -> void:
	var game := Game.new()
	game.map_size = Vector2i(400,400)
	game.presentation_snapshot = {"tick":1}
	var field := CountingField.new()
	game.environment_presentation_field = field
	var items: Array = [
		{"id":1,"position":Vector2(0,1),"presentation_bounds":[-2,-2,2,2]},
		{"id":2,"position":Vector2(12,12)},
		{"id":3,"position":Vector2(399,399),"presentation_bounds":[-2,-2,2,2]},
		{"id":4,"position":Vector2(210,210)},
		{"id":5,"position":Vector2(2,2),"presentation_layer":"ambient_actor"}
	]
	field.configure(items)
	var reference := Field.new()
	reference.configure(items)
	for bounds in [Rect2i(0,0,80,60),Rect2i(320,340,80,60),Rect2i(0,340,80,60),Rect2i(320,0,80,60),Rect2i(180,180,80,60)]:
		game.cached_environment_bounds = Rect2i()
		game.cached_environment_items.clear()
		var raw := Rect2i(bounds.position-Vector2i(2,2),bounds.size+Vector2i(4,4))
		var expected := reference.query(game._expanded_tile_bounds(raw,6))
		expected.append_array(reference.mobile_items())
		var before := field.queries
		for tick in range(100):
			game.presentation_snapshot = {"tick":tick}
			game._sync_environment_snapshot(bounds)
			check(game.presentation_snapshot["environment"]==expected,"unchanged complete ordered scenery at map edges and interior")
		check(field.queries-before==1,"one query across 100 publications, including map corners")
	var before := field.queries
	game._sync_environment_snapshot(Rect2i(182,182,80,60))
	check(field.queries==before,"camera movement within retained margin reuses scenery")
	game._sync_environment_snapshot(Rect2i(220,220,80,60))
	check(field.queries==before+1,"camera leaving retained area refreshes immediately")
	game.free()
	for failure in failures: push_error(failure)
	print("Environment snapshot cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
