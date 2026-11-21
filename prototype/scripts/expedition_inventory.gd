extends RefCounted

# The original service_item field remains the armour slot in existing saves.
const GEAR := ["service_weapon", "service_item", "service_relic"]
const SLOT_NAMES := ["Оружие", "Доспех", "Реликвия"]
const PACK_SIZE := 4
const STACK_SIZE := 3
const ITEMS := {
	"point": {"name":"Бронзовое остриё", "slot":0, "icon":38, "effect":"+2 к урону за попадание или к лечению жреца в секунду", "attack":2},
	"iron": {"name":"Кованое остриё", "slot":0, "icon":37, "effect":"+4 к урону за попадание или к лечению жреца в секунду", "attack":4},
	"shield": {"name":"Трофейный щит", "slot":1, "icon":19, "effect":"На 4% меньше входящего урона", "guard":0.04},
	"scales": {"name":"Чешуйчатый панцирь", "slot":1, "icon":74, "effect":"На 9% меньше входящего урона", "guard":0.09},
	"seal": {"name":"Печать наставника", "slot":2, "icon":71, "effect":"На 25% больше личного опыта"},
	"fibula": {"name":"Крылатая фибула", "slot":2, "icon":97, "effect":"На 25% короче перезарядка умения"},
	"balm": {"name":"Лечебный бальзам", "slot":-1, "icon":12, "effect":"Восстанавливает герою до 18 здоровья"},
	"incense": {"name":"Благовония", "slot":-1, "icon":9, "effect":"Сразу восстанавливают умение героя"}
}

static func pack(unit: Dictionary) -> Array:
	return unit.get("service_pack", [{}, {}, {}, {}])

static func valid_pack(value: Variant) -> bool:
	if not value is Array or value.size() != PACK_SIZE: return false
	for stack in value:
		if not stack is Dictionary: return false
		if stack.is_empty(): continue
		if not ITEMS.has(stack.get("item", "")) or not stack.get("count") is int: return false
		var limit := STACK_SIZE if ITEMS[stack.item].slot < 0 else 1
		if stack.count < 1 or stack.count > limit: return false
	return true

static func at(unit: Dictionary, slot: int) -> Dictionary:
	if slot < 0 or slot >= GEAR.size() + PACK_SIZE: return {}
	if slot < GEAR.size():
		var item := String(unit.get(GEAR[slot], ""))
		return {"item":item, "count":1} if ITEMS.has(item) else {}
	return pack(unit)[slot - GEAR.size()]

static func pack_slot(bag: Array, item: String) -> int:
	if ITEMS[item].slot < 0:
		for i in bag.size():
			if bag[i].get("item") == item and int(bag[i].count) < STACK_SIZE: return i
	for i in bag.size():
		if bag[i].is_empty(): return i
	return -1

static func receive(world, hero: Dictionary, item: String) -> bool:
	if not ITEMS.has(item): return false
	var slot := int(ITEMS[item].slot)
	if slot >= 0 and String(hero.get(GEAR[slot], "")).is_empty():
		world.set_entity_field(hero, GEAR[slot], item)
		return true
	var bag := pack(hero).duplicate(true)
	var index := pack_slot(bag, item)
	if index < 0: return false
	bag[index] = {"item":item, "count":int(bag[index].get("count", 0)) + 1}
	world.set_entity_field(hero, "service_pack", bag)
	return true

static func remove_one(world, hero: Dictionary, slot: int) -> void:
	if slot < GEAR.size():
		world.set_entity_field(hero, GEAR[slot], "")
		return
	var bag := pack(hero).duplicate(true)
	var index := slot - GEAR.size()
	var stack: Dictionary = bag[index]
	stack.count -= 1
	if stack.count == 0: bag[index] = {}
	world.set_entity_field(hero, "service_pack", bag)

static func act(world, hero: Dictionary, slot: int, expected: String, drop: bool, tick: int) -> String:
	var stack := at(hero, slot)
	if expected.is_empty() or stack.get("item") != expected: return "expedition_slot_changed"
	if drop:
		world.expedition_field.place(hero.pos, [expected])
		remove_one(world, hero, slot)
		return ""
	var bag := pack(hero).duplicate(true)
	if slot < GEAR.size():
		var index := pack_slot(bag, expected)
		if index < 0: return "expedition_pack_full"
		bag[index] = stack
		world.set_entity_fields(hero, {GEAR[slot]:"", "service_pack":bag})
		return ""
	var gear_slot := int(ITEMS[expected].slot)
	if gear_slot >= 0:
		bag[slot - GEAR.size()] = at(hero, gear_slot)
		world.set_entity_fields(hero, {GEAR[gear_slot]:expected, "service_pack":bag})
		return ""
	if expected == "balm":
		if hero.hp >= hero.max_hp: return "expedition_healthy"
		heal_wounds(world, hero, 18.0)
	elif expected == "incense":
		if int(hero.get("service_ready_tick", 0)) <= tick: return "expedition_already_ready"
		world.set_entity_field(hero, "service_ready_tick", tick)
	remove_one(world, hero, slot)
	return ""

static func balm_slot(hero: Dictionary) -> int:
	var bag := pack(hero)
	for i in bag.size():
		if bag[i].get("item") == "balm": return GEAR.size() + i
	return -1

static func carried(hero: Dictionary) -> Array:
	var result := []
	for i in GEAR.size() + PACK_SIZE:
		var stack := at(hero, i)
		for n in int(stack.get("count", 0)): result.append(stack.item)
	return result

static func heal_wounds(world, unit: Dictionary, amount: float) -> int:
	var healed := minf(amount, float(unit.max_hp) - float(unit.hp))
	world.set_entity_field(unit, "hp", float(unit.hp) + healed)
	var spent := int(unit.get("service_spent", 0))
	var used := int(unit.get("service_healed", 0))
	var credit := clampi(roundi(healed * 1000), 0, maxi(0, spent - used))
	if credit > 0: world.set_entity_field(unit, "service_healed", used + credit)
	return credit
