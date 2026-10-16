extends Node

const Catalog := preload("res://scripts/resource_catalog.gd")
const Palette := preload("res://scripts/player_palette.gd")
const Definition := preload("res://scripts/match_definition.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")

var failures: Array[String] = []
var output_path := "res://qa/ui-colors/source/report.json"
var report := {"passed": false, "sheets": 0, "icons": 0, "colors": 8, "pixels": 0, "screenshots": []}

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, context: String) -> void:
	if not condition: failures.append(context)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	report["release"] = not OS.has_feature("editor")
	if "--require-release" in OS.get_cmdline_user_args():
		check(report["release"], "verifier runs the real release executable")
	var catalog := Catalog.new()
	catalog.load()
	var players: Array = []
	for color_index in range(1, 9): players.append({"team": color_index, "color_index": color_index})
	catalog.configure_player_colors(players)
	var seen: Dictionary = {}
	for icon_kind in catalog.interface_icons.ASSET_NAMES:
		var sheet: String = catalog.interface_icons.ASSET_NAMES[icon_kind]
		if seen.has(sheet): continue
		seen[sheet] = true
		report["sheets"] += 1
		for frame in range(catalog.interface_icons.frame_count(icon_kind)):
			var blue: Texture2D = load("res://assets/generated/%s_%02d.png" % [sheet, frame])
			var red: Texture2D = load("res://assets/generated/%s_p2_%02d.png" % [sheet, frame])
			check(blue != null and red != null, "%s:%d has independent original decodes" % [sheet, frame])
			if blue == null or red == null: continue
			report["icons"] += 1
			for color_index in range(1, 9):
				var texture: Texture2D = catalog.interface_icons.texture(icon_kind, frame, color_index)
				check_image(texture, blue, red, color_index, "%s:%d color %d" % [sheet, frame, color_index])
	check(report["icons"] == 427, "all 427 original interface frames are covered")
	check(catalog.interface_icons.texture("unit", 0, 4) == catalog.interface_icons.texture("unit", 0, 4), "repeated HUD refresh reuses the recolored texture")
	check(catalog.interface_icons.texture("gate", 0, 4) != null, "custom gate icon recolors in the packaged runtime")
	var gate_blue: Image = catalog.interface_icons.texture("gate", 0, 1).get_image()
	var gate_brown: Image = catalog.interface_icons.texture("gate", 0, 4).get_image()
	check(gate_blue.get_data() != gate_brown.get_data(), "gate trim follows player color")
	if not failures.is_empty():
		finish()
		return
	report["live_hud_passed"] = false
	await check_live_hud()
	check(bool(report["live_hud_passed"]), "all live HUD scenarios completed")
	finish()

func check_image(texture: Texture2D, blue_texture: Texture2D, red_texture: Texture2D, color_index: int, context: String) -> void:
	if texture == null:
		failures.append(context + " has no texture")
		return
	var actual := texture.get_image()
	var blue := blue_texture.get_image()
	var red := red_texture.get_image()
	if actual.get_size() != blue.get_size():
		failures.append(context + " changed dimensions")
		return
	var shades: Dictionary = {}
	for index in range(10):
		shades[Palette.shade(1, index).to_rgba32()] = Palette.shade(color_index, index)
	for y in range(blue.get_height()):
		for x in range(blue.get_width()):
			var source := blue.get_pixel(x, y)
			var alternate := red.get_pixel(x, y)
			var expected := source
			if color_index == 2:
				expected = alternate
			elif source != alternate and source.a > 0.0:
				check(shades.has(source.to_rgba32()), context + " contains an unrecognized player shade")
				expected = shades.get(source.to_rgba32(), source)
			if not actual.get_pixel(x, y).is_equal_approx(expected):
				failures.append("%s changed the wrong pixel at %d,%d" % [context, x, y])
				return
	report["pixels"] += blue.get_width() * blue.get_height()

