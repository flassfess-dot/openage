class_name RoRGateSystem
extends RefCounted

const Footprint := preload("res://scripts/footprint.gd")
const MODES := ["auto", "open", "locked"]
const OPEN_SECONDS := 0.65
const HOLD_SECONDS := 1.2
const PASSABLE_FRACTION := 0.95
var world_ref: WeakRef
var gate_ids: Dictionary = {}
var policy_revision := 0
var planning_revisions: Dictionary = {}
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null

func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)

static func placement_stats(stats: Dictionary, axis: int) -> Dictionary:
	var result: Dictionary = stats.duplicate(true)
	var radii: Array = [2.0, 0.5, 2.0] if axis == 0 else [0.5, 2.0, 2.0]
	result["footprint_radius"] = radii
	result["selection_radius"] = radii
	return result

# Read-only placement query. Only whole, completed walls owned by the builder
# may be replaced; navigation still rejects every other occupant.
func replacement_wall_ids(team: int, position: Vector2, axis: int) -> Dictionary:
	var footprint := Footprint.building(placement_stats(world.unit_stats("gate"), axis), position)
	var cells: Array = footprint["occupied_cells"]
	var result: Dictionary = {}
	for cell in cells:
		for occupant in world.navigation_grid.occupants(cell):
			if String(occupant.get("category", "")) != "building":
				continue
			var id := int(occupant.get("id", -1))
			var wall: Variant = world.find_building(id)
			if wall == null or String(wall.get("kind", "")) != "wall" or int(wall.get("team", 0)) != team or String(wall.get("state", "")) != "complete" or float(wall.get("hp", 0)) <= 0:
				continue
			if wall.get("occupied_cells", []).all(func(wall_cell): return wall_cell in cells):
				result[id] = true
	return result

func replace_wall_segments(ids: Dictionary) -> void:
	var ordered: Array = ids.keys()
	ordered.sort()
	for id in ordered:
		var wall: Dictionary = world.find_building(int(id))
		world.release_building_navigation_occupancy(wall)
		world.deactivate_building_victory_objective(wall)
		world.production_system.unregister_building(int(id))
		world.entity_changes.remove(int(id))
		world.render_entity_projection_cache.erase(int(id))
		world.track_conquest_entity({"id": int(id), "hp": 0.0})
		world.buildings_by_id.erase(int(id))
		world.buildings.erase(wall)
		world.building_approach_slots.erase(int(id))
		for unit in world.get_units():
			if int(unit.get("target_building_id", -1)) == int(id):
				world.finish_building_order(unit, "wall_replaced")
	if not ids.is_empty():
		world.spatial_sync_system.mark_roster_dirty()
		world.mark_combat_roster_dirty()

func register(gate: Dictionary, axis: int = 0) -> void:
	gate_ids[int(gate["id"])] = true
	gate["gate_axis"] = clampi(axis, 0, 1)
	gate["gate_mode"] = "auto"
	gate["gate_open_fraction"] = 0.0
	gate["gate_hold_seconds"] = 0.0
	_layout(gate)
	policy_revision += 1

func reset() -> void:
	gate_ids.clear()
	planning_revisions.clear()
	policy_revision += 1

func _layout(gate: Dictionary) -> void:
	var cells: Array = gate.get("occupied_cells", []).duplicate()
	var axis := int(gate.get("gate_axis", 0))
	cells.sort_custom(func(a, b): return a[axis] < b[axis])
	var piers: Array = []
	var passage: Array = []
	for index in range(cells.size()):
		if index == 0 or index == cells.size() - 1:
			piers.append(cells[index])
		else:
			passage.append(cells[index])
	gate["gate_pier_cells"] = piers
	gate["gate_passage_cells"] = passage

func set_mode(ids: Array, issuer: int, mode: String) -> String:
	if mode not in MODES or ids.is_empty():
		return "invalid_gate_mode"
	var selected: Array = []
	for id in ids:
		var gate: Variant = world.find_building(id)
		if gate == null or String(gate.get("kind", "")) != "gate" or int(gate.get("team", 0)) != issuer or float(gate.get("hp", 0.0)) <= 0.0 or String(gate.get("state", "")) != "complete":
			return "gate_unavailable"
		if gate.get("gate_mode") != mode:
			selected.append(gate)
	for gate in selected:
		world.set_entity_field(gate, "gate_mode", mode)
	if not selected.is_empty():
		policy_revision += 1
	return ""

static func navigation_cells(gate: Dictionary) -> Array:
	if float(gate.get("hp", 1.0)) <= 0.0:
		return []
	if String(gate.get("state", "")) != "complete" or float(gate.get("gate_open_fraction", 0.0)) < PASSABLE_FRACTION:
		return gate.get("occupied_cells", [])
	return gate.get("gate_pier_cells", [])

