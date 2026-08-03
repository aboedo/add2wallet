#!/usr/bin/env python3
"""Generates the tall portrait screenshot the regression flow imports from Photos.

Real ticket screenshots can't live in this repo, so we synthesise one with the
same shape: a 1320x2868 phone screenshot, which is what used to make the
"View original file" preview blow out the layout.

Usage:
    python3 maestro/regression/make_fixture.py
    xcrun simctl addmedia booted maestro/regression/output/portrait_ticket.png
"""

import pathlib

from PIL import Image, ImageDraw

WIDTH, HEIGHT = 1320, 2868
OUTPUT = pathlib.Path(__file__).parent / "output" / "portrait_ticket.png"

BACKGROUND = (28, 39, 52)
CARD = (255, 255, 255)
MUTED = (150, 160, 172)


def main() -> None:
    image = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(image)

    # Fake mail header
    draw.rectangle([0, 0, WIDTH, 330], fill=(20, 28, 38))
    draw.ellipse([60, 190, 180, 310], fill=(226, 178, 178))
    draw.text((220, 240), "tickets@example.test", fill=MUTED)

    # Ticket card
    draw.rounded_rectangle([60, 880, WIDTH - 60, 1960], radius=40, fill=CARD)
    draw.text((140, 960), "SAMPLE EVENT - Day Tickets", fill=(24, 24, 24))
    draw.text((140, 1040), "Ticket ID: 000000000", fill=MUTED)

    # Two placeholder barcodes — enough structure to look like a real ticket
    for index, left in enumerate((260, 740)):
        draw.rectangle([left, 1320, left + 320, 1640], fill=(255, 255, 255))
        for row in range(16):
            for column in range(16):
                if (row * 7 + column * 5 + index) % 3:
                    continue
                x = left + 10 + column * 19
                y = 1330 + row * 19
                draw.rectangle([x, y, x + 17, y + 17], fill=(0, 0, 0))

    draw.rounded_rectangle([60, 2040, WIDTH - 60, 2760], radius=40, outline=CARD, width=4)
    draw.text((140, 2120), "Read this before attending", fill=CARD)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(f"wrote {OUTPUT} ({WIDTH}x{HEIGHT})")


if __name__ == "__main__":
    main()
