class_name RoRCommandMarkerPresentation
extends RefCounted

# data/Interfac.drs SLP 50405 contains the six visible RoR marker frames.
# Only their timing is approximated; the artwork and source order are exact.
const DEFAULT_DURATION := 0.42
const FIRST_VISIBLE_FRAME := 1
const LAST_VISIBLE_FRAME := 6

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
	var frame_index := clampi(FIRST_VISIBLE_FRAME + floori(normalized * float(LAST_VISIBLE_FRAME - FIRST_VISIBLE_FRAME + 1)), FIRST_VISIBLE_FRAME, LAST_VISIBLE_FRAME)
	return {"world_position": world_position, "frame_index": frame_index, "normalized_time": normalized}
