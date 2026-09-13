#!/usr/bin/env python3

"""Export the Rise of Rome logical sound table and concrete WAV variants."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import struct
import sys
import wave
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(SCRIPT_DIR))

from extract_graphics_catalog import find_drs_all, parse_drs  # noqa: E402
from openage.convert.service.read.gamedata import load_gamespec  # noqa: E402
from openage.convert.value_object.init.game_version import GameEdition, GameVersion  # noqa: E402


CACHE_SCHEMA_VERSION = 1
CATALOG_SCHEMA_VERSION = 1
IMPORTER_VERSION = "sound-catalog-3"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export RoR sounds, variants and event bindings.")
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--dat", type=Path)
    parser.add_argument("--objects", type=Path, required=True)
    parser.add_argument("--graphics", type=Path, required=True)
    parser.add_argument("--game-version", default="1.1")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def unwrap(value):
    if hasattr(value, "value"):
        return unwrap(value.value)
    if isinstance(value, dict):
        return {str(key): unwrap(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [unwrap(item) for item in value]
    return value


def wav_metadata(blob: bytes) -> dict[str, object]:
    if len(blob) < 12 or blob[:4] != b"RIFF" or blob[8:12] != b"WAVE":
        return {"valid": False, "error": "not a RIFF/WAVE resource"}
    try:
        with wave.open(io.BytesIO(blob), "rb") as stream:
            frames = stream.getnframes()
            rate = stream.getframerate()
            return {
                "valid": True,
                "channels": stream.getnchannels(),
                "sample_rate": rate,
                "sample_width_bits": stream.getsampwidth() * 8,
                "frame_count": frames,
                "duration_seconds": frames / rate if rate > 0 else 0.0,
            }
    except (wave.Error, EOFError):
        format_tag = None
        position = 12
        while position + 8 <= len(blob):
            chunk_type = blob[position:position + 4]
            chunk_size = struct.unpack_from("<I", blob, position + 4)[0]
            if chunk_type == b"fmt " and position + 10 <= len(blob):
                format_tag = struct.unpack_from("<H", blob, position + 8)[0]
                break
            position += 8 + chunk_size + (chunk_size & 1)
        return {"valid": True, "compressed": True, "format_tag": format_tag}


def event_bindings(objects: dict[str, object], graphics: dict[str, object]) -> dict[int, list[dict[str, object]]]:
    result: dict[int, list[dict[str, object]]] = {}

    def remember(sound_id, category: str, source: str, event: str) -> None:
        try:
            numeric = int(sound_id)
        except (TypeError, ValueError):
            return
        if numeric >= 0:
            result.setdefault(numeric, []).append({"category": category, "source": source, "event": event})

    category_for_event = {
        "selection": "voice_selection",
        "command": "voice_command",
        "train": "production",
        "death": "unit_death",
        "construction": "construction",
    }
    for object_key, record in objects.get("objects", {}).items():
        for event, sound_id in record.get("sounds", {}).items():
            remember(sound_id, category_for_event.get(event, "unit"), f"object {object_key}", event)
    for graphic_key, record in graphics.get("graphics", {}).items():
        sounds = record.get("sounds", {})
        remember(sounds.get("sound_id", -1), "graphic", f"graphic {graphic_key}", "play")
        for angle in sounds.get("attack", []):
            for event in angle.get("events", []):
                remember(event.get("sound_id", -1), "combat", f"graphic {graphic_key}", f"attack_angle_{angle.get('angle')}")
    return result


def cache_record(source_hashes: dict[str, object], game_version: str) -> dict[str, object]:
    components = {
        "sourceSha256": source_hashes,
        "importerVersion": IMPORTER_VERSION,
        "schemaVersion": CATALOG_SCHEMA_VERSION,
        "palette": {"id": "none", "sha256": "none"},
        "gameVersion": game_version,
    }
    encoded = json.dumps(components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"formatVersion": CACHE_SCHEMA_VERSION, "key": sha256_bytes(encoded), "components": components}


def main() -> int:
    args = parse_args()
    dat_path = args.dat or args.game / "data2" / "empires.dat"
    objects = json.loads(args.objects.read_text(encoding="utf-8"))
    graphics = json.loads(args.graphics.read_text(encoding="utf-8"))
    archive_paths = [path for name in ("sounds", "inter_up", "interfac") for path in find_drs_all(args.game, name)]
    source_hashes = {
        "empires_dat": sha256_bytes(dat_path.read_bytes()),
        "objects_catalog": sha256_bytes(args.objects.read_bytes()),
        "graphics_catalog": sha256_bytes(args.graphics.read_bytes()),
        "archives": {str(path.relative_to(args.game)).replace("\\", "/"): sha256_bytes(path.read_bytes()) for path in archive_paths},
    }
    cache = cache_record(source_hashes, args.game_version)
    if args.output.is_file():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if existing.get("cache", {}).get("key") == cache["key"]:
                print(f"sound catalog cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError):
            pass

    archives = {}
    for path in archive_paths:
        data, entries = parse_drs(path)
        archive_key = str(path.relative_to(args.game)).replace("\\", "/")
        archives[archive_key] = {"path": path, "data": data, "entries": entries}
    bindings = event_bindings(objects, graphics)
    game_version = GameVersion(GameEdition("Local Rise of Rome", "ROR", "YES", [], [], {}, [], []))
    with dat_path.open("rb") as dat_file:
        root = load_gamespec(dat_file, game_version).value[0]

    sounds = {}
    missing_audio = []
    for sound in root["sounds"].value:
        sound_id = int(sound["sound_id"].value)
        items = []
        for item in sound["sound_items"].value:
            values = unwrap(item)
            resource_id = int(values.get("resource_id", -1))
            source_drs = None
            audio = {"valid": False, "error": "WAV resource is missing"}
            for archive_name, archive in archives.items():
                location = archive["entries"].get(("wav", resource_id))
                if location is None:
                    continue
                offset, size = location
                source_drs = archive_name
                audio = wav_metadata(archive["data"][offset:offset + size])
                audio["byte_size"] = size
                break
            if source_drs is None and resource_id >= 0:
                missing_audio.append({"sound_id": sound_id, "resource_id": resource_id, "filename": values.get("filename", "")})
            items.append({
                "filename": values.get("filename", ""),
                "resource_id": resource_id,
                "probability": int(values.get("probablilty", 0)),
                "civilization_id": values.get("civilization_id"),
                "source_drs": source_drs,
                "audio": audio,
            })
        sound_bindings = bindings.get(sound_id, [])
        sounds[str(sound_id)] = {
            "sound_id": sound_id,
            "play_delay": int(sound["play_delay"].value),
            "volume": {"value": None, "source": "not stored in the RoR sound table"},
            "total_probability": sum(item["probability"] for item in items),
            "items": items,
            "categories": sorted(set(binding["category"] for binding in sound_bindings)),
            "event_bindings": sound_bindings,
        }
    unresolved_sound_ids = [
        {"sound_id": sound_id, "references": values}
        for sound_id, values in sorted(bindings.items())
        if str(sound_id) not in sounds
    ]
    payload = {
        "format_version": CATALOG_SCHEMA_VERSION,
        "cache": cache,
        "source": {
            "file": str(dat_path.relative_to(args.game)).replace("\\", "/"),
            "game_version": args.game_version,
            "dat_version": root["versionstr"].value,
            "archives": [str(path.relative_to(args.game)).replace("\\", "/") for path in archive_paths],
        },
        "sound_count": len(sounds),
        "sounds": sounds,
        "missing_audio": missing_audio,
        "unresolved_sound_ids": unresolved_sound_ids,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"exported {len(sounds)} logical sounds, {sum(len(sound['items']) for sound in sounds.values())} variants, "
        f"{len(missing_audio)} missing WAV to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
