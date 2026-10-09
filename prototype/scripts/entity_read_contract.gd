class_name RoREntityReadContract
extends RefCounted

const Data := preload("res://scripts/isolated_task_data.gd")
const SCHEMA_VERSION := 1
const RENDER_SCHEMA_KEY := "_ror_render_schema"
# One schema for one-shot and retained projections. No live entity borrowing.
const RENDER_FIELDS := [
	"id", "team", "kind", "entity_type", "source_unit_id", "scenario_object_id",
	"health_unknown", "location_only", "last_known",
	"pos", "previous_pos", "elevation", "source_elevation", "visual_height",
	"hp", "max_hp", "amount", "max_amount", "active", "logical_only",
	"state", "resource_state", "depletion_stage", "visible_when_depleted",
	"harvestable", "resource_type_id", "building_type", "movement_domain",
	"footprint_radius", "selection_radius", "selection_height",
	"anim", "anim_state", "facing", "presentation_facing",
	"death_phase", "death_elapsed", "decay_elapsed", "construction_stage",
	"environment_asset", "environment_variant", "tree_condition", "tree_phase", "tree_fall_elapsed", "tree_fall_duration", "source_felled_graphic_id", "source_felled_asset_name", "display_graphic_id", "source_frame", "source_graphic_id", "source_graphic_asset_name",
	"source_requested_graphic_asset_name", "source_asset_fallback_reason",
	"source_depleted_graphic_id", "source_depleted_asset_name", "combat_enabled", "task", "target_id",
	"target_building_id", "resource_id", "formation_forward", "preferred_formation", "formation_group_id", "carried_amount", "construction_progress"]
const AI_FIELDS := [
	"id", "team", "kind", "entity_type", "source_unit_id", "scenario_object_id",
	"pos", "hp", "max_hp", "state", "task", "target_id", "target_building_id", "diagnostic_reason", "movement_domain", "combat_enabled", "retaliation_target_id", "amount",
	"resource_type_id", "harvestable", "footprint_radius", "rally_point", "attack_range",
	"projectile_id", "blast_range",
	"reachable_builder_ids",
]
const CONTROL_FIELDS := [
	"stance", "attack_damage", "attack_range", "attack_range_min", "attack_period",
	"carry_capacity", "carried_resource_type_id", "resource_id", "gather_stage",
	"worker_role_source_unit_id", "dropoff_id", "diagnostic_reason",
	"construction_progress", "production_progress", "rally_point",
]
const ARRAY_FIELDS := ["behavior_tags", "unit_lineage", "allowed_gatherer_domains"]
const NESTED_RENDER_FIELDS := ["footprint", "presentation_state_overrides"]
const PRIVATE_TRADE_FIELDS := ["target_dock_id", "home_dock_id", "selected_input_resource_type_id", "approach_position", "cargo_goods", "cargo_gold", "trip_count"]

class CopyOnWrite extends RefCounted:
	var value: Dictionary
	var changed := false
	func _init(previous: Dictionary) -> void:
		value = previous
	func put(key: String, next: Variant) -> void:
		if value.has(key) and value[key] == next:
			return
		_edit()
		value[key] = RoRIsolatedTaskData.copy(next)
	func erase(key: String) -> void:
		if value.has(key):
			_edit()
			value.erase(key)
	func _edit() -> void:
		if not changed:
			value = value.duplicate()
			changed = true

static func entity_type(entity: Dictionary) -> String:
	var declared := String(entity.get("entity_type", ""))
	if not declared.is_empty():
		return declared
	# Normalize legacy imports before compact projection; DTOs retain this tag.
	if entity.has("production_queue"):
		return "building"
	if entity.has("resource_type_id") and (entity.has("amount") or not entity.has("team")):
		return "resource"
	return "unit"

static func category(entity: Dictionary) -> String:
	match entity_type(entity):
		"resource": return "resource"
		"building", "foundation": return "building"
		_: return "unit"

static func freeze(record: Dictionary) -> Dictionary:
	# The builder owns all nested containers; the topology registry is reserved
	# for large DTOs, rather than thousands of tiny presentation records.
	Data._freeze(record)
	return record

static func is_render_record(entity: Dictionary) -> bool:
	return entity.is_read_only() and int(entity.get(RENDER_SCHEMA_KEY, -1)) == SCHEMA_VERSION

static var native_kernel: Variant = null
static var native_enabled := true
const NESTED_FIELDS := ARRAY_FIELDS + NESTED_RENDER_FIELDS

static func render(entity: Dictionary, previous: Dictionary = {}) -> Dictionary:
	if is_render_record(entity):
		return entity
	if native_enabled and ClassDB.class_exists("RoRReadModelKernel"):
		if native_kernel == null:
			native_kernel = ClassDB.instantiate("RoRReadModelKernel")
		return native_kernel.project_render(entity, previous, RENDER_FIELDS, NESTED_FIELDS, SCHEMA_VERSION)
	return render_reference(entity, previous)

