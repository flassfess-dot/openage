extends SceneTree

const LootView := preload("res://scripts/expedition_loot_view.gd")

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Service := preload("res://scripts/expedition.gd")
const Kit := preload("res://scripts/expedition_inventory.gd")
var world
var controller
var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func issue(hero: Dictionary, action: String, options: Dictionary = {}, team := 1) -> Dictionary:
	var command := Commands.ServiceCommand.new(controller.tick_index, [int(hero.id)], action, "Полководец", options)
	controller.enqueue_command(command, true, team)
	controller.process_commands()
	return controller.get_command_result(command.sequence_id)

func make_field(catalog) -> void:
	world = World.new(Vector2i(40, 40))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.field_service_enabled = true
	world.set_simulation_seed(3435)
	controller = Controller.new(world)

func _initialize() -> void:
	var supplies: Texture2D = LootView.frame_for(["balm", "incense"]).texture
	check(supplies.get_image().get_used_rect().size.x == 21, "provision roll occupies 21 native pixels")
	var gear_art := {}
	for item in Kit.ITEMS:
		var shown: Texture2D = LootView.frame_for(["incense", item, "balm"]).texture
		if Kit.ITEMS[item].slot < 0:
			check(shown == supplies, "supplies share a bound roll")
		else:
			check(shown != supplies and not gear_art.has(shown), "distinct equipment in the satchel: " + item)
			check(shown.get_image().get_used_rect().size.x == 21, "satchel keeps its small battlefield silhouette: " + item)
			check(shown == LootView.frame_for([item, "balm"]).texture, "mixing in supplies preserves " + item)
			gear_art[shown] = true
	var catalog := Catalog.new()
	catalog.load_generated_data()
	make_field(catalog)
	var captain: Dictionary = world.add_unit(1, "archer", Vector2(8, 8), false)
	var medic: Dictionary = world.add_unit(1, "priest", Vector2(9, 8), false)
	var student: Dictionary = world.add_unit(1, "clubman", Vector2(8, 9), false)
	var distant: Dictionary = world.add_unit(1, "archer", Vector2(28, 28), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(34, 32), false)
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	for unit in [captain, medic]: Service.award(world, unit, Service.VETERAN)
	check(issue(captain,"captain").accepted and issue(medic,"medic").accepted, "captain and medic can serve together")
	Service.award(world, captain, 4000)
	check(captain.service_xp == 40000 and student.service_xp == 1000 and distant.service_xp == 0, "leadership shares a finite pool within four cells")
	world.set_entity_field(student, "hp", student.max_hp - 20.0)
	world.set_entity_field(student, "service_spent", 5000)
	check(issue(medic, "ability").accepted and is_equal_approx(student.hp, student.max_hp - 7.0), "tier-one group treatment restores thirteen HP per wounded soldier")
	check(medic.service_xp == 41000 and student.service_healed == 5000, "a medic earns XP only for uncredited enemy wounds")
	check(not issue(medic, "ability").accepted and medic.service_ready_tick == 500, "a repeated ability cannot bypass its cooldown")
	world.set_entity_field(student, "hp", student.max_hp)
	check(issue(captain, "ability").accepted and is_equal_approx(Service.incoming_damage(student, 10.0, 1), 8.5), "shield wall protects a squad member in combat")
	check(is_equal_approx(Service.incoming_damage(student, 10.0, 160), 10.0), "formation protection expires on the exact simulation tick")
	Service.award(world, captain, 90000)
	check(Service.level(captain.service_xp) == 3 and captain.service_xp == 120000, "experienced heroes reach and retain the third level")
	var field = world.expedition_field
	field.place(enemy.pos, ["seal"])
	check(not issue(captain, "pickup", {"pile":1}).accepted and field.visible_piles(world, 1).is_empty(), "a guessed coffer in fog cannot be seen or taken")
	field.place(captain.pos, ["point", "shield", "fibula", "iron", "scales", "balm", "balm", "balm", "incense", "seal"])
	check(not issue(captain, "pickup", {"pile":2}, 2).accepted, "another team cannot manage a hero's kit")
	check(issue(captain, "pickup", {"pile":2}).accepted, "hero takes everything that fits")
	check(Kit.pack(captain)[2].count == 3 and field.piles[2].items == ["seal"], "consumables stack to three and overflow stays in the original pile")
	check(LootView.frame_for(field.piles[2].items).texture == LootView.EQUIPMENT.seal, "partly collected satchel shows the remaining seal")
	check(not issue(captain,"pickup",{"pile":2}).accepted, "a second pickup with a full pack leaves its contents intact")
	check(not issue(captain,"activate",{"slot":1,"item":"shield"}).accepted, "unequipping into a full pack preserves the shield")
	check(issue(captain,"activate",{"slot":3,"item":"iron"}).accepted and captain.service_weapon == "iron" and Kit.at(captain,3).item == "point", "gear swaps atomically even with a full pack")
	check(not issue(captain,"drop",{"slot":3,"item":"iron"}).accepted, "repeating a stale slot action cannot remove the replacement")
	var bolt: Dictionary = world.combat_system.spawn_projectile(captain, enemy)
	var plain := bolt.duplicate()
	plain.erase("service_damage")
	check(is_equal_approx(world.combat_system._damage_at_impact(bolt, enemy) - world.combat_system._damage_at_impact(plain, enemy), 4.0), "a real missile retains the equipped bonus at release")
	check(issue(captain,"activate",{"slot":4,"item":"scales"}).accepted and is_equal_approx(Service.incoming_damage(captain, 100.0, 200), 85.0), "mail and veteran protection modify actual incoming damage")
	check(not issue(captain, "balm").accepted and Kit.at(captain,5).count == 3, "full-health hero does not waste balm")
	world.set_entity_field(captain, "hp", captain.max_hp - 5.0)
	check(issue(captain,"balm").accepted and captain.hp == captain.max_hp and Kit.at(captain,5).count == 2, "use heals up to maximum and consumes exactly one item")
	check(issue(captain,"activate",{"slot":6,"item":"incense"}).accepted and issue(captain,"ability").accepted and captain.service_ready_tick == 360, "incense restores the skill and the fibula shortens its next cooldown")
	check(issue(captain,"pickup",{"pile":2}).accepted and not field.piles.has(2), "a freed slot can collect what was left behind")
	# A new player order cancels pickup; an uninterrupted order walks through the normal mover.
	var goal := Vector2(12, 8)
	field.place(goal, ["balm"])
	var id := int(field.next_pile - 1)
	check(issue(medic,"pickup",{"pile":id}).accepted and field.pickup_orders.has(medic.id), "remote visible pickup schedules an approach")
	var stop := Commands.StopCommand.new(controller.tick_index, [int(medic.id)])
	controller.enqueue_command(stop, true, 1)
	controller.process_commands()
	check(not field.pickup_orders.has(medic.id) and field.piles.has(id), "stop cancels collection without moving goods")
	check(issue(medic,"pickup",{"pile":id}).accepted, "pickup can be retried")
	for i in 180:
		if not field.piles.has(id): break
		controller._run_fixed_tick(1, 2)
	check(not field.piles.has(id) and Kit.balm_slot(medic) >= 0 and Vector2(medic.pos).distance_to(goal) <= field.REACH, "walking hero collects on arrival within physical reach")
	var property := Kit.carried(captain)
	world.begin_entity_death(captain, {"team":2, "entity_id":enemy.id})
	var total := 0
	for pile in field.piles.values():
		if Vector2(pile.pos).distance_to(captain.pos) < 1: total += pile.items.size()
	check(total == property.size() + 1 and not field.hero_ids.has(captain.id), "hero death releases the entire kit and one rare trophy")
	var before: Dictionary = field.capture()
	world.begin_entity_death(captain, {"team":2, "entity_id":enemy.id})
	check(before == field.capture(), "repeated death resolution cannot duplicate gear")
	test_open_battle(catalog)
	test_building_trophies(catalog)
	print("Expedition equipment, abilities, progression, fog and pickup orders: %d failures" % failures)
	quit(1 if failures else 0)

