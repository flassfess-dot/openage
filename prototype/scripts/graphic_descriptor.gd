class_name RoRGraphicDescriptor

const FRAME_EVENT_KEYS := [
	"damage_frame",
	"projectile_release_frame",
	"resource_hit_frame",
	"construction_hit_frame",
	"death_complete_frame",
]

var asset_name: String = ""
var logical_angle_count: int = 1
var stored_angle_count: int = 1
var frames_per_angle: int = 1
var frame_duration: float = 0.1
var loop: bool = true
var mirroring_mode: int = 0
var start_angle_degrees: int = 0
var slp_direction_order: Array[int] = []
var hotspots: Array[Vector2] = []
var deltas: Array = []
var frame_events: Dictionary = {}


func _init(name: String = "", spec: Dictionary = {}, available_frame_count: int = 1, loop_enabled: bool = true) -> void:
	asset_name = name
	logical_angle_count = maxi(1, int(spec.get("angle_count", 1)))
	frames_per_angle = maxi(1, int(spec.get("frames_per_angle", available_frame_count)))
	stored_angle_count = maxi(1, ceili(float(available_frame_count) / float(frames_per_angle)))
	frame_duration = maxf(0.001, float(spec.get("frame_rate", 0.1)))
	loop = bool(spec.get("loop", loop_enabled))
	mirroring_mode = int(spec.get("mirroring_mode", 0))
	start_angle_degrees = posmod(int(spec.get("start_angle", 0)), 360)
	deltas = spec.get("deltas", []).duplicate(true)
	var degree_step := 360.0 / float(logical_angle_count)
	for index in range(logical_angle_count):
		slp_direction_order.append(posmod(roundi(start_angle_degrees + index * degree_step), 360))
	for event_name in FRAME_EVENT_KEYS:
		if spec.has(event_name):
			frame_events[event_name] = int(spec[event_name])

func set_hotspots(values: Array[Vector2]) -> void:
	hotspots = values.duplicate()

func hotspot_for(frame_index: int, fallback: Vector2) -> Vector2:
	return hotspots[frame_index] if frame_index >= 0 and frame_index < hotspots.size() else fallback

func resolve(logical_facing: int, animation_time: float, available_frame_count: int) -> Dictionary:
	var facing := posmod(logical_facing, logical_angle_count)
	var direction_degrees := slp_direction_order[facing]
	var source_direction := facing
	var mirrored := false
	if mirroring_mode != 0 and direction_degrees > 180:
		source_direction = posmod(logical_angle_count - facing, logical_angle_count)
		mirrored = true
	if source_direction >= stored_angle_count:
		source_direction = stored_angle_count - 1

	var elapsed_frame := maxi(0, floori(animation_time / frame_duration))
	var animation_frame := elapsed_frame % frames_per_angle if loop else mini(elapsed_frame, frames_per_angle - 1)
	var frame_index := source_direction * frames_per_angle + animation_frame
	frame_index = clampi(frame_index, 0, maxi(0, available_frame_count - 1))
	return {
		"logical_facing": facing,
		"direction_degrees": direction_degrees,
		"source_direction": source_direction,
		"mirrored": mirrored,
		"animation_frame": animation_frame,
		"frame_index": frame_index,
	}
