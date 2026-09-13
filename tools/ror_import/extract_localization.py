#!/usr/bin/env python3

"""Extract Unicode string tables from owned Rise of Rome language DLLs."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import re
from pathlib import Path


CACHE_SCHEMA_VERSION = 1
CATALOG_SCHEMA_VERSION = 1
IMPORTER_VERSION = "localization-catalog-2"
LANGUAGE_SUFFIXES = {
    "CNs": "zh_Hans",
    "CNt": "zh_Hant",
    "DE": "de",
    "ES": "es",
    "FR": "fr",
    "IT": "it",
    "PL": "pl",
    "PT": "pt",
    "RU": "ru",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Extract RoR strings with locale fallback metadata.")
    parser.add_argument("--game", type=Path, required=True, help="Rise of Rome install root")
    parser.add_argument("--objects", type=Path, required=True, help="objects-catalog.json")
    parser.add_argument("--game-version", default="1.1")
    parser.add_argument("--output", type=Path, required=True, help="localization-catalog.json")
    return parser.parse_args()


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract_windows_strings(path: Path) -> dict[str, str]:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    kernel32.LoadLibraryExW.argtypes = [ctypes.c_wchar_p, ctypes.c_void_p, ctypes.c_uint32]
    kernel32.LoadLibraryExW.restype = ctypes.c_void_p
    kernel32.FreeLibrary.argtypes = [ctypes.c_void_p]
    kernel32.FreeLibrary.restype = ctypes.c_int
    user32.LoadStringW.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_wchar_p, ctypes.c_int]
    user32.LoadStringW.restype = ctypes.c_int
    handle = kernel32.LoadLibraryExW(str(path), None, 0x00000002)
    if not handle:
        raise OSError(ctypes.get_last_error(), f"cannot load resource DLL: {path}")
    try:
        result = {}
        buffer = ctypes.create_unicode_buffer(8192)
        for string_id in range(65536):
            length = user32.LoadStringW(handle, string_id, buffer, len(buffer))
            if length > 0:
                result[str(string_id)] = buffer.value
        return result
    finally:
        kernel32.FreeLibrary(handle)


def linked_string_ids(objects: dict[str, object]) -> dict[str, list[str]]:
    references: dict[str, list[str]] = {}

    def remember(value, reference: str, offset: int = 0) -> None:
        try:
            string_id = int(value)
        except (TypeError, ValueError):
            return
        if string_id in (-1, 0, 65535):
            return
        resolved_id = string_id - offset
        if resolved_id > 0:
            references.setdefault(str(resolved_id), []).append(reference if offset == 0 else f"{reference} (raw {string_id})")

    for object_key, record in objects.get("objects", {}).items():
        remember(record.get("language", {}).get("name_id"), f"object {object_key} name")
    for technology_id, record in objects.get("technologies", {}).items():
        language = record.get("language", {})
        remember(language.get("name_id"), f"technology {technology_id} name")
        remember(language.get("description_id"), f"technology {technology_id} description")
        remember(language.get("tech_tree_id"), f"technology {technology_id} tech_tree", 149000)
    return {key: sorted(set(value)) for key, value in references.items()}


def cache_record(source_hashes: dict[str, str], object_hash: str, game_version: str) -> dict[str, object]:
    components = {
        "sourceSha256": source_hashes,
        "objectCatalogSha256": object_hash,
        "importerVersion": IMPORTER_VERSION,
        "schemaVersion": CATALOG_SCHEMA_VERSION,
        "palette": {"id": "none", "sha256": "none"},
        "gameVersion": game_version,
    }
    encoded = json.dumps(components, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "formatVersion": CACHE_SCHEMA_VERSION,
        "key": hashlib.sha256(encoded).hexdigest(),
        "components": components,
    }


def main() -> int:
    args = parse_args()
    patched_english = args.game / "language_up.dll"
    english_sources = [patched_english] if patched_english.is_file() else [path for path in (args.game / "language.dll", args.game / "languagex.dll") if path.is_file()]
    localized_sources = {}
    for suffix, locale in LANGUAGE_SUFFIXES.items():
        path = args.game / "gamex" / f"language_up_{suffix}.dll"
        if path.is_file():
            localized_sources[locale] = [path]
    if "ru" in localized_sources:
        russian_base = [path for path in (args.game / "language.dll", args.game / "languagex.dll") if path.is_file()]
        localized_sources["ru"] = russian_base + localized_sources["ru"]
    if not english_sources:
        raise FileNotFoundError("no English Rise of Rome language DLLs were found")
    all_paths = english_sources + [path for paths in localized_sources.values() for path in paths]
    source_hashes = {str(path.relative_to(args.game)).replace("\\", "/"): file_hash(path) for path in all_paths}
    object_hash = file_hash(args.objects)
    cache = cache_record(source_hashes, object_hash, args.game_version)
    if args.output.is_file():
        try:
            existing = json.loads(args.output.read_text(encoding="utf-8"))
            if existing.get("cache", {}).get("key") == cache["key"]:
                print(f"localization catalog cache hit: {args.output}")
                return 0
        except (OSError, UnicodeError, json.JSONDecodeError):
            pass

    languages = {}
    sources_by_locale = {"en": english_sources, **localized_sources}
    for locale, paths in sources_by_locale.items():
        strings = {}
        for path in paths:
            strings.update(extract_windows_strings(path))
        replacement_characters = sum(text.count("\ufffd") for text in strings.values())
        cyrillic_characters = sum(len(re.findall(r"[\u0400-\u04ff]", text)) for text in strings.values())
        languages[locale] = {
            "sources": [str(path.relative_to(args.game)).replace("\\", "/") for path in paths],
            "string_count": len(strings),
            "encoding": "UTF-16LE resources decoded to UTF-8 JSON",
            "replacement_characters": replacement_characters,
            "cyrillic_characters": cyrillic_characters,
            "strings": strings,
        }

    objects = json.loads(args.objects.read_text(encoding="utf-8"))
    references = linked_string_ids(objects)
    linked = {}
    for string_id, refs in references.items():
        available = sorted(locale for locale, data in languages.items() if string_id in data["strings"])
        linked[string_id] = {
            "references": refs,
            "available_languages": available,
            "fallback_available": string_id in languages["en"]["strings"],
        }

    payload = {
        "format_version": CATALOG_SCHEMA_VERSION,
        "cache": cache,
        "fallback_language": "en",
        "language_count": len(languages),
        "languages": languages,
        "linked_string_ids": linked,
        "validation": {
            "linked_ids": len(linked),
            "missing_in_fallback": sorted(int(key) for key, value in linked.items() if not value["fallback_available"]),
            "encoding_errors": sum(data["replacement_characters"] for data in languages.values()),
            "russian_cyrillic_characters": languages.get("ru", {}).get("cyrillic_characters", 0),
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"exported {len(languages)} languages and {len(linked)} linked string IDs "
        f"({payload['validation']['encoding_errors']} encoding errors) to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
