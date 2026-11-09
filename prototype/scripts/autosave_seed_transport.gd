extends RefCounted
## Internal IPC only. User checkpoints keep their existing representation.
## Binary Variant encoding expands shared dictionaries; retain the resource
## pool's immutable components explicitly across the process boundary.
const Pool := preload("res://scripts/resource_component_pool.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const VERSION := 1

static func encode(seed: Dictionary) -> Dictionary:
	var result := {"seed": seed}
	var checkpoint: Dictionary = seed.get("checkpoint", {})
	var world: Dictionary = checkpoint.get("world", {})
	var source: Array = world.get("resource_nodes", [])
	if source.is_empty(): return result
	var rows := source.duplicate()
	var masks := PackedInt32Array()
	masks.resize(rows.size())
	var templates: Array = []
	var candidates: Dictionary = {}
	var retained_bytes := 0
	var references := 0
	for row_index in range(source.size()):
		var row: Dictionary = source[row_index]
		var components: Dictionary = row.get("components", {})
		# Integer references cannot replace values in a typed dictionary.
		if components.get_typed_value_builtin() != TYPE_NIL: continue
		var next: Dictionary = {}
		var mask := 0
		for name_index in range(Pool.NAMES.size()):
			var name: String = Pool.NAMES[name_index]
			var value: Variant = components.get(name)
			if not value is Dictionary or not value.is_read_only(): continue
			var entries: Array = candidates.get(name, [])
			var template_id := -1
			for index in entries:
				if is_same(templates[index], value):
					template_id = int(index)
					break
			if template_id < 0:
				if templates.size() >= Pool.MAX_TEMPLATES: continue
				var bytes := var_to_bytes(value).size()
				if bytes > Pool.MAX_TEMPLATE_BYTES or retained_bytes + bytes > Pool.MAX_BYTES: continue
				template_id = templates.size()
				templates.append(value)
				entries.append(template_id)
				candidates[name] = entries
				retained_bytes += bytes
			if mask == 0: next = components.duplicate()
			# Replace in place: preserve component key order and scalar types in
			# the materialized checkpoint, including the canonical save hashes.
			next[name] = template_id
			mask |= 1 << name_index
			references += 1
		if mask != 0:
			var copy := row.duplicate()
			copy["components"] = next
			rows[row_index] = copy
			masks[row_index] = mask
	if templates.is_empty(): return result
	var next_world := world.duplicate()
	next_world["resource_nodes"] = rows
	var next_checkpoint := checkpoint.duplicate()
	next_checkpoint["world"] = next_world
	var next_seed := seed.duplicate()
	next_seed["checkpoint"] = next_checkpoint
	result["seed"] = next_seed
	result["resource_components"] = {"version": VERSION, "templates": templates, "masks": masks}
	if "--profile-save-memory" in OS.get_cmdline_user_args():
		print("AUTOSAVE seed sharing resources=", rows.size(), " templates=", templates.size(), " references=", references, " template_bytes=", retained_bytes)
	return result

static func decode(envelope: Dictionary) -> Dictionary:
	var seed_value: Variant = envelope.get("seed")
	if not seed_value is Dictionary: return {}
	var seed: Dictionary = seed_value
	if not envelope.has("resource_components"): return seed
	var transport: Variant = envelope["resource_components"]
	if not transport is Dictionary or int(transport.get("version", -1)) != VERSION: return {}
	var templates: Variant = transport.get("templates")
	var masks: Variant = transport.get("masks")
	if not templates is Array or not masks is PackedInt32Array or templates.size() > Pool.MAX_TEMPLATES: return {}
	var checkpoint: Variant = seed.get("checkpoint")
	if not checkpoint is Dictionary: return {}
	var world: Variant = checkpoint.get("world")
	if not world is Dictionary or not world.get("resource_nodes") is Array: return {}
	var rows: Array = world["resource_nodes"]
	if masks.size() != rows.size(): return {}
	var retained_bytes := 0
	for template in templates:
		if not template is Dictionary: return {}
		var bytes := var_to_bytes(template).size()
		retained_bytes += bytes
		if bytes > Pool.MAX_TEMPLATE_BYTES or retained_bytes > Pool.MAX_BYTES: return {}
	# Validate every reference before replacing any placeholder in the seed.
	for row_index in range(rows.size()):
		var mask := int(masks[row_index])
		if mask < 0 or mask >= 1 << Pool.NAMES.size(): return {}
		if mask == 0: continue
		if not rows[row_index] is Dictionary: return {}
		var components: Variant = rows[row_index].get("components")
		if not components is Dictionary or components.is_read_only(): return {}
		for name_index in range(Pool.NAMES.size()):
			if not (mask & (1 << name_index)): continue
			var index: Variant = components.get(Pool.NAMES[name_index])
			if not index is int or int(index) < 0 or int(index) >= templates.size(): return {}
	for template in templates:
		if not Data.freeze_detached(template, 0, false): return {}
	for row_index in range(rows.size()):
		var mask := int(masks[row_index])
		if mask == 0: continue
		var components: Dictionary = rows[row_index]["components"]
		for name_index in range(Pool.NAMES.size()):
			if mask & (1 << name_index):
				var name: String = Pool.NAMES[name_index]
				components[name] = templates[int(components[name])]
	if "--profile-save-memory" in OS.get_cmdline_user_args():
		print("AUTOSAVE seed restored shared templates=", templates.size(), " heap=", OS.get_static_memory_usage())
	return seed
