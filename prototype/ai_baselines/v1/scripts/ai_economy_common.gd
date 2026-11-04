extends RefCounted

# Shared accounting and deterministic command offers; planning stays in the
# forecast, production, construction and gathering modules.
static func economy_resources(resources: Array, buildings: Array, team: int, native: bool = true) -> Dictionary:
	if native and ClassDB.class_exists("RoRReadModelKernel"):
		var kernel = ClassDB.instantiate("RoRReadModelKernel")
		if kernel.has_method("economy_resource_view"):
			return kernel.economy_resource_view(resources, buildings, team)
	var active: Array = resources.filter(func(r): return int(r.get("amount", 0)) > 0)
	for building in buildings:
		if int(building.get("team", 0)) == team and bool(building.get("harvestable", false)) and int(building.get("amount", 0)) > 0:
			active.append(building)
	var by_id: Dictionary = {}
	var types: Dictionary = {}
	for row in active:
		by_id[int(row.get("id", -1))] = row
		types[int(row.get("resource_type_id", -1))] = true
	return {"resources":active,"by_id":by_id,"types":types}


static func own(rows: Array, team: int) -> Array:
	var result: Array = rows.filter(func(e): return int(e.get("team", 0)) == team and float(e.get("hp", 0.0)) > 0.0)
	result.sort_custom(func(a, b): return int(a.get("id", -1)) < int(b.get("id", -1)))
	return result


static func army_count(units: Array) -> int:
	return units.filter(func(u): return (bool(u.get("combat_enabled", false)) or "combatant" in u.get("behavior_tags", [])) and not bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and "worker" not in u.get("behavior_tags", []) and not bool(u.get("ai_profile", {}).get("transport", false))).size()


static func next_training_food(buildings: Array, worker: bool) -> int:
	var minimum := 2147483647
	for building in buildings:
		if worker and String(building.get("kind", "")) != "town_center": continue
		for option in building.get("command_options", {}).get("train", []):
			if not bool(option.get("accepted", true)) and String(option.get("reason", "")) != "insufficient_resources": continue
			var tags: Array = option.get("behavior_tags", [])
			if ("worker" in tags) != worker or (not worker and "combatant" not in tags): continue
			var cost: Dictionary = option.get("cost", {})
			minimum = mini(minimum, int(cost.get(0, cost.get("0", 0))))
	return 50 if minimum == 2147483647 else minimum


static func offer(
	result: Array,
	command,
	cost: Dictionary,
	points: int,
	producer: int,
	essential: bool,
	state,
	budget,
	reserved: Dictionary
) -> bool:
	var key := String(command.command_type()) + ":" + str(command.unit_ids) + ":" + str(command.params)
	if state.cooldowns.has(key):
		return false
	if not budget.reserve(cost, points, producer, essential):
		return false
	command.params["_ai_feedback"] = {"key": key, "cost": cost.duplicate(true)}
	if String(command.command_type()) == "build" and not cost.is_empty():
		command.params["_ai_feedback"]["site_key"] = site_key(String(command.params.get("building_type", "")), Vector2(command.params.get("target", Vector2.ZERO)))
	result.append(command)
	for id in command.unit_ids:
		reserved[int(id)] = true
	return true


static func site_key(kind: String, site: Vector2) -> String:
	return "build-site:%s:%s" % [kind, str(site)]
