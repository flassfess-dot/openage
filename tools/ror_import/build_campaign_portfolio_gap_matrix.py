#!/usr/bin/env python3

"""Aggregate all converted source campaigns into a compact, comparable gap matrix."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

from build_campaign_gap_matrix import (
    CampaignAuditError,
    available_asset_names,
    read_json,
    sha256_file,
    summarize_mission,
)


SCHEMA_VERSION = 1
AUDITOR_VERSION = "campaign-portfolio-gap-matrix-1"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the source campaign portfolio gap matrix.")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--runtime-catalog", type=Path, required=True)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--matches-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def source_campaign_by_filename(
    catalog: dict[str, Any], filename: str
) -> dict[str, Any]:
    result = next(
        (
            value
            for value in catalog.get("campaigns", [])
            if str(value.get("filename", "")).casefold() == filename.casefold()
        ),
        None,
    )
    if result is None:
        raise CampaignAuditError(f"campaign absent from source catalog: {filename}")
    return result


def compact_ai_gap(gap: dict[str, Any]) -> dict[str, Any]:
    capabilities = {
        str(name): {
            "implemented_ids": value.get("implemented_ids", []),
            "pending_ids": value.get("pending_ids", []),
            "documented_noop_ids": value.get("documented_noop_ids", []),
        }
        for name, value in sorted(gap.get("strategic_capabilities", {}).items())
        if value.get("pending_ids", [])
        or value.get("documented_noop_ids", [])
    }
    return {
        "team": int(gap.get("team", -1)),
        "normalization_status": str(gap.get("normalization_status", "")),
        "runtime_enabled": bool(gap.get("runtime_enabled", False)),
        "build_order_status": str(gap.get("build_order_status", "")),
        "pending_rule_directives": gap.get("pending_rule_directives", []),
        "unsupported_rule_line_count": int(gap.get("unsupported_rule_line_count", 0)),
        "unsupported_build_line_count": int(gap.get("unsupported_build_line_count", 0)),
        "unclassified_strategic_number_ids": gap.get(
            "unclassified_strategic_number_ids", []
        ),
        "strategic_capabilities": capabilities,
    }


def compact_mission(mission: dict[str, Any], declaration: dict[str, Any]) -> dict[str, Any]:
    source_settings = mission.get("source_settings", {})
    blocking = mission.get("blocking_gaps", {})
    parity = mission.get("parity_gaps", {})
    return {
        "scenario_index": int(mission.get("scenario_index", -1)),
        "audit_match_id": str(mission.get("match_id", "")),
        "title": str(mission.get("title", "")),
        "scenario_filename": str(mission.get("scenario_filename", "")),
        "scenario_sha256": str(mission.get("scenario_sha256", "")),
        "catalog_active_player_count": int(declaration.get("active_player_count", 0)),
        "runtime_player_count": int(mission.get("active_player_count", 0)),
        "map_size": mission.get("map_size", []),
        "source_object_count": int(mission.get("source_object_count", 0)),
        "runtime_entity_count": int(mission.get("runtime_entity_count", 0)),
        "presentation_object_count": int(mission.get("presentation_object_count", 0)),
        "source_ai_profile_count": int(mission.get("source_ai_profile_count", 0)),
        "normalized_condition_count": int(mission.get("normalized_condition_count", 0)),
        "blocking_gaps": blocking,
        "parity_gaps": parity,
        "blocking_gap_total": sum(int(value) for value in blocking.values()),
        "parity_gap_total": sum(int(value) for value in parity.values()),
        "gap_ids": mission.get("gap_ids", []),
        "object_gap_reasons": mission.get("object_gap_reasons", {}),
        "object_gaps": mission.get("object_gaps", []),
        "unsupported_conditions": mission.get("unsupported_conditions", []),
        "source_trigger_summary": mission.get("source_trigger_summary", {}),
        "source_settings_summary": {
            "multiplayer_victory_type": source_settings.get("multiplayer_victory_type"),
            "victory_score": source_settings.get("victory_score"),
            "victory_time": source_settings.get("victory_time"),
            "all_technologies": bool(source_settings.get("all_technologies", False)),
            "player_start_ages": source_settings.get("player_start_ages", []),
            "disabled_unit_count": sum(
                len(values) for values in source_settings.get("disabled_units", [])
            ),
            "disabled_building_count": sum(
                len(values) for values in source_settings.get("disabled_buildings", [])
            ),
            "disabled_technology_count": sum(
                len(values) for values in source_settings.get("disabled_technologies", [])
            ),
            "legacy_disabled_node_count": sum(
                len(values)
                for values in source_settings.get(
                    "legacy_disabled_technology_node_slots", []
                )
            ),
        },
        "ai_gaps": [compact_ai_gap(gap) for gap in mission.get("ai_gaps", [])],
        "missing_runtime_aliases": mission.get("missing_runtime_aliases", []),
        "missing_asset_names": mission.get("missing_asset_names", []),
        "launcher_ready": bool(mission.get("launcher_ready", False)),
        "parity_ready": bool(mission.get("parity_ready", False)),
    }


def compact_failed_mission(
    record: dict[str, Any], declaration: dict[str, Any]
) -> dict[str, Any]:
    source = record.get("source", {})
    raw_summary = record.get("raw_summary", {})
    failure = record.get("portfolio_audit_failure", {})
    blocking = {
        "import_failure_gap_count": 1,
        "object_gap_count": 0,
        "condition_gap_count": 0,
        "trigger_semantics_gap_count": 0,
        "ai_normalization_gap_count": 0,
        "asset_gap_count": 0,
    }
    parity = {
        "ai_semantics_gap_count": 0,
        "source_settings_gap_count": 0,
    }
    return {
        "scenario_index": int(declaration.get("scenario_index", -1)),
        "audit_match_id": str(declaration.get("audit_match_id", "")),
        "title": str(source.get("scenario_name", declaration.get("name", ""))),
        "scenario_filename": str(
            source.get("scenario_filename", declaration.get("filename", ""))
        ),
        "scenario_sha256": str(
            source.get("scenario_sha256", declaration.get("sha256", ""))
        ),
        "catalog_active_player_count": int(declaration.get("active_player_count", 0)),
        "runtime_player_count": int(raw_summary.get("active_player_count", 0)),
        "map_size": raw_summary.get("map_size", []),
        "source_object_count": int(raw_summary.get("source_object_count", 0)),
        "runtime_entity_count": 0,
        "presentation_object_count": 0,
        "source_ai_profile_count": int(raw_summary.get("source_ai_profile_count", 0)),
        "normalized_condition_count": 0,
        "blocking_gaps": blocking,
        "parity_gaps": parity,
        "blocking_gap_total": 1,
        "parity_gap_total": 0,
        "gap_ids": ["import_failure_gap"],
        "object_gap_reasons": {},
        "object_gaps": [],
        "unsupported_conditions": [],
        "source_trigger_summary": raw_summary.get("deferred_scenario_logic", {}),
        "source_settings_summary": {},
        "ai_gaps": [],
        "missing_runtime_aliases": [],
        "missing_asset_names": [],
        "import_failure": {
            "stage": str(failure.get("stage", "unknown")),
            "reason": str(failure.get("reason", "unknown conversion failure")),
        },
        "launcher_ready": False,
        "parity_ready": False,
    }


def aggregate_campaign(
    declaration: dict[str, Any], missions: list[dict[str, Any]]
) -> dict[str, Any]:
    gap_mission_counts: Counter[str] = Counter()
    object_gap_reasons: Counter[str] = Counter()
    unsupported_source_ids: Counter[int] = Counter()
    unsupported_condition_commands: Counter[int] = Counter()
    ai_capability_gap_profiles: Counter[str] = Counter()
    missing_aliases: set[str] = set()
    missing_assets: set[str] = set()
    for mission in missions:
        for gap_id in mission.get("gap_ids", []):
            gap_mission_counts[str(gap_id)] += 1
        object_gap_reasons.update(
            {
                str(reason): int(count)
                for reason, count in mission.get("object_gap_reasons", {}).items()
            }
        )
        for object_gap in mission.get("object_gaps", []):
            unsupported_source_ids[int(object_gap.get("source_unit_id", -1))] += int(
                object_gap.get("count", 0)
            )
        for condition in mission.get("unsupported_conditions", []):
            unsupported_condition_commands[int(condition.get("command", -1))] += 1
        for gap in mission.get("ai_gaps", []):
            for capability, coverage in gap.get("strategic_capabilities", {}).items():
                if coverage.get("pending_ids", []):
                    ai_capability_gap_profiles[str(capability)] += 1
            if gap.get("pending_rule_directives", []):
                ai_capability_gap_profiles["source_baseline"] += 1
            if gap.get("build_order_status") == "source_random_default_pending":
                ai_capability_gap_profiles["build_order"] += 1
        missing_aliases.update(str(value) for value in mission.get("missing_runtime_aliases", []))
        missing_assets.update(str(value) for value in mission.get("missing_asset_names", []))

    blocked_missions = sum(1 for mission in missions if not mission["launcher_ready"])
    blocking_total = sum(int(mission["blocking_gap_total"]) for mission in missions)
    parity_total = sum(int(mission["parity_gap_total"]) for mission in missions)
    return {
        "campaign_index": int(declaration.get("campaign_index", -1)),
        "portfolio_id": str(declaration.get("portfolio_id", "")),
        "name": str(declaration.get("name", "")),
        "filename": str(declaration.get("filename", "")),
        "extension": str(declaration.get("extension", "")),
        "sha256": str(declaration.get("sha256", "")),
        "mission_count": len(missions),
        "launcher_ready_mission_count": len(missions) - blocked_missions,
        "blocked_mission_count": blocked_missions,
        "parity_ready_mission_count": sum(1 for mission in missions if mission["parity_ready"]),
        "blocking_gap_total": blocking_total,
        "parity_gap_total": parity_total,
        "gap_mission_counts": dict(sorted(gap_mission_counts.items())),
        "object_gap_reasons": dict(sorted(object_gap_reasons.items())),
        "unsupported_source_object_counts": {
            str(source_id): count
            for source_id, count in sorted(unsupported_source_ids.items())
            if source_id >= 0
        },
        "unsupported_condition_command_counts": {
            str(command): count
            for command, count in sorted(unsupported_condition_commands.items())
        },
        "ai_capability_gap_profile_counts": dict(sorted(ai_capability_gap_profiles.items())),
        "missing_runtime_aliases": sorted(missing_aliases),
        "missing_asset_names": sorted(missing_assets),
        "selection_score": [
            blocked_missions,
            blocking_total,
            parity_total,
            len(missions),
        ],
        "missions": missions,
    }


def main() -> int:
    args = parse_args()
    manifest = read_json(args.manifest)
    catalog = read_json(args.catalog)
    runtime_catalog = read_json(args.runtime_catalog)
    if str(manifest.get("source_catalog_sha256", "")) != sha256_file(args.catalog):
        raise CampaignAuditError("portfolio manifest is stale for the source catalog")
    available_assets = available_asset_names(args.assets_root)
    campaigns: list[dict[str, Any]] = []

    for campaign_declaration in manifest.get("campaigns", []):
        source_campaign = source_campaign_by_filename(
            catalog, str(campaign_declaration.get("filename", ""))
        )
        source_scenarios = {
            int(value.get("index", -1)): value
            for value in source_campaign.get("scenarios", [])
        }
        missions: list[dict[str, Any]] = []
        campaign_index = int(campaign_declaration.get("campaign_index", -1))
        for declaration in campaign_declaration.get("missions", []):
            scenario_index = int(declaration.get("scenario_index", -1))
            match_path = args.matches_directory / f"c{campaign_index:02d}" / f"m{scenario_index:02d}.json"
            match = read_json(match_path)
            if match.get("portfolio_audit_failure"):
                missions.append(compact_failed_mission(match, declaration))
                continue
            detailed = summarize_mission(
                {
                    "scenario_index": scenario_index,
                    "match_id": str(declaration.get("audit_match_id", "")),
                    "launcher_state": "portfolio_audit_only",
                },
                source_scenarios[scenario_index],
                match,
                runtime_catalog,
                available_assets,
            )
            missions.append(compact_mission(detailed, declaration))
        campaigns.append(aggregate_campaign(campaign_declaration, missions))

    ranked = sorted(
        (
            campaign
            for campaign in campaigns
            if str(campaign.get("filename", "")).casefold() != "расцвет рима.cpx"
        ),
        key=lambda campaign: tuple(campaign["selection_score"]),
    )
    common_gap_campaign_counts: Counter[str] = Counter()
    for campaign in campaigns:
        common_gap_campaign_counts.update(campaign.get("gap_mission_counts", {}).keys())
    mission_count = sum(int(campaign["mission_count"]) for campaign in campaigns)
    payload = {
        "schema_version": SCHEMA_VERSION,
        "auditor_version": AUDITOR_VERSION,
        "manifest_sha256": sha256_file(args.manifest),
        "source_catalog_cache_key": str(catalog.get("cache", {}).get("key", "")),
        "runtime_catalog_cache_key": str(runtime_catalog.get("cache", {}).get("key", "")),
        "summary": {
            "campaign_count": len(campaigns),
            "mission_count": mission_count,
            "launcher_ready_mission_count": sum(
                int(campaign["launcher_ready_mission_count"]) for campaign in campaigns
            ),
            "blocked_mission_count": sum(
                int(campaign["blocked_mission_count"]) for campaign in campaigns
            ),
            "parity_ready_mission_count": sum(
                int(campaign["parity_ready_mission_count"]) for campaign in campaigns
            ),
            "common_gap_campaign_counts": dict(sorted(common_gap_campaign_counts.items())),
            "recommended_next_campaign_id": str(ranked[0]["portfolio_id"]) if ranked else "",
        },
        "ranked_unpublished_campaign_ids": [
            str(campaign["portfolio_id"]) for campaign in ranked
        ],
        "campaigns": campaigns,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"audited {len(campaigns)} campaigns / {mission_count} missions; "
        f"recommended {payload['summary']['recommended_next_campaign_id']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
