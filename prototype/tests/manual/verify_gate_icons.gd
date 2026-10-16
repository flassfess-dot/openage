extends Node

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const HudModel := preload("res://scripts/hud_view_model.gd")
const GateCatalog := preload("res://scripts/gate_catalog.gd")
const Definition := preload("res://scripts/match_definition.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")

var catalog
var failures: Array[String] = []
var output_path := "res://qa/gate-icons/source/report.json"
var report := {"passed": false, "variants": 11, "textures": 0, "civilization_tiers": 0, "live_hud_passed": false, "screenshots": []}

func _ready() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func check_textures() -> void:
	var icons = catalog.interface_icons
	check(icons.frame_count("gate") == 11, "eleven native gate portraits")
	check(not icons.has_icon("gate", -1) and not icons.has_icon("gate", 11), "invalid gate variants stay explicit")
	for icon_id in range(11):
		var colors: Dictionary = {}
		for player in range(1, 9):
			var texture: Texture2D = icons.texture("gate", icon_id, player)
			check(texture != null, "portrait %d color %d loads" % [icon_id, player])
			if texture == null: continue
			check(texture.get_size() == Vector2(50, 50), "portrait has the original building icon dimensions")
			check(icons.texture("gate", icon_id, player) == texture, "portrait cache reuses imported textures")
			colors[hash(texture.get_image().get_data())] = true
			report.textures += 1
		check(colors.size() == 8, "portrait %d preserves all eight player colors" % icon_id)

func check_civilizations() -> void:
	var hud := HudModel.new()
	hud.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
	for civilization in range(1, 17):
		var world := World.new(Vector2i(24, 24))
		world.set_gamespec(catalog.gamespec_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_team_civilization(1, civilization)
		for resource in range(4): world.set_resource_amount(1, resource, 10000)
		var worker: Dictionary = world.add_unit(1, "villager", Vector2(6, 6), false)
		var gate: Dictionary = {}
		var seen: Dictionary = {}
		for tier in range(3):
			for technology in [[101, 11], [102, 13], [103, 14]][tier]:
				world.grant_technology(1, technology)
			if gate.is_empty(): gate = world.add_building(9001, "gate", Vector2(14, 14), 1)
			var source_id: int = [10072, 10117, 10155][tier]
			check(int(gate.source_unit_id) == source_id, "existing gate upgrades before its portrait changes")
			var snapshot := Snapshot.with_queries(world, tier, 1)
			var menu: Dictionary = hud.build(snapshot, [int(worker.id)], "LINE")
			var commands: Array = menu.commands.filter(func(command): return command.get("type") == "build" and command.get("id") == "gate")
			check(commands.size() == 1, "civilization %d tier %d exposes a gate command" % [civilization, tier])
			if commands.is_empty(): continue
			var command: Dictionary = commands[0]
			check(int(command.source_unit_id) == source_id, "build command follows current wall research")
			var card: Dictionary = hud.build(snapshot, [int(gate.id)], "LINE")
			var leader: Dictionary = card.selection.leader
			check(command.icon_kind == "gate" and leader.icon_kind == "gate", "menu and selection use gate portraits")
			check(command.icon_id == leader.icon_id, "construction and selected gate agree after upgrade")
			var texture: Texture2D = catalog.interface_icons.texture("gate", command.icon_id, 1)
			check(texture != null, "resolved gate portrait exists")
			if texture != null: seen[hash(texture.get_image().get_data())] = true
			if tier == 0: check(int(command.icon_id) == 0, "small gates share the same architecture")
			report.civilization_tiers += 1
		check(seen.size() == 3, "civilization %d has three visually different researched gate portraits" % civilization)

func check_live_hud() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	var definition := Definition.load_json("res://tests/fixtures/e3_save_state_matrix_match.json")
	definition.players[0].color_index = 4
	definition.players[0].civilization_id = 1
	game.match_definition_override = definition
	get_tree().root.add_child(game)
	if not await MatchReady.wait_for_ready(get_tree(), game):
		failures.append("live match did not become ready")
		game.free()
		return
	game.game_controller.set_paused(true)
	game.set_process(false)
	var world = game.simulation_world
	for resource in range(4): world.set_resource_amount(1, resource, 10000)
	var worker: Dictionary = world.get_units().filter(func(unit): return unit.team == 1 and world.entity_is_worker(unit))[0]
	var gate: Dictionary = {}
	for tier in range(3):
		for technology in [[101, 11], [102, 13], [103, 14]][tier]:
			world.grant_technology(1, technology)
		if gate.is_empty(): gate = world.add_building(9001, "gate", Vector2(18, 18), 1)
		game.resource_catalog.prewarm_match_entities([], [gate])
		game.view_zoom = 1.8
		game.center_view_on_world(Vector2(gate.pos))
		game.message_time = 0
		var ids: Array[int] = [int(worker.id)]
		game.player_control_state.replace_or_add(ids, false)
		game.sync_world_state()
		game.refresh_hud_model()
		var hud = game.hud_controls
		check(hud.set_build_menu_open(true), "worker opens the actual construction palette")
		var command: Dictionary = {}
		for index in range(hud.active_train_commands.size()):
			var current: Dictionary = hud.active_train_commands[index]
			if current.get("type") == "build" and current.get("id") == "gate":
				command = current
				check(hud.train_buttons[index].icon == game.resource_catalog.interface_icons.texture("gate", int(current.icon_id), 1), "actual construction button uses the correct brown gate portrait")
		check(not command.is_empty(), "actual palette contains the gate")
		await capture(game, "tier-%d-build" % tier)
		game.select_hud_building(int(gate.id))
		game.sync_world_state()
		game.refresh_hud_model()
		var leader: Dictionary = game.hud_model.selection.leader
		check(leader.icon_id == command.get("icon_id", -1), "actual selected gate retains its researched portrait")
		check(hud.status_panel.portrait.texture == game.resource_catalog.interface_icons.texture("gate", int(leader.icon_id), 1), "actual selected portrait uses brown owner palette")
		await capture(game, "tier-%d-selected" % tier)
	report.live_hud_passed = true
	game.free()

func capture(game, label: String) -> void:
	game.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output_path.get_base_dir().path_join(label + ".png")
	check(get_tree().root.get_texture().get_image().save_png(path) == OK, "captures actual HUD " + label)
	report.screenshots.append(ProjectSettings.globalize_path(path))

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	report.release = not OS.has_feature("editor")
	if "--require-release" in OS.get_cmdline_user_args(): check(report.release, "runs the real Release")
	catalog = Catalog.new()
	catalog.load()
	check_textures()
	check_civilizations()
	check(report.textures == 88, "all color variants are covered")
	check(report.civilization_tiers == 48, "all civilization and wall research combinations are covered")
	if failures.is_empty() and DisplayServer.get_name() != "headless": await check_live_hud()
	if DisplayServer.get_name() != "headless": check(report.live_hud_passed, "all live HUD scenarios completed")
	report.passed = failures.is_empty()
	report.failures = failures
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Gate icons PASSED: 11 portraits, 8 colors, 48 civilization/tier cases and live HUD upgrades")
	get_tree().quit(0 if failures.is_empty() else 1)
