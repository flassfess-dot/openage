class_name RoRTradeProfitPolicy
extends RefCounted

# The original executable owns the exact map-size-dependent distance curve.
# The route lifecycle must not depend on its eventual calibration, so the
# current bounded monotonic approximation is isolated behind this policy.
const POLICY_ID := "ror_distance_calibration_pending_v1"
const MEASUREMENT_MANIFEST := "res://data/parity/naval_executable_gate.json"
const MINIMUM_GOLD: int = 7
const MAXIMUM_GOLD: int = 75


static func profit_between(home: Vector2, target: Vector2, map_size: Vector2i) -> int:
	var diagonal := Vector2(maxi(1, map_size.x), maxi(1, map_size.y)).length()
	var normalized := clampf(home.distance_to(target) / diagonal, 0.0, 1.0)
	return clampi(roundi(lerpf(float(MINIMUM_GOLD), float(MAXIMUM_GOLD), normalized)), MINIMUM_GOLD, MAXIMUM_GOLD)


static func metadata() -> Dictionary:
	return {
		"id": POLICY_ID,
		"calibration_status": "measurement_pending",
		"measurement_manifest": MEASUREMENT_MANIFEST,
		"minimum_gold": MINIMUM_GOLD,
		"maximum_gold": MAXIMUM_GOLD,
	}
