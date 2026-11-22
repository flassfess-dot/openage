extends RefCounted

const PlayerPalette := preload("res://scripts/player_palette.gd")
const GOLD := Color("ecc779")
const BRONZE := Color("ab8045")
const LIGHT := Color("fff0c4")
const HERO_FIGURE_SCALE := 1.10
const SHIELD_SIZE := Vector2i(7, 7)
# At native zoom the selection health bar starts five pixels above the sprite.
const SHIELD_HEAD_GAP := 6.0
const SHIELD_PIXELS := [
	"aggggga",
	"ghbbbga",
	"gbBBBgD",
	"gbBBBgD",
	".gbBgD.",
	"..ggD..",
	"...D...",
]
static var shield_textures: Dictionary[int, Texture2D] = {}

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

static func shield_rect(actor: Dictionary, zoom: float) -> Rect2:
	var height := Vector2(actor.hotspot).y * HERO_FIGURE_SCALE
	var offset := Vector2(-floorf(SHIELD_SIZE.x * 0.5), -height - SHIELD_HEAD_GAP - SHIELD_SIZE.y)
	var origin := (Vector2(actor.screen_position).round() + offset * zoom).round()
	return Rect2(origin, Vector2(SHIELD_SIZE) * zoom)

static func shield_texture(color_index: int) -> Texture2D:
	if not shield_textures.has(color_index):
		var colors := {
			"a": Color("ac814a"), "g": Color("cdab6a"), "h": Color("f3dea5"), "D": Color("342c24"),
			"b": PlayerPalette.shade(color_index, 3), "B": PlayerPalette.shade(color_index, 6),
		}
		var image := Image.create_empty(SHIELD_SIZE.x, SHIELD_SIZE.y, false, Image.FORMAT_RGBA8)
		for y in SHIELD_SIZE.y:
			for x in SHIELD_SIZE.x:
				var pixel: String = SHIELD_PIXELS[y][x]
				if pixel != ".":
					image.set_pixel(x, y, colors[pixel])
		shield_textures[color_index] = ImageTexture.create_from_image(image)
	return shield_textures[color_index]

static func draw_hero_shields(game, state: Dictionary) -> void:
	var clip: Rect2 = game.get_viewport_rect()
	var zoom := float(game.view_zoom)
	for hero in state.get("service_heroes", []):
		var actor: Dictionary = game.expedition_actor_items.get(hero.id, {})
		if hero.carrier >= 0 or actor.is_empty() or actor.frame_info.get("texture") == null: continue
		var rect := shield_rect(actor, zoom)
		if clip.intersects(rect):
			var color_index: int = game.resource_catalog.player_palette.color_index(int(hero.team))
			game.draw_texture_rect(shield_texture(color_index), rect, false)

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
	var coffer: bool = pile.get("coffer", false)
	if coffer: names.append("Трофейный ларец")
	for item in grouped:
		var label := String(preload("res://scripts/expedition_inventory.gd").ITEMS[item].name)
		if grouped[item] > 1: label += " ×%d" % grouped[item]
		names.append(label)
	var font := preload("res://scripts/hud_typography.gd").body_font()
	var width := 0.0
	for line in names: width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	var size := Vector2(width + 16, names.size() * 17 + 8)
	var origin := (position - Vector2(size.x * 0.5, size.y + 5)).round()
	origin.x = clampf(origin.x, 1, game.get_viewport_rect().size.x - size.x - 1)
	origin.y = maxf(game.hud_top_height(), origin.y)
	game.draw_rect(Rect2(origin, size), Color("29251ef5"))
	game.draw_rect(Rect2(origin, size), BRONZE, false, 1)
	for i in names.size():
		var color := GOLD if coffer and i == 0 else LIGHT
		game.draw_string(font, origin + Vector2(8, 16 + i * 17), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
