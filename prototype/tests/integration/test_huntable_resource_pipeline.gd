extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_source_contract(catalog)
	verify_hunter_to_carcass_pipeline(catalog)
	verify_military_kill_leaves_no_food(catalog)
	verify_carcass_decay(catalog)
	verify_huntable_reactions(catalog)
	verify_predator_command_and_carcass_pipeline(catalog)
	if failures.is_empty():
		print("I12-008 huntable resource pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_source_contract(catalog) -> void:
	var world = configured_world(catalog)
	var gazelle: Dictionary = world.add_unit(0, "gazelle", Vector2(10.0, 10.0), false)
	var elephant: Dictionary = world.add_unit(0, "elephant", Vector2(14.0, 10.0), false)
	var alligator: Dictionary = world.add_unit(0, "alligator", Vector2(18.0, 10.0), false)
	var lion: Dictionary = world.add_unit(0, "lion", Vector2(22.0, 10.0), false)
	assert_equal(gazelle.get("source_unit_id"), 65, "Gazelle keeps source identity")
	assert_equal(gazelle.get("max_hp"), 8.0, "Gazelle uses source health")
	assert_equal(gazelle.get("speed"), 1.100000023841858, "Gazelle uses source speed")
	assert_equal(elephant.get("source_unit_id"), 48, "Elephant keeps source identity")
	assert_equal(elephant.get("max_hp"), 45.0, "Elephant uses source health")
	assert_equal(elephant.get("attack_damage"), 10.0, "Elephant uses source attack")
	assert_equal(alligator.get("source_unit_id"), 1, "Alligator keeps source identity")
	assert_equal(alligator.get("max_hp"), 20.0, "Alligator uses source health")
	assert_equal(alligator.get("attack_damage"), 4.0, "Alligator uses source attack class amount")
	assert_equal(lion.get("source_unit_id"), 126, "Lion keeps source identity")
	assert_equal(lion.get("max_hp"), 20.0, "Lion uses source health")
	assert_equal(lion.get("attack_damage"), 2.0, "Lion uses source attack class amount")
	for state in ["idle", "move", "death"]:
		assert_equal(catalog.unit_frame_info(gazelle, state).get("asset_name"), "gazelle_%s" % state, "Gazelle %s presentation" % state)
	for state in ["idle", "move", "attack", "death"]:
		assert_equal(catalog.unit_frame_info(elephant, state).get("asset_name"), "elephant_%s" % state, "Elephant %s presentation" % state)
		assert_equal(catalog.unit_frame_info(alligator, state).get("asset_name"), "alligator_%s" % state, "Alligator %s presentation" % state)
		assert_equal(catalog.unit_frame_info(lion, state).get("asset_name"), "lion_%s" % state, "Lion %s presentation" % state)


func verify_hunter_to_carcass_pipeline(catalog) -> void:
	var world = configured_world(catalog)
	# Keep the drop site clear of the Hunter's initial mobile footprint. The
	# original Granary occupies several navigation cells around its anchor.
	# Original Hunter 122 deposits hunted food at Town Center 109 or
	# Storage Pit 103. Granary 68 belongs to the Forager/Farmer line.
	world.add_building(900, "storage_pit", Vector2(4.0, 8.0), 1)
	world.add_unit(2, "clubman", Vector2(28.0, 28.0), false)
	var hunter: Dictionary = world.add_unit(1, "villager", Vector2(8.0, 8.0), false)
	var gazelle: Dictionary = world.add_unit(0, "gazelle", Vector2(11.5, 8.0), false)
	var food_before: int = world.get_resource_amount(1, 0)
	assert_true(world.assign_command_attack([hunter], int(gazelle["id"])), "worker can issue ordinary attack against huntable")
	assert_equal(hunter.get("worker_role_source_unit_id"), 122, "worker enters original Hunter task form")
	assert_equal(hunter.get("projectile_id"), 100, "Hunter uses original spear projectile")
	assert_equal(hunter.get("attack_range"), 4.0, "Hunter uses source attack range")
	var hunter_view: Dictionary = hunter.duplicate(true)
	hunter_view["anim_state"] = AnimationController.ATTACK_WINDUP
	var attack_state: String = catalog.unit_presentation_state(hunter_view, "attack")
	assert_equal(attack_state, "hunter_attack", "task role maps combat state to Hunter attack")
	assert_equal(catalog.unit_frame_info(hunter_view, attack_state).get("asset_name"), "hunter_attack", "Hunter attack asset is loadable")
	var spear_stub := {"projectile_unit_id": 100, "pos": Vector2.ZERO, "target_position": Vector2.RIGHT, "elapsed": 0.0}
	assert_equal(catalog.projectile_frame_info(spear_stub).get("asset_name"), "hunter_spear", "Hunter spear uses source-aware projectile registry")

	var carcass: Variant = null
	for unused in range(1800):
		world.advance(0.05, 1, 2)
		var carcasses: Array = world.get_resources().filter(func(resource): return String(resource.get("kind", "")) == "gazelle_carcass")
		if not carcasses.is_empty():
			carcass = carcasses[0]
			break
	assert_true(carcass != null, "dead Gazelle becomes a gatherable carcass after death animation (hp=%.2f death=%s gazelle_task=%s hunter_task=%s hunter_reason=%s gazelle_pos=%s hunter_pos=%s projectiles=%d)" % [float(gazelle.get("hp", -1.0)), String(gazelle.get("death_phase", "")), String(gazelle.get("task", "")), String(hunter.get("task", "")), String(hunter.get("diagnostic_reason", "")), gazelle.get("pos", Vector2.ZERO), hunter.get("pos", Vector2.ZERO), world.get_projectiles().size()])
	if carcass == null:
		return
	assert_equal(carcass.get("source_unit_id"), 262, "carcass keeps original dead-unit identity")
	assert_equal(carcass.get("origin_source_unit_id"), 65, "carcass records originating huntable")
	assert_true(int(carcass.get("amount", 0)) <= 150 and int(carcass.get("amount", 0)) > 0, "Gazelle exposes original 150-food harvest pool")
	assert_equal(carcass.get("resource_type_id"), 0, "carcass maps to food stockpile")
	assert_equal(catalog.resource_frame_info(carcass).get("asset_name"), "gazelle_carcass", "carcass uses original source presentation")
	assert_equal(hunter.get("task"), "gather", "Hunter automatically continues from kill to carcass gathering")
	assert_equal(hunter.get("resource_id"), carcass.get("id"), "continued gather targets spawned carcass")
	assert_equal(hunter.get("worker_role_source_unit_id"), 122, "Hunter task identity persists while gathering carcass")

	# Source Hunter 122 gathers at 0.45 work/second; allow the full original
	# ten-food load plus the return trip instead of placeholder-worker timing.
	for unused in range(1800):
		world.advance(0.05, 1, 2)
		if int(hunter.get("deposit_cycles", 0)) > 0:
			break
	var hunter_context := "task=%s stage=%s carried=%.2f capacity=%.2f dropoff=%s pos=%s destination=%s reason=%s" % [
		String(hunter.get("task", "")),
		String(hunter.get("gather_stage", "")),
		float(hunter.get("carried_amount", 0.0)),
		float(hunter.get("carry_capacity", 0.0)),
		str(hunter.get("dropoff_id", -1)),
		str(hunter.get("pos", Vector2.ZERO)),
		str(hunter.get("dropoff_position", null)),
		String(hunter.get("diagnostic_reason", "")),
	]
	assert_true(int(hunter.get("deposit_cycles", 0)) > 0, "Hunter carries hunted food to a normal drop site (%s)" % hunter_context)
	assert_true(world.get_resource_amount(1, 0) > food_before, "hunted food reaches authoritative stockpile (%s)" % hunter_context)


func verify_military_kill_leaves_no_food(catalog) -> void:
	var world = configured_world(catalog)
	var soldier: Dictionary = world.add_unit(1, "clubman", Vector2(8.0, 8.0), false)
	var gazelle: Dictionary = world.add_unit(0, "gazelle", Vector2(8.6, 8.0), false)
	gazelle["hp"] = 1.0
	assert_true(world.assign_command_attack([soldier], int(gazelle["id"])), "military unit can attack a huntable")
	for unused in range(400):
		world.advance(0.05, 1, 2)
		if String(gazelle.get("death_phase", "alive")) != "alive":
			break
	assert_true(float(gazelle.get("hp", 1.0)) <= 0.0, "military attack kills the huntable")
	assert_equal(gazelle.get("killed_by_worker"), false, "killing blow records a non-worker source")
	for unused in range(400):
		world.advance(0.05, 1, 2)
		if bool(gazelle.get("huntable_death_resolved", false)):
			break
	var carcasses: Array = world.get_resources().filter(func(resource): return String(resource.get("kind", "")) == "gazelle_carcass")
	assert_equal(carcasses.size(), 0, "military-killed huntable leaves no gatherable food")


func verify_carcass_decay(catalog) -> void:
	var world = configured_world(catalog)
	var carcass: Dictionary = world.add_resource("gazelle_carcass", Vector2(8.0, 8.0), 10)
	world.advance_resource_lifecycle(10.0)
	assert_equal(carcass.get("amount"), 7, "Gazelle carcass decays at original 0.3 food per second")
	world.advance_resource_lifecycle(1.0)
	assert_equal(carcass.get("amount"), 7, "fractional decay is accumulated deterministically")
	world.advance_resource_lifecycle(3.0)
	assert_equal(carcass.get("amount"), 6, "accumulated decay eventually removes one food")


func verify_huntable_reactions(catalog) -> void:
	var world = configured_world(catalog)
	var hunter: Dictionary = world.add_unit(1, "villager", Vector2(8.0, 8.0), false)
	var gazelle: Dictionary = world.add_unit(0, "gazelle", Vector2(10.0, 8.0), false)
	gazelle["retaliation_target_id"] = int(hunter["id"])
	world.update_units(0.05, 1, 2)
	assert_equal(gazelle.get("task"), "move", "Gazelle uses declared flee reaction")
	assert_equal(gazelle.get("diagnostic_reason"), "huntable_flee", "flee reaction remains observable")
	var elephant: Dictionary = world.add_unit(0, "elephant", Vector2(14.0, 8.0), false)
	elephant["retaliation_target_id"] = int(hunter["id"])
	world.update_units(0.05, 1, 2)
	assert_equal(elephant.get("task"), "attack", "Elephant uses declared retaliation reaction")
	assert_equal(elephant.get("target_id"), hunter.get("id"), "Elephant retaliates against actual attacker")


func verify_predator_command_and_carcass_pipeline(catalog) -> void:
	var world = configured_world(catalog)
	var lion: Dictionary = world.add_unit(0, "lion", Vector2(10.0, 10.0), false)
	var villager: Dictionary = world.add_unit(1, "villager", Vector2(12.0, 10.0), false)
	world.add_unit(2, "clubman", Vector2(28.0, 28.0), false)
	var controller = GameController.new(world)
	controller.advance_frame(0.05, 1, 2)
	assert_equal(lion.get("task"), "attack", "wildlife system issues an ordinary attack command for a nearby source predator")
	assert_equal(lion.get("target_id"), villager.get("id"), "source predator selects the nearest living non-Gaia unit")
	assert_true(bool(lion.get("attack_autonomous", false)), "predator attack retains an authoritative autonomous leash")
	lion["hp"] = 0.0
	world.begin_entity_death(lion, world.combat_source_context(villager))
	world.advance_death_only(10.0)
	var carcasses: Array = world.get_resources().filter(func(resource): return String(resource.get("kind", "")) == "lion_carcass")
	assert_equal(carcasses.size(), 1, "dead Lion becomes one gatherable source carcass")
	if carcasses.is_empty():
		return
	var carcass: Dictionary = carcasses[0]
	assert_equal(carcass.get("source_unit_id"), 369, "Lion carcass keeps original dead-unit identity")
	assert_equal(carcass.get("amount"), 100, "Lion exposes its original living food capacity")
	assert_equal(catalog.resource_frame_info(carcass).get("asset_name"), "lion_carcass", "Lion carcass uses its original source presentation")


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
