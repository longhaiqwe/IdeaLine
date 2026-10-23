"""Synthesize the music bed and sound effects for the promo.

    python3 promo/audio/make_audio.py

Reads promo/build/events.json (written by build_scene.py) and writes
promo/build/audio/mix.wav (48 kHz stereo) plus music.wav and sfx.wav stems.
Everything is generated here; no samples or downloaded audio.
"""
import json
import math
import os
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROMO = os.path.dirname(HERE)
sys.path.insert(0, PROMO)
import timeline as T  # noqa: E402

SR = 48000
BEAT = 60.0 / T.BPM
DUR = (T.FRAME_END - T.FRAME_START + 1) / T.FPS
N = int(DUR * SR)
OUT = os.path.join(PROMO, "build", "audio")
rng = np.random.default_rng(11)


def frame_time(f):
    return (f - T.FRAME_START) / T.FPS


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def tvec(seconds):
    return np.arange(int(seconds * SR)) / SR


def lp(x, cutoff, order=2):
    b, a = signal.butter(order, cutoff / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, cutoff, order=2):
    b, a = signal.butter(order, cutoff / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


class Bus:
    def __init__(self):
        self.buf = np.zeros((N, 2))

    def add(self, x, at, gain=1.0, pan=0.0):
        """Mix mono or stereo `x` starting at `at` seconds. pan -1..1 (constant power)."""
        start = int(round(at * SR))
        if start >= N:
            return
        if x.ndim == 1:
            l, r = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
            x = np.stack([x * l, x * r], axis=1) * math.sqrt(2)
        if start < 0:
            x = x[-start:]
            start = 0
        end = min(N, start + len(x))
        self.buf[start:end] += x[: end - start] * gain


def reverb_ir(seconds=2.4, decay=0.55, tone=4500, seed=3):
    r = np.random.default_rng(seed)
    t = tvec(seconds)
    ir = np.zeros((len(t), 2))
    for ch in range(2):
        n = r.standard_normal(len(t))
        bright = lp(n, tone)
        dark = lp(n, 1200)
        fade = np.clip(t / seconds * 1.8, 0, 1)
        ir[:, ch] = (bright * (1 - fade) + dark * fade) * np.exp(-t / decay)
    ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))[:, None]
    return ir / np.sqrt(np.sum(ir ** 2) / 2)


def apply_reverb(bus, ir, wet):
    out = np.zeros_like(bus)
    for ch in range(2):
        out[:, ch] = signal.fftconvolve(bus[:, ch], ir[:, ch])[:N]
    return out * wet


# ---------------------------------------------------------------------------
# Instruments

def ep(freq, length, vel=1.0):
    """FM electric piano."""
    t = tvec(length + 1.8)
    decay = 1.6 * (220 / freq) ** 0.35
    env = np.exp(-t / decay) * (1 - np.exp(-t / 0.003))
    env *= np.where(t > length, np.exp(-(t - length) / 0.35), 1.0)
    index = 1.4 * np.exp(-t / 0.4) + 0.2
    mod = np.sin(2 * np.pi * freq * t)
    body = np.sin(2 * np.pi * freq * t + index * mod)
    tine = 0.18 * np.sin(2 * np.pi * freq * 7.0 * t + 0.6 * mod) * np.exp(-t / 0.06)
    trem = 1 + 0.06 * np.sin(2 * np.pi * 4.6 * t)
    return vel * (body + tine) * env * trem


def pad(freqs, length, attack=1.0, release=1.6):
    t = tvec(length + release)
    out = np.zeros((len(t), 2))
    for k, f in enumerate(freqs):
        for ch, det in enumerate((-0.07, 0.07)):
            ff = f * 2 ** (det / 12 + (0.03 if k % 2 else -0.03) / 12)
            wave = np.zeros(len(t))
            for h in range(1, 14):
                if ff * h > 5000:
                    break
                wave += np.sin(2 * np.pi * ff * h * t + h * 0.7) / h
            out[:, ch] += wave
    env = np.clip(t / attack, 0, 1) ** 1.5 * np.where(t > length, np.exp(-(t - length) / (release / 3)), 1.0)
    for ch in range(2):
        out[:, ch] = lp(out[:, ch], 1100, 2) * env
    return out / max(1, len(freqs)) * 0.5