func test_open_battle(catalog) -> void:
	make_field(catalog)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(6, 6), false)
	var infantry: Dictionary = world.add_unit(1, "swordsman", Vector2(8, 6), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(10, 6), false)
	world.add_unit(2, "clubman", Vector2(35, 35), false)
	# The record from the previous version held just one shield.
	Service.inherit_service(world, archer, {"role":"scout","name":"Лучник","xp":36000,"item":"shield"})
	check(Kit.at(archer,1).get("item") == "shield" and Kit.at(archer,3).is_empty(), "legacy commander has the old shield and four usable empty pack slots")
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	var fighters: Array[int] = [int(archer.id), int(infantry.id)]
	var attack := Commands.AttackCommand.new(0, fighters, int(target.id))
	controller.enqueue_command(attack, true, 1)
	controller.process_commands()
	check(controller.get_command_result(attack.sequence_id).accepted, "ordinary player attack starts the field encounter")
	for i in 750:
		if target.hp <= 0: break
		controller._run_fixed_tick(1, 2)
	check(target.hp <= 0 and world.expedition_field.piles.has(1), "live attacks and projectiles kill the target and generate a coffer")
	check(archer.service_xp > Service.VETERAN or infantry.service_xp > 0, "ordinary combat awards experience to participating troops")
	if not world.expedition_field.piles.has(1): return
	check(issue(archer, "pickup", {"pile":1}).accepted, "surviving hero can approach the actual casualty's loot")
	for i in 240:
		if not world.expedition_field.piles.has(1): break
		controller._run_fixed_tick(1, 2)
	check(archer.get("service_weapon") == "point" and Kit.balm_slot(archer) >= 0, "natural battle finishes with equipped loot and a packed consumable")

