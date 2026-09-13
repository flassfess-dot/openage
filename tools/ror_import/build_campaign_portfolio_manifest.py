#!/usr/bin/env python3

"""Build a deterministic manifest for every campaign in the validated source catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
GENERATOR_VERSION = "campaign-portfolio-manifest-1"


class PortfolioManifestError(ValueError):
    """Raised when the source catalog cannot produce a stable portfolio."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the source campaign portfolio manifest.")
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise PortfolioManifestError(f"{path}: expected a JSON object")
    return value


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    args = parse_args()
    catalog = read_json(args.catalog)
    campaigns: list[dict[str, Any]] = []
    seen_campaign_hashes: set[str] = set()
    seen_scenario_hashes: set[str] = set()
    mission_count = 0

    for campaign_index, source_campaign in enumerate(catalog.get("campaigns", [])):
        campaign_hash = str(source_campaign.get("sha256", ""))
        if len(campaign_hash) != 64 or campaign_hash in seen_campaign_hashes:
            raise PortfolioManifestError(
                f"campaign {campaign_index}: missing or duplicate source hash"
            )
        seen_campaign_hashes.add(campaign_hash)
        missions: list[dict[str, Any]] = []
        for source_scenario in source_campaign.get("scenarios", []):
            scenario_index = int(source_scenario.get("index", -1))
            scenario_hash = str(source_scenario.get("sha256", ""))
            if scenario_index != len(missions):
                raise PortfolioManifestError(
                    f"campaign {campaign_index}: non-contiguous scenario index {scenario_index}"
                )
            if len(scenario_hash) != 64 or scenario_hash in seen_scenario_hashes:
                raise PortfolioManifestError(
                    f"campaign {campaign_index}, mission {scenario_index}: missing or duplicate source hash"
                )
            seen_scenario_hashes.add(scenario_hash)
            missions.append(
                {
                    "scenario_index": scenario_index,
                    "audit_match_id": f"audit_c{campaign_index:02d}_m{scenario_index:02d}",
                    "name": str(source_scenario.get("name", "")),
                    "filename": str(source_scenario.get("filename", "")),
                    "sha256": scenario_hash,
                    "active_player_count": int(
                        source_scenario.get("header", {}).get("active_player_count", 0)
                    ),
                }
            )
        declared_count = int(source_campaign.get("scenario_count", len(missions)))
        if declared_count != len(missions):
            raise PortfolioManifestError(
                f"campaign {campaign_index}: catalog count {declared_count} != {len(missions)}"
            )
        mission_count += len(missions)
        campaigns.append(
            {
                "campaign_index": campaign_index,
                "portfolio_id": f"source_campaign_{campaign_index:02d}",
                "source_path": str(source_campaign.get("source_path", "")),
                "filename": str(source_campaign.get("filename", "")),
                "name": str(source_campaign.get("name", "")),
                "extension": str(source_campaign.get("extension", "")),
                "sha256": campaign_hash,
                "mission_count": len(missions),
                "missions": missions,
            }
        )

    summary = catalog.get("summary", {})
    if len(campaigns) != int(summary.get("campaign_count", -1)):
        raise PortfolioManifestError("portfolio campaign count differs from source catalog")
    if mission_count != int(summary.get("campaign_scenario_count", -1)):
        raise PortfolioManifestError("portfolio mission count differs from source catalog")

    payload = {
        "schema_version": SCHEMA_VERSION,
        "generator_version": GENERATOR_VERSION,
        "source_catalog_sha256": sha256_file(args.catalog),
        "source_catalog_cache_key": str(catalog.get("cache", {}).get("key", "")),
        "summary": {
            "campaign_count": len(campaigns),
            "mission_count": mission_count,
        },
        "campaigns": campaigns,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"manifested {len(campaigns)} campaigns and {mission_count} missions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
