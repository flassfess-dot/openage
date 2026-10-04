class_name RoRRenderWorld

const ResourcePresentationRegistry := preload("res://scripts/resource_presentation_registry.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const AMBIENT_TRAVEL_TICKS := 160
const AMBIENT_WANDER_RADIUS := 8.0
const AMBIENT_MIN_WAYPOINT_RADIUS := 5.0
const AMBIENT_HASH_MODULUS := 2_147_483_647

# These Gaia decorations are flat source artwork. Keeping the compatibility
# mapping here also fixes already packed scenarios produced by older importers.
const GROUND_DECAL_SOURCE_IDS := {
	168: true, 171: true, 173: true, 174: true, 175: true, 176: true, 177: true,
	178: true, 179: true, 180: true, 181: true, 182: true, 183: true,
	187: true, 188: true, 189: true, 190: true, 191: true,
}

var cached_resource_signature: int = 0
var cached_resource_drawables: Array = []
var cached_resource_projection: Variant = null
var cached_environment_signature: int = 0
var cached_environment_drawables: Array = []
var cached_environment_signature_valid := false
var cached_environment_records: Dictionary = {}
var cached_environment_revision := -1
var cached_environment_animated: Array = []
var cached_environment_projection: Variant = null
var performance_probe: Variant = null
var cached_building_depth_index: Dictionary = {}


func clear_caches() -> void:
	cached_building_depth_index.clear()
	cached_resource_signature = 0
	cached_resource_drawables.clear()
	cached_resource_projection = null
	cached_environment_signature = 0
	cached_environment_drawables.clear()
	cached_environment_signature_valid = false
	cached_environment_records.clear()
	cached_environment_revision = -1
	cached_environment_animated.clear()
	cached_environment_projection = null


func create_world_drawables(world_source, world_to_screen: Callable, interpolation_alpha: float = 1.0, frame_info_provider: Callable = Callable(), preview_ids: Array[int] = [], observer_team: int = 0, selected_ids: Array[int] = []) -> Array:
	var stage_started := Time.get_ticks_usec() if performance_probe != null else 0
	var drawables: Array = []
	var alpha := clampf(interpolation_alpha, 0.0, 1.0)
	var preview_id_lookup: Variant = _id_lookup(preview_ids)
	var selected_id_lookup: Variant = _id_lookup(selected_ids)
	var from_snapshot := world_source is Dictionary
	var presentation_tick := float(world_source.get("tick", 0)) if from_snapshot else 0.0
	var source_buildings: Array = world_source.get("buildings", []) if from_snapshot else world_source.get_buildings()
	var source_resources: Array = world_source.get("resources", []) if from_snapshot else world_source.get_resources()
	var source_objectives: Array = world_source.get("objectives", []) if from_snapshot else world_source.victory_objectives
	if not from_snapshot and observer_team > 0:
		# Compatibility renderer calls must obey the same last-known boundary as
		# the main snapshot renderer instead of reading live explored buildings.
		var legal_static: Dictionary = SimulationSnapshot.presentation(world_source, 0, observer_team, {
			"include_navigation": false,
			"include_build_sites": false,
			"include_fog_cells": false,
			"include_projectiles": false,
			"include_scenario": false,
			"include_worker_command_options": false,
			"compact_render_entities": true,
		})
		source_buildings = legal_static.get("buildings", [])
		source_objectives = legal_static.get("objectives", [])
	var source_projectiles: Array = world_source.get("projectiles", []) if from_snapshot else world_source.get_projectiles()
	var source_effects: Array = world_source.get("effects", []) if from_snapshot else []
	var source_markers: Array = world_source.get("markers", []) if from_snapshot else []
	var source_environment: Array = world_source.get("environment", []) if from_snapshot else []
	var source_units: Array = world_source.get("units", []) if from_snapshot else world_source.get_units()
	var resource_drawables: Array = _snapshot_resource_drawables(source_resources, world_to_screen, frame_info_provider, preview_ids + selected_ids) if from_snapshot else []
	_observe_stage("resources", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	var environment_projection := _snapshot_environment_drawables(source_environment, world_to_screen, frame_info_provider, int(world_source.get("environment_revision", -1))) if from_snapshot and world_source.has("environment") else {"static": [], "animated": source_environment}
	var environment_drawables: Array = environment_projection["static"]
	source_environment = environment_projection["animated"]
	_observe_stage("environment_cache", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	cached_building_depth_index = _building_depth_index(source_buildings)
	for building in source_buildings:
		if building["hp"] <= 0.0 and String(building.get("death_phase", "removed")) not in ["dying", "ruin"]:
			continue
		if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, building, true):
			continue
		var building_position: Vector2 = building["pos"]
		var building_screen: Vector2 = world_to_screen.call(building_position)
		var building_info := _frame_info(frame_info_provider, "building", building)
		var building_id := int(building["id"])
		var building_elevation := float(building.get("elevation", 0.0))
		var is_interior_resource := bool(building.get("harvestable", false))
		var base_sub_order := int(building_info.get("graphic_layer", 20)) * 1000 - (100 if is_interior_resource else 0)
		drawables.append(RenderItem.create("building", RenderItem.Layer.DECAL if is_interior_resource else RenderItem.Layer.UNIT_BUILDING, building_position, building_screen, building_id, building, building_info, building_elevation, Color.WHITE, 1.0, base_sub_order))
		var building_part_index := 0
		for part in building_info.get("composite_parts", []):
			building_part_index += 1
			var part_sub_order := int(part.get("graphic_layer", 20)) * 1000 + (100 if is_interior_resource else 0) + building_part_index
			var upright := String(part.get("presentation_layer", "")) == "upright"
			var part_item := RenderItem.create("building_part", RenderItem.Layer.UNIT_BUILDING if upright or not is_interior_resource else RenderItem.Layer.DECAL, building_position, building_screen, building_id, building, part, building_elevation, Color.WHITE, 1.0, part_sub_order)
			var depth_offset: Vector2 = part.get("depth_world_offset", Vector2.ZERO)
			part_item["depth_world_offset"] = depth_offset
			part_item["screen_y"] = Vector2(world_to_screen.call(building_position + depth_offset)).y
			drawables.append(part_item)
		if selected_id_lookup.has(building_id) or preview_id_lookup.has(building_id):
			drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, building_position, building_screen, building_id, building, building_info, building_elevation, RenderItem.color_for_team(int(building.get("team", 0))), 1.0, 1))
	_observe_stage("buildings", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	if not from_snapshot:
		for resource in source_resources:
			if resource["amount"] > 0 or bool(resource.get("visible_when_depleted", false)):
				if observer_team > 0 and not world_source.is_entity_visible_to(observer_team, resource, true):
					continue
				var resource_position: Vector2 = resource["pos"]
				var resource_screen: Vector2 = world_to_screen.call(resource_position)
				var resource_info := _frame_info(frame_info_provider, "resource", resource)
				drawables.append(RenderItem.create("resource", resource_layer(resource), resource_position, resource_screen, int(resource["id"]), resource, resource_info, float(resource.get("elevation", 0.0))))
				if preview_id_lookup.has(int(resource["id"])):
					drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, resource_position, resource_screen, int(resource["id"]), resource, resource_info, float(resource.get("elevation", 0.0)), Color("d6bc63"), 1.0, 1))
	for objective in source_objectives:
		if not bool(objective.get("active", true)) or bool(objective.get("logical_only", false)):
			continue
		if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, objective, true):
			continue
		var objective_info := _frame_info(frame_info_provider, "objective", objective)
		var objective_position: Vector2 = objective.get("pos", Vector2.ZERO)
		drawables.append(RenderItem.create("objective", RenderItem.Layer.UNIT_BUILDING, objective_position, world_to_screen.call(objective_position), int(objective.get("id", -1)), objective, objective_info, float(objective.get("source_elevation", 0.0))))
	for projectile in source_projectiles:
		if not bool(projectile.get("active", true)):
			continue
		if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, projectile):
			continue
		var previous_position: Vector2 = projectile.get("previous_pos", projectile["pos"])
		var render_position: Vector2 = previous_position.lerp(projectile["pos"], alpha)
		var projectile_info := _frame_info(frame_info_provider, "projectile", projectile)
		drawables.append(RenderItem.create("projectile", RenderItem.Layer.PROJECTILE_EFFECT, render_position, world_to_screen.call(render_position), int(projectile["id"]), projectile, projectile_info, float(projectile.get("elevation", 0.0)), RenderItem.color_for_team(int(projectile.get("team", 0)))))
	for effect in source_effects:
		if not bool(effect.get("active", true)):
			continue
		var effect_position: Vector2 = effect.get("pos", Vector2.ZERO)
		var effect_info := _frame_info(frame_info_provider, "effect", effect)
		drawables.append(RenderItem.create("effect", RenderItem.Layer.PROJECTILE_EFFECT, effect_position, world_to_screen.call(effect_position), int(effect.get("id", -1)), effect, effect_info, float(effect.get("elevation", 0.0)), Color.WHITE, 1.0, int(effect_info.get("graphic_layer", 30)) * 1000))
	for marker in source_markers:
		var marker_position: Vector2 = marker.get("position", Vector2.ZERO)
		var marker_info := _frame_info(frame_info_provider, "marker", marker)
		drawables.append(RenderItem.create("marker", RenderItem.Layer.UNIT_BUILDING, marker_position, world_to_screen.call(marker_position), int(marker.get("id", -1)), marker, marker_info, float(marker.get("source_elevation", 0.0)), Color.WHITE, 1.0, int(marker_info.get("graphic_layer", 20)) * 1000))
	for environment_item in source_environment:
		var environment_data: Dictionary = environment_item
		var environment_tick := presentation_tick + alpha
		var environment_position := ambient_actor_position(environment_data, environment_tick)
		if _is_ambient_actor(environment_data):
			environment_data = environment_item.duplicate(false)
			environment_data["presentation_tick"] = presentation_tick
			environment_data["movement_direction"] = ambient_actor_direction(environment_data, environment_tick)
		var environment_info := _frame_info(frame_info_provider, "environment", environment_data)
		var layer := environment_layer(environment_item)
		drawables.append(RenderItem.create("environment", layer, environment_position, world_to_screen.call(environment_position), int(environment_data.get("id", -1)), environment_data, environment_info, float(environment_data.get("source_elevation", 0.0)), Color.WHITE, 1.0, int(environment_info.get("graphic_layer", 0)) * 1000))
	_observe_stage("static_entities", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	for unit in source_units:
		var death_phase := String(unit.get("death_phase", "alive"))
		if unit["hp"] > 0.0 or death_phase in ["dying", "corpse"]:
			if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, unit):
				continue
			var previous_position: Vector2 = unit.get("previous_pos", unit["pos"])
			var render_position: Vector2 = previous_position.lerp(unit["pos"], alpha)
			var unit_screen: Vector2 = world_to_screen.call(render_position)
			var unit_sort_screen := unit_screen
			var depth_offset := _unit_building_depth_offset(render_position, unit_screen.y, cached_building_depth_index, world_to_screen)
			unit_sort_screen.y += depth_offset
			var frame_info := _frame_info(frame_info_provider, "unit", unit)
			var stable_id := int(unit["id"])
			var elevation := float(unit.get("elevation", 0.0))
			var player_color := RenderItem.color_for_team(int(unit.get("team", 0)))
			if death_phase != "corpse":
				drawables.append(RenderItem.create("shadow", RenderItem.Layer.SHADOW, render_position, unit_screen, stable_id, unit, {}, elevation, Color(0.0, 0.0, 0.0, 0.32)))
			var unit_base_sub_order := int(frame_info.get("graphic_layer", 20)) * 1000
			var unit_item := RenderItem.create("unit", RenderItem.Layer.UNIT_BUILDING, render_position, unit_screen, stable_id, unit, frame_info, elevation, player_color, 1.0, unit_base_sub_order)
			unit_item["screen_y"] = unit_sort_screen.y
			unit_item["depth_offset"] = depth_offset
			drawables.append(unit_item)
			var unit_part_index := 0
			for part_value in frame_info.get("composite_parts", []):
				var part: Dictionary = part_value
				unit_part_index += 1
				var part_sub_order := int(part.get("graphic_layer", 20)) * 1000 + unit_part_index
				var unit_part_item := RenderItem.create("unit_part", RenderItem.Layer.UNIT_BUILDING, render_position, unit_screen, stable_id, unit, part, elevation, player_color, 1.0, part_sub_order)
				unit_part_item["screen_y"] = unit_sort_screen.y
				unit_part_item["depth_offset"] = depth_offset
				drawables.append(unit_part_item)
			var highlighted: bool = selected_id_lookup.has(stable_id) or bool(unit.get("selected", false)) or preview_id_lookup.has(stable_id)
			if death_phase == "alive" and highlighted:
				drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, render_position, unit_screen, stable_id, unit, frame_info, elevation, player_color, 1.0, 1))
			if death_phase == "alive" and highlighted:
				drawables.append(RenderItem.create("health_bar", RenderItem.Layer.HEALTH_BAR, render_position, unit_screen, stable_id, unit, frame_info, elevation, player_color, 1.0, 2))
	_observe_stage("units", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	drawables = _sort_drawables_by_layer(drawables)
	_observe_stage("sort", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	var result: Array = drawables
	if not environment_drawables.is_empty():
		result = _merge_sorted_drawables(result, environment_drawables)
	if not resource_drawables.is_empty():
		result = _merge_sorted_drawables(result, resource_drawables)
	_observe_stage("merge", stage_started)
	return result


static func _sort_drawables_by_layer(drawables: Array) -> Array:
	# Layer is the primary RenderItem order key. Partition first so the custom
	# comparator only runs inside a layer instead of repeatedly comparing known,
	# unequal layers during the global sort.
	var layer_buckets: Array = []
	layer_buckets.resize(RenderItem.Layer.size())
	for layer_index in range(layer_buckets.size()):
		layer_buckets[layer_index] = []
	for drawable_value in drawables:
		var drawable: Dictionary = drawable_value
		var layer := clampi(int(drawable.get("layer", RenderItem.Layer.UNIT_BUILDING)), 0, layer_buckets.size() - 1)
		layer_buckets[layer].append(drawable)
	var result: Array = []
	result.resize(drawables.size())
	var result_index := 0
	for bucket_value in layer_buckets:
		var bucket: Array = bucket_value
		if bucket.size() > 1:
			bucket.sort_custom(RenderItem.less_same_layer)
		for drawable in bucket:
			result[result_index] = drawable
			result_index += 1
	return result


static func _id_lookup(entity_ids: Array[int]) -> Variant:
	# Linear membership is cheaper for the common empty/small selection and
	# avoids allocating two lookup dictionaries every rendered frame. Large
	# selections switch to O(1) membership for the entity traversal below.
	if entity_ids.size() <= 8:
		return entity_ids
	var result: Dictionary = {}
	for entity_id in entity_ids:
		result[entity_id] = true
	return result


static func ambient_actor_position(item: Dictionary, tick: float) -> Vector2:
	var origin := Vector2(item.get("position", Vector2.ZERO))
	if not _is_ambient_actor(item):
		return origin
	var cycle := floori(maxf(0.0, tick) / float(AMBIENT_TRAVEL_TICKS))
	var cycle_tick := maxf(0.0, tick) - float(cycle * AMBIENT_TRAVEL_TICKS)
	var from_offset := _ambient_offset(int(item.get("id", 0)), cycle)
	var to_offset := _ambient_offset(int(item.get("id", 0)), cycle + 1)
	var progress := clampf(cycle_tick / float(AMBIENT_TRAVEL_TICKS), 0.0, 1.0)
	var eased_progress := progress * progress * (3.0 - 2.0 * progress)
	var position := origin + from_offset.lerp(to_offset, eased_progress)
	var map_size_value: Variant = item.get("map_size", Vector2.ZERO)
	var map_size := Vector2.ZERO
	if map_size_value is Vector2 or map_size_value is Vector2i:
		map_size = Vector2(map_size_value)
	elif map_size_value is Array and map_size_value.size() >= 2:
		map_size = Vector2(float(map_size_value[0]), float(map_size_value[1]))
	if map_size.x > 1.0 and map_size.y > 1.0:
		position = position.clamp(Vector2(0.5, 0.5), map_size - Vector2(0.5, 0.5))
	return position


static func ambient_actor_direction(item: Dictionary, tick: float) -> Vector2:
	if not _is_ambient_actor(item):
		return Vector2.ZERO
	var before := ambient_actor_position(item, maxf(0.0, tick - 0.5))
	var after := ambient_actor_position(item, tick + 0.5)
	var direction := after - before
	if direction.length_squared() <= 0.000001:
		direction = ambient_actor_position(item, tick + 1.0) - ambient_actor_position(item, tick)
	return direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT


static func _is_ambient_actor(item: Dictionary) -> bool:
	return String(item.get("presentation_layer", "scenery")) == "ambient_actor"


static func environment_layer(item: Dictionary) -> int:
	# Compatibility for generated or saved shoals carrying the old scenery role.
	if item.get("decoration_key", "") == "ror_shallows" or item.get("asset_name", "") == "aoe2_temperate:ror_shallows" or int(item.get("graphic_id", -1)) == 503:
		return RenderItem.Layer.DECAL
	match String(item.get("presentation_layer", "scenery")):
		"decal":
			return RenderItem.Layer.DECAL
		"ambient_actor":
			return RenderItem.Layer.AIRBORNE
	if GROUND_DECAL_SOURCE_IDS.has(int(item.get("source_unit_id", -1))):
		return RenderItem.Layer.DECAL
	return RenderItem.Layer.UNIT_BUILDING


static func _ambient_offset(entity_id: int, cycle: int) -> Vector2:
	if cycle <= 0:
		return Vector2.ZERO
	var angle_index := _ambient_roll(entity_id, cycle, 31, 32)
	var radius_roll := float(_ambient_roll(entity_id, cycle, 47, 1000)) / 999.0
	var radius := lerpf(AMBIENT_MIN_WAYPOINT_RADIUS, AMBIENT_WANDER_RADIUS, radius_roll)
	return Vector2.RIGHT.rotated(TAU * float(angle_index) / 32.0) * radius


static func _ambient_roll(entity_id: int, cycle: int, salt: int, limit: int) -> int:
	var state := posmod(entity_id * 48_271 + cycle * 69_621 + salt * 17, AMBIENT_HASH_MODULUS)
	state = posmod(state * 48_271 + 1, AMBIENT_HASH_MODULUS)
	return posmod(state, maxi(1, limit))


func _reproject_statics(drawables: Array, world_to_screen: Callable) -> void:
	for drawable_value in drawables:
		var drawable: Dictionary = drawable_value
		var screen: Vector2 = world_to_screen.call(drawable["world_anchor"])
		drawable["screen_position"] = screen
		drawable["screen_y"] = screen.y

static func resource_layer(resource: Dictionary) -> int:
	# Carcasses and harvested trunks lie on the ground, below workers on any side.
	if "carcass" in resource.get("behavior_tags", []) or String(resource.get("tree_phase", "")) in ["felled", "stump"]:
		return RenderItem.Layer.DECAL
	return RenderItem.Layer.UNIT_BUILDING


func _snapshot_resource_drawables(resources: Array, world_to_screen: Callable, frame_info_provider: Callable, preview_ids: Array[int]) -> Array:
	var projection := hash([world_to_screen.call(Vector2.ZERO), world_to_screen.call(Vector2.ONE)])
	if cached_resource_projection != projection:
		_reproject_statics(cached_resource_drawables, world_to_screen)
		cached_resource_projection = projection
	if resources.is_empty():
		return []
	var signature := 17
	for resource_value in resources:
		var resource: Dictionary = resource_value
		signature = signature * 31 + int(resource.get("id", -1))
		signature = signature * 31 + int(resource.get("depletion_stage", 0))
		signature = signature * 31 + hash(String(resource.get("tree_phase", "")))
		signature = signature * 31 + hash(String(resource.get("environment_asset", "")))
		signature = signature * 31 + int(resource.get("environment_variant", 0))
		signature = signature * 31 + hash(String(resource.get("source_graphic_asset_name", "")))
		signature = signature * 31 + int(resource.get("source_frame", 0))
		signature = signature * 31 + (1 if int(resource.get("amount", 0)) > 0 else 0)
	signature = signature * 31 + hash(preview_ids)
	if signature == cached_resource_signature and not cached_resource_drawables.is_empty():
		var current_by_id: Dictionary = {}
		for resource_value in resources:
			var resource: Dictionary = resource_value
			current_by_id[int(resource.get("id", -1))] = resource
		for drawable_value in cached_resource_drawables:
			var drawable: Dictionary = drawable_value
			var resource_id := int(drawable.get("stable_id", -1))
			if current_by_id.has(resource_id):
				drawable["data"] = current_by_id[resource_id]
				if String(current_by_id[resource_id].get("kind", "")) in ResourcePresentationRegistry.ANIMATED_MARINE_KINDS or String(current_by_id[resource_id].get("tree_phase", "")) == "falling":
					var frame_info := _frame_info(frame_info_provider, "resource", current_by_id[resource_id])
					drawable["frame_info"] = frame_info
					drawable["frame"] = int(frame_info.get("frame_index", 0))
					drawable["hotspot"] = frame_info.get("hotspot", Vector2.ZERO)
		return cached_resource_drawables
	cached_resource_signature = signature
	cached_resource_drawables = []
	var preview_id_lookup: Variant = _id_lookup(preview_ids)
	for resource_value in resources:
		var resource: Dictionary = resource_value
		if int(resource.get("amount", 0)) <= 0 and not bool(resource.get("visible_when_depleted", false)):
			continue
		var position: Vector2 = resource.get("pos", Vector2.ZERO)
		var resource_id := int(resource.get("id", -1))
		var resource_info := _frame_info(frame_info_provider, "resource", resource)
		var resource_screen: Vector2 = world_to_screen.call(position)
		var elevation := float(resource.get("elevation", 0.0))
		cached_resource_drawables.append(RenderItem.create("resource", resource_layer(resource), position, resource_screen, resource_id, resource, resource_info, elevation))
		if preview_id_lookup.has(resource_id):
			cached_resource_drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, position, resource_screen, resource_id, resource, resource_info, elevation, Color("d6bc63"), 1.0, 1))
	cached_resource_drawables.sort_custom(RenderItem.less)
	return cached_resource_drawables


