class_name RoRSourceAiAttackGroup
extends RefCounted

const ASSEMBLING := "ASSEMBLING"
const READY := "READY"
const ATTACKING := "ATTACKING"
const RETREATING := "RETREATING"
const RECENTERING := "RECENTERING"
const EXTERMINATING := "EXTERMINATING"
const COMPLETE := "COMPLETE"

var group_id: int = 0
var team: int = 0
var member_ids: Array[int] = []
var active_member_ids: Array[int] = []
var retreating_member_ids: Array[int] = []
var initial_hp_by_member: Dictionary = {}
var initial_total_hp: float = 0.0
var rally_position: Vector2 = Vector2.ZERO
var objective_position: Vector2 = Vector2.ZERO
var target_id: int = -1
var target_observed: bool = false
var movement_domain: String = "land"
var formation_name: String = "RECTANGLE"
var wave_id: int = 0
var order_type: String = "attack_move"
var fill_method: int = 0
var gather_spacing: float = 0.0
var coordination_mode: int = 0
var commander_id: int = -1
var commander_selection_method: int = -1
var state: String = ATTACKING
var created_tick: int = 0
var updated_tick: int = 0
var lifecycle_revision: int = 0
var last_transition_reason: String = "created"
var current_total_hp: float = 0.0
var current_living_count: int = 0
var health_loss_percent: float = 0.0
var death_loss_percent: float = 0.0


func _init(
		id: int = 0,
		owner_team: int = 0,
		members: Array = [],
		world_objective: Vector2 = Vector2.ZERO,
		target_entity_id: int = -1,
		world_rally: Vector2 = Vector2.ZERO,
		domain: String = "land",
		formation: String = "RECTANGLE",
		tick: int = 0) -> void:
	group_id = id
	team = owner_team
	objective_position = world_objective
	rally_position = world_rally
	target_id = target_entity_id
	target_observed = target_entity_id >= 0
	movement_domain = domain if domain in ["land", "water"] else "land"
	formation_name = formation
	created_tick = tick
	updated_tick = tick
	for member_value in members:
		var member: Dictionary = member_value
		var entity_id := int(member.get("id", -1))
		if entity_id < 0 or member_ids.has(entity_id):
			continue
		member_ids.append(entity_id)
		initial_hp_by_member[entity_id] = maxf(0.0, float(member.get("hp", 0.0)))
	member_ids.sort()
	active_member_ids.assign(member_ids)
	initial_total_hp = _sum_initial_hp(member_ids)
	current_total_hp = initial_total_hp
	current_living_count = member_ids.size()


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
	var living_original_ids: Array[int] = []
	current_total_hp = 0.0
	for entity_id in member_ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit == null or float(unit.get("hp", 0.0)) <= 0.0:
			continue
		living_original_ids.append(entity_id)
		current_total_hp += minf(float(initial_hp_by_member.get(entity_id, 0.0)), float(unit.get("hp", 0.0)))
	current_living_count = living_original_ids.size()
	health_loss_percent = 100.0 if initial_total_hp <= 0.0 else clampf((initial_total_hp - current_total_hp) * 100.0 / initial_total_hp, 0.0, 100.0)
	death_loss_percent = 100.0 if member_ids.is_empty() else clampf(float(member_ids.size() - current_living_count) * 100.0 / float(member_ids.size()), 0.0, 100.0)
	active_member_ids = _living_subset(active_member_ids, units_by_id)
	retreating_member_ids = _living_subset(retreating_member_ids, units_by_id)
	if commander_id >= 0 and commander_id not in living_original_ids:
		commander_id = _select_commander(living_original_ids, units_by_id)


func configure_commander(members: Array, method: int) -> void:
	commander_selection_method = clampi(method, 0, 2)
	var units_by_id: Dictionary = {}
	for member_value in members:
		var member: Dictionary = member_value
		units_by_id[int(member.get("id", -1))] = member
	commander_id = _select_commander(member_ids, units_by_id)


func begin_individual_retreat(entity_id: int) -> void:
	active_member_ids.erase(entity_id)
	if not retreating_member_ids.has(entity_id):
		retreating_member_ids.append(entity_id)
		retreating_member_ids.sort()


func living_ids() -> Array[int]:
	var result: Array[int] = active_member_ids.duplicate()
	for entity_id in retreating_member_ids:
		if not result.has(entity_id):
			result.append(entity_id)
	result.sort()
	return result


