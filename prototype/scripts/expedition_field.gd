extends RefCounted

const Service := preload("res://scripts/expedition.gd")
const Inventory := preload("res://scripts/expedition_inventory.gd")
const REACH := 1.65
const MAX_FIELD_CACHES := 48
const COMMON := ["point", "shield", "balm", "seal", "balm", "incense"]
const RARE := ["iron", "scales", "fibula"]

var casualties: Dictionary = {}
var piles: Dictionary = {}
var pickup_orders: Dictionary = {}
var next_pile := 1
var hero_ids: Dictionary = {}
var clock_tick := 0

func capture() -> Dictionary:
	if next_pile == 1 and casualties.is_empty(): return {}
	return {"next":next_pile, "casualties":casualties.duplicate(), "piles":piles.duplicate(true), "orders":pickup_orders.duplicate()}

static func valid_state(state: Variant, size: Vector2i) -> bool:
	if not state is Dictionary or not state.get("next") is int or state.next < 1: return false
	for key in ["casualties", "piles", "orders"]:
		if not state.get(key) is Dictionary: return false
	for team in state.casualties:
		if not team is int or team <= 0 or not state.casualties[team] is int or state.casualties[team] < 0: return false
	var bounds := Rect2(Vector2.ZERO, Vector2(size))
	for id in state.piles:
		var pile: Variant = state.piles[id]
		if not id is int or id < 1 or id >= state.next or not pile is Dictionary or pile.get("id") != id: return false
		if not pile.get("pos") is Vector2 or not bounds.has_point(pile.pos) or not pile.get("items") is Array or pile.items.is_empty(): return false
		for item in pile.items:
			if not Inventory.ITEMS.has(item): return false
	for id in state.orders:
		var pile_id: Variant = state.orders[id]
		if not id is int or not pile_id is int or pile_id < 1 or pile_id >= state.next: return false
	return true

func restore(world, state: Dictionary) -> void:
	next_pile = int(state.get("next", 1))
	casualties = state.get("casualties", {}).duplicate()
	piles = state.get("piles", {}).duplicate(true)
	pickup_orders = state.get("orders", {}).duplicate()
	hero_ids.clear()
	for unit in world.get_units() + world.get_embarked_units():
		if unit.has("service_role") and unit.hp > 0: hero_ids[unit.id] = true

func place(position: Vector2, items: Array) -> void:
	if items.is_empty(): return
	for pile in piles.values():
		if Vector2(pile.pos).distance_squared_to(position) <= 0.8 * 0.8:
			pile.items.append_array(items)
			return
	piles[next_pile] = {"id":next_pile, "pos":position, "items":items.duplicate()}
	next_pile += 1

func release_kit(hero: Dictionary, position: Vector2) -> void:
	place(position, Inventory.carried(hero))
	hero_ids.erase(hero.id)
	pickup_orders.erase(hero.id)
	for key in Inventory.GEAR: hero.erase(key)
	hero.erase("service_pack")
	hero.erase("service_ready_tick")

func fallen(world, unit: Dictionary, killer_team: int) -> void:
	if not unit.has("service_xp"): return
	var items := []
	if unit.has("service_role"):
		release_kit(unit, unit.pos)
	if killer_team <= 0 or world.are_teams_allied(killer_team, int(unit.team)): return
	var count := int(casualties.get(unit.team, 0)) + 1
	casualties[unit.team] = count
	if piles.size() >= MAX_FIELD_CACHES: return
	var roll := posmod(int(world.simulation_seed) + int(unit.id) * 37 + count * 13, 997)
	if unit.has("service_role") or int(unit.service_xp) >= Service.VETERAN or count % 7 == 0:
		items.append(RARE[roll % RARE.size()])
	elif count == 1:
		items.assign(["point", "balm"])
	elif count % 3 == 0 or int(unit.service_xp) >= Service.SEASONED:
		items.append(COMMON[roll % COMMON.size()])
	place(unit.pos, items)

func visible_piles(world, team: int) -> Array:
	var result := []
	for pile in piles.values():
		if world.get_fog_of_war().state_at_world(team, pile.pos) == 2: result.append(pile.duplicate(true))
	return result

func roster(world, team: int) -> Array:
	var result := []
	for id in hero_ids:
		var unit: Variant = world.units_by_id.get(id, world.transport_system.embarked_units.get(id))
		if unit == null or unit.hp <= 0: continue
		var carrier := int(unit.get("transported_by_id", -1))
		if unit.team != team and (carrier >= 0 or not world.is_entity_visible_to(team, unit)): continue
		var row := {"id":id, "pos":unit.pos, "role":unit.service_role, "name":unit.service_name, "team":unit.team,
			"hp":unit.hp, "max_hp":unit.max_hp, "xp":unit.service_xp, "carrier":carrier}
		if unit.team == team:
			row["kit"] = []
			for i in Inventory.GEAR.size() + Inventory.PACK_SIZE: row.kit.append(Inventory.at(unit, i).duplicate())
			row["ready"] = int(unit.get("service_ready_tick", 0))
			row["guard_until"] = int(unit.get("service_guard_until", 0))
			var source: Dictionary = world.object_record_by_id(int(unit.source_unit_id), team)
			row["icon"] = int(source.get("interface", {}).get("icon_id", -1))
			if carrier >= 0:
				var vessel: Variant = world.find_combat_target(carrier)
				if vessel != null: row.pos = vessel.pos
		result.append(row)
	result.sort_custom(func(a, b): return a.id < b.id)
	return result

func request_pickup(world, hero: Dictionary, id: int) -> String:
	if not piles.has(id) or world.get_fog_of_war().state_at_world(hero.team, piles[id].pos) != 2:
		return "expedition_no_loot"
	var pos := Vector2(piles[id].pos)
	if Vector2(hero.pos).distance_squared_to(pos) <= REACH * REACH:
		pickup_orders.erase(hero.id)
		return collect(world, hero, id)
	if not world.assign_command_move([hero], pos): return "no_path"
	world.clear_entity_queued_orders(hero)
	world.transport_system.clear_pending_order(hero)
	pickup_orders[hero.id] = id
	return ""

func collect(world, hero: Dictionary, id: int) -> String:
	var remaining := []
	var taken := []
	for item in piles[id].items:
		if Inventory.receive(world, hero, item): taken.append(item)
		else: remaining.append(item)
	if taken.is_empty(): return "expedition_pack_full"
	if remaining.is_empty(): piles.erase(id)
	else: piles[id].items = remaining
	world.emit_domain_event("service_pickup", {"team":hero.team, "name":hero.service_name, "items":taken, "remaining":remaining.size()})
	return ""

func advance_pickups(world) -> void:
	for id in pickup_orders.keys():
		var unit: Variant = world.units_by_id.get(id)
		var pile: Dictionary = piles.get(pickup_orders[id], {})
		if unit == null or unit.hp <= 0 or not unit.has("service_role") or pile.is_empty():
			pickup_orders.erase(id)
		elif Vector2(unit.pos).distance_squared_to(pile.pos) <= REACH * REACH and world.get_fog_of_war().state_at_world(unit.team, pile.pos) == 2:
			var reason := collect(world, unit, int(pile.id))
			pickup_orders.erase(id)
			if reason != "": world.emit_domain_event("service_pickup_failed", {"team":unit.team, "reason":reason})
		elif unit.get("task") != "move":
			pickup_orders.erase(id)
