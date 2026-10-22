extends SceneTree

const Channels := preload("res://scripts/random_map_river_channels.gd")
const Surface := preload("res://scripts/random_map_river_surface.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var nodes: Array = []
	for x in range(6, 23): nodes.append(node(Vector2i(x, 12), Vector2i(x + 1, 12)))
	for y in range(12, 29): nodes.append(node(Vector2i(23, y), Vector2i(23, y + 1)))
	nodes[-1]["is_mouth"] = true
	var terrain: Array[int] = []
	terrain.resize(40 * 40)
	var river := Channels.build(Vector2i(40, 40), terrain, nodes, 48.0)
	var channel: Dictionary = river["channels"][0]
	var points: PackedVector2Array = channel["points"]
	check(points[0] == Vector2(6.5,12.5) and points[-1] == Vector2(23.5,29.5), "curves preserve source and outlet anchors")
	var maximum_turn := 0.0
	for i in range(1, points.size() - 1):
		check(points[i].distance_to(points[i - 1]) <= 0.4, "curve samples keep small continuous steps")
		var a := (points[i] - points[i - 1]).normalized()
		var b := (points[i + 1] - points[i]).normalized()
		maximum_turn = maxf(maximum_turn, absf(a.angle_to(b)))
	check(maximum_turn < deg_to_rad(35.0), "an original right-angle bend becomes a continuous curve")
	check(Array(channel["radii"]).max() <= 3.0, "main river varies in width without turning into a broad uniform canal")
	var bend_index := 0
	for i in range(points.size()):
		if absf(channel["bends"][i]) > absf(channel["bends"][bend_index]): bend_index = i
	var tangent := (points[bend_index + 2] - points[bend_index - 2]).normalized()
	var inside := Vector2(-tangent.y, tangent.x) * signf(channel["bends"][bend_index])
	check(Channels.sediment_at(channel, bend_index, inside) > Channels.sediment_at(channel, bend_index, -inside) + 0.1, "point bars accumulate on the inside of a bend")
	river["mouth_mask"] = PackedByteArray()
	river["mouth_mask"].resize(terrain.size())
	river["runoff_threshold"] = 48.0
	var field := Surface.build(Vector2i(40,40), terrain, river, [])
	check(field == Surface.build(Vector2i(40,40), terrain, river, []), "saved continuous surface is deterministic")
	var at := points[bend_index]
	check(Surface.sample(field, at).x > 1.0, "curved channel retains open water at its centre")
	var bank := Vector2(12.5, 12.5 + float(channel["radii"][0]))
	check(Surface.sample(field, bank).y > 0.99, "the compact bank uses the generated continuous contour")
	var outside := Surface.blend({0:1.0}, Vector4(-1.0,1.0,0.5,0.0))
	var edge := Surface.blend({0:0.5,1:0.5}, Vector4(-0.1,1.0,0.5,0.0))
	check(float(outside.get(1004,0)) == 0.0 and float(edge.get(1004,0)) > 0.25, "wet bank substrate fades into ordinary ground rather than drawing a sand border")
	for depth in [-1.0,-0.1,0.0,0.1,1.0]:
		var blend := Surface.blend({0:0.5,1:0.5}, Vector4(depth,1.0,0.8,0.2))
		var total := 0.0
		for weight in blend.values():
			check(weight >= -0.000001, "river material weights remain positive")
			total += weight
		check(is_equal_approx(total,1.0), "river material weights remain normalized")
	for failure in failures: push_error(failure)
	print("Curved rivers: smooth bends, narrow channel, inner-bank deposits and compact transitions; %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func node(cell: Vector2i, downstream: Vector2i) -> Dictionary:
	return {"cell":cell, "downstream":downstream, "discharge":240.0, "surface_level":0, "is_mouth":false, "basin":1}

func check(value: bool, message: String) -> void:
	if not value and message not in failures: failures.append(message)