def bass(freq, length):
    t = tvec(length + 0.3)
    env = (1 - np.exp(-t / 0.004)) * np.exp(-t / 0.9) * np.where(t > length, np.exp(-(t - length) / 0.06), 1.0)
    x = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * 2 * freq * t) + 0.08 * np.sin(2 * np.pi * 3 * freq * t)
    return lp(x * env, 900)


def pluck(freq, length=1.6, bright=0.5):
    """Karplus-Strong plucked string via a comb IIR filter."""
    n = int(length * SR)
    delay = max(2, int(round(SR / freq)))
    excite = np.zeros(n)
    burst = rng.uniform(-1, 1, delay)
    burst = lp(burst, 1500 + 5000 * bright)
    excite[:delay] = burst
    d = 0.996
    a = np.zeros(delay + 2)
    a[0] = 1
    a[delay] = -d * 0.5
    a[delay + 1] = -d * 0.5
    y = signal.lfilter([1.0], a, excite)
    y *= np.minimum(1, (np.arange(n)[::-1]) / (0.05 * SR))
    return y / (np.max(np.abs(y)) + 1e-9)


def bell(freq, length=3.5, vel=1.0):
    t = tvec(length)
    index = 3.2 * np.exp(-t / 0.5) + 0.3
    x = np.sin(2 * np.pi * freq * t + index * np.sin(2 * np.pi * freq * 3.5 * t))
    x += 0.35 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t / 0.4)
    env = (1 - np.exp(-t / 0.002)) * np.exp(-t / 1.4)
    return vel * x * env


def kick():
    t = tvec(0.5)
    f = 46 + 75 * np.exp(-t / 0.035)
    phase = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(phase) * np.exp(-t / 0.22)
    click = lp(rng.standard_normal(len(t)), 3000) * np.exp(-t / 0.004) * 0.25
    return x + click


def snap():
    t = tvec(0.35)
    n = rng.standard_normal(len(t))
    x = bp(n, 1400, 5200) * (np.exp(-t / 0.045) + 0.6 * np.exp(-np.maximum(0, t - 0.011) / 0.03) * (t > 0.011))
    return x * 1.4


def shaker(open_=False):
    t = tvec(0.12)
    n = rng.standard_normal(len(t))
    env = (1 - np.exp(-t / 0.006)) * np.exp(-t / (0.05 if open_ else 0.028))
    return hp(n, 6500) * env


def riser(length):
    t = tvec(length)
    n = rng.standard_normal(len(t))
    out = np.zeros(len(t))
    seg = int(0.05 * SR)
    for k in range(0, len(t), seg):
        u = k / len(t)
        lo = 300 + 4000 * u ** 2
        chunk = n[max(0, k - 2000): k + seg]
        fl = bp(chunk, lo, lo * 2.2, 1)[-min(seg, len(t) - k):]
        out[k: k + len(fl)] = fl
    return out * (t / length) ** 2.2


# ---------------------------------------------------------------------------
# Music

