"""Resolve an owned-game stack capture using a verified native linker map."""
import argparse
import bisect
import collections
import hashlib
import json
import re
import struct
from pathlib import Path


def pe(path):
    data = path.read_bytes()
    nt = struct.unpack_from("<I", data, 0x3C)[0]
    count = struct.unpack_from("<H", data, nt + 6)[0]
    optional_size = struct.unpack_from("<H", data, nt + 20)[0]
    optional = nt + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    base = struct.unpack_from("<Q" if magic == 0x20B else "<I", data, optional + (24 if magic == 0x20B else 28))[0]
    sections = []
    for index in range(count):
        start = optional + optional_size + index * 40
        name = data[start:start + 8].rstrip(b"\0").decode("ascii", "replace")
        virtual_size, rva, raw_size, raw = struct.unpack_from("<IIII", data, start + 8)
        sections.append((name, rva, virtual_size, data[raw:raw + raw_size]))
    text = next(section for section in sections if section[0] == ".text")
    return base, text, data


def analyze(case, library, mapping):
    capture = json.loads((case / "native-stacks.json").read_text(encoding="utf-8"))
    old_base, old_text, _ = pe(case / "executed-native.dll")
    new_base, new_text, _ = pe(library)
    if old_text[:3] != new_text[:3] or old_text[3] != new_text[3]:
        raise RuntimeError("Native .text differs: linker map cannot resolve this capture")
    text_start, text_size = new_text[1:3]
    symbols = {}
    for line in mapping.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"^\s+(0x[0-9a-fA-F]+)\s+([^\s].*)$", line)
        if not match:
            continue
        address = int(match[1], 16) - new_base
        name = match[2]
        if text_start <= address < text_start + text_size and not name.startswith(("0x", "*", ".")):
            if address not in symbols or name.startswith("godot::"):
                symbols[address] = name
    addresses = sorted(symbols)
    modules = sorted((int(row["base"], 16), int(row["base"], 16) + row["size"], row["name"]) for row in capture["modules"])
    bases = [row[0] for row in modules]

    def module(address):
        index = bisect.bisect_right(bases, address) - 1
        return modules[index] if index >= 0 and address < modules[index][1] else (0, 0, "unknown")

    def label(address):
        entry = module(address)
        rva = address - entry[0]
        if entry[2].startswith("ror_pathfinding"):
            if not text_start <= rva < text_start + text_size:
                return entry[2] + "+" + hex(rva) + " [outside executable .text]"
            index = bisect.bisect_right(addresses, rva) - 1
            if index >= 0:
                return symbols[addresses[index]]
        return entry[2] + "+" + hex(rva)

    result = {"native_text_sha256": hashlib.sha256(old_text[3]).hexdigest(), "native_map_symbols": len(symbols),
              "map_path": str(mapping.resolve()), "elapsed_ms": capture["elapsed_ms"],
              "qualification": "Wall stack samples include waits; they are not frame-performance qualification.", "threads": []}
    for thread in capture["threads"]:
        first_native = collections.Counter()
        inclusive = collections.Counter()
        top_frames = collections.Counter()
        top_modules = collections.Counter()
        nontext_native_frames = 0
        for stack in thread["stacks"]:
            frames = [int(address, 16) for address in stack["frames"]]
            count = stack["count"]
            top_frames[label(frames[0])] += count
            top_modules[module(frames[0])[2]] += count
            native = []
            for address in frames:
                entry = module(address)
                if not entry[2].startswith("ror_pathfinding"):
                    continue
                rva = address - entry[0]
                if text_start <= rva < text_start + text_size:
                    native.append(label(address))
                else:
                    nontext_native_frames += count
            first_native[native[0] if native else "<no native DLL frame>"] += count
            for name in set(native):
                inclusive[name] += count
        row = {key: thread[key] for key in ("id", "name", "priority", "rank_cpu_ms", "samples", "walk_errors", "context_errors", "suspend_errors")}
        row.update(first_native=first_native.most_common(), inclusive_native=inclusive.most_common(), top_frames=top_frames.most_common(), top_modules=top_modules.most_common(), nontext_native_frames=nontext_native_frames)
        result["threads"].append(row)
    output = case / "native-stacks.analysis.json"
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Verified native .text:", result["native_text_sha256"], "symbols:", len(symbols))
    for thread in result["threads"]:
        print("\nTHREAD", thread["id"], repr(thread["name"]), "priority", thread["priority"], "samples", thread["samples"])
        print("TOP MODULES", thread["top_modules"][:5])
        print("FIRST NATIVE")
        for name, count in thread["first_native"][:18]:
            print(count, round(count * 100 / thread["samples"], 1), name[:190])
        print("INCLUSIVE NATIVE")
        for name, count in thread["inclusive_native"][:12]:
            print(count, name[:190])
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", type=Path)
    parser.add_argument("--library", type=Path, default=Path("prototype/bin/ror_pathfinding.windows.template_release.x86_64.dll"))
    parser.add_argument("--map", type=Path, default=Path(".tools/ror-pathfinding-build/ror_pathfinding.map"))
    args = parser.parse_args()
    analyze(args.case, args.library, args.map)
