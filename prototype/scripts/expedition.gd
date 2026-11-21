extends RefCounted

const Inventory := preload("res://scripts/expedition_inventory.gd")

# Prices are in thousandths of a hit point actually dealt/restored.
const SEASONED := 12000
const VETERAN := 36000
const LIMIT := 3
const SECOND := "res://data/matches/expedition_coast.json"
const ROLES := {"captain":"Начальник строя", "scout":"Дозорный", "medic":"Полевой лекарь"}
const ABILITIES := {"captain":"Щитовой строй", "scout":"Разведка", "medic":"Перевязка"}
const ROLE_ICONS := {"captain":46, "scout":97, "medic":12}
const ROLE_DETAILS := {
	"captain":"Делится опытом с бойцами в радиусе 4 клеток. Щитовой строй снижает входящий урон отряду на 8 секунд.",
	"scout":"Видит на 2 клетки дальше. Разведка наносит окрестности на карту.",
	"medic":"Перевязка восстанавливает здоровье союзным бойцам в радиусе 4 клеток."
}
const HERO_XP := [36000, 72000, 120000]
const RECOVERY_TICKS := {"captain":480, "scout":600, "medic":500}

static func level(xp: int) -> int:
	return 3 if xp >= HERO_XP[2] else 2 if xp >= HERO_XP[1] else 1

static func ability_detail(role: String, tier: int) -> String:
	match role:
		"captain": return "Защита %d%% · 4 клетки · 8 сек." % (10 + 5 * tier)
		"scout": return "Открывает рельеф в радиусе %d клеток" % (9 + 2 * tier)
		"medic": return "+%d здоровья каждому раненому бойцу в радиусе 4 клеток" % (8 + 5 * tier)
	return ""

static func enabled(world) -> bool:
	return world.field_service_enabled

static func enroll(world, unit: Dictionary) -> void:
	if not enabled(world) or int(unit["team"]) <= 0 or unit["movement_domain"] != "land":
		return
	var tags: Array = unit.get("behavior_tags", [])
	if "worker" not in tags and "siege" not in tags and ("combatant" in tags or "religious" in tags or unit["kind"] == "priest"):
		unit["service_xp"] = 0

static func rank(xp: int) -> String:
	return "Ветеран" if xp >= VETERAN else "Бывалый" if xp >= SEASONED else "Новобранец"

static func award(world, unit: Dictionary, points: int) -> void:
	award_personal(world, unit, points)
	if points <= 0 or unit.get("service_role") != "captain" or unit.hp <= 0 or unit.get("cargo_state") == "embarked": return
	var students: Array = []
	for other in world.query_combat_entities_near(unit.pos, 4.0):
		if other.id != unit.id and other.team == unit.team and other.hp > 0 and other.has("service_xp") and not other.has("service_role") and int(other.service_xp) < VETERAN and Vector2(unit.pos).distance_squared_to(other.pos) <= 16.0:
			students.append(other)
	students.sort_custom(func(a, b): return a.id < b.id)
	var pool := points / 4
	for i in students.size():
		award_personal(world, students[i], pool / students.size() + int(i < pool % students.size()))

static func award_personal(world, unit: Dictionary, points: int) -> void:
	var old := int(unit.get("service_xp", -1))
	var limit := int(HERO_XP.back()) if unit.has("service_role") else VETERAN
	if points > 0 and old >= 0 and old < limit and float(unit.hp) > 0:
		var gained := points * 5 / 4 if unit.get("service_relic") == "seal" else points
		var xp := mini(limit, old + gained)
		world.set_entity_field(unit, "service_xp", xp)
		if unit.has("service_role") and level(xp) > level(old):
			world.emit_domain_event("service_level", {"team":unit.team, "name":unit.service_name, "level":level(xp)})
		elif old < VETERAN and xp == VETERAN:
			world.emit_domain_event("service_veteran", {"team":unit.team, "id":unit.id})

static func incoming_damage(unit: Dictionary, damage: float, tick: int = 0) -> float:
	var xp := int(unit["service_xp"])
	var reduction := 0.06 if xp >= VETERAN else 0.03 if xp >= SEASONED else 0.0
	reduction += float(Inventory.ITEMS.get(unit.get("service_item", ""), {}).get("guard", 0.0))
	if int(unit.get("service_guard_until", 0)) > tick:
		reduction += float(unit.get("service_guard", 0.0))
	return damage * (1.0 - reduction)

