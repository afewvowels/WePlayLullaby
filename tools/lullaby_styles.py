"""Alternative looks for Lullaby's rays, built on lullaby_rays.ray_alpha.

Usage:
  python lullaby_styles.py halftone [out.png]   halftone dots riding the rays
  python lullaby_styles.py streaks  [out.png]   rays made of fine radial lines
  (default output: ../graphics/entity/lullaby-rays.png, i.e. replaces the rays)

halftone: the rays are rebuilt from dots on a polar grid that rides the rays
  (rotation, twist and jagged wave move the dots). Dot size follows the ray's
  brightness (falloff, smoke, depth). Between pulses the dots vibrate in place;
  as each pulse's wave passes through they're shoved outward and sideways.
streaks: the rays are filled with fine black / grey / white lines running along
  the ray, like noise stretched 100x in one direction. The lines ride the rays
  and flow outward over the loop; the pulse wave brightens them as it passes.
All loops are seamless (every motion completes whole cycles in LOOP_TICKS).
"""
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

import lullaby_rays as R

# Halftone
DOT_SPACING = 0.034       # grid spacing (fraction of radius); ~29 rings of dots
DOT_FILL = 1.05           # dot diameter at full brightness, relative to the spacing
DOT_MIN = 0.06            # brightness below which a dot isn't drawn
VIBRATE = 0.16            # jitter between pulses (fraction of spacing)
VIBRATE_CYCLES = (7, 9, 11)  # jitter cycles per loop (whole numbers keep the loop seamless)
WAVE_PUSH = 0.55          # how far the pulse wave shoves dots outward (fraction of spacing)
WAVE_SWAY = 0.9           # ...and sideways
# Streaks
STREAK_LINES = 5.0        # how many texture widths around the circle (more = finer lines)
STREAK_ALONG = 0.35       # texture widths from centre to edge (low = long lines)
STREAK_FLOW = 0.5         # how far the lines flow outward per loop (texture widths)
STREAK_DARK = 0.04        # darkest lines (0 = black)
STREAK_CONTRAST = 2.6
STREAK_BLUR = 0.7         # px (at 384) of blur on the lines, so they're soft rather than crisp
STREAK_WAVER = 0.03       # lines wander sideways a little along their length (texture widths)
STREAK_SHIMMER = 0.3      # each line's brightness flickers by up to this much
STREAK_SHIMMER_CYCLES = 6 # flickers per loop (whole number keeps the loop seamless)
STREAK_SOLID_FROM = 0.3   # streaks start fading into solid colour here (fraction of radius)...
STREAK_SOLID_AT = 0.85    # ...and the ray is solid from here out
STREAK_WAVE_AMP = 0.0     # wavy displacement across the lines (texture widths; ~0.006 = one line)
STREAK_WAVE_SCALE = 4.0   # waves from centre to edge (bigger = tighter ripples)
STREAK_WAVE_TRAVEL = 1    # how many waves travel outward per loop (whole number)

_rng = np.random.default_rng(5)
_PHASES = _rng.uniform(0, 2 * np.pi, (3, 4096, 3))     # per-dot jitter phases


def _streak_tex():
    # Noise blurred much more along one axis than the other: long thin streaks.
    rng = np.random.default_rng(41)
    n = rng.normal(0, 1, (512, 512))
    n = ndimage.gaussian_filter(n, (24, 1.2), mode="wrap")   # (along v, across u)
    return n / (np.abs(n).max() + 1e-9)


_STREAK = _streak_tex()


def _streak_tex_b():
    rng = np.random.default_rng(42)
    n = ndimage.gaussian_filter(rng.normal(0, 1, (512, 512)), (24, 1.2), mode="wrap")
    return n / (np.abs(n).max() + 1e-9)


_STREAK_B = _streak_tex_b()


def ray_offset(r, phi, t):
    """The angular offset lullaby_rays applies at radius r (rotation, twist, jagged wave)."""
    period = 2 * np.pi / R.PERIODS
    off = R.TWIST * np.sin(2 * np.pi * t / R.LOOP_TICKS) * r + period * t / R.LOOP_TICKS
    since = t % R.PULSE_TICKS
    wave = np.zeros_like(r)
    if since < R.WAVE_TICKS:
        front = 0.08 + (since / R.WAVE_TICKS)
        wave = np.exp(-((r - front) / R.JAG_WIDTH) ** 2) * (1 - 0.5 * since / R.WAVE_TICKS)
        off = off + R.JAG_AMP * wave * R.tri(r * R.JAG_FREQ + 0.37 * np.floor(phi * 6))
    return off, wave


