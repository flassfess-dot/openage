class_name RoRCacheDependency
extends RefCounted

const Journal := preload("res://scripts/cell_change_journal.gd")
const TERRAIN_GEOMETRY := "terrain_geometry"
const TERRAIN_SURFACE := "terrain_surface"
const NAVIGATION_TOPOLOGY := "navigation_topology"
const NAVIGATION_SURFACE := "navigation_surface"
const FOG_VISIBILITY := "fog_visibility"
const FOG_EXPLORATION := "fog_exploration"
const RESOURCE_MEMORY := "resource_memory"
const ENTITIES := "entities"

static func geometry_key(map_size: Vector2i, elevation) -> int:
	return hash([map_size, elevation.get_instance_id(), elevation.cache_epoch, elevation.revision])

static func stamp(world, domain: String, observer: int = 0) -> Dictionary:
	var owner = world
	var revision := -1
	var epoch := 0
	match domain:
		ENTITIES:
			owner = world.entity_changes
			owner.flush()
			revision = int(owner.revision)
			epoch = int(owner.epoch)
		TERRAIN_GEOMETRY:
			owner = world.terrain_elevation
			revision = int(owner.revision)
		TERRAIN_SURFACE:
			revision = int(world.terrain_revision)
		NAVIGATION_TOPOLOGY:
			owner = world.navigation_grid
			revision = int(owner.revision)
		NAVIGATION_SURFACE:
			owner = world.navigation_grid
			revision = int(owner.surface_revision)
		FOG_VISIBILITY:
			owner = world.get_fog_of_war()
			epoch = int(owner.cache_epoch)
			revision = int(owner.revision_for_player(observer))
		FOG_EXPLORATION:
			owner = world.get_fog_of_war()
			epoch = int(owner.cache_epoch)
			revision = int(owner.exploration_revision_for_player(observer))
		RESOURCE_MEMORY:
			revision = int(world.known_resource_revision(observer))
		_:
			assert(false, "Unknown cache dependency: " + domain)
	epoch = int(owner.epoch) if domain == ENTITIES else int(owner.cache_epoch)
	return {"domain": domain, "source_id": owner.get_instance_id(), "observer": observer, "epoch": epoch, "revision": revision}

static func changes(world, domain: String, previous: Variant, observer: int = 0) -> Dictionary:
	var current := stamp(world, domain, observer)
	var fallback := {"stamp": current, "revision": current["revision"], "full": true, "exact": false, "cells": [], "region": Rect2(), "ids": [], "masks": {}, "removed_ids": [], "reason": "source_or_epoch_changed"}
	var before := int(previous) if previous is int else -1
	if previous is Dictionary:
		if previous.get("domain") != domain or previous.get("source_id") != current["source_id"] or previous.get("epoch", -1) != current["epoch"] or int(previous.get("observer", 0)) != observer:
			return fallback
		before = int(previous.get("revision", -1))
	var delta: Dictionary
	match domain:
		ENTITIES:
			delta = world.entity_changes.changes_since(before)
		TERRAIN_SURFACE:
			delta = Journal.delta(world.terrain_change_history, before, int(current["revision"]))
		TERRAIN_GEOMETRY:
			delta = Journal.delta(world.terrain_elevation.change_history, before, int(current["revision"]))
		NAVIGATION_TOPOLOGY:
			delta = Journal.delta(world.navigation_grid._change_log, before, int(current["revision"]))
		FOG_VISIBILITY:
			delta = world.get_fog_of_war().visibility_changes_since(observer, before)
		FOG_EXPLORATION:
			delta = world.get_fog_of_war().exploration_changes_since(observer, before)
		_:
			delta = {"revision": current["revision"], "full": before != int(current["revision"]), "exact": before == int(current["revision"]), "cells": [], "region": Rect2()}
	delta["stamp"] = current
	return delta
