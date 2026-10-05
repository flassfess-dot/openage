extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Model := preload("res://scripts/hud_view_model.gd")
const Controls := preload("res://scripts/hud_controls.gd")
const Registry := preload("res://scripts/interface_icon_registry.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	var registry = catalog.interface_icons
	for action in Registry.COMMAND_GLYPHS:
		var icon := Registry.command_icon(action)
		check(registry.texture(icon["icon_kind"], icon["icon_id"]) != null, "%s has a usable source icon" % action)
	var textures: Array = []
	for stance in ["aggressive", "defensive", "stand_ground", "passive"]:
		var icon := Registry.command_icon("stance", stance)
		var texture = registry.texture(icon["icon_kind"], icon["icon_id"])
		check(texture != null and texture not in textures, "each stance has a distinct meaningful icon")
		textures.append(texture)
	var ground := Registry.command_icon("attack_ground")
	check(ground != Registry.command_icon("attack_move") and registry.texture(ground["icon_kind"], ground["icon_id"]) != null, "ground fire is distinct from an attack order")
	var world = World.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var ship: Dictionary = world.add_unit(1, "transport", Vector2(6, 6), false)
	world.update_fog_of_war()
	var model := Model.new()
	model.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
	var ids: Array[int] = [int(ship["id"])]
	var initial := model.build_update(Snapshot.with_queries(world, 0, 1), ids, "RECTANGLE")
	var action := unload_action(initial["model"])
	check(not action.is_empty() and not action["enabled"] and action["icon_id"] == 5, "empty transport displays its disabled unload icon")
	check(initial["model"]["commands"].all(func(command): return command.get("id") not in ["attack_move", "stance"]), "unarmed transport shows applicable commands")
	ship["components"]["cargo"]["passenger_ids"] = [123]
	ship["components"]["cargo"]["count"] = 1
	var loaded := model.build_update(Snapshot.with_queries(world, 0, 1), ids, "RECTANGLE", initial["signature"])
	check(loaded["changed"] and unload_action(loaded["model"])["enabled"], "boarding invalidates HUD signature without changing selection")
	var controls := Controls.new()
	controls.icon_registry = registry
	check(controls.command_icon(unload_action(loaded["model"])) != null, "actual HUD renderer resolves unload texture")
	controls.free()
	ship["components"]["cargo"]["passenger_ids"] = []
	ship["components"]["cargo"]["count"] = 0
	var empty := model.build_update(Snapshot.with_queries(world, 0, 1), ids, "RECTANGLE", loaded["signature"])
	check(empty["changed"] and not unload_action(empty["model"])["enabled"], "unloading refreshes the same selected transport")
	for failure in failures: push_error(failure)
	print("Command icons and cargo HUD: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func unload_action(model: Dictionary) -> Dictionary:
	for command in model["commands"]:
		if command.get("id") == "unload": return command
	return {}
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
