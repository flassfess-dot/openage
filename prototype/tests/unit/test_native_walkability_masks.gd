extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Knowledge := preload("res://scripts/navigation_knowledge_grid.gd")
var failures := 0
func _initialize() -> void:
	if Grid.mask_kernel == null or not Grid.mask_kernel.has_method("walkability_mask"):
		push_error("Native walkability producer required");quit(1);return
	for knowledge in [false,true]:
		var grid: Variant = Knowledge.new(Vector2i(20,18)) if knowledge else Grid.new(Vector2i(20,18))
		for y in range(18):
			for x in range(20):
				var cell := Vector2i(x,y)
				grid.terrain_cells[cell] = ["grass","water","dark_water","shore","shallows","sand","forest_floor","void"][posmod(x+y,8)]
				grid.terrain_ids[cell] = [0,1,2,3,1000,1001,1002,1003,-1][posmod(x*3+y,9)]
				if (x+y)%7 == 0: grid.occupied_cells[cell] = true
				if knowledge: grid.learned[y*20+x] = 1 if (x+y)%5 else 0
		if knowledge: grid.terrain_cells.erase(Vector2i(2,3))
		for restrictions in [[],[{"accessible_damage_multiplier":[1.0,0.0,0.05,0.0500001]}]]:
			grid.terrain_restrictions = restrictions
			for domain in ["land","water","amphibious","air"]:
				for restriction in [-1,0,1,5]:
					Grid.native_masks_enabled = false
					var expected: PackedByteArray = grid.native_walkability_mask(domain,restriction)
					Grid.native_masks_enabled = true
					if grid.native_walkability_mask(domain,restriction) != expected: failures += 1;push_error("Walkability differs: knowledge="+str(knowledge)+" domain="+domain+" restriction="+str(restriction))
	print("Native walkability masks: %d failures" % failures)
	quit(0 if failures == 0 else 1)
