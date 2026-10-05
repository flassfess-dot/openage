class_name RoRPathBatchTask
extends RefCounted

var planner

func run(input: Dictionary) -> Dictionary:
	var before: Dictionary = {}
	for category in ["world", "cells", "smooth"]:
		before[category] = planner._geometry_bucket(category).duplicate()
	var paths: Array = []
	for request in input["requests"]:
		paths.append(planner.find_path(request["start"], request["goal"], String(request["domain"]), int(request["restriction"]), float(request["clearance"])))
	var deltas: Dictionary = {}
	var geometry: Dictionary = {}
	for category in ["world", "cells", "smooth"]:
		var added: Dictionary = {}
		var metadata: Dictionary = {}
		var bucket: Dictionary = planner._geometry_bucket(category)
		for key in bucket:
			if not before[category].has(key):
				added[key] = bucket[key]
				metadata[key] = planner.geometry_metadata[category][key]
		deltas[category] = added
		geometry[category] = metadata
	var samples: Dictionary = planner.performance_probe.samples_by_metric.duplicate(true) if planner.performance_probe != null else {}
	var counters: Dictionary = planner.performance_probe.counters.duplicate() if planner.performance_probe != null else {}
	return {"paths": paths, "cache": deltas["world"], "cells": deltas["cells"], "smoothed": deltas["smooth"], "geometry": geometry, "hits": planner.cache_hits, "samples": samples, "counters": counters}