def halftone_alpha(n, tick):
    t = tick % R.LOOP_TICKS
    dx, dy = R.grid(n)
    field = R.ray_alpha(dx, dy, t)                     # brightness to reproduce with dots
    peak = max(field.max(), 1e-6)
    r = np.sqrt(dx * dx + dy * dy)
    th = np.arctan2(dy, dx)
    off0, _ = ray_offset(r, th, t)
    phi = th - off0                                    # pixel position in ray coordinates
    s = DOT_SPACING
    ring = np.round(r / s).astype(int)
    out = np.zeros_like(r)
    loop = 2 * np.pi * t / R.LOOP_TICKS
    for di in (-1, 0, 1):
        i = np.clip(ring + di, 1, None)
        ri = i * s
        count = np.maximum(6, np.round(2 * np.pi * ri / s)).astype(int)
        step = 2 * np.pi / count
        j0 = np.round(phi / step).astype(int)
        for dj in (-1, 0, 1):
            j = (j0 + dj) % count
            # Vibration: whole cycles per loop, random phase per dot.
            k1, k2, k3 = VIBRATE_CYCLES
            seed = (i * 7919 + j * 104729) % 4096
            p1 = _PHASES[0, seed, 0]; p2 = _PHASES[1, seed, 1]; p3 = _PHASES[2, seed, 2]
            jr = VIBRATE * s * (np.sin(k1 * loop + p1) * 0.6 + np.sin(k3 * loop + p3) * 0.4)
            ja = VIBRATE * s * np.sin(k2 * loop + p2)
            dot_phi = j * step
            # The pulse wave shoves dots outward and sideways as it passes.
            _, wave = ray_offset(ri, dot_phi, t)
            sway = WAVE_SWAY * s * wave * np.sin(p1 + 3 * loop)
            dot_r = ri + jr + WAVE_PUSH * s * wave
            off, _ = ray_offset(dot_r, dot_phi, t)
            ang = dot_phi + off + (ja + sway) / np.maximum(dot_r, 1e-3)
            cx, cy = dot_r * np.cos(ang), dot_r * np.sin(ang)
            # Brightness of the rays where the dot sits.
            px = (cx + 1) * (n - 1) / 2
            py = (cy + 1) * (n - 1) / 2
            b = ndimage.map_coordinates(field, [py, px], order=1, mode="constant") / peak
            rad = 0.5 * DOT_FILL * s * np.sqrt(np.clip(b, 0, 1))
            rad = np.where(b < DOT_MIN, 0, rad)
            d = np.sqrt((dx - cx) ** 2 + (dy - cy) ** 2)
            aa = 1.5 / n                                  # ~0.75 px soft edge
            out = np.maximum(out, np.clip((rad - d) / aa + 0.5, 0, 1) * (rad > 0))
    # Dots are full strength; keep a little of the depth fade on top so the far half stays quiet.
    return out * (0.35 + 0.65 * R.depth_weight(dy))


def streak_alpha(n, tick):
    t = tick % R.LOOP_TICKS
    dx, dy = R.grid(n)
    base = R.ray_alpha(dx, dy, t)
    r = np.sqrt(dx * dx + dy * dy)
    th = np.arctan2(dy, dx)
    off, wave = ray_offset(r, th, t)
    loop = 2 * np.pi * t / R.LOOP_TICKS
    u = (th - off) / (2 * np.pi) * STREAK_LINES          # across the rays: fast
    v = r * STREAK_ALONG - STREAK_FLOW * t / R.LOOP_TICKS  # along the rays: slow, flowing out
    # Organic: lines wander sideways along their length, and the wander drifts over the loop.
    u = u + STREAK_WAVER * R._sample(R._GRAIN_TEX, u * 0.15 + 0.3 * np.cos(loop), v * 2.0 + 0.3 * np.sin(loop))
    # Wavy displacement: smooth noise waves along the rays that travel outward over the loop.
    if STREAK_WAVE_AMP > 0:
        wv = r * STREAK_WAVE_SCALE / 4.0 - STREAK_WAVE_TRAVEL * t / R.LOOP_TICKS
        u = u + STREAK_WAVE_AMP * R._sample(R._GRAIN_TEX, u * 0.04 + 0.5, wv)
    # Two line patterns crossfading over the loop, so lines fade in and out.
    mix = 0.5 - 0.5 * np.cos(loop)
    s = (R._sample(_STREAK, u, v) * (1 - mix) + R._sample(_STREAK_B, u, v) * mix) / np.sqrt((1 - mix) ** 2 + mix ** 2)
    s = np.clip(0.5 + 0.5 * s * STREAK_CONTRAST, 0, 1)
    # Shimmer: each line flickers on its own phase.
    phase = 2 * np.pi * (0.5 + 0.5 * R._sample(_STREAK_B, u * 0.5 + 0.21, 0.37 + 0 * v))
    s = s * (1 - STREAK_SHIMMER * (0.5 + 0.5 * np.sin(STREAK_SHIMMER_CYCLES * loop + phase)))
    # Soften the lines (not the ray edges).
    if STREAK_BLUR > 0:
        s = ndimage.gaussian_filter(s, STREAK_BLUR * n / 384)
    s = STREAK_DARK + (1 - STREAK_DARK) * s
    # Fade the streaks out along the ray so its outer end is solid colour.
    k = np.clip((r - STREAK_SOLID_FROM) / (STREAK_SOLID_AT - STREAK_SOLID_FROM), 0, 1)
    k = k * k * (3 - 2 * k)
    solid = 0.75                                           # roughly the streaks' average brightness
    s = s * (1 - k) + solid * k
    s = np.clip(s + 0.35 * wave, 0, 1)                    # the pulse wave lights the lines up
    return base * s


def build(kind, out, n=384, frames=40):
    fn = halftone_alpha if kind == "halftone" else streak_alpha
    cols = 8
    rows = (frames + cols - 1) // cols
    sheet = Image.new("RGBA", (n * cols, n * rows))
    for k in range(frames):
        a = fn(n, k * R.LOOP_TICKS / frames)
        if kind == "streaks":
            dx, dy = R.grid(n)
            a = R.soften(a, dy, n)
        im = Image.fromarray((np.clip(a, 0, 1) * 255).astype("uint8"))
        o = Image.new("RGBA", (n, n), (255, 255, 255, 0))
        o.putalpha(im)
        sheet.paste(o, ((k % cols) * n, (k // cols) * n))
    sheet.save(out, optimize=True)
    print(f"{kind}: {frames} frames of {n}px -> {out}")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("halftone", "streaks"):
        print(__doc__)
        sys.exit(1)
    here = os.path.dirname(os.path.abspath(__file__))
    default = os.path.normpath(os.path.join(here, "..", "graphics", "entity", "lullaby-rays.png"))
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else default)
