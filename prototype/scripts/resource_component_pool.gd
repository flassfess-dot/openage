extends RefCounted
## World-owned immutable configuration shared only by resource records.
const Data := preload("res://scripts/isolated_task_data.gd")
const NAMES := ["animation_state", "cargo", "combat", "conversion", "conversion_resistance", "healing", "health", "ownership", "production", "resource_carrier", "technology", "vision", "worker", "transform", "movement", "order", "trade"]
const LOCATION_KEY := "_ror_resource_locations"
const LOCATION_NAMES := ["transform", "movement", "order", "trade"]
const LOCATION_FIELDS := [["previous_position"], ["target", "destination"], ["target_position"], ["approach_position"]]
const MAX_TEMPLATES := 256
const MAX_TEMPLATE_BYTES := 64 * 1024
const MAX_BYTES := 4 * 1024 * 1024
var enabled := true
var buckets: Dictionary = {}
var template_count := 0
var retained_bytes := 0
var shared_components := 0
# Keep the storage experiment opt-in until its movement latency is explained.
# Already-marked checkpoints remain readable and preserve their storage form.
var location_templates_enabled := OS.get_environment("ROR_DIAGNOSTIC_ENABLE_RESOURCE_LOCATIONS") == "1" and OS.get_environment("ROR_DIAGNOSTIC_DISABLE_RESOURCE_LOCATIONS") != "1"
var location_binding_records := 0

func clear() -> void:
	buckets.clear()
	template_count = 0
	retained_bytes = 0
	shared_components = 0
	location_binding_records = 0

func intern(resource: Dictionary) -> void:
	if not enabled: return
	if location_templates_enabled: _compact_locations(resource)
	var location_mask := _location_mask(resource)
	if location_mask > 0: location_binding_records += 1
	var components: Dictionary = resource.get("components", {})
	if components.is_read_only():
		components = components.duplicate()
		resource["components"] = components
	for name in NAMES:
		if name in LOCATION_NAMES and not (location_mask & (1 << LOCATION_NAMES.find(name))): continue
		var value: Variant = components.get(name)
		if not value is Dictionary: continue
		# Active capabilities own mutable nested state in their domain systems.
		if name in ["cargo", "conversion", "healing", "worker", "trade"] and bool(value.get("enabled", false)): continue
		if name == "order" and (not bool(value.get("completed", true)) or not value.get("queued", []).is_empty()): continue
		# Byte equality also preserves key order and the exact scalar types used
		# by checkpoint encoding. A hash collision can never merge two values.
		var encoded := var_to_bytes(value)
		if encoded.size() > MAX_TEMPLATE_BYTES: continue
		var key := Vector2i(NAMES.find(name), hash(encoded))
		var entries: Array = buckets.get(key, [])
		var found := false
		for entry in entries:
			if entry["encoded"] == encoded:
				components[name] = entry["value"]
				shared_components += 1
				found = true
				break
		if found or template_count >= MAX_TEMPLATES or retained_bytes + encoded.size() > MAX_BYTES: continue
		var shared: Dictionary = value.duplicate(true)
		if not Data.freeze_detached(shared, 0, false): continue
		entries.append({"encoded": encoded, "value": shared})
		buckets[key] = entries
		components[name] = shared
		template_count += 1
		retained_bytes += encoded.size()

static func detach(resource: Dictionary) -> void:
	# Materialize before any authoritative nested write. A negative marker keeps
	# the materialized storage form stable across checkpoint restore/replay.
	project_locations(resource, true)
	var components: Dictionary = resource.get("components", {})
	if components.is_read_only():
		components = components.duplicate()
		resource["components"] = components
	for name in NAMES:
		var value: Variant = components.get(name)
		if value is Dictionary and value.is_read_only(): components[name] = value.duplicate(true)


static func _location_mask(entity: Dictionary) -> int:
	var binding: Variant = entity.get(LOCATION_KEY)
	if not binding is Vector3 or not binding.is_finite(): return 0
	var mask := int(binding.z)
	return mask if mask > 0 and mask <= 15 and float(mask) == float(binding.z) else 0


static func _compact_locations(resource: Dictionary) -> void:
	# Existing markers include materialized records (-1). Never recompact these
	# implicitly on load: storage identity contributes to canonical save hashes.
	if resource.has(LOCATION_KEY) or not resource.get("pos") is Vector2: return
	var origin: Vector2 = resource["pos"]
	if not origin.is_finite(): return
	var components: Dictionary = resource.get("components", {})
	if components.is_read_only():
		components = components.duplicate()
		resource["components"] = components
	var mask := 0
	for index in range(LOCATION_NAMES.size()):
		var name: String = LOCATION_NAMES[index]
		var value: Variant = components.get(name)
		if not value is Dictionary: continue
		var component: Dictionary = value
		if name == "movement":
			if float(component.get("speed", resource.get("speed", 0.0))) != 0.0 or String(component.get("domain", "static")) != "static" or not component.get("path", []).is_empty() or Vector2(component.get("actual_velocity", Vector2.ZERO)) != Vector2.ZERO: continue
		elif name == "order":
			if String(component.get("type", "none")) != "none" or not bool(component.get("completed", true)) or int(component.get("revision", 0)) != 0 or int(component.get("target_entity_id", -1)) != -1 or not component.get("queued", []).is_empty() or not component.get("history", []).is_empty(): continue
		elif name == "trade":
			if bool(component.get("enabled", false)) or String(component.get("stage", "idle")) != "idle" or int(component.get("target_dock_id", -1)) != -1 or int(component.get("home_dock_id", -1)) != -1 or int(component.get("cargo_goods", 0)) != 0 or int(component.get("cargo_gold", 0)) != 0 or int(component.get("trip_count", 0)) != 0: continue
		var matches := true
		for field in LOCATION_FIELDS[index]:
			if not component.get(field) is Vector2 or Vector2(component[field]) != origin:
				matches = false
				break
		if not matches: continue
		if component.is_read_only():
			component = component.duplicate(true)
			components[name] = component
		for field in LOCATION_FIELDS[index]: component.erase(field)
		mask |= 1 << index
	if mask != 0: resource[LOCATION_KEY] = Vector3(origin.x, origin.y, float(mask))


static func project_component_locations(entity: Dictionary, name: String, component: Dictionary) -> void:
	var index := LOCATION_NAMES.find(name)
	if index < 0 or not (_location_mask(entity) & (1 << index)): return
	var binding: Vector3 = entity[LOCATION_KEY]
	var origin := Vector2(binding.x, binding.y)
	for field in LOCATION_FIELDS[index]:
		if not component.has(field): component[field] = origin


static func project_locations(entity: Dictionary, materialize: bool = false) -> void:
	if not entity.has(LOCATION_KEY): return
	var mask := _location_mask(entity)
	if mask > 0:
		var components: Dictionary = entity.get("components", {})
		if components.is_read_only():
			components = components.duplicate()
			entity["components"] = components
		for index in range(LOCATION_NAMES.size()):
			if not (mask & (1 << index)): continue
			var name: String = LOCATION_NAMES[index]
			var component: Dictionary = components.get(name, {})
			if component.is_read_only():
				component = component.duplicate(true)
				components[name] = component
			project_component_locations(entity, name, component)
	if materialize:
		if mask > 0:
			var binding: Vector3 = entity[LOCATION_KEY]
			entity[LOCATION_KEY] = Vector3(binding.x, binding.y, -1.0)
	else: entity.erase(LOCATION_KEY)
