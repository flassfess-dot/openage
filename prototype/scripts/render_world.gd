class_name RoRRenderWorld

const RenderItem := preload("res://scripts/render_item.gd")

var cached_resource_signature: int = 0
var cached_resource_drawables: Array = []
var cached_environment_signature: int = 0
var cached_environment_drawables: Array = []
var cached_environment_signature_valid := false
var performance_probe: Variant = null


func clear_caches() -> void:
	cached_resource_signature = 0
	cached_resource_drawables.clear()
	cached_environment_signature = 0
	cached_environment_drawables.clear()
	cached_environment_signature_valid = false


func create_world_drawables(world_source, world_to_screen: Callable, interpolation_alpha: float = 1.0, frame_info_provider: Callable = Callable(), preview_ids: Array[int] = [], observer_team: int = 0, selected_ids: Array[int] = []) -> Array:
	var stage_started := Time.get_ticks_usec() if performance_probe != null else 0
	var drawables: Array = []
	var alpha := clampf(interpolation_alpha, 0.0, 1.0)
	var from_snapshot := world_source is Dictionary
	var source_buildings: Array = world_source.get("buildings", []) if from_snapshot else world_source.get_buildings()
	var source_resources: Array = world_source.get("resources", []) if from_snapshot else world_source.get_resources()
	var source_objectives: Array = world_source.get("objectives", []) if from_snapshot else world_source.victory_objectives
	var source_projectiles: Array = world_source.get("projectiles", []) if from_snapshot else world_source.get_projectiles()
	var source_effects: Array = world_source.get("effects", []) if from_snapshot else []
	var source_markers: Array = world_source.get("markers", []) if from_snapshot else []
	var source_environment: Array = world_source.get("environment", []) if from_snapshot else []
	var source_units: Array = world_source.get("units", []) if from_snapshot else world_source.get_units()
	var resource_drawables: Array = _snapshot_resource_drawables(source_resources, world_to_screen, frame_info_provider, preview_ids) if from_snapshot else []
	_observe_stage("resources", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	var environment_projection := _snapshot_environment_drawables(source_environment, world_to_screen, frame_info_provider) if from_snapshot else {"static": [], "animated": source_environment}
	var environment_drawables: Array = environment_projection["static"]
	source_environment = environment_projection["animated"]
	_observe_stage("environment_cache", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	for building in source_buildings:
		if building["hp"] <= 0.0 and String(building.get("death_phase", "removed")) != "dying":
			continue
		if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, building, true):
			continue
		var building_position: Vector2 = building["pos"]
		var building_info := _frame_info(frame_info_provider, "building", building)
		var building_id := int(building["id"])
		var building_elevation := float(building.get("elevation", 0.0))
		var base_sub_order := int(building_info.get("graphic_layer", 20)) * 1000
		drawables.append(RenderItem.create("building", RenderItem.Layer.UNIT_BUILDING, building_position, world_to_screen.call(building_position).y, building_id, building, building_info, building_elevation, Color.WHITE, 1.0, base_sub_order))
		var building_part_index := 0
		for part in building_info.get("composite_parts", []):
			building_part_index += 1
			var part_sub_order := int(part.get("graphic_layer", 20)) * 1000 + building_part_index
			drawables.append(RenderItem.create("building_part", RenderItem.Layer.UNIT_BUILDING, building_position, world_to_screen.call(building_position).y, building_id, building, part, building_elevation, Color.WHITE, 1.0, part_sub_order))
		if selected_ids.has(building_id) or preview_ids.has(building_id):
			drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, building_position, world_to_screen.call(building_position).y, building_id, building, building_info, building_elevation, RenderItem.color_for_team(int(building.get("team", 0))), 1.0, 1))
	_observe_stage("buildings", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	if not from_snapshot:
		for resource in source_resources:
			if resource["amount"] > 0 or bool(resource.get("visible_when_depleted", false)):
				if observer_team > 0 and not world_source.is_entity_visible_to(observer_team, resource, true):
					continue
				var resource_info := _frame_info(frame_info_provider, "resource", resource)
				drawables.append(RenderItem.create("resource", RenderItem.Layer.BASE_RESOURCE, resource["pos"], world_to_screen.call(resource["pos"]).y, int(resource["id"]), resource, resource_info, float(resource.get("elevation", 0.0))))
				if preview_ids.has(int(resource["id"])):
					drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, resource["pos"], world_to_screen.call(resource["pos"]).y, int(resource["id"]), resource, resource_info, float(resource.get("elevation", 0.0)), Color("d6bc63"), 1.0, 1))
	for objective in source_objectives:
		if not bool(objective.get("active", true)) or bool(objective.get("logical_only", false)):
			continue
		if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, objective, true):
			continue
		var objective_info := _frame_info(frame_info_provider, "objective", objective)
		var objective_position: Vector2 = objective.get("pos", Vector2.ZERO)
		drawables.append(RenderItem.create("objective", RenderItem.Layer.BASE_RESOURCE, objective_position, world_to_screen.call(objective_position).y, int(objective.get("id", -1)), objective, objective_info, float(objective.get("source_elevation", 0.0))))
	for projectile in source_projectiles:
		if not bool(projectile.get("active", true)):
			continue
		if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, projectile):
			continue
		var previous_position: Vector2 = projectile.get("previous_pos", projectile["pos"])
		var render_position: Vector2 = previous_position.lerp(projectile["pos"], alpha)
		var projectile_info := _frame_info(frame_info_provider, "projectile", projectile)
		drawables.append(RenderItem.create("projectile", RenderItem.Layer.PROJECTILE_EFFECT, render_position, world_to_screen.call(render_position).y, int(projectile["id"]), projectile, projectile_info, float(projectile.get("elevation", 0.0)), RenderItem.color_for_team(int(projectile.get("team", 0)))))
	for effect in source_effects:
		if not bool(effect.get("active", true)):
			continue
		var effect_position: Vector2 = effect.get("pos", Vector2.ZERO)
		var effect_info := _frame_info(frame_info_provider, "effect", effect)
		drawables.append(RenderItem.create("effect", RenderItem.Layer.PROJECTILE_EFFECT, effect_position, world_to_screen.call(effect_position).y, int(effect.get("id", -1)), effect, effect_info, float(effect.get("elevation", 0.0)), Color.WHITE, 1.0, int(effect_info.get("graphic_layer", 30)) * 1000))
	for marker in source_markers:
		var marker_position: Vector2 = marker.get("position", Vector2.ZERO)
		var marker_info := _frame_info(frame_info_provider, "marker", marker)
		drawables.append(RenderItem.create("marker", RenderItem.Layer.UNIT_BUILDING, marker_position, world_to_screen.call(marker_position).y, int(marker.get("id", -1)), marker, marker_info, float(marker.get("source_elevation", 0.0)), Color.WHITE, 1.0, int(marker_info.get("graphic_layer", 20)) * 1000))
	for environment_item in source_environment:
		var environment_position: Vector2 = environment_item.get("position", Vector2.ZERO)
		var environment_info := _frame_info(frame_info_provider, "environment", environment_item)
		var layer := RenderItem.Layer.BASE_RESOURCE
		match String(environment_item.get("presentation_layer", "scenery")):
			"decal": layer = RenderItem.Layer.DECAL
			"ambient_actor": layer = RenderItem.Layer.UNIT_BUILDING
		drawables.append(RenderItem.create("environment", layer, environment_position, world_to_screen.call(environment_position).y, int(environment_item.get("id", -1)), environment_item, environment_info, float(environment_item.get("source_elevation", 0.0)), Color.WHITE, 1.0, int(environment_info.get("graphic_layer", 0)) * 1000))
	_observe_stage("static_entities", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	for unit in source_units:
		var death_phase := String(unit.get("death_phase", "alive"))
		if unit["hp"] > 0.0 or death_phase in ["dying", "corpse"]:
			if not from_snapshot and observer_team > 0 and not world_source.is_entity_visible_to(observer_team, unit):
				continue
			var previous_position: Vector2 = unit.get("previous_pos", unit["pos"])
			var render_position: Vector2 = previous_position.lerp(unit["pos"], alpha)
			var screen_y: float = world_to_screen.call(render_position).y
			var frame_info := _frame_info(frame_info_provider, "unit", unit)
			var stable_id := int(unit["id"])
			var elevation := float(unit.get("elevation", 0.0))
			var player_color := RenderItem.color_for_team(int(unit.get("team", 0)))
			if death_phase != "corpse":
				drawables.append(RenderItem.create("shadow", RenderItem.Layer.SHADOW, render_position, screen_y, stable_id, unit, {}, elevation, Color(0.0, 0.0, 0.0, 0.32)))
			var unit_base_sub_order := int(frame_info.get("graphic_layer", 20)) * 1000
			drawables.append(RenderItem.create("unit", RenderItem.Layer.UNIT_BUILDING, render_position, screen_y, stable_id, unit, frame_info, elevation, player_color, 1.0, unit_base_sub_order))
			var unit_part_index := 0
			for part_value in frame_info.get("composite_parts", []):
				var part: Dictionary = part_value
				unit_part_index += 1
				var part_sub_order := int(part.get("graphic_layer", 20)) * 1000 + unit_part_index
				drawables.append(RenderItem.create("unit_part", RenderItem.Layer.UNIT_BUILDING, render_position, screen_y, stable_id, unit, part, elevation, player_color, 1.0, part_sub_order))
			if death_phase == "alive" and (selected_ids.has(stable_id) or bool(unit.get("selected", false)) or preview_ids.has(stable_id)):
				drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, render_position, screen_y, stable_id, unit, frame_info, elevation, player_color, 1.0, 1))
			if death_phase == "alive" and (selected_ids.has(stable_id) or bool(unit.get("selected", false)) or preview_ids.has(stable_id)):
				drawables.append(RenderItem.create("health_bar", RenderItem.Layer.HEALTH_BAR, render_position, screen_y, stable_id, unit, frame_info, elevation, player_color, 1.0, 2))
	_observe_stage("units", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	drawables.sort_custom(RenderItem.less)
	_observe_stage("sort", stage_started)
	stage_started = Time.get_ticks_usec() if performance_probe != null else 0
	var result: Array = drawables
	if not environment_drawables.is_empty():
		result = _merge_sorted_drawables(result, environment_drawables)
	if not resource_drawables.is_empty():
		result = _merge_sorted_drawables(result, resource_drawables)
	_observe_stage("merge", stage_started)
	return result


func _snapshot_resource_drawables(resources: Array, world_to_screen: Callable, frame_info_provider: Callable, preview_ids: Array[int]) -> Array:
	if resources.is_empty():
		return []
	var signature := 17
	for resource_value in resources:
		var resource: Dictionary = resource_value
		signature = signature * 31 + int(resource.get("id", -1))
		signature = signature * 31 + int(resource.get("depletion_stage", 0))
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
		return cached_resource_drawables
	cached_resource_signature = signature
	cached_resource_drawables = []
	for resource_value in resources:
		var resource: Dictionary = resource_value
		if int(resource.get("amount", 0)) <= 0 and not bool(resource.get("visible_when_depleted", false)):
			continue
		var position: Vector2 = resource.get("pos", Vector2.ZERO)
		var resource_id := int(resource.get("id", -1))
		var resource_info := _frame_info(frame_info_provider, "resource", resource)
		var screen_y := float(world_to_screen.call(position).y)
		var elevation := float(resource.get("elevation", 0.0))
		cached_resource_drawables.append(RenderItem.create("resource", RenderItem.Layer.BASE_RESOURCE, position, screen_y, resource_id, resource, resource_info, elevation))
		if preview_ids.has(resource_id):
			cached_resource_drawables.append(RenderItem.create("selection", RenderItem.Layer.SELECTION, position, screen_y, resource_id, resource, resource_info, elevation, Color("d6bc63"), 1.0, 1))
	cached_resource_drawables.sort_custom(RenderItem.less)
	return cached_resource_drawables


func _snapshot_environment_drawables(environment_items: Array, world_to_screen: Callable, frame_info_provider: Callable) -> Dictionary:
	var animated: Array = []
	var signature := 17
	for item_value in environment_items:
		var item: Dictionary = item_value
		if bool(item.get("animated", false)):
			animated.append(item)
			continue
		var position: Vector2 = item.get("position", Vector2.ZERO)
		signature = signature * 31 + int(item.get("id", -1))
		signature = signature * 31 + int(item.get("graphic_id", -1))
		signature = signature * 31 + hash(position)
		signature = signature * 31 + int(item.get("source_frame", 0))
		signature = signature * 31 + hash(String(item.get("presentation_layer", "scenery")))
		signature = signature * 31 + hash(float(item.get("source_elevation", 0.0)))
	if cached_environment_signature_valid and signature == cached_environment_signature:
		return {"static": cached_environment_drawables, "animated": animated}
	cached_environment_signature = signature
	cached_environment_signature_valid = true
	cached_environment_drawables = []
	for item_value in environment_items:
		var item: Dictionary = item_value
		if bool(item.get("animated", false)):
			continue
		var position: Vector2 = item.get("position", Vector2.ZERO)
		var frame_info := _frame_info(frame_info_provider, "environment", item)
		var layer := RenderItem.Layer.BASE_RESOURCE
		match String(item.get("presentation_layer", "scenery")):
			"decal": layer = RenderItem.Layer.DECAL
			"ambient_actor": layer = RenderItem.Layer.UNIT_BUILDING
		cached_environment_drawables.append(RenderItem.create(
			"environment",
			layer,
			position,
			world_to_screen.call(position).y,
			int(item.get("id", -1)),
			item,
			frame_info,
			float(item.get("source_elevation", 0.0)),
			Color.WHITE,
			1.0,
			int(frame_info.get("graphic_layer", 0)) * 1000
		))
	cached_environment_drawables.sort_custom(RenderItem.less)
	return {"static": cached_environment_drawables, "animated": animated}


func _merge_sorted_drawables(first: Array, second: Array) -> Array:
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


func refresh_world_drawables(drawables: Array, world_to_screen: Callable, interpolation_alpha: float = 1.0) -> Array:
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
		if kind == "projectile":
			position = Vector2(data.get("previous_pos", data.get("pos", Vector2.ZERO))).lerp(Vector2(data.get("pos", Vector2.ZERO)), alpha)
		elif kind in ["unit", "unit_part", "shadow", "selection", "health_bar"] and String(data.get("movement_domain", "land")) != "static":
			position = Vector2(data.get("previous_pos", data.get("pos", Vector2.ZERO))).lerp(Vector2(data.get("pos", Vector2.ZERO)), alpha)
		if position == null:
			continue
		var resolved_position: Vector2 = position
		if not resolved_position.is_equal_approx(Vector2(drawable.get("world_anchor", resolved_position))):
			moved = true
		drawable["world_anchor"] = resolved_position
		drawable["screen_y"] = float(world_to_screen.call(resolved_position).y)
	if moved:
		drawables.sort_custom(RenderItem.less)
	return drawables


func _frame_info(provider: Callable, kind: String, data: Variant) -> Dictionary:
	if provider.is_valid():
		var result: Variant = provider.call(kind, data)
		if result is Dictionary:
			return result
	return {}


func _observe_stage(stage: String, started: int) -> void:
	if performance_probe != null:
		performance_probe.observe_microseconds("presentation.draw.world_prepare.%s" % stage, Time.get_ticks_usec() - started)

