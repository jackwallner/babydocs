#!/usr/bin/env python3
"""Compose the 13-inch iPad App Store screenshots from raw simulator captures.

    fastlane/screenshots/ipad-raw/   2064x2752 captures from an iPad Pro 13-inch
    fastlane/screenshots/en-US/ipad_NN.png   the composed 2064x2752 frames

The headlines are the iPhone set's, word for word, so the page reads the same on
both devices. Same look as the iPhone and Duo sets: the light gradient, the
rounded face, a dark body around the real screen. One header per frame, no
periods, two lines at most, no price, no promise the build does not keep.
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "fastlane", "screenshots", "ipad-raw")
OUT = os.path.join(ROOT, "fastlane", "screenshots", "en-US")

W, H = 2064, 2752
TOP, BOTTOM = (238, 243, 251), (212, 225, 245)
INK = (20, 38, 65)
BEZEL = (24, 25, 27)
SF = "/System/Library/Fonts/SFNSRounded.ttf"

FRAMES = [
    ("01-newborn-account.png", "ipad_01.png", "Claim the $1,000\nnewborn account"),
    ("02-plan.png", "ipad_02.png", "See the next hard\ndeadline"),
    ("03-birth-certificate.png", "ipad_03.png", "Know exactly\nwhere to file"),
    ("04-coverage.png", "ipad_04.png", "Add the baby to your\nhealth plan in time"),
    ("05-documents.png", "ipad_05.png", "Bring every paper\nyou need"),
]


def header_font(size: int) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(SF, size)
    face.set_variation_by_name("Medium")
    return face


def gradient() -> Image.Image:
    image = Image.new("RGB", (W, H), TOP)
    draw = ImageDraw.Draw(image)
    for y in range(H):
        t = y / H
        draw.line([(0, y), (W, y)], fill=tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    return image


def compose(raw_name: str, out_name: str, headline: str) -> None:
    raw = Image.open(os.path.join(RAW, raw_name)).convert("RGB")
    assert raw.size == (W, H), f"{raw_name} is {raw.size}"
    image = gradient()
    draw = ImageDraw.Draw(image)

    face = header_font(150)
    y = 130
    for line in headline.split("\n"):
        width = draw.textlength(line, font=face)
        draw.text(((W - width) / 2, y), line, font=face, fill=INK)
        y += 178
    head_bottom = y + 40

    pad = 26
    bottom_margin = 80
    available = H - head_bottom - bottom_margin - 2 * pad
    scale = min((W - 2 * 170 - 2 * pad) / raw.width, available / raw.height)
    sw, sh = int(raw.width * scale), int(raw.height * scale)
    left = (W - sw) // 2
    top = head_bottom + pad + (available - sh) // 2
    body = [left - pad, top - pad, left + sw + pad, top + sh + pad]

    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [body[0], body[1] + 20, body[2], body[3] + 20], 84, fill=(15, 23, 42, 70)
    )
    image = Image.alpha_composite(image.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(30)))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(body, 84, fill=BEZEL)

    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw, sh], 62, fill=255)
    image.paste(raw.resize((sw, sh), Image.LANCZOS), (left, top), mask)

    os.makedirs(OUT, exist_ok=True)
    # No alpha: App Store Connect rejects a screenshot with a transparency channel.
    image.convert("RGB").save(os.path.join(OUT, out_name))
    print(f"  {out_name}  {image.size[0]}x{image.size[1]}  screen {sw}x{sh}")


def main() -> int:
    missing = [f[0] for f in FRAMES if not os.path.exists(os.path.join(RAW, f[0]))]
    if missing:
        print(f"Missing raws in {RAW}: {', '.join(missing)}")
        return 1
    for frame in FRAMES:
        compose(*frame)
    print(f"==> {len(FRAMES)} iPad screenshots in {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
