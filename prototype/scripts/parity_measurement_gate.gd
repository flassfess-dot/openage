class_name RoRParityMeasurementGate
extends RefCounted


static func load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func validation_issues(manifest: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if int(manifest.get("schema_version", 0)) != 1:
		issues.append("schema_version must be 1")
	if String(manifest.get("gate_id", "")).is_empty():
		issues.append("gate_id is required")
	var reference: Dictionary = manifest.get("reference_build", {})
	for field in ["executable_sha256", "data_sha256"]:
		if not _is_sha256(String(reference.get(field, ""))):
			issues.append("reference_build.%s must be a SHA-256 digest" % field)

	var seen_scene_ids: Dictionary = {}
	for scene_value in manifest.get("scenes", []):
		if not scene_value is Dictionary:
			issues.append("scene entries must be dictionaries")
			continue
		var scene: Dictionary = scene_value
		var scene_id := String(scene.get("id", ""))
		if scene_id.is_empty():
			issues.append("scene id is required")
		elif seen_scene_ids.has(scene_id):
			issues.append("duplicate scene id: %s" % scene_id)
		seen_scene_ids[scene_id] = true
		var source_ids: Array = scene.get("source_ids", scene.get("source_unit_ids", []))
		if source_ids.is_empty():
			issues.append("%s must name source_ids or source_unit_ids" % scene_id)
		if scene.get("required_metrics", []).is_empty():
			issues.append("%s must name required_metrics" % scene_id)
		for evidence_value in scene.get("modern_evidence", []):
			var evidence := String(evidence_value)
			if not FileAccess.file_exists(evidence):
				issues.append("%s modern evidence is missing: %s" % [scene_id, evidence])
		_validate_observation(scene_id, scene.get("original_observation", {}), issues)

	if manifest.has("trade_profit"):
		var trade: Dictionary = manifest.get("trade_profit", {})
		if String(trade.get("policy_id", "")).is_empty():
			issues.append("trade_profit.policy_id is required")
		if int(trade.get("required_map_count", 0)) < 3:
			issues.append("trade_profit requires at least three map sizes")
		if trade.get("required_fields", []).is_empty():
			issues.append("trade_profit.required_fields is empty")
		if String(trade.get("status", "")) == "measured" and trade.get("observations", []).is_empty():
			issues.append("measured trade_profit requires observations")
	return issues


static func unresolved_requirements(manifest: Dictionary) -> Array[String]:
	var unresolved: Array[String] = []
	for scene_value in manifest.get("scenes", []):
		if not scene_value is Dictionary:
			continue
		var scene: Dictionary = scene_value
		var observation: Dictionary = scene.get("original_observation", {})
		if String(observation.get("status", "pending")) != "captured":
			unresolved.append("original_capture:%s" % String(scene.get("id", "unnamed")))
	if manifest.has("trade_profit"):
		var trade: Dictionary = manifest.get("trade_profit", {})
		if String(trade.get("status", "measurement_pending")) != "measured":
			unresolved.append("trade_profit_measurement")
	for gap_value in manifest.get("source_owned_gaps", []):
		if not bool(gap_value.get("accepted", false)):
			unresolved.append("source_gap_disposition:%s" % String(gap_value.get("id", "unnamed")))
	return unresolved


static func can_claim_parity(manifest: Dictionary) -> bool:
	return String(manifest.get("status", "")) == "measured" \
		and validation_issues(manifest).is_empty() \
		and unresolved_requirements(manifest).is_empty()


static func _validate_observation(scene_id: String, observation: Dictionary, issues: Array[String]) -> void:
	var status := String(observation.get("status", "pending"))
	if status not in ["pending", "captured"]:
		issues.append("%s original observation has invalid status" % scene_id)
		return
	if status != "captured":
		return
	var artifacts: Array = observation.get("artifacts", [])
	var metrics: Dictionary = observation.get("metrics", {})
	if artifacts.is_empty():
		issues.append("%s captured observation has no artifacts" % scene_id)
	for artifact_value in artifacts:
		if not artifact_value is Dictionary:
			issues.append("%s observation artifact must be a dictionary" % scene_id)
			continue
		var artifact: Dictionary = artifact_value
		var path := String(artifact.get("path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			issues.append("%s observation artifact is missing: %s" % [scene_id, path])
		if not _is_sha256(String(artifact.get("sha256", ""))):
			issues.append("%s observation artifact has no valid SHA-256" % scene_id)
	if metrics.is_empty():
		issues.append("%s captured observation has no metrics" % scene_id)


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	var lowered := value.to_lower()
	for index in range(lowered.length()):
		if "0123456789abcdef".find(lowered.substr(index, 1)) < 0:
			return false
	return true