func planning_occupants(team: int, cell: Vector2i, occupants: Array, visible: bool) -> Array:
	if gate_ids.is_empty() or occupants.is_empty():
		return occupants
	var result: Array = []
	for occupant in occupants:
		var id := int(occupant.get("id", -1))
		if occupant.get("category") == "building" and gate_ids.has(id):
			# Shared exploration can reveal terrain without exposing the gate.
			if not visible:
				continue
			var gate: Variant = world.find_building(id)
			if (gate != null and cell in gate.get("gate_passage_cells", [])
					and gate.get("state") == "complete" and gate.get("gate_mode", "auto") in ["auto", "open"]
					and _admits(int(gate["team"]), team)):
				continue
		result.append(occupant)
	return result

func _admits(owner: int, traveller: int) -> bool:
	return world.are_teams_allied(owner, traveller)

func planning_revision(team: int) -> int:
	if gate_ids.is_empty():
		return 0
	var simulation_world = world
	var diplomacy_revision: int = simulation_world.player_registry.navigation_revision
	var previous: Array = planning_revisions.get(team, [])
	if previous.size() == 3 and int(previous[0]) == policy_revision and int(previous[1]) == diplomacy_revision:
		return int(previous[2])
	var owners: Array[int] = []
	for owner in simulation_world.player_registry.all_teams():
		if _admits(owner, team): owners.append(owner)
	var revision := hash([policy_revision, owners])
	if planning_revisions.size() >= 64: planning_revisions.clear()
	planning_revisions[team] = [policy_revision, diplomacy_revision, revision]
	return revision

func passage_cells() -> Array:
	var result: Array = []
	for id in gate_ids:
		var gate: Variant = world.find_building(id)
		if gate != null:
			result.append_array(gate.get("gate_passage_cells", []))
	return result

func _route_uses_passage(unit: Dictionary, gate: Dictionary) -> bool:
	var route: Array = unit.get("path", [])
	var origin := Vector2(unit.get("pos", Vector2.ZERO))
	var radius := float(unit.get("footprint_radius", 0.3)) + 0.1
	var radius_squared := radius * radius
	for index in range(maxi(0, int(unit.get("path_index", 0))), route.size()):
		var point := Vector2(route[index])
		for cell in gate.get("gate_passage_cells", []):
			if Footprint.segment_cell_distance_squared(origin, point, Vector2i(cell)) <= radius_squared:
				return true
		origin = point
	return false

func _passage_occupied(unit: Dictionary, gate: Dictionary) -> bool:
	var radius := float(unit.get("footprint_radius", 0.3)) + 0.15
	for cell in gate["gate_passage_cells"]:
		if Footprint.circle_cell_distance_squared(unit["pos"], cell) < radius * radius:
			return true
	return false

func advance(delta: float) -> void:
	for id in gate_ids.keys():
		var gate: Variant = world.find_building(int(id))
		if gate == null or float(gate.get("hp", 0.0)) <= 0.0:
			gate_ids.erase(id)
			policy_revision += 1
			continue
		if String(gate.get("state", "")) != "complete":
			continue
		var mode := String(gate.get("gate_mode", "auto"))
		var automatic := mode == "auto"
		var hold: float = maxf(0.0, float(gate.get("gate_hold_seconds", 0.0)) - delta)
		var previous := float(gate.get("gate_open_fraction", 0.0))
		var passage_open := previous >= PASSABLE_FRACTION
		var wants_open := mode == "open" or (automatic and hold > 0.0)
		if automatic or (passage_open and not wants_open):
			var owner := int(gate["team"])
			for unit in world.spatial_index.query_circle(Vector2(gate["pos"]), 4.0, "unit"):
				if float(unit.get("hp", 0.0)) <= 0.0 or String(unit.get("movement_domain", "land")) != "land" or bool(unit.get("embarked", false)):
					continue
				if automatic and _admits(owner, int(unit["team"])) and _route_uses_passage(unit, gate):
					hold = HOLD_SECONDS
					wants_open = true
					break
				# Wait for every unit in the passage before closing.
				if passage_open and not wants_open and _passage_occupied(unit, gate):
					wants_open = true
					if not automatic:
						break
		var next := move_toward(previous, 1.0 if wants_open else 0.0, delta / OPEN_SECONDS)
		world.set_entity_field(gate, "gate_hold_seconds", hold)
		if previous != next:
			world.set_entity_field(gate, "gate_open_fraction", next)
			if passage_open != (next >= PASSABLE_FRACTION):
				world.sync_building_navigation_occupancy(gate)
