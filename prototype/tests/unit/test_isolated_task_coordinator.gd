extends SceneTree

const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

static func calculate(input: Dictionary) -> Dictionary:
	OS.delay_usec(int(input.get("delay_us", 0)))
	if bool(input.get("invalid", false)):
		return {"object": RefCounted.new()}
	return {"value": int(input.get("value", 0)) * 2}

func _run() -> void:
	var coordinator := Coordinator.new()
	var source := {"nested": [{"value": 1}], "bytes": PackedByteArray([1, 2])}
	var detached: Dictionary = Data.copy(source)
	source["nested"][0]["value"] = 9
	source["bytes"][0] = 9
	check(detached["nested"][0]["value"] == 1 and detached["bytes"][0] == 1, "DTO containers never retain mutable source")
	check(not Data.is_detached({"nested": [Callable(self, "_run")]}), "nested callable rejected")
	var sealed_source := {"nested": [{"value": 1}]}
	sealed_source.make_read_only()
	var sealed := Data.seal(sealed_source)
	check(sealed["nested"].is_read_only() and sealed["nested"][0].is_read_only(), "sealing a readonly root freezes nested containers")
	check(is_same(Data.seal(sealed), sealed), "resealing a trusted root preserves identity")
	var copied_marker := {Data.SEAL_KEY: sealed[Data.SEAL_KEY], "nested": [{"value": 2}]}
	copied_marker.make_read_only()
	var resealed := Data.seal(copied_marker)
	check(resealed[Data.SEAL_KEY] != sealed[Data.SEAL_KEY] and resealed["nested"].is_read_only(), "untrusted readonly marker receives a fresh frozen root")
	var forged := {Data.SEAL_KEY: sealed[Data.SEAL_KEY], "nested": [RefCounted.new()]}
	forged.make_read_only()
	check(not Data.is_detached(forged), "forged seal cannot bypass Object validation")
	var cyclic: Dictionary = {}
	cyclic["self"] = cyclic
	check(not Data.is_detached(cyclic), "cyclic DTO is rejected before dispatch")
	cyclic.clear()
	var results := coordinator.run_ordered("test", [{"value": 1, "delay_us": 20000}, {"value": 2}, {"value": 3}], calculate, 42)
	check(results == [{"value": 2}, {"value": 4}, {"value": 6}], "reverse completion preserves input order")
	coordinator.enabled = false
	check(coordinator.run_ordered("test", [{"value": 4}], calculate, 43) == [{"value": 8}], "disabled pool uses sequential fallback")
	coordinator.enabled = true
	var obsolete := coordinator.submit("test", {"value": 5, "delay_us": 10000}, calculate)
	coordinator.invalidate()
	check(coordinator.collect(obsolete, true).is_empty(), "generation change rejects result")
	var wrong_revision := coordinator.submit("test", {"value": 6}, calculate, 1, 1, {"topology": 4})
	check(coordinator.collect(wrong_revision, true, {"topology": 5}).is_empty(), "revision mismatch rejects result")
	var invalid := coordinator.submit("test", {"invalid": true}, calculate)
	check(coordinator.collect(invalid, true).is_empty(), "non-DTO worker result rejected")
	for index in range(Coordinator.MAX_PENDING):
		check(coordinator.submit("test", {"value": index, "delay_us": 10000}, calculate) >= 0, "bounded queue accepts slot")
	check(coordinator.submit("test", {"value": 99}, calculate) < 0, "queue overflow is explicit")
	coordinator.configure({"test": false})
	check(coordinator.pending.is_empty(), "reconfigure joins every task")
	check(coordinator.submit("test", {"value": 7}, calculate) < 0, "per-subsystem switch")
	coordinator.configure({})
	coordinator.submit("test", {"value": 8, "delay_us": 10000}, calculate)
	coordinator.shutdown()
	check(coordinator.pending.is_empty(), "shutdown joins and releases tasks")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
