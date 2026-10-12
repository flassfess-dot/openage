class_name RoRAiCombatModel
extends RefCounted
const Rules := preload("res://scripts/combat_rules.gd")


# A deterministic estimate, not a second combat simulator. Profiles are copied
# from legal observed actors or public DAT definitions at the observation boundary.
static func profile(entity: Dictionary) -> Dictionary:
	return entity.get("ai_profile", {})


static func dps(attacker: Dictionary, defender: Dictionary) -> float:
	var attack := profile(attacker)
	var armor := profile(defender)
	if not bool(attack.get("enabled", attacker.get("combat_enabled", false))):
		return 0.0
	var building := (
		String(defender.get("entity_type", "")) == "building" or String(defender.get("movement_domain", "")) == "static"
	)
	var damage := Rules.total_damage(
		attack.get("attacks", []),
		armor.get("armors", []),
		0.2 if building else 1.0,
		0.1 if building else 1.0,
		float(armor.get("base_armor", 0.0))
	)
	if attack.get("attacks", []).is_empty():
		damage = maxf(0.1 if building else 1.0, float(attack.get("damage", 1.0)) * (0.2 if building else 1.0))
	return damage / maxf(0.1, float(attack.get("period", 2.0)))


static func strength(force: Array, opponents: Array = [], pair_limit: int = 64) -> float:
	var total := 0.0
	for actor in force:
		var data := profile(actor)
		if not bool(data.get("enabled", actor.get("combat_enabled", false))):
			continue
		var damage := float(data.get("damage", 1.0)) / maxf(0.1, float(data.get("period", 2.0)))
		if not opponents.is_empty():
			damage = 0.0
			var count := mini(opponents.size(), maxi(1, pair_limit))
			for index in range(count):
				damage += dps(actor, opponents[index])
			damage /= float(count)
		var hp := maxf(0.0, float(actor.get("hp", data.get("max_hp", 1.0))))
		if bool(actor.get("health_unknown", false)):
			hp = float(data.get("max_hp", 1.0))
		total += sqrt(hp * maxf(0.0, damage)) * (1.0 + minf(12.0, float(data.get("range", 0.0))) * 0.035)
	return total


static func counter_score(candidate: Dictionary, enemies: Array, own: Array) -> float:
	var score := strength([candidate], enemies)
	var kind := String(candidate.get("kind", ""))
	var same := 0
	for actor in own:
		if String(actor.get("kind", "")) == kind:
			same += 1
	var incoming := 0.0
	for enemy in enemies.slice(0, 32):
		incoming += dps(enemy, candidate)
	if not enemies.is_empty():
		incoming /= float(mini(enemies.size(), 32))
	return score / (1.0 + incoming * 0.05) / (1.0 + float(same) * 0.06)
