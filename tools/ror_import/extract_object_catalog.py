#!/usr/bin/env python3

"""Export Rise of Rome objects, civilizations and technology rules."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from openage.convert.service.read.gamedata import load_gamespec  # noqa: E402
from openage.convert.value_object.init.game_version import (  # noqa: E402
    GameEdition,
    GameVersion,
)


CACHE_SCHEMA_VERSION = 1
CATALOG_SCHEMA_VERSION = 2
IMPORTER_VERSION = "object-catalog-5"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export complete RoR object and rules catalog.")
    parser.add_argument("--game", type=Path, required=True, help="Rise of Rome install root")
    parser.add_argument("--dat", type=Path, help="Explicit Empires.dat path")
    parser.add_argument("--game-version", default="1.1", help="Installed Rise of Rome game version")
    parser.add_argument("--output", type=Path, required=True, help="Output objects-catalog.json")
    return parser.parse_args()


def unwrap(value):
    if hasattr(value, "value"):
        return unwrap(value.value)
    if isinstance(value, dict):
        return {str(key): unwrap(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [unwrap(item) for item in value]
    return value


def field(container, name: str, default=None):
    if name not in container.value:
        return default
    return unwrap(container[name])


def records(container, name: str) -> list[dict[str, object]]:
    if name not in container.value:
        return []
    result = unwrap(container[name])
    return result if isinstance(result, list) else []


def cache_record(source_hash: str, game_version: str) -> dict[str, object]:
    components = {
        "sourceSha256": source_hash,
        "importerVersion": IMPORTER_VERSION,
        "schemaVersion": CATALOG_SCHEMA_VERSION,
        "palette": {"id": "none", "sha256": "none"},
        "gameVersion": game_version,
    }
    encoded = json.dumps(components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "formatVersion": CACHE_SCHEMA_VERSION,
        "key": hashlib.sha256(encoded).hexdigest(),
        "components": components,
    }


def unit_record(unit, civilization_id: int) -> dict[str, object]:
    unit_type = int(field(unit, "unit_type", -1))
    storage = records(unit, "resource_storage")
    return {
        "key": f"{civilization_id}:{int(field(unit, 'id0', -1))}",
        "civilization_id": civilization_id,
        "unit_id": int(field(unit, "id0", -1)),
        "unit_type": unit_type,
        "unit_class": int(field(unit, "unit_class", -1)),
        "enabled": bool(field(unit, "enabled", True)),
        "language": {
            "name_id": int(field(unit, "language_dll_name", -1)),
        },
        "interface": {
            "icon_id": int(field(unit, "icon_id", -1)),
            "button_id": int(field(unit, "creation_button_id", -1)),
        },
        "health": float(field(unit, "hit_points", 0.0)),
        "line_of_sight": float(field(unit, "line_of_sight", 0.0)),
        "speed": float(field(unit, "speed", 0.0)),
        "turn_speed": float(field(unit, "turn_speed", 0.0)),
        "work_rate": float(field(unit, "work_rate", 0.0)),
        "geometry": {
            "radius": [float(field(unit, "radius_x", 0.0)), float(field(unit, "radius_y", 0.0)), float(field(unit, "radius_z", 0.0))],
            "selection": [float(field(unit, "selection_shape_x", 0.0)), float(field(unit, "selection_shape_y", 0.0)), float(field(unit, "selection_shape_z", 0.0))],
            "clearance": [float(field(unit, "clearance_size_x", 0.0)), float(field(unit, "clearance_size_y", 0.0))],
            "obstruction_type": int(field(unit, "obstruction_type", 2)),
        },
        "graphics": {
            "idle": int(field(unit, "idle_graphic0", -1)),
            "move": int(field(unit, "move_graphics", -1)),
            "attack": int(field(unit, "attack_sprite_id", -1)),
            "death": int(field(unit, "dying_graphic", -1)),
            "construction": int(field(unit, "construction_graphic_id", -1)),
            "damage": records(unit, "damage_graphics"),
        },
        "sounds": {
            "selection": int(field(unit, "selection_sound_id", -1)),
            "command": int(field(unit, "command_sound_id", -1)),
            "train": int(field(unit, "train_sound_id", -1)),
            "death": int(field(unit, "dying_sound_id", -1)),
            "construction": int(field(unit, "construction_sound_id", -1)),
        },
        "combat": {
            "attack_period": float(field(unit, "attack_speed", 0.0)),
            "range_min": float(field(unit, "weapon_range_min", 0.0)),
            "range_max": float(field(unit, "weapon_range_max", 0.0)),
            "blast_range": float(field(unit, "blast_range", 0.0)),
            "accuracy": int(field(unit, "accuracy", 0)),
            "projectile_id": int(field(unit, "projectile_id0", -1)),
            "frame_delay": int(field(unit, "frame_delay", 0)),
            "weapon_offset": [float(value) for value in field(unit, "weapon_offset", [0.0, 0.0, 0.0])],
            "attacks": records(unit, "attacks"),
            "armors": records(unit, "armors"),
        },
        "projectile": {
            "type": int(field(unit, "projectile_type", 0)),
            "smart_mode": bool(field(unit, "smart_mode", False)),
            "drop_animation_mode": int(field(unit, "drop_animation_mode", 0)),
            "penetration_mode": int(field(unit, "penetration_mode", 0)),
            "area_of_effect_special": int(field(unit, "area_of_effect_special", 0)),
            "arc": float(field(unit, "projectile_arc", 0.0)),
        },
        "resources": {
            "capacity": float(field(unit, "resource_capacity", 0.0)),
            "decay": float(field(unit, "resource_decay", 0.0)),
            "storage": storage,
            "cost": records(unit, "resource_cost"),
            "drop_site_ids": field(unit, "drop_sites", []),
        },
        "production": {
            "creation_time": int(field(unit, "creation_time", 0)),
            "train_location_id": int(field(unit, "train_location_id", -1)),
            "research_id": int(field(unit, "research_id", -1)),
        },
        "commands": records(unit, "unit_commands"),
        "links": {
            "dead_unit_id": int(field(unit, "dead_unit_id", -1)),
            "stack_unit_id": int(field(unit, "stack_unit_id", -1)),
            "terrain_restriction": int(field(unit, "terrain_restriction", -1)),
            "foundation_terrain_id": int(field(unit, "foundation_terrain_id", -1)),
            "task_group": int(field(unit, "task_group", -1)),
        },
    }


def main() -> int:
    args = parse_args()
    dat_path = args.dat or args.game / "data2" / "empires.dat"
    if not dat_path.is_file():
        raise FileNotFoundError(f"Rise of Rome data file not found: {dat_path}")
    source_hash = hashlib.sha256(dat_path.read_bytes()).hexdigest()
    cache = cache_record(source_hash, args.game_version)
    if args.output.is_file():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if existing.get("cache", {}).get("key") == cache["key"]:
                print(f"object catalog cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError):
            pass

    game_version = GameVersion(GameEdition("Local Rise of Rome", "ROR", "YES", [], [], {}, [], []))
    with dat_path.open("rb") as dat_file:
        root = load_gamespec(dat_file, game_version).value[0]

    civilizations = []
    objects: dict[str, object] = {}
    building_keys = []
    resource_object_keys = []
    unit_commands: dict[str, object] = {}
    for civilization_id, civilization in enumerate(root["civs"].value):
        object_keys = []
        for unit in civilization["units"].value:
            record = unit_record(unit, civilization_id)
            key = record["key"]
            objects[key] = record
            object_keys.append(key)
            if record["unit_type"] >= 80:
                building_keys.append(key)
            has_stored_resource = any(float(item.get("amount", 0.0)) != 0.0 for item in record["resources"]["storage"])
            if has_stored_resource or record["resources"]["capacity"] > 0.0:
                resource_object_keys.append(key)
            if record["commands"]:
                unit_commands[key] = record["commands"]
        civilizations.append({
            "civilization_id": civilization_id,
            "tech_tree_id": int(field(civilization, "tech_tree_id", -1)),
            "icon_set": int(field(civilization, "icon_set", -1)),
            "resources": field(civilization, "resources", []),
            "object_keys": object_keys,
        })

    technologies = {}
    for technology_id, research in enumerate(root["researches"].value):
        technologies[str(technology_id)] = {
            "technology_id": technology_id,
            "language": {
                "name_id": int(field(research, "language_dll_name", -1)),
                "description_id": int(field(research, "language_dll_description", -1)),
                "tech_tree_id": int(field(research, "language_dll_techtree", -1)),
            },
            "required_technology_count": int(field(research, "required_tech_count", 0)),
            "required_technology_ids": field(research, "required_techs", []),
            "research_location_id": int(field(research, "research_location_id", -1)),
            "research_time": int(field(research, "research_time", 0)),
            "resource_costs": records(research, "research_resource_costs"),
            "effect_bundle_id": int(field(research, "tech_effect_id", -1)),
            "icon_id": int(field(research, "icon_id", -1)),
            "button_id": int(field(research, "button_id", -1)),
            "hotkey": int(field(research, "hotkey", -1)),
            "technology_type": int(field(research, "tech_type", -1)),
        }

    effect_bundles = {}
    effect_commands = {}
    for bundle_id, bundle in enumerate(root["effect_bundles"].value):
        commands = records(bundle, "effects")
        effect_bundles[str(bundle_id)] = {"effect_bundle_id": bundle_id, "commands": commands}
        if commands:
            effect_commands[str(bundle_id)] = commands

    payload = {
        "format_version": CATALOG_SCHEMA_VERSION,
        "cache": cache,
        "source": {
            "file": str(dat_path.relative_to(args.game)).replace("\\", "/"),
            "sha256": source_hash,
            "game_version": args.game_version,
            "dat_version": root["versionstr"].value,
        },
        "counts": {
            "civilizations": len(civilizations),
            "objects": len(objects),
            "buildings": len(building_keys),
            "resource_objects": len(resource_object_keys),
            "technologies": len(technologies),
            "effect_bundles": len(effect_bundles),
        },
        "civilizations": civilizations,
        "objects": objects,
        "building_keys": building_keys,
        "resource_object_keys": resource_object_keys,
        "technologies": technologies,
        "effect_bundles": effect_bundles,
        "commands": {
            "unit": unit_commands,
            "technology_effect": effect_commands,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"exported {len(objects)} objects, {len(technologies)} technologies and "
        f"{len(effect_bundles)} effect bundles to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
