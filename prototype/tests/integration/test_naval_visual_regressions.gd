extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Hud := preload("res://scripts/hud_view_model.gd")
const Main := preload("res://main.gd")
const RenderWorld := preload("res://scripts/render_world.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	verify_fish_below_hulls(catalog)
	verify_live_ship_fire(catalog)
	verify_dock_upgrade_icons(catalog)
	for failure in failures: push_error(failure)
	print("Naval visual regressions: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func configured_world(catalog):
	var world = World.new(Vector2i(28, 28))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain: Array[int] = []
	for y in range(28):
		for x in range(28): terrain.append(1 if x <= 6 else 2 if x == 7 else 0)
	var heights: Array[int] = []
	heights.resize(29 * 29)
	heights.fill(0)
	world.configure_map_data({"terrain_ids": terrain, "vertex_levels": heights})
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	return world

func verify_fish_below_hulls(catalog) -> void:
	var world = configured_world(catalog)
	var boat: Dictionary = world.add_unit(1, "fishing_boat", Vector2(4.5, 10.5), false)
	var marine: Array = []
	for kind in ["deep_fish", "shore_fish", "whale"]:
		marine.append(world.add_scenario_resource(kind, Vector2(4.5, 10.5), 500))
	var clock := {"time": 0.0}
	var provider := func(kind, entity): return catalog.resource_frame_info(entity, clock["time"]) if kind == "resource" else catalog.unit_frame_info(entity, "idle") if kind == "unit" else {}
	var projection := func(point): return Vector2((point.x - point.y) * 32, (point.x + point.y) * 16)
	for native in [false, true]:
		var renderer = RenderWorld.new()
		if not native: renderer.native_render_kernel = null
		for direction in range(8):
			boat["pos"] = Vector2(4.5, 10.5) + Vector2.from_angle(direction * PI / 4.0) * 0.35
			boat["previous_pos"] = boat["pos"]
			for sample in range(4):
				clock["time"] = sample * 0.17
				# Exercise both the direct compatibility path and retained snapshot cache.
				for source in [world, {"units": [boat], "resources": marine, "buildings": [], "projectiles": []}]:
					var items: Array = renderer.create_world_drawables(source, projection, 1.0, provider, [], 0, [int(marine[0]["id"])], 1.0)
					var hull_index := -1
					var resource_count := 0
					for index in range(items.size()):
						var item: Dictionary = items[index]
						if item["kind"] in ["unit", "unit_part"]:
							if hull_index < 0: hull_index = index
						if item["kind"] == "resource":
							resource_count += 1
							check(hull_index < 0, "animated marine resource stays below every hull layer, direction %d native %s" % [direction, native])
							check(item["frame_info"].get("texture") != null, "marine source artwork remains visible")
					check(hull_index >= 0 and resource_count == 3, "all marine sprites and actual boat layers are rendered")
					check(items.any(func(item): return item["kind"] == "selection"), "shoal selection survives the water layer change")

func verify_live_ship_fire(catalog) -> void:
	var game = Main.new()
	game.resource_catalog = catalog
	for team in [1, 2]:
		for damage in [{"kind": "scout_ship", "source": 19, "hp": 49.0, "graphic": 326}, {"kind": "scout_ship", "source": 19, "hp": 24.0, "graphic": 327}, {"kind": "fishing_boat", "source": 13, "hp": 19.0, "graphic": 328}, {"kind": "scout_ship", "source": 21, "hp": 19.0, "graphic": 329}, {"kind": "catapult_trireme", "source": 277, "hp": 19.0, "graphic": 330}]:
			var ship := {"id": 81, "kind": damage["kind"], "source_unit_id": damage["source"], "team": team, "hp": damage["hp"], "max_hp": 100.0, "facing": 3, "anim_state": "idle", "anim": 0.0, "death_phase": "alive", "components": {"ownership": {"civilization_id": 13}}}
			var graphic := int(damage["graphic"])
			var spec: Dictionary = catalog.graphics_catalog_data.graphics[str(graphic)]
			var frame_duration := float(spec["frame_rate"])
			var frames := int(spec["frames_per_angle"])
			var seen: Dictionary = {}
			for tick in range(241):
				game.presentation_snapshot = {"tick": tick}
				var info: Dictionary = game.unit_frame_info(ship)
				var parts: Array = info.get("composite_parts", []).filter(func(part): return part.get("effect_kind") == "damage")
				check(parts.size() == 1, "living damaged ship has one fire overlay")
				if parts.size() != 1: continue
				var expected := floori(fmod(tick * 0.05, frames * frame_duration) / frame_duration)
				check(int(parts[0]["frame_index"]) == expected, "live idle fire %d team %d advances at tick %d" % [graphic, team, tick])
				seen[int(parts[0]["frame_index"])] = true
				# Hull clips restart on orders. Fire must retain the same phase.
				for state in ["move", "attack"]:
					ship["anim_state"] = state
					var other: Dictionary = game.unit_frame_info(ship)
					var other_parts: Array = other.get("composite_parts", []).filter(func(part): return part.get("effect_kind") == "damage")
					check(other_parts.size() == 1 and other_parts[0]["frame_index"] == expected, "action changes preserve fire phase")
				ship["anim_state"] = "idle"
			check(seen.size() >= frames - 1, "fire continues through repeated cycles beyond the idle twitch window")
			ship["death_phase"] = "corpse"
			check(not game.unit_frame_info(ship).get("composite_parts", []).any(func(part): return part.get("effect_kind") == "damage"), "corpse does not retain live fire")
	game.free()

func verify_dock_upgrade_icons(catalog) -> void:
	var world = configured_world(catalog)
	world.set_population_cap(1, 100)
	world.set_population_housing(1, 100)
	for resource in range(4): world.set_resource_amount(1, resource, 20000)
	var dock: Dictionary = world.add_building(1500, "dock", Vector2(5.5, 12.5), 1)
	var hud = Hud.new()
	hud.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
	world.grant_technology(1, 101)
	var previous_global: Variant = null
	for stage in [{"source": 19, "icon": 22, "name": 5015}, {"source": 20, "icon": 24, "name": 5016}, {"source": 21, "icon": 26, "name": 5017}]:
		if stage["source"] == 20:
			world.grant_technology(1, 102)
			world.grant_technology(1, 5)
		if stage["source"] == 21:
			world.grant_technology(1, 103)
			world.grant_technology(1, 7)
		if dock.get("production_queue", []).is_empty():
			check(world.enqueue_unit_production(1500, 1, "scout_ship") != null, "real Dock accepts galley production")
		var snapshot := Snapshot.with_queries(world, 10, 1, {"include_production_overview": true})
		var model: Dictionary = hud.build(snapshot, [1500], "LINE")
		var commands: Array = model["commands"].filter(func(command): return command.get("type") == "train" and command.get("id") == "scout_ship")
		check(commands.size() == 1, "Dock exposes one galley lineage command")
		var global_signature := Hud.global_input_signature(snapshot)
		if previous_global != null: check(global_signature != previous_global, "global queue invalidates when a queued unit upgrades")
		previous_global = global_signature
		for rows in [commands, model["queue"], hud.global_queue_model(snapshot, "ru")]:
			check(rows.size() == 1, "queued galley appears in selected and global production UI")
			if rows.size() != 1: continue
			check(int(rows[0]["icon_id"]) == int(stage["icon"]), "Dock command/queue icon follows source %d" % stage["source"])
			check(rows[0]["label"] == catalog.localization.text(int(stage["name"]), "ru"), "Dock command/queue name follows upgraded source")
			check(catalog.interface_icons.texture("unit", int(rows[0]["icon_id"])) != null, "actual upgraded icon asset is available")
		var created: Dictionary = world.add_unit(1, "scout_ship", Vector2(3.5, 4.5), false)
		var portrait: Dictionary = hud.build(Snapshot.with_queries(world, 10, 1), [int(created["id"])], "LINE")["selection"]["leader"]
		check(int(created["source_unit_id"]) == int(stage["source"]) and int(portrait["icon_id"]) == int(stage["icon"]), "produced unit portrait matches the Dock upgrade")
		check(not dock["production_queue"][0].has("source_unit_id"), "display metadata never modifies the paid authoritative queue")

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