func check_live_hud() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	var definition := Definition.load_json("res://tests/fixtures/e3_save_state_matrix_match.json")
	definition["players"][0]["color_index"] = 4
	definition["players"][0]["civilization_id"] = 1
	definition["players"][1]["color_index"] = 6
	game.match_definition_override = definition
	get_tree().root.add_child(game)
	if not await MatchReady.wait_for_ready(get_tree(), game):
		failures.append("live match did not become ready")
		game.free()
		return
	game.game_controller.set_paused(true)
	var world = game.simulation_world
	var town: Dictionary = world.get_buildings().filter(func(building): return building["team"] == 1 and building["kind"] == "town_center")[0]
	var worker: Dictionary = world.get_units().filter(func(unit): return unit["team"] == 1 and world.entity_is_worker(unit))[0]
	for index in range(4):
		check(world.enqueue_unit_production(int(town["id"]), 1, "villager") != null, "live town center accepts a queued villager")
	world.update_production(5)
	game.select_hud_building(int(town["id"]))
	game.sync_world_state()
	game.refresh_hud_model()
	game.center_view_on_world(Vector2(town["pos"]))
	game.message_time = 0
	var hud = game.hud_controls
	var panel = hud.status_panel
	var icons = game.resource_catalog.interface_icons
	var model: Dictionary = game.hud_model
	check(int(model.get("icon_team", -1)) == 1, "commands retain the local player identity")
	check(panel.portrait.texture == icons.texture(model["selection"]["leader"]["icon_kind"], model["selection"]["leader"]["icon_id"], 1), "selected building portrait uses the brown owner's palette")
	var brown: Texture2D = icons.texture("unit", 0, 1)
	check(brown.get_image().get_data() != load("res://assets/generated/unit_icon_00.png").get_image().get_data(), "team 1 maps to chosen brown rather than team-number blue")
	check(panel.job_icon.texture == brown, "active production icon is brown")
	check(not panel.pending_buttons.is_empty() and panel.pending_buttons[0].icon == brown, "grouped pending queue icon is brown")
	check(not panel.global_buttons.is_empty() and panel.global_buttons[0].icon == brown, "global production icon is brown")
	for index in range(hud.active_train_commands.size()):
		var command: Dictionary = hud.active_train_commands[index]
		if command.get("type") == "train":
			check(hud.train_buttons[index].icon == icons.texture(command["icon_kind"], command["icon_id"], 1), "actual training button follows local player color")
	await capture(game, "brown-production")
	var worker_ids: Array[int] = [int(worker["id"])]
	game.player_control_state.replace_or_add(worker_ids, false)
	game.sync_world_state()
	game.refresh_hud_model()
	check(hud.set_build_menu_open(true), "worker opens actual build palette")
	var build_icons := 0
	for index in range(hud.active_train_commands.size()):
		var command: Dictionary = hud.active_train_commands[index]
		check(hud.train_buttons[index].icon != null, "build palette keeps every action glyph including Back")
		if command.get("type") == "build":
			build_icons += 1
			check(hud.train_buttons[index].icon == icons.texture(command["icon_kind"], command["icon_id"], 1), "actual build icon follows local player color")
	check(build_icons > 0, "construction palette contains checked buildings")
	await capture(game, "brown-construction")
	# A selected foreign object has its own owner, independently of the observer.
	var enemy: Dictionary = world.get_units().filter(func(unit): return unit["team"] == 2 and unit["kind"] == "clubman")[0]
	var foreign_snapshot := {"observer_team": 1, "units": [enemy], "player_state": {"team": 1}}
	var enemy_ids: Array[int] = [int(enemy["id"])]
	var foreign_model: Dictionary = game.hud_view_model.build(foreign_snapshot, enemy_ids, "LINE")
	hud.set_view_model(foreign_model)
	check(int(foreign_model["selection"]["leader"]["icon_team"]) == 2, "foreign selection preserves owner identity")
	check(panel.portrait.texture == icons.texture(foreign_model["selection"]["leader"]["icon_kind"], foreign_model["selection"]["leader"]["icon_id"], 2), "foreign portrait uses its green owner rather than local brown")
	# A local player in slot 2 must also retain that identity in the global queue.
	var enemy_town: Dictionary = world.add_building(9901, "town_center", Vector2(23, 14), 2)
	check(world.enqueue_unit_production(int(enemy_town["id"]), 2, "villager") != null, "second player has active production")
	var snapshot: Dictionary = Snapshot.with_queries(world, 0, 2, {"include_production_overview": true})
	var no_selection: Array[int] = []
	var second_model: Dictionary = game.hud_view_model.build(snapshot, no_selection, "LINE")
	hud.set_view_model(second_model)
	check(second_model["global_queue"].size() > 0 and int(second_model["global_queue"][0]["icon_team"]) == 2, "production overview retains a non-first player's identity")
	check(panel.global_buttons[0].icon == icons.texture("unit", 0, 2), "second player's global queue is green")
	report["live_hud_passed"] = true
	game.free()

func capture(game, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output_path.get_base_dir().path_join(label + ".png")
	check(get_tree().root.get_texture().get_image().save_png(path) == OK, "captures actual rendered HUD " + label)
	report["screenshots"].append(ProjectSettings.globalize_path(path))

func finish() -> void:
	report["passed"] = failures.is_empty()
	report["failures"] = failures
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Interface player colors PASSED: 427 icons, 8 colors, live HUD panels and queues")
	get_tree().quit(0 if failures.is_empty() else 1)
