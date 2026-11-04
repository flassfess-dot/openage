extends RefCounted
const Current := preload("res://scripts/ai_player.gd")
const Baseline := preload("res://scripts/ai_arena_opponent.gd")

static func create(definition: Dictionary):
	var version:=String(definition.get("ai", {}).get("algorithm_version", "legacy_adaptive_v1"))
	if version == "baseline_v1":
		return Baseline.new(definition)
	if version not in ["legacy_adaptive_v1","competitive_v2"]: return null
	return Current.new(definition)
