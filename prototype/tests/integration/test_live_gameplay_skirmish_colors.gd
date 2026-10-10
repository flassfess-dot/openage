extends SceneTree
const Settings := preload("res://scripts/skirmish_settings.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Palette := preload("res://scripts/player_palette.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var settings: Dictionary = Settings.default_settings()
	settings["seed"] = 41641
	settings["players"][0]["color_index"] = 6
	settings["players"][1]["color_index"] = 3
	var built: Dictionary = Settings.build(settings)
	check(bool(built.get("valid", false)), "random map with chosen colours is valid")
	if not bool(built.get("valid", false)):
		finish("Live gameplay skirmish colours")
		return
	var catalog := Catalog.new()
	catalog.load()
	catalog.configure_player_colors(built["definition"]["players"])
	var world := World.new(built["definition"]["map"]["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world, built["definition"], built["map_data"])
	check(int(world.player_registry.players[1]["color_index"]) == 6 and int(world.player_registry.players[2]["color_index"]) == 3, "generated colours survive authoritative match bootstrap")
	var renderer := RenderWorld.new()
	renderer.player_palette = catalog.player_palette
	var drawables: Array = renderer.create_world_drawables(world, func(point): return point, 1.0)
	for item in drawables:
		if item["kind"] == "unit":
			var team := int(item["data"]["team"])
			check(item["player_color"] == Palette.shade(6 if team == 1 else 3, 3), "rendered player colour follows generation settings")
	# Compare actual player-colour pixels against independent blue/red source decodes.
	var players: Array = []
	for team in range(1, 9): players.append({"team": team, "color_index": 9 - team})
	catalog.configure_player_colors(players)
	for team in range(1, 9):
		var unit := {"id": team, "kind": "clubman", "team": team, "facing": 0, "hp": 40.0, "max_hp": 40.0}
		var info: Dictionary = catalog.unit_frame_info(unit, "idle", 0.0)
		var blue: Texture2D = catalog.unit_presentations.animation_frames("clubman", "idle")[0]
		var red: Texture2D = catalog.unit_presentations.animation_frames("enemy_clubman", "idle")[0]
		check_frame(info.get("texture"), blue, red, 9 - team, "unit colour %d" % (9 - team))
		var foundation := {"kind": "barracks", "team": team, "state": "foundation", "construction_stage": 0}
		var foundation_info: Dictionary = catalog.building_frame_info(foundation)
		check_frame(foundation_info.get("texture"), load("res://assets/generated/graphic_82_p1_00.png"), load("res://assets/generated/graphic_82_p2_00.png"), 9 - team, "foundation colour %d" % (9 - team))
		var flag: Dictionary = catalog.rally_flag_frame_info(team, 0.0)
		check_frame(flag.get("texture"), load("res://assets/generated/graphic_322_p1_00.png"), load("res://assets/generated/graphic_322_p2_00.png"), 9 - team, "rally flag colour %d" % (9 - team))
	finish("Live gameplay skirmish colours")

func check_frame(texture: Texture2D, blue: Texture2D, red: Texture2D, player: int, label: String) -> void:
	check(texture != null and blue != null and red != null, label + " has all source textures")
	if texture == null or blue == null or red == null: return
	var actual := texture.get_image()
	var first := blue.get_image()
	var second := red.get_image()
	check(actual.get_size() == first.get_size(), label + " preserves source size")
	if actual.get_size() != first.get_size(): return
	var checked := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var source := first.get_pixel(x, y)
			if source.a <= 0.0 or source == second.get_pixel(x, y): continue
			for shade_index in range(10):
				if source.is_equal_approx(Palette.shade(1, shade_index)):
					check(actual.get_pixel(x, y).is_equal_approx(Palette.shade(player, shade_index)), label + " preserves the exact source shade")
					checked += 1
	check(checked > 0, label + " contains tested player pixels")

func finish(label: String) -> void:
	if failures.is_empty():
		print(label + " passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
