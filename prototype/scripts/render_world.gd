class_name RoRRenderWorld

const FishShoalSelection := preload("res://scripts/fish_shoal_selection.gd")
const PickingService := preload("res://scripts/picking_service.gd")
const ResourcePresentationRegistry := preload("res://scripts/resource_presentation_registry.gd")
const RenderItem := preload("res://scripts/render_item.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SpriteAtlas := preload("res://scripts/sprite_atlas.gd")
var sprite_atlas := SpriteAtlas.new()
var sprite_atlas_enabled := true
var native_buildings_enabled := true
var sprite_template_cache := {"entries":{},"bytes":0}
var sprite_template_atlas := true
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

var player_palette

func team_color(team: int) -> Color:
	return player_palette.color_for_team(team) if player_palette != null else RenderItem.color_for_team(team)

var cached_resource_signature: int = 0
var cached_resource_drawables: Array = []
var cached_resource_projection: Variant = null
var cached_resource_records: Dictionary = {}
var cached_resource_raw_drawables: Array = []
var cached_resource_input: Array = []
var cached_resource_highlights: Array[int] = []
var cached_resource_animated: Array = []
var cached_sprite_scale := 0.0
var affine_static_projection := true
var cached_resource_origin: Variant = null
var cached_resource_scale := 0.0
var cached_resource_group_selections: Array = []
var cached_environment_origin: Variant = null
var cached_environment_scale := 0.0
var cached_resource_clip: Dictionary = {}
var cached_environment_clip: Dictionary = {}
var cached_environment_signature: int = 0
var cached_environment_drawables: Array = []
var cached_environment_signature_valid := false
var cached_environment_records: Dictionary = {}
var cached_environment_revision := -1
var cached_environment_animated: Array = []
var cached_environment_projection: Variant = null
var performance_probe: Variant = null
var cached_building_depth_index: Dictionary = {}
var cached_building_records: Dictionary = {}
var rally_drawables: Array = []
var camera_cache_ready := false
var camera_actor_items: Array = []
var camera_actor_statics: Array = []
var current_projection_origin := Vector2.ZERO
var cached_refresh_input: Array = []
var cached_refresh_static: Array = []
var cached_refresh_moving: Array = []
var cached_refresh_ambient: Array = []
var native_render_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null


func clear_caches() -> void:
	sprite_atlas.clear()
	sprite_template_cache = {"entries":{},"bytes":0}
	cached_building_depth_index.clear()
	cached_building_records.clear()
	camera_cache_ready = false
	camera_actor_items = []
	camera_actor_statics = []
	cached_refresh_input = []
	cached_refresh_static = []
	cached_refresh_moving = []
	cached_refresh_ambient = []
	cached_resource_signature = 0
	cached_resource_drawables.clear()
	cached_resource_projection = null
	cached_resource_records.clear()
	cached_resource_raw_drawables.clear()
	cached_resource_input = []
	cached_resource_highlights = []
	cached_resource_animated.clear()
	cached_resource_origin = null
	cached_environment_origin = null
	cached_resource_group_selections.clear()
	cached_resource_clip.clear()
	cached_environment_clip.clear()
	cached_environment_signature = 0
	cached_environment_drawables.clear()
	cached_environment_signature_valid = false
	cached_environment_records.clear()
	cached_environment_revision = -1
	cached_environment_animated.clear()
	cached_environment_projection = null


func create_world_drawables(world_source, world_to_screen: Callable, interpolation_alpha: float = 1.0, frame_info_provider: Callable = Callable(), preview_ids: Array[int] = [], observer_team: int = 0, selected_ids: Array[int] = [], sprite_scale: float = 0.0, viewport: Rect2 = Rect2()) -> Array:
	var stage_started := Time.get_ticks_usec() if performance_probe != null else 0
	var drawables: Array = []
	rally_drawables = []
	current_projection_origin = world_to_screen.call(Vector2.ZERO)
	if world_source is Dictionary and not world_source.has("resources"): cached_sprite_scale = sprite_scale
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
	var resource_drawables: Array = _snapshot_resource_drawables(source_resources, world_to_screen, frame_info_provider, preview_ids + selected_ids, sprite_scale, world_source.get("resource_delta", {}), viewport) if from_snapshot and world_source.has("resources") else []
	if viewport.has_area(): resource_drawables = _visible_static_drawables(resource_drawables, viewport, cached_resource_clip)
	_observe_stage("resources", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	var environment_projection := _snapshot_environment_drawables(source_environment, world_to_screen, frame_info_provider, int(world_source.get("environment_revision", -1)), viewport) if from_snapshot and world_source.has("environment") else {"static": [], "animated": source_environment}
	var environment_drawables: Array = environment_projection["static"]
	if viewport.has_area(): environment_drawables = _visible_static_drawables(environment_drawables, viewport, cached_environment_clip)
	source_environment = environment_projection["animated"]
	_observe_stage("environment_cache", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	cached_building_depth_index = _building_depth_index(source_buildings, frame_info_provider)
	if performance_probe != null: performance_probe.observe_microseconds("presentation.building.depth_index", Time.get_ticks_usec() - stage_started)
	var building_frames_us := 0
	var building_items_started := Time.get_ticks_usec() if performance_probe != null else 0
	if from_snapshot and native_buildings_enabled and native_render_kernel != null and native_render_kernel.has_method("create_building_render_items"):
		var batch: Dictionary = native_render_kernel.create_building_render_items(source_buildings, world_to_screen, frame_info_provider, Callable(self, "team_color"), cached_building_records, preview_ids, selected_ids, observer_team, sprite_scale, _can_project_visible(viewport), Callable(self, "_cache_sprite_batch"))
		drawables.append_array(batch["items"])
		rally_drawables = batch["rally"]
	else:
		var present_buildings: Dictionary = {}
		var moved_building_items: Array = []
		for building in source_buildings:
			if building["hp"] <= 0.0 and String(building.get("death_phase", "removed")) not in ["dying", "ruin"]:
				continue
			if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, building, true):
				continue
			var building_position: Vector2 = building["pos"]
			var building_screen: Vector2 = world_to_screen.call(building_position)
			var info_started := Time.get_ticks_usec() if performance_probe != null else 0
			var building_info := _frame_info(frame_info_provider, "building", building)
			if performance_probe != null: building_frames_us += Time.get_ticks_usec() - info_started
			var building_id := int(building["id"])
			var building_elevation := float(building.get("elevation", 0.0))
			var is_ruin := String(building.get("death_phase", "")) == "ruin"
			var is_interior_resource := bool(building.get("harvestable", false)) or is_ruin
			var base_sub_order := int(building_info.get("graphic_layer", 20)) * 1000 - (100 if is_interior_resource else 0)
			present_buildings[building_id] = true
			var selected: bool = selected_id_lookup.has(building_id)
			var previewed: bool = preview_id_lookup.has(building_id)
			var has_rally := selected and bool(building.get("rally_point_set", false))
			var retained: Dictionary = cached_building_records.get(building_id, {})
			# The catalog may lend its recursively readonly, time-invariant frame.
			# Actor/control records can change without walking that composition again.
			var info_signature: int = retained["info_signature"] if building_info.is_read_only() and is_same(retained.get("frame_info"), building_info) else hash(building_info)
			var signature := hash([info_signature, building_position, building_elevation, String(building.get("kind", "")), is_interior_resource, selected, previewed, observer_team])
			if not has_rally and retained.get("signature") == signature:
				var moved: bool = retained["screen"] != building_screen or float(retained["scale"]) != cached_sprite_scale
				var changed: bool = not is_same(retained["source"], building)
				if moved or changed:
					for item in retained["items"]:
						if changed: item["data"] = building
						if moved:
							if _can_project_visible(viewport):
								moved_building_items.append(item)
							else:
								item["screen_position"] = building_screen
								item["screen_y"] = Vector2(world_to_screen.call(building_position + Vector2(item.get("depth_world_offset", Vector2.ZERO)))).y
								_cache_resource_sprite(item)
				retained["screen"] = building_screen
				retained["scale"] = cached_sprite_scale
				retained["source"] = building
				drawables.append_array(retained["items"])
				continue
			var first_item := drawables.size()
			drawables.append(RenderItem.create("building", RenderItem.Layer.DECAL if is_interior_resource else RenderItem.Layer.UNIT_BUILDING, building_position, building_screen, building_id, building, building_info, building_elevation, Color.WHITE, 1.0, base_sub_order))
			var building_part_index := 0
			for part in building_info.get("composite_parts", []):
				building_part_index += 1
				var part_sub_order := int(part.get("graphic_layer", 20)) * 1000 + (100 if is_interior_resource else 0) + building_part_index
				var upright := not is_ruin and String(part.get("presentation_layer", "")) == "upright"
				var part_layer := RenderItem.Layer.SHADOW if String(part.get("presentation_layer", "")) == "shadow" else RenderItem.Layer.UNIT_BUILDING if upright or not is_interior_resource else RenderItem.Layer.DECAL
				var part_item := RenderItem.create("building_part", part_layer, building_position, building_screen, building_id, building, part, building_elevation, Color.WHITE, 1.0, part_sub_order)
				var depth_offset: Vector2 = part.get("depth_world_offset", Vector2.ZERO)
				part_item["depth_world_offset"] = depth_offset
				part_item["screen_y"] = Vector2(world_to_screen.call(building_position + depth_offset)).y
				drawables.append(part_item)
			if selected_id_lookup.has(building_id) or preview_id_lookup.has(building_id):
				drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, building_position, building_screen, building_id, building, building_info, building_elevation, team_color(int(building.get("team", 0))), 1.0, 1))
			if selected_id_lookup.has(building_id) and int(building.get("team", 0)) == observer_team and bool(building.get("rally_point_set", false)) and float(building.get("hp", 0.0)) > 0.0 and String(building.get("state", "")) == "complete":
				var rally_position := Vector2(building.get("rally_point", building_position))
				var rally_info := _frame_info(frame_info_provider, "rally_flag", building)
				var flag := RenderItem.create("rally_flag", RenderItem.Layer.UNIT_BUILDING, rally_position, world_to_screen.call(rally_position), building_id, building, rally_info, 0.0, team_color(observer_team), 1.0, 20_001)
				drawables.append(flag)
				rally_drawables.append(flag)
			var items := drawables.slice(first_item)
			for item in items: _cache_resource_sprite(item)
			cached_building_records[building_id] = {"signature": signature, "frame_info": building_info, "info_signature": info_signature, "items": items, "source": building, "screen": building_screen, "scale": cached_sprite_scale}
		if not moved_building_items.is_empty(): native_render_kernel.project_visible_static_items(moved_building_items, current_projection_origin, sprite_scale, Rect2())
		for id in cached_building_records.keys():
			if not present_buildings.has(id): cached_building_records.erase(id)
	if performance_probe != null:
		performance_probe.observe_microseconds("presentation.building.frames", building_frames_us)
		performance_probe.observe_microseconds("presentation.building.items", Time.get_ticks_usec() - building_items_started - building_frames_us)
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
				_append_resource_shadow(drawables, resource, resource_info, resource_position, resource_screen)
				if preview_id_lookup.has(int(resource["id"])) and PickingService.resource_is_selectable(resource):
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
		drawables.append(RenderItem.create("projectile", RenderItem.Layer.PROJECTILE_EFFECT, render_position, world_to_screen.call(render_position), int(projectile["id"]), projectile, projectile_info, float(projectile.get("elevation", 0.0)), team_color(int(projectile.get("team", 0)))))
	drawables.append_array(create_effect_drawables(source_effects, world_to_screen, frame_info_provider))
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
	if not from_snapshot:
		drawables = FishShoalSelection.group_drawables(drawables, preview_ids + selected_ids, world_to_screen)
	_observe_stage("static_entities", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	if from_snapshot and native_render_kernel != null and native_render_kernel.has_method("create_unit_render_items"):
		drawables.append_array(native_render_kernel.create_unit_render_items(source_units, world_to_screen, frame_info_provider, Callable(self, "team_color"), alpha, cached_building_depth_index, preview_ids, selected_ids))
	else:
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
				var player_color := team_color(int(unit.get("team", 0)))
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
	if sprite_scale > 0.0 and native_render_kernel != null and native_render_kernel.has_method("cache_actor_sprites"): native_render_kernel.cache_actor_sprites(drawables, sprite_scale)
	_observe_stage("units", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	drawables = native_render_kernel.sort_render_items(drawables) if native_render_kernel != null and native_render_kernel.has_method("sort_render_items") else _sort_drawables_by_layer(drawables)
	camera_actor_items = drawables
	camera_actor_statics = []
	if affine_static_projection and sprite_scale > 0.0 and native_render_kernel != null and native_render_kernel.has_method("project_visible_static_items"):
		camera_actor_statics = native_render_kernel.partition_render_items(camera_actor_items)["static"]
		native_render_kernel.project_visible_static_items(camera_actor_statics, current_projection_origin, sprite_scale, Rect2())
	camera_cache_ready = true
	if sprite_scale > 0.0:
		if native_buildings_enabled and native_render_kernel != null and native_render_kernel.has_method("clip_building_render_items"):
			drawables = native_render_kernel.clip_building_render_items(drawables, viewport)
		else:
			var visible: Array = []
			for item in drawables:
				if String(item["kind"]) in ["building", "building_part"]:
					if viewport.has_area() and item.has("sprite_command") and not viewport.intersects(item["sprite_command"][1], true): continue
				visible.append(item)
			drawables = visible
	_observe_stage("sort", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	var result: Array = drawables
	if not environment_drawables.is_empty():
		result = _merge_sorted_drawables(result, environment_drawables)
	if not resource_drawables.is_empty():
		result = _merge_sorted_drawables(result, resource_drawables)
	_observe_stage("merge", stage_started)
	sprite_atlas.flush()
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
		"shadow":
			return RenderItem.Layer.SHADOW
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


func _reproject_statics(drawables: Array, world_to_screen: Callable, old_origin: Variant = null, old_scale: float = 0.0) -> void:
	var origin: Vector2 = world_to_screen.call(Vector2.ZERO)
	var affine := affine_static_projection and old_origin is Vector2 and old_scale > 0.0 and cached_sprite_scale > 0.0
	if affine and native_render_kernel != null and native_render_kernel.has_method("reproject_static_items"):
		native_render_kernel.reproject_static_items(drawables, origin, old_origin, old_scale, cached_sprite_scale)
		return
	for drawable_value in drawables:
		var drawable: Dictionary = drawable_value
		var screen: Vector2
		if affine:
			# Derive once, then reuse the original local anchor. Repeated pans
			# must not accumulate rounding error or query terrain per object.
			if not drawable.has("projection_anchor"):
				drawable["projection_anchor"] = (Vector2(drawable["screen_position"]) - Vector2(old_origin)) / old_scale
			screen = Vector2(drawable["projection_anchor"]) * cached_sprite_scale + origin
		else:
			screen = world_to_screen.call(drawable["world_anchor"])
			if cached_sprite_scale > 0.0: drawable["projection_anchor"] = (screen - origin) / cached_sprite_scale
		drawable["screen_position"] = screen
		drawable["screen_y"] = screen.y
		if String(drawable["kind"]) in ["resource", "resource_shadow", "building", "building_part", "environment"]: _cache_resource_sprite(drawable)


func _cache_sprite_batch(items: Array) -> void:
	if native_render_kernel != null and native_render_kernel.has_method("cache_sprite_items"):
		if sprite_template_atlas != sprite_atlas_enabled:
			sprite_template_cache = {"entries":{},"bytes":0}
			sprite_template_atlas = sprite_atlas_enabled
		native_render_kernel.cache_sprite_items(items, cached_sprite_scale, current_projection_origin, Callable(sprite_atlas,"texture_for") if sprite_atlas_enabled else Callable(), sprite_template_cache)
	else:
		for item in items: _cache_resource_sprite(item)


func _cache_resource_sprite(item: Dictionary) -> void:
	item.erase("sprite_command")
	if cached_sprite_scale > 0.0 and not item.has("projection_anchor"):
		item["projection_anchor"] = (Vector2(item["screen_position"]) - current_projection_origin) / cached_sprite_scale
		item["projection_sort_y"] = (float(item["screen_y"]) - current_projection_origin.y) / cached_sprite_scale
	# Control records may share a body frame descriptor. They must still reach
	# their outline/health renderer, including on retained and animated updates.
	if String(item["kind"]) not in ["building", "building_part", "resource", "resource_shadow", "unit", "unit_part", "projectile", "effect", "marker", "environment", "rally_flag"]:
		return
	var info: Dictionary = item["frame_info"]
	var texture: Texture2D = info.get("texture")
	if cached_sprite_scale <= 0.0 or texture == null or info.has("gate_polygon") or info.has("rotation") or bool(info.get("mirrored", false)): return
	var anchor := Vector2(item["screen_position"]).round() + Vector2(info.get("screen_offset", Vector2.ZERO)) * cached_sprite_scale
	item["sprite_source_size"] = texture.get_size()
	item["sprite_screen_offset"] = Vector2(info.get("screen_offset", Vector2.ZERO))
	var rendered_texture := sprite_atlas.texture_for(texture) if sprite_atlas_enabled else texture
	var texture_rid := rendered_texture.get_rid()
	var region := Rect2(Vector2.ZERO, texture.get_size())
	if rendered_texture is AtlasTexture:
		texture_rid = rendered_texture.atlas.get_rid()
		region = rendered_texture.region
	item["sprite_command"] = [rendered_texture, Rect2(anchor - Vector2(item["hotspot"]) * cached_sprite_scale, texture.get_size() * cached_sprite_scale), Color(1, 1, 1, float(item["opacity"])), texture_rid, region]


static func _append_resource_shadow(drawables: Array, resource: Dictionary, frame_info: Dictionary, position: Vector2, screen: Vector2) -> void:
	var shadow: Dictionary = frame_info.get("shadow", {})
	if shadow.is_empty() or not ResourcePresentationRegistry.tree_canopy_visible(resource):
		return
	# A separate ground layer cannot cover nearby units or enlarge picking bounds.
	drawables.append(RenderItem.create("resource_shadow", RenderItem.Layer.SHADOW, position, screen, int(resource["id"]), resource, shadow, float(resource.get("elevation", 0.0))))


static func resource_layer(resource: Dictionary) -> int:
	# Marine resources belong to the water surface, below a hull approaching
	# from either side of their anchor (including the jumping fish frames).
	if String(resource.get("kind", "")) in ResourcePresentationRegistry.ANIMATED_MARINE_KINDS:
		return RenderItem.Layer.DECAL
	# Carcasses and harvested trunks lie on the ground, below workers on any side.
	if "carcass" in resource.get("behavior_tags", []) or String(resource.get("tree_phase", "")) in ["felled", "stump"]:
		return RenderItem.Layer.DECAL
	return RenderItem.Layer.UNIT_BUILDING


func _snapshot_resource_drawables(resources: Array, world_to_screen: Callable, frame_info_provider: Callable, preview_ids: Array[int], sprite_scale: float = 0.0, publication_delta: Dictionary = {}, viewport: Rect2 = Rect2()) -> Array:
	var projection := hash([world_to_screen.call(Vector2.ZERO), world_to_screen.call(Vector2.ONE)])
	var scale_changed := cached_sprite_scale != sprite_scale
	cached_sprite_scale = sprite_scale
	if cached_resource_projection != projection or scale_changed:
		if not _can_project_visible(viewport):
			_reproject_statics(cached_resource_raw_drawables, world_to_screen, cached_resource_origin, cached_resource_scale)
			_reproject_statics(cached_resource_group_selections, world_to_screen, cached_resource_origin, cached_resource_scale)
		cached_resource_origin = world_to_screen.call(Vector2.ZERO)
		cached_resource_scale = sprite_scale
		cached_resource_projection = projection
	if resources.is_read_only() and is_same(resources, cached_resource_input) and preview_ids == cached_resource_highlights:
		_refresh_resource_animations(frame_info_provider)
		if performance_probe != null: performance_probe.increment("presentation.resources.publications_reused")
		return cached_resource_drawables
	var highlights_changed := preview_ids != cached_resource_highlights
	var delta: Dictionary = {}
	# The legal-memory producer publishes an immutable delta with exact source
	# identities. No scan is needed when this renderer saw its predecessor.
	if not highlights_changed and publication_delta.is_read_only() and is_same(publication_delta.get("previous"), cached_resource_input) and is_same(publication_delta.get("current"), resources):
		delta = publication_delta
	elif not highlights_changed and native_render_kernel != null and native_render_kernel.has_method("diff_resource_records"):
		delta = native_render_kernel.diff_resource_records(cached_resource_input, resources)
	var incremental := bool(delta.get("valid", false))
	if performance_probe != null:
		performance_probe.increment("presentation.resources.incremental" if incremental else "presentation.resources.full_scan")
		performance_probe.increment("presentation.resources.records_scanned", delta["changed"].size() if incremental else resources.size())
	var immutable_view := resources.is_read_only()
	cached_resource_input = []
	cached_resource_highlights = preview_ids.duplicate()
	var next_records: Dictionary = cached_resource_records.duplicate() if incremental else {}
	var replaced: Dictionary = {}
	if incremental:
		for removed_id in delta["removed"]:
			next_records.erase(removed_id)
			replaced[removed_id] = true
	var retained: Dictionary = {}
	var added: Array = []
	var highlighted: Variant = _id_lookup(preview_ids)
	var has_fish := false
	var fish_changed := highlights_changed
	var resolved := 0
	for resource_value in (delta["changed"] if incremental else resources):
		var resource: Dictionary = resource_value
		immutable_view = immutable_view and resource.is_read_only() and (not resource.has("behavior_tags") or resource["behavior_tags"].is_read_only())
		if int(resource.get("amount", 0)) <= 0 and not bool(resource.get("visible_when_depleted", false)):
			if incremental:
				next_records.erase(int(resource["id"]))
				replaced[int(resource["id"])] = true
			continue
		var id := int(resource.get("id", -1))
		var selected: bool = highlighted.has(id) and PickingService.resource_is_selectable(resource)
		var previous: Dictionary = cached_resource_records.get(id, {})
		var identical: bool = resource.is_read_only() and is_same(previous.get("source"), resource) and (not resource.has("behavior_tags") or resource["behavior_tags"].is_read_only())
		var signature := int(previous.get("signature", 0))
		if not identical or bool(previous.get("selected", false)) != selected:
			signature = hash([resource.get("kind", ""), resource.get("pos", Vector2.ZERO), resource.get("elevation", 0.0), resource.get("depletion_stage", 0), resource.get("tree_phase", ""), resource.get("environment_asset", ""), resource.get("environment_variant", 0), resource.get("tree_condition", ""), resource.get("source_graphic_asset_name", ""), resource.get("source_depleted_asset_name", ""), resource.get("source_graphic_id", -1), resource.get("source_unit_id", -1), ResourcePresentationRegistry.is_carcass(resource), resource.get("source_frame", 0), int(resource.get("amount", 0)) > 0, selected])
		var animated: bool = bool(previous.get("animated", false)) if identical else ResourcePresentationRegistry.is_carcass(resource) or String(resource.get("kind", "")) in ResourcePresentationRegistry.ANIMATED_MARINE_KINDS or String(resource.get("tree_phase", "")) == "falling"
		var fish: bool = bool(previous.get("fish", false)) if identical else FishShoalSelection.is_fish(resource)
		has_fish = has_fish or fish
		if not previous.is_empty() and int(previous["signature"]) == signature:
			if identical:
				next_records[id] = previous
				retained[id] = true
				continue
			fish_changed = fish_changed or fish
			for item in previous["drawables"]:
				if not identical: item["data"] = resource
			previous["source"] = resource
			next_records[id] = previous
			retained[id] = true
			continue
		fish_changed = fish_changed or fish or bool(previous.get("fish", false))
		replaced[id] = true
		var position: Vector2 = resource.get("pos", Vector2.ZERO)
		var screen: Vector2 = world_to_screen.call(position)
		var info := _frame_info(frame_info_provider, "resource", resource)
		var elevation := float(resource.get("elevation", 0.0))
		var items: Array = [RenderItem.create("resource", resource_layer(resource), position, screen, id, resource, info, elevation)]
		_append_resource_shadow(items, resource, info, position, screen)
		for item in items:
			_cache_resource_sprite(item)
			item["clip_static_sprite"] = not animated
		if selected:
			items.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, position, screen, id, resource, info, elevation, Color("d6bc63"), 1.0, 1))
		next_records[id] = {"signature": signature, "drawables": items, "source": resource, "selected": selected, "animated": animated, "fish": fish}
		added.append_array(items)
		resolved += 1

	cached_resource_input = resources if immutable_view else []
	if not incremental or not added.is_empty() or not replaced.is_empty():
		cached_resource_animated = []
		for record in next_records.values():
			if bool(record["animated"]): cached_resource_animated.append(record)
	_refresh_resource_animations(frame_info_provider)
	if incremental:
		for id in delta["removed"]:
			if bool(cached_resource_records.get(id, {}).get("fish", false)): fish_changed = true
	else:
		for id in cached_resource_records:
			if not next_records.has(id) and bool(cached_resource_records[id]["fish"]): fish_changed = true
	if added.is_empty() and next_records.size() == cached_resource_records.size() and not fish_changed:
		cached_resource_records = next_records
		if performance_probe != null: performance_probe.increment("presentation.resources.frames_reused", next_records.size())
		return cached_resource_drawables
	var kept: Array = []
	for item in cached_resource_raw_drawables:
		if (not replaced.has(int(item["stable_id"]))) if incremental else retained.has(int(item["stable_id"])): kept.append(item)
	added.sort_custom(RenderItem.less)
	cached_resource_raw_drawables = _merge_static_items(kept, added)
	# Retain only the current viewport's legal records. A single entering tree or
	# depletion change never reloads all remaining resource frame descriptors.
	cached_resource_records = next_records
	cached_resource_drawables = cached_resource_raw_drawables
	cached_resource_group_selections = []
	if not has_fish:
		for record in next_records.values():
			if bool(record["fish"]): has_fish = true; break
	if has_fish:
		# Group/sort only the fish, then merge with the already sorted forest.
		# A few animated schools must not trigger a full resource re-sort.
		var fish_items: Array = []
		var other_items: Array = []
		for item in cached_resource_raw_drawables:
			if bool(cached_resource_records[int(item["stable_id"])]["fish"]):
				item.erase("selection_group")
				fish_items.append(item)
			else: other_items.append(item)
		var grouped := FishShoalSelection.group_drawables(fish_items, preview_ids, world_to_screen)
		for item in grouped:
			if String(item["kind"]) == "selection": cached_resource_group_selections.append(item)
		grouped.sort_custom(RenderItem.less)
		cached_resource_drawables = _merge_static_items(other_items, grouped)
	if performance_probe != null:
		performance_probe.increment("presentation.resources.frames_resolved", resolved)
		performance_probe.increment("presentation.resources.frames_reused", retained.size())
	return cached_resource_drawables


func _can_project_visible(viewport: Rect2) -> bool:
	return affine_static_projection and cached_sprite_scale > 0.0 and viewport.has_area() and native_render_kernel != null and native_render_kernel.has_method("project_visible_static_items")


func _merge_static_items(first: Array, second: Array) -> Array:
	if affine_static_projection and cached_sprite_scale > 0.0 and native_render_kernel != null and native_render_kernel.has_method("merge_projected_static_items"):
		return native_render_kernel.merge_projected_static_items(first, second, current_projection_origin, cached_sprite_scale)
	return merge_sorted_drawables(first, second)


func can_refresh_camera() -> bool:
	return camera_cache_ready and affine_static_projection and cached_sprite_scale > 0.0 and native_render_kernel != null and native_render_kernel.has_method("project_visible_static_items")


func refresh_camera_drawables(world_to_screen: Callable, interpolation_alpha: float, sprite_scale: float, viewport: Rect2) -> Array:
	current_projection_origin = world_to_screen.call(Vector2.ZERO)
	cached_sprite_scale = sprite_scale
	var projection := hash([current_projection_origin, world_to_screen.call(Vector2.ONE)])
	cached_resource_projection = projection
	cached_environment_projection = projection
	cached_resource_origin = current_projection_origin
	cached_environment_origin = current_projection_origin
	cached_resource_scale = sprite_scale
	cached_environment_scale = sprite_scale
	if camera_actor_statics.is_empty():
		camera_actor_statics = native_render_kernel.partition_render_items(camera_actor_items)["static"]
	native_render_kernel.project_visible_static_items(camera_actor_statics, current_projection_origin, sprite_scale, Rect2())
	refresh_world_drawables(camera_actor_items, world_to_screen, interpolation_alpha, false, true)
	for record in cached_building_records.values():
		if not record["items"].is_empty():
			record["screen"] = record["items"][0]["screen_position"]
			record["scale"] = sprite_scale
	var actors: Array = []
	for item in camera_actor_items:
		if String(item["kind"]) in ["building", "building_part"] and item.has("sprite_command") and not viewport.intersects(item["sprite_command"][1], true): continue
		actors.append(item)
	var resources := _visible_static_drawables(cached_resource_drawables, viewport, cached_resource_clip)
	var environment := _visible_static_drawables(cached_environment_drawables, viewport, cached_environment_clip)
	return merge_sorted_drawables(merge_sorted_drawables(actors, environment), resources)


func _visible_static_drawables(items: Array, viewport: Rect2, cache: Dictionary) -> Array:
	var key := [viewport, cached_resource_projection]
	if cache.get("key") == key and is_same(cache.get("source"), items): return cache["result"]
	var result: Array = []
	if _can_project_visible(viewport):
		if not is_same(cache.get("prepared_source"), items):
			cache["prepared"] = native_render_kernel.prepare_static_projection(items, current_projection_origin, cached_sprite_scale)
			cache["prepared_source"] = items
		result = native_render_kernel.project_prepared_static_items(cache["prepared"], current_projection_origin, cached_sprite_scale, viewport)
		cache["source"] = items
		cache["result"] = result
		cache["key"] = key
		return result
	for item in items:
		# Test the whole source sprite, including the crown/hotspot. Animation
		# and group selections stay conservative, even outside the viewport.
		if bool(item.get("clip_static_sprite", false)) and item.has("sprite_command"):
			if not viewport.intersects(item["sprite_command"][1], true): continue
		result.append(item)
	cache["source"] = items
	cache["result"] = result
	cache["key"] = key
	return result


func _refresh_resource_animations(provider: Callable) -> void:
	for record in cached_resource_animated:
		var info := _frame_info(provider, "resource", record["source"])
		for item in record["drawables"]:
			if String(item["kind"]) == "resource_shadow": continue
			item["frame_info"] = info
			item["frame"] = int(info.get("frame_index", 0))
			item["hotspot"] = info.get("hotspot", Vector2.ZERO)
			_cache_resource_sprite(item)


func _snapshot_environment_drawables(environment_items: Array, world_to_screen: Callable, frame_info_provider: Callable, revision: int = -1, viewport: Rect2 = Rect2()) -> Dictionary:
	# Pan/zoom preserves depth order, but cached and newly entering items must
	# share the current projection before merging with units and buildings.
	var projection := hash([world_to_screen.call(Vector2.ZERO), world_to_screen.call(Vector2.ONE)])
	if cached_environment_projection != projection:
		if not _can_project_visible(viewport):
			_reproject_statics(cached_environment_drawables, world_to_screen, cached_environment_origin, cached_environment_scale)
		cached_environment_origin = world_to_screen.call(Vector2.ZERO)
		cached_environment_scale = cached_sprite_scale
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
		_cache_resource_sprite(drawable)
		drawable["clip_static_sprite"] = true
		next_records[item_id] = {"signature": entry["signature"], "drawable": drawable}
		added.append(drawable)
	var kept: Array = []
	for drawable_value in cached_environment_drawables:
		var drawable: Dictionary = drawable_value
		if retained.has(int(drawable["stable_id"])):
			kept.append(drawable)
	added.sort_custom(RenderItem.less)
	cached_environment_drawables = _merge_static_items(kept, added)
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
	if native_render_kernel != null and native_render_kernel.has_method("merge_render_items"):
		return native_render_kernel.merge_render_items(first, second)
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


func refresh_world_drawables(drawables: Array, world_to_screen: Callable, interpolation_alpha: float = 1.0, projection_changed: bool = true, force_resort: bool = false) -> Array:
	# Frame descriptors, composite parts and render-item dictionaries are stable
	# for one published presentation revision. Between fixed simulation ticks only
	# interpolation changes, so update anchors in place instead of rebuilding the
	# complete render queue and resolving every sprite again.
	var alpha := clampf(interpolation_alpha, 0.0, 1.0)
	var moved := force_resort
	if not is_same(cached_refresh_input, drawables) or projection_changed:
		cached_refresh_input = drawables
		if native_render_kernel != null and native_render_kernel.has_method("partition_render_items"):
			var partition: Dictionary = native_render_kernel.partition_render_items(drawables)
			cached_refresh_static = partition["static"]
			cached_refresh_moving = partition["moving"]
			cached_refresh_ambient = partition.get("ambient", [])
		else:
			cached_refresh_static = []
			cached_refresh_moving = []
			for item in drawables:
				if _is_dynamic_drawable(String(item.get("kind", "")), item.get("data", {})): cached_refresh_moving.append(item)
				else: cached_refresh_static.append(item)
	var refresh_items: Array = drawables if projection_changed else cached_refresh_moving
	if not projection_changed and native_render_kernel != null and native_render_kernel.has_method("refresh_interpolated_items"):
		moved = bool(native_render_kernel.refresh_interpolated_items(cached_refresh_moving, world_to_screen, alpha, cached_building_depth_index, cached_sprite_scale)) or moved
		refresh_items = cached_refresh_ambient
	for drawable_value in refresh_items:
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
				if String(drawable["kind"]) in ["resource", "resource_shadow", "building", "building_part", "environment"]: _cache_resource_sprite(drawable)
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
		if drawable.has("sprite_command"): _cache_resource_sprite(drawable)
	if projection_changed:
		# A compatibility refresh can update a clipped subset of the caches.
		# Re-query the remaining statics before the next published queue.
		cached_resource_projection = null
		cached_environment_projection = null
		cached_resource_origin = null
		cached_environment_origin = null
		cached_resource_clip.clear()
		cached_environment_clip.clear()
	if moved:
		if native_render_kernel != null and native_render_kernel.has_method("sort_render_items"):
			cached_refresh_moving = native_render_kernel.sort_render_items(cached_refresh_moving)
		else: cached_refresh_moving.sort_custom(RenderItem.less)
		var merged := merge_sorted_drawables(cached_refresh_static, cached_refresh_moving)
		drawables.assign(merged)
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



func _unit_building_depth_offset(position: Vector2, screen_y: float, index: Dictionary, project: Callable) -> float:
	if native_render_kernel != null and native_render_kernel.has_method("unit_depth_offset"):
		return native_render_kernel.unit_depth_offset(position, screen_y, index, project)
	return _reference_unit_building_depth_offset(position, screen_y, index, project)


static func _reference_unit_building_depth_offset(position: Vector2, screen_y: float, index: Dictionary, project: Callable) -> float:
	var adjusted := screen_y
	var front_limit := -INF
	var back_limit := INF
	for building in index.get(Vector2i((position / 4.0).floor()), []):
		if building.has("gate_occluder"):
			var segment: Dictionary = building["gate_occluder"]
			var start: Vector2 = segment["start"]
			var end: Vector2 = segment["end"]
			var direction := end-start
			var length_squared := direction.length_squared()
			if length_squared < 0.0001:
				continue
			var along := (position-start).dot(direction)/length_squared
			var normal := direction.orthogonal().normalized()
			if normal.dot(Vector2.ONE) < 0:
				normal = -normal
			var side := (position-start).dot(normal)
			if along < -0.75 or along > 1.75 or absf(side) > 1.25:
				continue
			var depth: float = Vector2(project.call(segment["depth"])).y
			var margin := maxf(0.05,absf(depth)*0.00002)
			if side >= 0:
				front_limit = maxf(front_limit,depth+margin)
			else:
				back_limit = minf(back_limit,depth-margin)
			continue
		if bool(building.get("harvestable", false)) or float(building.get("hp", 0.0)) <= 0.0:
			continue
		var center := Vector2(building["pos"])
		var half := Vector2(building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5)))
		var offset := position - center
		if absf(offset.x) > half.x + 1.5 or absf(offset.y) > half.y + 1.5:
			continue
		if offset.x >= half.x or offset.y >= half.y:
			adjusted = maxf(adjusted, Vector2(project.call(center)).y + 0.01)
	if front_limit <= back_limit:
		adjusted = clampf(adjusted,front_limit,back_limit)
	return adjusted - screen_y


