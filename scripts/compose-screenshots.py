#!/usr/bin/env python3
"""Compose App Store screenshots from raw simulator captures.

    ./scripts/capture-screenshots.sh     # writes fastlane/screenshots/raw/
    ./scripts/compose-screenshots.py     # writes fastlane/screenshots/en-US/

Reads the raws that `BabyDocsUITests/ScreenshotUITests` captured and writes
1320x2868 PNGs, which is the `APP_IPHONE_67` size App Store Connect wants and
the only set a submission needs.

The raws are kept beside the output rather than thrown away. They are the
evidence: every screen in them came out of a real reconciliation pass over the
sample family, so if a rule is wrong the picture is wrong too, and a raw that
nobody can look at afterwards cannot be checked against the build that made it.

Copy rules, and none of them are stylistic:

  * **Never a price.** The product page renders the real per-territory price
    from the IAP records, and a figure typed here would be true in at most one
    of 175 storefronts. (The paywall capture shows a real StoreKit price
    because that is the binary doing its own disclosure, which is the version
    Apple actually enforces.)
  * **Never a promise the build does not keep.** Baby Docs files nothing and
    has no live sync, so no caption may imply either. Sending the plan is real
    and free, so it is described rather than sold.
  * No em dashes.
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "fastlane", "screenshots", "raw")
OUT = os.path.join(ROOT, "fastlane", "screenshots", "en-US")

# APP_IPHONE_67. One set at this size covers the 6.9-inch bucket too, so it is
# the only set the submission needs.
W, H = 1320, 2868

INK = (17, 24, 39)
BEZEL = (24, 25, 27)

# Pulled around the app's own iOS blue, so six cards read as one product. The
# app itself spends colour only on how close a deadline is, which is why none of
# these tints is a red or a warning orange: the store page must not teach a
# meaning the app then contradicts.
TINTS = {
    "blue": ((219, 234, 254), (191, 219, 254)),
    "mint": ((209, 244, 233), (186, 233, 218)),
    "sand": ((253, 236, 214), (250, 226, 193)),
    "lilac": ((233, 228, 253), (221, 214, 254)),
    "slate": ((226, 232, 240), (203, 213, 225)),
}

SF = "/System/Library/Fonts/SFNSRounded.ttf"

# The floating tab bar sits over a scroll-edge material, and the content passes
# under it by design, so a capture that includes the bar includes whatever was
# sliding under the glass at that instant. It is unmistakable at store size, so
# every raw is cropped just above the bar. A screenshot without a tab bar is
# ordinary store creative; one with a half-legible row behind glass is not.
TAB_BAR_CROP = 270

# A scrolled screen keeps its content under the translucent nav bar, which is
# right on a phone and reads as a smear of half-legible text when the picture is
# blown up to store size. The one frame captured mid-scroll is cropped below the
# bar instead: a clean band of content, and the screen it belongs to is already
# named on the frame before it.
CROPPED_NAV_BAR = 400

# (raw, output, tint, headline, crop_bottom, crop_top)
#
# The first three have to stand alone, because App Store search shows them
# without the ones after. So they are the three questions a parent actually
# arrives with, in order: what is due, why, and what do I take with me.
FRAMES = [
    ("01-plan.png", "01-deadlines.png", "blue",
     "Every deadline,\nsoonest first",
     TAB_BAR_CROP),
    ("02-task-detail.png", "02-why-and-where.png", "mint",
     "Why it applies, and\nwhere to do it",
     TAB_BAR_CROP),
    ("03-task-documents.png", "03-documents.png", "sand",
     "What to bring,\nbefore you go",
     TAB_BAR_CROP, CROPPED_NAV_BAR),
    ("06-documents.png", "04-still-to-find.png", "lilac",
     "Everything still to find,\nin one place",
     TAB_BAR_CROP),
    ("07-settings.png", "05-sources.png", "slate",
     "Every rule shows\nits working",
     TAB_BAR_CROP),
    # A sheet, so there is no tab bar. The crop stops below the purchase
    # button: the restore link underneath it landed against the bezel, and a
    # control cut in half by a drawn phone reads as a rendering mistake.
    ("05-paywall.png", "06-free.png", "blue",
     "Every deadline is free,\nand stays free",
     170),
]


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def canvas(tint: str) -> Image.Image:
    top, bottom = TINTS[tint]
    image = Image.new("RGB", (W, H), top)
    draw = ImageDraw.Draw(image)
    for y in range(H):
        t = y / H
        draw.line(
            [(0, y), (W, y)],
            fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return image


def rounded(image: Image.Image, radius: int) -> Image.Image:
    """Rounds a capture's corners so it sits inside the drawn body."""
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, image.size[0], image.size[1]], radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, max_width: int) -> list[str]:
    """Respects the author's own line breaks, then wraps anything still too wide."""
    lines: list[str] = []
    for paragraph in text.split("\n"):
        current = ""
        for word in paragraph.split():
            candidate = f"{current} {word}".strip()
            if draw.textlength(candidate, font=fnt) <= max_width:
                current = candidate
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
    return lines


