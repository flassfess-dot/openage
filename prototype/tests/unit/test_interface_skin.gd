extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load()
	assert_equal(catalog.interface_source_inventory_data.get("sourceArchives", []).size(), 3, "all layered Interfac archives are inventoried")
	for width in [640, 800, 1024]:
		var shell: Dictionary = catalog.interface_skin.hud_shell(width, 0)
		assert_true(shell["top"] != null, "%d top HUD frame loads" % width)
		assert_true(shell["bottom"] != null, "%d bottom HUD frame loads" % width)
		assert_equal(shell["top"].get_height(), 20, "%d top HUD frame height" % width)
		assert_equal(shell["bottom"].get_height(), 126, "%d bottom HUD frame height" % width)
		assert_true(catalog.interface_skin.has_valid_provenance(String(shell["asset_name"]), 0), "%d shell has exact archive/palette provenance" % width)
		assert_true(catalog.interface_skin.has_valid_provenance(String(shell["asset_name"]), 1), "%d bottom shell has exact archive/palette provenance" % width)
	assert_true(catalog.interface_skin.has_valid_provenance("interface_panel", 0), "fallback panel has exact archive/palette provenance")
	var inventory: Dictionary = catalog.interface_source_inventory_data
	assert_true(inventory.get("duplicateIds", {}).has("50103"), "duplicate source IDs remain visible instead of being flattened")
	if failures.is_empty():
		print("I12-020L source HUD skin tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])