func _snapshot_environment_drawables(environment_items: Array, world_to_screen: Callable, frame_info_provider: Callable, revision: int = -1) -> Dictionary:
	# Pan/zoom preserves depth order, but cached and newly entering items must
	# share the current projection before merging with units and buildings.
	var projection := hash([world_to_screen.call(Vector2.ZERO), world_to_screen.call(Vector2.ONE)])
	if cached_environment_projection != projection:
		_reproject_statics(cached_environment_drawables, world_to_screen)

		cached_environment_projection = projection
	# The main scene publishes a revision for its immutable spatial query.
	# Avoid hashing every decoration again on all 20 simulation ticks.
	if revision >= 0 and cached_environment_signature_valid and revision == cached_environment_revision:
		return {"static": cached_environment_drawables, "animated": cached_environment_animated}
	var animated: Array = []
	var wanted: Dictionary = {}
	var signature := 17
	for item_value in environment_items:
		var item: Dictionary = item_value
		if bool(item.get("animated", false)):
			animated.append(item)
			continue
		var item_id := int(item.get("id", -1))
		var item_signature := hash([item_id, item.get("graphic_id", -1), item.get("asset_name", ""), item.get("position", Vector2.ZERO), item.get("source_frame", 0), item.get("presentation_layer", "scenery"), item.get("source_elevation", 0.0), item.get("source_unit_id", -1), item.get("cliff_screen_offset", Vector2.ZERO)])
		wanted[item_id] = {"signature": item_signature, "item": item}
		signature = signature * 31 + item_signature
	cached_environment_revision = revision
	cached_environment_animated = animated
	if cached_environment_signature_valid and signature == cached_environment_signature:
		return {"static": cached_environment_drawables, "animated": animated}
	var retained: Dictionary = {}
	var next_records: Dictionary = {}
	var added: Array = []
	for item_id in wanted:
		var entry: Dictionary = wanted[item_id]
		var item: Dictionary = entry["item"]
		var previous: Dictionary = cached_environment_records.get(item_id, {})
		if not previous.is_empty() and int(previous["signature"]) == int(entry["signature"]):
			previous["drawable"]["data"] = item
			next_records[item_id] = previous
			retained[item_id] = true
			continue
		var position: Vector2 = item.get("position", Vector2.ZERO)
		var frame_info := _frame_info(frame_info_provider, "environment", item)
		var drawable := RenderItem.create("environment", environment_layer(item), position, world_to_screen.call(position), item_id, item, frame_info, float(item.get("source_elevation", 0.0)), Color.WHITE, 1.0, int(frame_info.get("graphic_layer", 0)) * 1000)
		next_records[item_id] = {"signature": entry["signature"], "drawable": drawable}
		added.append(drawable)
	var kept: Array = []
	for drawable_value in cached_environment_drawables:
		var drawable: Dictionary = drawable_value
		if retained.has(int(drawable["stable_id"])):
			kept.append(drawable)
	added.sort_custom(RenderItem.less)
	cached_environment_drawables = merge_sorted_drawables(kept, added)
	# Evict offscreen records: memory is bounded by the current query, not by
	# how much of a supergiant map the player has visited.
	cached_environment_records = next_records
	cached_environment_signature = signature
	cached_environment_signature_valid = true
	if performance_probe != null:
		performance_probe.increment("presentation.environment.frames_resolved", added.size())
		performance_probe.increment("presentation.environment.frames_reused", kept.size())
	return {"static": cached_environment_drawables, "animated": animated}

