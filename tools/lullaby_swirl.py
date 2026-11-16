"""Entranced overhead effect: a line swirling upwards like a mini tornado.

Usage: python lullaby_swirl.py [out_dir] [--variants]
  Default out_dir: ../graphics/entity next to this script. Writes lullaby-swirl.png
  (the single swirl the mod uses); --variants also writes the double and tight ones.
Needs: numpy, pillow  (pip install numpy pillow)

Writes, for each variant, a white + alpha sprite sheet (tinted in game) of
FRAMES frames that loops seamlessly as the coil spins, plus preview GIFs.

The swirl is a helix on a funnel: narrow at the bottom, wide at the top,
viewed from slightly above so the loops read as ellipses. The half of each
loop behind the axis is drawn thinner and dimmer, so it reads as coiling
around rather than as a flat zigzag. A coil climbs as it spins.
"""
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

FRAMES = 16
SIZE = 128          # frame size in px
SS = 4              # supersampling

VARIANTS = {
    # name: turns, strands, bottom radius, top radius, line width (px at SIZE)
    "single": dict(turns=3.0, strands=1, r0=0.05, r1=0.36, width=5.0),
    "double": dict(turns=2.5, strands=2, r0=0.05, r1=0.34, width=4.0),
    "tight":  dict(turns=4.5, strands=1, r0=0.04, r1=0.30, width=4.0),
}


def render(frame, turns, strands, r0, r1, width, tilt=0.32):
    n = SIZE * SS
    img = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(img)
    phase = 2 * np.pi * frame / FRAMES
    pts = 600
    h = np.linspace(0, 1, pts)                   # 0 = bottom, 1 = top
    rad = r0 + (r1 - r0) * h ** 1.4              # funnel
    segs = []
    for s in range(strands):
        th = 2 * np.pi * turns * h - phase + s * 2 * np.pi / strands
        x = rad * np.cos(th)
        z = rad * np.sin(th)                     # depth: + is toward the viewer
        y = 0.44 - 0.80 * h - z * tilt           # screen up = negative
        front = z / np.maximum(rad, 1e-6)        # -1 back .. 1 front
        # fade the ends of the line
        ends = np.clip(h / 0.12, 0, 1) * np.clip((1 - h) / 0.1, 0, 1)
        for i in range(pts - 1):
            segs.append((front[i], x[i], y[i], x[i + 1], y[i + 1], h[i], ends[i]))
    segs.sort(key=lambda s: s[0])                # back first
    for f, xa, ya, xb, yb, hh, e in segs:
        k = 0.5 + 0.5 * f                        # 0 back .. 1 front
        wpx = width * SS * (0.45 + 0.55 * hh) * (0.55 + 0.45 * k)
        val = int(255 * e * (0.35 + 0.65 * k))
        p = lambda u, v: ((u + 0.5) * n, (v + 0.5) * n)
        d.line([p(xa, ya), p(xb, yb)], fill=val, width=max(1, int(wpx)))
        rr = wpx / 2
        cx, cy = p(xb, yb)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=val)
    img = img.filter(ImageFilter.GaussianBlur(SS * 0.4)).resize((SIZE, SIZE), Image.LANCZOS)
    return img


def rgba(alpha):
    o = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    o.putalpha(alpha)
    return o


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = args[0] if args else os.path.normpath(os.path.join(here, "..", "graphics", "entity"))
    variants = VARIANTS if "--variants" in sys.argv else {"single": VARIANTS["single"]}
    os.makedirs(out, exist_ok=True)
    for name, v in variants.items():
        frames = [rgba(render(i, **v)) for i in range(FRAMES)]
        sheet = Image.new("RGBA", (SIZE * 8, SIZE * ((FRAMES + 7) // 8)))
        for i, f in enumerate(frames):
            sheet.paste(f, ((i % 8) * SIZE, (i // 8) * SIZE))
        path = os.path.join(out, "lullaby-swirl.png" if name == "single" else f"lullaby-swirl-{name}.png")
        sheet.save(path, optimize=True)
        print("  ->", path)
