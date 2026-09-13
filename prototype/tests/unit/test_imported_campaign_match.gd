extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")

const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"
const EXPECTED_MAP_SIZE := Vector2i(250, 250)
const EXPECTED_PLAYERS := 7
const EXPECTED_SOURCE_OBJECTS := 14923
const EXPECTED_RUNTIME_OBJECTS := 9546
const EXPECTED_PRESENTATION_MARKERS := 12
const EXPECTED_SOURCE_AI_MARKERS := 25
const EXPECTED_UNSUPPORTED_OBJECTS := 0
const EXPECTED_CLASSIFIED_GAIA_OBJECTS := 14263
const EXPECTED_PRESENTATION_ENVIRONMENT := 5310
const EXPECTED_STATIC_OBSTRUCTIONS := 30

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	assert_true(bool(definition.get("valid", false)), "imported campaign match validates: %s" % [definition.get("errors", [])])
	assert_equal(definition.get("id"), "campaign_birth_of_rome", "match has a stable runtime id")
	assert_equal(definition.get("title"), "Восхождение Рима", "source mission title survives conversion")
	assert_equal(definition.get("map", {}).get("size"), EXPECTED_MAP_SIZE, "source map dimensions survive conversion")
	assert_equal(definition.get("players", []).size(), EXPECTED_PLAYERS, "all active scenario players are present")
	assert_equal(definition.get("local_team"), 1, "source human player remains the local team")
	assert_equal(int(definition.get("gaps", {}).get("source_ai_player_count_pending", -1)), 0, "every source AI file is normalized")
	assert_equal(int(definition.get("gaps", {}).get("source_ai_player_count_normalized", -1)), 6, "campaign retains all normalized source AI contracts")
	assert_equal(int(definition.get("gaps", {}).get("source_ai_player_count_integrated", -1)), 6, "every opponent executes the source campaign profile")
	assert_equal(int(definition.get("gaps", {}).get("source_ai_player_count_partial", -1)), 6, "unsupported strategic-number semantics remain explicit")
	var source_delays := [1, 420, 600, 900, 1200, 1800]
	var source_marker_counts := [3, 5, 5, 7, 0, 4]
	var defence_enabled_count := 0
	var strategic_entries: Array = []
	for index in range(6):
		var ai_player: Dictionary = definition.get("players", [])[index + 1]
		var contract: Dictionary = ai_player.get("source_ai", {})
		assert_true(bool(ai_player.get("ai", {}).get("enabled", false)), "source AI player is enabled")
		assert_equal(String(ai_player.get("ai", {}).get("profile", "")), "source_campaign_v1", "campaign never substitutes generic skirmish AI")
		assert_equal(int(source_strategic_value(contract, 104)), source_delays[index], "source initial attack delay survives conversion")
		assert_equal(contract.get("target_markers", []).size(), source_marker_counts[index], "source attack marker count survives conversion")
		assert_true(not String(contract.get("rules_sha256", "")).is_empty(), "source rules retain an auditable content hash")
		assert_true(not contract.has("rules_text"), "runtime match does not embed the legacy AI source text")
		strategic_entries.append_array(contract.get("strategic_numbers", []))
		if bool(contract.get("runtime_support", {}).get("defence_enabled", false)):
			defence_enabled_count += 1
		for marker_value in contract.get("target_markers", []):
			assert_true(marker_value.get("position") is Vector2, "source Flare position is normalized for runtime commands")
	assert_equal(defence_enabled_count, 5, "five source profiles activate persistent defend groups from their non-zero source settings")
	for strategic_id in [18, 22, 25, 28, 35, 38, 42, 43, 44, 50, 51, 52, 54, 55, 56, 57, 92]:
		var entries: Array = strategic_entries.filter(func(entry): return int(entry.get("source_id", -1)) == strategic_id)
		assert_true(entries.all(func(entry): return String(entry.get("runtime_semantics", "")) != "pending"), "encountered defend/explore strategic number %d leaves the pending ledger" % strategic_id)
	var variation_entries: Array = strategic_entries.filter(func(entry): return int(entry.get("source_id", -1)) == 72)
	assert_true(not variation_entries.is_empty() and variation_entries.all(func(entry): return String(entry.get("runtime_semantics", "")) == "pending"), "ambiguous sentry-distance variation remains explicitly pending")
	assert_equal(definition.get("entities", []).size(), EXPECTED_RUNTIME_OBJECTS, "currently supported source objects enter the runtime")
	assert_equal(definition.get("source_entities", []).size(), EXPECTED_SOURCE_OBJECTS, "every source object remains traceable")
	assert_equal(definition.get("presentation_markers", []).size(), EXPECTED_PRESENTATION_MARKERS, "source scenario flags enter the presentation layer")
	assert_equal(definition.get("presentation_environment", []).size(), EXPECTED_PRESENTATION_ENVIRONMENT, "source terrain overlays, scenery and birds enter the indexed presentation field")
	assert_equal(definition.get("static_obstructions", []).size(), EXPECTED_STATIC_OBSTRUCTIONS, "source cliffs enter the navigation-owned static obstruction batch")
	for marker_value in definition.get("presentation_markers", []):
		var marker: Dictionary = marker_value
		assert_equal(int(marker.get("source_unit_id", -1)), 330, "presentation marker retains the source Flag DAT id")
		assert_equal(int(marker.get("graphic_id", -1)), 322, "source Flag resolves its original graphic id")
		assert_equal(String(marker.get("asset_name", "")), "graphic_322_p1", "Roman source Flag resolves the imported player palette")
		assert_true(marker.get("position") is Vector2, "presentation marker position is normalized for rendering")

	var gaps: Dictionary = definition.get("gaps", {})
	assert_equal(int(gaps.get("source_object_count", -1)), EXPECTED_SOURCE_OBJECTS, "gap ledger owns the source object total")
	assert_equal(int(gaps.get("runtime_entity_count", -1)), EXPECTED_RUNTIME_OBJECTS, "gap ledger owns the mapped object total")
	assert_equal(int(gaps.get("unsupported_object_count", -1)), EXPECTED_UNSUPPORTED_OBJECTS, "only unclassified simulation and environment objects remain unsupported")
	assert_equal(int(gaps.get("presentation_marker_count", -1)), EXPECTED_PRESENTATION_MARKERS, "gap ledger records presentation-owned source objects")
	assert_equal(int(gaps.get("presentation_environment_count", -1)), EXPECTED_PRESENTATION_ENVIRONMENT, "gap ledger records environment-presentation-owned source objects")
	assert_equal(int(gaps.get("static_obstruction_count", -1)), EXPECTED_STATIC_OBSTRUCTIONS, "gap ledger records navigation-owned source cliffs")
	assert_equal(int(gaps.get("source_ai_marker_count", -1)), EXPECTED_SOURCE_AI_MARKERS, "gap ledger records campaign-AI-owned source objects")
	var runtime_status_counts: Dictionary = {}
	for source_value in definition.get("source_entities", []):
		var source: Dictionary = source_value
		var status := String(source.get("runtime_status", "missing"))
		runtime_status_counts[status] = int(runtime_status_counts.get(status, 0)) + 1
	assert_equal(int(runtime_status_counts.get("mapped", 0)), EXPECTED_RUNTIME_OBJECTS, "mapped source object count is auditable")
	assert_equal(int(runtime_status_counts.get("presentation_only", 0)), EXPECTED_PRESENTATION_MARKERS, "presentation-only source object count is auditable")
	assert_equal(int(runtime_status_counts.get("presentation_environment", 0)), EXPECTED_PRESENTATION_ENVIRONMENT, "environment presentation source object count is auditable")
	assert_equal(int(runtime_status_counts.get("static_obstruction", 0)), EXPECTED_STATIC_OBSTRUCTIONS, "static obstruction source object count is auditable")
	assert_equal(int(runtime_status_counts.get("source_ai_marker", 0)), EXPECTED_SOURCE_AI_MARKERS, "source-AI marker count is auditable")
	assert_equal(int(runtime_status_counts.get("gap", 0)), EXPECTED_UNSUPPORTED_OBJECTS, "remaining unsupported object count is auditable")
	var gaia_expected := {
		"ambient_actor": [27, "environment_presentation", "animated_presentation_batch", "integrated"],
		"forest_resource": [8883, "forest_field", "static_resource_nodes", "integrated"],
		"presentation_scenery": [4049, "environment_presentation", "static_presentation_batch", "integrated"],
		"static_obstruction": [30, "navigation_grid", "static_obstruction_batch", "integrated"],
		"terrain_feature": [1234, "terrain_system", "terrain_overlay", "integrated"],
		"wildlife": [40, "wildlife_system", "mobile_simulation_entities", "integrated"],
	}
	var classified_total := 0
	for classification_value in gaps.get("gaia_classifications", []):
		var classification: Dictionary = classification_value
		var category := String(classification.get("category", ""))
		assert_true(gaia_expected.has(category), "Gaia category is explicitly owned: %s" % category)
		if not gaia_expected.has(category):
			continue
		var expected: Array = gaia_expected[category]
		var instance_count := int(classification.get("instance_count", 0))
		classified_total += instance_count
		assert_equal(instance_count, int(expected[0]), "%s source object count is stable" % category)
		assert_equal(String(classification.get("owner_system", "")), String(expected[1]), "%s has the correct system owner" % category)
		assert_equal(String(classification.get("integration_strategy", "")), String(expected[2]), "%s has a non-entity integration strategy" % category)
		assert_equal(String(classification.get("integration_status", "")), String(expected[3]), "%s reports its actual owner integration status" % category)
	assert_equal(classified_total, EXPECTED_CLASSIFIED_GAIA_OBJECTS, "every original Gaia gap has exactly one owner")
	var static_trees: Array = definition.get("entities", []).filter(func(entity): return bool(entity.get("static_field_node", false)))
	assert_equal(static_trees.size(), 8883, "forest owner integrates every previously missing source tree")
	assert_true(static_trees.all(func(tree): return int(tree.get("source_graphic_id", -1)) >= 0 and not String(tree.get("source_graphic_asset_name", "")).is_empty()), "forest nodes retain exact source presentation identity")
	for obstruction_value in definition.get("static_obstructions", []):
		var obstruction: Dictionary = obstruction_value
		assert_true(not obstruction.get("occupied_cells", []).is_empty(), "source cliff has an authoritative occupied-cell footprint")
		assert_true(obstruction.get("occupied_cells", []).all(func(cell): return cell is Vector2i), "source cliff occupied cells are normalized for navigation")
		assert_true(int(obstruction.get("source_frame", -1)) >= 0, "source cliff angle selects an original directional frame")
	assert_equal(int(gaps.get("unsupported_legacy_victory_condition_count", -1)), 0, "all first-mission victory conditions are supported")
	assert_equal(String(definition.get("scenario_logic", {}).get("status", "")), "integrated", "legacy victory logic is integrated")

	var scenario: Dictionary = definition.get("scenario_definition", {})
	assert_equal(String(scenario.get("source_format", "")), "ror_legacy_victory", "scenario keeps its source victory format")
	assert_equal(scenario.get("participants", []).size(), EXPECTED_PLAYERS, "every active source player keeps a victory definition")
	var roman_groups: Array = scenario.get("participants", [])[0].get("groups", [])
	assert_equal(roman_groups.size(), 1, "Roman mission conditions retain their source victory group")
	assert_equal(roman_groups[0].get("conditions", []).size(), 12, "all twelve fortified-tower areas are imported")
	for condition_value in roman_groups[0].get("conditions", []):
		var condition: Dictionary = condition_value
		assert_equal(condition.get("type"), "create_in_area", "Roman objective uses CreateInArea semantics")
		assert_equal(int(condition.get("source_unit_id", -1)), 199, "Roman objective requires the source Sentry Tower")
		assert_equal(condition.get("kind"), "tower", "Sentry Tower uses the shared tower archetype")
	for participant_value in scenario.get("participants", []).slice(1):
		var participant: Dictionary = participant_value
		var condition: Dictionary = participant.get("groups", [])[0].get("conditions", [])[0]
		assert_equal(condition.get("type"), "destroy_player", "opponent victory retains DestroyPlayer semantics")
		assert_equal(int(condition.get("target_team", -1)), 1, "opponent objective targets the Roman player")
	assert_equal(definition.get("victory_rules", [])[0].get("type"), "scenario_definition", "source scenario rule is evaluated before fallback conquest")

	for entity_value in definition.get("entities", []):
		var entity: Dictionary = entity_value
		assert_true(int(entity.get("scenario_object_id", -1)) >= 0, "runtime entity keeps scenario object id")
		assert_true(int(entity.get("source_unit_id", -1)) >= 0, "runtime entity keeps source DAT id")
		var position: Vector2 = entity.get("position", Vector2(-1, -1))
		assert_true(position.x >= 0.0 and position.y >= 0.0 and position.x < EXPECTED_MAP_SIZE.x and position.y < EXPECTED_MAP_SIZE.y, "runtime entity remains inside the source map")

	var generated := MapGenerator.generate(definition)
	assert_equal(generated.get("size"), EXPECTED_MAP_SIZE, "fixed source map uses the normal map generator contract")
	assert_equal(generated.get("terrain_ids", []).size(), EXPECTED_MAP_SIZE.x * EXPECTED_MAP_SIZE.y, "all source terrain cells reach the runtime")
	assert_equal(generated.get("vertex_levels", []).size(), (EXPECTED_MAP_SIZE.x + 1) * (EXPECTED_MAP_SIZE.y + 1), "source elevations become complete runtime vertices")
	assert_true(generated.get("resources", []).is_empty(), "fixed maps never add random resources")

	var player_one: Dictionary = definition.get("players", [])[0]
	assert_equal(player_one.get("controller"), "human", "source controller type survives conversion")
	assert_equal(int(player_one.get("civilization_id", -1)), 13, "Roman civilization id survives conversion")
	assert_equal(int(player_one.get("population_limit", -1)), 75, "source population limit is promoted into the runtime player contract")
	assert_equal(int(player_one.get("starting_resources", {}).get("gold", -1)), 150, "source starting resources survive conversion")
	assert_true(String(definition.get("source", {}).get("source_path", "")).ends_with("Расцвет Рима.cpx"), "source identity uses a portable campaign path")
	assert_true(not String(definition.get("source", {}).get("source_path", "")).contains(":"), "generated match contains no machine-specific source path")

	if failures.is_empty():
		print("I12-020E imported Birth of Rome source-AI contract tests passed")
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


func source_strategic_value(contract: Dictionary, source_id: int) -> int:
	for entry_value in contract.get("strategic_numbers", []):
		var entry: Dictionary = entry_value
		if int(entry.get("source_id", -1)) == source_id:
			return int(entry.get("value", 0))
	return 0
