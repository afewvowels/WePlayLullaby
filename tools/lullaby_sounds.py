"""Build Lullaby's sounds from the Brass_Swell_5.wav clip.

Usage: python lullaby_sounds.py <Brass_Swell_5.wav> [out_dir]   (default out_dir: ../sounds next to this script)
Needs: numpy, scipy (pip install numpy scipy) and ffmpeg on your PATH (for the .ogg files)

The clip is a dense, steady brass pad (~0.1-5.1 s) with a natural release
(~5.1-6.3 s). Everything is timed in game ticks (60 per second):

  start.ogg      30-tick swell-in: fade in while the pitch swoops 0.55x -> 1x
  pulse-N.ogg    one pulse: 60 ticks of pad + 5-tick equal-power fades on each
                 end (70 ticks total), with an "old record" tone (band-limited,
                 wow & flutter, light crackle) and a sub-bass thrum on the beat.
                 Played every 60 ticks, starting 5 ticks before the beat, so
                 the fades overlap and crossfade. Three variants from
                 different parts of the pad so it doesn't repeat.
  stop.ogg       record running down: the clip's own release, slowing from
                 1x to 0.3x pitch, ~0.9 s
  scratch.ogg    missed pulse / brown-out: a quick back-and-forth scrub
"""
import sys, os, wave, subprocess
import numpy as np
from scipy import signal

SR = 44100
TICK = SR / 60.0

if len(sys.argv) < 2:
    print(__doc__)
    sys.exit(1)
src = sys.argv[1]
out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds"))
os.makedirs(out_dir, exist_ok=True)

w = wave.open(src)
assert w.getframerate() == SR
x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, w.getnchannels())
pad = x.astype(np.float64).mean(axis=1) / 32768.0
rng = np.random.default_rng(7)


def ticks(n):
    return int(round(n * TICK))


def varispeed(sig, start, speed_curve):
    """Read `sig` from sample `start` at a time-varying playback speed (1 = normal)."""
    pos = start + np.cumsum(speed_curve)
    pos = np.clip(pos, 0, len(sig) - 2)
    return np.interp(pos, np.arange(len(sig)), sig)


def old_record(sig):
    """Gramophone tone: band-limit, gentle wow & flutter, light crackle."""
    n = len(sig)
    t = np.arange(n) / SR
    wow = 1 + 0.004 * np.sin(2 * np.pi * 0.55 * t) + 0.0015 * np.sin(2 * np.pi * 6.3 * t)
    sig = varispeed(np.concatenate([sig, np.zeros(SR)]), 0, wow)[:n]
    b, a = signal.butter(2, [220, 3800], btype="band", fs=SR)
    sig = signal.lfilter(b, a, sig)
    crackle = np.zeros(n)
    hits = rng.random(n) < 18 / SR  # ~18 pops per second
    crackle[hits] = rng.normal(0, 0.25, hits.sum())
    bc, ac = signal.butter(2, 2500, btype="high", fs=SR)
    crackle = signal.lfilter(bc, ac, crackle) + rng.normal(0, 0.004, n)
    return sig + crackle * 0.35


def thrum(n):
    """Sub-bass pulse: the brass pad's lows dropped an octave, short swell."""
    seg = pad[ticks(60):ticks(60) + 2 * n + SR]
    low = varispeed(seg, 0, np.full(n, 0.5))
    b, a = signal.butter(4, 140, btype="low", fs=SR)
    low = signal.lfilter(b, a, low)
    t = np.arange(n) / SR
    env = (1 - np.exp(-t / 0.03)) * np.exp(-t / 0.28)
    low = low / (np.abs(low).max() + 1e-9)
    return low * env


def fades(sig, fin, fout):
    n = len(sig)
    env = np.ones(n)
    if fin:
        env[:fin] = np.sin(np.linspace(0, np.pi / 2, fin)) ** 2
    if fout:
        env[-fout:] = np.cos(np.linspace(0, np.pi / 2, fout)) ** 2
    return sig * env


def write(name, sig, peak_db=-1.0):
    sig = sig / (np.abs(sig).max() + 1e-12) * 10 ** (peak_db / 20)
    tmp = os.path.join(out_dir, name + ".wav")
    with wave.open(tmp, "wb") as o:
        o.setnchannels(1); o.setsampwidth(2); o.setframerate(SR)
        o.writeframes((sig * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5",
                    os.path.join(out_dir, name + ".ogg")], check=True)
    os.remove(tmp)
    return sig


FADE = ticks(5)
BODY = ticks(60)

# Pulse chunks: 5-tick fade-in, 60-tick body, 5-tick fade-out. The thrum lands
# on the beat, 5 ticks in (where the chunk reaches full level).
pulses = []
for i, start_s in enumerate([0.6, 2.1, 3.6]):
    s = int(start_s * SR)
    seg = pad[s:s + BODY + 2 * FADE].copy()
    music = old_record(seg)
    th = np.zeros_like(seg)
    tn = len(seg) - FADE
    th[FADE:] = thrum(tn)
    mix = 0.75 * music / np.abs(music).max() + 0.6 * th
    pulses.append(write(f"pulse-{i + 1}", fades(mix, FADE, FADE), peak_db=-3.0))

# Start: 30 ticks, fade in while the pitch swoops up into the pad, then hands
# over to the first pulse (which starts 5 ticks before the beat).
n = ticks(30) + FADE
sp = 0.55 + 0.45 * (np.linspace(0, 1, n) ** 0.6)
start = old_record(varispeed(pad, int(0.15 * SR), sp))
env = np.linspace(0, 1, n) ** 1.6
start = start / np.abs(start).max() * env
start[-FADE:] *= np.cos(np.linspace(0, np.pi / 2, FADE)) ** 2
write("start", start, peak_db=-4.0)

# Stop: the clip's own release, slowing like a turntable losing power.
n = int(0.9 * SR)
sp = np.linspace(1.0, 0.3, n) ** 1.3
stop = old_record(varispeed(pad, int(4.6 * SR), sp))
stop = fades(stop, FADE, int(0.35 * SR)) * np.linspace(1, 0.6, n)
write("stop", stop, peak_db=-3.0)

# Scratch: scrub back and forth over the pad.
n = int(0.45 * SR)
t = np.linspace(0, 1, n)
sp = 3.2 * np.sin(2 * np.pi * 2.2 * t) * (1 - t) ** 0.5 + 0.2
sc = varispeed(pad, int(2.5 * SR), sp)
b, a = signal.butter(2, [300, 5000], btype="band", fs=SR)
sc = signal.lfilter(b, a, sc) * np.exp(-t * 2.5)
sc = fades(sc, ticks(1), ticks(4))
write("scratch", sc, peak_db=-2.0)

print("wrote", sorted(os.listdir(out_dir)))
