class_name RoRNativeMovementTask
extends RefCounted

# The owner configures the numeric native snapshot before dispatch and joins
# every job before any subsequent configure/update. Native scratch is thread-local.
var kernel

func run(input: Dictionary) -> Dictionary:
	var results: Array = []
	for request in input["requests"]:
		results.append(kernel.calculate_movement(int(request["id"]), request["target"], float(request["speed"]), float(request["scale"]), float(request["delta"])))
	return {"results": results}
