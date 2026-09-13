#!/usr/bin/env python3

"""Convert and audit every source campaign mission with bounded parallelism."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit the complete source campaign portfolio.")
    parser.add_argument("--game-path", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--objects", type=Path, required=True)
    parser.add_argument("--runtime-catalog", type=Path, required=True)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--archetypes", type=Path, required=True)
    parser.add_argument("--converter", type=Path, required=True)
    parser.add_argument("--match-builder", type=Path, required=True)
    parser.add_argument("--matrix-builder", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=4)
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected a JSON object")
    return value


def require_file(path: Path, label: str) -> Path:
    resolved = path.resolve(strict=True)
    if not resolved.is_file():
        raise ValueError(f"{label} is not a file: {resolved}")
    return resolved


def source_campaign_path(campaign_root: Path, relative_source: str) -> Path:
    source_name = Path(relative_source).name
    resolved = (campaign_root / source_name).resolve(strict=True)
    if campaign_root not in resolved.parents:
        raise ValueError(f"campaign escapes the configured source root: {resolved}")
    return resolved


def run_checked(arguments: list[str], label: str) -> None:
    completed = subprocess.run(
        arguments,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"{label} failed ({completed.returncode})\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )


def stable_failure_reason(error: RuntimeError) -> str:
    lines = [line.strip() for line in str(error).splitlines() if line.strip()]
    for line in reversed(lines):
        if "Error:" in line:
            return line
    return lines[0] if lines else "unknown conversion failure"


def write_failure_record(
    match_path: Path,
    stage: str,
    reason: str,
    mission: dict[str, Any],
    raw: dict[str, Any] | None = None,
) -> None:
    raw = raw or {}
    players = raw.get("players", [])
    payload = {
        "portfolio_audit_failure": {
            "stage": stage,
            "reason": reason,
        },
        "source": raw.get(
            "source",
            {
                "scenario_index": int(mission.get("scenario_index", -1)),
                "scenario_name": str(mission.get("name", "")),
                "scenario_filename": str(mission.get("filename", "")),
                "scenario_sha256": str(mission.get("sha256", "")),
            },
        ),
        "raw_summary": {
            "map_size": raw.get("map", {}).get("size", []),
            "source_object_count": len(raw.get("objects", [])),
            "active_player_count": sum(
                1 for player in players if bool(player.get("active", False))
            ),
            "source_ai_profile_count": sum(
                1
                for player in players
                if bool(player.get("active", False))
                and (
                    player.get("source_ai", {}).get("embedded_rules")
                    or player.get("source_ai", {}).get("embedded_build_list")
                    or player.get("source_ai", {}).get("rule_name")
                    or player.get("source_ai", {}).get("build_list_name")
                )
            ),
            "deferred_scenario_logic": raw.get("deferred_scenario_logic", {}),
        },
    }
    match_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def convert_mission(
    converter: Path,
    match_builder: Path,
    campaign_path: Path,
    campaign_index: int,
    mission: dict[str, Any],
    temporary_root: Path,
    catalog: Path,
    archetypes: Path,
    objects: Path,
) -> str:
    scenario_index = int(mission.get("scenario_index", -1))
    label = f"c{campaign_index:02d}/m{scenario_index:02d}"
    mission_root = temporary_root / f"c{campaign_index:02d}"
    mission_root.mkdir(parents=True, exist_ok=True)
    raw_path = mission_root / f"m{scenario_index:02d}.raw.json"
    match_path = mission_root / f"m{scenario_index:02d}.json"
    try:
        run_checked(
            [
                str(converter),
                "--campaign",
                str(campaign_path),
                "--scenario-index",
                str(scenario_index),
                "--output",
                str(raw_path),
            ],
            f"raw conversion {label}",
        )
    except RuntimeError as error:
        write_failure_record(
            match_path, "raw_conversion", stable_failure_reason(error), mission
        )
        return f"{label} raw-conversion-blocked"
    raw = read_json(raw_path)
    try:
        run_checked(
            [
                sys.executable,
                str(match_builder),
                "--raw",
                str(raw_path),
                "--catalog",
                str(catalog),
                "--archetypes",
                str(archetypes),
                "--objects",
                str(objects),
                "--match-id",
                str(mission.get("audit_match_id", "")),
                "--output",
                str(match_path),
            ],
            f"runtime normalization {label}",
        )
    except RuntimeError as error:
        write_failure_record(
            match_path,
            "runtime_normalization",
            stable_failure_reason(error),
            mission,
            raw,
        )
        raw_path.unlink()
        return f"{label} normalization-blocked"
    raw_path.unlink()
    return label


def main() -> int:
    args = parse_args()
    if args.workers < 1 or args.workers > 16:
        raise ValueError("--workers must be between 1 and 16")
    campaign_root = (args.game_path / "campaign").resolve(strict=True)
    manifest_path = require_file(args.manifest, "portfolio manifest")
    catalog_path = require_file(args.catalog, "scenario catalog")
    object_path = require_file(args.objects, "object catalog")
    runtime_catalog_path = require_file(args.runtime_catalog, "runtime catalog")
    archetypes_path = require_file(args.archetypes, "runtime archetypes")
    converter_path = require_file(args.converter, "scenario converter")
    match_builder_path = require_file(args.match_builder, "match builder")
    matrix_builder_path = require_file(args.matrix_builder, "matrix builder")
    assets_root = args.assets_root.resolve(strict=True)
    manifest = read_json(manifest_path)
    jobs: list[tuple[int, Path, dict[str, Any]]] = []
    for campaign in manifest.get("campaigns", []):
        campaign_index = int(campaign.get("campaign_index", -1))
        campaign_path = source_campaign_path(
            campaign_root, str(campaign.get("source_path", ""))
        )
        for mission in campaign.get("missions", []):
            jobs.append((campaign_index, campaign_path, mission))

    with tempfile.TemporaryDirectory(prefix="ror-campaign-portfolio-") as temporary:
        temporary_root = Path(temporary).resolve()
        completed_count = 0
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = [
                executor.submit(
                    convert_mission,
                    converter_path,
                    match_builder_path,
                    campaign_path,
                    campaign_index,
                    mission,
                    temporary_root,
                    catalog_path,
                    archetypes_path,
                    object_path,
                )
                for campaign_index, campaign_path, mission in jobs
            ]
            for future in as_completed(futures):
                label = future.result()
                completed_count += 1
                print(f"portfolio {completed_count}/{len(jobs)}: {label}", flush=True)

        run_checked(
            [
                sys.executable,
                str(matrix_builder_path),
                "--manifest",
                str(manifest_path),
                "--catalog",
                str(catalog_path),
                "--runtime-catalog",
                str(runtime_catalog_path),
                "--assets-root",
                str(assets_root),
                "--matches-directory",
                str(temporary_root),
                "--output",
                str(args.output.resolve()),
            ],
            "portfolio matrix aggregation",
        )
    print(f"portfolio audit complete: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
