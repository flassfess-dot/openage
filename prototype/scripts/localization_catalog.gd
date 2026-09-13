class_name RoRLocalizationCatalog
extends RefCounted

var fallback_language: String = "en"
var languages: Dictionary = {}


func load_data(data: Dictionary) -> void:
	fallback_language = String(data.get("fallback_language", "en"))
	languages = data.get("languages", {})


func text(string_id: int, locale: String) -> String:
	var key := String.num_int64(string_id)
	var localized: Dictionary = languages.get(locale, {}).get("strings", {})
	if localized.has(key):
		return String(localized[key])
	var fallback: Dictionary = languages.get(fallback_language, {}).get("strings", {})
	return String(fallback.get(key, "[%d]" % string_id))


func has_translation(string_id: int, locale: String) -> bool:
	return languages.get(locale, {}).get("strings", {}).has(String.num_int64(string_id))