func test_building_trophies(catalog) -> void:
	make_field(catalog)
	var field = world.expedition_field
	var hero: Dictionary = world.add_unit(1, "swordsman", Vector2(11, 14), false)
	Service.inherit_service(world, hero, {"role":"captain", "name":"Марк", "xp":Service.VETERAN})
	var attacker: Dictionary = world.combat_source_context(hero)
	var town: Dictionary = world.add_building(301, "town_center", Vector2(12, 10), 2)
	var wonder: Dictionary = world.add_building(302, "wonder", Vector2(23, 20), 2)
	world.update_fog_of_war()
	world.combat_system._apply_impact_damage(town, town.max_hp + 1.0, attacker, -1, 1)
	if not field.piles.has(1):
		check(false, "enemy town center leaves loot on the lethal hit")
		return
	var city_cache: Dictionary = field.piles[1]
	check(city_cache.get("coffer", false) and city_cache.items.size() == 2 and city_cache.items[0] in field.TOWN_GEAR and city_cache.items[1] == "balm", "town center leaves equipment and balm")
	world.begin_entity_death(town, attacker)
	check(city_cache.items.size() == 2 and field.piles.size() == 1, "a second destruction notification cannot duplicate the city reward")
	check(issue(hero, "pickup", {"pile":1}).accepted, "commander accepts the pickup order on cleared city ruins")
	for i in 200:
		if not field.piles.has(1): break
		controller._run_fixed_tick(1, 2)
	check(not field.piles.has(1) and city_cache.items[0] in Kit.carried(hero) and Kit.balm_slot(hero) >= 0, "the city coffer can be reached and emptied")

	world.combat_system._apply_impact_damage(wonder, wonder.max_hp + 1.0, attacker, -1, 1)
	if not field.piles.has(2):
		check(false, "enemy wonder leaves a coffer")
		return
	var treasury: Dictionary = field.piles[2]
	var goods: Array = treasury.items.duplicate()
	check(treasury.get("coffer", false) and goods.size() == 3 and goods[0] in field.RARE and goods[1] in field.RARE and goods[0] != goods[1] and goods[2] == "incense", "wonder holds two different rare items and incense")
	check(not world.victory_objectives.any(func(o): return o.get("category") == "artifact"), "a trophy coffer creates no victory artifact")
	var collector: Dictionary = world.add_unit(1, "archer", treasury.pos, false)
	Service.inherit_service(world, collector, {"role":"scout", "name":"Луций", "xp":Service.VETERAN})
	var full_pack := [{"item":"balm", "count":3}, {"item":"balm", "count":3}, {"item":"balm", "count":3}, {"item":"balm", "count":3}]
	world.set_entity_field(collector, "service_pack", full_pack)
	world.update_fog_of_war()
	check(issue(collector, "pickup", {"pile":2}).accepted and treasury.items == ["incense"] and treasury.coffer, "a partly emptied wonder coffer retains its form and remaining supplies")
	var chest := LootView.frame_for(treasury.items, treasury.coffer)
	check(chest.texture != LootView.SUPPLIES and chest.texture.get_image().get_used_rect().size.x == 24, "the stripped reliquary has its own 24-pixel silhouette")
	field.place(treasury.pos, ["balm"])
	check(field.piles.size() == 1 and treasury.items == ["incense", "balm"] and treasury.coffer, "nearby field loot merges into the existing coffer")

	world.begin_entity_death(world.add_building(303, "house", Vector2(8, 20), 2), attacker)
	world.begin_entity_death(world.add_building(304, "wonder", Vector2(8, 27), 2, false), attacker)
	world.begin_entity_death(world.add_building(305, "town_center", Vector2(14, 27), 1), {"reason":"delete_entity"})
	var allied: Dictionary = world.add_building(306, "wonder", Vector2(21, 29), 3)
	world.player_registry.set_mutual_relation(1, 3, "ally")
	world.begin_entity_death(allied, attacker)
	world.field_service_enabled = false
	world.begin_entity_death(world.add_building(307, "town_center", Vector2(31, 29), 2), attacker)
	check(field.piles.size() == 1 and field.next_pile == 3, "ordinary buildings, foundations, demolition, allies and classic matches produce no coffer")
