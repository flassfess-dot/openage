extends SceneTree
const Raster := preload("res://scripts/minimap_terrain_raster.gd")
var failures: Array[String] = []
func _initialize() -> void:
	check(ClassDB.class_exists("RoRReadModelKernel") and ClassDB.instantiate("RoRReadModelKernel").has_method("rasterize_minimap_fog"), "native fog raster is available")
	for size in [Vector2i(35, 19), Vector2i(400, 400)]:
		var fog := PackedByteArray()
		fog.resize(size.x * size.y)
		for i in range(fog.size()): fog[i] = i % 3
		for rectangle in [Rect2(12, 15, 232, 116), Rect2(0.25, 1.75, 131, 80)]:
			var scale := minf((rectangle.size.x - 16.0) / (size.x + size.y), (rectangle.size.y - 12.0) * 2.0 / (size.x + size.y))
			var center: Vector2 = rectangle.position + Vector2(rectangle.size.x * 0.5, 6)
			var reference := Raster.build_fog(size, rectangle, center, scale, fog, false)
			var native := Raster.build_fog(size, rectangle, center, scale, fog)
			if native.get_data() != reference.get_data():
				var actual := native.get_data()
				var expected := reference.get_data()
				var shown := 0
				for i in range(actual.size()):
					if actual[i] != expected[i]:
						print("fog byte ", i, " native=", actual[i], " reference=", expected[i])
						shown += 1
						if shown >= 4: break
			check(native.get_data() == reference.get_data(), "native fog pixels exactly match reference for %s, %s" % [size, rectangle])
	var missing := Raster.build_fog(Vector2i(2, 2), Rect2(0,0,8,8), Vector2.ZERO, 1.0, PackedByteArray())
	check(missing.get_data() == Raster.build_fog(Vector2i(2,2), Rect2(0,0,8,8), Vector2.ZERO, 1.0, PackedByteArray(), false).get_data(), "incomplete fog stays transparent")
	for failure in failures: push_error(failure)
	print("Native minimap fog: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
