extends SceneTree
const Publication := preload("res://scripts/presentation_publication.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var coordinator := Coordinator.new()
	coordinator.subsystem_enabled["presentation"] = true
	var publication := Publication.new()
	var source := {"tick": 10, "observer_team": 1, "units": [{"id": 1, "team": 1, "entity_type": "unit", "pos": Vector2(4, 5), "facing": 3, "components": {"worker": {"enabled": true}}, "command_options": {"build": [{"kind": "house"}]}}], "resources": [{"id": 2, "entity_type": "resource", "pos": Vector2(6, 7), "amount": 100}], "buildings": [], "fog": {"cells": PackedByteArray([2, 1, 0])}, "overview": {"units": [{"id": 1, "pos": Vector2(4, 5)}]}}
	var selected: Array[int] = [1]
	var request_before := coordinator.next_request_id
	var first := publication.publish(source, selected, coordinator)
	check(coordinator.next_request_id == request_before, "already projected publication never submits or waits for echo workers")
	source["units"][0]["pos"] = Vector2(9, 9)
	source["resources"][0]["amount"] = 0
	source["fog"]["cells"][0] = 0
	check(first["units"][0]["pos"] == Vector2(4, 5), "published units cannot follow live mutations")
	check(first["units"][0]["command_options"] == {"build": [{"kind": "house"}]}, "selected command model belongs to published tick")
	check(first["resources"][0]["amount"] == 100 and first["fog"]["cells"][0] == 2, "resources and fog are detached")
	source["tick"] = 11
	var second := publication.publish(source, selected, coordinator)
	check(second["tick"] == 11 and first["tick"] == 10, "buffer ownership protects prior publication")
	source["units"] = []
	var third := publication.publish(source, [], coordinator)
	check(third["units"].is_empty(), "removed units do not survive publication")
	check(third["resources"][0]["amount"] == 0 and first["resources"][0]["amount"] == 100, "slot reuse refreshes resources without mutating earlier publication")
	source["tick"] = 12
	source["resources"][0]["amount"] = 50
	var fourth := publication.publish(source, [], coordinator)
	check(fourth["resources"][0]["amount"] == 50 and second["resources"][0]["amount"] == 0, "both retained slots publish immutable resource records")
	coordinator.subsystem_enabled["presentation"] = false
	var direct := publication.publish(source, [], coordinator)
	check(is_same(direct, source), "standard retained snapshot bypasses copying and worker validation")
	coordinator.subsystem_enabled["presentation"] = true
	var arbitrary := {"id": 300, "environment_asset": "pine", "environment_variant": 2, "tree_condition": "healthy", "future_render_field": {"frames": PackedInt32Array([1, 2, 3])}}
	var captured := Publication.capture_entity(arbitrary, false)
	check(captured == arbitrary, "publication preserves the complete supplied render contract")
	arbitrary["future_render_field"]["frames"][0] = 9
	check(captured["future_render_field"]["frames"][0] == 1, "unknown nested render fields remain detached")
	coordinator.shutdown()
	publication.clear()
	check(publication.published_slot == -1, "load resets publication slots")
	finish()
