class_name RoRWorkerRoleSystem
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const CombatRules := preload("res://scripts/combat_rules.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func profile_for_resource(worker: Dictionary, resource: Dictionary) -> Dictionary:
	var worker_runtime: Dictionary = world.data_repository.runtime_metadata(String(worker.get("kind", "")))
	var resource_runtime: Dictionary = world.data_repository.runtime_metadata(String(resource.get("kind", "")))
	var named_profile := String(resource_runtime.get("worker_profile", ""))
	if not named_profile.is_empty():
		var task_profile: Dictionary = worker_runtime.get("worker_task_profiles", {}).get(named_profile, {})
		if not task_profile.is_empty():
			return task_profile.duplicate(true)
	return profile_for_resource_type(worker, int(resource.get("resource_type_id", -1)))


func profile_for_resource_type(worker: Dictionary, resource_type_id: int) -> Dictionary:
	var worker_runtime: Dictionary = world.data_repository.runtime_metadata(String(worker.get("kind", "")))
	return worker_runtime.get("worker_resource_profiles", {}).get(String.num_int64(resource_type_id), {}).duplicate(true)


func profile_for_task(worker: Dictionary, task_name: String) -> Dictionary:
	var worker_runtime: Dictionary = world.data_repository.runtime_metadata(String(worker.get("kind", "")))
	return worker_runtime.get("worker_task_profiles", {}).get(task_name, {}).duplicate(true)


func profile_for_hunt(worker: Dictionary, target: Dictionary) -> Dictionary:
	var target_runtime: Dictionary = world.data_repository.runtime_metadata(String(target.get("kind", "")))
	var profile_name := String(target_runtime.get("worker_profile", "hunt"))
	return world.data_repository.runtime_metadata(String(worker.get("kind", ""))).get("worker_task_profiles", {}).get(profile_name, {}).duplicate(true)


func apply(worker: Dictionary, profile: Dictionary, combat_role: bool = false) -> bool:
	if profile.is_empty():
		clear(worker)
		return false
	clear(worker)
	var role_source_id := int(profile.get("role_source_unit_id", -1))
	var role_source: Dictionary = world.object_record_by_id(role_source_id, int(worker.get("team", 0))) if role_source_id >= 0 else {}
	if not role_source.is_empty():
		_apply_task_source(worker, role_source)
	worker["worker_role_source_unit_id"] = role_source_id
	worker["worker_role_name"] = String(profile.get("role_name", ""))
	worker["worker_role_profile"] = profile.duplicate(true)
	worker["presentation_state_overrides"] = _presentation_overrides(profile)
	var identity: Dictionary = worker.get("components", {}).get("identity", {})
	identity["task_source_unit_id"] = role_source_id
	identity["task_source_key"] = String(role_source.get("key", ""))
	if combat_role and not role_source.is_empty():
		_apply_combat_source(worker, role_source)
	return true


func clear(worker: Dictionary) -> void:
	if worker.has("_worker_base_combat"):
		var backup: Dictionary = worker["_worker_base_combat"]
		for field in ["attack_damage", "attack_period", "attack_range_min", "attack_range", "blast_range", "projectile_id", "combat_enabled", "stance", "acquisition_range", "chase_range"]:
			if backup.has(field):
				worker[field] = backup[field]
		worker.get("components", {})["combat"] = backup.get("component", {}).duplicate(true)
		worker.erase("_worker_base_combat")
	if worker.has("_worker_base_task"):
		var task_backup: Dictionary = worker["_worker_base_task"]
		worker["gather_interval"] = task_backup.get("gather_interval", worker.get("gather_interval", 1.0))
		worker["carry_capacity"] = task_backup.get("carry_capacity", worker.get("carry_capacity", 0.0))
		var components: Dictionary = worker.get("components", {})
		components["worker"] = task_backup.get("worker_component", {}).duplicate(true)
		components["resource_carrier"] = task_backup.get("carrier_component", {}).duplicate(true)
		worker.erase("_worker_base_task")
	worker["worker_role_source_unit_id"] = -1
	worker["worker_role_name"] = ""
	worker["worker_role_profile"] = {}
	worker["presentation_state_overrides"] = {}
	var identity: Dictionary = worker.get("components", {}).get("identity", {})
	identity.erase("task_source_unit_id")
	identity.erase("task_source_key")


func presentation_state(unit: Dictionary, default_state: String) -> String:
	var overrides: Dictionary = unit.get("presentation_state_overrides", {})
	return String(overrides.get(String(unit.get("anim_state", AnimationController.IDLE)), default_state))


func _presentation_overrides(profile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var idle_state := String(profile.get("idle_state", ""))
	var move_state := String(profile.get("move_state", ""))
	var attack_state := String(profile.get("attack_state", ""))
	var work_state := String(profile.get("work_state", ""))
	var carry_state := String(profile.get("carry_state", ""))
	var build_state := String(profile.get("build_state", ""))
	var repair_state := String(profile.get("repair_state", ""))
	var death_state := String(profile.get("death_state", ""))
	var corpse_state := String(profile.get("corpse_state", ""))
	if not idle_state.is_empty(): result[AnimationController.IDLE] = idle_state
	if not move_state.is_empty(): result[AnimationController.MOVE] = move_state
	if not attack_state.is_empty():
		result[AnimationController.ATTACK_WINDUP] = attack_state
		result[AnimationController.ATTACK_RECOVER] = attack_state
	if not work_state.is_empty(): result[AnimationController.GATHER] = work_state
	if not carry_state.is_empty(): result[AnimationController.CARRY] = carry_state
	if not build_state.is_empty(): result[AnimationController.BUILD] = build_state
	if not repair_state.is_empty(): result[AnimationController.REPAIR] = repair_state
	if not death_state.is_empty(): result[AnimationController.DIE] = death_state
	if not corpse_state.is_empty(): result[AnimationController.DECAY] = corpse_state
	return result


func _apply_task_source(worker: Dictionary, source: Dictionary) -> void:
	var components: Dictionary = worker.get("components", {})
	var worker_component: Dictionary = components.get("worker", {})
	var carrier_component: Dictionary = components.get("resource_carrier", {})
	worker["_worker_base_task"] = {
		"gather_interval": worker.get("gather_interval", 1.0),
		"carry_capacity": worker.get("carry_capacity", 0.0),
		"worker_component": worker_component.duplicate(true),
		"carrier_component": carrier_component.duplicate(true),
	}
	var role_source_id := int(source.get("unit_id", -1))
	var work_rate := maxf(0.01, float(source.get("work_rate", 1.0)))
	var capacity := maxf(0.0, float(source.get("resources", {}).get("capacity", 0.0)))
	for command_value in world.technology_system.persistent_entity_effects(int(worker.get("team", 0))):
		var command: Dictionary = command_value
		if not _effect_matches_source(command, source, role_source_id):
			continue
		var raw_type := int(command.get("type_id", -1))
		var effect_type := raw_type % 10 if raw_type >= 10 and raw_type < 30 else raw_type
		match int(command.get("attr_c", -1)):
			13: work_rate = maxf(0.01, _apply_effect_operator(work_rate, effect_type, float(command.get("attr_d", 0.0))))
			14: capacity = maxf(0.0, _apply_effect_operator(capacity, effect_type, float(command.get("attr_d", 0.0))))
	worker["gather_interval"] = 1.0 / work_rate
	worker["carry_capacity"] = capacity
	worker_component["work_rate"] = work_rate
	worker_component["commands"] = source.get("commands", []).duplicate(true)
	worker_component["task_group"] = int(source.get("links", {}).get("task_group", 0))
	worker_component["drop_site_ids"] = source.get("resources", {}).get("drop_site_ids", []).duplicate()
	carrier_component["capacity"] = capacity


func _effect_matches_source(command: Dictionary, source: Dictionary, source_id: int) -> bool:
	var unit_id := int(command.get("attr_a", -1))
	if unit_id >= 0:
		return unit_id == source_id
	var class_id := int(command.get("attr_b", -1))
	return class_id >= 0 and int(source.get("unit_class", -2)) == class_id


func _apply_effect_operator(current: float, effect_type: int, value: float) -> float:
	match effect_type:
		0: return value
		4: return current + value
		5: return current * value
		_: return current


func _apply_combat_source(worker: Dictionary, source: Dictionary) -> void:
	if source.is_empty():
		return
	var component: Dictionary = worker.get("components", {}).get("combat", {})
	worker["_worker_base_combat"] = {
		"attack_damage": worker.get("attack_damage", 0.0),
		"attack_period": worker.get("attack_period", 0.0),
		"attack_range_min": worker.get("attack_range_min", 0.0),
		"attack_range": worker.get("attack_range", 0.0),
		"blast_range": worker.get("blast_range", 0.0),
		"projectile_id": worker.get("projectile_id", -1),
		"combat_enabled": worker.get("combat_enabled", false),
		"stance": worker.get("stance", "passive"),
		"acquisition_range": worker.get("acquisition_range", 0.0),
		"chase_range": worker.get("chase_range", 0.0),
		"component": component.duplicate(true),
	}
	var source_combat: Dictionary = source.get("combat", {})
	var attacks: Array = source_combat.get("attacks", []).duplicate(true)
	worker["attack_damage"] = CombatRules.primary_attack_damage(attacks)
	worker["attack_period"] = float(source_combat.get("attack_period", 0.0))
	worker["attack_range_min"] = float(source_combat.get("range_min", 0.0))
	worker["attack_range"] = float(source_combat.get("range_max", 0.0))
	worker["blast_range"] = float(source_combat.get("blast_range", 0.0))
	worker["projectile_id"] = int(source_combat.get("projectile_id", -1))
	worker["combat_enabled"] = not attacks.is_empty()
	component["attacks"] = attacks
	component["armors"] = source_combat.get("armors", []).duplicate(true)
	component["attack_period"] = worker["attack_period"]
	component["range_min"] = worker["attack_range_min"]
	component["range_max"] = worker["attack_range"]
	component["blast_range"] = worker["blast_range"]
	component["accuracy"] = int(source_combat.get("accuracy", 0))
	component["projectile_id"] = worker["projectile_id"]
	component["frame_delay"] = int(source_combat.get("frame_delay", 0))
	component["weapon_offset"] = source_combat.get("weapon_offset", [0.0, 0.0, 0.0]).duplicate()
