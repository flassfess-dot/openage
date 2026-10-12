"""Summarize saved AI measurement reports; never launches the game."""
from __future__ import annotations
import argparse
import json
import math
import statistics
from pathlib import Path


def load(directory: Path) -> dict[tuple, dict]:
    rows = {}
    for path in sorted(directory.glob("*.json")):
        row = json.loads(path.read_text(encoding="utf-8"))
        if row.get("schema_version") != 1 or "matrix_sha256" not in row:
            continue
        if row.get("error"):
            continue
        key = (row["matrix_sha256"], int(row["case_id"]), bool(row["threaded"]))
        if key in rows:
            raise ValueError(f"Duplicate measured case: {key}")
        rows[key] = row
    return rows


def wilson(wins: int, n: int) -> list[float] | None:
    if not n:
        return None
    z = 1.959963984540054
    p = wins / n
    denominator = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denominator
    radius = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denominator
    return [max(0.0, center - radius), min(1.0, center + radius)]


def metrics(row: dict) -> dict:
    player = next(p for p in row["players"] if p["team"] == row["subject_team"])
    return player["metrics"]


def summarize(rows: dict) -> dict:
    values = list(rows.values())
    wins = sum(r["outcome"] == "win" for r in values)
    return {
        "measured_cases": len(values),
        "wins": wins,
        "losses": sum(r["outcome"] == "loss" for r in values),
        "draws": sum(r["outcome"] == "draw" for r in values),
        "win_fraction": wins / len(values) if values else None,
        "wilson_95_percent": wilson(wins, len(values)),
        "median_idle_worker_ratio": statistics.median(metrics(r)["idle_worker_ratio"] for r in values) if values else None,
        "median_command_rejection_ratio": statistics.median(metrics(r)["command_rejection_ratio"] for r in values) if values else None,
        "interpretation": "Timeouts count as draws. Different seeds, factions and starts are pooled; inspect strata before claiming improvement.",
    }


def paired(before: dict, after: dict) -> dict:
    common = sorted(before.keys() & after.keys())
    differences = {}
    for field in ["idle_worker_ratio", "command_rejection_ratio", "losses", "budget_rejections"]:
        delta = [float(metrics(after[k])[field]) - float(metrics(before[k])[field]) for k in common]
        differences[field] = {"mean_after_minus_before": statistics.mean(delta) if delta else None,
                              "median_after_minus_before": statistics.median(delta) if delta else None}
    return {"matched_cases": len(common), "unmatched_before": len(before) - len(common),
            "unmatched_after": len(after) - len(common), "differences": differences}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path)
    parser.add_argument("--before", type=Path)
    args = parser.parse_args()
    rows = load(args.reports)
    output = {"summary": summarize(rows), "strata": {}}
    for field in ["map_type_ids", "resource_preset_ids", "starting_age_ids", "difficulty_ids", "opponent_policy_ids"]:
        labels = sorted({r["case"][field] for r in rows.values()})
        output["strata"][field] = {label: summarize({k: r for k, r in rows.items() if r["case"][field] == label}) for label in labels}
    if args.before:
        output["paired_comparison"] = paired(load(args.before), rows)
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
