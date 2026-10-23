"""Combine the 3D cover render with the cover text layer.

    python3 promo/composite/make_cover.py

Reads promo/build/cover/cover_3d.png and cover_text.png.
Writes promo/out/灵感晾台-封面.png and a JPEG copy for embedding.
"""
import os

import numpy as np
from PIL import Image

PROMO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COVER = os.path.join(PROMO, "build", "cover")
OUT = os.path.join(PROMO, "out")
CREAM = np.array([0.968, 0.958, 0.925], dtype=np.float32)
W, H = 1920, 1080


def main():
    bg = Image.open(os.path.join(COVER, "cover_3d.png")).convert("RGB").resize((W, H), Image.LANCZOS)
    x = np.asarray(bg).astype(np.float32) / 255
    # soft cream scrim behind the title block (lower left)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    up = np.clip((yy / H - 0.50) / 0.42, 0, 1) ** 1.2
    side = np.clip(1 - (xx / (W * 0.72)) ** 2, 0, 1)
    a = (0.45 * up * side)[..., None]
    x = x * (1 - a) + CREAM * a
    # gentle vignette, matching the film
    r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 * 0.8 + ((yy - H / 2) / (H / 2)) ** 2)
    x *= (1 - 0.10 * np.clip(r - 0.35, 0, None) ** 1.6)[..., None]
    base = Image.fromarray(np.clip(x * 255 + 0.5, 0, 255).astype(np.uint8)).convert("RGBA")
    text = Image.open(os.path.join(COVER, "cover_text.png")).convert("RGBA")
    base.alpha_composite(text)
    os.makedirs(OUT, exist_ok=True)
    cover = base.convert("RGB")
    cover.save(os.path.join(OUT, "灵感晾台-封面.png"))
    cover.save(os.path.join(COVER, "cover.jpg"), quality=94)
    print("Wrote", os.path.join(OUT, "灵感晾台-封面.png"))


if __name__ == "__main__":
    main()
