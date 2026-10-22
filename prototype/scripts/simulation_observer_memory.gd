extends RefCounted

# Owns this state; the world is passed per operation to avoid a reference cycle.
const EntityReadContract := preload("res://scripts/entity_read_contract.gd")
const ResourcePublication := preload("res://scripts/immutable_resource_publication.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const AiNavigationKnowledge := preload("res://scripts/ai_navigation_knowledge.gd")
const RESOURCE_MEMORY_CHUNK_SIZE := 8
const MAX_MINIMAP_RESOURCE_CHANGES := 4096

var known_resources_by_player: Dictionary = {}
var known_ai_resources_by_player: Dictionary = {}
var last_known_buildings_by_player: Dictionary = {}
var ai_navigation_knowledge = AiNavigationKnowledge.new()

func reset() -> void:
	known_resources_by_player.clear()
	ai_navigation_knowledge.clear()
	last_known_buildings_by_player.clear()
	known_ai_resources_by_player.clear()


func restore_last_known_buildings(world, encoded: Dictionary) -> void:
	# Save archives stringify dictionary keys; runtime lookups use integer team and entity IDs.
	last_known_buildings_by_player.clear()
	for observer_key in encoded:
		var observer_team = int(observer_key)
		if observer_team <= 0 or not encoded[observer_key] is Dictionary:
			continue
		var restored: Dictionary = {}
		var records: Dictionary = encoded[observer_key]
		for entity_key in records:
			if records[entity_key] is Dictionary:
				restored[int(entity_key)] = records[entity_key].duplicate(true)
		last_known_buildings_by_player[observer_team] = restored


func known_resource_memory_state(world) -> Dictionary:
	var result: Dictionary = {}
	var observers: Array = known_resources_by_player.keys()
	for observer_value in observers:
		var observer_team = int(observer_value)
		world.get_known_resources(observer_team)
		var cached: Dictionary = known_resources_by_player[observer_value]
		result[observer_team] = cached.get("resources", []).duplicate(true)
	return result


func known_resource_revision(world, observer_team: int) -> int:
	world.get_known_resources(observer_team)
	return int(known_resources_by_player.get(observer_team, {}).get("revision", 0))


# One presentation consumer per observer. The queue contains only legal resource
# memory changes that can alter a marker, not every decrement of a tree's wood.
# null requests an initial/bulk rebuild; an empty dictionary means no work.


func consume_known_resource_marker_changes(world, observer_team: int) -> Variant:
	world.get_known_resources(observer_team)
	var cached: Dictionary = known_resources_by_player.get(observer_team, {})
	if cached.is_empty():
		return null
	var rebuild = not bool(cached.get("marker_changes_tracked", false)) or bool(cached.get("marker_changes_overflow", false))
	cached["marker_changes_tracked"] = true
	cached["marker_changes_overflow"] = false
	var pending: Dictionary = cached.get("marker_changes", {})
	var changes: Dictionary = {}
	if not rebuild:
		var ids: Dictionary = cached.get("ids", {})
		for resource_id in pending:
			changes[resource_id] = ids.get(resource_id)
	pending.clear()
	return null if rebuild else changes


func _mark_known_resource_marker_changed(world, cached: Dictionary, resource_id: int) -> void:
	if not bool(cached.get("marker_changes_tracked", false)) or bool(cached.get("marker_changes_overflow", false)):
		return
	var pending: Dictionary = cached["marker_changes"]
	pending[resource_id] = true
	if pending.size() > MAX_MINIMAP_RESOURCE_CHANGES:
		pending.clear()
		cached["marker_changes_overflow"] = true


func restore_known_resource_memory(world, encoded: Dictionary) -> void:
	known_resources_by_player.clear()
	known_ai_resources_by_player.clear()
	var fog = world.get_fog_of_war()
	for observer_key in encoded.keys():
		var observer_team = int(observer_key)
		if observer_team <= 0 or not encoded[observer_key] is Array:
			continue
		fog.ensure_player(observer_team)
		var ally_ids: Array = fog.shared_vision_by_player.get(observer_team, {}).keys()
		ally_ids.sort()
		var cached = world._empty_known_resource_cache(hash(ally_ids))
		for record_value in encoded[observer_key]:
			if record_value is Dictionary:
				world._remember_known_resource(cached, record_value, true)
		cached["revision"] = 1
		known_resources_by_player[observer_team] = cached
		fog.consume_newly_explored_cells(observer_team)
		fog.consume_newly_visible_cells(observer_team)


func get_known_resources(world, observer_team: int) -> Array:
	if observer_team <= 0:
		return world.resource_nodes
	var fog = world.get_fog_of_war()
	fog.ensure_player(observer_team)
	var ally_ids: Array = fog.shared_vision_by_player.get(observer_team, {}).keys()
	ally_ids.sort()
	var alliance_signature = hash(ally_ids)
	var cached: Dictionary = known_resources_by_player.get(observer_team, {})
	if not cached.is_empty() and int(cached.get("alliance_signature", 0)) == alliance_signature:
		world._refresh_known_resource_cache(observer_team, cached, fog)
		return cached.get("resources", [])
	var states: PackedByteArray = fog.states_by_player[observer_team]
	var allies: Dictionary = fog.shared_vision_by_player.get(observer_team, {})
	cached = world._empty_known_resource_cache(alliance_signature)
	for resource_value in world.resource_nodes:
		var resource: Dictionary = resource_value
		var owner = int(resource.get("team", 0))
		if owner > 0 and bool(allies.get(owner, false)):
			world._remember_known_resource(cached, resource)
			continue
		var position: Vector2 = resource.get("pos", Vector2.ZERO)
		var cell_x = floori(position.x)
		var cell_y = floori(position.y)
		if cell_x < 0 or cell_y < 0 or cell_x >= fog.map_size.x or cell_y >= fog.map_size.y:
			continue
		if int(states[cell_y * fog.map_size.x + cell_x]) != FogOfWar.UNKNOWN:
			world._remember_known_resource(cached, resource)
	fog.consume_newly_explored_cells(observer_team)
	fog.consume_newly_visible_cells(observer_team)
	cached["revision"] = 1
	known_resources_by_player[observer_team] = cached
	return cached.get("resources", [])


func get_known_ai_resources(world, observer_team: int) -> Array:
	# Strategic planners only read a small, stable projection of resource nodes.
	# Reuse those dictionaries between decisions instead of allocating and
	# populating thousands of copies for every AI player every two seconds.
	var known: Array = world.get_known_resources(observer_team)
	if observer_team <= 0:
		return known
	var known_cache: Dictionary = known_resources_by_player.get(observer_team, {})
	if known_cache.has("ai_projection"):
		return known_cache["ai_projection"]["resources"]
	var projected = {"resources": [], "ids": {}}
	for resource in known:
		var item = world._compact_ai_resource(resource)
		projected["resources"].append(item)
		projected["ids"][int(item["id"])] = item
	known_cache["ai_projection"] = projected
	known_ai_resources_by_player[observer_team] = projected
	return projected["resources"]


# Warm the immutable resource publication alongside incremental AI navigation.
# A restored large forest must not produce a single long frame on first use.


func prepare_known_ai_resource_snapshot(world, observer_team: int, max_records: int = 64) -> bool:
	var known = world.get_known_resources(observer_team)
	var cache: Dictionary = known_resources_by_player.get(observer_team, {})
	if observer_team <= 0 or cache.has("ai_projection"):
		return true
	var revision = int(cache.get("revision", 0))
	var pending: Dictionary = cache.get("ai_projection_preparing", {})
	if pending.is_empty() or int(pending["revision"]) != revision:
		pending = {"revision": revision, "resources": [], "ids": {}, "publication": ResourcePublication.new()}
		cache["ai_projection_preparing"] = pending
	var end = mini(known.size(), pending["resources"].size() + maxi(1, max_records))
	for index in range(pending["resources"].size(), end):
		var item = world._compact_ai_resource(known[index])
		if not pending["publication"].upsert(item):
			cache.erase("ai_projection_preparing")
			return false
		pending["resources"].append(item)
		pending["ids"][int(item["id"])] = item
	if end < known.size():
		return false
	pending.erase("revision")
	cache["ai_projection"] = pending
	known_ai_resources_by_player[observer_team] = pending
	cache.erase("ai_projection_preparing")
	return true


func get_known_ai_resource_snapshot(world, observer_team: int) -> Array:
	var resources = world.get_known_ai_resources(observer_team)
	var cache: Dictionary = known_resources_by_player.get(observer_team, {})
	var projection: Dictionary = cache.get("ai_projection", {})
	if projection.is_empty():
		return resources.duplicate()
	if not projection.has("publication"):
		var publication = ResourcePublication.new()
		for record in resources:
			if not publication.upsert(record):
				return resources.duplicate()
		projection["publication"] = publication
	return projection["publication"].snapshot()


func _update_ai_resource_projection(world, cached: Dictionary, memory: Dictionary) -> void:
	if not cached.has("ai_projection"):
		return
	var projection: Dictionary = cached["ai_projection"]
	var id = int(memory["id"])
	var item = world._compact_ai_resource(memory)
	if projection["ids"].get(id) == item:
		return
	if projection.has("publication") and not projection["publication"].upsert(item):
		projection.erase("publication")
	if projection["ids"].has(id):
		world._replace_known_resource(projection["resources"], item)
		projection["ids"][id] = item
	else:
		projection["ids"][id] = item
		world._insert_known_resource_sorted(projection["resources"], item)


func _compact_ai_resource(world, resource: Dictionary) -> Dictionary:
	return EntityReadContract.resource(resource)


func _empty_known_resource_cache(world, alliance_signature: int) -> Dictionary:
	return {
		"alliance_signature": alliance_signature,
		"resources": [],
		"ids": {},
		"by_cell": {},
		"by_chunk": {},
		"dirty_ids": {},
		"marker_changes": {},
		"marker_changes_tracked": false,
		"marker_changes_overflow": false,
		"revision": 0,
	}


func _refresh_known_resource_cache(world, observer_team: int, cached: Dictionary, fog) -> void:
	var changed = false
	var allies: Dictionary = fog.shared_vision_by_player.get(observer_team, {})
	var candidate_cells: Dictionary = {}
	for cell_index_value in fog.consume_newly_explored_cells(observer_team):
		candidate_cells[int(cell_index_value)] = true
	for cell_index_value in fog.consume_newly_visible_cells(observer_team):
		candidate_cells[int(cell_index_value)] = true
	for cell_index_value in candidate_cells.keys():
		var cell_index = int(cell_index_value)
		var cell = Vector2i(cell_index % world.map_size.x, cell_index / world.map_size.x)
		if fog.state_at_cell(observer_team, cell) != FogOfWar.VISIBLE:
			continue
		var live_ids: Dictionary = {}
		for resource_value in world.resource_nodes_by_cell.get(cell_index, []):
			var resource: Dictionary = resource_value
			var resource_id = int(resource.get("id", -1))
			live_ids[resource_id] = true
			changed = world._remember_known_resource(cached, resource) or changed
		var remembered_in_cell: Dictionary = cached.get("by_cell", {}).get(cell_index, {})
		for resource_id_value in remembered_in_cell.keys():
			var resource_id = int(resource_id_value)
			if not live_ids.has(resource_id):
				changed = world._forget_known_resource(cached, resource_id) or changed
	var dirty_ids: Dictionary = cached.get("dirty_ids", {})
	for resource_id_value in dirty_ids.keys():
		var resource_id = int(resource_id_value)
		var live: Variant = world.resource_nodes_by_id.get(resource_id)
		var remembered: Variant = cached.get("ids", {}).get(resource_id)
		var position = Vector2.ZERO
		if live is Dictionary:
			position = Vector2(live.get("pos", Vector2.ZERO))
		elif remembered is Dictionary:
			position = Vector2(remembered.get("pos", Vector2.ZERO))
		else:
			continue
		var ownership_source: Dictionary = live if live is Dictionary else remembered
		var owner = int(ownership_source.get("team", 0))
		var allied_resource = owner > 0 and bool(allies.get(owner, false))
		if not allied_resource and fog.state_at_world(observer_team, position) != FogOfWar.VISIBLE:
			continue
		if live is Dictionary:
			changed = world._remember_known_resource(cached, live) or changed
		else:
			changed = world._forget_known_resource(cached, resource_id) or changed
	dirty_ids.clear()
	if changed:
		cached["revision"] = int(cached.get("revision", 0)) + 1


func mark_known_resource_dirty(world, resource: Dictionary) -> void:
	world._mark_known_resource_dirty(resource)


func _mark_known_resource_dirty(world, resource: Dictionary) -> void:
	var resource_id = int(resource.get("id", -1))
	if resource_id < 0:
		return
	for observer_value in known_resources_by_player.keys():
		var cached: Dictionary = known_resources_by_player[observer_value]
		var dirty_ids: Dictionary = cached.get("dirty_ids", {})
		dirty_ids[resource_id] = true
		cached["dirty_ids"] = dirty_ids


func _remember_known_resource(world, cached: Dictionary, resource: Dictionary, compact_source: bool = false) -> bool:
	var resource_id = int(resource.get("id", -1))
	if resource_id < 0:
		return false
	if int(resource.get("amount", 0)) <= 0 and not bool(resource.get("visible_when_depleted", false)):
		return world._forget_known_resource(cached, resource_id)
	var memory: Dictionary = EntityReadContract.render(resource) if compact_source else world.render_entity_projection_cache.project(resource)
	var ids: Dictionary = cached.get("ids", {})
	var existing: Variant = ids.get(resource_id)
	if existing is Dictionary:
		if existing == memory:
			return false
		if existing.get("pos") != memory.get("pos") or (int(existing.get("amount", 0)) > 0) != (int(memory.get("amount", 0)) > 0):
			world._mark_known_resource_marker_changed(cached, resource_id)
		if existing.get("pos") == memory.get("pos"):
			world._mark_resource_view_changed(cached, resource_id)
			world._replace_known_resource(cached["resources"], memory)
			ids[resource_id] = memory
			world._update_ai_resource_projection(cached, memory)
			return true
		# Moving a remembered resource must also migrate its spatial indices.
		world._forget_known_resource(cached, resource_id)
	world._mark_resource_view_changed(cached, resource_id)
	var known: Array = cached.get("resources", [])
	world._insert_known_resource_sorted(known, memory)
	ids[resource_id] = memory
	world._update_ai_resource_projection(cached, memory)
	world._mark_known_resource_marker_changed(cached, resource_id)
	var cell_index = world._resource_cell_index(memory)
	var by_cell: Dictionary = cached.get("by_cell", {})
	var cell_ids: Dictionary = by_cell.get(cell_index, {})
	cell_ids[resource_id] = true
	by_cell[cell_index] = cell_ids
	var chunk_key = world._resource_chunk_key(memory)
	var by_chunk: Dictionary = cached.get("by_chunk", {})
	var chunk_ids: Dictionary = by_chunk.get(chunk_key, {})
	chunk_ids[resource_id] = true
	by_chunk[chunk_key] = chunk_ids
	cached["resources"] = known
	cached["ids"] = ids
	cached["by_cell"] = by_cell
	cached["by_chunk"] = by_chunk
	return true


func _forget_known_resource(world, cached: Dictionary, resource_id: int) -> bool:
	var ids: Dictionary = cached.get("ids", {})
	var memory: Variant = ids.get(resource_id)
	if not memory is Dictionary:
		return false
	world._mark_resource_view_changed(cached, resource_id)
	var known: Array = cached.get("resources", [])
	known.erase(memory)
	if cached.has("ai_projection"):
		var projected: Dictionary = cached["ai_projection"]
		projected["resources"].erase(projected["ids"].get(resource_id))
		projected["ids"].erase(resource_id)
		if projected.has("publication"):
			projected["publication"].erase(resource_id)
	ids.erase(resource_id)
	world._mark_known_resource_marker_changed(cached, resource_id)
	var cell_index = world._resource_cell_index(memory)
	var by_cell: Dictionary = cached.get("by_cell", {})
	var cell_ids: Dictionary = by_cell.get(cell_index, {})
	cell_ids.erase(resource_id)
	if cell_ids.is_empty():
		by_cell.erase(cell_index)
	else:
		by_cell[cell_index] = cell_ids
	var chunk_key = world._resource_chunk_key(memory)
	var by_chunk: Dictionary = cached.get("by_chunk", {})
	var chunk_ids: Dictionary = by_chunk.get(chunk_key, {})
	chunk_ids.erase(resource_id)
	if chunk_ids.is_empty():
		by_chunk.erase(chunk_key)
	else:
		by_chunk[chunk_key] = chunk_ids
	return true


func _resource_cell_index(world, resource: Dictionary) -> int:
	var position = Vector2(resource.get("pos", Vector2.ZERO))
	return floori(position.y) * world.map_size.x + floori(position.x)


func _resource_chunk_key(world, resource: Dictionary) -> Vector2i:
	var position = Vector2(resource.get("pos", Vector2.ZERO))
	return Vector2i(
		floori(position.x / float(RESOURCE_MEMORY_CHUNK_SIZE)),
		floori(position.y / float(RESOURCE_MEMORY_CHUNK_SIZE))
	)


func get_known_resources_in_bounds(world, observer_team: int, bounds: Rect2) -> Array:
	if observer_team <= 0:
		return world.resource_nodes.filter(func(resource): return bounds.has_point(Vector2(resource.get("pos", Vector2.ZERO))))
	# Ensure the incremental exploration cache is current, then traverse only
	# remembered resource cells intersecting the camera. Reading the live cell
	# index here would leak hidden depletion/removal through the fog.
	world.get_known_resources(observer_team)
	var cached: Dictionary = known_resources_by_player.get(observer_team, {})
	var known_ids: Dictionary = cached.get("ids", {})
	var known_by_chunk: Dictionary = cached.get("by_chunk", {})
	var start_x = clampi(floori(bounds.position.x), 0, world.map_size.x)
	var start_y = clampi(floori(bounds.position.y), 0, world.map_size.y)
	var end_x = clampi(ceili(bounds.end.x), 0, world.map_size.x)
	var end_y = clampi(ceili(bounds.end.y), 0, world.map_size.y)
	var view_bounds = Rect2i(start_x, start_y, maxi(0, end_x - start_x), maxi(0, end_y - start_y))
	var view: Dictionary = cached.get("render_view", {})
	if view.get("bounds") == view_bounds:
		var retained: Array = view["records"]
		var result = retained
		var changed_records: Array = []
		var removed_ids: Array = []
		for id_value in view["dirty"]:
			var id = int(id_value)
			var low = 0
			var high = result.size()
			while low < high:
				var middle = (low + high) / 2
				if int(result[middle]["id"]) < id: low = middle + 1
				else: high = middle
			var existing = low < result.size() and int(result[low]["id"]) == id
			var record: Dictionary = known_ids.get(id, {})
			var inside = not record.is_empty() and view_bounds.has_point(Vector2i(Vector2(record["pos"]).floor()))
			if not existing and not inside: continue
			if existing and inside and is_same(result[low], record): continue
			if inside: changed_records.append(record)
			else: removed_ids.append(id)
			if is_same(result, retained): result = retained.duplicate()
			if existing:
				if inside: result[low] = record
				else: result.remove_at(low)
			elif inside: result.insert(low, record)
		view["dirty"].clear()
		result.make_read_only()
		view["records"] = result
		if not is_same(result, retained):
			changed_records.make_read_only()
			removed_ids.make_read_only()
			var delta = {"valid": true, "previous": retained, "current": result, "changed": changed_records, "removed": removed_ids}
			delta.make_read_only()
			view["delta"] = delta
		return result
	var result: Array = []
	if end_x <= start_x or end_y <= start_y:
		result.make_read_only()
		cached["render_view"] = {"bounds": view_bounds, "records": result, "dirty": {}}
		return result
	var kernel: Variant = world.render_entity_projection_cache.native_kernel
	if world.native_render_resource_queries_enabled and kernel != null and kernel.has_method("known_resources_in_bounds"):
		result = kernel.known_resources_in_bounds(known_ids,known_by_chunk,view_bounds,RESOURCE_MEMORY_CHUNK_SIZE)
		cached["render_view"] = {"bounds":view_bounds,"records":result,"dirty":{}}
		return result
	var first_chunk_x = floori(float(start_x) / float(RESOURCE_MEMORY_CHUNK_SIZE))
	var first_chunk_y = floori(float(start_y) / float(RESOURCE_MEMORY_CHUNK_SIZE))
	var last_chunk_x = floori(float(end_x - 1) / float(RESOURCE_MEMORY_CHUNK_SIZE))
	var last_chunk_y = floori(float(end_y - 1) / float(RESOURCE_MEMORY_CHUNK_SIZE))
	for chunk_y in range(first_chunk_y, last_chunk_y + 1):
		for chunk_x in range(first_chunk_x, last_chunk_x + 1):
			var chunk_ids: Dictionary = known_by_chunk.get(Vector2i(chunk_x, chunk_y), {})
			for resource_id_value in chunk_ids.keys():
				var resource: Variant = known_ids.get(int(resource_id_value))
				if not resource is Dictionary:
					continue
				var position = Vector2(resource.get("pos", Vector2.ZERO))
				var cell_x = floori(position.x)
				var cell_y = floori(position.y)
				if cell_x >= start_x and cell_x < end_x and cell_y >= start_y and cell_y < end_y:
					result.append(resource)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	result.make_read_only()
	# One camera publication per observer, bounded by this query. Only legal
	# observation changes enter its queue; hidden live changes never reach it.
	cached["render_view"] = {"bounds": view_bounds, "records": result, "dirty": {}}
	return result


func known_resource_view_delta(world, observer_team: int) -> Dictionary:
	# At most the latest legal publication and its predecessor. Consumers that
	# missed a publication use the ordinary full comparison instead.
	return known_resources_by_player.get(observer_team, {}).get("render_view", {}).get("delta", {})


func _mark_resource_view_changed(world, cached: Dictionary, id: int) -> void:
	var view: Dictionary = cached.get("render_view", {})
	if not view.is_empty(): view["dirty"][id] = true


func _replace_known_resource(world, known: Array, replacement: Dictionary) -> void:
	var id = int(replacement["id"])
	var low = 0
	var high = known.size()
	while low < high:
		var middle = (low + high) / 2
		if int(known[middle]["id"]) < id:
			low = middle + 1
		else:
			high = middle
	if low < known.size() and int(known[low]["id"]) == id:
		known[low] = replacement
	else:
		known.insert(low, replacement)


func _insert_known_resource_sorted(world, known: Array, resource: Dictionary) -> void:
	var resource_id = int(resource.get("id", -1))
	var lower = 0
	var upper = known.size()
	while lower < upper:
		var middle = (lower + upper) / 2
		if resource_id < int(known[middle].get("id", -1)):
			upper = middle
		else:
			lower = middle + 1
	known.insert(lower, resource)