static func _building_depth_index(buildings: Array, provider: Callable = Callable()) -> Dictionary:
	var index: Dictionary = {}
	for building in buildings:
		if bool(building.get("harvestable", false)) or float(building.get("hp", 0.0)) <= 0.0:
			continue
		if String(building.get("kind", "")) == "gate":
			if provider.is_valid():
				var provided: Variant = provider.call("building",building)
				if not provided is Dictionary:
					continue
				var info: Dictionary = provided
				for local in info.get("gate_occluders",[]):
					var origin := Vector2(building["pos"])
					var segment := {"start":origin+Vector2(local["start"]),"end":origin+Vector2(local["end"]),"depth":origin+Vector2(local["depth"])}
					var first := Vector2i(((Vector2(segment["start"]).min(segment["end"])-Vector2.ONE*2.0)/4.0).floor())
					var last := Vector2i(((Vector2(segment["start"]).max(segment["end"])+Vector2.ONE*2.0)/4.0).floor())
					for y in range(first.y,last.y+1):
						for x in range(first.x,last.x+1):
							var key := Vector2i(x,y)
							if not index.has(key): index[key] = []
							index[key].append({"gate_occluder":segment})
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


func create_effect_drawables(effects: Array, world_to_screen: Callable, frame_info_provider: Callable) -> Array:
	var drawables: Array = []
	for effect in effects:
		if not bool(effect.get("active", true)):
			continue
		var effect_position: Vector2 = effect.get("pos", Vector2.ZERO)
		var effect_info := _frame_info(frame_info_provider, "effect", effect)
		drawables.append(RenderItem.create("effect", RenderItem.Layer.PROJECTILE_EFFECT, effect_position, world_to_screen.call(effect_position), int(effect.get("id", -1)), effect, effect_info, float(effect.get("elevation", 0.0)), Color.WHITE, 1.0, int(effect_info.get("graphic_layer", 30)) * 1000))
		var part_index := 0
		for part in effect_info.get("composite_parts", []):
			part_index += 1
			drawables.append(RenderItem.create("effect", RenderItem.Layer.PROJECTILE_EFFECT, effect_position, world_to_screen.call(effect_position), int(effect.get("id", -1)), effect, part, float(effect.get("elevation", 0.0)), Color.WHITE, 1.0, int(part.get("graphic_layer", 30)) * 1000 + part_index))
	drawables.sort_custom(RenderItem.less)
	return drawables