def compose(
    raw_name: str,
    out_name: str,
    tint: str,
    headline: str,
    crop_bottom: int,
    crop_top: int = 0,
) -> None:
    raw = Image.open(os.path.join(RAW, raw_name)).convert("RGB")
    if crop_bottom or crop_top:
        raw = raw.crop((0, crop_top, raw.width, raw.height - crop_bottom))

    image = canvas(tint)
    draw = ImageDraw.Draw(image)

    margin = 86
    head_font = font(SF, 90)

    y = 155
    for line in wrap(draw, headline, head_font, W - margin * 2):
        draw.text((margin, y), line, font=head_font, fill=INK)
        y += 107

    # The phone is scaled to whatever height is left, so an edit to the copy
    # above cannot push the screen off the bottom of the canvas.
    #
    # Whatever is left over after that is split above and below the device
    # rather than dropped underneath it. The old version pinned the device to
    # the top of the space and let the remainder pile up at the bottom, and with
    # the deeper crops that was five hundred points of empty tint under a stubby
    # phone: the frame read as an unfinished layout rather than a considered one,
    # which is most of what "not seamless between sections" was about.
    head_bottom = y + 40
    bottom_margin = 92
    available_h = H - head_bottom - bottom_margin
    frame_w = W - margin * 2

    scale = min(frame_w / raw.width, available_h / raw.height)
    screen_w, screen_h = int(raw.width * scale), int(raw.height * scale)
    top = head_bottom + max(24, (available_h - screen_h) // 2)

    pad = 14
    body = [
        (W - screen_w) // 2 - pad, top - pad,
        (W - screen_w) // 2 + screen_w + pad, top + screen_h + pad,
    ]

    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [body[0], body[1] + 16, body[2], body[3] + 16], 72, fill=(15, 23, 42, 70)
    )
    image.paste(
        Image.alpha_composite(
            image.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(26))
        ).convert("RGB"),
        (0, 0),
    )

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(body, 72, fill=BEZEL)

    screen = rounded(raw.resize((screen_w, screen_h), Image.LANCZOS), 58)
    image.paste(screen, ((W - screen_w) // 2, top), screen)

    os.makedirs(OUT, exist_ok=True)
    # No alpha: App Store Connect rejects a screenshot with a transparency
    # channel, and it rejects it after the upload rather than before.
    image.convert("RGB").save(os.path.join(OUT, out_name))
    print(f"  {out_name}  {image.size[0]}x{image.size[1]}")


def main() -> int:
    missing = [f[0] for f in FRAMES if not os.path.exists(os.path.join(RAW, f[0]))]
    if missing:
        print(f"Missing raws in {RAW}: {', '.join(missing)}")
        print("Run ./scripts/capture-screenshots.sh first.")
        return 1

    for args in FRAMES:
        compose(*args)
    print(f"==> {len(FRAMES)} screenshots in {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
