class_name RoRSimulationCombatSystem
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const CombatRules := preload("res://scripts/combat_rules.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const FormationCombat := preload("res://scripts/formation_combat.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const ProjectileMotion := preload("res://scripts/projectile_motion.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null
var projectiles: Array = []
var resolved_projectiles: Array = []
var ground_target_buffer := {
	"id": -1,
	"pos": Vector2.ZERO,
	"hp": 1.0,
	"footprint_radius": 0.0,
	"elevation": 0.0,
	"attack_ground": true,
}


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func reset() -> void:
	projectiles.clear()
	resolved_projectiles.clear()


func can_attack_ground(unit: Dictionary) -> bool:
	var combat: Dictionary = unit.get("components", {}).get("combat", {})
	return bool(unit.get("combat_enabled", false)) and int(combat.get("projectile_id", unit.get("projectile_id", -1))) >= 0 and float(combat.get("blast_range", unit.get("blast_range", 0.0))) > 0.0


func attack_ground_target(position: Vector2) -> Dictionary:
	return _ground_target(position).duplicate()


func _ground_target(position: Vector2) -> Dictionary:
	ground_target_buffer["pos"] = position
	ground_target_buffer["elevation"] = world.elevation_at(position)
	return ground_target_buffer


func assign_command_attack_ground(selected: Array, target: Vector2) -> bool:
	var ground_target := _ground_target(target)
	var resolved_count := 0
	for unit in selected:
		if not can_attack_ground(unit):
			continue
		world.conversion_system.cancel(unit, "new_order")
		world.healing_system.cancel(unit, "new_order")
		world.release_resource_approach_slot(unit)
		world.release_building_approach_slot(unit)
		unit["gather_stage"] = "none"
		unit["resource_id"] = -1
		unit["target_building_id"] = -1
		unit["task"] = "attack_ground"
		unit["target_id"] = -1
		world.clear_combat_intent(unit)
		unit["combat_destination"] = FormationCombat.destination(unit, ground_target)
		unit["retaliation_target_id"] = -1
		OrderPipeline.begin(unit, "attack_ground", -1, target, true)
		if CombatRules.is_in_range(unit, ground_target):
			world.release_unit_destination(unit)
			OrderPipeline.transition(unit, OrderPipeline.PLAN_PATH)
			OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
			resolved_count += 1
		elif world.assign_unit_destination(unit, Vector2(unit["combat_destination"])):
			resolved_count += 1
		else:
			world.halt_unit(unit, "no_path")
	return resolved_count > 0


func assign_command_attack(selected: Array, target_id: int, policy: Dictionary = {}) -> bool:
	var target: Variant = world.find_combat_target(target_id)
	if target == null or target["hp"] <= 0.0:
		return false
	var huntable: bool = world.entity_has_behavior_tag(target, "huntable")
	for candidate in selected:
		if not world.entity_is_worker(candidate):
			continue
		if huntable:
			world.worker_role_system.apply(candidate, world.worker_role_system.profile_for_hunt(candidate, target), true)
			candidate["pending_hunt_target_id"] = target_id
			world.configure_unit_combat_awareness(candidate)
		else:
			world.worker_role_system.clear(candidate)
			candidate["pending_hunt_target_id"] = -1
	var mobile_attackers: Array = selected.filter(func(entity): return not world.entity_is_static(entity))
	if not mobile_attackers.is_empty():
		FormationCombat.assign_slots(mobile_attackers, target)
	var resolved_count := 0
	for unit in selected:
		var static_attacker: bool = world.entity_is_static(unit)
		if not static_attacker:
			world.conversion_system.cancel(unit, "new_order")
			world.healing_system.cancel(unit, "new_order")
		var autonomous := bool(policy.get("autonomous", false))
		var previous_task := String(unit.get("task", "idle"))
		if autonomous and previous_task != "attack" and previous_task in ["move", "attack_move"]:
			unit["combat_resume"] = {
				"task": previous_task,
				"destination": unit.get("destination", unit.get("pos", Vector2.ZERO)),
			}
		elif not autonomous:
			unit["combat_resume"] = {}
			unit["combat_pursuit"] = not huntable and not static_attacker
		world.release_resource_approach_slot(unit)
		world.release_building_approach_slot(unit)
		unit["gather_stage"] = "none"
		unit["resource_id"] = -1
		unit["target_building_id"] = -1
		world.destination_reservations.release(int(unit["id"]))
		unit["reserved_destination"] = null
		unit["task"] = "attack"
		unit["target_id"] = target_id
		unit["attack_autonomous"] = autonomous
		if int(unit.get("formation_group_id", -1)) >= 0:
			unit["formation_slot_mode"] = "released"
		unit["combat_leash_origin"] = Vector2(policy.get("leash_origin", unit.get("pos", Vector2.ZERO)))
		unit["chase_range"] = maxf(0.0, float(policy.get("chase_range", unit.get("chase_range", 0.0))))
		unit["retaliation_target_id"] = -1
		unit["diagnostic_reason"] = "target:%s" % String(policy.get("trigger", "explicit"))
		if static_attacker:
			unit["combat_destination"] = unit.get("pos", Vector2.ZERO)
		var target_direction: Vector2 = target["pos"] - unit["pos"]
		if target_direction.length_squared() > 0.0001:
			unit["action_facing"] = world.facing_for_vector(target_direction)
		OrderPipeline.begin(unit, "attack", target_id, target["pos"], true)
		if CombatRules.is_in_range(unit, target):
			OrderPipeline.transition(unit, OrderPipeline.PLAN_PATH)
			OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
			OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
			resolved_count += 1
		elif not static_attacker and world.assign_unit_destination(unit, unit["combat_destination"]):
			resolved_count += 1
		else:
			finish_combat(unit, "target_unreachable")
	if resolved_count > 0 and world.capture_domain_events:
		world.emit_domain_event("target_acquired", {
			"target_id": target_id,
			"unit_ids": selected.map(func(unit): return int(unit.get("id", -1))),
			"autonomous": bool(policy.get("autonomous", false)),
			"trigger": String(policy.get("trigger", "explicit")),
		})
	return resolved_count > 0


func finish_combat(unit: Dictionary, reason: String = "target_unavailable") -> void:
	var completed_target_id := int(unit.get("target_id", -1))
	var completed_target: Variant = world.find_combat_target(completed_target_id)
	var waiting_for_carcass: bool = world.entity_is_worker(unit) and int(unit.get("pending_hunt_target_id", -1)) == completed_target_id and completed_target != null and float(completed_target.get("hp", 0.0)) <= 0.0
	var resume: Dictionary = unit.get("combat_resume", {}).duplicate(true)
	OrderPipeline.complete(unit, reason)
	unit["diagnostic_reason"] = "combat_complete:%s" % reason
	if reason in ["target_became_allied", "target_unreachable"]:
		unit["combat_pursuit"] = false
	unit["target_id"] = -1
	unit["combat_role"] = ""
	unit["combat_slot_index"] = -1
	unit["combat_slot_count"] = 0
	unit["combat_destination"] = null
	unit["attack_autonomous"] = false
	unit["combat_resume"] = {}
	if world.entity_is_static(unit):
		unit["task"] = "idle"
		EntityComponents.sync_dynamic(unit)
		return
	if waiting_for_carcass:
		unit["task"] = "idle"
		world.stop_unit_motion(unit)
		return
	if world.entity_is_worker(unit):
		unit["pending_hunt_target_id"] = -1
		world.worker_role_system.clear(unit)
	if bool(unit.get("combat_pursuit", false)):
		unit["task"] = "idle"
		world.stop_unit_motion(unit)
		return
	var formation_home: Variant = unit.get("formation_home")
	if formation_home is Vector2 and int(unit.get("formation_group_id", -1)) >= 0:
		unit["task"] = "move"
		unit["formation_slot_mode"] = "soft"
		OrderPipeline.begin(unit, "move", -1, formation_home, false)
		if not world.assign_unit_destination(unit, formation_home):
			world.restore_formation_facing(unit)
	elif String(resume.get("task", "")) in ["move", "attack_move"] and resume.get("destination") is Vector2:
		var resume_task := String(resume["task"])
		var resume_destination: Vector2 = resume["destination"]
		unit["task"] = resume_task
		OrderPipeline.begin(unit, resume_task, -1, resume_destination, false)
		if not world.assign_unit_destination(unit, resume_destination):
			unit["task"] = "idle"
			OrderPipeline.complete(unit, "resume_unreachable")
	else:
		unit["task"] = "idle"
		world.stop_unit_motion(unit)
		world.restore_formation_facing(unit)


func release_finished_combat_reservations() -> void:
	for unit in world.unit_activity_registry.ordered_units():
		if String(unit.get("task", "")) != "attack":
			continue
		var target = world.find_combat_target(int(unit.get("target_id", -1)))
		if target == null or float(target.get("hp", 0.0)) <= 0.0:
			world.release_unit_destination(unit)


func advance_projectiles(context: Dictionary) -> void:
	update_projectiles(float(context.get("delta", 0.0)), int(context.get("player_team", 0)))


func advance_static_combatants(context: Dictionary) -> void:
	update_static_combatants(float(context.get("delta", 0.0)), int(context.get("player_team", 0)))


func update_static_combatants(delta: float, player_team: int) -> void:
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if float(building.get("hp", 0.0)) <= 0.0:
			world.begin_building_destruction(building)
			continue
		if String(building.get("state", "complete")) != "complete" or not bool(building.get("combat_enabled", false)):
			continue
		building["cooldown"] = maxf(0.0, float(building.get("cooldown", 0.0)) - delta)
		var animation_state := AnimationController.IDLE
		var attack_target: Variant = null
		if String(building.get("task", "idle")) == "attack":
			var target = world.find_combat_target(int(building.get("target_id", -1)))
			if target == null or float(target.get("hp", 0.0)) <= 0.0:
				world.finish_combat(building)
			elif world.are_teams_allied(int(building.get("team", 0)), int(target.get("team", 0))):
				world.finish_combat(building, "target_became_allied")
			elif bool(building.get("attack_autonomous", false)) and not world.is_entity_visible_to(int(building.get("team", 0)), target):
				world.finish_combat(building, "target_lost")
			elif not CombatRules.is_in_range(building, target):
				world.finish_combat(building, "stand_ground_range")
			else:
				if OrderPipeline.phase(building) == OrderPipeline.RECOVER and float(building.get("cooldown", 0.0)) <= 0.0:
					OrderPipeline.restart(building)
				world.face_unit_toward(building, Vector2(target.get("pos", building.get("pos", Vector2.ZERO))))
				if float(building.get("cooldown", 0.0)) <= 0.0:
					OrderPipeline.transition(building, OrderPipeline.FACE_TARGET)
					OrderPipeline.transition(building, OrderPipeline.PERFORM_ACTION)
					animation_state = AnimationController.ATTACK_WINDUP
					attack_target = target
				else:
					OrderPipeline.transition(building, OrderPipeline.RECOVER)
					animation_state = AnimationController.ATTACK_RECOVER
		var restart_attack_clip := animation_state == AnimationController.ATTACK_WINDUP and String(building.get("anim_state", "")) == AnimationController.ATTACK_RECOVER
		AnimationController.update(building, animation_state, delta, restart_attack_clip)
		if attack_target != null:
			apply_attack_frame_event(building, attack_target, player_team)
		EntityComponents.sync_dynamic(building)


func advance_unit_order(unit: Dictionary, delta: float, result: Dictionary) -> void:
	result["moving"] = false
	result["animation_state"] = AnimationController.IDLE
	result["attack_target"] = null
	if String(unit.get("task", "")) == "attack_ground":
		_advance_ground_attack_order(unit, delta, result)
	else:
		_advance_target_attack_order(unit, delta, result)


func _advance_ground_attack_order(unit: Dictionary, delta: float, result: Dictionary) -> void:
	var simulation_world = world
	var ground_position: Vector2 = OrderPipeline.current(unit).get("target_position", unit.get("pos", Vector2.ZERO))
	var ground_target := _ground_target(ground_position)
	if not can_attack_ground(unit):
		simulation_world.halt_unit(unit, "attack_ground_unavailable")
	elif not CombatRules.is_in_range(unit, ground_target):
		if String(unit.get("stance", "passive")) == "stand_ground":
			simulation_world.halt_unit(unit, "stand_ground_range")
		else:
			var ground_destination := FormationCombat.destination(unit, ground_target)
			unit["combat_destination"] = ground_destination
			simulation_world.ensure_navigation_destination(unit, ground_destination)
			if unit.get("path", []).is_empty():
				simulation_world.halt_unit(unit, "no_path")
			else:
				result["moving"] = simulation_world.movement_system.move_unit(unit, delta)
	else:
		simulation_world.movement_system.face_unit_toward(unit, ground_position)
		if float(unit.get("cooldown", 0.0)) <= 0.0:
			OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
			OrderPipeline.transition(unit, OrderPipeline.PERFORM_ACTION)
			result["animation_state"] = AnimationController.ATTACK_WINDUP
			result["attack_target"] = ground_target
		else:
			OrderPipeline.transition(unit, OrderPipeline.RECOVER)
			result["animation_state"] = AnimationController.ATTACK_RECOVER


func _advance_target_attack_order(unit: Dictionary, delta: float, result: Dictionary) -> void:
	var simulation_world = world
	var enemy = simulation_world.find_combat_target(int(unit.get("target_id", -1)))
	if enemy == null or float(enemy.get("hp", 0.0)) <= 0.0:
		simulation_world.finish_combat(unit)
	elif simulation_world.are_teams_allied(int(unit.get("team", 0)), int(enemy.get("team", 0))):
		simulation_world.finish_combat(unit, "target_became_allied")
	elif bool(unit.get("attack_autonomous", false)) and not simulation_world.is_entity_visible_to(int(unit.get("team", 0)), enemy):
		simulation_world.finish_combat(unit, "target_lost")
	elif not bool(unit.get("combat_pursuit", false)) and String(unit.get("stance", "passive")) == "stand_ground" and not CombatRules.is_in_range(unit, enemy):
		simulation_world.finish_combat(unit, "stand_ground_range")
	elif bool(unit.get("attack_autonomous", false)) and Vector2(unit.get("combat_leash_origin", unit.get("pos", Vector2.ZERO))).distance_to(Vector2(enemy.get("pos", Vector2.ZERO))) > float(unit.get("chase_range", 0.0)) + 0.0001:
		simulation_world.finish_combat(unit, "leash_exceeded")
	else:
		if OrderPipeline.phase(unit) == OrderPipeline.RECOVER and float(unit.get("cooldown", 0.0)) <= 0.0:
			OrderPipeline.restart(unit)
		var combat_destination := FormationCombat.destination(unit, enemy)
		unit["combat_destination"] = combat_destination
		var too_close := CombatRules.is_too_close(unit, enemy)
		if not CombatRules.is_in_range(unit, enemy) or too_close:
			simulation_world.ensure_navigation_destination(unit, combat_destination)
			result["moving"] = simulation_world.movement_system.move_unit(unit, delta)
		else:
			simulation_world.movement_system.face_unit_toward(unit, Vector2(enemy.get("pos", unit.get("pos", Vector2.ZERO))))
			if float(unit.get("cooldown", 0.0)) <= 0.0:
				OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
				OrderPipeline.transition(unit, OrderPipeline.PERFORM_ACTION)
				result["animation_state"] = AnimationController.ATTACK_WINDUP
				result["attack_target"] = enemy
			else:
				OrderPipeline.transition(unit, OrderPipeline.RECOVER)
				result["animation_state"] = AnimationController.ATTACK_RECOVER


func apply_attack_frame_event(unit: Dictionary, enemy: Dictionary, player_team: int) -> void:
	if enemy["hp"] <= 0.0:
		return
	var attack_spec: Dictionary = world.attack_animation_spec(unit)
	var event_name := "projectile_release_frame" if unit["projectile_id"] >= 0 else "damage_frame"
	var event_frame := int(attack_spec.get(event_name, 0))
	var frame_duration := maxf(0.001, float(attack_spec.get("frame_rate", 0.1)))
	if not AnimationController.event_reached(unit, event_name, event_frame, frame_duration):
		return
	var damage := 0.0
	# Payload dictionaries are built at the call site, so gate the hot combat
	# emissions on the capture flag instead of relying on the emit-time early-out.
	if world.capture_domain_events:
		world.emit_domain_event("attack", {
			"attacker_id": int(unit["id"]),
			"target_id": int(enemy["id"]),
			"ranged": int(unit.get("projectile_id", -1)) >= 0,
		})
	if int(unit.get("projectile_id", -1)) >= 0:
		spawn_projectile(unit, enemy)
	else:
		var combat: Dictionary = unit.get("components", {}).get("combat", {})
		var blast_range := maxf(0.0, float(combat.get("blast_range", unit.get("blast_range", 0.0))))
		var candidates: Array = world.query_combat_entities_near(Vector2(enemy["pos"]), blast_range) if blast_range > 0.0 else [enemy]
		var source_context: Dictionary = world.combat_source_context(unit)
		var friendly_fire := bool(combat.get("friendly_fire", false))
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value
			if float(candidate.get("hp", 0.0)) <= 0.0:
				continue
			if not friendly_fire and world.are_teams_allied(int(unit.get("team", 0)), int(candidate.get("team", 0))):
				continue
			var impact_damage := CombatRules.entity_damage(unit, candidate)
			_apply_impact_damage(candidate, impact_damage, source_context, -1, player_team)
			if int(candidate.get("id", -1)) == int(enemy.get("id", -2)):
				damage = impact_damage
	unit["cooldown"] = maxf(0.1, unit["attack_period"])
	OrderPipeline.transition(unit, OrderPipeline.RECOVER)
	unit["last_damage"] = damage


func spawn_projectile(attacker: Dictionary, target: Dictionary) -> Dictionary:
	var projectile_unit_id := int(attacker.get("projectile_id", -1))
	var projectile_source: Dictionary = world.object_record_by_id(projectile_unit_id, int(attacker.get("team", 0)))
	var projectile_entity_id: int = world.entity_id_sequence.next()
	var combat: Dictionary = attacker.get("components", {}).get("combat", {})
	var projectile_spec: Dictionary = projectile_source.get("projectile", {})
	var speed := maxf(0.001, float(projectile_source.get("speed", 8.0)))
	var accuracy := int(combat.get("accuracy", 100))
	var weapon_offset: Array = combat.get("weapon_offset", [0.0, 0.0, 0.0])
	var spawn := ProjectileMotion.spawn_position(attacker, target["pos"], weapon_offset)
	var ground_attack := bool(target.get("attack_ground", false))
	var predictive_aim := bool(projectile_spec.get("smart_mode", false)) or bool(combat.get("ballistics", false))
	var aim: Dictionary = {"position": Vector2(target["pos"]), "roll": 0, "accurate": true} if ground_attack else ProjectileMotion.aim_position(attacker, target, speed, predictive_aim, accuracy, projectile_entity_id)
	var destination: Vector2 = aim["position"]
	var launch_height := float(weapon_offset[2]) if weapon_offset.size() > 2 else 0.0
	var projectile_radius := 0.1
	var radius_values: Array = projectile_source.get("geometry", {}).get("radius", [])
	if not radius_values.is_empty():
		projectile_radius = maxf(float(radius_values[0]), float(radius_values[1]) if radius_values.size() > 1 else 0.0)
	var projectile := {
		"id": projectile_entity_id,
		"kind": "projectile",
		"projectile_unit_id": projectile_unit_id,
		"team": int(attacker.get("team", 0)),
		"source_id": int(attacker.get("id", -1)),
		"source_is_worker": world.entity_is_worker(attacker),
		"target_id": int(target.get("id", -1)),
		"attack_ground": ground_attack,
		"pos": spawn,
		"previous_pos": spawn,
		"origin": spawn,
		"target_position": destination,
		"initial_target_position": target["pos"],
		"origin_elevation": float(attacker.get("elevation", world.elevation_at(attacker["pos"]))),
		"target_elevation": float(target.get("elevation", world.elevation_at(target["pos"]))),
		"elevation": float(attacker.get("elevation", 0.0)) + launch_height,
		"visual_height": launch_height,
		"launch_height": launch_height,
		"speed": speed,
		"arc": float(projectile_spec.get("arc", 0.0)),
		"smart_mode": predictive_aim,
		"source_smart_mode": bool(projectile_spec.get("smart_mode", false)),
		"guidance": "predictive" if predictive_aim else "ballistic",
		"accuracy": accuracy,
		"accuracy_roll": int(aim["roll"]),
		"accurate": bool(aim["accurate"]),
		"attacks": combat.get("attacks", []).duplicate(true),
		"base_damage": float(attacker.get("attack_damage", 1.0)),
		"blast_range": maxf(0.0, float(combat.get("blast_range", attacker.get("blast_range", 0.0)))),
		"friendly_fire": bool(combat.get("friendly_fire", false)),
		"blast_falloff": String(combat.get("blast_falloff", "none")),
		"impact_effect_graphic_id": int(combat.get("impact_effect_graphic_id", -1)),
		"radius": projectile_radius,
		"total_distance": spawn.distance_to(destination),
		"elapsed": 0.0,
		"active": true,
		"hit": false,
		"direct_hit": false,
		"hit_target_ids": [],
		"damage": 0.0,
	}
	projectiles.append(projectile)
	world.emit_domain_event("entity_created", {
		"entity_id": projectile_entity_id,
		"entity_category": "projectile",
		"kind": "projectile",
		"team": int(attacker.get("team", 0)),
		"source_id": int(attacker.get("id", -1)),
	})
	return projectile


func update_projectiles(delta: float, player_team: int) -> void:
	var active_projectiles: Array = []
	for projectile in projectiles:
		if not bool(projectile.get("active", true)):
			continue
		if not ProjectileMotion.advance(projectile, delta):
			active_projectiles.append(projectile)
			continue
		var target: Variant = world.find_combat_target(int(projectile.get("target_id", -1)))
		var candidates := _impact_candidates(projectile, target)
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value
			if not _can_damage(projectile, candidate):
				continue
			var impact_damage := _damage_at_impact(projectile, candidate)
			projectile["hit"] = true
			projectile["direct_hit"] = bool(projectile.get("direct_hit", false)) or int(candidate.get("id", -1)) == int(projectile.get("target_id", -2))
			projectile["hit_target_ids"].append(int(candidate.get("id", -1)))
			projectile["damage"] = float(projectile.get("damage", 0.0)) + impact_damage
			_apply_impact_damage(candidate, impact_damage, {
				"entity_id": int(projectile.get("source_id", -1)),
				"team": int(projectile.get("team", 0)),
				"is_worker": bool(projectile.get("source_is_worker", false)),
			}, int(projectile["id"]), player_team)
		projectile["impact_position"] = Vector2(projectile["pos"])
		if world.capture_domain_events:
			world.emit_domain_event("projectile_impact", {
				"projectile_id": int(projectile["id"]),
				"source_id": int(projectile.get("source_id", -1)),
				"team": int(projectile.get("team", 0)),
				"position": Vector2(projectile["pos"]),
				"impact_effect_graphic_id": int(projectile.get("impact_effect_graphic_id", -1)),
				"blast_range": float(projectile.get("blast_range", 0.0)),
				"hit_target_ids": projectile.get("hit_target_ids", []).duplicate(),
			})
		projectile["active"] = false
		resolved_projectiles.append(projectile)
		if resolved_projectiles.size() > 100:
			resolved_projectiles.pop_front()
	projectiles.assign(active_projectiles)


func _impact_candidates(projectile: Dictionary, target: Variant) -> Array:
	var blast_range := maxf(0.0, float(projectile.get("blast_range", 0.0)))
	if blast_range > 0.0:
		return world.query_combat_entities_near(Vector2(projectile["pos"]), blast_range)
	if target == null or float(target.get("hp", 0.0)) <= 0.0 or not bool(projectile.get("accurate", false)):
		return []
	var collision_radius := float(projectile.get("radius", 0.1)) + float(target.get("footprint_radius", 0.3)) + 0.08
	return [target] if Vector2(projectile["pos"]).distance_to(Vector2(target["pos"])) <= collision_radius else []


func _apply_impact_damage(target: Dictionary, damage: float, source_context: Dictionary, projectile_id: int, player_team: int) -> void:
	var source_id := int(source_context.get("entity_id", -1))
	var source_team := int(source_context.get("team", 0))
	target["hp"] -= damage
	target["retaliation_target_id"] = source_id
	world.refresh_unit_activity(target)
	world.record_attack_distress({"id": source_id, "team": source_team}, target)
	if world.capture_domain_events:
		world.emit_domain_event("hit", {
			"source_id": source_id,
			"target_id": int(target["id"]),
			"projectile_id": projectile_id,
		})
		var damage_payload := {
			"source_id": source_id,
			"target_id": int(target["id"]),
			"amount": damage,
			"remaining_hp": maxf(0.0, float(target["hp"])),
		}
		if projectile_id >= 0:
			damage_payload["projectile_id"] = projectile_id
		world.emit_domain_event("damage", damage_payload)
	if damage > 0.0 and float(target["hp"]) <= 0.0:
		world.begin_entity_death(target, source_context)
		if source_team == player_team and not world.are_teams_allied(source_team, int(target.get("team", 0))):
			world.kills += 1
	EntityComponents.sync_dynamic(target)


func _can_damage(projectile: Dictionary, candidate: Dictionary) -> bool:
	if float(candidate.get("hp", 0.0)) <= 0.0:
		return false
	if bool(projectile.get("friendly_fire", false)):
		return true
	return not world.are_teams_allied(int(projectile.get("team", 0)), int(candidate.get("team", 0)))


func _damage_at_impact(projectile: Dictionary, target: Dictionary) -> float:
	var multiplier := 1.5 if float(target.get("elevation", 0.0)) < float(projectile.get("origin_elevation", 0.0)) else 1.0
	var attacks: Array = projectile.get("attacks", [])
	return CombatRules.damage_from_attacks(attacks, target, multiplier, float(projectile.get("base_damage", 1.0)))
