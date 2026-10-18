class_name RoRGateSystem
extends RefCounted

const Footprint := preload("res://scripts/footprint.gd")
const MODES := ["auto", "open", "locked"]
const OPEN_SECONDS := 0.65
const HOLD_SECONDS := 1.2
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
		selected.append(gate)
	for gate in selected:
		world.set_entity_field(gate, "gate_mode", mode)
	policy_revision += 1
	return ""

func navigation_cells(gate: Dictionary) -> Array:
	if float(gate.get("hp", 0.0)) <= 0.0:
		return []
	if String(gate.get("state", "")) != "complete" or float(gate.get("gate_open_fraction", 0.0)) < 0.95:
		return gate.get("occupied_cells", [])
	return gate.get("gate_pier_cells", [])

func planning_occupants(team: int, cell: Vector2i, occupants: Array) -> Array:
	if gate_ids.is_empty():
		return occupants
	var result: Array = []
	for occupant in occupants:
		var gate: Variant = world.find_building(int(occupant.get("id", -1))) if String(occupant.get("category", "")) == "building" else null
		if gate != null and String(gate.get("kind", "")) == "gate" and String(gate.get("state", "")) == "complete" and String(gate.get("gate_mode", "auto")) in ["auto", "open"] and world.are_teams_allied(team, int(gate.get("team", 0))) and cell in gate.get("gate_passage_cells", []):
			continue
		result.append(occupant)
	return result

func planning_revision(team: int) -> int:
	if gate_ids.is_empty():
		return 0
	var simulation_world = world
	var diplomacy_revision: int = simulation_world.player_registry.navigation_revision
	var previous: Array = planning_revisions.get(team, [])
	if previous.size() == 3 and int(previous[0]) == policy_revision and int(previous[1]) == diplomacy_revision:
		return int(previous[2])
	var revision := hash([policy_revision, simulation_world.get_allied_teams(team)])
	if planning_revisions.size() >= 64: planning_revisions.clear()
	planning_revisions[team] = [policy_revision, diplomacy_revision, revision]
	return revision

func all_cells() -> Array:
	var result: Array = []
	for id in gate_ids:
		var gate: Variant = world.find_building(id)
		if gate != null:
			result.append_array(gate.get("occupied_cells", []))
	return result

func _route_uses_passage(unit: Dictionary, gate: Dictionary) -> bool:
	var route: Array = unit.get("path", [])
	var origin := Vector2(unit.get("pos", Vector2.ZERO))
	var radius := float(unit.get("footprint_radius", 0.3)) + 0.1
	for index in range(maxi(0, int(unit.get("path_index", 0))), route.size()):
		var point := Vector2(route[index])
		for cell in gate.get("gate_passage_cells", []):
			if Footprint.segment_cell_distance_squared(origin, point, Vector2i(cell)) <= radius * radius:
				return true
		origin = point
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
		_layout(gate)
		var nearby: Array = world.spatial_index.query_circle(Vector2(gate["pos"]), 4.0, "unit")
		var occupied := false
		var request := false
		for unit in nearby:
			if float(unit.get("hp", 0.0)) <= 0.0 or String(unit.get("movement_domain", "land")) != "land" or bool(unit.get("embarked", false)):
				continue
			for cell in gate["gate_passage_cells"]:
				if Footprint.circle_cell_distance_squared(Vector2(unit["pos"]), Vector2i(cell)) < pow(float(unit.get("footprint_radius", 0.3)) + 0.15, 2):
					occupied = true
			if world.are_teams_allied(int(gate["team"]), int(unit.get("team", 0))) and _route_uses_passage(unit, gate):
				request = true
		var mode := String(gate.get("gate_mode", "auto"))
		var hold: float = maxf(0.0, float(gate.get("gate_hold_seconds", 0.0)) - delta)
		if mode == "auto" and request:
			hold = HOLD_SECONDS
		var wants_open: bool = mode == "open" or (mode == "auto" and hold > 0.0)
		var previous := float(gate.get("gate_open_fraction", 0.0))
		# Nobody is pushed, trapped or crushed by a closing door.
		if occupied and previous >= 0.95:
			wants_open = true
		var next := move_toward(previous, 1.0 if wants_open else 0.0, delta / OPEN_SECONDS)
		world.set_entity_field(gate, "gate_hold_seconds", hold)
		if not is_equal_approx(previous, next):
			world.set_entity_field(gate, "gate_open_fraction", next)
			if (previous >= 0.95) != (next >= 0.95):
				world.sync_building_navigation_occupancy(gate)