music = Bus()
F, A, Bb, C, D, E, G = 65, 69, 70, 72, 74, 76, 67  # F4 etc. reference only
CHORDS = {
    "Fmaj9": [53, 57, 60, 64, 67],      # F3 A3 C4 E4 G4
    "Am7": [57, 60, 64, 67, 72],        # A3 C4 E4 G4 C5
    "Dm9": [50, 57, 60, 64, 65],        # D3 A3 C4 E4 F4
    "Bbmaj7": [46, 53, 57, 62, 65],     # Bb2 F3 A3 D4 F4
    "Gm7": [55, 58, 62, 65, 69],        # G3 Bb3 D4 F4 A4
    "C9sus4": [48, 55, 58, 62, 65],     # C3 G3 Bb3 D4 F4
}
ROOTS = {"Fmaj9": 41, "Am7": 45, "Dm9": 38, "Bbmaj7": 34, "Gm7": 43, "C9sus4": 36}
PROG = ["Fmaj9", "Am7", "Dm9", "Bbmaj7", "Fmaj9", "Am7", "Dm9", "Bbmaj7",
        "Fmaj9", "Am7", "Dm9", "Bbmaj7", "Gm7", "C9sus4", "Fmaj9", "Fmaj9"]
TOTAL_BEATS = DUR / BEAT
GROOVE = (8, 56)      # drums and bass between these beats
SNAPS = (16, 56)
PLUCKS = (16, 56)

for bar, name in enumerate(PROG):
    b0 = bar * 4
    if b0 >= TOTAL_BEATS:
        break
    at = b0 * BEAT
    notes = CHORDS[name]
    last = bar == len(PROG) - 2
    length = 4 * BEAT if bar < len(PROG) - 2 else (TOTAL_BEATS - b0) * BEAT
    # electric piano: whole notes in the intro and the ending, syncopated comping in the groove
    if b0 < GROOVE[0] or b0 >= GROOVE[1]:
        hits = [(0, 4)]
    else:
        hits = [(0, 1.4), (1.5, 1.0), (2.5, 1.4)]
    for off, ln in hits:
        for k, m in enumerate(notes[1:]):
            strum = k * 0.012
            vel = 0.24 if b0 < GROOVE[0] else (0.16 if off == 0 else 0.11)
            music.add(ep(hz(m), ln * BEAT if not last else length, vel), at + off * BEAT + strum, pan=-0.25 + 0.12 * k)
    music.add(pad([hz(m) for m in notes[:4]], length, attack=1.2), at, gain=0.34 if b0 < GROOVE[0] else 0.22)
    if GROOVE[0] <= b0 < GROOVE[1]:
        root = hz(ROOTS[name])
        for off, ln in ((0, 1.3), (1.5, 0.9), (3, 0.8)):
            music.add(bass(root, ln * BEAT), at + off * BEAT, gain=0.42)
        for beat_ in range(4):
            if beat_ in (0, 2) or (beat_ == 3 and bar % 2 == 1):
                kat = at + (beat_ + (0.5 if beat_ == 3 else 0)) * BEAT
                music.add(kick(), kat, gain=0.5 if beat_ != 3 else 0.32)
        for e in range(8):
            swing = 0.06 if e % 2 else 0.0
            music.add(shaker(e % 4 == 2), at + (e * 0.5 + swing) * BEAT, gain=0.09 if e % 2 else 0.13, pan=0.35)
        if SNAPS[0] <= b0 < SNAPS[1]:
            for beat_ in (1, 3):
                music.add(snap(), at + beat_ * BEAT, gain=0.16, pan=-0.1)
    if PLUCKS[0] <= b0 < PLUCKS[1]:
        arp = notes[1:] + [notes[2] + 12]
        pattern = [0, 2, 1, 3, 2, 4, 3, 1]
        for e, idx in enumerate(pattern):
            m = arp[idx % len(arp)] + 12
            music.add(pluck(hz(m), 1.2, 0.35), at + e * 0.5 * BEAT, gain=0.07, pan=0.45 if e % 2 else -0.45)

# reveal -> edges lift, and a soft cymbal-like swell on the edges downbeat
edges_beat = (T.start("edges") - T.FRAME_START) / T.BEAT
music.add(riser(4 * BEAT), (edges_beat - 4) * BEAT, gain=0.06)
swell = lp(hp(rng.standard_normal(int(2.5 * SR)), 3500), 12000) * np.exp(-tvec(2.5) / 0.7)
music.add(swell, edges_beat * BEAT, gain=0.035)