static func bonus_damage(unit: Dictionary) -> float:
	return float(Inventory.ITEMS.get(unit.get("service_weapon", ""), {}).get("attack", 0))

static func garrison_shooters(world, tower: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for id in tower.components.cargo.passenger_ids:
		var soldier: Dictionary = world.transport_system.embarked_units.get(id, {})
		if soldier.has("service_xp") and soldier.hp > 0 and "ranged" in soldier.get("behavior_tags", []) and world.are_teams_allied(int(tower.team), int(soldier.team)):
			ids.append(int(id))
	ids.sort()
	return ids

static func credit_hit(world, target: Dictionary, damage: float, source_id: int, team: int, crew: Array) -> void:
	if team <= 0 or int(target.team) <= 0 or world.are_teams_allied(team, int(target.team)):
		return
	# No credit for hitting livestock, workers, foundations or empty walls.
	if not target.has("service_xp") and (target.has("production_queue") or not target.get("combat_enabled", false) or "worker" in target.get("behavior_tags", [])):
		return
	var source: Variant = world.find_unit(source_id)
	if source == null:
		source = world.transport_system.embarked_units.get(source_id)
	var shooters: Array = []
	if source != null and source.team == team and source.has("service_xp") and source.hp > 0:
		shooters.append(source)
	for id in crew:
		var archer: Variant = world.units_by_id.get(id, world.transport_system.embarked_units.get(id))
		if archer != null and archer.hp > 0 and world.are_teams_allied(team, int(archer.team)):
			shooters.append(archer)
	var spent := int(target.get("service_spent", 0))
	var points := mini(roundi(1000 * minf(float(target.hp), damage)), roundi(1000 * float(target.max_hp)) - spent)
	if points <= 0:
		return
	world.set_entity_field(target, "service_spent", spent + points)
	for i in shooters.size():
		award(world, shooters[i], points / shooters.size() + int(i < points % shooters.size()))

static func appoint(world, unit: Dictionary, role: String, officer_name: String) -> String:
	if int(unit.get("service_xp", -1)) < VETERAN or not ROLES.has(role) or unit.has("service_role"):
		return "expedition_promotion_unavailable"
	officer_name = officer_name.strip_edges()
	if officer_name.is_empty() or officer_name.length() > 24 or "\n" in officer_name or "\r" in officer_name or "\t" in officer_name:
		return "expedition_invalid_name"
	for id in world.expedition_field.hero_ids:
		var other: Variant = world.units_by_id.get(id, world.transport_system.embarked_units.get(id))
		if other != null and other.team == unit.team and other.hp > 0 and other.get("service_role") == role:
			return "expedition_officer_exists"
	world.set_entity_fields(unit, {"service_role":role, "service_name":officer_name})
	world.expedition_field.hero_ids[unit.id] = true
	if role == "scout":
		unit.components.vision.range += 2.0
		world.notify_entity_changed(unit)
	return ""

static func use_ability(world, hero: Dictionary, tick: int) -> String:
	var role := String(hero.service_role)
	if int(hero.get("service_ready_tick", 0)) > tick: return "expedition_recovering"
	var tier := level(int(hero.service_xp))
	var affected := false
	if role == "scout":
		var fog = world.get_fog_of_war()
		var center := Vector2i(Vector2(hero.pos).floor())
		var radius := 9 + 2 * tier
		for y in range(maxi(0, center.y - radius), mini(world.map_size.y, center.y + radius + 1)):
			for x in range(maxi(0, center.x - radius), mini(world.map_size.x, center.x + radius + 1)):
				var cell := Vector2i(x, y)
				if center.distance_squared_to(cell) <= radius * radius and fog.state_at_world(hero.team, Vector2(cell) + Vector2(0.5, 0.5)) == 0:
					fog.reveal_explored_cell(hero.team, cell)
					affected = true
		if not affected: return "expedition_surveyed"
	else:
		var soldiers: Array = world.query_combat_entities_near(hero.pos, 4.0)
		var medical_credit := 0
		for ally in soldiers:
			if not ally.has("service_xp") or ally.hp <= 0 or not world.are_teams_allied(hero.team, ally.team) or Vector2(hero.pos).distance_squared_to(ally.pos) > 16.0: continue
			if role == "medic":
				if ally.hp >= ally.max_hp: continue
				medical_credit += Inventory.heal_wounds(world, ally, 8 + 5 * tier)
			else:
				world.set_entity_fields(ally, {"service_guard":0.10 + 0.05 * tier, "service_guard_until":tick + 160})
			affected = true
		if not affected: return "expedition_no_wounded"
		if medical_credit > 0: award(world, hero, medical_credit)
	var recovery := int(RECOVERY_TICKS[role])
	if hero.get("service_relic") == "fibula": recovery = recovery * 3 / 4
	world.set_entity_field(hero, "service_ready_tick", tick + recovery)
	world.emit_domain_event("service_ability", {"team":hero.team, "pos":hero.pos, "role":role, "radius":9 + 2 * tier if role == "scout" else 4})
	return ""

static func search_shrine(world, unit: Dictionary) -> String:
	if not unit.has("service_role"):
		return "expedition_item_unavailable"
	for shrine in world.get_buildings():
		var item := String(shrine.get("expedition_cache", ""))
		if item in ["shield", "chart"] and shrine.hp > 0 and Vector2(shrine.pos).distance_squared_to(unit.pos) <= 16.0 and world.get_fog_of_war().state_at_world(int(unit.team), shrine.pos) == 2:
			if item == "shield" and not Inventory.receive(world, unit, item): return "expedition_pack_full"
			world.set_entity_field(shrine, "expedition_cache", "")
			if item == "chart":
				# Survey only the marked ground. This is exploration, not live
				# sight: troops and structures in fog are not disclosed.
				for cell in shrine.get("survey_cells", []):
					world.get_fog_of_war().reveal_explored_cell(int(unit.team), cell)
			return ""
	return "expedition_no_cache"

static func survivors(world, team: int) -> Array:
	var rows := []
	for unit in world.get_units() + world.get_embarked_units():
		if unit.team == team and unit.hp > 0 and int(unit.get("service_xp", 0)) > 0:
			rows.append({"id":int(unit.id), "kind":String(unit.kind), "xp":int(unit.service_xp),
				"role":String(unit.get("service_role","")), "name":String(unit.get("service_name","")), "item":String(unit.get("service_item","")),
				"weapon":String(unit.get("service_weapon","")), "relic":String(unit.get("service_relic","")), "pack":Inventory.pack(unit).duplicate(true)})
	rows.sort_custom(func(a,b):
		if a.role.is_empty() != b.role.is_empty(): return not a.role.is_empty()
		return a.xp > b.xp if a.xp != b.xp else a.id < b.id)
	return rows

static func inherit_service(world, unit: Dictionary, record: Dictionary) -> void:
	if not unit.has("service_xp"): return
	world.set_entity_field(unit, "service_xp", clampi(int(record.get("xp", 0)), 0, VETERAN))
	if ROLES.has(record.get("role", "")) and appoint(world, unit, record.role, record.name) == "":
		world.set_entity_field(unit, "service_xp", clampi(int(record.xp), VETERAN, int(HERO_XP.back())))
		for key in ["weapon", "item", "relic"]:
			var item := String(record.get(key, ""))
			if Inventory.ITEMS.has(item) and Inventory.ITEMS[item].slot == ["weapon", "item", "relic"].find(key):
				Inventory.receive(world, unit, item)
		var bag := [{}, {}, {}, {}]
		var previous: Array = record.get("pack", [])
		for i in mini(bag.size(), previous.size()):
			if not previous[i] is Dictionary: continue
			var item := String(previous[i].get("item", ""))
			if Inventory.ITEMS.has(item):
				bag[i] = {"item":item, "count":clampi(int(previous[i].get("count", 1)), 1, Inventory.STACK_SIZE if Inventory.ITEMS[item].slot < 0 else 1)}
		world.set_entity_field(unit, "service_pack", bag)
