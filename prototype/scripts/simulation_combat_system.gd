class_name RoRSimulationCombatSystem
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const CombatRules := preload("res://scripts/combat_rules.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const ProjectileMotion := preload("res://scripts/projectile_motion.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null
var projectiles: Array = []
var resolved_projectiles: Array = []


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func reset() -> void:
	projectiles.clear()
	resolved_projectiles.clear()


func advance_projectiles(context: Dictionary) -> void:
	update_projectiles(float(context.get("delta", 0.0)), int(context.get("player_team", 0)))


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
