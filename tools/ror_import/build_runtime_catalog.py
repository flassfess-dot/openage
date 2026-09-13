#!/usr/bin/env python3

"""Build the small normalized runtime catalog from complete generated RoR catalogs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


SCHEMA_VERSION = 1
IMPORTER_VERSION = "runtime-catalog-3"
ANIMATION_FIELDS = ("idle", "move", "attack", "death", "construction")
SOUND_FIELDS = ("selection", "command", "train", "death", "construction")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a normalized RoR runtime catalog.")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--objects", type=Path, required=True)
    parser.add_argument("--graphics", type=Path, required=True)
    parser.add_argument("--sounds", type=Path, required=True)
    parser.add_argument("--localization", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cache_record(paths: dict[str, Path]) -> dict[str, object]:
    source_hashes = {name: file_hash(path) for name, path in sorted(paths.items())}
    components = {
        "sourceSha256": source_hashes,
        "importerVersion": IMPORTER_VERSION,
        "schemaVersion": SCHEMA_VERSION,
        "palette": {"id": "none", "sha256": "none"},
        "gameVersion": "1.1",
    }
    encoded = json.dumps(components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"formatVersion": 1, "key": hashlib.sha256(encoded).hexdigest(), "components": components}


def graphic_descriptor(graphic_id: int, graphics: dict[str, object]) -> dict[str, object]:
    if graphic_id < 0:
        return {"graphic_id": -1, "available": False}
    source = graphics.get(str(graphic_id), {})
    slp = source.get("slp", {})
    return {
        "graphic_id": graphic_id,
        "slp_id": int(source.get("slp_id", -1)),
        "available": bool(slp.get("valid", False)),
        "frames_per_angle": int(source.get("frames_per_angle", 0)),
        "angle_count": int(source.get("angle_count", 0)),
        "frame_rate": float(source.get("frame_rate", 0.0)),
        "replay_delay": float(source.get("replay_delay", 0.0)),
        "mirroring_mode": int(source.get("mirroring_mode", 0)),
        "layer": int(source.get("layer", 0)),
        "frame_count": int(slp.get("frame_count", 0)),
    }


def sound_descriptor(sound_id: int, sounds: dict[str, object]) -> dict[str, object]:
    if sound_id < 0:
        return {"sound_id": -1, "available": False, "valid_variant_count": 0}
    source = sounds.get(str(sound_id), {})
    valid_variants = [item for item in source.get("items", []) if item.get("audio", {}).get("valid", False)]
    return {
        "sound_id": sound_id,
        "available": bool(valid_variants),
        "valid_variant_count": len(valid_variants),
        "play_delay": int(source.get("play_delay", 0)),
    }


def normalize_record(
    source: dict[str, object],
    graphics: dict[str, object],
    sounds: dict[str, object],
    fallback_strings: dict[str, object],
) -> dict[str, object]:
    combat = source.get("combat", {})
    resources = source.get("resources", {})
    production = source.get("production", {})
    language = source.get("language", {})
    interface = source.get("interface", {})
    name_id = int(language.get("name_id", -1))
    animations = {
        field: graphic_descriptor(int(source.get("graphics", {}).get(field, -1)), graphics)
        for field in ANIMATION_FIELDS
    }
    sound_events = {
        field: sound_descriptor(int(source.get("sounds", {}).get(field, -1)), sounds)
        for field in SOUND_FIELDS
    }
    return {
        "source_key": str(source.get("key", "")),
        "civilization_id": int(source.get("civilization_id", 0)),
        "enabled_at_start": bool(source.get("enabled", False)),
        "simulation": {
            "unit_id": int(source.get("unit_id", -1)),
            "unit_type": int(source.get("unit_type", -1)),
            "unit_class": int(source.get("unit_class", -1)),
            "hit_points": float(source.get("health", 0.0)),
            "line_of_sight": float(source.get("line_of_sight", 0.0)),
            "speed": float(source.get("speed", 0.0)),
            "turn_speed": float(source.get("turn_speed", 0.0)),
            "work_rate": float(source.get("work_rate", 0.0)),
            "terrain_restriction": int(source.get("links", {}).get("terrain_restriction", -1)),
            "obstruction_type": int(source.get("geometry", {}).get("obstruction_type", 2)),
            "selection_radius": source.get("geometry", {}).get("selection", []),
            "attack_period": float(combat.get("attack_period", 0.0)),
            "range_min": float(combat.get("range_min", 0.0)),
            "range": float(combat.get("range_max", 0.0)),
            "blast_range": float(combat.get("blast_range", 0.0)),
            "accuracy": int(combat.get("accuracy", 0)),
            "weapon_offset": combat.get("weapon_offset", [0.0, 0.0, 0.0]),
            "projectile_id": int(combat.get("projectile_id", -1)),
            "attack_frame_delay": int(combat.get("frame_delay", 0)),
            "creation_time": int(production.get("creation_time", 0)),
            "attacks": combat.get("attacks", []),
            "armors": combat.get("armors", []),
            "resource_capacity": float(resources.get("capacity", 0.0)),
            "resource_cost": resources.get("cost", []),
            "animations": animations,
            "sounds": sound_events,
        },
        "presentation": {
            "name_id": name_id,
            "fallback_name": str(fallback_strings.get(str(name_id), "")),
            "icon_id": int(interface.get("icon_id", -1)),
            "button_id": int(interface.get("button_id", -1)),
            "graphics": animations,
            "sounds": sound_events,
        },
        "relationships": {
            "dead_unit_id": int(source.get("links", {}).get("dead_unit_id", -1)),
            "stack_unit_id": int(source.get("links", {}).get("stack_unit_id", -1)),
            "projectile_unit_id": int(combat.get("projectile_id", -1)),
            "train_location_unit_id": int(production.get("train_location_id", -1)),
            "research_id": int(production.get("research_id", -1)),
        },
    }


def build_catalog(manifest, objects_catalog, graphics_catalog, sound_catalog, localization_catalog, cache):
    objects = objects_catalog.get("objects", {})
    graphics = graphics_catalog.get("graphics", {})
    sounds = sound_catalog.get("sounds", {})
    fallback_language = str(localization_catalog.get("fallback_language", "en"))
    fallback_strings = localization_catalog.get("languages", {}).get(fallback_language, {}).get("strings", {})
    default_civilization_id = int(manifest.get("default_civilization_id", 13))
    archetypes: dict[str, object] = {}
    internal_ids: set[str] = set()
    presentation_ids: set[str] = set()

    for definition in manifest.get("archetypes", []):
        alias = str(definition.get("alias", ""))
        internal_id = str(definition.get("internal_id", ""))
        presentation_id = str(definition.get("presentation_id", ""))
        source_unit_id = int(definition.get("source_unit_id", -1))
        scope = str(definition.get("civilization_scope", "team"))
        if not alias or not internal_id or not presentation_id or source_unit_id < 0:
            raise ValueError(f"invalid runtime archetype: {definition}")
        if alias in archetypes or internal_id in internal_ids or presentation_id in presentation_ids:
            raise ValueError(f"duplicate runtime identifier for archetype {alias}")
        internal_ids.add(internal_id)
        presentation_ids.add(presentation_id)
        candidate_records = {
            key.split(":", 1)[0]: normalize_record(record, graphics, sounds, fallback_strings)
            for key, record in objects.items()
            if int(record.get("unit_id", -1)) == source_unit_id
            and (scope == "team" or int(record.get("civilization_id", -1)) == 0)
        }
        if not candidate_records:
            raise ValueError(f"source unit {source_unit_id} for {alias} is absent")
        archetypes[alias] = {
            "identifiers": {
                "internal_id": internal_id,
                "source_unit_id": source_unit_id,
                "presentation_id": presentation_id,
            },
            "category": str(definition.get("category", "unit")),
            "civilization_scope": scope,
            "default_civilization_id": 0 if scope == "gaia" else default_civilization_id,
            "behavior_tags": sorted(set(str(tag) for tag in definition.get("behavior_tags", []))),
            "runtime": definition.get("runtime", {}),
            "records": candidate_records,
        }

    return {
        "format_version": SCHEMA_VERSION,
        "cache": cache,
        "default_civilization_id": default_civilization_id,
        "archetype_count": len(archetypes),
        "archetypes": archetypes,
    }


def main() -> int:
    args = parse_args()
    paths = {
        "manifest": args.manifest,
        "objects": args.objects,
        "graphics": args.graphics,
        "sounds": args.sounds,
        "localization": args.localization,
    }
    cache = cache_record(paths)
    if args.output.is_file():
        try:
            existing = read_json(args.output)
            if existing.get("cache", {}).get("key") == cache["key"]:
                print(f"runtime catalog cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError):
            pass
    catalog = build_catalog(
        read_json(args.manifest),
        read_json(args.objects),
        read_json(args.graphics),
        read_json(args.sounds),
        read_json(args.localization),
        cache,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"exported {catalog['archetype_count']} normalized runtime archetypes to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
