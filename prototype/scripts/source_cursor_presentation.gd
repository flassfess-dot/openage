class_name RoRSourceCursorPresentation
extends RefCounted

# data/Interfac.drs SLP 51000: the seven cursor frames shipped with RoR 1.1.
static func frame_for_semantic(semantic: String) -> int:
	match semantic:
		"select", "gather", "return_resources", "build", "repair", "heal", "board", "trade": return 3
		"attack", "attack_move", "convert": return 4
		"attack_ground": return 5
		"unsupported": return 6
		_: return 0


static func hotspot_for_metadata(metadata: Dictionary) -> Vector2:
	var source: Array = metadata.get("hotspot", [0, 0])
	return Vector2(float(source[0]), float(source[1])) if source.size() >= 2 else Vector2.ZERO
