extends RefCounted

const RenderItem := preload("res://scripts/render_item.gd")
const HOTSPOT := Vector2(16, 17)
const HIT_AREA := Rect2(-22, -22, 44, 32)
# At the same ground anchor, Genie draws a corpse on graphic layer 10 and a standing soldier on 20.
const GROUND_SUB_ORDER := 15_000
const SUPPLIES := preload("res://assets/expedition/loot/supplies.png")
# Body outline in the existing NE-facing neutral artifact frame, above the cart and its shafts.
const COFFER_SOURCE := "res://assets/generated/artifact_neutral_01.png"
const COFFER_BODY := [
	Vector2(13, 12), Vector2(32, 2), Vector2(43, 6), Vector2(43, 16),
	Vector2(22, 27), Vector2(13, 22),
]
# Largest recognizable silhouette first, independent of the order of drops.
const EQUIPMENT := {
	"shield": preload("res://assets/expedition/loot/shield.png"),
	"scales": preload("res://assets/expedition/loot/scales.png"),
	"iron": preload("res://assets/expedition/loot/iron.png"),
	"point": preload("res://assets/expedition/loot/point.png"),
	"fibula": preload("res://assets/expedition/loot/fibula.png"),
	"seal": preload("res://assets/expedition/loot/seal.png"),
}

static var _coffer_art: Texture2D
static var _coffer_loaded := false

static func coffer_texture() -> Texture2D:
	if _coffer_loaded: return _coffer_art
	_coffer_loaded = true
	if not ResourceLoader.exists(COFFER_SOURCE): return null
	var source := load(COFFER_SOURCE) as Texture2D
	var pixels := source.get_image() if source != null else null
	if pixels == null or (pixels.is_compressed() and pixels.decompress() != OK): return null
	var bounds := Rect2i(13, 2, 30, 25)
	var body := pixels.get_region(bounds)
	body.convert(Image.FORMAT_RGBA8)
	var outline := PackedVector2Array(COFFER_BODY)
	for y in body.get_height():
		for x in body.get_width():
			var center := Vector2(bounds.position + Vector2i(x, y)) + Vector2(0.5, 0.5)
			if not Geometry2D.is_point_in_polygon(center, outline):
				body.set_pixel(x, y, Color.TRANSPARENT)
	body.resize(24, 20, Image.INTERPOLATE_NEAREST)
	var sprite := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	sprite.blit_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), Vector2i(4, 2))
	_coffer_art = ImageTexture.create_from_image(sprite)
	_coffer_art.set_meta("ror_immutable_sprite", true)
	return _coffer_art

static func frame_for(items: Array, coffer: bool = false) -> Dictionary:
	if coffer and coffer_texture() != null:
		return {"texture": _coffer_art, "hotspot": HOTSPOT, "asset_name": "expedition_coffer"}
	var texture := SUPPLIES
	for item in EQUIPMENT:
		if item in items:
			texture = EQUIPMENT[item]
			break
	return {"texture": texture, "hotspot": HOTSPOT, "asset_name": "expedition_loot"}

static func pile_at(game, screen: Vector2) -> Dictionary:
	var candidates := {}
	var zoom := float(game.view_zoom)
	for pile in game.presentation_snapshot.get("player_state", {}).get("service_loot", []):
		var local := (screen - Vector2(game.world_to_screen(pile.pos)).round()) / zoom
		if HIT_AREA.has_point(local):
			candidates[pile.id] = local.distance_squared_to(HIT_AREA.get_center())
	if candidates.is_empty():
		return {}

	var nearest := {}
	var distance := INF
	var drawables: Array = game.current_world_drawables()
	var project := Callable(game, "world_to_screen")
	for index in range(drawables.size() - 1, -1, -1):
		var drawable: Dictionary = drawables[index]
		if drawable.layer < RenderItem.Layer.UNIT_BUILDING:
			break
		if drawable.kind == "field_loot":
			if not candidates.has(drawable.stable_id):
				continue
			if game.picking_service.texture_hit(screen, drawable, project, zoom):
				return drawable.data
			var d: float = candidates[drawable.stable_id]
			if d < distance:
				nearest = drawable.data
				distance = d
		elif drawable.kind in ["unit", "unit_part", "building", "building_part", "resource", "environment"]:
			if drawable.kind in ["unit", "unit_part", "building", "building_part"] and float(drawable.data.get("hp", 1.0)) <= 0.0:
				continue
			if drawable.has("sprite_command") and not Rect2(drawable.sprite_command[1]).abs().has_point(screen):
				continue
			if game.picking_service.texture_hit(screen, drawable, project, zoom, true):
				# Leave an order on visible scenery or a soldier to the normal picker.
				return {}
	return nearest
