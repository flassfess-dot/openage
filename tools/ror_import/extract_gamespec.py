#!/usr/bin/env python3

"""Export a small, runtime-friendly slice of Rise of Rome's Empires.dat."""

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
GAMESPEC_SCHEMA_VERSION = 4
IMPORTER_VERSION = "gamespec-5"


UNIT_IDS = {
    "archer": 4,
    "clubman": 73,
    "town_center": 109,
    "villager": 118,
}

ANIMATION_FIELDS = {
    "idle": "idle_graphic0",
    "move": "move_graphics",
    "attack": "attack_sprite_id",
    "death": "dying_graphic",
}

SOUND_FIELDS = {
    "selection": "selection_sound_id",
    "command": "command_sound_id",
    "train": "train_sound_id",
    "death": "dying_sound_id",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read owned RoR data once and export the prototype subset as JSON."
    )
    parser.add_argument("--game", type=Path, required=True, help="Rise of Rome install root")
    parser.add_argument("--dat", type=Path, help="Explicit Empires.dat path")
    parser.add_argument("--civ", type=int, default=13, help="Civilization index (13 = Romans)")
    parser.add_argument("--game-version", default="1.1", help="Installed Rise of Rome game version")
    parser.add_argument("--output", type=Path, required=True, help="Output JSON path")
    return parser.parse_args()


def make_cache_record(source_hash: str, game_version: str, civilization_index: int) -> dict[str, object]:
    components = {
        "sourceSha256": source_hash,
        "importerVersion": IMPORTER_VERSION,
        "schemaVersion": GAMESPEC_SCHEMA_VERSION,
        "palette": {"id": "none", "sha256": "none"},
        "gameVersion": game_version,
        "civilizationIndex": civilization_index,
    }
    encoded = json.dumps(components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "formatVersion": CACHE_SCHEMA_VERSION,
        "key": hashlib.sha256(encoded).hexdigest(),
        "components": components,
    }


def container_list(member) -> list[dict[str, object]]:
    return [
        {name: value.value for name, value in container.value.items()}
        for container in member.value
    ]


def graphic_info(graphic) -> dict[str, object]:
    return {
        "graphic_id": graphic["graphic_id"].value,
        "slp_id": graphic["slp_id"].value,
        "filename": graphic["filename"].value,
        "frames_per_angle": graphic["frame_count"].value,
        "angle_count": graphic["angle_count"].value,
        "frame_rate": graphic["frame_rate"].value,
        "replay_delay": graphic["replay_delay"].value,
        "mirroring_mode": graphic["mirroring_mode"].value,
        "layer": graphic["layer"].value,
        "deltas": container_list(graphic["graphic_deltas"]),
    }


def sound_info(sound) -> dict[str, object]:
    return {
        "sound_id": sound["sound_id"].value,
        "play_delay": sound["play_delay"].value,
        "items": container_list(sound["sound_items"]),
    }


