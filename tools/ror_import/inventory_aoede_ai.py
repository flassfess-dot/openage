#!/usr/bin/env python3

"""Create a portable, derived AoE DE AI/PER evidence ledger.

The source installation is read-only. The output intentionally excludes the
absolute installation path and verbatim AI build-order lines.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from build_scenario_match import (
    SOURCE_AI_STRATEGIC_CAPABILITIES,
    strategic_number_runtime_semantics,
)


SCHEMA_VERSION = 1
IMPORTER_VERSION = "aoede-ai-evidence-1"
AI_ENTRY = re.compile(
    r"^(?P<opcode>[A-Z]+)(?P<source_id>\d+)\s+.+?\s+"
    r"(?P<amount>-?\d+)\s+(?P<producer>-?\d+)"
    r"(?:\s+(?P<parameter>-?\d+))?\s*$",
    re.IGNORECASE,
)
PER_ENTRY = re.compile(
    r"^(?P<source_id>\d+)\s+(?P<value>-?\d+)"
    r"(?:\s*//\s*(?P<name>.*?))?\s*$"
)
PER_LEGACY_DIRECTIVE = re.compile(
    r"^(?P<opcode>[A-Z]+)\s+(?P<source_id>\d+)\s+(?P<value>-?\d+)\s*$",
    re.IGNORECASE,
)
VALID_AI_OPCODES = {"B", "C", "R", "T", "U"}
CIVILIZATION_TOKENS = {
    "EGYPT": 1,
    "GREEK": 2,
    "BABYLON": 3,
    "ASSYRIA": 4,
    "MINOAN": 5,
    "HITTITE": 6,
    "PHOENICIA": 7,
    "SUMER": 8,
    "PERSIA": 9,
    "SHANG": 10,
    "YAMATO": 11,
    "CHOSON": 12,
    "ROME": 13,
    "ROMAN": 13,
    "CARTHAGE": 14,
    "PALMYRA": 15,
    "MACEDON": 16,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def classify_name(path: Path) -> dict[str, Any]:
    name = path.stem.upper()
    civilizations = sorted(
        {civilization_id for token, civilization_id in CIVILIZATION_TOKENS.items() if token in name}
    )
    return {
        "civilization_ids": civilizations,
        "water": "WATER" in name or "NAVAL" in name,
        "death_match": "DEATH MATCH" in name,
    }


def parse_ai(path: Path, root: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    opcode_counts: Counter[str] = Counter()
    unique_ids: dict[str, set[int]] = {opcode: set() for opcode in sorted(VALID_AI_OPCODES)}
    maximum_amount: dict[str, int] = {}
    producer_ids: set[int] = set()
    anomaly_records: list[dict[str, Any]] = []
    entry_count = 0
    for line_number, raw_line in enumerate(read_text(path).splitlines(), 1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        match = AI_ENTRY.match(stripped)
        if match is None:
            anomaly_records.append(
                {
                    "relative_path": relative(path, root),
                    "line": line_number,
                    "reason": "unparsed_ai_entry",
                    "line_sha256": hashlib.sha256(stripped.encode("utf-8")).hexdigest(),
                }
            )
            continue
        source_opcode = match.group("opcode").upper()
        opcode = source_opcode if source_opcode in VALID_AI_OPCODES else "unknown"
        if opcode == "unknown":
            anomaly_records.append(
                {
                    "relative_path": relative(path, root),
                    "line": line_number,
                    "reason": f"unknown_ai_opcode:{source_opcode}",
                    "line_sha256": hashlib.sha256(stripped.encode("utf-8")).hexdigest(),
                }
            )
            continue
        entry_count += 1
        source_id = int(match.group("source_id"))
        amount = int(match.group("amount"))
        producer = int(match.group("producer"))
        opcode_counts[opcode] += 1
        unique_ids[opcode].add(source_id)
        maximum_amount[opcode] = max(maximum_amount.get(opcode, amount), amount)
        if producer >= 0:
            producer_ids.add(producer)
    return (
        {
            "relative_path": relative(path, root),
            "sha256": sha256(path),
            "size": path.stat().st_size,
            "entry_count": entry_count,
            "opcode_counts": dict(sorted(opcode_counts.items())),
            "unique_source_ids": {
                opcode: sorted(values) for opcode, values in unique_ids.items() if values
            },
            "maximum_requested_amount": dict(sorted(maximum_amount.items())),
            "producer_source_ids": sorted(producer_ids),
            "classification": classify_name(path),
            "parse_anomaly_count": len(anomaly_records),
        },
        anomaly_records,
    )


def parse_per(path: Path, root: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    entries: list[dict[str, Any]] = []
    legacy_directives: list[dict[str, Any]] = []
    anomalies: list[dict[str, Any]] = []
    seen: Counter[int] = Counter()
    has_default = False
    has_end = False
    for line_number, raw_line in enumerate(read_text(path).splitlines(), 1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if stripped.upper() == "DEFAULT":
            has_default = True
            continue
        if stripped.upper() == "END":
            has_end = True
            continue
        match = PER_ENTRY.match(stripped)
        if match is None:
            directive = PER_LEGACY_DIRECTIVE.match(stripped)
            if directive is not None:
                legacy_directives.append(
                    {
                        "opcode": directive.group("opcode").upper(),
                        "source_id": int(directive.group("source_id")),
                        "value": int(directive.group("value")),
                    }
                )
                continue
            anomalies.append(
                {
                    "relative_path": relative(path, root),
                    "line": line_number,
                    "reason": "unparsed_per_entry",
                    "line_sha256": hashlib.sha256(stripped.encode("utf-8")).hexdigest(),
                }
            )
            continue
        source_id = int(match.group("source_id"))
        name = (match.group("name") or "").strip()
        seen[source_id] += 1
        entries.append(
            {
                "source_id": source_id,
                "value": int(match.group("value")),
                "name": name,
                "capability": SOURCE_AI_STRATEGIC_CAPABILITIES.get(source_id, "unclassified"),
                "runtime_semantics": strategic_number_runtime_semantics(source_id, name),
            }
        )
    capability_counts = Counter(entry["capability"] for entry in entries)
    semantics_counts = Counter(entry["runtime_semantics"] for entry in entries)
    return (
        {
            "relative_path": relative(path, root),
            "sha256": sha256(path),
            "size": path.stat().st_size,
            "has_default_marker": has_default,
            "has_end_marker": has_end,
            "entry_count": len(entries),
            "duplicate_source_ids": sorted(source_id for source_id, count in seen.items() if count > 1),
            "capability_counts": dict(sorted(capability_counts.items())),
            "runtime_semantics_counts": dict(sorted(semantics_counts.items())),
            "entries": entries,
            "legacy_directives": legacy_directives,
            "classification": classify_name(path),
            "parse_anomaly_count": len(anomalies),
        },
        anomalies,
    )


def optional_file(root: Path, relative_path: str) -> dict[str, Any]:
    path = root / relative_path
    if not path.is_file():
        return {"relative_path": relative_path, "present": False}
    return {
        "relative_path": relative_path,
        "present": True,
        "size": path.stat().st_size,
        "sha256": sha256(path),
    }


def build_ledger(root: Path) -> dict[str, Any]:
    build_path = root / "build.txt"
    ai_files = sorted(root.rglob("*.ai"), key=lambda path: relative(path, root).casefold())
    per_files = sorted(root.rglob("*.per"), key=lambda path: relative(path, root).casefold())
    ai_profiles: list[dict[str, Any]] = []
    per_profiles: list[dict[str, Any]] = []
    anomalies: list[dict[str, Any]] = []
    for path in ai_files:
        profile, profile_anomalies = parse_ai(path, root)
        ai_profiles.append(profile)
        anomalies.extend(profile_anomalies)
    for path in per_files:
        profile, profile_anomalies = parse_per(path, root)
        per_profiles.append(profile)
        anomalies.extend(profile_anomalies)
    aggregate_opcodes: Counter[str] = Counter()
    for profile in ai_profiles:
        aggregate_opcodes.update(profile["opcode_counts"])
    aggregate_semantics: Counter[str] = Counter()
    for profile in per_profiles:
        aggregate_semantics.update(profile["runtime_semantics_counts"])
    return {
        "schema_version": SCHEMA_VERSION,
        "importer_version": IMPORTER_VERSION,
        "source_id": "aoede-reference",
        "source_role": "secondary_evidence_no_runtime_authority",
        "build": read_text(build_path).strip() if build_path.is_file() else "unknown",
        "source_files": {
            "executable": optional_file(root, "AoEDE_s.exe"),
            "empires_orig": optional_file(root, "Data/empires-orig.dat"),
            "empires_classic": optional_file(root, "Data/empires_classic.dat"),
            "empires_de": optional_file(root, "Data/empires.dat"),
        },
        "summary": {
            "ai_profile_count": len(ai_profiles),
            "per_profile_count": len(per_profiles),
            "ai_entry_count": sum(profile["entry_count"] for profile in ai_profiles),
            "per_entry_count": sum(profile["entry_count"] for profile in per_profiles),
            "ai_opcode_counts": dict(sorted(aggregate_opcodes.items())),
            "per_runtime_semantics_counts": dict(sorted(aggregate_semantics.items())),
            "parse_anomaly_count": len(anomalies),
        },
        "ai_profiles": ai_profiles,
        "per_profiles": per_profiles,
        "parse_anomalies": anomalies,
    }


def serialized(ledger: dict[str, Any]) -> str:
    return json.dumps(ledger, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="AoE DE installation root")
    parser.add_argument("--output", required=True, type=Path, help="Portable JSON evidence path")
    parser.add_argument("--check", action="store_true", help="Fail when output differs; do not write")
    args = parser.parse_args()
    root = args.source.resolve()
    if not (root / "AoEDE_s.exe").is_file() or not (root / "CP_AI").is_dir():
        print("AoE DE source root is missing AoEDE_s.exe or CP_AI", file=sys.stderr)
        return 2
    content = serialized(build_ledger(root))
    if args.check:
        if not args.output.is_file() or args.output.read_text(encoding="utf-8") != content:
            print(f"stale AoE DE AI evidence: {args.output}", file=sys.stderr)
            return 1
        print(f"AoE DE AI evidence is current: {args.output}")
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8", newline="\n")
    print(
        "AoE DE AI evidence: "
        f"{len(json.loads(content)['ai_profiles'])} AI / "
        f"{len(json.loads(content)['per_profiles'])} PER -> {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
