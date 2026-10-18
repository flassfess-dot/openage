extends SceneTree
const Footprint := preload("res://scripts/footprint.gd")
var failures := 0
func _initialize() -> void:
	var kernel: Variant = ClassDB.instantiate("RoRReadModelKernel")
	var rng := RandomNumberGenerator.new()
	rng.seed = 19980318
	for iteration in range(200):
		var centers := PackedVector2Array()
		var halves := PackedVector2Array()
		var cells: Array = []
		var ids: Array = []
		for i in range(25):
			var center := Vector2(rng.randf_range(0,25),rng.randf_range(0,25))
			var half := Vector2(rng.randf_range(0.5,3),rng.randf_range(0.5,3))
			centers.append(center); halves.append(half); cells.append(Footprint.occupied_cells(center,half)); ids.append(i)
		var position := Vector2(rng.randf_range(0,25),rng.randf_range(0,25))
		var footprint := Footprint.building({"footprint_radius":[rng.randf_range(0.5,2),rng.randf_range(0.5,2)]},position)
		var replaced := {iteration % 25:true}
		var expected := false
		var half: Vector2 = footprint.obstruction_half_size
		for i in range(centers.size()):
			if replaced.has(ids[i]): continue
			var delta := (centers[i]-position).abs()
			if delta.x < halves[i].x+half.x-0.001 and delta.y < halves[i].y+half.y-0.001: expected=true;break
			for cell in footprint.occupied_cells:
				if cell in cells[i]: expected=true;break
			if expected: break
		var actual: bool = kernel.foundation_intersects_structures(footprint,position,{"centers":centers,"halves":halves,"cells":cells,"ids":ids},replaced)
		if actual != expected: failures += 1
	print("Native foundation geometry: %d failures" % failures)
	quit(0 if failures == 0 else 1)
