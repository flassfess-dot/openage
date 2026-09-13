class_name RoRCompositeGraphic


static func delta_visible(display_angle: int, logical_facing: int, angle_count: int) -> bool:
	return display_angle < 0 or display_angle == posmod(logical_facing, maxi(1, angle_count))


static func construction_stage(progress: float, stage_count: int) -> int:
	if stage_count <= 1:
		return 0
	return mini(stage_count - 1, floori(clampf(progress, 0.0, 1.0) * float(stage_count)))


static func damage_state(hit_point_ratio: float) -> String:
	if hit_point_ratio <= 0.0:
		return "destroyed"
	if hit_point_ratio <= 0.25:
		return "critical"
	if hit_point_ratio <= 0.5:
		return "damaged"
	return "intact"


static func effect_kinds(hit_point_ratio: float) -> Array[String]:
	match damage_state(hit_point_ratio):
		"critical": return ["smoke", "fire"]
		"damaged": return ["smoke"]
		_: return []
