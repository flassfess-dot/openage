"""Build the Windows application icon from the project's PNG."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def main():
    icon = ROOT / "prototype/assets/app/icon.png"
    with Image.open(icon) as image:
        image.save(icon.with_suffix(".ico"), sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])


if __name__ == "__main__":
    main()
