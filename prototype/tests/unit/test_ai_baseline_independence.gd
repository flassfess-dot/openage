extends SceneTree
const Original := preload("res://scripts/ai_player.gd")
const Frozen := preload("res://ai_baselines/v1/scripts/ai_player.gd")
const Policy := preload("res://scripts/skirmish_ai_policy.gd")
const Codec := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var evidence: Array = []
	for index in range(24):
		var policy := Policy.resolve("random_map_balanced", "standard")
		policy["algorithm_version"] = "legacy_adaptive_v1"
		var definition := {"team": 1, "ai": policy}
		var original := Original.new(definition)
		var frozen := Frozen.new(definition)
		var snapshot := fixture(index)
		var before := original.canonical_state()
		var commands := original.collect_commands(snapshot, index * 20 + 1)
		var reference := frozen.collect_commands(snapshot.duplicate(true), index * 20 + 1)
		check(records(commands) == records(reference), "frozen commands differ at " + str(index))
		check(original.canonical_state() == frozen.canonical_state(), "frozen state differs at " + str(index))
		var replayed := Frozen.new(definition)
		check(replayed.restore_state(before), "restore baseline input")
		check(records(replayed.collect_commands(snapshot.duplicate(true), index * 20 + 1)) == records(reference), "repeated baseline differs")
		evidence.append({"case": index, "input": hash(var_to_bytes(snapshot)), "commands": hash(var_to_bytes(records(reference))), "state": hash(var_to_bytes(frozen.canonical_state()))})
	var output := FileAccess.open("res://qa/ai-competitive/competitive-20261030/baseline_equivalence.json", FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify({"cases": evidence, "failures": failures}, "\t"))
	for failure in failures: push_error(failure)
	print("Frozen baseline equivalence: ", evidence.size(), " inputs, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func fixture(index: int) -> Dictionary:
	var points: Array[Vector2] = [Vector2(3.5,3.5),Vector2(4.5,3.5),Vector2(6.5,3.5),Vector2(9.5,3.5)]
	var result := {"tick": index*20, "observer_team":1,"map_size":Vector2i(24,24),"units":[],"buildings":[],"resources":[],"navigation":{"land":points,"water":[],"reachable":{"land":points,"water":[]},"reachable_frontier":{"land":points,"water":[]}},"build_sites":{},"player_state":{"status":"active","age":100+index%4,"food":index*37,"wood":index*19,"stone":0,"gold":index*7,"population":index%5,"population_points":index%5*2,"population_cap":20,"population_limit":50,"allies":[1],"relations":{2:"enemy"}}}
	result["buildings"].append({"id":1,"team":1,"kind":"town_center","entity_type":"building","state":"complete","hp":600.0,"max_hp":600.0,"pos":Vector2(3.5,3.5),"production_queue":[],"command_options":{"train":[],"research":[]},"ai_drop_site":true})
	for worker in range(index%8):
		result["units"].append({"id":worker+2,"team":1,"kind":"villager","pos":Vector2(4.5,3.5),"hp":25.0,"task":"idle","movement_domain":"land","components":{"worker":{"enabled":true}},"command_options":{"build":[]}})
	result["resources"].append({"id":100,"pos":Vector2(6.5,3.5),"amount":1000,"resource_type_id":index%4,"allowed_gatherer_domains":["land"]})
	if index%2:
		result["units"].append({"id":200,"team":2,"kind":"clubman","pos":Vector2(9.5,3.5),"hp":40.0,"combat_enabled":true,"movement_domain":"land","target_domains":["land"],"ai_profile":{"enabled":true,"damage":4.0,"period":2.0,"range":0.0,"max_hp":40.0}})
	return result

func records(commands: Array) -> Array:
	var result: Array = []
	var codec := Codec.new()
	for command in commands: result.append({"type":command.command_type(),"ids":command.unit_ids,"params":codec.encode_variant(command.params,false),"tick":command.tick})
	return result

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
