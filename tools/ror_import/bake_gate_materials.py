"""Small opaque plank materials for gate leaves, in the classic building palette."""
from pathlib import Path
import random
from PIL import Image, ImageDraw

OUTPUT = Path(__file__).resolve().parents[2] / "prototype/assets/gates"
STYLES = {"egyptian": (115, 78, 40), "greek": (104, 74, 44), "mesopotamian": (99, 65, 35), "east_asian": (112, 69, 36), "roman": (103, 73, 42)}


def main():
    for index, (style, base) in enumerate(STYLES.items()):
        random_source = random.Random(1097 + index)
        image = Image.new("RGB", (64, 64))
        for y in range(64):
            for x in range(64):
                seam = x % 8
                grain = random_source.choice([-10, -5, 0, 0, 3, 7])
                grain += -28 if seam == 0 else 15 if seam == 1 else (x//8 % 3-1)*5
                image.putpixel((x, y), tuple(max(0, min(255, channel+grain)) for channel in base))
        draw = ImageDraw.Draw(image)
        # Heavy wooden cross-braces, iron straps and small forged rivets.
        draw.line((3, 57, 59, 7), fill="#35291d", width=7)
        draw.line((3, 55, 59, 5), fill=tuple(min(255, c+17) for c in base), width=4)
        draw.line((4, 6, 60, 56), fill="#35291d", width=7)
        draw.line((4, 4, 60, 54), fill=tuple(min(255, c+11) for c in base), width=4)
        for y in [15, 47]:
            draw.rectangle((0, y, 63, y+5), fill="#292824")
            draw.line((0, y, 63, y), fill="#70695b", width=1)
            draw.line((0, y+5, 63, y+5), fill="#181b19", width=1)
            for x in [4, 20, 36, 52]:
                draw.rectangle((x, y+2, x+1, y+3), fill="#aaa080")
        image.save(OUTPUT / f"{style}-door.png")


if __name__ == "__main__":
    main()
