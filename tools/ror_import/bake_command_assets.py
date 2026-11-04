"""Compose extension commands from the original RoR command artwork."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "prototype/assets/generated"
OUTPUT = ROOT / "prototype/assets/ui/commands"


def glyph(frame, size=42):
    art = Image.open(SOURCE / f"hud_glyph_50721_{frame:02d}.png").convert("RGBA")
    if frame == 6:
        # This original flag frame has an opaque palette backdrop, unlike the
        # other command silhouettes. Keep the pole and flag, remove that paper.
        art.putdata([(r, g, b, 0 if (r, g, b) == (254, 254, 254) else a)
                     for r, g, b, a in art.get_flattened_data()])
    bounds = art.getbbox()
    if bounds:
        art = art.crop(bounds)
    art.thumbnail((size, size), Image.Resampling.NEAREST)
    return art


def composite(name, frame, badge=None):
    image = Image.new("RGBA", (50, 50))
    art = glyph(frame)
    image.alpha_composite(art, ((50-art.width)//2, (50-art.height)//2))
    if badge is not None:
        mark = glyph(badge, 18)
        image.alpha_composite(mark, (31, 31))
    image.save(OUTPUT / f"{name}.png")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    composite("aggressive", 4, 11)
    composite("defensive", 12, 3)
    composite("stand_ground", 3, 12)
    composite("passive", 3)
    image = Image.open(OUTPUT / "passive.png")
    draw = ImageDraw.Draw(image)
    draw.line((11, 44, 39, 44), fill="#2a2015", width=4)
    draw.line((12, 43, 38, 43), fill="#c5a46a", width=2)
    image.save(OUTPUT / "passive.png")
    composite("attack_ground", 4)
    image = Image.open(OUTPUT / "attack_ground.png")
    draw = ImageDraw.Draw(image)
    draw.ellipse((27, 28, 47, 46), fill="#292017", outline="#d0aa63", width=2)
    draw.ellipse((32, 32, 42, 42), outline="#a43825", width=2)
    draw.line((37, 27, 37, 47), fill="#e5cf9a", width=1)
    draw.line((26, 37, 48, 37), fill="#e5cf9a", width=1)
    image.save(OUTPUT / "attack_ground.png")
    for name, frame, badge in [("gate-auto", 6, 7), ("gate-open", 6, 11), ("gate-locked", 6, 3)]:
        composite(name, frame, badge)
    icon = ROOT / "prototype/assets/app/icon.png"
    if icon.exists():
        Image.open(icon).save(icon.with_suffix(".ico"), sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])


if __name__ == "__main__":
    main()
