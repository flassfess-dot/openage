extends SceneTree

const LocalizationCatalog := preload("res://scripts/localization_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_generated_languages_and_encoding()
	test_locale_fallback()

	if failures.is_empty():
		print("D-005 localization catalog tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_generated_languages_and_encoding() -> void:
	var file := FileAccess.open("res://assets/generated/localization-catalog.json", FileAccess.READ)
	assert_true(file != null, "localization catalog exists")
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	assert_true(data is Dictionary, "localization catalog JSON")
	if not data is Dictionary:
		return
	assert_equal(data.get("language_count"), 10, "language count")
	assert_equal(data.get("fallback_language"), "en", "fallback language")
	assert_equal(data.get("validation", {}).get("encoding_errors"), 0, "UTF encoding errors")
	assert_equal(data.get("languages", {}).get("en", {}).get("cyrillic_characters"), 0, "English source is not mixed with Russian DLL")
	assert_true(data.get("languages", {}).get("ru", {}).get("cyrillic_characters", 0) > 50000, "Russian Cyrillic decoded")
	assert_true(data.get("linked_string_ids", {}).has("8001"), "tech-tree offset resolves to actual string ID")
	assert_equal(data.get("linked_string_ids", {}).has("157001"), false, "raw offset ID is not treated as DLL ID")
	var catalog = LocalizationCatalog.new()
	catalog.load_data(data)
	assert_equal(catalog.text(1003, "en"), "Age of Empires Help", "English string")
	assert_equal(catalog.text(1003, "ru"), "Помощь", "Russian string")


func test_locale_fallback() -> void:
	var catalog = LocalizationCatalog.new()
	catalog.load_data({
		"fallback_language": "en",
		"languages": {
			"en": {"strings": {"7": "Fallback"}},
			"ru": {"strings": {"8": "Перевод"}},
		},
	})
	assert_equal(catalog.text(8, "ru"), "Перевод", "requested language wins")
	assert_equal(catalog.text(7, "ru"), "Fallback", "missing translation uses fallback")
	assert_equal(catalog.text(9, "ru"), "[9]", "missing fallback remains diagnosable")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
