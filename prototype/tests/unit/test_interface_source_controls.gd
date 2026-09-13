extends SceneTree

const ParityGate := preload("res://scripts/parity_measurement_gate.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

const MANIFEST_PATH := "res://data/parity/source_ui_executable_gate.json"
const COMMAND_IDS := [50713, 50714, 50715, 50716]
const COMPACT_IDS := [50725, 50726, 50727, 50728]

var failures: Array[String] = []


func _initialize() -> void:
	var manifest: Dictionary = ParityGate.load_manifest(MANIFEST_PATH)
	assert_true(not manifest.is_empty(), "source UI measurement manifest loads")
	assert_true(ParityGate.validation_issues(manifest).is_empty(), "source UI measurement contract is structurally valid")
	assert_equal(String(manifest.get("status", "")), "capture_pending", "UI parity gate remains honest")
	assert_true(not ParityGate.can_claim_parity(manifest), "unobserved source control states cannot claim parity")
	var unresolved := ParityGate.unresolved_requirements(manifest)
	for scene_id in ["command_button_state_order", "compact_button_state_order", "status_strip_semantics", "hud_shell_context_mapping"]:
		assert_true(unresolved.has("original_capture:%s" % scene_id), "%s requires original capture" % scene_id)

	var catalog := ResourceCatalog.new()
	catalog.load()
	for source_id in COMMAND_IDS:
		assert_control_family(catalog, source_id, Vector2i(54, 54), true)
		assert_inventory_role(catalog, source_id, "square_control_backplate_candidate")
	for source_id in COMPACT_IDS:
		assert_control_family(catalog, source_id, Vector2i(54, 31), false)
		assert_inventory_role(catalog, source_id, "compact_control_family_candidate")

	var status: Dictionary = catalog.interface_skin.status_candidate()
	assert_equal(status.get("semantic_role_status", ""), "original_capture_pending", "status meaning remains observation-gated")
	var status_frames: Array = status.get("frames", [])
	assert_equal(status_frames.size(), 26, "all status candidate frames load")
	for texture_value in status_frames:
		var texture: Texture2D = texture_value
		assert_equal(Vector2i(texture.get_width(), texture.get_height()), Vector2i(50, 7), "status candidate keeps native dimensions")
		assert_true(catalog.interface_skin.has_valid_provenance("hud_status_50745", status_frames.find(texture)), "status frame has exact provenance")
	assert_inventory_role(catalog, 50745, "status_strip_family_candidate")
	assert_equal(catalog.interface_skin.status_frame_index(1.0), 0, "full remaining value selects the first source strip")
	assert_equal(catalog.interface_skin.status_frame_index(0.5), 13, "half remaining value selects the central source strip")
	assert_equal(catalog.interface_skin.status_frame_index(0.0), 25, "empty remaining value selects the last source strip")
	assert_true(catalog.interface_skin.status_frame(0.5) != null, "source status lookup returns a renderable texture")

	var reference: Dictionary = manifest.get("reference_build", {})
	assert_equal(String(reference.get("interface_archive", "")), "data/Interfac.drs", "measurement names the exact interface layer")
	assert_equal(String(reference.get("interface_archive_sha256", "")), "8a7f1b1f9009d4bc0262c7890935d69d62668c80751ec3b861345064a0e63d33", "measurement pins the installed interface archive")

	if failures.is_empty():
		print("I12-020L source UI control evidence tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_control_family(catalog: ResourceCatalog, source_id: int, expected_dimensions: Vector2i, expect_identical_frames: bool) -> void:
	var candidate: Dictionary = catalog.interface_skin.control_candidate(source_id)
	assert_equal(candidate.get("semantic_composition_status", ""), "original_capture_pending", "%d semantics remain observation-gated" % source_id)
	assert_true(candidate.get("semantic_composition", {}).is_empty(), "%d does not invent state composition" % source_id)
	var frames: Array = candidate.get("frames", [])
	var hashes: Array = candidate.get("frame_sha256", [])
	assert_equal(frames.size(), 4, "%d imports every candidate frame" % source_id)
	assert_equal(hashes.size(), 4, "%d records every decoded frame hash" % source_id)
	assert_true(not String(hashes[0]).is_empty(), "%d hashes decoded source pixels" % source_id)
	if expect_identical_frames:
		for hash_value in hashes:
			assert_equal(hash_value, hashes[0], "%d contains four byte-identical decoded backplates" % source_id)
	else:
		var unique_hashes: Dictionary = {}
		for hash_value in hashes:
			unique_hashes[String(hash_value)] = true
		assert_equal(unique_hashes.size(), 4, "%d contains four distinct decoded compact-control frames" % source_id)
	for frame in range(frames.size()):
		var texture: Texture2D = frames[frame]
		assert_equal(Vector2i(texture.get_width(), texture.get_height()), expected_dimensions, "%d frame %d keeps native dimensions" % [source_id, frame])
		assert_true(catalog.interface_skin.has_valid_provenance("hud_control_%d" % source_id, frame), "%d frame %d has exact provenance" % [source_id, frame])


func assert_inventory_role(catalog: ResourceCatalog, source_id: int, expected_role: String) -> void:
	for record_value in catalog.interface_source_inventory_data.get("records", []):
		var record: Dictionary = record_value
		if String(record.get("source", "")) == "data/Interfac.drs" and int(record.get("id", -1)) == source_id:
			assert_equal(String(record.get("role", "")), expected_role, "%d has evidence-limited inventory role" % source_id)
			return
	failures.append("%d inventory record is missing" % source_id)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
