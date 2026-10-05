class_name RoRNavigationPreparationTask
extends RefCounted

const NavigationData := preload("res://scripts/navigation_task_data.gd")

static func run(input: Dictionary) -> Dictionary:
	var grid = NavigationData.create_grid(input["grid"])
	var domain := String(input["domain"])
	var restriction := int(input["restriction"])
	var mask: PackedByteArray = grid.native_walkability_mask(domain, restriction)
	var native_components: Array = []
	if ClassDB.class_exists("RoRPathKernel"):
		var kernel = ClassDB.instantiate("RoRPathKernel")
		kernel.configure(grid.size.x, grid.size.y, grid.revision, mask)
		for radius in input.get("radii", [0.0]):
			native_components.append({"radius": radius, "labels": kernel.connectivity_labels(float(radius))})
	return {"key": "%s:%d" % [domain, restriction], "revision": grid.revision, "surface_revision": grid.surface_revision, "mask": mask, "components": grid._build_surface_components(domain, restriction), "native_components": native_components}
