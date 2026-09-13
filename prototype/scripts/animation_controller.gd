class_name RoRAnimationController

const IDLE := "Idle"
const MOVE := "Move"
const TURN := "Turn"
const ATTACK_WINDUP := "AttackWindup"
const ATTACK_RECOVER := "AttackRecover"
const GATHER := "Gather"
const CARRY := "Carry"
const BUILD := "Build"
const REPAIR := "Repair"
const CONVERT := "Convert"
const HEAL := "Heal"
const DIE := "Die"
const DECAY := "Decay"

const ALL_STATES := [IDLE, MOVE, TURN, ATTACK_WINDUP, ATTACK_RECOVER, GATHER, CARRY, BUILD, REPAIR, CONVERT, HEAL, DIE, DECAY]
const STATE_TO_CLIP := {
	IDLE: "idle",
	MOVE: "move",
	TURN: "idle",
	ATTACK_WINDUP: "attack",
	ATTACK_RECOVER: "attack",
	GATHER: "work",
	CARRY: "move",
	BUILD: "build",
	REPAIR: "work",
	CONVERT: "convert",
	HEAL: "heal",
	DIE: "death",
	DECAY: "death",
}


static func clip_for_state(state: String) -> String:
	return STATE_TO_CLIP.get(state, "idle")

static func state_for_task(task: String, moving: bool, action_ready: bool = false) -> String:
	if moving:
		return MOVE
	match task:
		"attack": return ATTACK_WINDUP if action_ready else ATTACK_RECOVER
		"gather": return GATHER
		"carry": return CARRY
		"build": return BUILD
		"repair": return REPAIR
		"convert": return CONVERT
		"heal": return HEAL
		"turn": return TURN
		"die": return DIE
		"decay": return DECAY
		_: return IDLE

static func update(unit: Dictionary, requested_state: String, delta: float, restart_same_clip: bool = false) -> bool:
	var state := requested_state if ALL_STATES.has(requested_state) else IDLE
	var previous_state := String(unit.get("anim_state", ""))
	if previous_state != state:
		unit["anim_state"] = state
		if restart_same_clip or clip_for_state(previous_state) != clip_for_state(state):
			unit["anim"] = 0.0
			unit["animation_events_fired"] = {}
		else:
			unit["anim"] = float(unit.get("anim", 0.0)) + maxf(0.0, delta)
		return true
	unit["anim"] = float(unit.get("anim", 0.0)) + maxf(0.0, delta)
	return false

static func event_reached(unit: Dictionary, event_name: String, event_frame: int, frame_duration: float) -> bool:
	if event_frame < 0 or frame_duration <= 0.0:
		return false
	var fired: Dictionary = unit.get("animation_events_fired", {})
	if bool(fired.get(event_name, false)):
		return false
	var current_frame := floori(float(unit.get("anim", 0.0)) / frame_duration)
	if current_frame < event_frame:
		return false
	fired[event_name] = true
	unit["animation_events_fired"] = fired
	return true
