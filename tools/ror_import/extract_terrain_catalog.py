#!/usr/bin/env python3

"""Export Rise of Rome terrain, border and edge-mask metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from openage.convert.service.read.gamedata import load_gamespec  # noqa: E402
from openage.convert.value_object.conversion.ror.internal_nyan_names import (  # noqa: E402
    TERRAIN_GROUP_LOOKUPS,
)
from openage.convert.value_object.init.game_version import (  # noqa: E402
    GameEdition,
    GameVersion,
)
from extract_graphics_catalog import find_drs_all, parse_drs, slp_frame_geometry  # noqa: E402


CACHE_SCHEMA_VERSION = 1
CATALOG_SCHEMA_VERSION = 1
IMPORTER_VERSION = "terrain-catalog-4"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export RoR terrain and border tables.")
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--dat", type=Path)
    parser.add_argument("--game-version", default="1.1")
    parser.add_argument("--output", type=Path, required=True)
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
    value = field(container, name, [])
    return value if isinstance(value, list) else []


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path: Path, root: Path) -> str:
    return str(path.relative_to(root)).replace("\\", "/")


def cache_record(source_hashes: dict[str, str], game_version: str) -> dict[str, object]:
    components = {
        "sourceSha256": source_hashes,
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


def main() -> int:
    args = parse_args()
    dat_path = args.dat or args.game / "data2" / "empires.dat"
    if not dat_path.is_file():
        raise FileNotFoundError(f"Rise of Rome data file not found: {dat_path}")

    archive_paths = [path for name in ("terrain", "border") for path in find_drs_all(args.game, name)]
    edge_paths = []
    for folder_name in ("data2", "data"):
        for filename in ("TileEdge.Dat", "BlkEdge.Dat"):
            candidate = args.game / folder_name / filename
            if candidate.is_file():
                edge_paths.append(candidate)
    source_paths = [dat_path, *archive_paths, *edge_paths]
    source_hashes = {relative(path, args.game): sha256_file(path) for path in source_paths}
    cache = cache_record(source_hashes, args.game_version)
    if args.output.is_file():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if existing.get("cache", {}).get("key") == cache["key"]:
                print(f"terrain catalog cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError):
            pass

    archives = []
    for path in archive_paths:
        data, entries = parse_drs(path)
        archives.append({"path": path, "data": data, "entries": entries})

    def resolve_slp(slp_id: int) -> dict[str, object]:
        for archive in archives:
            location = archive["entries"].get(("slp", slp_id))
            if location is None:
                continue
            offset, size = location
            geometry = slp_frame_geometry(archive["data"][offset:offset + size])
            geometry["source_drs"] = relative(archive["path"], args.game)
            geometry["slp_id"] = slp_id
            return geometry
        return {"valid": False, "slp_id": slp_id, "source_drs": None, "frames": []}

    game_version = GameVersion(GameEdition("Local Rise of Rome", "ROR", "YES", [], [], {}, [], []))
    with dat_path.open("rb") as dat_file:
        root = load_gamespec(dat_file, game_version).value[0]

    terrains = {}
    for terrain_id, terrain in enumerate(root["terrains"].value):
        lookup = TERRAIN_GROUP_LOOKUPS.get(terrain_id)
        slp_id = int(field(terrain, "slp_id", -1))
        terrains[str(terrain_id)] = {
            "terrain_id": terrain_id,
            "name": lookup[1] if lookup else field(terrain, "internal_name", ""),
            "filename_prefix": lookup[2] if lookup else field(terrain, "filename", ""),
            "enabled": bool(field(terrain, "enabled", False)),
            "random": int(field(terrain, "random", 0)),
            "internal_name": field(terrain, "internal_name", ""),
            "filename": field(terrain, "filename", ""),
            "slp_id": slp_id,
            "sound_id": int(field(terrain, "sound_id", -1)),
            "colors": {
                "high": int(field(terrain, "map_color_hi", 0)),
                "medium": int(field(terrain, "map_color_med", 0)),
                "low": int(field(terrain, "map_color_low", 0)),
                "cliff_left": int(field(terrain, "map_color_cliff_lt", 0)),
                "cliff_right": int(field(terrain, "map_color_cliff_rt", 0)),
            },
            "passable_terrain_id": int(field(terrain, "passable_terrain", -1)),
            "impassable_terrain_id": int(field(terrain, "impassable_terrain", -1)),
            "animation": {
                "animated": bool(field(terrain, "is_animated", False)),
                "frame_count": int(field(terrain, "animation_frame_count", 0)),
                "pause_frame_count": int(field(terrain, "pause_frame_count", 0)),
                "interval": float(field(terrain, "interval", 0.0)),
                "pause_between_loops": float(field(terrain, "pause_between_loops", 0.0)),
            },
            "elevation_graphics": records(terrain, "elevation_graphics"),
            "replacement_terrain_id": int(field(terrain, "terrain_replacement_id", -1)),
            "terrain_to_draw": [int(field(terrain, "terrain_to_draw0", -1)), int(field(terrain, "terrain_to_draw1", -1))],
            "borders": [int(value) for value in field(terrain, "borders", [])],
            "terrain_units": {
                "ids": field(terrain, "terrain_unit_id", []),
                "density": field(terrain, "terrain_unit_density", []),
                "placement_flags": field(terrain, "terrain_placement_flag", []),
                "used_count": int(field(terrain, "terrain_units_used_count", 0)),
            },
            "slp": resolve_slp(slp_id),
            "available_fields": sorted(terrain.value.keys()),
        }

    borders = {}
    for border_id, border in enumerate(root["terrain_border"].value):
        slp_id = int(field(border, "slp_id", -1))
        borders[str(border_id)] = {
            "border_id": border_id,
            "enabled": bool(field(border, "enabled", False)),
            "random": int(field(border, "random", 0)),
            "internal_name": field(border, "internal_name", ""),
            "filename": field(border, "filename", ""),
            "slp_id": slp_id,
            "sound_id": int(field(border, "sound_id", -1)),
            "color": field(border, "color", []),
            "animation": {
                "animated": bool(field(border, "is_animated", False)),
                "frame_count": int(field(border, "animation_frame_count", 0)),
                "interval": float(field(border, "interval", 0.0)),
            },
            "frames": records(border, "frames"),
            "underlay_terrain_id": int(field(border, "underlay_terrain", -1)),
            "border_style": int(field(border, "border_style", -1)),
            "slp": resolve_slp(slp_id),
        }

    restrictions = []
    for restriction in root["terrain_restrictions"].value:
        restrictions.append({
            "accessible_damage_multiplier": field(restriction, "accessible_dmgmultiplier", []),
        })

    edge_masks = []
    for path in edge_paths:
        edge_masks.append({
            "file": relative(path, args.game),
            "kind": "fog" if path.name.lower() == "blkedge.dat" else "tile_edge",
            "byte_size": path.stat().st_size,
            "sha256": source_hashes[relative(path, args.game)],
        })

    result = {
        "format_version": CATALOG_SCHEMA_VERSION,
        "cache": cache,
        "source": {"game_version": args.game_version, "dat": relative(dat_path, args.game)},
        "geometry": {
            "tile_sizes": records(root, "tile_sizes"),
            "tile_width": int(field(root, "tile_width", 0)),
            "tile_height": int(field(root, "tile_height", 0)),
            "tile_half_width": int(field(root, "tile_half_width", 0)),
            "tile_half_height": int(field(root, "tile_half_height", 0)),
            "elevation_height": int(field(root, "elev_height", 0)),
        },
        "terrain_count": len(terrains),
        "border_count": len(borders),
        "restriction_count": len(restrictions),
        "terrains": terrains,
        "borders": borders,
        "restrictions": restrictions,
        "edge_masks": edge_masks,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"terrain catalog: {len(terrains)} terrains, {len(borders)} borders, {len(edge_masks)} edge-mask files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