def unit_info(unit, graphics: dict[int, object], sounds: dict[int, object]) -> dict[str, object]:
    animations = {}
    for name, member_name in ANIMATION_FIELDS.items():
        graphic_id = unit[member_name].value if member_name in unit.value else -1
        if graphic_id in graphics:
            animations[name] = graphic_info(graphics[graphic_id])

    projectile_id = unit["projectile_id0"].value if "projectile_id0" in unit.value else -1
    frame_delay = unit["frame_delay"].value if "frame_delay" in unit.value else 0
    if "attack" in animations:
        event_name = "projectile_release_frame" if projectile_id >= 0 else "damage_frame"
        animations["attack"][event_name] = frame_delay

    result = {
        "unit_id": unit["id0"].value,
        "unit_type": unit["unit_type"].value,
        "hit_points": unit["hit_points"].value,
        "line_of_sight": unit["line_of_sight"].value,
        "speed": unit["speed"].value,
        "terrain_restriction": unit["terrain_restriction"].value,
        "selection_radius": [
            unit["selection_shape_x"].value,
            unit["selection_shape_y"].value,
            unit["selection_shape_z"].value,
        ],
        "attack_period": unit["attack_speed"].value if "attack_speed" in unit.value else 0.0,
        "range": unit["weapon_range_max"].value if "weapon_range_max" in unit.value else 0.0,
        "accuracy": unit["accuracy"].value if "accuracy" in unit.value else 0,
        "weapon_offset": [value.value for value in unit["weapon_offset"].value] if "weapon_offset" in unit.value else [0.0, 0.0, 0.0],
        "projectile_id": projectile_id,
        "attack_frame_delay": frame_delay,
        "creation_time": unit["creation_time"].value if "creation_time" in unit.value else 0,
        "attacks": container_list(unit["attacks"]) if "attacks" in unit.value else [],
        "armors": container_list(unit["armors"]) if "armors" in unit.value else [],
        "resource_cost": container_list(unit["resource_cost"]) if "resource_cost" in unit.value else [],
        "sounds": {},
        "animations": animations,
    }
    for name, member_name in SOUND_FIELDS.items():
        sound_id = unit[member_name].value if member_name in unit.value else -1
        if sound_id in sounds:
            result["sounds"][name] = sound_info(sounds[sound_id])
    return result


def referenced_graphics(units: dict[str, object], graphics: dict[int, object]) -> dict[str, object]:
    pending = [
        animation["graphic_id"]
        for unit in units.values()
        for animation in unit["animations"].values()
    ]
    result: dict[str, object] = {}
    while pending:
        graphic_id = pending.pop()
        key = str(graphic_id)
        if graphic_id < 0 or key in result or graphic_id not in graphics:
            continue
        info = graphic_info(graphics[graphic_id])
        result[key] = info
        pending.extend(
            delta["graphic_id"]
            for delta in info["deltas"]
            if delta["graphic_id"] >= 0
        )
    return result


def main() -> int:
    args = parse_args()
    dat_path = args.dat or args.game / "data2" / "empires.dat"
    if not dat_path.is_file():
        raise FileNotFoundError(f"Rise of Rome data file not found: {dat_path}")

    source_hash = hashlib.sha256(dat_path.read_bytes()).hexdigest()
    cache = make_cache_record(source_hash, args.game_version, args.civ)
    if args.output.is_file():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if existing.get("cache", {}).get("key") == cache["key"]:
                print(f"gamespec cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError):
            pass

    game_version = GameVersion(
        GameEdition("Local Rise of Rome", "ROR", "YES", [], [], {}, [], [])
    )
    with dat_path.open("rb") as dat_file:
        root = load_gamespec(dat_file, game_version).value[0]

    if not 0 <= args.civ < len(root["civs"].value):
        raise ValueError(f"civilization index {args.civ} is unavailable")

    graphics = {
        graphic["graphic_id"].value: graphic
        for graphic in root["graphics"].value
    }
    sounds = {sound["sound_id"].value: sound for sound in root["sounds"].value}
    civ = root["civs"].value[args.civ]
    units = {unit["id0"].value: unit for unit in civ["units"].value}

    missing = [unit_id for unit_id in UNIT_IDS.values() if unit_id not in units]
    if missing:
        raise ValueError(f"required unit IDs are absent: {missing}")

    unit_payload = {
        name: unit_info(units[unit_id], graphics, sounds)
        for name, unit_id in UNIT_IDS.items()
    }
    payload = {
        "format_version": GAMESPEC_SCHEMA_VERSION,
        "cache": cache,
        "source": {
            "file": str(dat_path.relative_to(args.game)).replace("\\", "/"),
            "size": dat_path.stat().st_size,
            "sha256": source_hash,
            "game_version": args.game_version,
            "version": root["versionstr"].value,
        },
        "civilization_index": args.civ,
        "civilization_count": len(root["civs"].value),
        "graphic_count": len(root["graphics"].value),
        "terrain_count": len(root["terrains"].value),
        "units": unit_payload,
        "graphics": referenced_graphics(unit_payload, graphics),
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"exported RoR {payload['source']['version']} data for "
        f"{len(payload['units'])} prototype entities to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
