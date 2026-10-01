#!/usr/bin/env python3
"""Compose docs/assets/hero-v2.jpg: the real top bar plus real hover-card
screenshots floating over a blurred wallpaper. Every element is an actual
capture from docs/assets/; only the arrangement is composed. Needs Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
A = ROOT / "docs/assets"
W, H = 1920, 740


def load(name, scale=1.0):
    im = Image.open(A / name).convert("RGB")
    return im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)


def main():
    # blurred wallpaper backdrop, taken from the bar's own background
    bg = load("topbar-v2.png").crop((1150, 0, 1400, 60)).resize((W, H), Image.BICUBIC)
    canvas = bg.filter(ImageFilter.GaussianBlur(40))
    canvas = ImageEnhance.Color(ImageEnhance.Brightness(canvas).enhance(0.42)).enhance(1.2)

    def place(im, x, y, r=14):
        nonlocal canvas
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle((x + 4, y + 12, x + im.width + 4, y + im.height + 12), r, fill=(0, 0, 0, 160))
        c = canvas.convert("RGBA")
        c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(16)))
        canvas = c.convert("RGB")
        mask = Image.new("L", im.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), r, fill=255)
        canvas.paste(im, (x, y), mask)

    canvas.paste(load("topbar-v2.png"), (0, 0))
    media, weather = load("card-media.png", 1.4), load("card-weather.png", 1.4)
    shot, agenda = load("card-resident-shot.png", 1.25), load("card-agenda.png", 1.25)
    chips = load("stats-chips.png", 1.4)
    y0, gap = 112, 48
    x1 = 110
    x2 = x1 + media.width + gap
    x3 = x2 + weather.width + gap
    place(media, x1, y0)
    place(weather, x2, y0)
    place(shot, x3, y0)
    place(agenda, x3, y0 + shot.height + 36)
    place(chips, x2 + (weather.width - chips.width) // 2, y0 + weather.height + 44, r=10)
    canvas.save(A / "hero-v2.jpg", quality=88, optimize=True, progressive=True)
    print("wrote hero-v2.jpg")


if __name__ == "__main__":
    main()
