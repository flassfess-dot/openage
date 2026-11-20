"""Bake original command drawings into 50 px material-shaded HUD sprites.

The SVGs supply silhouettes, colour and light. A flat material mask generated
from the same paths confines the finish to each surface. No game assets, random
generators at runtime, or graphics drivers are needed to rebuild the sprites.
"""

import argparse
import math
from pathlib import Path
import random
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "prototype"
UI = PROJECT / "assets/ui"
SOURCE = UI / "icon_sources"
SIZE = 50
PAINT_TAGS = {"path", "ellipse", "rect", "circle", "polygon"}

# Flat mask RGB, value variation at three scales, and shallow surface relief.
MATERIALS = {
    "iron":    ((255,   0,   0), (10, 17,  9, 1.0)),
    "bronze":  ((  0, 255,   0), (17, 20, 10, 1.0)),
    "leather": ((  0,   0, 255), (13, 15,  8, 0.4)),
    "stone":   ((255, 255,   0), (23, 27, 18, 1.0)),
    "wood":    ((  0, 255, 255), (17, 18, 10, 0.7)),
    "cloth":   ((255,   0, 255), (14, 15, 14, 0.4)),
    "red":     ((127,   0,   0), (16, 16, 10, 0.6)),
    "green":   ((  0, 127,   0), (16, 16, 10, 0.6)),
    "patina":  ((  0,   0, 127), (24, 21, 14, 0.8)),
    "bone":    ((127, 127,   0), (17, 16,  9, 0.6)),
    "food":    ((  0, 127, 127), (18, 20, 16, 0.7)),
    "neutral": ((127,   0, 127), ( 7,  7,  6, 0.1)),
}
BY_RGB = {rgb: name for name, (rgb, _) in MATERIALS.items()}

ET.register_namespace("", "http://www.w3.org/2000/svg")
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")


def material_svg(source):
    """Map fill/stroke in SVG path order; groups and repeated shapes stay intact."""
    svg = source.read_text(encoding="utf-8")
    tags = re.search(r"<!-- materials: (.+?) -->", svg)
    root = ET.fromstring(svg)
    shapes = [e for e in root.iter() if e.tag.split("}")[-1] in PAINT_TAGS]
    material_ids = tags[1].split(" | ") if tags else []
    if len(shapes) != len(material_ids):
        raise ValueError(f"{source.name}: expected one material tag per painted shape")
    for shape, tag in zip(shapes, material_ids):
        fill, _, stroke = tag.partition("/")
        for attribute, default, material in (
            ("fill", "black", fill),
            ("stroke", "none", stroke or fill),
        ):
            if shape.get(attribute, default) != "none":
                rgb = MATERIALS[material][0]
                shape.set(attribute, "#{:02x}{:02x}{:02x}".format(*rgb))
    return ET.tostring(root, encoding="utf-8")


def noise(rng, columns, rows):
    field = Image.new("L", (columns, rows))
    field.putdata([rng.randrange(256) for _ in range(columns * rows)])
    return field.resize((SIZE, SIZE), Image.Resampling.BILINEAR)


def closest_material(rgb):
    if rgb in BY_RGB:
        return BY_RGB[rgb]
    # At a material seam the SVG rasterizer blends IDs. Select the closest
    # material instead of amplifying this blend with extra surface contrast.
    nearest = min(BY_RGB, key=lambda color: sum((a - b) ** 2 for a, b in zip(rgb, color)))
    return BY_RGB[nearest]


