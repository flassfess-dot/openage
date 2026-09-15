class_name RoRConversionSystem
extends RefCounted

const CombatRules := preload("res://scripts/combat_rules.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")

const MONOTHEISM_TECHNOLOGY_ID: int = 19
const BASE_RECHARGE_RATE: float = 2.0
const RESISTANT_TARGET_MULTIPLIER: float = 0.25
const MARTYRDOM_RESOURCE_ID: int = 57

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func component(entity: Dictionary) -> Dictionary:
	return entity.get("components", {}).get("conversion", {})


func is_converter(entity: Dictionary) -> bool:
	return bool(component(entity).get("enabled", false))


func validate_target(converter: Dictionary, target: Variant, require_faith: bool = true) -> String:
	if not is_converter(converter):
		return "not_a_converter"
	if float(converter.get("hp", 0.0)) <= 0.0:
		return "converter_unavailable"
	var conversion := component(converter)
	if require_faith and float(conversion.get("faith", 0.0)) + 0.0001 < float(conversion.get("max_faith", 100.0)):
		return "faith_depleted"
	if not target is Dictionary or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_target"
	var converter_team := int(converter.get("team", 0))
	var target_team := int(target.get("team", 0))
	if target_team <= 0:
		return "unconvertible_gaia"
	if world.are_teams_allied(converter_team, target_team):
		return "friendly_target"
	var source_unit_id := int(target.get("source_unit_id", -1))
	if source_unit_id in [109, 276] or world.entity_has_behavior_tag(target, "wonder"):
		return "conversion_immune"
	var target_is_building := world.find_building(int(target.get("id", -1))) != null
	if (target_is_building or is_converter(target)) and not world.technology_system.is_researched(converter_team, MONOTHEISM_TECHNOLOGY_ID):
		return "monotheism_required"
	return ""


func range_for(converter: Dictionary, target: Dictionary) -> float:
	if world.find_building(int(target.get("id", -1))) != null:
		return maxf(0.0, float(component(converter).get("building_range", 1.0)))
	return maxf(0.0, float(converter.get("attack_range", 0.0)))


func is_in_range(converter: Dictionary, target: Dictionary) -> bool:
	return CombatRules.edge_distance(converter, target) <= range_for(converter, target) + 0.0001


func resistance_multiplier(converter: Dictionary, target: Dictionary) -> float:
	if world.entity_has_behavior_tag(target, "chariot") or String(target.get("movement_domain", "land")) == "water" or world.entity_has_behavior_tag(target, "naval"):
		return float(component(converter).get("resistant_target_multiplier", RESISTANT_TARGET_MULTIPLIER))
	return 1.0


func success_chance_for(converter: Dictionary, target: Dictionary) -> float:
	var conversion := component(converter)
	return clampf(float(conversion.get("base_success_chance", 0.30)) * float(conversion.get("chance_multiplier", 1.0)) * resistance_multiplier(converter, target), 0.0, 1.0)


func recharge_rate_for(converter: Dictionary) -> float:
	var team := int(converter.get("team", 0))
	return world.technology_system.rule_resource_value(team, 35, BASE_RECHARGE_RATE)


func advance_faith(converter: Dictionary, delta: float) -> void:
	if not is_converter(converter):
		return
	var conversion := component(converter)
	var rate := recharge_rate_for(converter)
	conversion["recharge_rate"] = rate
	if bool(conversion.get("active", false)):
		return
	var maximum := float(conversion.get("max_faith", 100.0))
	conversion["faith"] = minf(maximum, float(conversion.get("faith", 0.0)) + maxf(0.0, delta) * rate)


func begin(converter: Dictionary, target: Dictionary) -> String:
	var rejection := validate_target(converter, target)
	if not rejection.is_empty():
		return rejection
	var conversion := component(converter)
	conversion["active"] = true
	conversion["target_id"] = int(target.get("id", -1))
	conversion["chant_elapsed"] = 0.0
	conversion["chants"] = 0
	world.emit_domain_event("conversion_started", {
		"converter_id": int(converter.get("id", -1)),
		"target_id": int(target.get("id", -1)),
		"team": int(converter.get("team", 0)),
	})
	return ""


