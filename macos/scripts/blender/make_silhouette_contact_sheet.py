#!/usr/bin/env python3
"""Review all brand source PNGs beside the masks actually used by Blender.

Requires Pillow, already used by the repository's brand icon acquisition tools.
This script never changes source icons or runtime meshes.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

MACOS = Path(__file__).resolve().parents[2]
ART = MACOS / "Resources" / "KeychainArt"
ICONS = MACOS / "Resources" / "ProviderIcons"
manifest = json.loads((ART / "manifest.json").read_text())
providers = sorted(manifest["providers"])
columns, cell_width, cell_height = 7, 270, 184
rows = (len(providers) + columns - 1) // columns
sheet = Image.new("RGB", (columns * cell_width, rows * cell_height), "#E5EAF0")
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 17)
    small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 11)
except OSError:
    font = small = ImageFont.load_default()

for i, provider in enumerate(providers):
    x, y = (i % columns) * cell_width, (i // columns) * cell_height
    draw.rounded_rectangle((x + 5, y + 5, x + cell_width - 5, y + cell_height - 5), 8, fill="#F7F9FB")
    for j, path in enumerate((ICONS / f"{provider}.png", ART / "previews" / "masks" / f"{provider}.png")):
        image = Image.open(path).convert("RGBA")
        image.thumbnail((112, 112), Image.Resampling.LANCZOS)
        px, py = x + 14 + j * 130 + (112 - image.width) // 2, y + 12 + (112 - image.height) // 2
        # A pale checker background makes white artwork and true holes visible.
        for tx in range(0, 112, 8):
            for ty in range(0, 112, 8):
                draw.rectangle((x + 14 + j * 130 + tx, y + 12 + ty,
                                x + 21 + j * 130 + tx, y + 19 + ty),
                               fill="#DCE3EB" if (tx + ty) % 16 == 0 else "#EEF1F5")
        sheet.paste(image, (px, py), image)
    extraction = manifest["providers"][provider]["extraction"]
    method = extraction["method"]
    draw.text((x + 14, y + 132), f"{i + 1:02d}  {provider}", fill="#263647", font=font)
    draw.text((x + 14, y + 155), "source  >  " + ("alpha silhouette" if method == "alpha" else "background/detail separated"), fill="#4C647C", font=small)

output = ART / "previews" / "all-brand-silhouettes.png"
sheet.save(output)
special = [p for p in providers if manifest["providers"][p]["extraction"]["method"] != "alpha"]
print(f"Saved {output} ({len(providers)} source/mask pairs)")
print("Separated backgrounds/details: " + ", ".join(special))
