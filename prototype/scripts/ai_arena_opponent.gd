# Fixed arena challenger. Its economy and strategic dependencies are frozen.
extends "res://ai_baselines/v1/scripts/ai_player.gd"
const ArenaCommands := preload("res://scripts/commands.gd")

func collect_commands(snapshot: Dictionary, tick: int) -> Array:
	var commands: Array = super.collect_commands(snapshot, tick)
	var role := String(economic_policy.get("opponent_role", "baseline"))
	if role not in ["ranged", "raid", "siege", "naval"]: return commands
	var enemies: Array = snapshot.get("units", []).filter(func(e): return int(e.get("team", 0)) != team and int(e.get("team", 0)) > 0 and not bool(e.get("last_known", false)) and int(e.get("team",0)) not in snapshot.get("player_state",{}).get("allies",[team]))
	if role == "siege": enemies.append_array(snapshot.get("buildings", []).filter(func(e): return int(e.get("team",0)) != team and int(e.get("team",0)) > 0 and not bool(e.get("last_known", false)) and int(e.get("team",0)) not in snapshot.get("player_state",{}).get("allies",[team])))
	if enemies.is_empty(): return commands
	var ids: Dictionary = {}
	for actor in snapshot.get("units", []):
		if int(actor.get("team",0)) != team or bool(actor.get("components",{}).get("worker",{}).get("enabled",false)) or not bool(actor.get("combat_enabled",false)): continue
		var profile: Dictionary = actor.get("ai_profile",{})
		var target: Dictionary = {}
		var best := -INF
		for enemy in enemies:
			var distance := Vector2(actor.get("pos",Vector2.ZERO)).distance_to(Vector2(enemy.get("pos",Vector2.ZERO)))
			if distance > 12.0 or String(enemy.get("movement_domain","land")) not in actor.get("target_domains",["land","water","static"]): continue
			var score := -distance
			if role == "raid" and bool(enemy.get("components",{}).get("worker",{}).get("enabled",false)): score += 20.0
			if role == "siege" and String(enemy.get("entity_type","")) == "building": score += 20.0
			if role == "naval" and bool(enemy.get("components",{}).get("cargo",{}).get("enabled",false)): score += 20.0
			if score > best: best = score; target = enemy
		if target.is_empty(): continue
		var id := int(actor["id"])
		var command = null
		var delta := Vector2(actor.get("pos",Vector2.ZERO)) - Vector2(target.get("pos",Vector2.ZERO))
		if role == "ranged" and float(profile.get("range",0.0)) > 2.0 and delta.length() < float(profile.get("range",0.0))*0.7 and float(profile.get("cooldown",0.0)) > 0.3:
			command = ArenaCommands.MoveCommand.new(tick,[id],Vector2(actor["pos"])+delta.normalized()*2.0)
		elif int(actor.get("target_id",-1)) != int(target["id"]): command = ArenaCommands.AttackCommand.new(tick,[id],int(target["id"]))
		if command != null: ids[id] = command
	var result: Array = []
	for command in commands:
		if command.unit_ids.any(func(id): return ids.has(int(id))): continue
		result.append(command)
	result.append_array(ids.values())
	return result
