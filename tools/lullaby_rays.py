"""Lullaby ground effect: twisted sunburst with a jagged wave travelling outwards,
warped as if projected over bumpy ground.

Usage:
  python3 lullaby_rays.py sheet <out.png> [size] [frames]

One loop = 2 pulses = 120 ticks:
  - the twist swings one way during the first pulse and back during the second
  - each pulse sends a jagged wave from the centre to the edge
  - the rays turn by exactly one ray + gap (the pattern repeats PERIODS times
    around the circle), so the rotation is baked in and loops seamlessly
  - a fixed, low-frequency warp bends the rays and the outer edge as if the
    pattern were projected over bumpy ground. Because the rotation is baked in
    (not done by turning the sprite at runtime), the bumps stay put while the
    rays sweep across them.
White + alpha, tinted in game.
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

PERIODS = 12          # ray + gap pairs around the circle (24 wedges)
RAY_SHARE = 0.48      # fraction of each period that is ray
TWIST = 0.45          # radians of twist from centre to edge, each way
LOOP_TICKS = 120      # two pulses
PULSE_TICKS = 60
WAVE_TICKS = 45       # time for the jagged wave to cross from centre to edge
JAG_AMP = 0.10        # radians of zigzag at the wave front
JAG_FREQ = 22         # zigzags from centre to edge
JAG_WIDTH = 0.11      # width of the jagged band (fraction of radius)
WARP = 0.055          # bumpy-ground displacement (fraction of radius)
EDGE_WOBBLE = 0.07    # how much the outer edge wanders in and out
GRAIN = 0.675         # how far the dim patches drop (0.675 = down to about a third)
GRAIN_SCALE = 0.45    # size of the patches (smaller = bigger patches)
GRAIN_BIAS = 0.6      # < 1 spreads the dim patches over more of the rays
GRAIN_CONTRAST = 0.3  # 0 = as is, 1 = strong; a gentle push toward brighter brights and dimmer dims
GRAIN_DRIFT = 0.07    # how far the smoke drifts around its loop (texture widths)
DEPTH_TOP = 0.25       # brightness at the top edge (farthest from the camera); bottom is 1.0
DEPTH_CURVE = 1.2     # > 1 keeps the near half brighter for longer
EDGE_ROUGH = 0.06     # ragged ray edges (fraction of a ray + gap period)

_rng = np.random.default_rng(11)
# A handful of smooth waves in random directions = gentle bumps.
_waves = [(_rng.uniform(0, 2 * np.pi), _rng.uniform(2.0, 5.0), _rng.uniform(0, 2 * np.pi), _rng.uniform(0.5, 1.0))
          for _ in range(6)]


def grid(n):
    c = (n - 1) / 2
    y, x = np.mgrid[0:n, 0:n]
    return (x - c) / c, (y - c) / c


def bumps(dx, dy, seed_shift=0.0):
    out = np.zeros_like(dx)
    total = 0
    for ang, freq, ph, amp in _waves:
        out += amp * np.sin(freq * (dx * np.cos(ang) + dy * np.sin(ang)) + ph + seed_shift)
        total += amp
    return out / total


def _noise_tex(size, blurs, seed, wrap=True):
    """Smooth random texture in [-1, 1]: a few octaves of blurred noise."""
    from scipy import ndimage
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size))
    for sigma, amp in blurs:
        n = ndimage.gaussian_filter(rng.normal(0, 1, (size, size)), sigma, mode="wrap" if wrap else "reflect")
        out += amp * n / (np.abs(n).max() + 1e-9)
    return out / (np.abs(out).max() + 1e-9)


_GRAIN_TEX = _noise_tex(512, [(18, 1.0), (6, 0.6), (2, 0.35)], 21)   # smoke, layer A
_GRAIN_TEX_B = _noise_tex(512, [(18, 1.0), (6, 0.6), (2, 0.35)], 22) # smoke, layer B
_EDGE_TEX = _noise_tex(512, [(10, 1.0), (3, 0.5)], 33)              # travels with the rays



def _sample(tex, u, v):
    """Sample a wrapping texture at u, v in texture-widths (bilinear)."""
    from scipy import ndimage
    n = tex.shape[0]
    return ndimage.map_coordinates(tex, [(v * n) % n, (u * n) % n], order=1, mode="wrap")


def tri(v):
    """Triangle wave in [-1, 1] with period 1: gives zigzag (jagged) edges."""
    return 4 * np.abs(v - np.floor(v + 0.5)) - 1


def ray_alpha(dx, dy, tick):
    t = tick % LOOP_TICKS
    # Bumpy ground: displace the sample point, fixed in world space.
    wx = dx + WARP * bumps(dx, dy, 0.0)
    wy = dy + WARP * bumps(dx, dy, 1.7)
    r = np.sqrt(wx * wx + wy * wy)
    th = np.arctan2(wy, wx)
    period = 2 * np.pi / PERIODS
    rotation = period * t / LOOP_TICKS                     # one period per loop
    twist = TWIST * np.sin(2 * np.pi * t / LOOP_TICKS)     # one way, then back
    off = twist * r + rotation
    since = t % PULSE_TICKS
    if since < WAVE_TICKS:
        front = 0.08 + (since / WAVE_TICKS) * 1.0
        band = np.exp(-((r - front) / JAG_WIDTH) ** 2)
        amp = JAG_AMP * (1 - 0.5 * since / WAVE_TICKS)
        off = off + amp * band * tri(r * JAG_FREQ + 0.37 * np.floor(th * 6))
    a = ((th - off) % period) / period
    # Ragged edges: nudge each point's place in its ray by noise that moves with the rays.
    ray_u = (th - off) / (2 * np.pi)
    a = a + EDGE_ROUGH * _sample(_EDGE_TEX, ray_u * 3.0, r * 1.6)
    m = ((a % 1.0) < RAY_SHARE).astype(float)
    # Patchy opacity, fixed to the ground like a rough surface catching the light.
    # Smoke: two noise layers drifting around small circles in opposite directions
    # and crossfading, so patches grow, shrink and shift. Everything returns to its
    # start after one loop, so the animation loops seamlessly.
    ph = 2 * np.pi * t / LOOP_TICKS
    ua, va = dx * GRAIN_SCALE + 0.5, dy * GRAIN_SCALE + 0.5
    na = _sample(_GRAIN_TEX, ua + GRAIN_DRIFT * np.cos(ph), va + GRAIN_DRIFT * np.sin(ph))
    nb = _sample(_GRAIN_TEX_B, ua - GRAIN_DRIFT * np.sin(ph), va + GRAIN_DRIFT * np.cos(ph))
    mix = 0.5 - 0.5 * np.cos(ph)                                  # A -> B -> A over the loop
    n = (na * (1 - mix) + nb * mix) / np.sqrt((1 - mix) ** 2 + mix ** 2)
    v = np.clip(0.5 + 0.5 * n, 0, 1)
    v = np.clip((v - 0.5) * (1 + 2 * GRAIN_CONTRAST) + 0.5, 0, 1)
    m = m * np.clip(1.0 - GRAIN * v ** GRAIN_BIAS, 0, 1)
    # Uneven outer edge, hollow centre.
    rr = np.sqrt(dx * dx + dy * dy)
    edge = 1.0 - EDGE_WOBBLE * (0.5 + 0.5 * bumps(dx * 1.3, dy * 1.3, 3.1))
    fade = np.clip((rr - 0.08) / 0.12, 0, 1) * np.clip((edge - rr) / 0.35, 0, 1) ** 1.5
    # Brightness varies a little over the bumps, like light falling on a slope.
    shade = 0.85 + 0.15 * bumps(dx, dy, 4.2)
    # Depth: brightest at the bottom of the screen (nearest the camera), dimmer toward the top.
    near = np.clip((dy + 1) / 2, 0, 1) ** (1 / DEPTH_CURVE)
    depth = DEPTH_TOP + (1 - DEPTH_TOP) * near
    return m * fade * shade * depth


def to_rgba(alpha, n, blur=0.7):
    im = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(blur))
    o = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    o.putalpha(im)
    return o


def soft_sheet(out, n, frames, blur, gain, cols=8):
    """Blurred copy of the rays at lower resolution: used for the bloom layer and the light."""
    big = n * 2
    dx, dy = grid(big)
    rows = (frames + cols - 1) // cols
    sheet = Image.new("RGBA", (n * cols, n * rows))
    for i in range(frames):
        tick = i * LOOP_TICKS / frames
        a = np.clip(ray_alpha(dx, dy, tick) * gain, 0, 1)
        im = Image.fromarray((a * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(blur * 2))
        im = im.resize((n, n), Image.LANCZOS)
        o = Image.new("RGBA", (n, n), (255, 255, 255, 0))
        o.putalpha(im)
        sheet.paste(o, ((i % cols) * n, (i // cols) * n))
    sheet.save(out, optimize=True)
    print(f"{frames} soft frames of {n}px, blur {blur}px, {cols}x{rows}")


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "bloom":
    # Bloom: same timing as the rays (40 frames / 120 ticks), half resolution, blurred.
    soft_sheet(sys.argv[2], 192, 40, blur=5, gain=1.3)

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "light":
    # Light: 20 frames (one every 6 ticks), more blur; swapped by script.
    soft_sheet(sys.argv[2], 192, 20, blur=4, gain=1.5, cols=5)

if __name__ == "__main__" and sys.argv[1] == "sheet":
    out = sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 384
    frames = int(sys.argv[4]) if len(sys.argv) > 4 else 40
    dx, dy = grid(n)
    cols = 8
    rows = (frames + cols - 1) // cols
    sheet = Image.new("RGBA", (n * cols, n * rows))
    for i in range(frames):
        tick = i * LOOP_TICKS / frames
        sheet.paste(to_rgba(ray_alpha(dx, dy, tick), n), ((i % cols) * n, (i // cols) * n))
    sheet.save(out, optimize=True)
    print(f"{frames} frames of {n}px, {cols}x{rows}, 1 frame every {LOOP_TICKS / frames:g} ticks")
