#!/usr/bin/env python3

"""Build a deterministic catalog of owned Rise of Rome scenarios and campaigns.

Only source metadata is decoded here. Full map/entity/trigger conversion belongs to
the following scenario content waves; this gate makes those waves traceable to an
immutable source file and never stores a machine-specific installation path.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
from pathlib import Path


CATALOG_SCHEMA_VERSION = 1
IMPORTER_VERSION = "scenario-catalog-1"
SCENARIO_EXTENSIONS = {".scn", ".scx"}
CAMPAIGN_EXTENSIONS = {".cpn", ".cpx"}
FORMAT_VERSION_PATTERN = re.compile(r"^[0-9]\.[0-9]{2}$")


class SourceFormatError(ValueError):
    """Raised when a source-owned scenario or campaign is structurally invalid."""


class Reader:
    def __init__(self, data: bytes, label: str) -> None:
        self.data = data
        self.label = label
        self.offset = 0

    def read(self, length: int) -> bytes:
        if length < 0 or self.offset + length > len(self.data):
            raise SourceFormatError(
                f"{self.label}: unexpected end at {self.offset}, requested {length} bytes"
            )
        result = self.data[self.offset : self.offset + length]
        self.offset += length
        return result

    def u32(self) -> int:
        return struct.unpack("<I", self.read(4))[0]

    def i32(self) -> int:
        return struct.unpack("<i", self.read(4))[0]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract deterministic RoR scenario/campaign source metadata."
    )
    parser.add_argument("--game", type=Path, required=True, help="Rise of Rome install root")
    parser.add_argument("--game-version", default="1.1")
    parser.add_argument("--encoding", default="cp1251", help="Legacy source string encoding")
    parser.add_argument("--output", type=Path, required=True, help="scenario-catalog.json")
    return parser.parse_args()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def decode_legacy(data: bytes, encoding: str) -> str:
    value = data.split(b"\0", 1)[0]
    if not value:
        return ""
    candidates = [encoding, "cp1252", "utf-8"]
    for candidate in dict.fromkeys(candidates):
        try:
            return value.decode(candidate)
        except UnicodeDecodeError:
            continue
    return value.decode(encoding, errors="replace")


def read_fixed_string(reader: Reader, length: int, encoding: str) -> str:
    return decode_legacy(reader.read(length), encoding)


def read_optional_u32_string(reader: Reader, encoding: str) -> str | None:
    length = reader.u32()
    if length == 0xFFFFFFFF:
        return None
    return decode_legacy(reader.read(length), encoding) if length > 0 else None


def parse_scenario_header(data: bytes, label: str, encoding: str) -> dict[str, object]:
    reader = Reader(data, label)
    try:
        format_version = reader.read(4).decode("ascii")
    except UnicodeDecodeError as error:
        raise SourceFormatError(f"{label}: non-ASCII scenario version") from error
    if not FORMAT_VERSION_PATTERN.fullmatch(format_version):
        raise SourceFormatError(f"{label}: unsupported scenario version {format_version!r}")

    header_size = reader.u32()
    header_version = reader.u32()
    timestamp = reader.u32() if header_version >= 2 else 0
    description = read_optional_u32_string(reader, encoding)
    any_single_player_victory = reader.u32() != 0
    active_player_count = reader.u32()
    if header_size <= 0 or header_size > len(data):
        raise SourceFormatError(
            f"{label}: header size {header_size} exceeds source size {len(data)}"
        )
    if active_player_count > 16:
        raise SourceFormatError(
            f"{label}: implausible active player count {active_player_count}"
        )
    return {
        "format_version": format_version,
        "header_size": header_size,
        "header_version": header_version,
        "timestamp": timestamp,
        "description": description or "",
        "any_single_player_victory": any_single_player_victory,
        "active_player_count": active_player_count,
    }


def relative_source_path(path: Path, game_root: Path) -> str:
    return path.relative_to(game_root).as_posix()


def standalone_record(path: Path, game_root: Path, encoding: str) -> dict[str, object]:
    data = path.read_bytes()
    relative_path = relative_source_path(path, game_root)
    return {
        "source_path": relative_path,
        "filename": path.name,
        "extension": path.suffix.lower(),
        "size": len(data),
        "sha256": sha256_bytes(data),
        "header": parse_scenario_header(data, relative_path, encoding),
    }


def campaign_record(path: Path, game_root: Path, encoding: str) -> dict[str, object]:
    data = path.read_bytes()
    relative_path = relative_source_path(path, game_root)
    reader = Reader(data, relative_path)
    try:
        format_version = reader.read(4).decode("ascii")
    except UnicodeDecodeError as error:
        raise SourceFormatError(f"{relative_path}: non-ASCII campaign version") from error
    if format_version != "1.00":
        raise SourceFormatError(
            f"{relative_path}: unsupported classic campaign version {format_version!r}"
        )
    campaign_name = read_fixed_string(reader, 256, encoding)
    scenario_count = reader.u32()
    if scenario_count <= 0 or scenario_count > 256:
        raise SourceFormatError(
            f"{relative_path}: implausible scenario count {scenario_count}"
        )

    entries: list[dict[str, object]] = []
    ranges: list[tuple[int, int]] = []
    for index in range(scenario_count):
        size = reader.i32()
        offset = reader.i32()
        name = read_fixed_string(reader, 255, encoding)
        filename = read_fixed_string(reader, 255, encoding)
        reader.read(2)
        if size <= 0 or offset < 0 or offset + size > len(data):
            raise SourceFormatError(
                f"{relative_path}: invalid entry {index} range offset={offset} size={size}"
            )
        current_range = (offset, offset + size)
        if any(current_range[0] < end and start < current_range[1] for start, end in ranges):
            raise SourceFormatError(f"{relative_path}: overlapping scenario entry {index}")
        ranges.append(current_range)
        scenario_data = data[offset : offset + size]
        entry_label = f"{relative_path}#{index}:{filename}"
        entries.append(
            {
                "index": index,
                "name": name,
                "filename": filename,
                "size": size,
                "sha256": sha256_bytes(scenario_data),
                "header": parse_scenario_header(scenario_data, entry_label, encoding),
            }
        )

    return {
        "source_path": relative_path,
        "filename": path.name,
        "extension": path.suffix.lower(),
        "size": len(data),
        "sha256": sha256_bytes(data),
        "format_version": format_version,
        "name": campaign_name,
        "scenario_count": scenario_count,
        "scenarios": entries,
    }


def source_files(folder: Path, extensions: set[str]) -> list[Path]:
    if not folder.is_dir():
        raise FileNotFoundError(f"source directory is missing: {folder}")
    return sorted(
        (path for path in folder.iterdir() if path.is_file() and path.suffix.lower() in extensions),
        key=lambda path: path.name.casefold(),
    )


def cache_record(records: list[dict[str, object]], game_version: str) -> dict[str, object]:
    source_hashes = {str(record["source_path"]): str(record["sha256"]) for record in records}
    components = {
        "source_sha256": source_hashes,
        "importer_version": IMPORTER_VERSION,
        "schema_version": CATALOG_SCHEMA_VERSION,
        "game_version": game_version,
    }
    encoded = json.dumps(components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"key": sha256_bytes(encoded), "components": components}


def main() -> int:
    args = parse_args()
    game_root = args.game.resolve()
    standalone = [
        standalone_record(path, game_root, args.encoding)
        for path in source_files(game_root / "scenario", SCENARIO_EXTENSIONS)
    ]
    campaigns = [
        campaign_record(path, game_root, args.encoding)
        for path in source_files(game_root / "campaign", CAMPAIGN_EXTENSIONS)
    ]
    all_sources = standalone + campaigns
    cache = cache_record(all_sources, args.game_version)
    if args.output.is_file():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if existing.get("cache", {}).get("key") == cache["key"]:
                print(f"scenario catalog cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError):
            pass

    embedded_count = sum(int(campaign["scenario_count"]) for campaign in campaigns)
    payload = {
        "format_version": CATALOG_SCHEMA_VERSION,
        "cache": cache,
        "source": {
            "game_version": args.game_version,
            "encoding": args.encoding,
            "scenario_directory": "scenario",
            "campaign_directory": "campaign",
        },
        "summary": {
            "standalone_scenario_count": len(standalone),
            "campaign_count": len(campaigns),
            "campaign_scenario_count": embedded_count,
            "source_file_count": len(all_sources),
        },
        "standalone_scenarios": standalone,
        "campaigns": campaigns,
        "validation": {"errors": [], "status": "valid"},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"exported {len(standalone)} standalone scenarios and {len(campaigns)} campaigns "
        f"({embedded_count} embedded scenarios) to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
