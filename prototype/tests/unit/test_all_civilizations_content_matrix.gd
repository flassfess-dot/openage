extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

const EXPECTED_CIVILIZATIONS := {
	1: {"alias": "egyptian", "name_id": 10231, "ru": "Египтяне"},
	2: {"alias": "greek", "name_id": 10232, "ru": "Греки"},
	3: {"alias": "babylonian", "name_id": 10233, "ru": "Вавилоняне"},
	4: {"alias": "assyrian", "name_id": 10234, "ru": "Ассирийцы"},
	5: {"alias": "minoan", "name_id": 10235, "ru": "Минойцы"},
	6: {"alias": "hittite", "name_id": 10236, "ru": "Хетты"},
	7: {"alias": "phoenician", "name_id": 10237, "ru": "Финикийцы"},
	8: {"alias": "sumerian", "name_id": 10238, "ru": "Шумеры"},
	9: {"alias": "persian", "name_id": 10239, "ru": "Персы"},
	10: {"alias": "shang", "name_id": 10240, "ru": "Шан"},
	11: {"alias": "yamato", "name_id": 10241, "ru": "Ямато"},
	12: {"alias": "choson", "name_id": 10242, "ru": "Чосон"},
	13: {"alias": "roman", "name_id": 10246, "ru": "Римляне"},
	14: {"alias": "carthaginian", "name_id": 10247, "ru": "Карфагеняне"},
	15: {"alias": "palmyran", "name_id": 10249, "ru": "Пальмирцы"},
	16: {"alias": "macedonian", "name_id": 10248, "ru": "Македонцы"},
}

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var matrix := read_json("res://data/content_waves/all_civilizations.json")
	verify_civilizations(matrix, catalog)
	verify_common_roster(matrix, catalog)
	verify_gap_ledger(matrix)
	if failures.is_empty():
		print("E4-001 all-civilizations source matrix tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_civilizations(matrix: Dictionary, catalog) -> void:
	var civilizations: Array = matrix.get("civilizations", [])
	assert_equal(civilizations.size(), 16, "matrix lists every playable civilization")
	var seen_ids: Dictionary = {}
	var supported_types: Array = matrix.get("supported_civilization_effect_types", [])
	var supported_attributes: Array = matrix.get("supported_civilization_attribute_ids", [])
	var supported_resources: Array = matrix.get("supported_civilization_resource_ids", [])
	for expected_id in range(1, 17):
		var entry: Dictionary = civilizations[expected_id - 1] if expected_id - 1 < civilizations.size() else {}
		var civilization_id := int(entry.get("civilization_id", -1))
		assert_equal(civilization_id, expected_id, "civilization ordering is source-stable")
		assert_true(not seen_ids.has(civilization_id), "civilization ID %d is unique" % civilization_id)
		seen_ids[civilization_id] = true
		var expected: Dictionary = EXPECTED_CIVILIZATIONS.get(civilization_id, {})
		assert_equal(String(entry.get("alias", "")), String(expected.get("alias", "")), "civilization %d has the source-stable alias" % civilization_id)
		assert_equal(int(entry.get("name_id", -1)), int(expected.get("name_id", -2)), "civilization %d has the correct localized name ID" % civilization_id)
		assert_true(String(entry.get("vertical_status", "")) in ["planned", "partial", "integrated"], "civilization %d has an honest status" % civilization_id)
		var source := civilization_record(catalog.object_catalog_data, civilization_id)
		assert_true(not source.is_empty(), "civilization %d exists in objects catalog" % civilization_id)
		assert_equal(int(source.get("tech_tree_id", -1)), int(entry.get("technology_tree_effect_bundle_id", -2)), "civilization %d uses exact technology tree bundle" % civilization_id)
		assert_equal(int(source.get("icon_set", -1)), int(entry.get("icon_set", -2)), "civilization %d uses exact icon set" % civilization_id)
		assert_equal(catalog.localization.text(int(entry.get("name_id", -1)), "ru"), String(expected.get("ru", "")), "civilization %d resolves the correct source localization" % civilization_id)
		var bundle: Dictionary = catalog.object_catalog_data.get("effect_bundles", {}).get(String.num_int64(int(source.get("tech_tree_id", -1))), {})
		assert_true(not bundle.get("commands", []).is_empty(), "civilization %d has a non-empty source effect bundle" % civilization_id)
		for command_value in bundle.get("commands", []):
			var command: Dictionary = command_value
			var effect_type := int(command.get("type_id", -1))
			assert_true(supported_types.any(func(value): return int(value) == effect_type), "civilization %d effect type %s is implemented" % [civilization_id, effect_type])
			if effect_type in [0, 4, 5]:
				var attribute_id := int(command.get("attr_c", -1))
				assert_true(supported_attributes.any(func(value): return int(value) == attribute_id), "civilization %d attribute %s has runtime semantics" % [civilization_id, attribute_id])
			elif effect_type == 1:
				var resource_id := int(command.get("attr_a", -1))
				assert_true(supported_resources.any(func(value): return int(value) == resource_id), "civilization %d rule resource %s has runtime semantics" % [civilization_id, resource_id])
			if int(command.get("type_id", -1)) == 102:
				assert_true(catalog.object_catalog_data.get("technologies", {}).has(String.num_int64(int(command.get("attr_d", -1)))), "civilization %d disables a real technology" % civilization_id)
		verify_runtime_records(catalog.runtime_catalog_data, civilization_id)
		verify_initialized_rules(catalog, source, civilization_id)


func verify_runtime_records(runtime: Dictionary, civilization_id: int) -> void:
	for alias_value in runtime.get("archetypes", {}):
		var alias := String(alias_value)
		var archetype: Dictionary = runtime["archetypes"][alias]
		if String(archetype.get("civilization_scope", "team")) != "team":
			continue
		var source_id := int(archetype.get("identifiers", {}).get("source_unit_id", -1))
		var record: Dictionary = archetype.get("records", {}).get(String.num_int64(civilization_id), {})
		assert_true(not record.is_empty(), "%s has a direct civilization %d record" % [alias, civilization_id])
		assert_equal(String(record.get("source_key", "")), "%d:%d" % [civilization_id, source_id], "%s does not silently fall back for civilization %d" % [alias, civilization_id])


func verify_initialized_rules(catalog, civilization: Dictionary, civilization_id: int) -> void:
	var world = SimulationWorld.new(Vector2i(8, 8))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, civilization_id)
	var expected_disabled: Dictionary = {}
	var bundle: Dictionary = catalog.object_catalog_data.get("effect_bundles", {}).get(String.num_int64(int(civilization.get("tech_tree_id", -1))), {})
	for command_value in bundle.get("commands", []):
		var command: Dictionary = command_value
		if int(command.get("type_id", -1)) == 102:
			expected_disabled[int(command.get("attr_d", -1))] = true
	for technology_id in range(catalog.object_catalog_data.get("technologies", {}).size()):
		assert_equal(world.technology_system.is_technology_disabled(1, technology_id), expected_disabled.has(technology_id), "civilization %d technology %d restriction" % [civilization_id, technology_id])


