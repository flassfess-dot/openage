class_name RoRCombatRules

const MELEE_CONTACT_MARGIN: float = 0.08


static func damage_for_attack(attack: Dictionary, armors: Array, multiplier: float = 1.0, base_armor: float = 0.0) -> float:
	var amount := float(attack.get("amount", 0.0))
	if not attack.has("type_id"):
		return maxf(amount * multiplier, 0.0)
	var attack_class := int(attack["type_id"])
	var armor_amount := base_armor
	var matched_class := false
	for armor_value in armors:
		var armor: Dictionary = armor_value
		if int(armor.get("type_id", -1)) != attack_class:
			continue
		matched_class = true
		armor_amount += float(armor.get("amount", 0.0))
	if matched_class:
		armor_amount -= base_armor
	return maxf((amount - armor_amount) * multiplier, 0.0)


static func total_damage(attacks: Array, armors: Array, multiplier: float = 1.0, minimum_damage: float = 1.0, base_armor: float = 0.0) -> float:
	var total := 0.0
	for attack_value in attacks:
		var attack: Dictionary = attack_value
		total += damage_for_attack(attack, armors, multiplier, base_armor)
	return maxf(total, minimum_damage)


static func is_building_target(target: Dictionary) -> bool:
	return target.has("occupied_cells") and String(target.get("movement_domain", "")) == "static"


static func damage_from_attacks(attacks: Array, target: Dictionary, multiplier: float = 1.0, fallback: float = 0.0) -> float:
	var target_combat: Dictionary = target.get("components", {}).get("combat", {})
	var building_target := is_building_target(target)
	var final_multiplier := multiplier * (0.2 if building_target else 1.0)
	var minimum_damage := 0.1 if building_target else 1.0
	if attacks.is_empty():
		return maxf(fallback * final_multiplier, minimum_damage)
	return total_damage(attacks, target_combat.get("armors", []), final_multiplier, minimum_damage, float(target_combat.get("base_armor", 0.0)))


static func primary_attack_damage(attacks: Array, fallback: float = 0.0) -> float:
	# The scalar is presentation/compatibility data; authoritative combat retains
	# every attack class. RoR commonly stores a zero-value bonus class before the
	# base melee class, so taking attacks[0] makes cavalry appear to have no attack.
	for attack_value in attacks:
		var attack: Dictionary = attack_value
		if int(attack.get("type_id", -1)) == 4:
			return float(attack.get("amount", fallback))
	if attacks.is_empty():
		return fallback
	var result := 0.0
	for attack_value in attacks:
		var attack: Dictionary = attack_value
		result = maxf(result, float(attack.get("amount", 0.0)))
	return result


static func edge_distance(attacker: Dictionary, target: Dictionary) -> float:
	var attacker_position := Vector2(attacker.get("pos", Vector2.ZERO))
	var target_position := Vector2(target.get("pos", Vector2.ZERO))
	var target_footprint: Dictionary = target.get("footprint", {})
	if String(target_footprint.get("shape", "")) == "polygon":
		var half_size := Vector2(target_footprint.get("half_size", Vector2.ZERO))
		var offset := (attacker_position - target_position).abs() - half_size
		var outside := Vector2(maxf(0.0, offset.x), maxf(0.0, offset.y)).length()
		return maxf(0.0, outside - float(attacker.get("footprint_radius", 0.0)))
	var center_distance: float = attacker_position.distance_to(target_position)
	var occupied_radius := float(attacker.get("footprint_radius", 0.0)) + float(target.get("footprint_radius", 0.0))
	return maxf(0.0, center_distance - occupied_radius)


static func is_in_range(attacker: Dictionary, target: Dictionary) -> bool:
	var maximum_range := float(attacker.get("attack_range", 0.0))
	var allowed_edge_distance := maximum_range if maximum_range > 1.0 else maximum_range + MELEE_CONTACT_MARGIN
	var distance := edge_distance(attacker, target)
	return distance <= allowed_edge_distance + 0.0001 and not is_too_close(attacker, target)


static func is_too_close(attacker: Dictionary, target: Dictionary) -> bool:
	var combat: Dictionary = attacker.get("components", {}).get("combat", {})
	var minimum_range := maxf(0.0, float(combat.get("range_min", attacker.get("attack_range_min", 0.0))))
	return minimum_range > 0.0 and edge_distance(attacker, target) + 0.0001 < minimum_range


static func entity_damage(attacker: Dictionary, target: Dictionary, multiplier: float = 1.0) -> float:
	var attacker_components: Dictionary = attacker.get("components", {})
	var combat: Dictionary = attacker_components.get("combat", {})
	var attacks: Array = combat.get("attacks", [])
	var elevation_multiplier := 1.0
	if int(combat.get("projectile_id", attacker.get("projectile_id", -1))) < 0 and float(attacker.get("elevation", 0.0)) < float(target.get("elevation", 0.0)):
		elevation_multiplier = 2.0 / 3.0
	return damage_from_attacks(attacks, target, multiplier * elevation_multiplier, float(attacker.get("attack_damage", 0.0)))
