class_name RoRCommandMarkerPresentation
extends RefCounted

# The marker is a screen-space presentation effect anchored to a world position.
# Geometry is calibrated from two 1680x1050 RoR 1.1/UPatch captures. Exact source
# frame timing remains data-tunable until a high-frame-rate reference is captured.
const DEFAULT_DURATION := 0.42
const CONTRACT_DURATION_RATIO := 0.72
const WIDE_HALF_EXTENT := Vector2(22.0, 14.0)
const CONTRACTED_HALF_EXTENT := Vector2(13.0, 10.0)
const BRIGHT_COLOR := Color8(255, 1, 1)
const SHADOW_COLOR := Color8(130, 28, 0)
const SHADOW_OFFSET := Vector2(2.0, 2.0)

var world_position := Vector2.ZERO
var elapsed := 0.0
var duration := DEFAULT_DURATION
var active := false


func trigger(position: Vector2, requested_duration: float = DEFAULT_DURATION) -> void:
	world_position = position
	elapsed = 0.0
	duration = maxf(requested_duration, 0.001)
	active = true


func reset() -> void:
	world_position = Vector2.ZERO
	elapsed = 0.0
	duration = DEFAULT_DURATION
	active = false


func advance(delta: float) -> void:
	if not active:
		return
	elapsed += maxf(delta, 0.0)
	if elapsed + 0.000001 >= duration:
		active = false


func snapshot() -> Dictionary:
	if not active:
		return {}
	var normalized := clampf(elapsed / duration, 0.0, 1.0)
	var contract_progress := clampf(normalized / CONTRACT_DURATION_RATIO, 0.0, 1.0)
	# A smooth convergence avoids sub-pixel jitter while keeping the two measured
	# wide/contracted silhouettes. Rendering snaps the returned points to pixels.
	contract_progress = contract_progress * contract_progress * (3.0 - 2.0 * contract_progress)
	var half_extent := WIDE_HALF_EXTENT.lerp(CONTRACTED_HALF_EXTENT, contract_progress)
	var opacity := 1.0 if normalized < 0.82 else clampf((1.0 - normalized) / 0.18, 0.0, 1.0)
	return {
		"world_position": world_position,
		"half_extent": half_extent,
		"opacity": opacity,
		"bright_color": Color(BRIGHT_COLOR, opacity),
		"shadow_color": Color(SHADOW_COLOR, opacity),
		"shadow_offset": SHADOW_OFFSET,
		"normalized_time": normalized,
	}


static func arrow_polygon(direction: Vector2, outer_extent: float) -> PackedVector2Array:
	var axis := direction.normalized()
	var perpendicular := Vector2(-axis.y, axis.x)
	var gap := 1.0
	var head_length := minf(6.0, maxf(3.0, outer_extent * 0.38))
	var head_half_width := minf(5.0, maxf(3.0, outer_extent * 0.31))
	var shaft_half_width := 2.0
	var head_base := gap + head_length
	var tail := maxf(head_base + 2.0, outer_extent)
	return PackedVector2Array([
		axis * gap,
		axis * head_base + perpendicular * head_half_width,
		axis * head_base + perpendicular * shaft_half_width,
		axis * tail + perpendicular * shaft_half_width,
		axis * tail - perpendicular * shaft_half_width,
		axis * head_base - perpendicular * shaft_half_width,
		axis * head_base - perpendicular * head_half_width,
	])
