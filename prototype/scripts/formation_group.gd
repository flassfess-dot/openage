class_name RoRFormationGroup
extends RefCounted

const Geometry := preload("res://scripts/formation_geometry.gd")
const Assignment := preload("res://scripts/formation_assignment.gd")

var group_id: int
var member_ids: Array[int] = []
var anchor: Vector2
var forward: Vector2
var formation_type: String
var preferred_formation_type: String
var spacing: float
var slots: Array = []
var assignments: Dictionary = {}
var state: String = "ASSEMBLE"
var state_ticks: int = 0
var lifecycle_revision: int = 0
var last_transition_reason: String = "created"
var slot_constraint_mode: String = "soft"
var maximum_slot_error: float = INF
var policy: Dictionary = {"orientation": "route", "cohesion": "soft", "engagement": "release"}
var engagement_forward: Vector2 = Vector2.ZERO
var route: Array[Vector2] = []
var corridor_modes: Array[String] = []
var required_corridor_width: int = 1
var has_compression: bool = false


func _init(id: int, members: Array[int], world_anchor: Vector2, world_forward: Vector2, type: String, slot_spacing: float = 1.0) -> void:
	group_id = id
	member_ids = members.duplicate()
	member_ids.sort()
	anchor = world_anchor
	forward = world_forward.normalized() if world_forward.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	engagement_forward = forward
	formation_type = type if Geometry.ALL.has(type) else Geometry.BLOCK
	preferred_formation_type = formation_type
	spacing = maxf(0.1, slot_spacing)
	rebuild_slots()


func rebuild_slots() -> void:
	slots.clear()
	assignments.clear()
	var local := Geometry.local_slots(member_ids.size(), formation_type, spacing)
	var world := Geometry.world_slots(local, anchor, forward)
	for index in range(member_ids.size()):
		var slot := {"slot_id": index, "local": local[index], "world": world[index], "capacity_radius": spacing * 0.45}
		slots.append(slot)
		assignments[member_ids[index]] = index


func assign_units(units: Array, previous_assignments: Dictionary = {}) -> void:
	assignments = Assignment.assign(units, slots, previous_assignments)


func slot_for(entity_id: int) -> Dictionary:
	if not assignments.has(entity_id):
		return {}
	return slots[int(assignments[entity_id])]
