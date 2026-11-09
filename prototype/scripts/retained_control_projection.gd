extends RefCounted
## Owner-only cache. Entries contain detached immutable values, never entities.
const Contract := preload("res://scripts/entity_read_contract.gd")
const EntityProjection := preload("res://scripts/simulation_presentation_projection.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const MAX_ENTRIES := 8192
var kernel = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
var supported: bool = kernel != null and kernel.has_method("project_retained_control")
var certified := false
var entries: Dictionary = {}
var seen: Dictionary = {}
var counters: Dictionary = {}
var world_id := -1
var epoch := -1
var certified_units: Array = []
var certified_buildings: Array = []
var building_rows_enabled := OS.get_environment("ROR_DIAGNOSTIC_BUILDING_ROW_CAPTURE") != "0"
var building_rows_supported: bool = supported and kernel.has_method("capture_building_control_rows")
var profile_building_rows := "--profile-building-rows-alternatives" in OS.get_cmdline_user_args()
var building_rows_native := false
var publication_sequence := 0
var compare_building_rows := "--compare-building-control-rows" in OS.get_cmdline_user_args()
var compare_enabled := "--compare-retained-scene-controls" in OS.get_cmdline_user_args()
var comparison_generations := 0
var compare_generation := false
var compact_ui_requested := OS.get_environment("ROR_DIAGNOSTIC_COMPACT_UI_CONTROLS") != "0"
var compact_ui_supported: bool = kernel != null and kernel.has_method("project_ui_control")
var profile_compact_ui := "--profile-compact-ui-controls" in OS.get_cmdline_user_args()
var compare_compact_ui := "--compare-compact-ui-controls" in OS.get_cmdline_user_args()
var compact_ui_tick := false
var ui_reference_units: Dictionary = {}
var ui_versions: Dictionary = {}
var ui_versions_supported := false
var source_journal: Variant

func clear() -> void:
	entries.clear()
	seen.clear()
	counters.clear()
	certified_units = []
	certified_buildings = []
	publication_sequence = 0
	if kernel != null and kernel.has_method("clear_control_row_certificates"): kernel.clear_control_row_certificates()
	world_id = -1
	epoch = -1
	comparison_generations = 0
	ui_reference_units.clear()
	ui_versions = {}
	ui_versions_supported = false
	source_journal = null

func begin(world, tick: int) -> void:
	if world_id != world.get_instance_id() or epoch != int(world.entity_changes.epoch):
		clear()
		world_id = world.get_instance_id()
		epoch = int(world.entity_changes.epoch)
	seen.clear()
	source_journal = world.entity_changes
	certified = supported and Contract.native_enabled
	certified_units = []
	certified_buildings = []
	publication_sequence += 1
	ui_reference_units = {}
	ui_versions_supported = world.get_script() != null and world.get_script().resource_path == "res://scripts/simulation_world.gd" and world.entity_mutations.ui_versions_enabled
	ui_versions = world.entity_mutations.ui_control_versions if ui_versions_supported else {}
	compact_ui_tick = compact_ui_requested and compact_ui_supported and certified and (not profile_compact_ui or ((publication_sequence * 1103515245 + 12345) & 0xffff) >= 32768)
	building_rows_native = building_rows_enabled and building_rows_supported and (not profile_building_rows or ((publication_sequence * 1103515245 + 12345) & 0xffff) >= 32768)
	compare_generation = (compare_enabled or compare_building_rows or (compare_compact_ui and compact_ui_tick)) and comparison_generations < 32 and (comparison_generations < 4 or tick % 32 == 0)
	if compare_generation:
		comparison_generations += 1
		counters["comparison_generations"] = comparison_generations

func project(entity: Dictionary, rendered: Dictionary, team: int, metadata_only: bool = false) -> Dictionary:
	var id := int(entity.get("id", -1))
	seen[id] = true
	if supported and Contract.native_enabled:
		var entry: Dictionary = entries.get(id, {})
		if not entries.has(id) and entries.size() < MAX_ENTRIES: entries[id] = entry
		counters["calls"] = int(counters.get("calls", 0)) + 1
		# A building's render row includes animation samples that don't advance
		# the journal. Both the source revision and the exact immutable pose
		# must still match. Enrichment (menus, prices, trade and garrison) runs
		# against the current generation even when this base record is shared.
		var building_version := -1
		if not metadata_only and source_journal != null and entity.has("production_queue") and rendered.is_read_only():
			building_version = source_journal.revision_for(id)
			if building_version >= 0 and entry.get("building_version", -1) == building_version and entry.get("building_observer") == team and is_same(entry.get("rendered"), rendered) and entry.has("record"):
				counters["building_version_hits"] = int(counters.get("building_version_hits", 0)) + 1
				if compare_generation and compare_enabled:
					var expected := EntityProjection._compact_control_entity(entity, team, Callable(), rendered)
					if entry["record"] != expected:
						counters["comparison_mismatches"] = int(counters.get("comparison_mismatches", 0)) + 1
						push_error("Retained building control differs from current state: entity=%d" % id)
				return entry["record"]
		if compact_ui_tick and metadata_only:
			var version := int(ui_versions.get(id, 0))
			var own := team <= 0 or int(entity.get("team", 0)) == team
			var same_version := ui_versions_supported and entry.has("ui_record") and int(entry.get("ui_cached_version", -1)) == version and bool(entry.get("ui_own", not own)) == own and is_same(entry.get("ui_cached_schema"), Contract.UI_COMPONENT_FIELDS) and is_same(entry.get("ui_cached_fields"), Contract.UI_CONTROL_FIELDS)
			var compact: Dictionary
			if same_version:
				compact = entry["ui_record"]
				counters["ui_version_hits"] = int(counters.get("ui_version_hits", 0)) + 1
			else:
				compact = kernel.project_ui_control(entity, rendered, team, Contract.UI_CONTROL_FIELDS, Contract.UI_COMPONENT_FIELDS, Contract.PRIVATE_TRADE_FIELDS, entry, counters)
				if not compact.is_empty():
					entry["ui_cached_version"] = version
					entry["ui_cached_schema"] = Contract.UI_COMPONENT_FIELDS
					entry["ui_cached_fields"] = Contract.UI_CONTROL_FIELDS
			if not compact.is_empty():
				if compare_compact_ui and compare_generation:
					ui_reference_units[id] = kernel.project_retained_control(entity, rendered, team, Contract.CONTROL_FIELDS, Contract.PRIVATE_TRADE_FIELDS, entry, counters, true)
					_compare_ui_fields(compact, ui_reference_units[id], id)
				return compact
			counters["ui_fallbacks"] = int(counters.get("ui_fallbacks", 0)) + 1
		var result: Dictionary = kernel.project_retained_control(entity, rendered, team, Contract.CONTROL_FIELDS, Contract.PRIVATE_TRADE_FIELDS, entry, counters, metadata_only)
		if not result.is_empty():
			if building_version >= 0:
				entry["building_version"] = building_version
				entry["building_observer"] = team
			if compare_generation and compare_enabled:
				var expected := EntityProjection._compact_control_entity(entity, team, Callable(), rendered)
				counters["comparison_rows"] = int(counters.get("comparison_rows", 0)) + 1
				var complete := result
				if metadata_only:
					complete = rendered.duplicate()
					complete.merge(result, true)
					Contract.redact_foreign_control(complete, team)
				if complete != expected:
					counters["comparison_mismatches"] = int(counters.get("comparison_mismatches", 0)) + 1
					push_error("Retained control projection differs from reference: entity=%d" % id)
			return result
	certified = false
	return EntityProjection._compact_control_entity(entity, team, Callable(), rendered)

func _compare_ui_fields(actual: Dictionary, expected: Dictionary, id: int) -> void:
	# Observe every legally published unit, including offscreen priests/boats.
	# Compare the UI contract only; internal combat/work state is intentionally
	# absent from the compact record.
	for key in Contract.UI_CONTROL_FIELDS + ["id", "team", "kind", "entity_type", "behavior_tags", "movement_domain", "task"]:
		if actual.get(key) != expected.get(key):
			counters["ui_field_mismatches"] = int(counters.get("ui_field_mismatches", 0)) + 1
			push_error("UI control field differs: entity=%d field=%s" % [id, key])
	for name in Contract.UI_COMPONENT_FIELDS:
		var actual_component: Dictionary = actual.get("components", {}).get(name, {})
		var expected_component: Dictionary = expected.get("components", {}).get(name, {})
		for key in Contract.UI_COMPONENT_FIELDS[name]:
			counters["ui_field_comparisons"] = int(counters.get("ui_field_comparisons", 0)) + 1
			if actual_component.get(key) != expected_component.get(key):
				counters["ui_field_mismatches"] = int(counters.get("ui_field_mismatches", 0)) + 1
				push_error("UI component differs: entity=%d field=%s.%s" % [id, name, key])

func seal_units(rows: Array) -> void:
	# Native control rows own recursively immutable descendants. Enrichment
	# only adds the factory-frozen shared worker menu to shallow row copies.
	# This certificate is issued only for the canonical UI options below.
	if not certified: return
	for row in rows:
		if not row.is_read_only(): row.make_read_only()
	rows.make_read_only()
	certified_units = rows

func retain_units(rows: Array) -> void:
	if certified and is_same(rows, certified_units): Data._retain_immutable(rows)

func seal_buildings(rows: Array) -> Array:
	if not building_rows_native: return rows
	var expected: Array = Data.capture_frozen({"rows":rows}).get("rows", []) if compare_building_rows and compare_generation else []
	var completed: Array = kernel.capture_building_control_rows(rows, counters)
	if completed.size() != rows.size() or not completed.is_read_only():
		counters["building_row_fallbacks"] = int(counters.get("building_row_fallbacks", 0)) + 1
		return rows
	if compare_building_rows and compare_generation:
		counters["building_row_comparisons"] = int(counters.get("building_row_comparisons", 0)) + rows.size()
		if completed != expected:
			counters["building_row_mismatches"] = int(counters.get("building_row_mismatches", 0)) + 1
			push_error("Building control publication changed values during capture")
	certified_buildings = completed
	return completed

func retain_buildings(rows: Array) -> void:
	if building_rows_native and is_same(rows, certified_buildings): Data._retain_immutable(rows)

func finish() -> void:
	source_journal = null
	for id in entries.keys():
		if not seen.has(id): entries.erase(id)