def finish(drawing, materials, source):
    drawing = drawing.convert("RGBA").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    masks = materials.convert("RGBA").resize((SIZE, SIZE), Image.Resampling.NEAREST)
    rng = random.Random(source.stem)
    coarse = noise(rng, 8, 8).load()
    medium = noise(rng, 18, 18).load()
    fine = noise(rng, 48, 48).load()
    grain = noise(rng, 36, 10).load()
    lum = drawing.convert("L").filter(ImageFilter.GaussianBlur(0.62)).load()
    art, mask = drawing.load(), masks.load()
    pixels = []
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, alpha = art[x, y]
            if alpha < 30:
                pixels.append((0, 0, 0, 0))
                continue
            rgb = mask[x, y][:3]
            material = closest_material(rgb)
            c, m, f, relief = MATERIALS[material][1]
            broad = (coarse[x, y] - 128) / 128
            mid = (medium[x, y] - 128) / 128
            detail = (fine[x, y] - 128) / 128
            # Keep the same upper-left light on every material. Emphasize
            # transitions inside the object, not the already shaded rim.
            dx = lum[min(SIZE - 1, x + 1), y] - lum[max(0, x - 1), y]
            dy = lum[x, min(SIZE - 1, y + 1)] - lum[x, max(0, y - 1)]
            light = (17 - x) * 0.07 + (17 - y) * 0.19
            texture = c * broad + m * mid + f * detail
            sided = (abs(dx) * 0.025 + abs(dy) * 0.025) if alpha > 245 else 0
            bevel = relief * min(7, sided) * (1 if dx + dy > 0 else -1)
            if material == "wood":
                # Run the grain diagonally on timber and vertically on doors.
                phase = x * 1.8 + (y * 1.67 if source.stem == "trade-wood" else y * 0.09)
                texture += 7.5 * math.sin(phase + broad * 1.3 + mid * 1.0) * (0.63 + detail * 0.37)
            elif material == "iron":
                texture += (grain[x, y] - 128) * 0.08
                if mid < -0.29 and detail > 0.27:
                    texture -= 19
                if r + g + b > 420 and mid > 0.33 and detail > 0.13:
                    texture += 16
            elif material in ("bronze", "patina"):
                if mid < -0.3:
                    texture -= 8
                if detail > 0.37 and broad > 0.04:
                    texture += 10
            elif material == "stone":
                chip = 10 if mid > 0.4 and detail > 0.16 else -8 if mid < -0.38 else 0
                texture += chip
            elif material == "cloth":
                texture += 3.5 if (x + y) % 3 == 0 else -1.5
            elif material == "food":
                texture += 4.3 * math.sin(x * 1.6 + y * 1.84 + mid * 2.1)

            # Preserve original hues and the semantic arrow colour, even with
            # dirt in the shadows. Reduce texture on partly covered pixels.
            value = r * 0.299 + g * 0.587 + b * 0.114
            weight = min(1, max(0.33, value / 84)) * (alpha / 255)
            variation = light + (texture + bevel) * weight
            patina = max(0, -mid) * 12 if material == "bronze" else 0
            colors = []
            for channel, tint in zip((r, g, b), (-patina, 0.37 * patina, 0.28 * patina)):
                shaded = value + (channel - value) * 0.96 + variation + tint
                colors.append(max(0, min(255, round(shaded / 4) * 4)))
            pixels.append((*colors, alpha))
    output = Image.new("RGBA", drawing.size)
    output.putdata(pixels)
    return output


def main():
    bundled_godot = ROOT / ".tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(bundled_godot) if bundled_godot.is_file() else "godot",
                        help="Godot 4.7 editor executable or a command on PATH")
    parser.add_argument("--output", type=Path, default=UI)
    parser.add_argument("--work-dir", type=Path, help="Parent for scratch files (defaults to the OS temp directory)")
    parser.add_argument("--check", action="store_true", help="Compare pixels with existing bakes without writing")
    args = parser.parse_args()

    sources = sorted(SOURCE.glob("*/*.svg"))
    if not sources:
        parser.error("no editable HUD artwork found")
    godot_path = Path(args.godot).expanduser()
    godot = str(godot_path.resolve()) if godot_path.is_file() else args.godot
    with tempfile.TemporaryDirectory(prefix="ror-hud-icons-", dir=args.work_dir) as directory:
        scratch = Path(directory).resolve()
        for source in sources:
            (scratch / source.name).write_bytes(source.read_bytes())
            (scratch / f"{source.stem}.material.svg").write_bytes(material_svg(source))
        log = scratch / "godot.log"
        try:
            subprocess.run(
                [godot, "--headless", "--log-file", str(log),
                 "--script", str(Path(__file__).with_name("rasterize_hud_icons.gd").resolve()),
                 "--", str(scratch)],
                check=True,
                cwd=scratch,
                timeout=45,
            )
        except (OSError, subprocess.SubprocessError) as error:
            parser.exit(1, f"Could not rasterize HUD drawings: {error}\n"
                        + (log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""))
        different = []
        for source in sources:
            with (
                Image.open(scratch / f"{source.stem}.png") as drawing,
                Image.open(scratch / f"{source.stem}.material.png") as mask,
            ):
                result = finish(drawing, mask, source)
            path = args.output / source.relative_to(SOURCE).with_suffix(".png")
            if args.check:
                if not path.is_file():
                    different.append(path)
                    continue
                with Image.open(path) as existing:
                    if result.size != existing.size or result.tobytes() != existing.convert("RGBA").tobytes():
                        different.append(path)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                result.save(path, optimize=True)
        if different:
            for path in different:
                print(f"Outdated sprite: {path}")
            return 1
    print(f"{'Verified' if args.check else 'Baked'} {len(sources)} HUD sprites.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
