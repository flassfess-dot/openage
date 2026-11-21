extends RefCounted

const EDGE := Color("32251c")
const GOLD := Color("ecc779")
const BRONZE := Color("ab8045")
const LIGHT := Color("fff0c4")
const HERO_FIGURE_SCALE := 1.10

static func hero_frame(source: Dictionary) -> Dictionary:
	# Pose descriptors and textures can be shared with an ordinary soldier.
	var frame := source.duplicate()
	frame["figure_scale"] = HERO_FIGURE_SCALE
	if source.has("composite_parts"):
		var parts := []
		for part in source["composite_parts"]:
			parts.append(hero_frame(part))
		frame["composite_parts"] = parts
	return frame

static func banner_position(actor: Dictionary, zoom: float) -> Vector2:
	var height := clampf(Vector2(actor.hotspot).y, 28.0, 62.0)
	var shoulder := Vector2(11, -height * HERO_FIGURE_SCALE) * zoom
	return (Vector2(actor.screen_position).round() + shoulder).round()

static func pile_at(game, screen: Vector2) -> Dictionary:
	var nearest := {}
	var distance := INF
	var scale: float = clampf(game.view_zoom, 0.8, 2.5)
	for pile in game.presentation_snapshot.get("player_state", {}).get("service_loot", []):
		var delta := screen - Vector2(game.world_to_screen(pile.pos)) + Vector2(0, 6) * scale
		var d := delta.length_squared()
		if absf(delta.x) <= 12 * scale and absf(delta.y) <= 10 * scale and d < distance:
			nearest = pile
			distance = d
	return nearest

static func draw_field(game, state: Dictionary) -> void:
	var clip: Rect2 = game.get_viewport_rect().grow(50.0)
	var zoom := float(game.view_zoom)
	var scale := clampf(zoom, 0.8, 2.5)
	for pile in state.get("service_loot", []):
		var ground := Vector2(game.world_to_screen(pile.pos)).round()
		if not clip.has_point(ground): continue
		game.draw_set_transform(ground, 0, Vector2.ONE * scale)
		# Low isometric coffer with a leather lid, two bronze bands and a clasp.
		polygon(game, [-10,-3, 0,-9, 11,-4, 11,0, 0,5, -10,1], Color("302616"))
		polygon(game, [-9,-8, 0,-12, 10,-8, 1,-3], Color("dbab67"))
		polygon(game, [-9,-8, 1,-3, 1,3, -9,-1], Color("946037"))
		polygon(game, [1,-3, 10,-8, 10,-2, 1,3], Color("60442c"))
		for offset in [0, 10]:
			game.draw_line(Vector2(-7+offset*0.5,-7+offset*0.23), Vector2(1+offset*0.5,-11+offset*0.23), BRONZE, 2)
		game.draw_rect(Rect2(0,-4,3,4), GOLD)
		game.draw_line(Vector2(-4,-10), Vector2(0,-12), LIGHT)
		game.draw_set_transform(Vector2.ZERO)
	for hero in state.get("service_heroes", []):
		var actor: Dictionary = game.expedition_actor_items.get(hero.id, {})
		if actor.is_empty() or hero.carrier >= 0: continue
		var shoulder := banner_position(actor, zoom)
		if not clip.has_point(shoulder): continue
		game.draw_set_transform(shoulder, 0, Vector2.ONE * scale)
		var cloth: Color = game.resource_catalog.player_palette.color_for_team(int(hero.team)).darkened(0.42)
		game.draw_line(Vector2(-5,-5), Vector2(-5,15), EDGE, 2)
		game.draw_line(Vector2(-5,-5), Vector2(-5,8), BRONZE)
		if hero.role == "captain":
			game.draw_rect(Rect2(-5,-5,14,15), EDGE)
			game.draw_rect(Rect2(-4,-4,12,13), GOLD)
			game.draw_rect(Rect2(-3,-3,10,10), cloth)
			for x in [-3,1,5]: game.draw_rect(Rect2(x,9,2,3), BRONZE)
		elif hero.role == "scout":
			polygon(game, [-5,-5, 13,-3, 6,1, 10,4, -5,7], EDGE)
			polygon(game, [-4,-4, 10,-3, 4,1, 7,3, -4,6], cloth)
			game.draw_line(Vector2(-4,-4), Vector2(11,-3), GOLD)
		else:
			polygon(game, [-5,-5, 8,-5, 8,5, 2,10, -5,6], EDGE)
			polygon(game, [-4,-4, 7,-4, 7,4, 2,8, -4,5], LIGHT)
			polygon(game, [-3,-3, 6,-3, 6,3, 2,6, -3,4], cloth)
		match hero.role:
			"captain": polygon(game, [-2,-1, 0,0, 2,-2, 4,0, 6,-1, 5,3, -1,3], LIGHT)
			"scout":
				polygon(game, [-2,3, 0,0, 6,-2, 4,1, 2,3], LIGHT)
				game.draw_line(Vector2(-1,4), Vector2(4,0), GOLD)
			"medic":
				polygon(game, [-2,0, 6,0, 4,3, 0,3], LIGHT)
				game.draw_line(Vector2(2,2), Vector2(2,5), GOLD)
		game.draw_set_transform(Vector2.ZERO)

static func polygon(canvas: CanvasItem, coordinates: Array, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(0, coordinates.size(), 2): points.append(Vector2(coordinates[i], coordinates[i+1]))
	canvas.draw_colored_polygon(points, color)

static func draw_pulses(game, pulses: Array, tick: int) -> void:
	for i in range(pulses.size() - 1, -1, -1):
		var pulse: Dictionary = pulses[i]
		var t := float(tick - int(pulse.tick)) / 18.0
		if t >= 1 or t < 0:
			pulses.remove_at(i)
			continue
		var color := LIGHT if pulse.role == "medic" else GOLD
		color.a = 0.8 * (1.0 - t)
		var ring := PackedVector2Array()
		var radius := float(pulse.radius) * (0.25 + 0.75 * t)
		for step in 49:
			ring.append(game.world_to_screen(Vector2(pulse.pos) + Vector2.RIGHT.rotated(TAU * step / 48.0) * radius))
		game.draw_polyline(ring, color, 1.0)

static func draw_loot_label(game, position: Vector2, pile: Dictionary) -> void:
	var grouped := {}
	for item in pile.items: grouped[item] = int(grouped.get(item, 0)) + 1
	var names := PackedStringArray()
	for item in grouped:
		var label := String(preload("res://scripts/expedition_inventory.gd").ITEMS[item].name)
		if grouped[item] > 1: label += " ×%d" % grouped[item]
		names.append(label)
	var font := preload("res://scripts/hud_typography.gd").body_font()
	var width := 0.0
	for line in names: width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	var size := Vector2(width + 16, names.size() * 17 + 8)
	var origin := (position - Vector2(size.x * 0.5, size.y + 16)).round()
	origin.x = clampf(origin.x, 1, game.get_viewport_rect().size.x - size.x - 1)
	origin.y = maxf(game.hud_top_height(), origin.y)
	game.draw_rect(Rect2(origin, size), Color("29251ef5"))
	game.draw_rect(Rect2(origin, size), BRONZE, false, 1)
	for i in names.size():
		game.draw_string(font, origin + Vector2(8, 16 + i * 17), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LIGHT)
