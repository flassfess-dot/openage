extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var matrix := read_json("res://data/content_waves/roman_all_ages.json")
	var civilization_id := int(matrix.get("civilization_id", -1))
	var civilization := civilization_record(catalog.object_catalog_data, civilization_id)
	assert_equal(int(civilization.get("tech_tree_id", -1)), int(matrix.get("technology_tree_effect_bundle_id", -2)), "matrix uses exact Roman tech tree bundle")
	var seen_lines: Dictionary = {}
	for line_value in matrix.get("lines", []):
		var line: Dictionary = line_value
		var line_id := String(line.get("id", ""))
		assert_true(not line_id.is_empty() and not seen_lines.has(line_id), "content line ID is unique: %s" % line_id)
		seen_lines[line_id] = true
		assert_true(String(line.get("status", "")) in ["integrated", "partial", "planned"], "%s has explicit evidence status" % line_id)
		var producer_id := int(line.get("producer_unit_id", -1))
		for source_id in line.get("source_unit_ids", []):
			var source := source_record(catalog.object_catalog_data, civilization_id, int(source_id))
			assert_true(not source.is_empty(), "%s source %s exists for Romans" % [line_id, source_id])
			assert_true(int(source.get("language", {}).get("name_id", -1)) > 0, "%s source %s has an original name" % [line_id, source_id])
			if producer_id >= 0 and int(source.get("production", {}).get("train_location_id", -1)) >= 0:
				assert_equal(int(source.get("production", {}).get("train_location_id", -1)), producer_id, "%s source %s uses declared producer" % [line_id, source_id])
		for task_form_id in line.get("task_form_unit_ids", []):
			assert_true(not source_record(catalog.object_catalog_data, civilization_id, int(task_form_id)).is_empty(), "%s task form %s exists" % [line_id, task_form_id])
		for building_source_id in line.get("building_source_unit_ids", []):
			assert_true(not source_record(catalog.object_catalog_data, civilization_id, int(building_source_id)).is_empty(), "%s building source %s exists" % [line_id, building_source_id])
		for resource_source_id in line.get("resource_source_unit_ids", []):
			assert_true(not source_record(catalog.object_catalog_data, 0, int(resource_source_id)).is_empty(), "%s resource source %s exists" % [line_id, resource_source_id])
		for technology_id in line.get("technology_ids", []):
			assert_true(catalog.object_catalog_data.get("technologies", {}).has(String.num_int64(int(technology_id))), "%s technology %s exists" % [line_id, technology_id])
		for evidence_path in line.get("evidence", []):
			assert_true(FileAccess.file_exists(String(evidence_path)), "%s evidence exists" % line_id)
	verify_integrated_sources(matrix, catalog.runtime_catalog_data, catalog.object_catalog_data)
	assert_true(matrix.get("lines", []).any(func(line): return String(line.get("id", "")) == "naval_economy" and String(line.get("status", "")) == "integrated"), "Fishing and Whale economy has a complete source-driven vertical slice")
	assert_true(matrix.get("lines", []).any(func(line): return String(line.get("id", "")) == "naval_trade_transport" and String(line.get("status", "")) == "integrated"), "Trade and Transport source roster has a complete runtime vertical slice")
	assert_true(matrix.get("lines", []).any(func(line): return String(line.get("id", "")) == "naval_combat" and String(line.get("status", "")) == "integrated"), "combat ship roster has source-driven effects/audio/golden/stress evidence without claiming executable parity")
	assert_true(matrix.get("deferred_lines", []).any(func(line): return String(line.get("id", "")) == "naval_world_parity"), "remaining naval world and parity evidence is explicitly deferred, not omitted")
	var gap_ids: Array = matrix.get("known_cross_cutting_gaps", []).map(func(gap): return String(gap.get("id", "")))
	assert_true("ROM-FIRE-PROJECTILES" in gap_ids, "remaining fire-projectile blocker stays explicit")
	assert_true("ROM-NAVAL-COMPOSITE" not in gap_ids, "implemented hull/sail/oar/weapon composition is removed from gaps")
	assert_true("ROM-NAVAL-TRADE" not in gap_ids and "ROM-TRADE-PROFIT-CALIBRATION" in gap_ids, "integrated trade lifecycle leaves only the honest executable-calibration gap")
	assert_true("ROM-BUILD-MENU" not in gap_ids and "ROM-PRIEST-HEAL" not in gap_ids and "ROM-MARTYRDOM" not in gap_ids, "completed command-palette and Priest work is removed from gaps")

	if failures.is_empty():
		print("I12-004 Roman all-ages content matrix tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_integrated_sources(matrix: Dictionary, runtime: Dictionary, object_catalog: Dictionary) -> void:
	var represented: Dictionary = {}
	var represented_buildings: Dictionary = {}
	for archetype_value in runtime.get("archetypes", {}).values():
		var archetype: Dictionary = archetype_value
		var archetype_source_id := int(archetype.get("identifiers", {}).get("source_unit_id", -1))
		represented[archetype_source_id] = true
		if String(archetype.get("category", "")) == "building":
			represented_buildings[archetype_source_id] = true
		for variant_source_id in archetype.get("runtime", {}).get("presentation_variants", {}).keys():
			represented[int(variant_source_id)] = true
		for resource_variant_source_id in archetype.get("runtime", {}).get("source_variant_unit_ids", []):
			represented[int(resource_variant_source_id)] = true
	# Building presentation is directly source-driven, so age upgrades do not
	# require a second manual sprite profile. Follow source unit-upgrade effects
	# only from registered building archetypes; unit upgrades still require a
	# source-aware presentation variant above.
	var changed := true
	while changed:
		changed = false
		for bundle_value in object_catalog.get("effect_bundles", {}).values():
			var bundle: Dictionary = bundle_value
			for command_value in bundle.get("commands", []):
				var command: Dictionary = command_value
				if int(command.get("type_id", -1)) != 3:
					continue
				var upgrade_source_id := int(command.get("attr_a", -1))
				var target_id := int(command.get("attr_b", -1))
				if represented_buildings.has(upgrade_source_id) and not represented_buildings.has(target_id):
					represented_buildings[target_id] = true
					represented[target_id] = true
					changed = true
	for line_value in matrix.get("lines", []):
		var line: Dictionary = line_value
		for integrated_source_id in line.get("integrated_source_unit_ids", []):
			assert_true(represented.has(int(integrated_source_id)), "%s integrated source %s reaches runtime or a presentation variant" % [line.get("id", ""), integrated_source_id])
		for integrated_resource_source_id in line.get("integrated_resource_source_unit_ids", []):
			assert_true(represented.has(int(integrated_resource_source_id)), "%s integrated resource source %s reaches runtime or a declared source variant" % [line.get("id", ""), integrated_resource_source_id])


func civilization_record(catalog: Dictionary, civilization_id: int) -> Dictionary:
	for value in catalog.get("civilizations", []):
		var civilization: Dictionary = value
		if int(civilization.get("civilization_id", -1)) == civilization_id:
			return civilization
	return {}


func source_record(catalog: Dictionary, civilization_id: int, source_unit_id: int) -> Dictionary:
	return catalog.get("objects", {}).get("%d:%d" % [civilization_id, source_unit_id], {})


func read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	failures.append("cannot parse %s" % path)
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
