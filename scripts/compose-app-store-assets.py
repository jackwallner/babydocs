#!/usr/bin/env python3
"""Compose App Store screenshots from real simulator captures and art-directed scenes."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


WIDTH = 1320
HEIGHT = 2868
SCREEN_WIDTH = 1052
SCREEN_TOP = 500
SCREEN_HEIGHT = round(SCREEN_WIDTH * 2622 / 1206)
DEVICE_X = (WIDTH - SCREEN_WIDTH - 44) // 2
DEVICE_Y = SCREEN_TOP - 20
DEVICE_WIDTH = SCREEN_WIDTH + 44
DEVICE_HEIGHT = SCREEN_HEIGHT + 40

FONT_DIR = Path("/System/Library/Fonts")
TITLE_FONT = FONT_DIR / "HelveticaNeue.ttc"
SUBTITLE_FONT = FONT_DIR / "SFNS.ttf"


FRAMES = (
    {
        "raw": "01-plan.png",
        "scene": "01-navy-paper.png",
        "title": "KNOW WHAT APPLIES",
        "subtitle": "A plan built from your household answers.",
        "ink": (255, 250, 240),
    },
    {
        "raw": "02-task-detail.png",
        "scene": "02-warm-desk.png",
        "title": "SEE THE SOURCE",
        "subtitle": "Every task shows the office, the date and what to bring.",
        "ink": (15, 23, 36),
    },
    {
        "raw": "03-documents-checklist.png",
        "scene": "03-blue-folder.png",
        "title": "BRING THE RIGHT PAPERS",
        "subtitle": "The checklist stays beside the official link.",
        "ink": (255, 250, 240),
    },
    {
        "raw": "04-send-plan.png",
        "scene": "02-warm-desk.png",
        "title": "SEND THE PLAN FOR FREE",
        "subtitle": "The other parent gets the same answers and deadlines.",
        "ink": (15, 23, 36),
    },
    {
        "raw": "05-children.png",
        "scene": "03-blue-folder.png",
        "title": "KEEP EVERY CHILD IN ORDER",
        "subtitle": "Start with one household. Add the rest when you need them.",
        "ink": (255, 250, 240),
    },
    {
        "raw": "06-plus.png",
        "scene": "01-navy-paper.png",
        "title": "KEEP THE WORK AROUND IT",
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
    body = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    body_draw = ImageDraw.Draw(body)
    body_draw.rounded_rectangle(
        (DEVICE_X, DEVICE_Y, DEVICE_X + DEVICE_WIDTH, DEVICE_Y + DEVICE_HEIGHT),
        radius=102,
        fill=(12, 17, 25, 255),
    )
    shadow = body.filter(ImageFilter.GaussianBlur(34))
    alpha = shadow.getchannel("A").point(lambda value: round(value * 0.55))
    shadow.putalpha(alpha)
    canvas.alpha_composite(shadow, (0, 28))
    canvas.alpha_composite(body)

    screen = raw.convert("RGB").resize((SCREEN_WIDTH, SCREEN_HEIGHT), Image.Resampling.LANCZOS)
    mask = Image.new("L", (SCREEN_WIDTH, SCREEN_HEIGHT), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, SCREEN_WIDTH, SCREEN_HEIGHT), radius=76, fill=255
    )
    screen_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    screen_layer.paste(screen, (DEVICE_X + 22, SCREEN_TOP), mask)
    canvas.alpha_composite(screen_layer)


def compose(source_dir: Path, scene_dir: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(FRAMES, start=1):
        scene = Image.open(scene_dir / frame["scene"]).convert("RGB")
        canvas = cover(scene, (WIDTH, HEIGHT)).convert("RGBA")
        add_text(canvas, frame["title"], frame["subtitle"], frame["ink"])
        raw = Image.open(source_dir / frame["raw"]).convert("RGB")
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
