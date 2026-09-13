extends SceneTree

var failures: Array[String] = []
var assets: Array = []


func _initialize() -> void:
	assets = read_json("res://assets/generated/assets.json")
	test_palette_pair("graphic_13_p1", "graphic_13_p2", 0, [
		Color8(7, 15, 103, 255),
		Color8(0, 0, 87, 255),
	])
	test_palette_pair("villager_idle", "enemy_villager_idle", 0, [
		Color8(7, 15, 103, 255),
	])

	if failures.is_empty():
		print("G-004b player palette pixel tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_palette_pair(player_one_name: String, player_two_name: String, frame: int, required_dark_shades: Array) -> void:
	var player_one := find_asset(player_one_name, frame)
	var player_two := find_asset(player_two_name, frame)
	assert_true(not player_one.is_empty(), "%s metadata exists" % player_one_name)
	assert_true(not player_two.is_empty(), "%s metadata exists" % player_two_name)
	if player_one.is_empty() or player_two.is_empty():
		return

	var image_one := load_image(String(player_one.get("file", "")))
	var image_two := load_image(String(player_two.get("file", "")))
	if image_one == null or image_two == null:
		return
	assert_equal(image_one.get_size(), image_two.get_size(), "%s/%s dimensions" % [player_one_name, player_two_name])
	if image_one.get_size() != image_two.get_size():
		return

	var differing_pixels := 0
	var alpha_mismatches := 0
	var player_one_colors: Dictionary = {}
	for y in range(image_one.get_height()):
		for x in range(image_one.get_width()):
			var color_one := image_one.get_pixel(x, y)
			var color_two := image_two.get_pixel(x, y)
			if color_one.a8 != color_two.a8:
				alpha_mismatches += 1
			# Godot's lossless texture importer may propagate border RGB into
			# fully transparent texels. Those bytes cannot be displayed and are
			# deliberately excluded; every source-visible texel remains exact.
			if (color_one.a8 > 0 or color_two.a8 > 0) and color_one.to_rgba32() != color_two.to_rgba32():
				differing_pixels += 1
				player_one_colors[color_one.to_rgba32()] = true

	var semantics: Dictionary = player_one.get("semanticPixels", {})
	var expected_differences := int(semantics.get("player_color", 0)) + int(semantics.get("outline", 0))
	assert_equal(alpha_mismatches, 0, "%s/%s alpha masks remain identical" % [player_one_name, player_two_name])
	assert_equal(differing_pixels, expected_differences, "%s only changes source player-colour pixels" % player_one_name)
	for shade in required_dark_shades:
		var color: Color = shade
		assert_true(player_one_colors.has(color.to_rgba32()), "%s preserves dark AoE1 shade %s" % [player_one_name, color])


func find_asset(asset_name: String, frame: int) -> Dictionary:
	for asset in assets:
		if String(asset.get("name", "")) == asset_name and int(asset.get("frame", 0)) == frame:
			return asset
	return {}


func load_image(filename: String) -> Image:
	var texture = load("res://assets/generated/%s" % filename)
	if not texture is Texture2D:
		failures.append("%s loads as Texture2D" % filename)
		return null
	return (texture as Texture2D).get_image()


func read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("cannot read %s" % path)
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		failures.append("invalid array JSON %s" % path)
		return []
	return parsed


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
