class_name RoRGateCatalog
extends RefCounted

# Additive project content; imported DAT and SLP files remain untouched.
const UNIT_OFFSET := 10000
const WALL_IDS := [72, 117, 155]
const ICON_VARIANTS := [
	"small",
	"egyptian-medium", "egyptian-fortified",
	"greek-medium", "greek-fortified",
	"mesopotamian-medium", "mesopotamian-fortified",
	"east_asian-medium", "east_asian-fortified",
	"roman-medium", "roman-fortified",
]

static func icon_id(source_unit_id: int, architecture: int) -> int:
	var tier := WALL_IDS.find(source_unit_id - UNIT_OFFSET)
	return 0 if tier <= 0 else clampi(architecture, 0, 4) * 2 + tier


static func install_objects(catalog: Dictionary) -> void:
	if catalog.is_empty() or int(catalog.get("gate_extension_version", 0)) == 1:
		return
	var objects: Dictionary = catalog.get("objects", {})
	for civilization in range(17):
		for wall_id in WALL_IDS:
			var source: Dictionary = objects.get("%d:%d" % [civilization, wall_id], {})
			if source.is_empty():
				continue
			var gate: Dictionary = source.duplicate(true)
			gate["unit_id"] = wall_id + UNIT_OFFSET
			gate["key"] = "%d:%d" % [civilization, gate["unit_id"]]
			gate["health"] = float(source["health"]) * 3.0
			gate["geometry"]["radius"] = [2.0, 0.5, 2.0]
			gate["geometry"]["selection"] = [2.0, 0.5, 2.0]
			gate["geometry"]["clearance"] = [2.0, 0.5]
			gate["language"]["name_id"] = -1
			gate["interface"]["button_id"] = 11
			gate["resources"]["cost"] = [{"type_id": 1, "amount": 40, "enabled": true}, {"type_id": 2, "amount": 20, "enabled": true}]
			gate["production"]["creation_time"] = 28
			objects[gate["key"]] = gate
			catalog["building_keys"].append(gate["key"])
			catalog["civilizations"][civilization]["object_keys"].append(gate["key"])
	# Class-wide effects already match gates; mirror only wall-specific effects.
	for bundle in catalog.get("effect_bundles", {}).values():
		bundle["commands"].append_array(mirrored_wall_commands(bundle.get("commands", [])))
	catalog["counts"]["objects"] = objects.size()
	catalog["counts"]["buildings"] = catalog["building_keys"].size()
	catalog["gate_extension_version"] = 1

static func mirrored_wall_commands(commands: Array) -> Array:
	var additions: Array = []
	for command in commands:
		if int(command.get("type_id", -1)) not in [0,2,3,4,5,10,14,15,20,24,25] or int(command.get("attr_a", -1)) not in WALL_IDS:
			continue
		var copy: Dictionary = command.duplicate(true)
		copy["attr_a"] = int(copy["attr_a"]) + UNIT_OFFSET
		if int(copy.get("type_id", -1)) == 3:
			if int(copy.get("attr_b", -1)) not in WALL_IDS:
				continue
			copy["attr_b"] = int(copy["attr_b"]) + UNIT_OFFSET
		if not commands.has(copy):
			additions.append(copy)
	return additions

static func is_gate_unit(id: int) -> bool:
	return id-UNIT_OFFSET in WALL_IDS

static func install_runtime(catalog: Dictionary) -> void:
	var archetypes: Dictionary = catalog.get("archetypes", {})
	if archetypes.has("gate") or not archetypes.has("wall"):
		return
	var gate: Dictionary = archetypes["wall"].duplicate(true)
	gate["identifiers"] = {"internal_id": "ror.building.gate", "source_unit_id": 10072, "presentation_id": "building.gate"}
	gate["behavior_tags"] = ["defence", "static", "gate"]
	gate["runtime"] = {"required_technology_id": 11, "connectivity_group": "wall", "source_variant_unit_ids": [10117, 10155]}
	for record in gate.get("records", {}).values():
		record["source_key"] = "%d:10072" % int(record["civilization_id"])
		var stats: Dictionary = record["simulation"]
		stats["unit_id"] = 10072
		stats["hit_points"] = float(stats["hit_points"]) * 3.0
		stats["selection_radius"] = [2.0, 0.5, 2.0]
		stats["creation_time"] = 28
		stats["resource_cost"] = [{"type_id": 1, "amount": 40, "enabled": true}, {"type_id": 2, "amount": 20, "enabled": true}]
		record["presentation"]["name_id"] = -1
		record["presentation"]["fallback_name"] = "Ворота"
		record["presentation"]["button_id"] = 11
	archetypes["gate"] = gate
