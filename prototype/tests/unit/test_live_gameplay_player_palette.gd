extends SceneTree
const Palette := preload("res://scripts/player_palette.gd")
const PlayerRegistry := preload("res://scripts/player_registry.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var blue := Image.create(13, 1, false, Image.FORMAT_RGBA8)
	var red := Image.create(13, 1, false, Image.FORMAT_RGBA8)
	for index in range(10):
		blue.set_pixel(index, 0, Palette.shade(1, index))
		red.set_pixel(index, 0, Palette.shade(2, index))
	# Ordinary blue artwork, translucent shadow and transparency are not player pixels.
	for image in [blue, red]:
		image.set_pixel(10, 0, Palette.shade(1, 4))
		image.set_pixel(11, 0, Color(0, 0, 0, 0.4))
		image.set_pixel(12, 0, Color.TRANSPARENT)
	var definitions: Array = []
	for player in range(1, 9):
		definitions.append({"team": player, "color_index": 9 - player, "controller": "human" if player == 1 else "ai", "civilization_id": 13})
		var mapped: Image = Palette.remap_images(blue, red, player)
		for index in range(10):
			check(mapped.get_pixel(index, 0).is_equal_approx(Palette.shade(player, index)), "player %d retains original shade %d" % [player, index])
		for index in range(10, 13):
			check(mapped.get_pixel(index, 0) == blue.get_pixel(index, 0), "ordinary pixel %d remains unchanged for player %d" % [index, player])
	check(blue.get_pixel(0, 0) == Palette.shade(1, 0), "remapping never mutates a shared source image")
	var palette := Palette.new()
	palette.configure_players(definitions)
	var registry := PlayerRegistry.new()
	registry.configure(definitions)
	var colors: Dictionary = {}
	for team in range(1, 9):
		check(palette.color_index(team) == 9 - team, "ownership and colour are independent for team %d" % team)
		check(int(registry.players[team]["color_index"]) == 9 - team, "authoritative player registry retains colour for team %d" % team)
		colors[palette.color_for_team(team)] = true
	check(colors.size() == 8, "all eight minimap/player colours are distinct")
	check(palette.color_for_team(0) == Color.WHITE, "Gaia does not acquire an owner colour")
	finish("Live gameplay player palette")

func finish(label: String) -> void:
	if failures.is_empty():
		print(label + " passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
