#!/usr/bin/env python3

"""Summarize source-owned campaign matches into a machine-checkable launch gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
AUDITOR_VERSION = "campaign-gap-matrix-2"


class CampaignAuditError(ValueError):
    """Raised when campaign identity or an audit input is inconsistent."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a RoR campaign gap matrix.")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--runtime-catalog", type=Path, required=True)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--matches-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise CampaignAuditError(f"{path}: expected a JSON object")
    return value


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_campaign(catalog: dict[str, Any], filename: str) -> dict[str, Any]:
    campaign = next(
        (
            value
            for value in catalog.get("campaigns", [])
            if str(value.get("filename", "")).casefold() == filename.casefold()
        ),
        None,
    )
    if campaign is None:
        raise CampaignAuditError(f"campaign absent from catalog: {filename}")
    return campaign


def available_asset_names(assets_root: Path) -> set[str]:
    result: set[str] = set()
    for path in assets_root.glob("*.png"):
        result.add(path.stem)
        if re.search(r"_\d+$", path.stem):
            result.add(re.sub(r"_\d+$", "", path.stem))
    return result


def direct_asset_names(match: dict[str, Any]) -> set[str]:
    names: set[str] = set()
    for entity in match.get("entities", []):
        for key in ("source_graphic_asset_name", "source_depleted_asset_name"):
            if entity.get(key):
                names.add(str(entity[key]))
    for collection in (
        "presentation_markers",
        "presentation_environment",
        "static_obstructions",
    ):
        for item in match.get(collection, []):
            if item.get("asset_name"):
                names.add(str(item["asset_name"]))
    return names


def archetype_asset_names(
    match: dict[str, Any], runtime_catalog: dict[str, Any]
) -> tuple[set[str], list[str]]:
    archetypes = runtime_catalog.get("archetypes", {})
    aliases = {
        str(entity.get("kind", ""))
        for entity in match.get("entities", [])
        if str(entity.get("kind", ""))
    }
    missing_aliases = sorted(alias for alias in aliases if alias not in archetypes)
    names: set[str] = set()
    for alias in sorted(aliases - set(missing_aliases)):
        runtime = archetypes[alias].get("runtime", {})
        state_groups = [runtime.get("presentation_states", {})]
        state_groups.extend(runtime.get("presentation_variants", {}).values())
        for states in state_groups:
            for state in states.values():
                for key in ("asset_name", "enemy_asset_name"):
                    if state.get(key):
                        names.add(str(state[key]))
    return names, missing_aliases


