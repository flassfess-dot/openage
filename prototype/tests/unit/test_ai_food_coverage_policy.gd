extends SceneTree
const Economy := preload("res://scripts/ai_adaptive_economy.gd")
const Strategy := preload("res://scripts/ai_strategy_state.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var units: Array = []
	for i in range(20): units.append({"id": i+1, "team": 1, "hp": 25, "movement_domain": "land", "resource_id": 2, "components": {"worker": {"enabled": true}}})
	var buildings: Array = [{"id": 100, "team": 1, "hp": 100, "kind": "town_center", "pos": Vector2(10,10), "ai_drop_site": true}]
	var resources: Array = [{"id": 1, "resource_type_id": 0, "amount": 1000, "pos": Vector2(11,10), "allowed_gatherer_domains": ["land"]}, {"id": 2, "resource_type_id": 1, "amount": 9999, "pos": Vector2(30,30), "allowed_gatherer_domains": ["land"]}, {"id": 3, "resource_type_id": 0, "amount": 9999, "pos": Vector2(11,10), "allowed_gatherer_domains": ["water"]}, {"id": 4, "resource_type_id": 0, "amount": 9999, "pos": Vector2(90,90), "allowed_gatherer_domains": ["land"]}]
	var snapshot := {"tick": 6000, "units": units, "buildings": buildings, "resources": resources, "player_state": {"age": 102, "population_limit": 64}}
	var policy := {"maximum_farms": 12, "construction_priorities": [], "building_limits": {"storage_pit": 1, "granary": 1}}
	var state := Strategy.new()
	var first := Economy.policy_for(snapshot, 1, policy, state)
	check(first["building_limits"]["farm"] == 9, "distant food, wood and water-only fish do not cover land-worker food needs")
	check(first["building_limits"]["storage_pit"] == 2, "non-food gatherers still contribute delivery distance")
	resources.append({"id": 5, "resource_type_id": 0, "amount": 2000, "pos": Vector2(12,10), "allowed_gatherer_domains": ["land"]})
	check(Economy.policy_for(snapshot, 1, policy, state)["building_limits"]["farm"] == 0, "enough nearby usable food retains the old farm decision")
	for failure in failures: push_error(failure)
	print("AI food coverage: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
