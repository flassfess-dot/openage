class_name RoRSourceAiAssignmentGroup
extends RefCounted

const DEFEND := "defend"
const EXPLORE := "explore"
const ESCORT := "escort"

const MOVING := "MOVING"
const ACTIVE := "ACTIVE"
const ENGAGING := "ENGAGING"
const COMPLETE := "COMPLETE"

var group_id: int = 0
var team: int = 0
var role: String = DEFEND
var member_ids: Array[int] = []
var anchor_id: int = -1
var anchor_kind: String = ""
var anchor_position: Vector2 = Vector2.ZERO
var objective_position: Vector2 = Vector2.ZERO
var target_id: int = -1
var movement_domain: String = "land"
var formation_name: String = "RECTANGLE"
var defence_distance: float = 0.0
var influence_radius: float = 0.0
var priority: int = 0
var commander_id: int = -1
var commander_selection_method: int = -1
var state: String = MOVING
var created_tick: int = 0
var updated_tick: int = 0
var lifecycle_revision: int = 0
var last_transition_reason: String = "created"


func _init(
		id: int = 0,
		owner_team: int = 0,
		assignment_role: String = DEFEND,
		members: Array = [],
		world_anchor: Vector2 = Vector2.ZERO,
		tick: int = 0) -> void:
	group_id = id
	team = owner_team
	role = assignment_role if assignment_role in [DEFEND, EXPLORE, ESCORT] else DEFEND
	anchor_position = world_anchor
	objective_position = world_anchor
	created_tick = tick
	updated_tick = tick
	for member_value in members:
		var member: Dictionary = member_value
		var entity_id := int(member.get("id", -1))
		if entity_id >= 0 and not member_ids.has(entity_id):
			member_ids.append(entity_id)
	member_ids.sort()


func transition(next_state: String, reason: String, tick: int) -> bool:
	updated_tick = tick
	if state == next_state:
		return false
	state = next_state
	lifecycle_revision += 1
	last_transition_reason = reason
	return true


func sync_members(units_by_id: Dictionary, tick: int) -> void:
	updated_tick = tick
	var living: Array[int] = []
	for entity_id in member_ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and float(unit.get("hp", 0.0)) > 0.0:
			living.append(entity_id)
	member_ids = living
	if commander_id >= 0 and commander_id not in member_ids:
		commander_id = _select_commander(member_ids, units_by_id)
	if member_ids.is_empty():
		transition(COMPLETE, "no_surviving_members", tick)


func configure_commander(members: Array, method: int) -> void:
	commander_selection_method = clampi(method, 0, 2)
	var units_by_id: Dictionary = {}
	for member_value in members:
		var member: Dictionary = member_value
		units_by_id[int(member.get("id", -1))] = member
	commander_id = _select_commander(member_ids, units_by_id)


func canonical_state() -> Dictionary:
	return {
		"group_id": group_id,
		"team": team,
		"role": role,
		"member_ids": member_ids.duplicate(),
		"anchor_id": anchor_id,
		"anchor_kind": anchor_kind,
		"anchor_position": anchor_position,
		"objective_position": objective_position,
		"target_id": target_id,
		"movement_domain": movement_domain,
		"formation_name": formation_name,
		"defence_distance": defence_distance,
		"influence_radius": influence_radius,
		"priority": priority,
		"commander_id": commander_id,
		"commander_selection_method": commander_selection_method,
		"state": state,
		"created_tick": created_tick,
		"updated_tick": updated_tick,
		"lifecycle_revision": lifecycle_revision,
		"last_transition_reason": last_transition_reason,
	}


static func from_state(data: Dictionary):
	var group = new()
	group.group_id = int(data.get("group_id", 0))
	group.team = int(data.get("team", 0))
	group.role = String(data.get("role", DEFEND))
	group.member_ids.assign(_int_array(data.get("member_ids", [])))
	group.anchor_id = int(data.get("anchor_id", -1))
	group.anchor_kind = String(data.get("anchor_kind", ""))
	group.anchor_position = Vector2(data.get("anchor_position", Vector2.ZERO))
	group.objective_position = Vector2(data.get("objective_position", group.anchor_position))
	group.target_id = int(data.get("target_id", -1))
	group.movement_domain = String(data.get("movement_domain", "land"))
	group.formation_name = String(data.get("formation_name", "RECTANGLE"))
	group.defence_distance = maxf(0.0, float(data.get("defence_distance", 0.0)))
	group.influence_radius = maxf(0.0, float(data.get("influence_radius", 0.0)))
	group.priority = maxi(0, int(data.get("priority", 0)))
	group.commander_id = int(data.get("commander_id", -1))
	group.commander_selection_method = int(data.get("commander_selection_method", -1))
	group.state = String(data.get("state", MOVING))
	group.created_tick = int(data.get("created_tick", 0))
	group.updated_tick = int(data.get("updated_tick", group.created_tick))
	group.lifecycle_revision = int(data.get("lifecycle_revision", 0))
	group.last_transition_reason = String(data.get("last_transition_reason", "restored"))
	return group


static func _int_array(source: Array) -> Array[int]:
	var result: Array[int] = []
	for value in source:
		result.append(int(value))
	result.sort()
	return result


func _select_commander(ids: Array[int], units_by_id: Dictionary) -> int:
	if commander_selection_method not in [0, 1, 2]:
		return -1
	var candidates: Array = []
	for entity_id in ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and float(unit.get("hp", 0.0)) > 0.0:
			candidates.append(unit)
	if candidates.is_empty():
		return -1
	candidates.sort_custom(func(left, right):
		var left_metric := float(left.get("attack_range", 0.0)) if commander_selection_method == 2 else float(left.get("hp", 0.0))
		var right_metric := float(right.get("attack_range", 0.0)) if commander_selection_method == 2 else float(right.get("hp", 0.0))
		if not is_equal_approx(left_metric, right_metric):
			return left_metric < right_metric if commander_selection_method == 1 else left_metric > right_metric
		return int(left.get("id", -1)) < int(right.get("id", -1))
	)
	return int(candidates[0].get("id", -1))
