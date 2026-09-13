#!/usr/bin/env python3

"""Export a complete Rise of Rome graphic catalog from owned local data."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
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
CATALOG_SCHEMA_VERSION = 1
IMPORTER_VERSION = "graphics-catalog-3"
ARCHIVE_NAMES = ("graphics", "inter_up", "interfac", "terrain", "border")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export all RoR Graphic records and SLP frame geometry.")
    parser.add_argument("--game", type=Path, required=True, help="Rise of Rome install root")
    parser.add_argument("--dat", type=Path, help="Explicit Empires.dat path")
    parser.add_argument("--game-version", default="1.1", help="Installed Rise of Rome game version")
    parser.add_argument("--output", type=Path, required=True, help="Output graphics-catalog.json")
    return parser.parse_args()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def find_drs(game_root: Path, name: str) -> Path | None:
    paths = find_drs_all(game_root, name)
    return paths[0] if paths else None


def find_drs_all(game_root: Path, name: str) -> list[Path]:
    wanted = f"{name}.drs"
    result = []
    for folder_name in ("data2", "data"):
        folder = game_root / folder_name
        if not folder.is_dir():
            continue
        for candidate in folder.iterdir():
            if candidate.name.lower() == wanted:
                result.append(candidate)
                break
    return result


def parse_drs(path: Path) -> tuple[bytes, dict[tuple[str, int], tuple[int, int]]]:
    data = path.read_bytes()
    if len(data) < 64:
        raise ValueError(f"DRS archive is too small: {path}")
    table_count = struct.unpack_from("<i", data, 56)[0]
    entries: dict[tuple[str, int], tuple[int, int]] = {}
    for table_index in range(table_count):
        table_position = 64 + table_index * 12
        extension = data[table_position:table_position + 4][::-1].decode("latin1").strip().lower()
        table_offset, file_count = struct.unpack_from("<ii", data, table_position + 4)
        for index in range(file_count):
            entry_position = table_offset + index * 12
            resource_id, offset, size = struct.unpack_from("<iii", data, entry_position)
            entries[(extension, resource_id)] = (offset, size)
    return data, entries


def slp_frame_geometry(blob: bytes) -> dict[str, object]:
    if len(blob) < 32:
        return {"valid": False, "error": "SLP is smaller than its header", "frames": []}
    version = blob[0:4].decode("latin1", errors="replace")
    frame_count = struct.unpack_from("<i", blob, 4)[0]
    if frame_count <= 0 or 32 + frame_count * 32 > len(blob):
        return {"valid": False, "version": version, "error": f"invalid frame count {frame_count}", "frames": []}
    frames = []
    for index in range(frame_count):
        header = 32 + index * 32
        palette_offset = struct.unpack_from("<I", blob, header + 8)[0]
        width, height, hotspot_x, hotspot_y = struct.unpack_from("<iiii", blob, header + 16)
        frames.append({
            "index": index,
            "width": width,
            "height": height,
            "hotspot": [hotspot_x, hotspot_y],
            "palette_id": palette_offset + 50500,
        })
    return {"valid": True, "version": version, "frame_count": frame_count, "frames": frames}


def container_list(member) -> list[dict[str, object]]:
    return [
        {name: value.value for name, value in container.value.items()}
        for container in member.value
    ]


def scalar_list(member) -> list[object]:
    return [value.value if hasattr(value, "value") else value for value in member.value]


def attack_sounds(graphic) -> list[dict[str, object]]:
    if "graphic_attack_sounds" not in graphic.value:
        return []
    result = []
    for angle, container in enumerate(graphic["graphic_attack_sounds"].value):
        properties = container.value.get("sound_props")
        result.append({"angle": angle, "events": container_list(properties) if properties else []})
    return result


def cache_record(dat_hash: str, archive_hashes: dict[str, str], game_version: str) -> dict[str, object]:
    palette_hash = archive_hashes.get("interfac", "missing")
    components = {
        "sourceSha256": dat_hash,
        "archiveSha256": archive_hashes,
        "importerVersion": IMPORTER_VERSION,
        "schemaVersion": CATALOG_SCHEMA_VERSION,
        "palette": {"id": "catalog-metadata", "sha256": palette_hash},
        "gameVersion": game_version,
    }
    encoded = json.dumps(components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "formatVersion": CACHE_SCHEMA_VERSION,
        "key": sha256_bytes(encoded),
        "components": components,
    }


def main() -> int:
    args = parse_args()
    dat_path = args.dat or args.game / "data2" / "empires.dat"
    if not dat_path.is_file():
        raise FileNotFoundError(f"Rise of Rome data file not found: {dat_path}")
    archive_paths = [path for name in ARCHIVE_NAMES for path in find_drs_all(args.game, name)]
    archive_hashes = {str(path.relative_to(args.game)).replace("\\", "/"): sha256_bytes(path.read_bytes()) for path in archive_paths}
    dat_hash = sha256_bytes(dat_path.read_bytes())
    cache = cache_record(dat_hash, archive_hashes, args.game_version)
    if args.output.is_file():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if existing.get("cache", {}).get("key") == cache["key"]:
                print(f"graphics catalog cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError):
            pass

    drs_archives = {}
    for path in archive_paths:
        data, entries = parse_drs(path)
        archive_key = str(path.relative_to(args.game)).replace("\\", "/")
        drs_archives[archive_key] = {"path": path, "data": data, "entries": entries}

    game_version = GameVersion(GameEdition("Local Rise of Rome", "ROR", "YES", [], [], {}, [], []))
    with dat_path.open("rb") as dat_file:
        root = load_gamespec(dat_file, game_version).value[0]

    entries: dict[str, object] = {}
    missing_slp = []
    for graphic in root["graphics"].value:
        graphic_id = int(graphic["graphic_id"].value)
        slp_id = int(graphic["slp_id"].value)
        source_drs = None
        slp = {"valid": False, "error": "SLP is not present in loaded DRS archives", "frames": []}
        for archive_name, archive in drs_archives.items():
            location = archive["entries"].get(("slp", slp_id))
            if location is None:
                continue
            offset, size = location
            source_drs = archive_name
            slp = slp_frame_geometry(archive["data"][offset:offset + size])
            break
        if source_drs is None and slp_id >= 0:
            missing_slp.append({"graphic_id": graphic_id, "slp_id": slp_id})
        entries[str(graphic_id)] = {
            "graphic_id": graphic_id,
            "filename": graphic["filename"].value,
            "source_drs": source_drs,
            "slp_id": slp_id,
            "coordinates": scalar_list(graphic["coordinates"]),
            "frames_per_angle": int(graphic["frame_count"].value),
            "angle_count": int(graphic["angle_count"].value),
            "frame_rate": float(graphic["frame_rate"].value),
            "replay_delay": float(graphic["replay_delay"].value),
            "speed_adjust": float(graphic["speed_adjust"].value),
            "sequence_type": int(graphic["sequence_type"].value),
            "mirroring_mode": int(graphic["mirroring_mode"].value),
            "layer": graphic["layer"].value,
            "player_color": {
                "old_color_flag": bool(graphic["old_color_flag"].value),
                "force_id": int(graphic["player_color_force_id"].value),
                "adapt_color": int(graphic["adapt_color"].value),
            },
            "sounds": {
                "sound_id": int(graphic["sound_id"].value),
                "attack": attack_sounds(graphic),
            },
            "deltas": container_list(graphic["graphic_deltas"]),
            "slp": slp,
        }

    payload = {
        "format_version": CATALOG_SCHEMA_VERSION,
        "cache": cache,
        "source": {
            "empires_dat": str(dat_path.relative_to(args.game)).replace("\\", "/"),
            "game_version": args.game_version,
            "dat_version": root["versionstr"].value,
            "archives": [str(path.relative_to(args.game)).replace("\\", "/") for path in archive_paths],
        },
        "graphic_count": len(root["graphics"].value),
        "entry_count": len(entries),
        "missing_slp": missing_slp,
        "graphics": entries,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"exported {len(entries)} graphics ({len(missing_slp)} missing SLP) to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
