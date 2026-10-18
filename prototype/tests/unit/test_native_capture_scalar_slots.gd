extends SceneTree
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	var kernel = ClassDB.instantiate("RoRReadModelKernel")
	if kernel == null:
		push_error("Native capture is required")
		quit(1)
		return
	var values := [null,true,17,0.375,"text",&"name",Vector2(1.25,2.5),Vector2i(2,3),Vector3(1,2,3),Vector3i(2,3,4),Vector4(1,2,3,4),Color(0.2,0.4,0.6,0.8),Rect2(1,2,3,4),Rect2i(1,2,3,4),Transform2D(0.4,Vector2(3,4)),NodePath("unit/target")]
	var source := {"values":values,"nested":{"enabled":true,"count":4,"position":Vector2.ONE}}
	var captured := Data.capture_frozen(source)
	check(captured == source,"capture preserves unchanged scalar slots and complete nested values")
	for index in range(values.size()):
		check(typeof(captured["values"][index]) == typeof(values[index]),"capture preserves scalar type at %d"%index)
	values.append(99)
	source["nested"]["count"] = 8
	check(captured["values"].size() == 16 and captured["nested"]["count"] == 4,"mutable source remains detached after scalar writeback is skipped")
	var points: Array[Vector2] = [Vector2.ONE,Vector2.ZERO]
	var typed := Data.capture_frozen({"points":points})
	points.append(Vector2(2,3))
	check(typed["points"].is_typed() and typed["points"].size() == 2 and typed["points"].is_read_only(),"typed scalar arrays preserve type, isolation and readonly state")
	var trusted := {"a":1,"b":2}
	trusted.make_read_only()
	var forged := {"a":1,"hidden":RefCounted.new()}
	forged.make_read_only()
	check(not kernel.capture_frozen({"row":forged},[trusted])["valid"],"equal dictionary shape cannot certify a hidden object")
	var trusted_array := [1,2]
	trusted_array.make_read_only()
	var forged_array := [1,Callable(self,"_initialize")]
	forged_array.make_read_only()
	check(not kernel.capture_frozen({"rows":forged_array},[trusted_array])["valid"],"equal array shape cannot certify a callable")
	var retained: Dictionary = kernel.capture_frozen({"row":trusted},[trusted])
	check(retained["valid"] and is_same(retained["value"]["row"],trusted),"exact validated identity still shares its immutable root")
	for failure in failures: push_error(failure)
	print("Native capture scalar slots: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
