class_name RoRIsolatedTaskData
extends RefCounted

# Large immutable topology DTOs are validated once. A bounded, synchronized
# LRU identity registry avoids walking the same map for every chunk submission.
# Read-only is recursive; a marker on a forged/mutated dictionary is insufficient.
const MAX_SEALED_ROOTS := 12
const SEAL_KEY := "_ror_detached_dto"
static var seal_mutex := Mutex.new()
static var sealed_roots: Dictionary = {}
static var next_seal := 1
const MAX_IMMUTABLE_ROOTS := 12
static var immutable_roots: Array = []

static func is_detached(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_RID, TYPE_SIGNAL:
			return false
		TYPE_DICTIONARY:
			if is_trusted_immutable(value):
				return true
			if value.is_read_only() and value.has(SEAL_KEY):
				seal_mutex.lock()
				var token: Variant = value[SEAL_KEY]
				var trusted := sealed_roots.has(token) and is_same(sealed_roots[token], value)
				if trusted:
					# Transient route snapshots must not evict an actively used map.
					# Promote only the exact validated, recursively readonly root.
					sealed_roots.erase(token)
					sealed_roots[token] = value
				seal_mutex.unlock()
				if trusted:
					return true
			for key in value:
				if not is_detached(key, depth + 1) or not is_detached(value[key], depth + 1):
					return false
		TYPE_ARRAY:
			if value.is_typed() and value.get_typed_builtin() in [TYPE_VECTOR2, TYPE_VECTOR2I]:
				return true
			if is_trusted_immutable(value):
				return true
			for item in value:
				if not is_detached(item, depth + 1):
					return false
	return true

static func _freeze(value: Variant) -> void:
	if is_trusted_immutable(value):
		return
	if value is Dictionary:
		for key in value:
			_freeze(key)
			_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		if not (value.is_typed() and value.get_typed_builtin() in [TYPE_VECTOR2, TYPE_VECTOR2I]):
			for item in value:
				_freeze(item)
		value.make_read_only()

# Only producer-owned DTO containers may be registered. Identity, recursive
# validation and readonly state are required; no user-provided marker is trusted.
static func is_trusted_immutable(value: Variant) -> bool:
	if not (value is Dictionary or value is Array) or not value.is_read_only():
		return false
	# Readonly typed point arrays contain only value types. They are safe by
	# construction and need no retaining registry entry, even after eviction.
	if value is Array and value.is_typed() and value.get_typed_builtin() in [TYPE_VECTOR2, TYPE_VECTOR2I]:
		return true
	seal_mutex.lock()
	if value is Dictionary and value.has(SEAL_KEY):
		var token: Variant = value[SEAL_KEY]
		if sealed_roots.has(token) and is_same(sealed_roots[token], value):
			sealed_roots.erase(token)
			sealed_roots[token] = value
			seal_mutex.unlock()
			return true
	for index in range(immutable_roots.size()):
		if is_same(immutable_roots[index], value):
			immutable_roots.remove_at(index)
			immutable_roots.append(value)
			seal_mutex.unlock()
			return true
	seal_mutex.unlock()
	return false

static func freeze_detached(value: Variant, depth: int = 0, retain_root: bool = true) -> bool:
	if depth > 64:
		return false
	if is_trusted_immutable(value):
		return true
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_RID, TYPE_SIGNAL:
			return false
		TYPE_DICTIONARY:
			for key in value:
				if not freeze_detached(key, depth + 1, false) or not freeze_detached(value[key], depth + 1, false):
					return false
			value.make_read_only()
		TYPE_ARRAY:
			if not (value.is_typed() and value.get_typed_builtin() in [TYPE_VECTOR2, TYPE_VECTOR2I]):
				for item in value:
					if not freeze_detached(item, depth + 1, false):
						return false
			value.make_read_only()
		_:
			return true
	if not retain_root or (value is Array and value.is_typed() and value.get_typed_builtin() in [TYPE_VECTOR2, TYPE_VECTOR2I]):
		return true
	_retain_immutable(value)
	return true

# Internal producer hook. The caller must have validated and recursively frozen
# every child, and must own the outer container. Identity remains the only trust
# criterion; a readonly container or a user-supplied marker is not a certificate.
static func _retain_immutable(value: Variant) -> void:
	assert((value is Dictionary or value is Array) and value.is_read_only())
	seal_mutex.lock()
	for index in range(immutable_roots.size()):
		if is_same(immutable_roots[index], value):
			immutable_roots.remove_at(index)
			break
	while immutable_roots.size() >= MAX_IMMUTABLE_ROOTS:
		immutable_roots.pop_front()
	immutable_roots.append(value)
	seal_mutex.unlock()

# Copy mutable decision state, sharing only recursively validated readonly
# islands. In particular a retained navigation map is neither copied nor walked.
static func capture(value: Variant, depth: int = 0) -> Variant:
	if depth > 64 or is_trusted_immutable(value):
		return value
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[capture(key, depth + 1)] = capture(value[key], depth + 1)
		return result
	if value is Array:
		var result: Array = value.duplicate()
		for index in range(value.size()):
			result[index] = capture(value[index], depth + 1)
		return result
	return copy(value)

static func seal(value: Dictionary) -> Dictionary:
	if not is_detached(value):
		return {}
	seal_mutex.lock()
	if value.is_read_only() and value.has(SEAL_KEY) and sealed_roots.has(value[SEAL_KEY]) and is_same(sealed_roots[value[SEAL_KEY]], value):
		seal_mutex.unlock()
		return value
	var token := next_seal
	next_seal += 1
	seal_mutex.unlock()
	var root: Dictionary = value.duplicate() if value.is_read_only() else value
	root[SEAL_KEY] = token
	# Tree work must happen outside the registry mutex: validated immutable
	# children consult the same registry, and workers may finish concurrently.
	_freeze(root)
	seal_mutex.lock()
	while sealed_roots.size() >= MAX_SEALED_ROOTS:
		sealed_roots.erase(sealed_roots.keys()[0])
	sealed_roots[token] = root
	seal_mutex.unlock()
	return root

static func copy(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY, TYPE_ARRAY:
			return value.duplicate(true)
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return value.duplicate()
	return value
