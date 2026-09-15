#!/usr/bin/env python3

"""Convert a raw Genie scenario snapshot into the runtime match contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from collections import Counter
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
IMPORTER_VERSION = "scenario-match-35"
SUPPORTED_RUNTIME_CATEGORIES = {"unit", "building", "resource", "objective"}
VICTORY_COMMAND_NAMES = {
    0: "capture",
    1: "create",
    2: "destroy",
    3: "destroy_multiple",
    4: "bring_to_area",
    5: "bring_to_object",
    6: "attribute",
    7: "explore",
    8: "create_in_area",
    9: "destroy_all",
    10: "destroy_player",
    11: "points",
}
SOURCE_AI_SUPPORTED_STRATEGIC_NUMBERS = {
    16, 18, 19, 20, 22, 25, 26, 28, 30, 31, 35, 36, 38, 40, 41, 42, 43,
    44, 46, 47, 48, 49, 50, 51, 52, 54, 55, 56, 57, 58, 59, 60, 61, 62,
    63, 64, 65, 66, 67, 68, 69, 70, 73, 74, 75, 84, 85, 86, 87, 88, 91,
    92, 104,
}
SOURCE_AI_TICKS_PER_SECOND = 20
SOURCE_AI_STRATEGIC_CAPABILITIES = {
    0: "economy",
    1: "economy",
    2: "economy",
    3: "economy",
    4: "economy",
    5: "economy",
    16: "attack",
    18: "exploration",
    19: "defence",
    20: "defence",
    22: "defence",
    23: "scenario_control",
    24: "scenario_control",
    25: "defence",
    26: "attack",
    28: "defence",
    29: "scenario_control",
    30: "combat_control",
    31: "combat_control",
    32: "exploration",
    34: "targeting",
    35: "exploration",
    36: "attack",
    37: "attack",
    38: "defence",
    39: "defence",
    40: "combat_control",
    41: "attack",
    42: "exploration",
    43: "exploration",
    44: "exploration",
    45: "exploration",
    46: "attack",
    47: "attack",
    48: "defence",
    49: "combat_control",
    50: "defence",
    51: "defence",
    52: "defence",
    53: "defence",
    54: "defence",
    55: "defence",
    56: "defence",
    57: "defence",
    58: "naval_transport",
    59: "naval_transport",
    60: "naval_transport",
    61: "naval_transport",
    62: "naval_transport",
    63: "naval_transport",
    64: "naval_transport",
    65: "naval_transport",
    66: "naval_transport",
    67: "naval_transport",
    68: "naval_transport",
    69: "naval_transport",
    70: "naval_transport",
    71: "combat_control",
    72: "defence",
    73: "economy",
    74: "economy",
    75: "combat_control",
    76: "combat_control",
    77: "targeting",
    78: "targeting",
    79: "targeting",
    80: "targeting",
    81: "targeting",
    82: "targeting",
    83: "targeting",
    84: "economy",
    85: "economy",
    86: "economy",
    87: "economy",
    88: "combat_control",
    89: "targeting",
    90: "targeting",
    91: "combat_control",
    92: "defence",
    104: "attack",
}
SOURCE_AI_DOCUMENTED_NOOP_MARKERS = (
    "UNUSED AT THIS POINT",
    "TEMPORARILY UNUSED",
)
PRESENTATION_ONLY_SOURCE_IDS = {162, 330}
SOURCE_AI_MARKER_IDS = {112}
PREDATOR_SOURCE_IDS = {1, 126}
PRESENTATION_ENVIRONMENT_CATEGORIES = {
    "terrain_feature",
    "presentation_scenery",
    "ambient_actor",
}
SOURCE_PRESENTATION_ENVIRONMENT_OVERRIDES = {
    # Tree Stump is a source presentation object, not a fresh wood resource.
    # Its DAT graphic 600 resolves to the already imported DRS 623 asset.
    131: {
        "runtime_alias": "tree_stump",
        "owner_category": "presentation_scenery",
        "asset_name": "tree_stump",
        "presentation_layer": "scenery",
    },
}
SOURCE_GRAPHIC_ASSET_FALLBACKS = {
    # DAT graphic 930 names SLP 799, which is absent from the installed RoR
    # archives. Preserve that request in the evidence ledger while rendering
    # the semantically equivalent standard tree instead of a missing texture.
    930: ("tree", "source_slp_unavailable"),
}
GAIA_OWNER_CONTRACTS = {
    "forest_resource": ("forest_field", "static_resource_nodes"),
    "terrain_feature": ("terrain_system", "terrain_overlay"),
    "static_obstruction": ("navigation_grid", "static_obstruction_batch"),
    "wildlife": ("wildlife_system", "mobile_simulation_entities"),
    "ambient_actor": ("environment_presentation", "animated_presentation_batch"),
    "presentation_scenery": ("environment_presentation", "static_presentation_batch"),
    "unclassified": ("scenario_import", "blocked_pending_classification"),
}

# The classic AoE/RoR Options tab stores fixed node flags in tooltip order
# (language IDs 30508..30523), followed by four reserved cells. A disabled
# building node also removes access to everything trained or researched there.
LEGACY_TECHNOLOGY_NODES: dict[int, dict[str, Any]] = {
    0: {"node": "granary", "kind": "building", "source_object_id": 68},
    1: {"node": "storage_pit", "kind": "building", "source_object_id": 103},
    2: {"node": "dock", "kind": "building", "source_object_id": 45},
    3: {"node": "barracks", "kind": "building", "source_object_id": 12},
    4: {"node": "market", "kind": "building", "source_object_id": 84},
    5: {"node": "archery_range", "kind": "building", "source_object_id": 87},
    6: {"node": "stable", "kind": "building", "source_object_id": 101},
    7: {"node": "temple", "kind": "building", "source_object_id": 104},
    8: {"node": "government_center", "kind": "building", "source_object_id": 82},
    9: {"node": "siege_workshop", "kind": "building", "source_object_id": 49},
    10: {"node": "academy", "kind": "building", "source_object_id": 0},
    11: {"node": "tool_age", "kind": "age", "technology_id": 101},
    12: {"node": "bronze_age", "kind": "age", "technology_id": 102},
    13: {"node": "iron_age", "kind": "age", "technology_id": 103},
    14: {"node": "town_center", "kind": "building", "source_object_id": 109},
    15: {"node": "wonder", "kind": "building", "source_object_id": 276},
}


class ScenarioConversionError(ValueError):
    """Raised when source identity or the target contract is inconsistent."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a source-owned RoR campaign match.")
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--archetypes", type=Path, required=True)
    parser.add_argument("--objects", type=Path, required=True)
    parser.add_argument(
        "--match-id",
        required=True,
        help="Stable runtime id declared by the campaign manifest.",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", args.match_id):
        parser.error("--match-id must match [a-z][a-z0-9_]*")
    return args


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ScenarioConversionError(f"{path}: expected a JSON object")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_identity(raw: dict[str, Any], catalog: dict[str, Any]) -> dict[str, Any]:
    source = dict(raw.get("source", {}))
    campaign_filename = str(source.get("campaign_filename", ""))
    scenario_index = int(source.get("scenario_index", -1))
    campaign = next(
        (
            value
            for value in catalog.get("campaigns", [])
            if str(value.get("filename", "")).casefold() == campaign_filename.casefold()
        ),
        None,
    )
    if campaign is None:
        raise ScenarioConversionError(f"campaign is absent from source catalog: {campaign_filename}")
    if str(campaign.get("sha256", "")) != str(source.get("campaign_sha256", "")):
        raise ScenarioConversionError("campaign hash differs from the validated source catalog")
    scenarios = campaign.get("scenarios", [])
    if scenario_index < 0 or scenario_index >= len(scenarios):
        raise ScenarioConversionError(f"scenario index outside source catalog: {scenario_index}")
    scenario = scenarios[scenario_index]
    if str(scenario.get("sha256", "")) != str(source.get("scenario_sha256", "")):
        raise ScenarioConversionError("scenario hash differs from the validated source catalog")
    source["source_path"] = str(campaign.get("source_path", ""))
    source["catalog_cache_key"] = str(catalog.get("cache", {}).get("key", ""))
    return source


def register_source(
    result: dict[int, dict[str, Any]], source_id: Any, archetype: dict[str, Any]
) -> None:
    if source_id is None:
        return
    source_id = int(source_id)
    if source_id < 0:
        return
    previous = result.get(source_id)
    if previous is not None and previous.get("alias") != archetype.get("alias"):
        raise ScenarioConversionError(
            f"source unit {source_id} maps to both {previous.get('alias')} and "
            f"{archetype.get('alias')}"
        )
    result[source_id] = archetype


def archetype_by_source(manifest: dict[str, Any]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    excluded_sources: set[int] = set()
    for archetype in manifest.get("archetypes", []):
        register_source(result, archetype.get("source_unit_id"), archetype)
        runtime = archetype.get("runtime", {})
        archetype_exclusions = {
            int(source_id) for source_id in runtime.get("source_mapping_excluded_ids", [])
        }
        excluded_sources.update(archetype_exclusions)
        for source_id in runtime.get("source_variant_unit_ids", []):
            if int(source_id) in archetype_exclusions:
                continue
            register_source(result, source_id, archetype)
        for source_id in runtime.get("presentation_variants", {}):
            if int(source_id) in archetype_exclusions:
                continue
            register_source(result, source_id, archetype)
        for profile_group in ("worker_resource_profiles", "worker_task_profiles"):
            for profile in runtime.get(profile_group, {}).values():
                register_source(result, profile.get("role_source_unit_id"), archetype)
    missing_owners = sorted(source_id for source_id in excluded_sources if source_id not in result)
    if missing_owners:
        raise ScenarioConversionError(
            "source mapping exclusions have no canonical owner: "
            + ", ".join(str(source_id) for source_id in missing_owners)
        )
    return result


def object_catalog_by_source(catalog: dict[str, Any]) -> dict[int, dict[str, Any]]:
    grouped: dict[int, list[dict[str, Any]]] = {}
    for record in catalog.get("objects", {}).values():
        grouped.setdefault(int(record.get("unit_id", -1)), []).append(record)
    result: dict[int, dict[str, Any]] = {}
    for source_id, candidates in grouped.items():
        candidates.sort(key=lambda value: (int(value.get("civilization_id", -1)) != 0, int(value.get("civilization_id", -1))))
        result[source_id] = candidates[0]
    return result


def resource_amount(source_id: int, objects: dict[int, dict[str, Any]], state: int) -> int:
    if state == 7:
        return 0
    record = objects.get(source_id, {})
    resources = record.get("resources", {})
    storage = resources.get("storage", [])
    positive = [float(value.get("amount", 0.0)) for value in storage if float(value.get("amount", 0.0)) > 0.0]
    amount = positive[0] if positive else float(resources.get("capacity", 0.0))
    return max(0, int(round(amount)))


def classify_gaia_object(source_id: int, record: dict[str, Any]) -> str:
    """Route a Gaia object to its owning runtime system using source DAT fields."""
    unit_class = int(record.get("unit_class", -1))
    unit_type = int(record.get("unit_type", -1))
    if source_id == 80:
        return "terrain_feature"
    if unit_class == 15:
        return "forest_resource"
    if unit_class == 34:
        return "static_obstruction"
    if unit_class == 10 and unit_type == 70:
        return "wildlife"
    if unit_class == 10 and unit_type == 40:
        return "ambient_actor"
    if unit_class == 14:
        return "presentation_scenery"
    return "unclassified"


def gaia_gap_ledger(
    source_entities: list[dict[str, Any]],
    object_catalog: dict[int, dict[str, Any]],
) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    for source in source_entities:
        if int(source.get("owner_slot", -1)) != 0:
            continue
        source_id = int(source.get("source_unit_id", -1))
        category = str(source.get("owner_contract_category", ""))
        integration_status = "integrated" if category else "pending"
        if not category:
            if source.get("runtime_status") != "gap":
                continue
            category = classify_gaia_object(source_id, object_catalog.get(source_id, {}))
        owner_system, strategy = GAIA_OWNER_CONTRACTS[category]
        source["gap_category"] = category
        source["gap_owner_system"] = owner_system
        group = grouped.setdefault(
            category,
            {"source_counts": Counter(), "integration_statuses": set()},
        )
        group["source_counts"][source_id] += 1
        group["integration_statuses"].add(integration_status)
    result: list[dict[str, Any]] = []
    for category in sorted(grouped):
        source_counts = grouped[category]["source_counts"]
        statuses = grouped[category]["integration_statuses"]
        owner_system, strategy = GAIA_OWNER_CONTRACTS[category]
        result.append(
            {
                "category": category,
                "owner_system": owner_system,
                "integration_strategy": strategy,
                "integration_status": "integrated" if statuses == {"integrated"} else "partial" if "integrated" in statuses else "pending",
                "instance_count": sum(source_counts.values()),
                "source_ids": [
                    {"source_unit_id": source_id, "count": source_counts[source_id]}
                    for source_id in sorted(source_counts)
                ],
            }
        )
    return result


def vertex_levels(tile_levels: list[Any], width: int, height: int) -> list[int]:
    expected = width * height
    if len(tile_levels) != expected:
        raise ScenarioConversionError(
            f"tile elevation count {len(tile_levels)} does not match map {width}x{height}"
        )
    result: list[int] = []
    for y in range(height + 1):
        source_y = min(y, height - 1)
        for x in range(width + 1):
            source_x = min(x, width - 1)
            result.append(max(0, int(tile_levels[source_y * width + source_x])))
    return result


def position_in_bounds(position: list[Any], width: int, height: int) -> bool:
    return len(position) >= 2 and 0.0 <= float(position[0]) < width and 0.0 <= float(position[1]) < height


def obstruction_cells(
    position: list[Any], radius: list[Any], width: int, height: int
) -> list[list[int]]:
    half_x = max(0.0, float(radius[0])) if radius else 0.0
    half_y = max(0.0, float(radius[1])) if len(radius) > 1 else half_x
    center_x, center_y = float(position[0]), float(position[1])
    minimum_x = math.ceil(center_x - half_x - 0.5)
    maximum_x = math.floor(center_x + half_x - 0.5)
    minimum_y = math.ceil(center_y - half_y - 0.5)
    maximum_y = math.floor(center_y + half_y - 0.5)
    return [
        [x, y]
        for y in range(max(0, minimum_y), min(height - 1, maximum_y) + 1)
        for x in range(max(0, minimum_x), min(width - 1, maximum_x) + 1)
    ]


def player_start(
    team: int,
    objects: list[dict[str, Any]],
    mappings: dict[int, dict[str, Any]],
    width: int,
    height: int,
) -> list[float]:
    owned = [value for value in objects if int(value.get("owner_slot", -1)) == team]
    for preferred_alias in ("town_center", "villager"):
        preferred = [
            value
            for value in owned
            if mappings.get(int(value.get("source_unit_id", -1)), {}).get("alias")
            == preferred_alias
            and position_in_bounds(value.get("position", []), width, height)
        ]
        if preferred:
            x = sum(float(value["position"][0]) for value in preferred) / len(preferred)
            y = sum(float(value["position"][1]) for value in preferred) / len(preferred)
            return [x, y]
    for value in owned:
        if position_in_bounds(value.get("position", []), width, height):
            return [float(value["position"][0]), float(value["position"][1])]
    return [width * 0.5, height * 0.5]


def source_text_sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest() if value else ""


def strategic_number_runtime_semantics(source_id: int, name: str) -> str:
    upper_name = name.upper()
    if any(marker in upper_name for marker in SOURCE_AI_DOCUMENTED_NOOP_MARKERS):
        return "source_documented_noop"
    if source_id in SOURCE_AI_SUPPORTED_STRATEGIC_NUMBERS:
        return "implemented"
    return "pending"


def strategic_capability_coverage(
    entries: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    buckets: dict[str, dict[str, Any]] = {}
    for entry in entries:
        capability = str(entry["capability"])
        semantics = str(entry["runtime_semantics"])
        bucket = buckets.setdefault(
            capability,
            {
                "entry_count": 0,
                "implemented_ids": set(),
                "source_documented_noop_ids": set(),
                "pending_ids": set(),
            },
        )
        bucket["entry_count"] += 1
        if semantics == "implemented":
            bucket["implemented_ids"].add(int(entry["source_id"]))
        elif semantics == "source_documented_noop":
            bucket["source_documented_noop_ids"].add(int(entry["source_id"]))
        else:
            bucket["pending_ids"].add(int(entry["source_id"]))
    return {
        capability: {
            "entry_count": int(bucket["entry_count"]),
            "implemented_ids": sorted(bucket["implemented_ids"]),
            "source_documented_noop_ids": sorted(
                bucket["source_documented_noop_ids"]
            ),
            "pending_ids": sorted(bucket["pending_ids"]),
        }
        for capability, bucket in sorted(buckets.items())
    }


def effective_strategic_number(
    entries: list[dict[str, Any]], source_id: int, default: int
) -> int:
    result = default
    for entry in entries:
        if int(entry.get("source_id", -1)) == source_id:
            result = int(entry.get("value", default))
    return result


def has_implemented_strategic_number(
    entries: list[dict[str, Any]], source_id: int
) -> bool:
    return any(
        int(entry.get("source_id", -1)) == source_id
        and entry.get("runtime_semantics") == "implemented"
        for entry in entries
    )


def parse_strategic_numbers(
    value: str,
) -> tuple[list[dict[str, Any]], list[str], list[dict[str, Any]]]:
    entries: list[dict[str, Any]] = []
    unsupported: list[str] = []
    directives: list[dict[str, Any]] = []
    reached_end = False
    for raw_line in value.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        if line.upper() == "END":
            reached_end = True
            continue
        if line.upper() == "DEFAULT":
            directives.append(
                {
                    "name": "DEFAULT",
                    "runtime_status": "recognized_pending_baseline",
                }
            )
            continue
        match = re.match(r"^(-?\d+)\s+(-?\d+)(?:\s*//\s*(.*?))?\s*$", line)
        if match is None:
            unsupported.append(line)
            continue
        source_id = int(match.group(1))
        name = (match.group(3) or "").strip()
        runtime_semantics = strategic_number_runtime_semantics(source_id, name)
        entries.append(
            {
                "source_id": source_id,
                "value": int(match.group(2)),
                "name": name,
                "capability": SOURCE_AI_STRATEGIC_CAPABILITIES.get(
                    source_id, "unclassified"
                ),
                "runtime_semantics": runtime_semantics,
                "runtime_supported": runtime_semantics != "pending",
            }
        )
    if value and not reached_end:
        unsupported.append("END marker missing")
    return entries, unsupported, directives


def parse_build_order(
    value: str,
) -> tuple[list[dict[str, Any]], list[str], list[str]]:
    entries: list[dict[str, Any]] = []
    unsupported: list[str] = []
    disabled: list[str] = []
    for raw_line in value.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue
        # Several stock campaign lists disable entries by prefixing them with a
        # backslash. Preserve those source lines for audit instead of treating
        # them as executable or as an unknown dialect.
        if line.startswith("\\"):
            disabled.append(line)
            continue
        match = re.match(
            r"^([A-Za-z])\s*(-?\d+)\s+(.+?)\s+(-?\d+)\s+(-?\d+)(?:\s+(-?\d+(?:\s+-?\d+)*))?\s*$",
            line,
        )
        if match is None or match.group(1).upper() not in {"B", "C", "R", "T", "U"}:
            unsupported.append(line)
            continue
        opcode = match.group(1).upper()
        entry_type = {
            "B": "building",
            "C": "technology",
            "R": "technology",
            "T": "unit",
            "U": "unit",
        }[opcode]
        source_parameters = (match.group(6) or "").split()
        entries.append(
            {
                "type": entry_type,
                "source_opcode": opcode,
                "source_id": int(match.group(2)),
                "source_name": match.group(3),
                "target_count": int(match.group(4)),
                "producer_source_unit_id": int(match.group(5)),
                "source_parameters": source_parameters,
            }
        )
    return entries, unsupported, disabled


def normalize_source_ai(
    source: dict[str, Any],
    objects: list[dict[str, Any]],
    team: int,
    mappings: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    raw_ai = source.get("source_ai") or {}
    rules = str(raw_ai.get("embedded_rules") or "")
    build_list = str(raw_ai.get("embedded_build_list") or "")
    strategic_numbers, unsupported_rule_lines, source_rule_directives = (
        parse_strategic_numbers(rules)
    )
    build_order, unsupported_build_lines, disabled_build_lines = parse_build_order(
        build_list
    )
    for entry in build_order:
        if entry["type"] in {"unit", "building"}:
            entry["runtime_alias"] = str(
                mappings.get(int(entry["source_id"]), {}).get("alias", "")
            )
    target_markers = [
        {
            "scenario_object_id": int(value.get("scenario_object_id", -1)),
            "source_unit_id": 112,
            "position": [float(value["position"][0]), float(value["position"][1])],
            "source_state": int(value.get("state", 0)),
        }
        for value in objects
        if int(value.get("owner_slot", -1)) == team
        and int(value.get("source_unit_id", -1)) == 112
        and int(value.get("state", 0)) != 7
        and len(value.get("position", [])) >= 2
    ]
    target_markers.sort(key=lambda value: int(value["scenario_object_id"]))
    rule_name = str(raw_ai.get("rule_name") or "")
    build_list_name = str(raw_ai.get("build_list_name") or "")
    random_rule = rule_name.casefold() == "random" and not rules
    if random_rule:
        source_rule_directives.append(
            {
                "name": "RANDOM",
                "runtime_status": "source_random_default_pending",
            }
        )
    random_build_list = build_list_name.casefold() == "random" and not build_list
    has_tactical_update_number = any(
        int(entry.get("source_id", -1)) == 88
        and entry.get("runtime_semantics") == "implemented"
        for entry in strategic_numbers
    )
    tactical_update_seconds = max(
        0, effective_strategic_number(strategic_numbers, 88, 1)
    )

    pending_strategic_number_ids = sorted(
        {
            int(entry["source_id"])
            for entry in strategic_numbers
            if not entry["runtime_supported"]
        }
    )
    documented_noop_strategic_number_ids = sorted(
        {
            int(entry["source_id"])
            for entry in strategic_numbers
            if entry["runtime_semantics"] == "source_documented_noop"
        }
    )
    pending_rule_directives = [
        directive["name"]
        for directive in source_rule_directives
        if directive["runtime_status"] != "integrated"
    ]
    runtime_status = (
        "partial"
        if pending_strategic_number_ids
        or pending_rule_directives
        or random_build_list
        or unsupported_rule_lines
        or unsupported_build_lines
        else "integrated"
    )
    has_source_contract = bool(
        strategic_numbers
        or build_order
        or source_rule_directives
        or rule_name
        or build_list_name
    )
    status = runtime_status if has_source_contract else "absent"
    attack_enabled = any(
        has_implemented_strategic_number(strategic_numbers, source_id)
        for source_id in (16, 26, 36, 46, 104)
    )
    naval_attack_enabled = (
        has_implemented_strategic_number(strategic_numbers, 58)
        and has_implemented_strategic_number(strategic_numbers, 59)
        and effective_strategic_number(strategic_numbers, 58, 0) > 0
        and effective_strategic_number(strategic_numbers, 59, 0) > 0
    )
    defence_response_enabled = all(
        has_implemented_strategic_number(strategic_numbers, source_id)
        for source_id in (19, 20)
    )
    defence_enabled = (
        has_implemented_strategic_number(strategic_numbers, 38)
        and effective_strategic_number(strategic_numbers, 38, 0) > 0
        and any(
            has_implemented_strategic_number(strategic_numbers, source_id)
            and effective_strategic_number(strategic_numbers, source_id, 0) > 0
            for source_id in (50, 51, 52, 54, 55, 56)
        )
    )
    exploration_enabled = (
        (
            has_implemented_strategic_number(strategic_numbers, 35)
            and effective_strategic_number(strategic_numbers, 35, 0) > 0
        )
        or (
            has_implemented_strategic_number(strategic_numbers, 42)
            and has_implemented_strategic_number(strategic_numbers, 43)
            and effective_strategic_number(strategic_numbers, 42, 0) > 0
            and effective_strategic_number(strategic_numbers, 43, 0) > 0
        )
    )
    naval_exploration_enabled = (
        has_implemented_strategic_number(strategic_numbers, 61)
        and has_implemented_strategic_number(strategic_numbers, 62)
        and effective_strategic_number(strategic_numbers, 61, 0) > 0
        and effective_strategic_number(strategic_numbers, 62, 0) > 0
    )
    naval_defence_enabled = (
        has_implemented_strategic_number(strategic_numbers, 67)
        and has_implemented_strategic_number(strategic_numbers, 68)
        and has_implemented_strategic_number(strategic_numbers, 70)
        and effective_strategic_number(strategic_numbers, 67, 0) > 0
        and effective_strategic_number(strategic_numbers, 68, 0) > 0
        and effective_strategic_number(strategic_numbers, 70, 0) > 0
    )
    naval_escort_enabled = any(
        has_implemented_strategic_number(strategic_numbers, source_id)
        and effective_strategic_number(strategic_numbers, source_id, 0) > 0
        for source_id in (64, 65, 66)
    )
    return {
        "schema_version": 1,
        "status": status,
        "rule_name": rule_name,
        "rule_type": int(raw_ai.get("rule_type") or 0),
        "rules_sha256": source_text_sha256(rules),
        "build_list_name": build_list_name,
        "build_list_sha256": source_text_sha256(build_list),
        "city_plan_name": str(raw_ai.get("city_plan_name") or ""),
        "city_plan_sha256": source_text_sha256(str(raw_ai.get("embedded_city_plan") or "")),
        "strategic_numbers": strategic_numbers,
        "source_rule_directives": source_rule_directives,
        "build_order": build_order,
        "build_order_status": "source_random_default_pending" if random_build_list else "normalized",
        "target_markers": target_markers,
        "unsupported_rule_lines": unsupported_rule_lines,
        "unsupported_build_lines": unsupported_build_lines,
        "disabled_build_lines": disabled_build_lines,
        "runtime_support": {
            "status": runtime_status,
            "economy_enabled": True,
            "build_order_enabled": bool(build_order),
            "military_enabled": (
                attack_enabled
                or naval_attack_enabled
                or defence_response_enabled
                or defence_enabled
                or exploration_enabled
                or naval_exploration_enabled
                or naval_defence_enabled
                or naval_escort_enabled
            ),
            "attack_enabled": attack_enabled or naval_attack_enabled,
            "naval_attack_enabled": naval_attack_enabled,
            "defence_response_enabled": defence_response_enabled,
            "defence_enabled": defence_enabled,
            "exploration_enabled": exploration_enabled,
            "naval_exploration_enabled": naval_exploration_enabled,
            "naval_defence_enabled": naval_defence_enabled,
            "naval_escort_enabled": naval_escort_enabled,
            "tactical_update_interval_ticks": max(
                1, tactical_update_seconds * SOURCE_AI_TICKS_PER_SECOND
            ),
            "tactical_update_source": (
                "strategic_number_88"
                if has_tactical_update_number
                else "runtime_fallback"
            ),
            "supported_strategic_number_ids": sorted(SOURCE_AI_SUPPORTED_STRATEGIC_NUMBERS),
            "pending_strategic_number_ids": pending_strategic_number_ids,
            "documented_noop_strategic_number_ids": documented_noop_strategic_number_ids,
            "unclassified_strategic_number_ids": sorted(
                {
                    int(entry["source_id"])
                    for entry in strategic_numbers
                    if entry["capability"] == "unclassified"
                }
            ),
            "pending_rule_directives": pending_rule_directives,
            "strategic_capabilities": strategic_capability_coverage(
                strategic_numbers
            ),
        },
    }


def legacy_disabled_technology_nodes(
    scenario_settings: dict[str, Any], player_index: int
) -> list[dict[str, Any]]:
    if scenario_settings.get("disabled_technologies_format") != "legacy_node_flags":
        return []
    player_slots = list(
        scenario_settings.get("legacy_disabled_technology_node_slots", [])
    )
    slots = list(player_slots[player_index]) if player_index < len(player_slots) else []
    result: list[dict[str, Any]] = []
    for value in slots:
        slot = int(value)
        if slot not in LEGACY_TECHNOLOGY_NODES:
            continue
        node = dict(LEGACY_TECHNOLOGY_NODES[slot])
        node["slot"] = slot
        result.append(node)
    result.sort(key=lambda value: int(value["slot"]))
    return result


def build_players(
    raw_players: list[dict[str, Any]],
    objects: list[dict[str, Any]],
    mappings: dict[int, dict[str, Any]],
    scenario_settings: dict[str, Any],
    width: int,
    height: int,
) -> list[dict[str, Any]]:
    players: list[dict[str, Any]] = []
    for player_index, source in enumerate(raw_players):
        if not bool(source.get("active", False)):
            continue
        team = player_index + 1
        world = source.get("world_resources") or source.get("start_resources") or {}
        resources = {
            key: max(0, int(round(float(world.get(key, 0.0)))))
            for key in ("food", "wood", "gold", "stone")
        }
        player = {
            "team": team,
            "controller": "human" if int(source.get("player_type", 0)) == 1 else "ai",
            "civilization_id": max(0, int(source.get("civilization_id", 13))),
            "start": player_start(team, objects, mappings, width, height),
            "starting_resources": resources,
            "population_limit": max(1, int(round(float(world.get("population", 50.0))))),
            "source": {
                "player_index": player_index,
                "name": source.get("name"),
                "color": source.get("color"),
                "posture": source.get("posture"),
                "view": source.get("view"),
                "location": source.get("location"),
                "allied_victory": bool(source.get("allied_victory", False)),
                "population_limit": (source.get("world_resources") or {}).get("population"),
            },
        }
        source_start_ages = list(scenario_settings.get("player_start_ages", []))
        source_start_age = int(source_start_ages[player_index]) if player_index < len(source_start_ages) else -1
        player["source"]["starting_age"] = source_start_age
        player["starting_age_technology_id"] = {
            -1: 100,
            0: 100,
            1: 101,
            2: 102,
            3: 103,
            4: 103,
        }.get(source_start_age, 100)
        player["starting_technology_mode"] = (
            "post_iron" if source_start_age == 4 else "age_start"
        )
        disabled_nodes = legacy_disabled_technology_nodes(
            scenario_settings, player_index
        )
        if disabled_nodes:
            player["disabled_technology_nodes"] = disabled_nodes
        if player["controller"] == "ai":
            source_ai = normalize_source_ai(source, objects, team, mappings)
            player["source_ai"] = source_ai
            source_random_fallback = (
                str(source_ai.get("rule_name", "")).casefold() == "random"
                and str(source_ai.get("build_list_name", "")).casefold() == "empty"
            )
            source_profile_ready = (
                source_ai["status"] in {"normalized", "partial", "integrated"}
                and bool(source_ai["strategic_numbers"] or source_ai["build_order"])
            )
            player["ai"] = {
                "enabled": source_profile_ready or source_random_fallback,
                "profile": (
                    "source_campaign_v1"
                    if source_profile_ready
                    else "source_random_fallback"
                    if source_random_fallback
                    else "source_campaign_pending"
                ),
                "economic_interval_ticks": 20,
                "military_interval_ticks": int(
                    source_ai["runtime_support"]["tactical_update_interval_ticks"]
                ),
                "formation": "RECTANGLE",
            }
        players.append(player)
    return players


def runtime_entities(
    raw_objects: list[dict[str, Any]],
    mappings: dict[int, dict[str, Any]],
    object_catalog: dict[int, dict[str, Any]],
    width: int,
    height: int,
) -> tuple[
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
]:
    entities: list[dict[str, Any]] = []
    source_entities: list[dict[str, Any]] = []
    presentation_markers: list[dict[str, Any]] = []
    presentation_environment: list[dict[str, Any]] = []
    static_obstructions: list[dict[str, Any]] = []
    gaps: Counter[tuple[str, int]] = Counter()
    for source_value in raw_objects:
        source = dict(source_value)
        source_id = int(source.get("source_unit_id", -1))
        state = int(source.get("state", 0))
        archetype = mappings.get(source_id)
        source_record = object_catalog.get(source_id, {})

        environment_override = SOURCE_PRESENTATION_ENVIRONMENT_OVERRIDES.get(source_id)
        if (
            environment_override is not None
            and int(source.get("owner_slot", -1)) == 0
            and position_in_bounds(source.get("position", []), width, height)
        ):
            position = source["position"]
            graphic_id = int(source_record.get("graphics", {}).get("idle", -1))
            owner_category = str(environment_override["owner_category"])
            owner_system, _strategy = GAIA_OWNER_CONTRACTS[owner_category]
            source["runtime_status"] = "presentation_environment"
            source["runtime_alias"] = str(environment_override["runtime_alias"])
            source["runtime_category"] = "presentation"
            source["runtime_owner_system"] = owner_system
            source["owner_contract_category"] = owner_category
            presentation_environment.append(
                {
                    "id": -200000 - len(presentation_environment),
                    "kind": owner_category,
                    "presentation_subtype": str(environment_override["runtime_alias"]),
                    "position": [float(position[0]), float(position[1])],
                    "source_unit_id": source_id,
                    "scenario_object_id": int(source.get("scenario_object_id", -1)),
                    "source_state": state,
                    "source_angle": float(source.get("angle", 0.0)),
                    "source_elevation": float(position[2]) if len(position) >= 3 else 0.0,
                    "source_frame": int(source.get("frame", -1)),
                    "graphic_id": graphic_id,
                    "asset_name": str(environment_override["asset_name"]),
                    "presentation_layer": str(environment_override["presentation_layer"]),
                    "animated": False,
                }
            )
            source_entities.append(source)
            continue

        # Scenario flags and Flare objects are service-layer data in this mission,
        # not autonomous simulation entities. Preserve their source identity while
        # routing them to the system that actually owns their behavior.
        if source_id in PRESENTATION_ONLY_SOURCE_IDS and position_in_bounds(
            source.get("position", []), width, height
        ):
            position = source["position"]
            owner_team = int(source.get("owner_slot", 0))
            record = object_catalog.get(source_id, {})
            graphic_id = int(record.get("graphics", {}).get("idle", -1))
            source["runtime_status"] = "presentation_only"
            source["runtime_alias"] = "scenario_flag"
            source["runtime_category"] = "presentation_marker"
            presentation_markers.append(
                {
                    "id": -100000 - len(presentation_markers),
                    "kind": "scenario_flag",
                    "team": owner_team,
                    "position": [float(position[0]), float(position[1])],
                    "source_unit_id": source_id,
                    "scenario_object_id": int(source.get("scenario_object_id", -1)),
                    "source_state": state,
                    "source_angle": float(source.get("angle", 0.0)),
                    "source_frame": int(source.get("frame", -1)),
                    "graphic_id": graphic_id,
                    "asset_name": f"graphic_{graphic_id}_p{max(1, owner_team)}",
                }
            )
            source_entities.append(source)
            continue
        owner_category = classify_gaia_object(source_id, source_record)
        if (
            archetype is None
            and int(source.get("owner_slot", -1)) == 0
            and owner_category in PRESENTATION_ENVIRONMENT_CATEGORIES
            and position_in_bounds(source.get("position", []), width, height)
        ):
            position = source["position"]
            graphic_id = int(source_record.get("graphics", {}).get("idle", -1))
            owner_system, _strategy = GAIA_OWNER_CONTRACTS[owner_category]
            source["runtime_status"] = "presentation_environment"
            source["runtime_alias"] = owner_category
            source["runtime_category"] = "presentation"
            source["runtime_owner_system"] = owner_system
            source["owner_contract_category"] = owner_category
            presentation_environment.append(
                {
                    "id": -200000 - len(presentation_environment),
                    "kind": owner_category,
                    "position": [float(position[0]), float(position[1])],
                    "source_unit_id": source_id,
                    "scenario_object_id": int(source.get("scenario_object_id", -1)),
                    "source_state": state,
                    "source_angle": float(source.get("angle", 0.0)),
                    "source_elevation": float(position[2]) if len(position) >= 3 else 0.0,
                    "source_frame": int(source.get("frame", -1)),
                    "graphic_id": graphic_id,
                    "asset_name": f"graphic_{graphic_id}",
                    "presentation_layer": (
                        "decal"
                        if owner_category == "terrain_feature"
                        else "ambient_actor"
                        if owner_category == "ambient_actor"
                        else "scenery"
                    ),
                    "animated": owner_category == "ambient_actor",
                }
            )
            source_entities.append(source)
            continue
        if (
            archetype is None
            and int(source.get("owner_slot", -1)) == 0
            and owner_category == "static_obstruction"
            and position_in_bounds(source.get("position", []), width, height)
        ):
            position = source["position"]
            graphic_id = int(source_record.get("graphics", {}).get("idle", -1))
            source["runtime_status"] = "static_obstruction"
            source["runtime_alias"] = "cliff"
            source["runtime_category"] = "navigation_obstruction"
            source["runtime_owner_system"] = "navigation_grid"
            source["owner_contract_category"] = owner_category
            static_obstructions.append(
                {
                    "id": -300000 - len(static_obstructions),
                    "kind": "cliff",
                    "position": [float(position[0]), float(position[1])],
                    "occupied_cells": obstruction_cells(
                        position,
                        list(source_record.get("geometry", {}).get("radius", [])),
                        width,
                        height,
                    ),
                    "source_unit_id": source_id,
                    "scenario_object_id": int(source.get("scenario_object_id", -1)),
                    "source_state": state,
                    "source_angle": float(source.get("angle", 0.0)),
                    "source_elevation": float(position[2]) if len(position) >= 3 else 0.0,
                    "source_frame": int(round(float(source.get("angle", 0.0)))),
                    "graphic_id": graphic_id,
                    "asset_name": f"graphic_{graphic_id}",
                    "presentation_layer": "scenery",
                    "animated": False,
                }
            )
            source_entities.append(source)
            continue
        if source_id in SOURCE_AI_MARKER_IDS:
            source["runtime_status"] = "source_ai_marker"
            source["runtime_alias"] = "flare"
            source["runtime_category"] = "campaign_ai_marker"
            source_entities.append(source)
            continue
        if (
            archetype is None
            and int(source.get("owner_slot", -1)) == 0
            and classify_gaia_object(source_id, source_record) == "forest_resource"
            and position_in_bounds(source.get("position", []), width, height)
        ):
            position = source["position"]
            idle_graphic_id = int(source_record.get("graphics", {}).get("idle", -1))
            depleted_graphic_id = int(source_record.get("graphics", {}).get("death", -1))
            requested_asset_name = f"graphic_{idle_graphic_id}"
            fallback = SOURCE_GRAPHIC_ASSET_FALLBACKS.get(idle_graphic_id)
            runtime_asset_name = str(fallback[0]) if fallback else requested_asset_name
            source["runtime_status"] = "mapped"
            source["runtime_alias"] = "tree"
            source["runtime_category"] = "resource"
            source["runtime_owner_system"] = "forest_field"
            source["owner_contract_category"] = "forest_resource"
            entities.append(
                {
                    "category": "resource",
                    "team": 0,
                    "kind": "tree",
                    "position": [float(position[0]), float(position[1])],
                    "amount": resource_amount(source_id, object_catalog, state),
                    "source_unit_id": source_id,
                    "scenario_object_id": int(source.get("scenario_object_id", -1)),
                    "source_state": state,
                    "source_angle": float(source.get("angle", 0.0)),
                    "source_elevation": float(position[2]) if len(position) >= 3 else 0.0,
                    "source_frame": int(source.get("frame", -1)),
                    "source_graphic_id": idle_graphic_id,
                    "source_graphic_asset_name": runtime_asset_name,
                    "source_requested_graphic_asset_name": requested_asset_name,
                    "source_asset_fallback_reason": str(fallback[1]) if fallback else "",
                    "source_depleted_graphic_id": depleted_graphic_id,
                    "source_depleted_asset_name": f"graphic_{depleted_graphic_id}",
                    "static_field_node": True,
                }
            )
            source_entities.append(source)
            continue
        reason = ""
        if archetype is None:
            reason = "archetype_missing"
        elif str(archetype.get("category", "")) not in SUPPORTED_RUNTIME_CATEGORIES:
            reason = "runtime_category_unsupported"
        elif source.get("garrisoned_in") is not None:
            reason = "initial_garrison_unsupported"
        elif not position_in_bounds(source.get("position", []), width, height):
            reason = "position_out_of_bounds"

        source["runtime_status"] = "gap" if reason else "mapped"
        source["runtime_alias"] = str(archetype.get("alias", "")) if archetype else ""
        source["runtime_category"] = str(archetype.get("category", "")) if archetype else ""
        if reason:
            source["gap_reason"] = reason
            gaps[(reason, source_id)] += 1
            source_entities.append(source)
            continue

        position = source["position"]
        category = str(archetype["category"])
        entity = {
            "category": category,
            "team": int(source.get("owner_slot", 0)),
            "kind": str(archetype["alias"]),
            "position": [float(position[0]), float(position[1])],
            "source_unit_id": source_id,
            "scenario_object_id": int(source.get("scenario_object_id", -1)),
            "source_state": state,
            "source_angle": float(source.get("angle", 0.0)),
            "source_elevation": float(position[2]) if len(position) >= 3 else 0.0,
            "source_frame": int(source.get("frame", -1)),
        }
        if category == "resource":
            entity["amount"] = resource_amount(source_id, object_catalog, state)
        elif category == "building":
            entity["completed"] = state == 2
        elif category == "objective":
            graphic_id = int(source_record.get("graphics", {}).get("idle", -1))
            entity["completed"] = state == 2
            entity["active"] = True
            entity["graphic_id"] = graphic_id
            entity["asset_name"] = f"graphic_{graphic_id}"
        if int(source.get("owner_slot", -1)) == 0 and source_id in PREDATOR_SOURCE_IDS:
            source["runtime_owner_system"] = "wildlife_system"
            source["owner_contract_category"] = owner_category
        entities.append(entity)
        source_entities.append(source)

    gap_records = [
        {"reason": reason, "source_unit_id": source_id, "count": count}
        for (reason, source_id), count in sorted(gaps.items())
    ]
    return entities, source_entities, presentation_markers, presentation_environment, static_obstructions, gap_records


def alliance_pairs(diplomacy: list[list[Any]], player_count: int) -> list[list[int]]:
    result: list[list[int]] = []
    for left in range(player_count):
        for right in range(left + 1, player_count):
            left_value = int(diplomacy[left][right]) if left < len(diplomacy) and right < len(diplomacy[left]) else 3
            right_value = int(diplomacy[right][left]) if right < len(diplomacy) and left < len(diplomacy[right]) else 3
            if left_value == 0 and right_value == 0:
                result.append([left + 1, right + 1])
    return result


def source_player_team(source_player_id: int, owner_team: int) -> int:
    return owner_team if source_player_id < 0 else source_player_id


def normalize_scenario_definition(
    raw: dict[str, Any],
    mappings: dict[int, dict[str, Any]],
    active_teams: set[int],
    source_entities: list[dict[str, Any]],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    participants: list[dict[str, Any]] = []
    unsupported: list[dict[str, Any]] = []
    mapped_objects = {
        int(value.get("scenario_object_id", -1)): value
        for value in source_entities
        if value.get("runtime_status") == "mapped"
        and int(value.get("scenario_object_id", -1)) >= 0
    }
    for raw_player in raw.get("players", []):
        source_slot = int(raw_player.get("slot", -1))
        owner_team = source_slot + 1
        if owner_team not in active_teams:
            continue
        grouped: dict[int, list[dict[str, Any]]] = {}
        victory = raw_player.get("victory_conditions") or {}
        for condition_index, raw_condition in enumerate(victory.get("entries", [])):
            command = int(raw_condition.get("command", -1))
            command_name = VICTORY_COMMAND_NAMES.get(command, f"unknown_{command}")
            group_id = int(raw_condition.get("victory_group", 0))
            condition_id = f"team_{owner_team}_group_{group_id}_condition_{condition_index}"
            common = {
                "id": condition_id,
                "source_command": command,
                "source_command_name": command_name,
                "source_state": int(raw_condition.get("state", 0)),
            }
            normalized: dict[str, Any] | None = None
            if command == 8:
                source_unit_id = int(raw_condition.get("object_type", -1))
                archetype = mappings.get(source_unit_id, {})
                area = [float(value) for value in raw_condition.get("area", [])]
                if len(area) == 4 and archetype:
                    normalized = {
                        **common,
                        "type": "create_in_area",
                        "team": source_player_team(
                            int(raw_condition.get("player_id", -1)), owner_team
                        ),
                        "source_unit_id": source_unit_id,
                        "kind": str(archetype.get("alias", "")),
                        "required_count": max(1, int(raw_condition.get("number", 1))),
                        "area": area,
                    }
            elif command == 3:
                target_team = source_player_team(
                    int(raw_condition.get("player_id", -1)), owner_team
                )
                target_source_unit_id = int(raw_condition.get("object_type", -1))
                required_count = max(1, int(raw_condition.get("number", 1)))
                target_ids = sorted(
                    int(value.get("scenario_object_id", -1))
                    for value in source_entities
                    if value.get("runtime_status") == "mapped"
                    and int(value.get("owner_slot", -1)) == target_team
                    and int(value.get("source_unit_id", -1))
                    == target_source_unit_id
                    and int(value.get("scenario_object_id", -1)) >= 0
                )
                if target_source_unit_id >= 0 and len(target_ids) >= required_count:
                    normalized = {
                        **common,
                        "type": "destroy_count",
                        "target_team": target_team,
                        "target_source_unit_id": target_source_unit_id,
                        "target_scenario_object_ids": target_ids,
                        "required_count": required_count,
                    }
            elif command == 4:
                source_object_id = int(raw_condition.get("source_object", -1))
                source_object = mapped_objects.get(source_object_id)
                area = [float(value) for value in raw_condition.get("area", [])]
                if source_object is not None and len(area) == 4:
                    normalized = {
                        **common,
                        "type": "bring_object_to_area",
                        "target_scenario_object_id": source_object_id,
                        "target_source_unit_id": int(
                            source_object.get("source_unit_id", -1)
                        ),
                        "area": area,
                    }
            elif command == 2:
                target_object_id = int(raw_condition.get("target_object", -1))
                target_object = mapped_objects.get(target_object_id)
                if target_object is not None:
                    normalized = {
                        **common,
                        "type": "destroy_object",
                        "target_scenario_object_id": target_object_id,
                        "target_source_unit_id": int(
                            target_object.get("source_unit_id", -1)
                        ),
                        "target_team": source_player_team(
                            int(raw_condition.get("player_id", -1)), owner_team
                        ),
                    }
            elif command == 10:
                normalized = {
                    **common,
                    "type": "destroy_player",
                    "target_team": source_player_team(
                        int(raw_condition.get("player_id", -1)), owner_team
                    ),
                }
            if normalized is None:
                unsupported.append(
                    {
                        "team": owner_team,
                        "condition_index": condition_index,
                        "command": command,
                        "command_name": command_name,
                        "source": raw_condition,
                    }
                )
                continue
            grouped.setdefault(group_id, []).append(normalized)
        groups = [
            {
                "id": f"team_{owner_team}_group_{group_id}",
                "source_group": group_id,
                "mode": "all",
                "conditions": conditions,
            }
            for group_id, conditions in sorted(grouped.items())
            if conditions
        ]
        if groups:
            participants.append(
                {
                    "team": owner_team,
                    "completion_mode": "any",
                    "groups": groups,
                }
            )
    legacy = raw.get("legacy_victory", {})
    return (
        {
            "schema_version": 1,
            "source_format": "ror_legacy_victory",
            "all_conditions_required": bool(
                legacy.get("all_conditions_required", False)
            ),
            "participants": participants,
            "source_global_victory": legacy.get("global", {}),
        },
        unsupported,
    )


def normalize_match_victory_rules(
    raw: dict[str, Any], scenario_definition: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    settings = raw.get("scenario_settings", {})
    global_victory = scenario_definition.get("source_global_victory", {})
    victory_type = int(settings.get("multiplayer_victory_type", -1))
    rules: list[dict[str, Any]] = []
    unsupported: list[dict[str, Any]] = []
    if scenario_definition.get("participants", []):
        rules.append({"type": "scenario_definition"})

    if victory_type == 0:
        # Classic Standard victory: any of conquest, all artifacts, all ruins,
        # or a completed Wonder held for the source countdown. The scenario
        # stores victory_time in tenths of a second (9000 = about 15 minutes).
        hold_seconds = max(0.0, float(settings.get("victory_time", 9000)) / 10.0)
        rules.extend(
            [
                {"type": "conquest"},
                {"type": "artifacts", "hold_seconds": hold_seconds},
                {"type": "ruins", "hold_seconds": hold_seconds},
                {"type": "wonder", "hold_seconds": hold_seconds},
            ]
        )
    elif victory_type == 1:
        rules.append({"type": "conquest"})
    elif victory_type == 4:
        if bool(global_victory.get("conquest", False)):
            rules.append({"type": "conquest"})
    else:
        unsupported.append(
            {
                "field": "multiplayer_victory_type",
                "source_value": victory_type,
                "reason": "victory_mode_unsupported",
            }
        )

    if not rules:
        unsupported.append(
            {
                "field": "victory_rules",
                "source_value": victory_type,
                "reason": "no_runtime_victory_rule",
            }
        )
    return rules, unsupported


def source_settings_support(raw: dict[str, Any], victory_gaps: list[dict[str, Any]]) -> dict[str, Any]:
    settings = raw.get("scenario_settings", {})
    active_slots = [
        index
        for index, player in enumerate(raw.get("players", []))
        if bool(player.get("active", False))
    ]
    start_ages = list(settings.get("player_start_ages", []))
    pending_age_teams = [
        slot + 1
        for slot in active_slots
        if slot < len(start_ages) and int(start_ages[slot]) not in {-1, 0, 1, 2, 3, 4}
    ]
    disabled_scopes: dict[str, list[int]] = {}
    for field in ("disabled_technologies", "disabled_units", "disabled_buildings"):
        values = list(settings.get(field, []))
        teams = [
            slot + 1
            for slot in active_slots
            if slot < len(values) and bool(values[slot])
        ]
        if teams:
            disabled_scopes[field] = teams
    legacy_unknown_slots: dict[int, list[int]] = {}
    if settings.get("disabled_technologies_format") == "legacy_node_flags":
        rows = list(settings.get("legacy_disabled_technology_node_slots", []))
        for slot in active_slots:
            values = list(rows[slot]) if slot < len(rows) else []
            unknown = sorted(
                int(value)
                for value in values
                if int(value) not in LEGACY_TECHNOLOGY_NODES
            )
            if unknown:
                legacy_unknown_slots[slot + 1] = unknown
    all_technologies_pending = bool(settings.get("all_technologies", False))
    gap_count = (
        len(victory_gaps)
        + len(pending_age_teams)
        + sum(len(teams) for teams in disabled_scopes.values())
        + sum(len(slots) for slots in legacy_unknown_slots.values())
        + int(all_technologies_pending)
    )
    return {
        "status": "integrated" if gap_count == 0 else "partial",
        "gap_count": gap_count,
        "victory_mode_status": "integrated" if not victory_gaps else "pending",
        "victory_mode_gaps": victory_gaps,
        "starting_age_status": "integrated" if not pending_age_teams else "pending",
        "pending_starting_age_teams": pending_age_teams,
        "disabled_content_status": "integrated" if not disabled_scopes and not legacy_unknown_slots else "pending",
        "pending_disabled_content_teams": disabled_scopes,
        "legacy_technology_nodes_status": "integrated" if not legacy_unknown_slots else "pending",
        "pending_legacy_technology_node_slots": legacy_unknown_slots,
        "all_technologies_status": "pending" if all_technologies_pending else "integrated",
    }


def main() -> int:
    args = parse_args()
    raw = read_json(args.raw)
    catalog = read_json(args.catalog)
    manifest = read_json(args.archetypes)
    object_catalog_json = read_json(args.objects)
    source = source_identity(raw, catalog)
    cache_components = {
        "scenario_sha256": str(source["scenario_sha256"]),
        "campaign_sha256": str(source["campaign_sha256"]),
        "catalog_cache_key": str(source["catalog_cache_key"]),
        "archetypes_sha256": sha256_file(args.archetypes),
        "objects_sha256": sha256_file(args.objects),
        "match_id": args.match_id,
        "importer_version": IMPORTER_VERSION,
        "importer_sha256": sha256_file(Path(__file__)),
        "schema_version": SCHEMA_VERSION,
    }
    cache_key = hashlib.sha256(
        json.dumps(cache_components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    if args.output.is_file():
        try:
            existing = read_json(args.output)
            if existing.get("cache", {}).get("key") == cache_key:
                print(f"scenario match cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError, ScenarioConversionError):
            pass

    raw_map = raw.get("map", {})
    size = raw_map.get("size", [])
    if len(size) != 2:
        raise ScenarioConversionError("scenario map size is missing")
    width, height = int(size[0]), int(size[1])
    if width < 8 or height < 8 or width > 256 or height > 256:
        raise ScenarioConversionError(f"scenario map size outside runtime contract: {width}x{height}")
    terrain_ids = [int(value) for value in raw_map.get("terrain_ids", [])]
    if len(terrain_ids) != width * height:
        raise ScenarioConversionError("scenario terrain count does not match map size")

    mappings = archetype_by_source(manifest)
    object_catalog = object_catalog_by_source(object_catalog_json)
    raw_objects = list(raw.get("objects", []))
    entities, source_entities, presentation_markers, presentation_environment, static_obstructions, gaps = runtime_entities(
        raw_objects, mappings, object_catalog, width, height
    )
    gaia_classifications = gaia_gap_ledger(source_entities, object_catalog)
    players = build_players(
        list(raw.get("players", [])),
        raw_objects,
        mappings,
        dict(raw.get("scenario_settings", {})),
        width,
        height,
    )
    if len(players) < 2:
        raise ScenarioConversionError("scenario must contain at least two active players")
    diplomacy = list(raw.get("diplomacy", []))
    scenario_definition, unsupported_scenario_conditions = normalize_scenario_definition(
        raw,
        mappings,
        {int(player["team"]) for player in players},
        source_entities,
    )
    victory_rules, unsupported_victory_settings = normalize_match_victory_rules(
        raw, scenario_definition
    )
    settings_support = source_settings_support(raw, unsupported_victory_settings)
    neutral_pairs = 0
    for left in range(len(players)):
        for right in range(left + 1, len(players)):
            if left < len(diplomacy) and right < len(diplomacy[left]) and int(diplomacy[left][right]) == 1:
                neutral_pairs += 1

    seed = int(str(source["scenario_sha256"])[:8], 16) & 0x7FFFFFFF or 1
    payload = {
        "schema_version": SCHEMA_VERSION,
        "id": args.match_id,
        "title": str(source.get("scenario_name", "Birth of Rome")),
        "start_message": str(raw.get("description", "")).splitlines()[0],
        "briefing": str(raw.get("description", "")).strip(),
        "cache": {"key": cache_key, "components": cache_components},
        "source": source,
        "map": {
            "size": [width, height],
            "seed": seed,
            "generator": {
                "type": "fixed_source",
                "terrain_ids": terrain_ids,
                "vertex_levels": vertex_levels(
                    list(raw_map.get("tile_elevations", [])), width, height
                ),
            },
            "source_tiles": {
                "tile_elevations": raw_map.get("tile_elevations", []),
                "layered_terrain_ids": raw_map.get("layered_terrain_ids", []),
                "zones": raw_map.get("zones", []),
            },
        },
        "players": players,
        "local_team": next(
            (int(value["team"]) for value in players if value["controller"] == "human"),
            int(players[0]["team"]),
        ),
        "entities": entities,
        "presentation_markers": presentation_markers,
        "presentation_environment": presentation_environment,
        "static_obstructions": static_obstructions,
        "source_entities": source_entities,
        "alliances": alliance_pairs(diplomacy, len(players)),
        "source_diplomacy": diplomacy,
        "victory_rules": victory_rules,
        "scenario_definition": scenario_definition,
        "source_settings": raw.get("scenario_settings", {}),
        "scenario_logic": {
            "status": "integrated"
            if not unsupported_scenario_conditions
            else "partial",
            "trigger_source": raw.get("deferred_scenario_logic", {}),
            "legacy_victory_source": raw.get("legacy_victory", {}),
            "unsupported_conditions": unsupported_scenario_conditions,
        },
        "gaps": {
            "source_object_count": len(source_entities),
            "runtime_entity_count": len(entities),
            "unsupported_object_count": sum(int(record["count"]) for record in gaps),
            "presentation_marker_count": len(presentation_markers),
            "presentation_environment_count": len(presentation_environment),
            "static_obstruction_count": len(static_obstructions),
            "source_ai_marker_count": sum(1 for value in source_entities if value.get("runtime_status") == "source_ai_marker"),
            "gaia_classifications": gaia_classifications,
            "objects": gaps,
            "source_asset_fallback_count": sum(
                1
                for entity in entities
                if str(entity.get("source_asset_fallback_reason", ""))
                or str(
                    mappings.get(int(entity.get("source_unit_id", -1)), {})
                    .get("runtime", {})
                    .get("presentation_variants", {})
                    .get(str(int(entity.get("source_unit_id", -1))), {})
                    .get("fallback_reason", "")
                )
            ),
            "neutral_diplomacy_pair_count": neutral_pairs,
            "unsupported_legacy_victory_condition_count": len(
                unsupported_scenario_conditions
            ),
            "source_ai_player_count_pending": sum(
                1
                for player in players
                if player["controller"] == "ai"
                and not bool(player.get("ai", {}).get("enabled", False))
            ),
            "source_ai_player_count_normalized": sum(
                1
                for player in players
                if player["controller"] == "ai"
                and player.get("source_ai", {}).get("status") in {"normalized", "partial"}
            ),
            "source_ai_player_count_integrated": sum(
                1
                for player in players
                if player["controller"] == "ai"
                and bool(player.get("ai", {}).get("enabled", False))
            ),
            "source_ai_player_count_partial": sum(
                1
                for player in players
                if player["controller"] == "ai"
                and bool(player.get("ai", {}).get("enabled", False))
                and player.get("source_ai", {})
                .get("runtime_support", {})
                .get("status")
                == "partial"
            ),
            "source_settings_runtime_status": str(settings_support["status"]),
            "source_settings": settings_support,
            "initial_garrison": "deferred",
        },
        "validation": {"status": "valid", "errors": []},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"built {payload['id']}: {width}x{height}, {len(players)} players, "
        f"{len(entities)}/{len(source_entities)} runtime objects"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