# ending motif on the end card (bell, F major)
end_t = frame_time(T.start("end"))
for k, (m, off) in enumerate(((77, 0.65), (81, 1.15), (84, 1.65), (89, 2.4))):
    music.add(bell(hz(m), 4.0, 0.12 if k < 3 else 0.15), end_t + off, pan=-0.3 + 0.2 * k)

# ---------------------------------------------------------------------------
# Sound effects

sfx = Bus()


def click(level=1.0, tone=1.0):
    t = tvec(0.09)
    n = rng.standard_normal(len(t))
    body = np.sin(2 * np.pi * 190 * tone * t) * np.exp(-t / 0.018)
    tick = hp(n, 2500) * np.exp(-t / 0.004)
    rattle = bp(n, 900, 3000) * np.exp(-t / 0.012) * 0.4
    return level * (0.6 * tick + 0.45 * body + rattle)


def soft_click(level=1.0):
    t = tvec(0.06)
    n = rng.standard_normal(len(t))
    return level * (bp(n, 1800, 7000) * np.exp(-t / 0.006) * 0.8 + np.sin(2 * np.pi * 240 * t) * np.exp(-t / 0.012) * 0.3)


def whoosh(length=0.6, lo=500, hi=3200, peak=0.55):
    t = tvec(length)
    n = rng.standard_normal(len(t))
    out = np.zeros(len(t))
    seg = int(0.02 * SR)
    for k in range(0, len(t), seg):
        u = k / len(t)
        f = lo * (hi / lo) ** (math.sin(math.pi * min(1, u / peak / 2)) if u < peak else 1 - 0.4 * (u - peak))
        chunk = n[max(0, k - 1500): k + seg]
        fl = bp(chunk, f * 0.6, min(f * 1.6, 20000), 1)[-min(seg, len(t) - k):]
        out[k: k + len(fl)] = fl
    env = np.where(t < peak * length, (t / (peak * length)) ** 1.6, np.exp(-(t - peak * length) / (0.25 * length)))
    return out * env


def wood_snap(level=1.0):
    t = tvec(0.25)
    out = np.zeros(len(t))
    for f, d, a in ((1150, 0.05, 0.6), (2380, 0.03, 0.4), (3720, 0.018, 0.3), (420, 0.04, 0.5)):
        out += a * np.sin(2 * np.pi * f * t) * np.exp(-t / d)
    n = rng.standard_normal(len(t))
    out += hp(n, 3000) * np.exp(-t / 0.002) * 0.9
    second = np.zeros(len(t))
    lag = int(0.018 * SR)
    second[lag:] = out[:-lag] * 0.45
    return level * (out + second)


def rustle(length=0.4, level=1.0):
    t = tvec(length)
    imp = (rng.random(len(t)) < 0.004).astype(float) * rng.uniform(0.3, 1, len(t))
    crackle = bp(signal.lfilter([1], [1, -0.6], imp), 2000, 9000)
    hiss = bp(rng.standard_normal(len(t)), 3000, 10000) * 0.08
    env = np.sin(np.pi * np.clip(t / length, 0, 1)) ** 0.7
    return level * (crackle + hiss) * env


def pop(level=1.0):
    t = tvec(0.22)
    f = 520 + 380 * (1 - np.exp(-t / 0.03))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.06)
    air = whoosh(0.22, 800, 2600, 0.3)
    return level * (0.5 * tone + 0.6 * air)