def summarize_mission(
    declaration: dict[str, Any],
    source_scenario: dict[str, Any],
    match: dict[str, Any],
    runtime_catalog: dict[str, Any],
    available_assets: set[str],
) -> dict[str, Any]:
    expected_id = str(declaration["match_id"])
    source = match.get("source", {})
    if str(match.get("id", "")) != expected_id:
        raise CampaignAuditError(f"mission id mismatch: expected {expected_id}")
    if int(source.get("scenario_index", -1)) != int(declaration["scenario_index"]):
        raise CampaignAuditError(f"scenario index mismatch for {expected_id}")
    if str(source.get("scenario_sha256", "")) != str(source_scenario.get("sha256", "")):
        raise CampaignAuditError(f"scenario hash mismatch for {expected_id}")

    gaps = match.get("gaps", {})
    unsupported_objects = int(gaps.get("unsupported_object_count", 0))
    unsupported_conditions = int(
        gaps.get("unsupported_legacy_victory_condition_count", 0)
    )
    trigger_source = match.get("scenario_logic", {}).get("trigger_source", {})
    pending_triggers = int(trigger_source.get("condition_count", 0)) + int(
        trigger_source.get("effect_count", 0)
    )
    pending_ai = int(gaps.get("source_ai_player_count_pending", 0))
    partial_ai = int(gaps.get("source_ai_player_count_partial", 0))
    source_settings = match.get("source_settings", {})
    settings_pending = int(gaps.get("source_settings", {}).get("gap_count", 0))

    archetype_assets, missing_aliases = archetype_asset_names(match, runtime_catalog)
    required_assets = direct_asset_names(match) | archetype_assets
    missing_assets = sorted(
        name for name in required_assets if name not in available_assets
    )
    asset_gap_count = len(missing_aliases) + len(missing_assets)

    blocking = {
        "object_gap_count": unsupported_objects,
        "condition_gap_count": unsupported_conditions,
        "trigger_semantics_gap_count": pending_triggers,
        "ai_normalization_gap_count": pending_ai,
        "asset_gap_count": asset_gap_count,
    }
    parity = {
        "ai_semantics_gap_count": partial_ai,
        "source_settings_gap_count": settings_pending,
    }
    gap_ids: list[str] = []
    for key, count in {**blocking, **parity}.items():
        if count > 0:
            gap_ids.append(key.removesuffix("_count"))
    launcher_ready = all(count == 0 for count in blocking.values())
    parity_ready = launcher_ready and all(count == 0 for count in parity.values())
    object_reasons = Counter()
    object_gaps = sorted(
        gaps.get("objects", []),
        key=lambda value: (
            str(value.get("reason", "")),
            int(value.get("source_unit_id", -1)),
        ),
    )
    for record in object_gaps:
        object_reasons[str(record.get("reason", "unknown"))] += int(
            record.get("count", 0)
        )
    unsupported_condition_records = match.get("scenario_logic", {}).get(
        "unsupported_conditions", []
    )
    ai_gaps: list[dict[str, Any]] = []
    for player in match.get("players", []):
        if str(player.get("controller", "")) != "ai":
            continue
        contract = player.get("source_ai", {})
        runtime_support = contract.get("runtime_support", {})
        pending_numbers = runtime_support.get(
            "pending_strategic_number_ids", []
        )
        pending_directives = runtime_support.get("pending_rule_directives", [])
        build_order_status = str(contract.get("build_order_status", ""))
        enabled = bool(player.get("ai", {}).get("enabled", False))
        if enabled and str(runtime_support.get("status", "partial")) == "integrated":
            continue
        ai_gaps.append(
            {
                "team": int(player.get("team", -1)),
                "normalization_status": str(contract.get("status", "absent")),
                "runtime_enabled": enabled,
                "rule_name": str(contract.get("rule_name", "")),
                "build_list_name": str(contract.get("build_list_name", "")),
                "build_order_status": build_order_status,
                "pending_strategic_number_ids": pending_numbers,
                "pending_rule_directives": pending_directives,
                "documented_noop_strategic_number_ids": runtime_support.get(
                    "documented_noop_strategic_number_ids", []
                ),
                "unclassified_strategic_number_ids": runtime_support.get(
                    "unclassified_strategic_number_ids", []
                ),
                "strategic_capabilities": runtime_support.get(
                    "strategic_capabilities", {}
                ),
                "unsupported_rule_line_count": len(
                    contract.get("unsupported_rule_lines", [])
                ),
                "unsupported_build_line_count": len(
                    contract.get("unsupported_build_lines", [])
                ),
            }
        )

    return {
        "scenario_index": int(declaration["scenario_index"]),
        "match_id": expected_id,
        "title": str(source.get("scenario_name", source_scenario.get("name", ""))),
        "scenario_filename": str(source.get("scenario_filename", "")),
        "scenario_sha256": str(source_scenario.get("sha256", "")),
        "map_size": match.get("map", {}).get("size", []),
        "active_player_count": len(match.get("players", [])),
        "source_ai_profile_count": sum(
            1
            for player in match.get("players", [])
            if str(player.get("controller", "")) == "ai"
        ),
        "source_object_count": int(gaps.get("source_object_count", 0)),
        "runtime_entity_count": int(gaps.get("runtime_entity_count", 0)),
        "presentation_object_count": int(gaps.get("presentation_marker_count", 0))
        + int(gaps.get("presentation_environment_count", 0))
        + int(gaps.get("static_obstruction_count", 0)),
        "normalized_condition_count": sum(
            len(group.get("conditions", []))
            for participant in match.get("scenario_definition", {}).get(
                "participants", []
            )
            for group in participant.get("groups", [])
        ),
        "blocking_gaps": blocking,
        "parity_gaps": parity,
        "object_gap_reasons": dict(sorted(object_reasons.items())),
        "object_gaps": object_gaps,
        "unsupported_conditions": unsupported_condition_records,
        "source_trigger_summary": trigger_source,
        "source_settings": source_settings,
        "ai_gaps": ai_gaps,
        "missing_runtime_aliases": missing_aliases,
        "missing_asset_names": missing_assets,
        "gap_ids": gap_ids,
        "launcher_ready": launcher_ready,
        "parity_ready": parity_ready,
        "launcher_state": str(declaration.get("launcher_state", "blocked_pending_gate")),
        "published": str(declaration.get("launcher_state", "")).startswith("published"),
    }


