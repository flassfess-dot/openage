#!/usr/bin/env python3

"""Validate generated Rise of Rome catalogs and write JSON/Markdown reports."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

REPORT_SCHEMA_VERSION = 3
IMPORTER_VERSION = "cache-validator-3"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the generated RoR cache.")
    parser.add_argument("--cache-dir", type=Path, required=True)
    parser.add_argument("--game", type=Path, help="Kept for launcher compatibility; validation uses the generated catalogs")
    parser.add_argument("--runtime", type=Path, help="Normalized runtime catalog; defaults to cache-dir/runtime-catalog.json")
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--markdown-output", type=Path, required=True)
    return parser.parse_args()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def add_issue(collection: list[dict[str, object]], **values) -> None:
    collection.append(values)


def normalized_effect_type(raw_type: int) -> int:
    if raw_type in range(10, 17):
        return raw_type - 10
    if raw_type in range(20, 27):
        return raw_type - 20
    return raw_type


def runtime_candidate_unit_ids(object_catalog: dict[str, object]) -> set[int]:
    objects = object_catalog.get("objects", {})
    candidates = {
        int(record.get("unit_id", -1))
        for record in objects.values()
        if record.get("enabled", False) and int(record.get("unit_id", -1)) >= 0
    }
    for bundle in object_catalog.get("effect_bundles", {}).values():
        for command in bundle.get("commands", []):
            effect_type = normalized_effect_type(int(command.get("type_id", -1)))
            if effect_type == 2 and int(command.get("attr_b", 0)) != 0:
                candidates.add(int(command.get("attr_a", -1)))
            elif effect_type == 3 and int(command.get("attr_b", -1)) >= 0:
                candidates.add(int(command["attr_b"]))

    changed = True
    while changed:
        changed = False
        for record in objects.values():
            if int(record.get("unit_id", -1)) not in candidates:
                continue
            linked_ids = [int(record.get("combat", {}).get("projectile_id", -1))]
            if int(record.get("unit_type", -1)) != 60:
                linked_ids.extend(int(record.get("links", {}).get(field, -1)) for field in ("dead_unit_id", "stack_unit_id"))
            for linked_id in linked_ids:
                if linked_id >= 0 and linked_id not in candidates:
                    candidates.add(linked_id)
                    changed = True
    return candidates


def enabled_object_graphic_roots(objects: dict[str, object], candidate_unit_ids: set[int]) -> tuple[set[int], dict[int, list[dict[str, object]]]]:
    roots: set[int] = set()
    references: dict[int, list[dict[str, object]]] = {}
    for object_key, record in objects.items():
        if int(record.get("unit_id", -1)) not in candidate_unit_ids:
            continue
        for field, value in record.get("graphics", {}).items():
            if field == "damage" or not isinstance(value, (int, float)):
                continue
            graphic_id = int(value)
            if graphic_id < 0:
                continue
            roots.add(graphic_id)
            references.setdefault(graphic_id, []).append({"object_key": object_key, "field": field})
    return roots, references


def reachable_graphic_ids(graphics: dict[str, object], roots: set[int]) -> set[int]:
    reachable = set(roots)
    pending = sorted(roots, reverse=True)
    while pending:
        graphic_id = pending.pop()
        graphic = graphics.get(str(graphic_id), {})
        for delta in graphic.get("deltas", []):
            target_id = int(delta.get("graphic_id", -1))
            if target_id >= 0 and target_id not in reachable:
                reachable.add(target_id)
                pending.append(target_id)
    return reachable


def sound_binding_is_active(binding: dict[str, object], objects: dict[str, object], candidate_unit_ids: set[int], reachable_graphics: set[int]) -> bool:
    source = str(binding.get("source", ""))
    if source.startswith("object "):
        record = objects.get(source.removeprefix("object "), {})
        return int(record.get("unit_id", -1)) in candidate_unit_ids
    if source.startswith("graphic "):
        try:
            return int(source.removeprefix("graphic ")) in reachable_graphics
        except ValueError:
            return False
    return False


def dependency_cycles(adjacency: dict[int, set[int]], source: str) -> list[dict[str, object]]:
    cycles: list[dict[str, object]] = []
    visiting: set[int] = set()
    visited: set[int] = set()
    stack: list[int] = []
    seen_cycles: set[tuple[int, ...]] = set()

    def visit(node: int) -> None:
        if node in visited:
            return
        if node in visiting:
            start = stack.index(node)
            cycle = stack[start:] + [node]
            normalized = tuple(cycle[:-1])
            rotations = [normalized[index:] + normalized[:index] for index in range(len(normalized))]
            identity = min(rotations) if rotations else ()
            if identity not in seen_cycles:
                seen_cycles.add(identity)
                cycles.append({"source": source, "path": cycle})
            return
        visiting.add(node)
        stack.append(node)
        for target in sorted(adjacency.get(node, set())):
            visit(target)
        stack.pop()
        visiting.remove(node)
        visited.add(node)

    for node in sorted(adjacency):
        visit(node)
    return cycles


def coverage_summary(
    graphics_catalog: dict[str, object],
    object_catalog: dict[str, object],
    sound_catalog: dict[str, object],
    localization_catalog: dict[str, object],
) -> dict[str, int]:
    graphics = graphics_catalog.get("graphics", {})
    objects = object_catalog.get("objects", {})
    candidate_unit_ids = runtime_candidate_unit_ids(object_catalog)
    candidate_records = [
        record
        for record in objects.values()
        if int(record.get("unit_id", -1)) in candidate_unit_ids
    ]
    roots, _ = enabled_object_graphic_roots(objects, candidate_unit_ids)
    reachable = reachable_graphic_ids(graphics, roots)
    fallback_language = str(localization_catalog.get("fallback_language", "en"))
    fallback_strings = localization_catalog.get("languages", {}).get(fallback_language, {}).get("strings", {})
    player_facing = [
        record
        for record in candidate_records
        if int(record.get("unit_type", -1)) != 60
    ]
    icon_required = [
        record
        for record in candidate_records
        if (
            int(record.get("interface", {}).get("button_id", -1)) >= 0
            or int(record.get("production", {}).get("train_location_id", -1)) >= 0
        )
    ]
    active_sounds = [
        sound
        for sound in sound_catalog.get("sounds", {}).values()
        if any(sound_binding_is_active(binding, objects, candidate_unit_ids, reachable) for binding in sound.get("event_bindings", []))
    ]
    resource_graphics = [
        graphic_id
        for graphic_id in reachable
        if int(graphics.get(str(graphic_id), {}).get("slp_id", -1)) >= 0
    ]
    resource_sounds = [
        sound
        for sound in active_sounds
        if any(int(item.get("resource_id", -1)) >= 0 for item in sound.get("items", []))
    ]

    def has_name(record: dict[str, object]) -> bool:
        name_id = int(record.get("language", {}).get("name_id", -1))
        return name_id not in (-1, 0, 65535) and str(name_id) in fallback_strings

    return {
        "enabled_objects": sum(1 for record in objects.values() if record.get("enabled", False)),
        "runtime_candidate_objects": len(candidate_records),
        "runtime_candidate_unit_ids": len(candidate_unit_ids),
        "player_facing_objects": len(player_facing),
        "player_facing_objects_with_name": sum(1 for record in player_facing if has_name(record)),
        "objects_requiring_icon": len(icon_required),
        "objects_with_required_icon": sum(1 for record in icon_required if int(record.get("interface", {}).get("icon_id", -1)) >= 0),
        "reachable_graphics": len(reachable),
        "reachable_resource_graphics": len(resource_graphics),
        "reachable_resource_graphics_with_slp": sum(1 for graphic_id in resource_graphics if graphics.get(str(graphic_id), {}).get("slp", {}).get("valid", False)),
        "active_logical_sounds": len(active_sounds),
        "active_resource_sounds": len(resource_sounds),
        "active_resource_sounds_with_audio": sum(
            1
            for sound in resource_sounds
            if any(item.get("audio", {}).get("valid", False) for item in sound.get("items", []))
        ),
    }


def validate_runtime_catalog(runtime_catalog: dict[str, object], object_catalog: dict[str, object]) -> list[dict[str, object]]:
    findings: list[dict[str, object]] = []
    objects = object_catalog.get("objects", {})
    internal_ids: set[str] = set()
    presentation_ids: set[str] = set()
    valid_categories = {"unit", "building", "resource", "objective", "projectile"}
    for alias, definition in runtime_catalog.get("archetypes", {}).items():
        identifiers = definition.get("identifiers", {})
        internal_id = str(identifiers.get("internal_id", ""))
        presentation_id = str(identifiers.get("presentation_id", ""))
        source_unit_id = int(identifiers.get("source_unit_id", -1))
        category = str(definition.get("category", ""))
        for namespace, value, seen in (
            ("internal_id", internal_id, internal_ids),
            ("presentation_id", presentation_id, presentation_ids),
        ):
            if not value:
                add_issue(findings, archetype=alias, field=namespace, reason="missing_identifier")
            elif value in seen:
                add_issue(findings, archetype=alias, field=namespace, value=value, reason="duplicate_identifier")
            seen.add(value)
        if source_unit_id < 0:
            add_issue(findings, archetype=alias, field="source_unit_id", reason="invalid_identifier")
        if category not in valid_categories:
            add_issue(findings, archetype=alias, field="category", value=category, reason="unsupported_category")
        records = definition.get("records", {})
        if not records:
            add_issue(findings, archetype=alias, field="records", reason="missing_records")
        for civilization_id, normalized in records.items():
            source_key = str(normalized.get("source_key", ""))
            source = objects.get(source_key, {})
            if not source:
                add_issue(findings, archetype=alias, civilization_id=civilization_id, field="source_key", value=source_key, reason="unknown_source_record")
            elif int(source.get("unit_id", -1)) != source_unit_id:
                add_issue(findings, archetype=alias, civilization_id=civilization_id, field="source_unit_id", value=source_unit_id, reason="source_id_mismatch")
    if int(runtime_catalog.get("archetype_count", -1)) != len(runtime_catalog.get("archetypes", {})):
        add_issue(findings, field="archetype_count", reason="count_mismatch")
    return findings


def validate(
    graphics_catalog: dict[str, object],
    object_catalog: dict[str, object],
    sound_catalog: dict[str, object],
    localization_catalog: dict[str, object],
) -> dict[str, object]:
    graphics = graphics_catalog.get("graphics", {})
    objects = object_catalog.get("objects", {})
    technologies = object_catalog.get("technologies", {})
    effect_bundles = object_catalog.get("effect_bundles", {})
    issues = {
        "missing_slp": [],
        "missing_audio": [],
        "unknown_ids": [],
        "broken_deltas": [],
        "dependency_cycles": [],
        "missing_name_or_icon": [],
        "suspicious_values": [],
    }

    candidate_unit_ids = runtime_candidate_unit_ids(object_catalog)
    graphic_roots, graphic_references = enabled_object_graphic_roots(objects, candidate_unit_ids)
    reachable_graphics = reachable_graphic_ids(graphics, graphic_roots)

    for missing in graphics_catalog.get("missing_slp", []):
        graphic_id = int(missing.get("graphic_id", -1))
        is_reachable = graphic_id in reachable_graphics
        add_issue(
            issues["missing_slp"],
            **missing,
            classification="owned_source_gap",
            impact="runtime_candidate_reference" if is_reachable else "inactive_or_unreferenced",
            reachable=is_reachable,
            direct_references=graphic_references.get(graphic_id, []),
        )

    # A sound ID addresses the logical sound table, not a WAV resource directly.
    # The sound catalog has already resolved every variant through the layered DRS
    # archives, so use its exact missing variants instead of comparing unlike IDs.
    for missing in sound_catalog.get("missing_audio", []):
        sound_id = int(missing.get("sound_id", -1))
        sound = sound_catalog.get("sounds", {}).get(str(sound_id), {})
        active_bindings = [
            binding
            for binding in sound.get("event_bindings", [])
            if sound_binding_is_active(binding, objects, candidate_unit_ids, reachable_graphics)
        ]
        fallback_available = any(
            bool(item.get("audio", {}).get("valid", False))
            for item in sound.get("items", [])
        )
        add_issue(
            issues["missing_audio"],
            **missing,
            classification="owned_source_gap",
            impact=(
                "active_binding_with_fallback"
                if active_bindings and fallback_available
                else "active_binding_without_audio"
                if active_bindings
                else "inactive_or_unreferenced"
            ),
            active_binding_count=len(active_bindings),
            fallback_available=fallback_available,
        )
    for sound_id in sound_catalog.get("unresolved_sound_ids", []):
        if isinstance(sound_id, dict):
            add_issue(issues["unknown_ids"], **sound_id)
        else:
            add_issue(issues["unknown_ids"], source="sound catalog", field="sound_id", target_id=int(sound_id))

    # Object IDs are shared across civilizations. Some civ-specific records link
    # to a base record that legitimately lives under a different civilization.
    known_unit_ids = {int(record.get("unit_id", -1)) for record in objects.values()}
    fallback_language = str(localization_catalog.get("fallback_language", "en"))
    fallback_strings = localization_catalog.get("languages", {}).get(fallback_language, {}).get("strings", {})

    graphic_adjacency: dict[int, set[int]] = {}
    for graphic_key, graphic in graphics.items():
        source_graphic_id = int(graphic_key)
        graphic_adjacency.setdefault(source_graphic_id, set())
        for delta in graphic.get("deltas", []):
            target_id = int(delta.get("graphic_id", -1))
            if target_id >= 0 and str(target_id) not in graphics:
                add_issue(issues["broken_deltas"], graphic_id=int(graphic_key), target_graphic_id=target_id)
            elif target_id >= 0:
                graphic_adjacency[source_graphic_id].add(target_id)
        slp = graphic.get("slp", {})
        if slp.get("valid", False):
            angle_count = int(graphic.get("angle_count", 0))
            frames_per_angle = int(graphic.get("frames_per_angle", 0))
            slp_frame_count = int(slp.get("frame_count", 0))
            implicit_static_frame = angle_count == 0 and frames_per_angle == 0 and slp_frame_count == 1
            if (angle_count <= 0 or frames_per_angle <= 0) and not implicit_static_frame:
                add_issue(issues["suspicious_values"], source=f"graphic {graphic_key}", field="direction_or_frame_count", value=[graphic.get("angle_count"), graphic.get("frames_per_angle")])
            if float(graphic.get("frame_rate", 0.0)) < 0.0:
                add_issue(issues["suspicious_values"], source=f"graphic {graphic_key}", field="frame_rate", value=graphic.get("frame_rate"))
            for frame in slp.get("frames", []):
                width = int(frame.get("width", 0))
                height = int(frame.get("height", 0))
                if width <= 0 or height <= 0 or width > 4096 or height > 4096:
                    add_issue(issues["suspicious_values"], source=f"graphic {graphic_key} frame {frame.get('index')}", field="dimensions", value=[width, height])

    for object_key, record in objects.items():
        for field, graphic_id in record.get("graphics", {}).items():
            if field == "damage" or not isinstance(graphic_id, (int, float)):
                continue
            numeric = int(graphic_id)
            if numeric >= 0 and str(numeric) not in graphics:
                add_issue(issues["unknown_ids"], source=f"object {object_key}", field=f"graphics.{field}", target_id=numeric)
        # Projectile records inherit dead/stack link slots in the DAT layout, but
        # the RoR runtime does not consume them as entity lifecycle references.
        if int(record.get("unit_type", -1)) != 60:
            for field in ("dead_unit_id", "stack_unit_id"):
                target_id = int(record.get("links", {}).get(field, -1))
                if target_id >= 0 and target_id not in known_unit_ids:
                    add_issue(issues["unknown_ids"], source=f"object {object_key}", field=f"links.{field}", target_id=target_id)
        name_id = int(record.get("language", {}).get("name_id", -1))
        icon_id = int(record.get("interface", {}).get("icon_id", -1))
        button_id = int(record.get("interface", {}).get("button_id", -1))
        train_location_id = int(record.get("production", {}).get("train_location_id", -1))
        runtime_candidate = int(record.get("unit_id", -1)) in candidate_unit_ids
        unit_type = int(record.get("unit_type", -1))
        fallback_name_available = name_id not in (-1, 0, 65535) and str(name_id) in fallback_strings
        name_required = runtime_candidate and unit_type != 60
        icon_required = runtime_candidate and (button_id >= 0 or train_location_id >= 0)
        if (name_required and not fallback_name_available) or (icon_required and icon_id < 0):
            add_issue(
                issues["missing_name_or_icon"],
                object_key=object_key,
                name_id=name_id,
                fallback_name_available=fallback_name_available,
                icon_id=icon_id,
                name_required=name_required,
                icon_required=icon_required,
            )
        health = float(record.get("health", 0.0))
        speed = float(record.get("speed", 0.0))
        range_min = float(record.get("combat", {}).get("range_min", 0.0))
        range_max = float(record.get("combat", {}).get("range_max", 0.0))
        if health < 0.0:
            add_issue(issues["suspicious_values"], source=f"object {object_key}", field="health", value=health)
        if speed < 0.0:
            add_issue(issues["suspicious_values"], source=f"object {object_key}", field="speed", value=speed)
        if range_min > range_max:
            add_issue(issues["suspicious_values"], source=f"object {object_key}", field="range", value=[range_min, range_max])

    technology_adjacency: dict[int, set[int]] = {}
    for technology_key, technology in technologies.items():
        technology_id = int(technology_key)
        technology_adjacency.setdefault(technology_id, set())
        effect_id = int(technology.get("effect_bundle_id", -1))
        if effect_id >= 0 and str(effect_id) not in effect_bundles:
            add_issue(issues["unknown_ids"], source=f"technology {technology_key}", field="effect_bundle_id", target_id=effect_id)
        for required_id in technology.get("required_technology_ids", []):
            numeric = int(required_id)
            if numeric >= 0 and str(numeric) not in technologies:
                add_issue(issues["unknown_ids"], source=f"technology {technology_key}", field="required_technology_ids", target_id=numeric)
            elif numeric >= 0:
                technology_adjacency[technology_id].add(numeric)

    issues["dependency_cycles"].extend(dependency_cycles(graphic_adjacency, "graphic deltas"))
    issues["dependency_cycles"].extend(dependency_cycles(technology_adjacency, "technology prerequisites"))

    severities = {
        # These records describe gaps in the user's owned source installation,
        # not malformed generated cache files. Their item-level impact says
        # whether an enabled catalog record can reach the missing resource.
        "missing_slp": "warning",
        "missing_audio": "warning",
        "unknown_ids": "error",
        "broken_deltas": "error",
        "dependency_cycles": "error",
        "missing_name_or_icon": "warning",
        "suspicious_values": "warning",
    }
    return {
        name: {"severity": severities[name], "count": len(values), "items": values}
        for name, values in issues.items()
    }


def markdown_report(report: dict[str, object]) -> str:
    lines = [
        "# Rise of Rome cache validation",
        "",
        f"Validated graphics: {report['inputs']['graphics']}; objects: {report['inputs']['objects']}; logical sounds: {report['inputs']['sounds']}; languages: {report['inputs']['languages']}.",
        "",
        "| Category | Severity | Count |",
        "|---|---:|---:|",
    ]
    for name, section in report["issues"].items():
        lines.append(f"| `{name}` | {section['severity']} | {section['count']} |")
    lines.extend([
        "",
        "## Coverage",
        "",
        "| Metric | Covered | Total |",
        "|---|---:|---:|",
        f"| Player-facing localized names | {report['coverage']['player_facing_objects_with_name']} | {report['coverage']['player_facing_objects']} |",
        f"| Required object icons | {report['coverage']['objects_with_required_icon']} | {report['coverage']['objects_requiring_icon']} |",
        f"| Reachable resource-backed graphics with SLP | {report['coverage']['reachable_resource_graphics_with_slp']} | {report['coverage']['reachable_resource_graphics']} |",
        f"| Active resource-backed logical sounds with audio | {report['coverage']['active_resource_sounds_with_audio']} | {report['coverage']['active_resource_sounds']} |",
        "",
        "Missing SLP/WAV findings are gaps in the owned source installation. They are warnings, while malformed references and dependency cycles remain errors. Each resource finding records whether an enabled catalog record can reach it.",
    ])
    for name, section in report["issues"].items():
        lines.extend(["", f"## {name}", ""])
        if not section["items"]:
            lines.append("No findings.")
            continue
        for item in section["items"][:100]:
            lines.append(f"- `{json.dumps(item, ensure_ascii=False, sort_keys=True)}`")
        if section["count"] > 100:
            lines.append(f"- …and {section['count'] - 100} more; see the JSON report for the complete list.")
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    graphics_path = args.cache_dir / "graphics-catalog.json"
    objects_path = args.cache_dir / "objects-catalog.json"
    sounds_path = args.cache_dir / "sound-catalog.json"
    localization_path = args.cache_dir / "localization-catalog.json"
    runtime_path = args.runtime or args.cache_dir / "runtime-catalog.json"
    graphics_catalog = read_json(graphics_path)
    object_catalog = read_json(objects_path)
    sound_catalog = read_json(sounds_path)
    localization_catalog = read_json(localization_path)
    runtime_catalog = read_json(runtime_path)
    issues = validate(graphics_catalog, object_catalog, sound_catalog, localization_catalog)
    runtime_findings = validate_runtime_catalog(runtime_catalog, object_catalog)
    issues["runtime_catalog"] = {"severity": "error", "count": len(runtime_findings), "items": runtime_findings}
    source_hashes = {
        "graphics_catalog": file_hash(graphics_path),
        "object_catalog": file_hash(objects_path),
        "sound_catalog": file_hash(sounds_path),
        "localization_catalog": file_hash(localization_path),
        "runtime_catalog": file_hash(runtime_path),
    }
    components = {
        "sourceSha256": source_hashes,
        "importerVersion": IMPORTER_VERSION,
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "palette": {"id": "none", "sha256": "none"},
        "gameVersion": object_catalog.get("source", {}).get("game_version", "unknown"),
    }
    encoded = json.dumps(components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    report = {
        "format_version": REPORT_SCHEMA_VERSION,
        "cache": {"key": hashlib.sha256(encoded).hexdigest(), "components": components},
        "inputs": {
            "graphics": graphics_catalog.get("entry_count", 0),
            "objects": object_catalog.get("counts", {}).get("objects", 0),
            "sounds": sound_catalog.get("sound_count", 0),
            "sound_variants": sum(len(sound.get("items", [])) for sound in sound_catalog.get("sounds", {}).values()),
            "languages": localization_catalog.get("language_count", 0),
            "runtime_archetypes": runtime_catalog.get("archetype_count", 0),
        },
        "summary": {
            "errors": sum(section["count"] for section in issues.values() if section["severity"] == "error"),
            "warnings": sum(section["count"] for section in issues.values() if section["severity"] == "warning"),
        },
        "coverage": coverage_summary(graphics_catalog, object_catalog, sound_catalog, localization_catalog),
        "issues": issues,
    }
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.markdown_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.markdown_output.write_text(markdown_report(report), encoding="utf-8")
    print(f"validation report: {report['summary']['errors']} errors, {report['summary']['warnings']} warnings")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