events = json.load(open(os.path.join(PROMO, "build", "events.json")))["events"]
for ev in events:
    at = frame_time(ev["frame"])
    kind = ev["type"]
    if kind == "key_down":
        sfx.add(click(0.9, 1.0 if ev.get("key") not in ("ret",) else 0.8), at, gain=0.55, pan=0.1)
    elif kind == "key_up":
        sfx.add(soft_click(0.7), at, gain=0.35)
    elif kind == "type":
        sfx.add(soft_click(rng.uniform(0.5, 0.9)), at, gain=0.28, pan=rng.uniform(-0.2, 0.2))
    elif kind == "type_commit":
        sfx.add(click(0.5, 0.8), at, gain=0.22)
    elif kind == "pop":
        sfx.add(pop(), at, gain=0.42)
    elif kind == "whoosh_short":
        sfx.add(whoosh(0.3, 900, 3000, 0.4), at, gain=0.25)
    elif kind == "whoosh":
        sfx.add(whoosh(0.75, 450, 3600, 0.55), at, gain=0.5, pan=-0.35)
    elif kind == "clip":
        sfx.add(wood_snap(1.0), at, gain=0.5, pan=-0.3)
        sfx.add(rustle(0.35, 0.9), at, gain=0.25, pan=-0.3)
    elif kind == "paper_shift":
        sfx.add(rustle(0.45, 0.8), at, gain=0.22, pan=0.2)
    elif kind == "swish":
        sfx.add(whoosh(0.45, 600, 3000, 0.45), at, gain=0.33)
    elif kind == "pickup":
        sfx.add(rustle(0.25, 0.9), at, gain=0.22)
        sfx.add(soft_click(0.6), at, gain=0.2)
    elif kind == "slide":
        sfx.add(rustle(1.3, 0.7), at, gain=0.2, pan=-0.2)
        sfx.add(whoosh(1.2, 400, 1500, 0.5), at, gain=0.12, pan=-0.2)
    elif kind == "drop":
        sfx.add(wood_snap(0.7), at, gain=0.42)
    elif kind == "whoosh_soft":
        sfx.add(whoosh(0.9, 300, 2200, 0.5), at, gain=0.3)
    elif kind == "chime":
        pass  # handled by the ending motif

# ---------------------------------------------------------------------------
# Mix

ir_music = reverb_ir(2.6, 0.7)
ir_room = reverb_ir(0.9, 0.18, 7000, seed=5)
music_mix = music.buf + apply_reverb(music.buf, ir_music, 0.22)
music_mix[:, 0] = hp(music_mix[:, 0], 32)
music_mix[:, 1] = hp(music_mix[:, 1], 32)
sfx_mix = sfx.buf + apply_reverb(sfx.buf, ir_room, 0.12)

# gentle ducking of the music under effects
env = np.abs(sfx_mix).max(axis=1)
env = signal.lfilter([1 - math.exp(-1 / (0.08 * SR))], [1, -math.exp(-1 / (0.08 * SR))], env)
duck = 1 - 0.25 * np.clip(env / (env.max() + 1e-9) * 3, 0, 1)
music_mix *= duck[:, None]

t = np.arange(N) / SR
fade_in = np.clip(t / 0.8, 0, 1)
fade_out = np.clip((DUR - t) / 2.2, 0, 1) ** 1.5
music_mix *= (fade_in * fade_out)[:, None]


def norm_rms(x, db):
    rms = np.sqrt(np.mean(x ** 2) + 1e-12)
    return x * (10 ** (db / 20) / rms)


music_mix = norm_rms(music_mix, -21)
sfx_peak = np.max(np.abs(sfx_mix)) + 1e-9
sfx_mix = sfx_mix / sfx_peak * 10 ** (-7 / 20)
mix = music_mix + sfx_mix
mix = np.tanh(mix * 1.15) / 1.15
peak = np.max(np.abs(mix))
mix *= 10 ** (-1 / 20) / peak

os.makedirs(OUT, exist_ok=True)
for name, data in (("music", music_mix), ("sfx", sfx_mix), ("mix", mix)):
    wavfile.write(os.path.join(OUT, f"{name}.wav"), SR, (np.clip(data, -1, 1) * 32767).astype(np.int16))
print(f"Wrote {OUT}/mix.wav ({DUR:.2f} s), {len(events)} cues, mix RMS {20 * math.log10(np.sqrt(np.mean(mix ** 2))):.1f} dBFS")
