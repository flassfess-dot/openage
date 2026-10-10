extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const WORLD_DIRECTIONS := [Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0)]
# Source PNGs inspected independently: block 0 points south, 4/8 north;
# east-side headings mirror the matching west-side block.
const SOURCE_BLOCKS_8 := [0, 1, 2, 3, 4, 3, 2, 1]
const SOURCE_BLOCKS_16 := [0, 2, 4, 6, 8, 6, 4, 2]
const SOURCES := [13, 14, 15, 16, 17, 18, 19, 20, 21, 250, 277]
var failures: Array[String] = []

func _initialize() -> void:
	verify_angle_scale()
	var catalog := Catalog.new()
	catalog.load()
	for source_id in SOURCES:
		for team in [1, 2]:
			for facing in range(8):
				var unit := {"id": source_id, "kind": alias_for_source(source_id), "source_unit_id": source_id, "team": team, "facing": facing, "anim": 0.0, "hp": 100.0, "max_hp": 100.0}
				check(FacingConvention.logical_for_world(WORLD_DIRECTIONS[facing]) == facing, "world compass sector %d" % facing)
				var states: Array = ["idle", "move", "attack"] if source_id in [19, 20, 21, 250, 277] else ["idle", "move"]
				for state in states:
					for sample in [0.0, 0.16, 0.73, 1.19]:
						var info: Dictionary = catalog.unit_frame_info(unit, state, sample)
						var context := "ship %d team %d %s compass %d time %.2f" % [source_id, team, state, facing, sample]
						check(not info.is_empty(), context + " resolves imported art")
						if info.is_empty(): continue
						verify_layer(catalog, info, facing, context + " hull")
						for part in info.get("composite_parts", []):
							verify_layer(catalog, part, facing, context + " composite")
				var death: Dictionary = catalog.unit_frame_info(unit, "death", 0.16)
				check(int(death.get("source_direction", -1)) == 0 and not bool(death.get("mirrored", true)), "nondirectional ship death stays on source block zero")
	# Changing a unit graphic cannot rotate existing eight-angle land sprites.
	for facing in range(8):
		var soldier := {"kind": "clubman", "source_unit_id": 73, "team": 1, "facing": facing, "anim": 0.0}
		verify_layer(catalog, catalog.unit_frame_info(soldier, "move"), facing, "clubman sector %d" % facing)
	finish()

func verify_angle_scale() -> void:
	for facing in range(8):
		check(FacingConvention.for_angle_count(facing, 8) == facing, "eight-sector graphic preserves heading")
		check(FacingConvention.for_angle_count(facing, 16) == facing * 2, "sixteen-sector graphic scales heading")
		check(FacingConvention.for_angle_count(facing, 32) == facing * 4, "thirty-two-sector graphic scales heading")
		check(FacingConvention.for_angle_count(facing, 1) == 0, "one-sector graphic ignores heading")
	check(FacingConvention.for_angle_count(-1, 16) == 14, "negative facing wraps before scaling")
	check(FacingConvention.for_angle_count(15, 16) == 14, "oversized facing wraps before scaling")

func verify_layer(catalog, layer: Dictionary, facing: int, context: String) -> void:
	var graphic_id := int(layer.get("graphic_id", -1))
	var spec: Dictionary = catalog.graphics_catalog_data.get("graphics", {}).get(str(graphic_id), {})
	var count := int(spec.get("angle_count", 1))
	check(count in [8, 16], context + " has a supported directional source")
	if count not in [8, 16]: return
	var expected_source: int = SOURCE_BLOCKS_16[facing] if count == 16 else SOURCE_BLOCKS_8[facing]
	check(int(layer.get("source_direction", -1)) == expected_source, context + " selects the bow direction")
	check(int(layer.get("direction_degrees", -1)) == facing * 45, context + " preserves compass angle")
	check(bool(layer.get("mirrored", false)) == (facing > 4), context + " reflects east-side headings")
	# Compare with the actual PNG in the expected directional block, not another
	# call to GraphicDescriptor.resolve or the facing-conversion helper.
	var asset_name := String(layer.get("asset_name", ""))
	var frames_per_angle := 8 if asset_name.ends_with("war_galley_rowing") else int(spec.get("frames_per_angle", 1))
	var actual_index := int(layer.get("frame_index", -1))
	var expected_index := expected_source * frames_per_angle + posmod(actual_index, frames_per_angle)
	check(actual_index == expected_index, context + " animation stays inside the expected source block")
	var metadata: Dictionary = catalog.get_texture_metadata(asset_name, expected_index)
	check(not metadata.is_empty(), context + " has expected source metadata")
	if metadata.is_empty(): return
	var expected: Texture2D = load("res://assets/generated/%s" % String(metadata["file"]))
	var actual: Texture2D = layer.get("texture")
	check(actual != null and expected != null, context + " has loadable textures")
	if actual != null and expected != null:
		check(actual.get_image().get_data() == expected.get_image().get_data(), context + " draws expected source pixels")
	var hotspot: Array = metadata.get("hotspot", [])
	if hotspot.size() >= 2:
		check(Vector2(layer.get("hotspot", Vector2.ZERO)) == Vector2(hotspot[0], hotspot[1]), context + " preserves per-frame hull/sail anchor")

func alias_for_source(source_id: int) -> String:
	if source_id in [13, 14]: return "fishing_boat"
	if source_id in [15, 16]: return "trade_boat"
	if source_id in [17, 18]: return "transport"
	if source_id in [19, 20, 21]: return "scout_ship"
	return "catapult_trireme"

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)

func finish() -> void:
	if failures.is_empty():
		print("Live gameplay naval compass and source pixels passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)