def main() -> int:
    args = parse_args()
    manifest = read_json(args.manifest)
    catalog = read_json(args.catalog)
    runtime_catalog = read_json(args.runtime_catalog)
    campaign = source_campaign(catalog, str(manifest.get("campaign_filename", "")))
    available_assets = available_asset_names(args.assets_root)
    source_scenarios = {
        int(value.get("index", -1)): value for value in campaign.get("scenarios", [])
    }
    missions: list[dict[str, Any]] = []
    for declaration in manifest.get("missions", []):
        index = int(declaration.get("scenario_index", -1))
        if index not in source_scenarios:
            raise CampaignAuditError(f"manifest scenario absent from catalog: {index}")
        match_path = args.matches_directory / f"{index}.json"
        missions.append(
            summarize_mission(
                declaration,
                source_scenarios[index],
                read_json(match_path),
                runtime_catalog,
                available_assets,
            )
        )

    if len(missions) != len(source_scenarios):
        raise CampaignAuditError(
            f"manifest covers {len(missions)} of {len(source_scenarios)} campaign missions"
        )
    ai_capability_gap_counts: Counter[str] = Counter()
    for mission in missions:
        for gap in mission.get("ai_gaps", []):
            for capability, coverage in gap.get(
                "strategic_capabilities", {}
            ).items():
                if coverage.get("pending_ids", []):
                    ai_capability_gap_counts[str(capability)] += 1
            if gap.get("pending_rule_directives", []):
                ai_capability_gap_counts["source_baseline"] += 1
            if gap.get("build_order_status") == "source_random_default_pending":
                ai_capability_gap_counts["build_order"] += 1

    payload = {
        "schema_version": SCHEMA_VERSION,
        "auditor_version": AUDITOR_VERSION,
        "campaign_id": str(manifest.get("campaign_id", "")),
        "campaign_filename": str(campaign.get("filename", "")),
        "campaign_name": str(campaign.get("name", "")),
        "campaign_sha256": str(campaign.get("sha256", "")),
        "manifest_sha256": sha256_file(args.manifest),
        "runtime_catalog_cache_key": str(runtime_catalog.get("cache", {}).get("key", "")),
        "gate_contract": {
            "launcher_required_zero_gaps": [
                "objects",
                "legacy_conditions",
                "trigger_semantics",
                "ai_normalization",
                "assets",
            ],
            "parity_additional_zero_gaps": ["ai_semantics", "source_settings"],
            "publication_rule": "A mission enters the launcher only after launcher_ready and reproducible win/loss evidence.",
        },
        "summary": {
            "mission_count": len(missions),
            "published_count": sum(1 for mission in missions if mission["published"]),
            "launcher_ready_count": sum(
                1 for mission in missions if mission["launcher_ready"]
            ),
            "blocked_count": sum(
                1 for mission in missions if not mission["launcher_ready"]
            ),
            "parity_ready_count": sum(
                1 for mission in missions if mission["parity_ready"]
            ),
            "source_ai_profile_count": sum(
                int(mission["source_ai_profile_count"]) for mission in missions
            ),
            "source_ai_gap_profile_count": sum(
                len(mission.get("ai_gaps", [])) for mission in missions
            ),
            "unclassified_strategic_number_count": sum(
                len(gap.get("unclassified_strategic_number_ids", []))
                for mission in missions
                for gap in mission.get("ai_gaps", [])
            ),
            "ai_capability_gap_profile_counts": dict(
                sorted(ai_capability_gap_counts.items())
            ),
        },
        "missions": missions,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"audited {len(missions)} missions: "
        f"{payload['summary']['launcher_ready_count']} ready, "
        f"{payload['summary']['blocked_count']} blocked"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
