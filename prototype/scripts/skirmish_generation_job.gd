class_name RoRSkirmishGenerationJob
extends RefCounted

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var _thread := Thread.new()
var _mutex := Mutex.new()
var _started := false
var _joined := false
var _progress := 0.0
var _stage := "Ожидание"


func start(settings: Dictionary) -> bool:
	if _started:
		return false
	_started = true
	_joined = false
	_update_progress(0.0, "Подготовка генератора")
	var error := _thread.start(_generate.bind(settings.duplicate(true)))
	if error != OK:
		_started = false
		_update_progress(0.0, "Не удалось запустить генератор")
		return false
	return true


func snapshot() -> Dictionary:
	_mutex.lock()
	var result := {
		"started": _started,
		"complete": _started and not _joined and not _thread.is_alive(),
		"progress": _progress,
		"stage": _stage,
	}
	_mutex.unlock()
	return result


func take_result() -> Dictionary:
	if not _started or _joined or _thread.is_alive():
		return {}
	var result: Variant = _thread.wait_to_finish()
	_joined = true
	return result if result is Dictionary else {
		"valid": false,
		"errors": ["skirmish_generation_result_invalid"],
	}


func shutdown() -> void:
	if _started and not _joined:
		_thread.wait_to_finish()
		_joined = true


func _generate(settings: Dictionary) -> Dictionary:
	return SkirmishSettings.build_with_progress(settings, _update_progress)


func _update_progress(value: float, stage: String) -> void:
	_mutex.lock()
	_progress = clampf(value, 0.0, 1.0)
	_stage = stage
	_mutex.unlock()