func advance_conversion(converter: Dictionary, target: Dictionary, delta: float) -> String:
	var rejection := validate_target(converter, target, false)
	if not rejection.is_empty():
		return rejection
	var conversion := component(converter)
	if not bool(conversion.get("active", false)) or int(conversion.get("target_id", -1)) != int(target.get("id", -1)):
		return "conversion_not_active"
	conversion["chant_elapsed"] = float(conversion.get("chant_elapsed", 0.0)) + maxf(0.0, delta)
	var interval := maxf(0.1, float(conversion.get("chant_interval", 1.5)))
	while float(conversion.get("chant_elapsed", 0.0)) + 0.0001 >= interval:
		conversion["chant_elapsed"] = float(conversion["chant_elapsed"]) - interval
		conversion["chants"] = int(conversion.get("chants", 0)) + 1
		var chant_count := int(conversion["chants"])
		world.emit_domain_event("conversion_chant", {
			"converter_id": int(converter.get("id", -1)),
			"target_id": int(target.get("id", -1)),
			"chant": chant_count,
		})
		var minimum := maxi(1, int(conversion.get("min_chants", 3)))
		if chant_count < minimum:
			continue
		var maximum := maxi(minimum, int(conversion.get("max_chants", 100)))
		var chance := success_chance_for(converter, target)
		if chant_count < maximum and world.simulation_rng.randf() >= chance:
			continue
		var old_team := int(target.get("team", 0))
		var new_team := int(converter.get("team", 0))
		if not world.transfer_entity_ownership(target, new_team, int(converter.get("id", -1))):
			return "ownership_transfer_failed"
		conversion["faith"] = 0.0
		complete(converter)
		world.emit_domain_event("conversion_succeeded", {
			"converter_id": int(converter.get("id", -1)),
			"target_id": int(target.get("id", -1)),
			"old_team": old_team,
			"new_team": new_team,
			"chants": chant_count,
			"chance": chance,
		})
		return "success"
	return "pending"


func complete(converter: Dictionary) -> void:
	var conversion := component(converter)
	conversion["active"] = false
	conversion["target_id"] = -1
	conversion["chant_elapsed"] = 0.0
	conversion["chants"] = 0


func cancel(converter: Dictionary, reason: String = "cancelled") -> void:
	if not is_converter(converter):
		return
	var conversion := component(converter)
	var was_active := bool(conversion.get("active", false))
	var target_id := int(conversion.get("target_id", -1))
	complete(converter)
	if was_active:
		world.emit_domain_event("conversion_cancelled", {
			"converter_id": int(converter.get("id", -1)),
			"target_id": target_id,
			"reason": reason,
		})


func validate_martyrdom(converter: Dictionary) -> String:
	if not is_converter(converter) or float(converter.get("hp", 0.0)) <= 0.0:
		return "no_eligible_martyr"
	if world.get_resource_amount(int(converter.get("team", 0)), MARTYRDOM_RESOURCE_ID) <= 0:
		return "martyrdom_not_researched"
	var conversion := component(converter)
	if String(converter.get("task", "")) != "convert" or not bool(conversion.get("active", false)):
		return "martyrdom_requires_conversion"
	if OrderPipeline.phase(converter) != OrderPipeline.PERFORM_ACTION:
		return "martyrdom_conversion_not_started"
	var target = world.find_unit(int(conversion.get("target_id", -1)))
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_martyrdom_target"
	if is_converter(target):
		return "martyrdom_priest_immune"
	var rejection := validate_target(converter, target, false)
	if not rejection.is_empty():
		return rejection
	if not is_in_range(converter, target):
		return "martyrdom_conversion_not_started"
	return ""


func perform_martyrdom(converter: Dictionary) -> String:
	var rejection := validate_martyrdom(converter)
	if not rejection.is_empty():
		return rejection
	var conversion := component(converter)
	var target: Dictionary = world.find_unit(int(conversion.get("target_id", -1)))
	var converter_id := int(converter.get("id", -1))
	var old_team := int(target.get("team", 0))
	var new_team := int(converter.get("team", 0))
	if not world.transfer_entity_ownership(target, new_team, converter_id):
		return "ownership_transfer_failed"
	complete(converter)
	world.emit_domain_event("martyrdom_succeeded", {
		"converter_id": converter_id,
		"target_id": int(target.get("id", -1)),
		"old_team": old_team,
		"new_team": new_team,
	})
	converter["hp"] = 0.0
	converter.get("components", {}).get("health", {})["current"] = 0.0
	world.begin_death(converter)
	return ""
