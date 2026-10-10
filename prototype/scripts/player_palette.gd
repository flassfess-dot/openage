class_name RoRPlayerPalette
extends RefCounted

# Original RoR JASC palette 50500, SLP player shades at 16 * player + [0..9].
const RAMPS := [[[227,247,255],[187,215,235],[147,187,215],[115,155,199],[87,123,179],[63,95,159],[39,63,143],[23,39,123],[7,15,103],[0,0,87]],[[255,239,239],[255,191,191],[255,143,143],[255,95,95],[255,47,47],[227,11,0],[199,23,0],[143,31,0],[111,11,7],[83,11,0]],[[255,255,199],[255,255,159],[255,255,0],[227,227,0],[223,207,15],[195,163,27],[163,115,23],[135,103,39],[107,75,39],[79,55,35]],[[243,219,187],[231,195,115],[207,163,67],[183,139,43],[163,115,79],[139,91,55],[115,71,39],[95,51,27],[63,55,35],[35,35,31]],[[255,219,179],[255,195,111],[251,159,31],[247,139,23],[243,119,15],[239,99,7],[207,67,0],[159,51,0],[135,43,0],[111,35,0]],[[175,207,147],[155,183,111],[139,159,79],[127,139,55],[99,123,47],[75,107,43],[55,95,39],[27,67,27],[19,51,19],[11,27,11]],[[254,254,254],[235,235,235],[219,219,219],[199,199,199],[179,179,179],[143,143,143],[107,107,107],[71,71,71],[55,55,55],[35,35,35]],[[235,255,239],[159,231,187],[95,211,159],[43,191,147],[0,171,147],[0,131,123],[0,111,107],[0,79,79],[0,63,67],[0,35,39]]]
const MAX_CACHED_TEXTURES := 4096
var colors_by_team: Dictionary = {}
var references: Dictionary = {}
var cached_textures: Dictionary = {}

func configure_players(players: Array) -> void:
	colors_by_team.clear()
	for player in players:
		var team := int(player.get("team", 0))
		if team > 0:
			colors_by_team[team] = clampi(int(player.get("color_index", team)), 1, 8)

func color_index(team: int) -> int:
	return int(colors_by_team.get(team, clampi(team, 1, 8)))

func color_for_team(team: int) -> Color:
	return shade(color_index(team), 3) if team > 0 else Color.WHITE

static func shade(player: int, index: int) -> Color:
	var rgb: Array = RAMPS[clampi(player, 1, 8) - 1][clampi(index, 0, 9)]
	return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))

func configure_assets(records: Array) -> void:
	references.clear()
	cached_textures.clear()
	for record in records:
		if String(record.get("archive", "")) != "graphics" or not record.has("frame"):
			continue
		var name := String(record.get("name", ""))
		if name.begins_with("neutral_"):
			continue
		var player := 2 if name.begins_with("enemy_") or name.ends_with("_p2") else 1
		if name.right(3).begins_with("_p") and name.right(3) not in ["_p1", "_p2"]:
			continue
		var key := _reference_key(record)
		if not references.has(key): references[key] = {}
		references[key][player] = record

static func _reference_key(record: Dictionary) -> String:
	return str([record.get("id", -1), record.get("source", ""), record.get("frame", 0), record.get("paletteId", 50500), record.get("derivation", {})])

func texture_for(record: Dictionary, texture: Texture2D, player: int) -> Texture2D:
	if texture == null or int(record.get("semanticPixels", {}).get("player_color", 0)) <= 0:
		return texture
	var name := String(record.get("name", ""))
	var source_player := 2 if name.begins_with("enemy_") or name.ends_with("_p2") else 1
	if source_player == player: return texture
	var pair: Dictionary = references.get(_reference_key(record), {})
	if not pair.has(1) or not pair.has(2): return texture
	var target_record: Dictionary = pair.get(player, {})
	if not target_record.is_empty():
		return load("res://assets/generated/%s" % target_record["file"]) as Texture2D
	var key := "%s:%d" % [_reference_key(record), player]
	var cached: WeakRef = cached_textures.get(key)
	if cached != null and cached.get_ref() != null: return cached.get_ref() as Texture2D
	var blue: Texture2D = load("res://assets/generated/%s" % pair[1]["file"])
	var red: Texture2D = load("res://assets/generated/%s" % pair[2]["file"])
	if blue == null or red == null: return texture
	var remapped := remap_images(blue.get_image(), red.get_image(), player)
	if remapped == null: return texture
	var result := ImageTexture.create_from_image(remapped)
	result.set_meta("ror_immutable_player_texture", true)
	if cached_textures.size() >= MAX_CACHED_TEXTURES: cached_textures.erase(cached_textures.keys()[0])
	cached_textures[key] = weakref(result)
	return result

static func remap_images(blue: Image, red: Image, player: int) -> Image:
	if blue == null or red == null or blue.get_size() != red.get_size(): return null
	# The two original decodes differ only at SLP player-colour commands. Ordinary
	# blue pixels and shadows are identical and must never be recoloured.
	var result: Image = blue.duplicate()
	result.convert(Image.FORMAT_RGBA8)
	var shade_lookup: Dictionary = {}
	for index in range(10): shade_lookup[shade(1, index).to_rgba32()] = shade(player, index)
	for y in range(blue.get_height()):
		for x in range(blue.get_width()):
			var source := blue.get_pixel(x, y)
			if source.a > 0.0 and source != red.get_pixel(x, y) and shade_lookup.has(source.to_rgba32()):
				result.set_pixel(x, y, shade_lookup[source.to_rgba32()])
	return result