func merge_sorted_drawables(first: Array, second: Array) -> Array:
	# Both inputs are sorted by the strict total RenderItem order (distinct
	# entities never tie), so this linear merge yields exactly the order a full
	# re-sort would produce while touching each item once.
	var result: Array = []
	result.resize(first.size() + second.size())
	var first_index := 0
	var second_index := 0
	var result_index := 0
	while first_index < first.size() or second_index < second.size():
		if second_index >= second.size() or (first_index < first.size() and RenderItem.less(first[first_index], second[second_index])):
			result[result_index] = first[first_index]
			first_index += 1
		else:
			result[result_index] = second[second_index]
			second_index += 1
		result_index += 1
	return result


func _merge_sorted_drawables(first: Array, second: Array) -> Array:
	return merge_sorted_drawables(first, second)


const INTERPOLATED_KINDS := ["unit", "unit_part", "shadow", "selection", "health_bar"]


func refresh_world_drawables(drawables: Array, world_to_screen: Callable, interpolation_alpha: float = 1.0, projection_changed: bool = true) -> Array:
	# Frame descriptors, composite parts and render-item dictionaries are stable
	# for one published presentation revision. Between fixed simulation ticks only
	# interpolation changes, so update anchors in place instead of rebuilding the
	# complete render queue and resolving every sprite again.
	var alpha := clampf(interpolation_alpha, 0.0, 1.0)
	var moved := false
	for drawable_value in drawables:
		var drawable: Dictionary = drawable_value
		var kind := String(drawable.get("kind", ""))
		var data: Dictionary = drawable.get("data", {})
		var position: Variant = null
		if kind == "environment" and _is_ambient_actor(data):
			var ambient_tick := float(data.get("presentation_tick", 0.0)) + alpha
			position = ambient_actor_position(data, ambient_tick)
			data["movement_direction"] = ambient_actor_direction(data, ambient_tick)
		elif _is_interpolated_drawable(kind, data):
			position = Vector2(data.get("previous_pos", data.get("pos", Vector2.ZERO))).lerp(Vector2(data.get("pos", Vector2.ZERO)), alpha)
		if position == null:
			# Static drawables keep their world anchor; their screen position only
			# changes with the camera, and the affine pan/zoom projection preserves
			# relative depth order, so no re-sort is needed for them.
			if projection_changed:
				var static_screen: Vector2 = world_to_screen.call(Vector2(drawable.get("world_anchor", Vector2.ZERO)))
				drawable["screen_position"] = static_screen
				var sort_offset := Vector2(drawable.get("depth_world_offset", Vector2.ZERO))
				drawable["screen_y"] = Vector2(world_to_screen.call(Vector2(drawable.get("world_anchor", Vector2.ZERO)) + sort_offset)).y
			continue
		var resolved_position: Vector2 = position
		if not resolved_position.is_equal_approx(Vector2(drawable.get("world_anchor", resolved_position))):
			moved = true
		drawable["world_anchor"] = resolved_position
		var screen_position: Vector2 = world_to_screen.call(resolved_position)
		drawable["screen_position"] = screen_position
		if kind in ["unit", "unit_part"]:
			drawable["depth_offset"] = _unit_building_depth_offset(resolved_position, screen_position.y, cached_building_depth_index, world_to_screen)
		drawable["screen_y"] = screen_position.y + float(drawable.get("depth_offset", 0.0))
	if projection_changed:
		var projection := hash([world_to_screen.call(Vector2.ZERO), world_to_screen.call(Vector2.ONE)])
		cached_resource_projection = projection
		cached_environment_projection = projection
	if moved:
		var static_drawables: Array = []
		var moving_drawables: Array = []
		for drawable_value in drawables:
			var drawable: Dictionary = drawable_value
			var data: Dictionary = drawable.get("data", {})
			if _is_dynamic_drawable(String(drawable.get("kind", "")), data):
				moving_drawables.append(drawable)
			else:
				static_drawables.append(drawable)
		moving_drawables.sort_custom(RenderItem.less)
		var merged := merge_sorted_drawables(static_drawables, moving_drawables)
		for index in range(drawables.size()):
			drawables[index] = merged[index]
	return drawables