func verify_common_roster(matrix: Dictionary, catalog) -> void:
	var represented := represented_sources(catalog.runtime_catalog_data, catalog.object_catalog_data)
	var seen_lines: Dictionary = {}
	for line_value in matrix.get("common_roster_lines", []):
		var line: Dictionary = line_value
		var line_id := String(line.get("id", ""))
		var alias := String(line.get("runtime_alias", ""))
		assert_true(not line_id.is_empty() and not seen_lines.has(line_id), "common roster line is uniquely identified: %s" % line_id)
		seen_lines[line_id] = true
		assert_true(catalog.runtime_catalog_data.get("archetypes", {}).has(alias), "%s has a runtime archetype" % line_id)
		assert_equal(String(catalog.runtime_catalog_data.get("archetypes", {}).get(alias, {}).get("category", "")), String(line.get("category", "")), "%s category matches runtime" % line_id)
		assert_equal(String(line.get("status", "")), "integrated", "%s does not overstate an incomplete runtime line" % line_id)
		for source_id_value in line.get("source_unit_ids", []):
			var source_id := int(source_id_value)
			assert_true(represented.get(source_id, []).has(alias), "%s source %d reaches its logical runtime line" % [line_id, source_id])
			for civilization_id in range(1, 17):
				assert_true(catalog.object_catalog_data.get("objects", {}).has("%d:%d" % [civilization_id, source_id]), "%s source %d exists for civilization %d" % [line_id, source_id, civilization_id])


func represented_sources(runtime: Dictionary, object_catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var building_sources: Dictionary = {}
	for alias_value in runtime.get("archetypes", {}):
		var alias := String(alias_value)
		var archetype: Dictionary = runtime["archetypes"][alias]
		if String(archetype.get("civilization_scope", "team")) != "team":
			continue
		var source_id := int(archetype.get("identifiers", {}).get("source_unit_id", -1))
		add_representation(result, source_id, alias)
		if String(archetype.get("category", "")) == "building":
			building_sources[source_id] = alias
		for variant_source_id in archetype.get("runtime", {}).get("presentation_variants", {}):
			add_representation(result, int(variant_source_id), alias)
		for variant_source_id in archetype.get("runtime", {}).get("source_variant_unit_ids", []):
			add_representation(result, int(variant_source_id), alias)
	var changed := true
	while changed:
		changed = false
		for bundle_value in object_catalog.get("effect_bundles", {}).values():
			for command_value in bundle_value.get("commands", []):
				var command: Dictionary = command_value
				if int(command.get("type_id", -1)) != 3:
					continue
				var source_id := int(command.get("attr_a", -1))
				var target_id := int(command.get("attr_b", -1))
				if building_sources.has(source_id) and not building_sources.has(target_id):
					building_sources[target_id] = building_sources[source_id]
					add_representation(result, target_id, String(building_sources[source_id]))
					changed = true
	return result


func add_representation(result: Dictionary, source_id: int, alias: String) -> void:
	if not result.has(source_id):
		result[source_id] = []
	if not result[source_id].has(alias):
		result[source_id].append(alias)


func verify_gap_ledger(matrix: Dictionary) -> void:
	var gap_ids: Array = matrix.get("known_gaps", []).map(func(gap): return String(gap.get("id", "")))
	assert_true("E4-CIV-VERTICAL-EVIDENCE" in gap_ids, "non-Roman vertical evidence remains explicit")
	assert_true("E4-CIV-PARITY-CAPTURE" in gap_ids, "executable parity remains separate from source integration")


func civilization_record(catalog: Dictionary, civilization_id: int) -> Dictionary:
	for value in catalog.get("civilizations", []):
		var civilization: Dictionary = value
		if int(civilization.get("civilization_id", -1)) == civilization_id:
			return civilization
	return {}


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
