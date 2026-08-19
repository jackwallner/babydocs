#!/usr/bin/env python3
"""Compose App Store screenshots from real simulator captures and art-directed scenes."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


WIDTH = 1320
HEIGHT = 2868
SCREEN_WIDTH = 1052
DEVICE_X = (WIDTH - SCREEN_WIDTH - 44) // 2
DEVICE_WIDTH = SCREEN_WIDTH + 44

# The floating tab bar is glass and the content passes under it by design, so a
# capture that keeps the bar keeps whatever was sliding under it at that
# instant. Every frame taken on a tab screen is cropped just above the bar. The
# old set placed the raw whole, which is what put a grey slab with half-legible
# text through it across the bottom of six store images.
TAB_BAR_CROP = 270
# The top of the space the device is centred in: below the headline block.
DEVICE_BAND_TOP = 470
DEVICE_BAND_BOTTOM = HEIGHT - 60

FONT_DIR = Path("/System/Library/Fonts")
TITLE_FONT = FONT_DIR / "HelveticaNeue.ttc"
SUBTITLE_FONT = FONT_DIR / "SFNS.ttf"


FRAMES = (
    {
        "raw": "01-plan.png",
        "crop": TAB_BAR_CROP,
        "scene": "01-navy-paper.png",
        "title": "KNOW WHAT APPLIES",
        "subtitle": "A plan built from your household answers.",
        "ink": (255, 250, 240),
    },
    {
        "raw": "02-task-detail.png",
        "crop": TAB_BAR_CROP,
        "scene": "02-warm-desk.png",
        "title": "SEE THE SOURCE",
        "subtitle": "Every task shows the office, the date and what to bring.",
        "ink": (15, 23, 36),
    },
    {
        "raw": "03-documents-checklist.png",
        "crop": TAB_BAR_CROP,
        "crop_top": 400,
        "scene": "03-blue-folder.png",
        "title": "BRING THE RIGHT PAPERS",
        "subtitle": "The checklist stays beside the official link.",
        "ink": (255, 250, 240),
    },
    {
        "raw": "04-send-plan.png",
        "crop": 0,
        "scene": "02-warm-desk.png",
        "title": "SEND THE PLAN FOR FREE",
        "subtitle": "The other parent gets the same answers and deadlines.",
        "ink": (15, 23, 36),
    },
    {
        "raw": "05-children.png",
        "crop": TAB_BAR_CROP,
        "scene": "03-blue-folder.png",
        "title": "KEEP EVERY CHILD IN ORDER",
        "subtitle": "Start with one household. Add the rest when you need them.",
        "ink": (255, 250, 240),
    },
    {
        "raw": "06-plus.png",
        "crop": 215,
        "scene": "01-navy-paper.png",
        "title": "KEEP WHAT COMES BACK",
        "subtitle": "Plus adds the vault, follow-ups and employer packet.",
        "ink": (255, 250, 240),
    },
)


def font(path: Path, size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size, index=index)


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    source_ratio = image.width / image.height
    target_ratio = size[0] / size[1]
    if source_ratio > target_ratio:
        height = size[1]
        width = round(height * source_ratio)
    else:
        width = size[0]
        height = round(width / source_ratio)
    image = image.resize((width, height), Image.Resampling.LANCZOS)
    left = (width - size[0]) // 2
    top = (height - size[1]) // 2
    return image.crop((left, top, left + size[0], top + size[1]))


def wrapped_lines(draw: ImageDraw.ImageDraw, value: str, typeface: ImageFont.FreeTypeFont, width: int) -> list[str]:
    words = value.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=typeface)[2] <= width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def add_text(
    canvas: Image.Image,
    title: str,
    subtitle: str,
    ink: tuple[int, int, int],
) -> None:
    draw = ImageDraw.Draw(canvas)
    title_font = font(TITLE_FONT, 82, index=1)
    subtitle_font = font(SUBTITLE_FONT, 36)
    text_width = WIDTH - 192
    title_lines = wrapped_lines(draw, title, title_font, text_width)
    subtitle_lines = wrapped_lines(draw, subtitle, subtitle_font, text_width)

    x = 96
    y = 92
    draw.text((x, y), "BABY DOCS", font=font(SUBTITLE_FONT, 24), fill=ink)
    y += 50
    for line in title_lines:
        draw.text((x, y), line, font=title_font, fill=ink)
        y += 92
    y += 10
    for line in subtitle_lines:
        draw.text((x, y), line, font=subtitle_font, fill=ink)
        y += 45


def add_device(canvas: Image.Image, raw: Image.Image) -> None:
    """Draws the phone, sized to the capture it is holding.

    The geometry used to be fixed, which was fine while every raw was the same
    full-screen height and wrong the moment one was cropped. It is derived from
    the image now, and the device is centred in the band under the headline
    rather than pinned to the top of it, so a shorter capture leaves even air
    above and below instead of a stripe of dead scene along the bottom.
    """
    screen_height = round(SCREEN_WIDTH * raw.height / raw.width)
    band = DEVICE_BAND_BOTTOM - DEVICE_BAND_TOP
    screen_top = DEVICE_BAND_TOP + max(0, (band - screen_height - 40) // 2)
    device_y = screen_top - 20
    device_height = screen_height + 40

    body = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    body_draw = ImageDraw.Draw(body)
    body_draw.rounded_rectangle(
        (DEVICE_X, device_y, DEVICE_X + DEVICE_WIDTH, device_y + device_height),
        radius=102,
        fill=(12, 17, 25, 255),
    )
    shadow = body.filter(ImageFilter.GaussianBlur(34))
    alpha = shadow.getchannel("A").point(lambda value: round(value * 0.55))
    shadow.putalpha(alpha)
    canvas.alpha_composite(shadow, (0, 28))
    canvas.alpha_composite(body)

    screen = raw.convert("RGB").resize((SCREEN_WIDTH, screen_height), Image.Resampling.LANCZOS)
    mask = Image.new("L", (SCREEN_WIDTH, screen_height), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, SCREEN_WIDTH, screen_height), radius=76, fill=255
    )
    screen_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    screen_layer.paste(screen, (DEVICE_X + 22, screen_top), mask)
    canvas.alpha_composite(screen_layer)


def compose(source_dir: Path, scene_dir: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(FRAMES, start=1):
        scene = Image.open(scene_dir / frame["scene"]).convert("RGB")
        canvas = cover(scene, (WIDTH, HEIGHT)).convert("RGBA")
        add_text(canvas, frame["title"], frame["subtitle"], frame["ink"])
        raw = Image.open(source_dir / frame["raw"]).convert("RGB")
        crop = frame.get("crop", 0)
        crop_top = frame.get("crop_top", 0)
        if crop or crop_top:
            raw = raw.crop((0, crop_top, raw.width, raw.height - crop))
        add_device(canvas, raw)
        output = output_dir / f"store-{index:02d}.png"
        canvas.convert("RGB").save(output, format="PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=Path("app-store/raw"))
    parser.add_argument("--scene-dir", type=Path, default=Path("app-store/scenes"))
    parser.add_argument("--output-dir", type=Path, default=Path("app-store/output"))
    args = parser.parse_args()
    compose(args.source_dir, args.scene_dir, args.output_dir)


if __name__ == "__main__":
    main()