func _is_interpolated_drawable(kind: String, data: Dictionary) -> bool:
	return kind == "projectile" or (kind in INTERPOLATED_KINDS and String(data.get("movement_domain", "land")) != "static")


func _is_dynamic_drawable(kind: String, data: Dictionary) -> bool:
	return _is_interpolated_drawable(kind, data) or (kind == "environment" and _is_ambient_actor(data))


func _frame_info(provider: Callable, kind: String, data: Variant) -> Dictionary:
	if provider.is_valid():
		var result: Variant = provider.call(kind, data)
		if result is Dictionary:
			return result
	return {}


func _observe_stage(stage: String, started: int) -> void:
	if performance_probe != null:
		performance_probe.observe_microseconds("presentation.draw.world_prepare.%s" % stage, Time.get_ticks_usec() - started)



static func _unit_building_depth_offset(position: Vector2, screen_y: float, index: Dictionary, project: Callable) -> float:
	var adjusted := screen_y
	for building in index.get(Vector2i((position / 4.0).floor()), []):
		if bool(building.get("harvestable", false)) or float(building.get("hp", 0.0)) <= 0.0:
			continue
		var center := Vector2(building["pos"])
		var half := Vector2(building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5)))
		var offset := position - center
		if absf(offset.x) > half.x + 1.5 or absf(offset.y) > half.y + 1.5:
			continue
		if offset.x >= half.x or offset.y >= half.y:
			adjusted = maxf(adjusted, Vector2(project.call(center)).y + 0.01)
	return adjusted - screen_y


static func _building_depth_index(buildings: Array) -> Dictionary:
	var index: Dictionary = {}
	for building in buildings:
		if bool(building.get("harvestable", false)) or float(building.get("hp", 0.0)) <= 0.0:
			continue
		var center := Vector2(building["pos"])
		var extent := Vector2(building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5))) + Vector2.ONE * 1.5
		var first := Vector2i(((center - extent) / 4.0).floor())
		var last := Vector2i(((center + extent) / 4.0).floor())
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, y)
				if not index.has(key):
					index[key] = []
				index[key].append(building)
	return index
