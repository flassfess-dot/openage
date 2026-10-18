extends SceneTree
const Profile := preload("res://scripts/ai_observation_profile.gd")
const World := preload("res://scripts/simulation_world.gd")
class Source extends RefCounted:
	var queries := 0
	var lookups := 0
	var entity: Dictionary = {}
	var definition := {"health":40.0,"speed":1.25,"combat":{"attacks":[{"type_id":4,"amount":3.0}],"armors":[{"type_id":4,"amount":1.0}],"base_armor":1.0,"attack_period":2.0,"range_max":4.0}}
	func object_record_by_id(_id: int, _team: int) -> Dictionary:
		queries += 1
		return definition
	func find_unit(_id: int) -> Dictionary:
		lookups += 1
		return entity
	func find_building(_id: int) -> Dictionary:
		lookups += 1
		return entity
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	var kernel = ClassDB.instantiate("RoRReadModelKernel")
	if kernel == null or not kernel.has_method("owned_ai_actor_profile"):
		push_error("Current native actor profile kernel is required")
		quit(1)
		return
	var owner := Source.new()
	for index in range(48):
		owner.entity = {"attack_damage":float(index),"attack_period":0.5+float(index)/10.0,"attack_range":float(index%9),"speed":float(index%7)/3.0,"max_hp":float(20+index),"combat_enabled":index%2==0,"carried_amount":float(index)/2.0,"carried_resource_type_id":index%4,"gather_stage":"returning" if index%3==0 else "harvesting","components":{"combat":{"attacks":[{"type_id":3,"amount":0.0},{"type_id":4,"amount":float(index)}],"armors":[{"type_id":3,"amount":float(index)/4.0}],"base_armor":float(index%5)},"cargo":{"enabled":index%4==0}}}
		var row := {"id":17,"team":1,"source_unit_id":123,"entity_type":"unit" if index%2==0 else "building"}
		Profile.native_actor_enabled = false
		var expected := Profile.actor(owner,row,1)
		var queries := owner.queries
		Profile.native_actor_enabled = true
		var actual := Profile.actor(owner,row,1)
		check(actual == expected,"owned profile differs at case %d"%index)
		check(owner.queries == queries,"normalized owned actor does not reread the source catalog")
		actual["attacks"][0]["amount"] = -999.0
		check(owner.entity["components"]["combat"]["attacks"][0]["amount"] == 0.0,"profile attacks are detached from live actor")
		row["team"] = 2
		var lookups := owner.lookups
		var foreign := Profile.actor(owner,row,1)
		check(foreign == Profile.from_record(owner.definition,row),"foreign actor uses only its legal row and public definition")
		check(owner.lookups == lookups,"foreign actor never looks up hidden live data")
	for field in ["attack_damage","attack_period","attack_range","speed","max_hp","combat_enabled"]:
		var incomplete := owner.entity.duplicate(true)
		incomplete.erase(field)
		check(kernel.owned_ai_actor_profile(incomplete).is_empty(),"missing runtime field requires the reference path: %s"%field)
	owner.entity.erase("attack_damage")
	var row := {"id":17,"team":1,"source_unit_id":123,"entity_type":"unit"}
	Profile.native_actor_enabled = false
	var fallback := Profile.actor(owner,row,1)
	Profile.native_actor_enabled = true
	check(Profile.actor(owner,row,1) == fallback,"incomplete compatibility actor preserves source defaults")
	var world := World.new(Vector2i(16,16))
	var unit: Dictionary = world.add_unit(1,"clubman",Vector2(4.5,4.5),false)
	check(not kernel.owned_ai_actor_profile(unit).is_empty(),"actual normalized world actors use the native path")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Native owned AI actor profiles: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
