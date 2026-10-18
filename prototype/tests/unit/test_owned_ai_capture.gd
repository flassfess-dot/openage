extends SceneTree
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	var kernel = ClassDB.instantiate("RoRReadModelKernel")
	if kernel == null or not kernel.has_method("capture_owned_frozen"):
		push_error("Native owned capture is required")
		quit(1)
		return
	var actor := {"id":7,"profile":{"attacks":[{"type_id":4,"amount":3.0}]}}
	var actors := [actor]
	var input := {"actors":actors}
	var expected := Data.capture_frozen(input)
	var frozen := Data.freeze_owned(input)
	check(frozen == expected,"owned handoff preserves the full detached value")
	check(is_same(frozen,input) and is_same(frozen["actors"],actors) and is_same(frozen["actors"][0],actor),"producer-owned arrays and rows are frozen without cloning")
	check(input.is_read_only() and actors.is_read_only() and actor.is_read_only() and actor["profile"]["attacks"][0].is_read_only(),"every owned container becomes readonly")
	var live_child := {"points":[Vector2.ONE]}
	var borrowed := {"child":live_child}
	borrowed.make_read_only()
	var publication := Data.freeze_owned({"borrowed":borrowed})
	live_child["points"].append(Vector2.ZERO)
	check(not live_child.is_read_only() and not live_child["points"].is_read_only(),"readonly borrowing never freezes a mutable external descendant")
	check(publication["borrowed"]["child"]["points"].size() == 1,"borrowed mutable descendants are detached")
	var buffer := PackedVector2Array([Vector2.ONE])
	var packed_parent := {"buffer":buffer}
	packed_parent.make_read_only()
	var detached := Data.freeze_owned({"borrowed":packed_parent,"own_buffer":buffer})
	buffer[0] = Vector2.ZERO
	check(detached["borrowed"]["buffer"][0] == Vector2.ONE and detached["own_buffer"][0] == Vector2.ONE,"packed buffers detach through owned and readonly branches")
	check(not is_same(detached["borrowed"],packed_parent),"readonly packed-buffer parents are copied instead of edited")
	for value in [RefCounted.new(),Callable(self,"_initialize"),Signal(self,"tree_changed"),RID()]:
		check(Data.freeze_owned({"nested":[value]}).is_empty(),"owned handoff rejects live object/callable/signal/RID values")
	var sealed := Data.seal(Data.capture_frozen({"value":1}))
	var forged := {Data.SEAL_KEY:sealed[Data.SEAL_KEY],"object":RefCounted.new()}
	forged.make_read_only()
	check(Data.freeze_owned({"borrowed":forged}).is_empty(),"copied certification tokens cannot hide borrowed objects")
	var mutable := {"nested":{"value":3}}
	var regular := Data.capture_frozen(mutable)
	mutable["nested"]["value"] = 4
	check(not mutable.is_read_only() and regular["nested"]["value"] == 3,"ordinary capture still preserves its mutable source")
	for failure in failures: push_error(failure)
	print("Owned AI capture: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
