extends RefCounted

static func project(projectile: Dictionary, observer: int) -> Dictionary:
	var result: Dictionary = {}
	for field in ["id","team","pos","previous_pos","speed","blast_range","radius"]:
		if projectile.has(field): result[field] = projectile[field]
	result["velocity"] = (Vector2(projectile.get("pos",Vector2.ZERO))-Vector2(projectile.get("previous_pos",projectile.get("pos",Vector2.ZERO))))*20.0
	# A launcher's own target is known. Foreign aim, accuracy roll and eventual
	# damage/hit are deliberately excluded even when the projectile is visible.
	if int(projectile.get("team",0)) == observer:
		for field in ["source_id","target_id","base_damage"]:
			if projectile.has(field): result[field] = projectile[field]
	return result

static func select_visible(projectiles: Array, units: Array, observer: int, maximum: int=1024) -> Array:
	if projectiles.size()<=maximum: return projectiles
	# Bound attention by proximity to our troops, rather than by projectile ID.
	# Old shells about to land must retain priority over newly launched arrows.
	var occupied: Dictionary={}
	for unit in units:
		if int(unit.get("team",0))==observer: occupied[Vector2i((Vector2(unit.get("pos",Vector2.ZERO))/4.0).floor())]=true
	var ranked: Array=[]
	for projectile in projectiles:
		var position:=Vector2(projectile.get("pos",Vector2.ZERO))
		var predicted:=position+Vector2(projectile.get("velocity",Vector2.ZERO))*0.25
		var proximity:=10000.0
		for point in [position,predicted]:
			var cell:=Vector2i((Vector2(point)/4.0).floor())
			for y in range(-2,3):
				for x in range(-2,3):
					var neighbor:=cell+Vector2i(x,y)
					if occupied.has(neighbor): proximity=minf(proximity,Vector2(point).distance_squared_to((Vector2(neighbor)+Vector2(0.5,0.5))*4.0))
		var priority:=proximity+(8.0 if int(projectile.get("team",0))==observer else 0.0)
		ranked.append({"projectile":projectile,"priority":priority})
	ranked.sort_custom(func(a,b): return float(a["priority"])<float(b["priority"]) if not is_equal_approx(float(a["priority"]),float(b["priority"])) else int(a["projectile"].get("id",0))<int(b["projectile"].get("id",0)))
	return ranked.slice(0,maximum).map(func(row): return row["projectile"])
