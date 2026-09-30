#!/usr/bin/env python3
"""Build the README/docs images from the Guide's full-screen previews.

Reads   scripts/quickshell/guide/previews/preview_<widget>.png  (1920x1080)
Writes  docs/assets/<widget>.jpg
(The hero collage is built separately by build_hero.py.)

Crop boxes follow WindowRegistry.js at 1920x1080, uiScale 1. If you
recapture at another resolution/scale, adjust BOXES. Needs Pillow.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "scripts/quickshell/guide/previews"
OUT = ROOT / "docs/assets"

# widget -> (left, top, right, bottom) of the popup itself
BOXES = {
    "battery":   (1428, 70, 1908, 830),
    "volume":    (1428, 70, 1908, 830),
    "calendar":  (235, 70, 1685, 820),
    "music":     (12, 70, 712, 690),
    "network":   (1008, 70, 1908, 770),
    "monitors":  (535, 250, 1385, 830),
    "focustime": (510, 180, 1410, 900),
    "wallpaper": (0, 215, 1920, 865),
    "guide":     (360, 165, 1560, 915),
}
PAD = 28        # wallpaper margin around each popup
BAR_H = 60      # never let the padding pull the top bar into a crop
MAX_W = 1400


def save_jpg(im, path):
    im.save(path, quality=86, optimize=True, progressive=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (l, t, r, b) in BOXES.items():
        src = SRC / f"preview_{name}.png"
        if not src.exists():
            print(f"skip {name}: {src} missing")
            continue
        im = Image.open(src).convert("RGB")
        w, h = im.size
        crop = im.crop((max(0, l - PAD), max(BAR_H, t - PAD), min(w, r + PAD), min(h, b + PAD)))
        if crop.width > MAX_W:
            crop = crop.resize((MAX_W, round(crop.height * MAX_W / crop.width)), Image.LANCZOS)
        save_jpg(crop, OUT / f"{name}.jpg")
        print(f"wrote {name}.jpg")



if __name__ == "__main__":
    main()
