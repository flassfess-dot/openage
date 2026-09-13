extends SceneTree

const GameController := preload("res://scripts/game_controller.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MatchRegistry := preload("res://scripts/match_registry.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const ScenarioLedger := preload("res://scripts/source_ai_scenario_ledger.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load()
	var missions: Array = []
	var errors: Array[String] = []
	for entry_value in MatchRegistry.entries():
		var entry: Dictionary = entry_value
		if not String(entry.get("id", "")).begins_with("campaign_"):
			continue
		var definition := MatchDefinition.load_json(String(entry.get("path", "")))
		var map_data := MapGenerator.generate(definition)
		var world := SimulationWorld.new(map_data["size"])
		world.set_gamespec(catalog.gamespec_data)
		world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		MatchBootstrap.apply(world, definition, map_data)
		var result := ScenarioLedger.probe(world, GameController.new(world), definition)
		for error in ScenarioLedger.validate_probe(result):
			errors.append("%s:%s" % [String(definition.get("id", "")), error])
		missions.append(ScenarioLedger.stable_projection(result))
		print("AI_SCENARIO %s profiles=%d commands=%d accepted=%d rejected=%d snapshot=%dms plan=%dms" % [
			String(result.get("match_id", "")),
			int(result.get("profile_count", 0)),
			int(result.get("issued_command_count", 0)),
			int(result.get("accepted_command_count", 0)),
			int(result.get("rejected_command_count", 0)),
			int(result.get("snapshot_milliseconds", 0)),
			int(result.get("planning_milliseconds", 0)),
		])
	var ledger := {
		"schema_version": 1,
		"status": "integrated_runtime_probe",
		"tick": 1,
		"mission_count": missions.size(),
		"missions": missions,
		"known_parity_gaps": ["source workforce", "source targeting", "DEFAULT inheritance", "Random", "strategic numbers 71/72/76"],
	}
	print("AI_SCENARIO_LEDGER_BEGIN")
	print(JSON.stringify(ledger, "  "))
	print("AI_SCENARIO_LEDGER_END")
	if errors.is_empty():
		quit(0)
		return
	for error in errors:
		push_error(error)
	quit(1)
