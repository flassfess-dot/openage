class_name RoRNativeMovementTask
extends RefCounted

# A private context retains immutable terrain and neighbor generations.
# Results can be polled or discarded while the owner continues its unit loop.
var kernel

func run(input: Dictionary) -> Dictionary:
	var results: Array = []
	for request in input["requests"]:
		results.append(kernel.calculate_movement(int(request["id"]), request["target"], float(request["speed"]), float(request["scale"]), float(request["delta"])))
	return {"results": results}