func unit_health_loss_percent(entity_id: int, current_hp: float) -> float:
	var initial_hp := float(initial_hp_by_member.get(entity_id, 0.0))
	if initial_hp <= 0.0:
		return 100.0
	return clampf((initial_hp - maxf(0.0, current_hp)) * 100.0 / initial_hp, 0.0, 100.0)


func canonical_state() -> Dictionary:
	var initial_members: Array = []
	for entity_id in member_ids:
		initial_members.append({"entity_id": entity_id, "hp": float(initial_hp_by_member.get(entity_id, 0.0))})
	return {
		"group_id": group_id,
		"team": team,
		"member_ids": member_ids.duplicate(),
		"active_member_ids": active_member_ids.duplicate(),
		"retreating_member_ids": retreating_member_ids.duplicate(),
		"initial_members": initial_members,
		"initial_total_hp": initial_total_hp,
		"rally_position": rally_position,
		"objective_position": objective_position,
		"target_id": target_id,
		"target_observed": target_observed,
		"movement_domain": movement_domain,
		"formation_name": formation_name,
		"wave_id": wave_id,
		"order_type": order_type,
		"fill_method": fill_method,
		"gather_spacing": gather_spacing,
		"coordination_mode": coordination_mode,
		"commander_id": commander_id,
		"commander_selection_method": commander_selection_method,
		"state": state,
		"created_tick": created_tick,
		"updated_tick": updated_tick,
		"lifecycle_revision": lifecycle_revision,
		"last_transition_reason": last_transition_reason,
		"current_total_hp": current_total_hp,
		"current_living_count": current_living_count,
		"health_loss_percent": health_loss_percent,
		"death_loss_percent": death_loss_percent,
	}


static func from_state(data: Dictionary):
	var group = new()
	group.group_id = int(data.get("group_id", 0))
	group.team = int(data.get("team", 0))
	group.member_ids.assign(_int_array(data.get("member_ids", [])))
	group.active_member_ids.assign(_int_array(data.get("active_member_ids", [])))
	group.retreating_member_ids.assign(_int_array(data.get("retreating_member_ids", [])))
	group.initial_hp_by_member.clear()
	for member_value in data.get("initial_members", []):
		var member: Dictionary = member_value
		group.initial_hp_by_member[int(member.get("entity_id", -1))] = float(member.get("hp", 0.0))
	group.initial_total_hp = float(data.get("initial_total_hp", group._sum_initial_hp(group.member_ids)))
	group.rally_position = Vector2(data.get("rally_position", Vector2.ZERO))
	group.objective_position = Vector2(data.get("objective_position", Vector2.ZERO))
	group.target_id = int(data.get("target_id", -1))
	group.target_observed = bool(data.get("target_observed", group.target_id >= 0))
	group.movement_domain = String(data.get("movement_domain", "land"))
	group.formation_name = String(data.get("formation_name", "RECTANGLE"))
	group.wave_id = int(data.get("wave_id", 0))
	group.order_type = String(data.get("order_type", "attack_move"))
	group.fill_method = clampi(int(data.get("fill_method", 0)), 0, 1)
	group.gather_spacing = maxf(0.0, float(data.get("gather_spacing", 0.0)))
	group.coordination_mode = clampi(int(data.get("coordination_mode", 0)), 0, 2)
	group.commander_id = int(data.get("commander_id", -1))
	group.commander_selection_method = int(data.get("commander_selection_method", -1))
	group.state = String(data.get("state", ATTACKING))
	group.created_tick = int(data.get("created_tick", 0))
	group.updated_tick = int(data.get("updated_tick", group.created_tick))
	group.lifecycle_revision = int(data.get("lifecycle_revision", 0))
	group.last_transition_reason = String(data.get("last_transition_reason", "restored"))
	group.current_total_hp = float(data.get("current_total_hp", group.initial_total_hp))
	group.current_living_count = int(data.get("current_living_count", group.member_ids.size()))
	group.health_loss_percent = float(data.get("health_loss_percent", 0.0))
	group.death_loss_percent = float(data.get("death_loss_percent", 0.0))
	return group


func _sum_initial_hp(ids: Array[int]) -> float:
	var result := 0.0
	for entity_id in ids:
		result += float(initial_hp_by_member.get(entity_id, 0.0))
	return result


func _living_subset(source: Array[int], units_by_id: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for entity_id in source:
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and float(unit.get("hp", 0.0)) > 0.0:
			result.append(entity_id)
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


static func _int_array(source: Array) -> Array[int]:
	var result: Array[int] = []
	for value in source:
		result.append(int(value))
	result.sort()
	return result
