class_name RoRFormationLifecycle
extends RefCounted

const ASSEMBLE := "ASSEMBLE"
const TRAVEL := "TRAVEL"
const DEPLOY := "DEPLOY"
const ENGAGED := "ENGAGED"
const REGROUP := "REGROUP"
const REFORM := "REFORM"
const DISBAND := "DISBAND"
const SLOT_TOLERANCE := 0.22


static func evaluate(group, members: Array, target_provider: Callable = Callable()) -> Dictionary:
	var previous := String(group.state)
	if members.is_empty():
		return transition(group, DISBAND, "no_members")
	var has_combat := members.any(func(unit): return String(unit.get("task", "")) == "attack")
	var any_moving := members.any(func(unit): return String(unit.get("task", "")) in ["move", "attack_move"])
	var maximum_slot_error := _maximum_slot_error(group, members)
	var at_slots := maximum_slot_error <= SLOT_TOLERANCE
	var desired := previous
	var reason := "stable"

	if has_combat:
		desired = ENGAGED
		reason = "member_engaged"
		group.engagement_forward = _engagement_forward(group, members, target_provider)
	else:
		match previous:
			ASSEMBLE:
				desired = DEPLOY if at_slots and not any_moving else TRAVEL
				reason = "assembled" if desired == DEPLOY else "travel_started"
			TRAVEL:
				if at_slots and not any_moving:
					desired = DEPLOY
					reason = "anchor_reached"
			DEPLOY:
				if any_moving:
					desired = TRAVEL
					reason = "new_route"
			ENGAGED:
				desired = REGROUP
				reason = "contact_ended"
			REGROUP:
				if at_slots and not any_moving:
					desired = REFORM
					reason = "members_regrouped"
			REFORM:
				if not at_slots or any_moving:
					desired = REGROUP
					reason = "reform_interrupted"
				elif int(group.state_ticks) >= 1:
					desired = DEPLOY
					reason = "formation_ready"

	var result := transition(group, desired, reason)
	group.maximum_slot_error = maximum_slot_error
	group.slot_constraint_mode = slot_mode_for(String(group.state))
	return result


static func transition(group, state: String, reason: String) -> Dictionary:
	var previous := String(group.state)
	var changed := previous != state
	if changed:
		group.state = state
		group.state_ticks = 0
		group.lifecycle_revision += 1
		group.last_transition_reason = reason
	else:
		group.state_ticks += 1
	return {"changed": changed, "previous": previous, "current": String(group.state), "reason": reason}


static func slot_mode_for(state: String) -> String:
	match state:
		ENGAGED: return "released"
		REFORM: return "hard"
		ASSEMBLE, TRAVEL, REGROUP, DEPLOY: return "soft"
		_: return "none"


static func _maximum_slot_error(group, members: Array) -> float:
	var maximum := 0.0
	for unit_value in members:
		var unit: Dictionary = unit_value
		var slot: Dictionary = group.slot_for(int(unit.get("id", -1)))
		if slot.is_empty():
			return INF
		maximum = maxf(maximum, Vector2(unit.get("pos", Vector2.ZERO)).distance_to(Vector2(slot["world"])))
	return maximum


static func _engagement_forward(group, members: Array, target_provider: Callable) -> Vector2:
	if not target_provider.is_valid():
		return group.forward
	var member_center := Vector2.ZERO
	var target_center := Vector2.ZERO
	var target_count := 0
	for unit_value in members:
		var unit: Dictionary = unit_value
		member_center += Vector2(unit.get("pos", Vector2.ZERO))
		if String(unit.get("task", "")) != "attack":
			continue
		var target = target_provider.call(int(unit.get("target_id", -1)))
		if target != null:
			target_center += Vector2(target.get("pos", Vector2.ZERO))
			target_count += 1
	member_center /= float(members.size())
	if target_count <= 0:
		return group.forward
	target_center /= float(target_count)
	var direction := target_center - member_center
	return direction.normalized() if direction.length_squared() > 0.0001 else group.forward
