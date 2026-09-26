extends SceneTree

const HUDModalOverlay := preload("res://scripts/hud_modal_overlay.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var definition := {
		"map": {"size": Vector2i(72, 72), "seed": 41721, "type_id": "grasslands"},
		"players": [{"team": 1, "starting_age_technology_id": 102, "population_limit": 50}],
		"victory_rules": [{"type": "conquest"}],
		"skirmish_settings": {"map_type_id": "grasslands", "starting_age_id": "bronze", "population_limit": 50, "victory_mode_id": "conquest", "full_tech_tree": true},
	}
	var summary: String = HUDModalOverlay.instruction_summary(definition)
	for expected in ["Внутренняя карта", "72×72", "41721", "Бронзовый век", "50", "Завоевание", "Full Tech Tree: Вкл."]:
		assert_true(summary.contains(expected), "pause instructions include %s" % expected)
	definition["skirmish_settings"] = {}
	summary = HUDModalOverlay.instruction_summary(definition)
	assert_true(summary.contains("Бронзовый век") and summary.contains("Завоевание"), "non-skirmish match uses its actual player and victory rules")
	assert_true(summary.contains("Full Tech Tree: Выкл."), "unconfigured Full Tech Tree is reported as disabled, not assumed enabled")
	definition["map"] = {"size": [24, 24], "seed": 41721, "generator": {"type": "coastal_land"}}
	definition["players"] = [{"team": 1}]
	summary = HUDModalOverlay.instruction_summary(definition)
	assert_true(summary.contains("Побережье") and summary.contains("Каменный век") and summary.contains("Лимит: 50"), "prototype match reports the simulation defaults and actual map generator")
	assert_true(HUDModalOverlay.match_status_summary({"player_state": {"status": "resigned"}}).contains("наблюдателя"), "menu explains spectator-only control state")
	assert_true(HUDModalOverlay.match_status_summary({"battle_over": true, "match_result": {"winner_team": 2}}).contains("команда 2"), "menu reports the winning team after victory")
	var overlay := HUDModalOverlay.new()
	overlay.set_named_saves([{"path": "user://saves/named/slot_a.json", "slot_name": "Рим", "tick": 42, "saved_at_unix": 0}])
	assert_true(overlay.named_load_options.item_count == 1 and not overlay.named_load_button.disabled, "menu exposes available named save metadata")
	overlay.set_snapshot({"player_state": {"status": "defeated"}})
	overlay.show_menu()
	assert_true(overlay.match_status_label.text.contains("наблюдателя"), "open menu displays live spectator status")
	overlay.set_named_saves([])
	assert_true(overlay.named_load_button.disabled, "named load is unavailable when there are no slots")
	overlay.free()
	if failures.is_empty():
		print("P08 match instruction summary tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
