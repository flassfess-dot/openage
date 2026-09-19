extends SceneTree

const NodeRuntime := preload("res://tests/test_support/node_runtime.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_cache_key_self_test()
	test_generated_cache_contract()

	if failures.is_empty():
		print("D-001 versioned cache tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_cache_key_self_test() -> void:
	var node_binary := NodeRuntime.resolve()
	if node_binary.is_empty():
		failures.append(NodeRuntime.unavailable_message())
		return
	var importer := ProjectSettings.globalize_path("res://../tools/ror_import/import_assets.js")
	var output: Array = []
	var exit_code := OS.execute(node_binary, [importer, "--self-test-cache"], output, true)
	assert_equal(exit_code, 0, "cache key self-test exit")
	assert_true("\n".join(output).contains("D-001 asset cache key self-test passed"), "cache key self-test output")


func test_generated_cache_contract() -> void:
	var assets = read_json("res://assets/generated/assets.json")
	var asset_cache: Dictionary = read_json("res://assets/generated/asset-cache.json")
	var gamespec: Dictionary = read_json("res://assets/generated/gamespec-prototype.json")
	var source_manifest: Dictionary = read_json("res://assets/generated/source-manifest.json")
	var runtime_catalog: Dictionary = read_json("res://assets/generated/runtime-catalog.json")
	assert_true(assets is Array and not assets.is_empty(), "asset catalog exists")
	assert_equal(asset_cache.get("formatVersion"), 1, "asset cache schema")
	assert_equal(asset_cache.get("gameVersion"), "1.1", "asset cache game version")
	assert_equal(asset_cache.get("entries", {}).size(), assets.size(), "one cache record per exported asset")
	var unique_files: Dictionary = {}
	for asset in assets:
		var filename: String = asset["file"]
		unique_files[filename] = true
		var record: Dictionary = asset_cache["entries"].get(filename, {})
		assert_equal(String(record.get("key", "")).length(), 64, "%s cache key" % filename)
		var components: Dictionary = record.get("components", {})
		for required in ["sourceSha256", "importerVersion", "schemaVersion", "palette", "gameVersion"]:
			assert_true(components.has(required), "%s includes %s" % [filename, required])
	assert_equal(unique_files.size(), assets.size(), "asset output filenames are unique")
	var villager_cache: Dictionary = asset_cache["entries"].get("villager_idle_00.png", {})
	assert_equal(villager_cache.get("components", {}).get("importerVersion"), "slp-4", "AoE1 ten-shade player-colour decoder version")
	var gamespec_components: Dictionary = gamespec.get("cache", {}).get("components", {})
	assert_equal(String(gamespec.get("cache", {}).get("key", "")).length(), 64, "gamespec cache key")
	for required in ["sourceSha256", "importerVersion", "schemaVersion", "palette", "gameVersion"]:
		assert_true(gamespec_components.has(required), "gamespec includes %s" % required)
	assert_true(gamespec_components["importerVersion"] != asset_cache["entries"].values()[0]["components"]["importerVersion"], "gamespec and asset invalidation are independent")
	assert_equal(runtime_catalog.get("format_version"), 1, "runtime catalog schema")
	assert_equal(runtime_catalog.get("archetype_count"), 68, "runtime archetype count includes the complete common civilization roster, published campaign roster, source wildlife and Artifact")
	assert_equal(String(runtime_catalog.get("cache", {}).get("key", "")).length(), 64, "runtime catalog cache key")
	var runtime_components: Dictionary = runtime_catalog.get("cache", {}).get("components", {})
	for required in ["sourceSha256", "importerVersion", "schemaVersion", "palette", "gameVersion"]:
		assert_true(runtime_components.has(required), "runtime catalog includes %s" % required)
	assert_equal(source_manifest.get("format"), 2, "source manifest schema")
	assert_true(source_manifest.get("palettes", {}).has("50500"), "source manifest stores palette hash")


func read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("cannot read %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		failures.append("invalid JSON %s" % path)
		return {}
	return parsed


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
