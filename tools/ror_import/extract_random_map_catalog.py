#!/usr/bin/env python3

"""Export random-map parameters from the owner's Rise of Rome Empires.dat.

The binary layout is read by the vendored openage parser. This exporter keeps
source values intact; gameplay interpretation belongs to the Godot generator.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from zlib import decompress


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from openage.convert.value_object.init.game_version import (  # noqa: E402
    GameEdition,
    GameVersion,
)
from openage.convert.value_object.read.media.datfile.empiresdat import (  # noqa: E402
    EmpiresDatWrapper,
)


PROFILE_IDS = (
    "small_islands",
    "islands",
    "coastal",
    "grasslands",
    "highlands",
    "continental",
    "mediterranean",
    "hill_country",
    "narrows",
)

FIELDS = {
    "land": (
        "land_id", "terrain", "land_spacing", "base_size", "zone",
        "placement_type", "base_x", "base_y", "land_proportion",
        "by_player_flag", "start_area_radius", "terrain_edge_fade",
        "clumpiness",
    ),
    "terrain": (
        "proportion", "terrain_id", "number_of_clumps", "edge_spacing",
        "placement_zone", "clumpiness",
    ),
    "unit": (
        "unit_id", "host_terrain", "group_placing", "scale_flag",
        "objects_per_group", "fluctuation", "groups_per_player",
        "group_radius", "own_at_start", "set_place_for_all_players",
        "min_distance_to_players", "max_distance_to_players",
    ),
    "elevation": (
        "proportion", "terrain", "clump_count", "base_terrain",
        "base_elevation", "tile_spacing",
    ),
}


def record(value: object, fields: tuple[str, ...]) -> dict[str, int]:
    return {field: int(getattr(value, field)) for field in fields}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dat", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    source = args.dat.read_bytes()
    version = GameVersion(GameEdition("Local Rise of Rome", "ROR", "YES", [], [], {}, [], []))
    wrapper = EmpiresDatWrapper()
    wrapper.read(decompress(source, -15), 0, version)
    root = wrapper.empiresdat[0]
    profiles = []
    for index, (info, map_record) in enumerate(zip(root.map_infos, root.maps)):
        profiles.append({
            "source_index": index,
            "profile_id": PROFILE_IDS[index] if index < len(PROFILE_IDS) else "internal_%d" % index,
            "source_map_id": int(info.map_id),
            "base_terrain": int(map_record.base_terrain),
            "border_usage": int(map_record.border_usage),
            "water_shape": int(map_record.water_shape),
            "land_coverage": int(map_record.land_coverage),
            "land_zones": [record(value, FIELDS["land"]) for value in map_record.base_zones],
            "terrain_groups": [record(value, FIELDS["terrain"]) for value in map_record.map_terrains],
            "unit_groups": [record(value, FIELDS["unit"]) for value in map_record.map_units],
            "elevation_groups": [record(value, FIELDS["elevation"]) for value in map_record.map_elevations],
        })

    payload = {
        "schema_version": 1,
        "source": "Rise of Rome data2/empires.dat",
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "parser": "openage EmpiresDatWrapper",
        "profile_mapping": "DAT record order matched to language_up.dll IDs 10602-10610; internal records are not menu options",
        "profiles": profiles,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Exported {len(profiles)} source random-map records to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
