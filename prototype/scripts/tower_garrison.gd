class_name RoRTowerGarrison
extends RefCounted

const CAPACITY := 5
const MAX_EXTRA_ARROWS := 4


static func configure(components: Dictionary) -> void:
	var cargo: Dictionary = components.get("cargo", {}).duplicate(true)
	cargo.merge({"enabled": true, "garrison": true, "capacity": CAPACITY, "passenger_ids": cargo.get("passenger_ids", []).duplicate(), "allowed_domains": ["land"], "allow_artifacts": false}, true)
	components["cargo"] = cargo


static func is_tower(entity: Dictionary) -> bool:
	return String(entity.get("kind", "")) == "tower" or bool(entity.get("components", {}).get("cargo", {}).get("garrison", false))


static func accepts(unit: Dictionary) -> bool:
	if String(unit.get("movement_domain", "land")) != "land":
		return false
	var tags: Array = unit.get("behavior_tags", [])
	for excluded in ["cavalry", "siege", "naval", "huntable", "capturable", "transport"]:
		if excluded in tags:
			return false
	return "mobile" in tags and tags.any(func(tag): return tag in ["combatant", "worker", "religious", "hero"])


static func extra_arrows(world, tower: Dictionary) -> int:
	if not is_tower(tower):
		return 0
	var fire_power := 0.0
	for id in tower["components"]["cargo"].get("passenger_ids", []):
		var unit: Dictionary = world.transport_system.embarked_units.get(int(id), {})
		if float(unit.get("hp", 0.0)) <= 0.0 or "ranged" not in unit.get("behavior_tags", []):
			continue
		var owner := int(tower.get("team", 0))
		var passenger_owner := int(unit.get("team", 0))
		if passenger_owner != owner and not (world.are_teams_allied(owner, passenger_owner) and world.are_teams_allied(passenger_owner, owner)):
			continue
		fire_power += maxf(0.0, float(unit.get("attack_damage", 0.0))) / maxf(0.1, float(unit.get("attack_period", 1.0)))
	var tower_dps := maxf(0.1, float(tower.get("attack_damage", 1.0))) / maxf(0.1, float(tower.get("attack_period", 1.0)))
	return mini(MAX_EXTRA_ARROWS, floori(fire_power / tower_dps + 0.000001))


static func presentation(world, tower: Dictionary) -> Dictionary:
	var units: Array = []
	for id in tower["components"]["cargo"].get("passenger_ids", []):
		var unit: Dictionary = world.transport_system.embarked_units.get(int(id), {})
		if unit.is_empty():
			continue
		var record := {}
		for field in ["id", "kind", "team", "source_unit_id", "hp", "max_hp"]:
			record[field] = unit.get(field)
		record["components"] = {"ownership": unit.get("components", {}).get("ownership", {}).duplicate(true)}
		units.append(record)
	return {"capacity": CAPACITY, "units": units, "extra_arrows": extra_arrows(world, tower)}
