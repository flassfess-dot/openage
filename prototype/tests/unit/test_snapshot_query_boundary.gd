extends SceneTree

const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Store := preload("res://scripts/ai_observation_store.gd")
var failures: Array[String] = []

class CountingWorld extends "res://scripts/simulation_world.gd":
	var query_count := 0
	func get_build_options(_team: int) -> Array:
		query_count += 1
		return [{"kind": "house", "accepted": true}]
	func get_build_options_for_kinds(_team: int, _kinds: Array) -> Array:
		query_count += 1
		return [{"kind": "house", "accepted": true}]
	func get_unit_production_options(_id: int, _team: int) -> Array:
		query_count += 1
		return []
	func get_research_options(_id: int, _team: int) -> Array:
		query_count += 1
		return []
	func get_mixed_domain_build_sites(_team: int, _maximum: int = 4) -> Dictionary:
		query_count += 1
		return {"house": [Vector2(8.5, 8.5)]}
	func reachable_builder_ids(_building: Dictionary) -> Array[int]:
		query_count += 1
		return []

func _initialize() -> void:
	var world := CountingWorld.new(Vector2i(16, 16))
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(4, 4), false)
	world.add_building(80, "town_center", Vector2(6, 6))
	var options := {"compact_entities": true, "include_navigation": true, "include_build_sites": true, "include_worker_command_options": true}
	var bare := Snapshot.presentation(world, 10, 1, options)
	check(world.query_count == 0, "reading a snapshot never runs command or placement queries")
	check(bare["navigation"].is_empty() and bare["build_sites"].is_empty(), "navigation/placement require an explicit query stage")
	check(not bare["units"][0].has("command_options"), "factual projection has no computed command availability")
	check(world.ai_navigation_knowledge.entries.is_empty(), "plain snapshot does not prepare map navigation")
	var store := Store.new()
	var knowledge := store.observe(world, 10, 1, options)
	check(world.query_count == 0, "retained AI observations also only read factual data")
	var enriched := Snapshot.with_queries(world, 10, 1, {"include_navigation": false, "include_build_sites": false, "command_option_entity_ids": [int(worker["id"])]})
	check(world.query_count == 1, "explicit selection queries touch only the selected worker")
	check(enriched["units"][0].get("command_options", {}).get("build", []).size() == 1, "explicit query exposes build availability")
	check(not worker.has("command_options") and not bare["units"][0].has("command_options") and not knowledge["units"][0].has("command_options"), "query enrichment cannot modify live or retained factual rows")
	var before := world.query_count
	Snapshot.with_queries(world, 11, 1, {"include_navigation": false, "include_build_sites": false, "command_option_entity_ids": []})
	check(world.query_count == before, "empty selection causes no availability queries")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