# Reference/fallback implementation defines the parity contract.
static func render_reference(entity: Dictionary, previous: Dictionary = {}) -> Dictionary:
	if is_render_record(entity):
		return entity
	var edit := CopyOnWrite.new(previous)
	for key in RENDER_FIELDS:
		if key == "entity_type":
			continue
		if entity.has(key):
			edit.put(key, entity[key])
		else:
			edit.erase(key)
	edit.put("entity_type", entity_type(entity))
	edit.put(RENDER_SCHEMA_KEY, SCHEMA_VERSION)
	for key in ARRAY_FIELDS + NESTED_RENDER_FIELDS:
		if entity.has(key):
			edit.put(key, entity[key])
		else:
			edit.erase(key)
	var source_components: Dictionary = entity.get("components", {})
	var components: Dictionary = {}
	var ownership: Dictionary = source_components.get("ownership", {})
	if not ownership.is_empty():
		components["ownership"] = {"civilization_id": int(ownership.get("civilization_id", 13))}
	for name in ["worker", "conversion", "healing"]:
		var source: Dictionary = source_components.get(name, {})
		if not source.is_empty():
			components[name] = {"enabled": bool(source.get("enabled", false))}
	var cargo: Dictionary = source_components.get("cargo", {})
	if not cargo.is_empty():
		components["cargo"] = {"enabled": bool(cargo.get("enabled", false)), "capacity": maxi(0, int(cargo.get("capacity", 0)))}
	var trade: Dictionary = source_components.get("trade", {})
	if not trade.is_empty():
		components["trade"] = {"enabled": bool(trade.get("enabled", false)), "target_building_source_id": int(trade.get("target_building_source_id", -1))}
	edit.put("components", components)
	return freeze(edit.value) if edit.changed or not edit.value.is_read_only() else edit.value


static func ai(entity: Dictionary, observer_team: int = 0, previous: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for key in AI_FIELDS:
		if entity.has(key):
			result[key] = Data.copy(entity[key])
	if observer_team <= 0 or int(entity.get("team", 0)) == observer_team:
		for field in ["resource_id", "path_request_id"]:
			if entity.has(field): result[field] = int(entity[field])
	if entity.has("unit_lineage"):
		result["unit_lineage"] = entity.get("unit_lineage", []).duplicate()
	if entity.has("behavior_tags"):
		result["behavior_tags"] = entity.get("behavior_tags", []).duplicate()
	if entity.has("allowed_gatherer_domains"):
		result["allowed_gatherer_domains"] = entity.get("allowed_gatherer_domains", []).duplicate()
	var worker: Dictionary = entity.get("components", {}).get("worker", {})
	var components := {"worker": {"enabled": bool(worker.get("enabled", false))}}
	if observer_team <= 0 or int(entity.get("team", 0)) == observer_team:
		var order: Dictionary = entity.get("components", {}).get("order", {})
		if not order.is_empty():
			components["order"] = {
				"type": String(order.get("type", "none")),
				"target_entity_id": int(order.get("target_entity_id", -1)),
				"completed": bool(order.get("completed", true)),
				"completion_reason": String(order.get("completion_reason", "")),
			}
	var healing: Dictionary = entity.get("components", {}).get("healing", {})
	if bool(healing.get("enabled", false)):
		components["healing"] = {"enabled": true}
	var combat: Dictionary = entity.get("components", {}).get("combat", {})
	if not combat.is_empty():
		components["combat"] = {
			"projectile_id": int(entity.get("projectile_id", combat.get("projectile_id", -1))),
			"blast_range": float(entity.get("blast_range", combat.get("blast_range", 0.0))),
		}
	var cargo: Dictionary = entity.get("components", {}).get("cargo", {})
	if bool(cargo.get("enabled", false)):
		components["cargo"] = {
			"enabled": true,
			"capacity": maxi(0, int(cargo.get("capacity", 0))),
			"allow_allied": bool(cargo.get("allow_allied", true)),
			"allow_artifacts": bool(cargo.get("allow_artifacts", true)),
		}
		if observer_team <= 0 or int(entity.get("team", 0)) == observer_team:
			components["cargo"]["passenger_ids"] = cargo.get("passenger_ids", []).duplicate()
	var trade: Dictionary = entity.get("components", {}).get("trade", {})
	if bool(trade.get("enabled", false)):
		components["trade"] = {"enabled": true}
		if observer_team <= 0 or int(entity.get("team", 0)) == observer_team:
			for field in PRIVATE_TRADE_FIELDS:
				if trade.has(field):
					components["trade"][field] = trade[field]
	result["components"] = components
	if entity.has("production_queue") and (observer_team <= 0 or int(entity.get("team", 0)) == observer_team):
		var queue: Array = []
		for order_value in entity.get("production_queue", []):
			var order: Dictionary = order_value
			queue.append({
				"order_type": String(order.get("order_type", "unit")),
				"kind": String(order.get("kind", "")),
				"technology_id": int(order.get("technology_id", -1)),
				"status": String(order.get("status", "queued")),
				"population_cost": int(order.get("population_cost", 0)),
			})
		result["production_queue"] = queue
	result["entity_type"] = entity_type(entity)
	return previous if previous.is_read_only() and previous == result else freeze(result)


# Forest observations keep the compact resource contract; rendering fields and
# animation components are not copied into every AI's explored resource list.
static func resource(source: Dictionary) -> Dictionary:
	return freeze({
		"id": int(source.get("id", -1)), "team": int(source.get("team", 0)),
		"kind": String(source.get("kind", "")), "entity_type": String(source.get("entity_type", "resource")),
		"pos": Vector2(source.get("pos", Vector2.ZERO)),
		"movement_domain": String(source.get("movement_domain", source.get("placement_domain", "land"))),
		"resource_type_id": int(source.get("resource_type_id", -1)),
		"harvestable": bool(source.get("harvestable", true)),
		"allowed_gatherer_domains": source.get("allowed_gatherer_domains", []).duplicate(),
		"amount": int(source.get("amount", 0)),
	})
