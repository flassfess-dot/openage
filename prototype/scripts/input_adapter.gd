class_name RoRInputAdapter

const PointerController := preload("res://scripts/pointer_controller.gd")

var pointer := PointerController.new()
var pointer_position := Vector2.ZERO


func reset() -> void:
	pointer.reset()


func translate(event: InputEvent, in_world_area: bool = true) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if event is InputEventMouseButton:
		pointer_position = event.position
		if event.pressed and not in_world_area:
			reset()
			actions.append({"type": "consume_outside_world"})
			return actions
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					actions.append({"type": "zoom", "position": event.position, "steps": 1})
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					actions.append({"type": "zoom", "position": event.position, "steps": -1})
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					pointer.begin_primary(event.position)
					actions.append({"type": "selection_started"})
				else:
					var selection := pointer.end_primary(event.position)
					if not selection.is_empty():
						actions.append({"type": "selection_committed", "from": selection["from"], "to": selection["to"], "mode": selection["type"]})
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					pointer.begin_secondary(event.position)
				else:
					var command := pointer.end_secondary(event.position)
					if command.get("type", "") == "context_command":
						actions.append({"type": "context_committed", "position": command["position"]})
					elif command.get("type", "") == "formation_direction":
						actions.append({"type": "context_committed", "position": command["position"], "direction_end": command["direction_end"]})
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					pointer.begin_pan(event.position)
				else:
					pointer.end_pan()
	elif event is InputEventMouseMotion:
		pointer_position = event.position
		actions.append({"type": "pointer_moved", "pan_delta": pointer.update_position(event.position)})
	elif event is InputEventKey and event.pressed and not event.echo:
		var group_number := control_group_number(event.keycode)
		if group_number > 0:
			actions.append({"type": "control_group", "number": group_number, "assign": event.ctrl_pressed, "additive": event.shift_pressed})
			return actions
		match event.keycode:
			KEY_Q: actions.append({"type": "attack_move_mode"})
			KEY_X: actions.append({"type": "stop"})
			KEY_H: actions.append({"type": "hold"})
			KEY_V: actions.append({"type": "cycle_stance"})
			KEY_F5: actions.append({"type": "set_formation", "formation": "LINE"})
			KEY_F6: actions.append({"type": "set_formation", "formation": "RECTANGLE"})
			KEY_F7: actions.append({"type": "set_formation", "formation": "COLUMN"})
			KEY_F8: actions.append({"type": "set_formation", "formation": "WEDGE"})
			KEY_F9: actions.append({"type": "set_formation", "formation": "STAGGERED"})
			KEY_T: actions.append({"type": "train", "archetype": "clubman"})
			KEY_M: actions.append({"type": "toggle_audio"})
			KEY_SPACE: actions.append({"type": "toggle_pause"})
			KEY_COMMA: actions.append({"type": "change_speed", "direction": -1})
			KEY_PERIOD: actions.append({"type": "change_speed", "direction": 1})
			KEY_F3: actions.append({"type": "toggle_diagnostics"})
			KEY_F10: actions.append({"type": "open_calibration"})
			KEY_DELETE: actions.append({"type": "martyrdom"})
			KEY_U: actions.append({"type": "unload", "position": pointer_position})
			KEY_R: actions.append({"type": "resign"} if event.shift_pressed else {"type": "reset_game"})
			KEY_ESCAPE: actions.append({"type": "quit"})
	return actions


func selection_gesture() -> Dictionary:
	if not pointer.is_selecting():
		return {}
	return {"from": pointer.anchor, "to": pointer.current, "is_box": pointer.state == PointerController.State.PRIMARY_BOX}


func formation_gesture() -> Dictionary:
	if not pointer.is_setting_formation_direction():
		return {}
	return {"position": pointer.anchor, "direction_end": pointer.current}


static func control_group_number(keycode: Key) -> int:
	match keycode:
		KEY_1: return 1
		KEY_2: return 2
		KEY_3: return 3
		KEY_4: return 4
		KEY_5: return 5
		KEY_6: return 6
		KEY_7: return 7
		KEY_8: return 8
		KEY_9: return 9
		_: return 0
