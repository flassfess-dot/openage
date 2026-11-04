extends "res://tests/integration/test_worker_regressions.gd"
func _initialize() -> void:
	var catalog=Catalog.new(); catalog.load()
	var world=configured(catalog)
	world.grant_technology(1,101); world.add_building(901,"market",Vector2(6,16),1)
	world.add_unit(1,"villager",Vector2(17,14),false); world.add_unit(1,"villager",Vector2(22,14),false)
	var foundation=world.place_foundation(1,"farm",Vector2(18,17))
	print("FARM ",foundation.get("footprint",{})," center=",foundation.get("pos"))
	for point in [Vector2(21,17),Vector2(18,20)]:
		print("PLACEMENT ",point," legal=",world.can_place_foundation(1,"farm",point)," reason=",world.last_build_failure," footprint=",load("res://scripts/footprint.gd").building(world.unit_stats("farm"),point))
	quit(0)
