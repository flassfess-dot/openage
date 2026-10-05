extends SceneTree

const Data := preload("res://scripts/isolated_task_data.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var topology := Data.seal({"cells": {Vector2i(4, 4): {"terrain": "grass"}}})
	var token: int = int(topology[Data.SEAL_KEY])
	for index in range(Data.MAX_SEALED_ROOTS * 3):
		check(Data.is_detached({"topology": topology}), "active topology stays detached")
		Data.seal({"transient_route": [Vector2(index, index + 1)]})
		check(Data.sealed_roots.has(token), "active topology remains registered after transient seal %d" % index)
		check(Data.sealed_roots.size() <= Data.MAX_SEALED_ROOTS, "registry stays bounded")

	# A copied marker does not identify the original readonly dictionary.
	var forged := {Data.SEAL_KEY: token, "nested": [RefCounted.new()]}
	forged.make_read_only()
	check(not Data.is_detached(forged), "marker cannot bypass nested Object rejection")
	var readonly_copy: Dictionary = topology.duplicate(true)
	readonly_copy.make_read_only()
	var resealed := Data.seal(readonly_copy)
	check(not is_same(resealed, topology) and int(resealed[Data.SEAL_KEY]) != token, "copied marker receives its own identity")

	# Inactive roots can be evicted without accepting forged mutable descendants.
	for index in range(Data.MAX_SEALED_ROOTS):
		Data.seal({"unused": index})
	check(not Data.sealed_roots.has(token), "inactive topology is evicted")
	var invalid_old := {Data.SEAL_KEY: token, "nested": [Callable(self, "check")]}
	invalid_old.make_read_only()
	check(not Data.is_detached(invalid_old), "evicted marker cannot bypass Callable rejection")
	check(Data.is_detached(topology), "evicted valid topology remains usable")
	for failure in failures:
		push_error(failure)
	print("Detached topology registry: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)
