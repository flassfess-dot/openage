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

static func is_detached(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_RID, TYPE_SIGNAL:
			return false
		TYPE_DICTIONARY:
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
			for item in value:
				if not is_detached(item, depth + 1):
					return false
	return true

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			_freeze(key)
			_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value:
			_freeze(item)
		value.make_read_only()

static func seal(value: Dictionary) -> Dictionary:
	if not is_detached(value):
		return {}
	seal_mutex.lock()
	if value.is_read_only() and value.has(SEAL_KEY) and sealed_roots.has(value[SEAL_KEY]) and is_same(sealed_roots[value[SEAL_KEY]], value):
		seal_mutex.unlock()
		return value
	# A readonly root cannot receive a marker. Copy its top level, then freeze
	# every nested container; untrusted markers always receive a fresh identity.
	var root: Dictionary = value
	if value.is_read_only():
		root = {}
		root.merge(value)
	var token := next_seal
	next_seal += 1
	root[SEAL_KEY] = token
	_freeze(root)
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
