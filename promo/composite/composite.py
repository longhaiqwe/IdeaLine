"""Composite rendered frames with caption layers and audio into the final MP4.

    python3 promo/composite/composite.py [--frames DIR] [--out FILE] [--scale 0.5]

Reads promo/render/frame_####.png, promo/build/textures/captions/*.png,
promo/build/audio/mix.wav and the cover from make_cover.py. Writes promo/out/灵感晾台-介绍.mp4.
The cover opens the video (held, then dissolved into the first shot, so platforms that use the
first frame as the thumbnail show it) and is also embedded as the file's cover art.
"""
import argparse
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROMO = os.path.dirname(HERE)
sys.path.insert(0, PROMO)
import timeline as T  # noqa: E402

CAPTIONS = os.path.join(PROMO, "build", "textures", "captions")
CREAM = np.array([0.968, 0.958, 0.925], dtype=np.float32)

S = T.SHOTS
EDGE_SWITCH = [S["edges"][0] + 27, S["edges"][0] + 63, S["edges"][0] + 99]  # matches build_scene.py


def ease_out(t):
    t = min(1.0, max(0.0, t))
    return 1 - (1 - t) ** 3


# (layer, frame in, frame out or None, style)
CUES = [
    ("macro", S["macro"][0] + 26, S["macro"][1] - 6, "hero"),
    ("hotkey", S["hotkey"][0] + 14, S["hotkey"][1] - 3, "line"),
    ("submit", S["submit"][0] + 2, S["hang"][0] + 44, "line"),
    ("reveal", S["reveal"][0] + 22, S["reveal"][1] - 3, "line"),
    ("edges", S["edges"][0] + 6, S["edges"][1] - 3, "line"),
    ("edges_pill_0", S["edges"][0] + 10, EDGE_SWITCH[0] + 4, "pill"),
    ("edges_pill_1", EDGE_SWITCH[0] + 4, EDGE_SWITCH[1] + 4, "pill"),
    ("edges_pill_2", EDGE_SWITCH[1] + 4, EDGE_SWITCH[2] + 4, "pill"),
    ("edges_pill_3", EDGE_SWITCH[2] + 4, S["edges"][1] - 3, "pill"),
    ("drag", S["drag"][0] + 10, S["drag"][1] - 3, "line"),
    ("library", S["library"][0] + 10, S["library"][1] - 3, "line"),
    ("end_eyebrow", S["end"][0] + 30, None, "end"),
    ("end_title", S["end"][0] + 36, None, "end"),
    ("end_tagline", S["end"][0] + 48, None, "end"),
    ("end_meta", S["end"][0] + 62, None, "end"),
    ("end_url", S["end"][0] + 68, None, "end"),
]


class Layer:
    def __init__(self, name, scale):
        im = Image.open(os.path.join(CAPTIONS, f"{name}.png")).convert("RGBA")
        if scale != 1:
            im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        pad = round(16 * scale)
        x0, y0, x1, y1 = im.getbbox()
        x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
        x1, y1 = min(im.width, x1 + pad), min(im.height, y1 + pad)
        self.box = (x0, y0)
        self.im = im.crop((x0, y0, x1, y1))
        self.scale = scale


def cue_state(f, f_in, f_out, style):
    """Returns (opacity, dy pixels at 1080p, blur px) or None when hidden."""
    if f < f_in:
        return None
    rise = {"hero": 22, "line": 16, "pill": 8, "end": 18}[style]
    dur = {"hero": 22, "line": 14, "pill": 6, "end": 20}[style]
    t = ease_out((f - f_in) / dur)
    opacity, dy, blur = t, rise * (1 - t), 7 * (1 - t) if style != "pill" else 0
    if f_out is not None:
        out_len = 4 if style == "pill" else 8
        if f >= f_out:
            return None
        if f > f_out - out_len:
            u = (f - (f_out - out_len)) / out_len
            opacity *= 1 - u
            dy -= 6 * u if style != "pill" else 0
    if opacity <= 0.002:
        return None
    return opacity, dy, blur


def scrim(w, h):
    """Cream gradient behind the opening headline (bottom-left)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    up = np.clip((yy / h - 0.38) / 0.40, 0, 1) ** 1.1
    side = np.clip(1 - (xx / (w * 0.95)) ** 2.2, 0, 1)
    a = (0.90 * up * side * 255).astype(np.uint8)
    rgb = np.empty((h, w, 4), np.uint8)
    rgb[..., :3] = (CREAM * 255).astype(np.uint8)
    rgb[..., 3] = a
    return Image.fromarray(rgb, "RGBA")


def lower_scrim(w, h):
    """Cream gradient along the bottom edge behind line captions."""
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32)
    a = (0.62 * np.clip((yy / h - 0.70) / 0.30, 0, 1) ** 1.4 * 255).astype(np.uint8)
    rgba = np.empty((h, w, 4), np.uint8)
    rgba[..., :3] = (CREAM * 255).astype(np.uint8)
    rgba[..., 3] = a
    return Image.fromarray(rgba, "RGBA")


def faded(img, opacity):
    out = img.copy()
    out.putalpha(img.getchannel("A").point(lambda v, o=opacity: round(v * o)))
    return out


def grade(rgb, f, rng, w, h, vignette, fade_in=True):
    x = rgb.astype(np.float32) / 255.0
    x *= vignette[..., None]
    grain = rng.standard_normal((h // 2, w // 2)).astype(np.float32)
    grain = np.repeat(np.repeat(grain, 2, axis=0), 2, axis=1)[:h, :w]
    x += grain[..., None] * 0.006
    # fade in from cream when there is no cover; the end card holds to the last frame
    k = min(1.0, (f - T.FRAME_START) / 14) if fade_in else 1.0
    if k < 1:
        e = ease_out(k)
        x = x * e + CREAM * (1 - e)
    return np.clip(x * 255 + 0.5, 0, 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", default=os.path.join(PROMO, "render"))
    ap.add_argument("--pattern", default="frame_{:04d}.png")
    ap.add_argument("--out", default=os.path.join(PROMO, "out", "灵感晾台-介绍.mp4"))
    ap.add_argument("--audio", default=os.path.join(PROMO, "build", "audio", "mix.wav"))
    ap.add_argument("--scale", type=float, default=1.0, help="output scale relative to 1920x1080")
    ap.add_argument("--crf", type=int, default=16)
    ap.add_argument("--cover", default=os.path.join(PROMO, "build", "cover", "cover.jpg"))
    ap.add_argument("--cover-hold", type=int, default=15, help="frames the cover is held before the film")
    ap.add_argument("--cover-fade", type=int, default=12, help="frames of cover-to-film dissolve")
    args = ap.parse_args()

    w, h = round(T.WIDTH * args.scale), round(T.HEIGHT * args.scale)
    layers = {name: Layer(name, args.scale) for name, *_ in CUES}
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 * 0.8 + ((yy - h / 2) / (h / 2)) ** 2 * 1.0)
    vignette = 1 - 0.10 * np.clip(r - 0.35, 0, None) ** 1.6
    rng = np.random.default_rng(1)
    hero_scrim = scrim(w, h)
    bottom_scrim = lower_scrim(w, h)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    use_cover = bool(args.cover) and os.path.exists(args.cover)
    cover = Image.open(args.cover).convert("RGB").resize((w, h), Image.LANCZOS) if use_cover else None
    hold = args.cover_hold if use_cover else 0
    delay_ms = round(hold / T.FPS * 1000)
    tmp = os.path.splitext(args.out)[0] + ".tmp.mp4"

    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(T.FPS), "-i", "-",
        "-i", args.audio,
        "-af", f"adelay={delay_ms}|{delay_ms}",
        "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv",
        "-c:v", "libx264", "-preset", "slow", "-crf", str(args.crf), "-profile:v", "high",
        "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
        "-c:a", "aac", "-b:a", "256k", "-ar", "48000",
        "-movflags", "+faststart", "-shortest", tmp,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for _ in range(hold):
        proc.stdin.write(cover.tobytes())
    for f in range(T.FRAME_START, T.FRAME_END + 1):
        src = os.path.join(args.frames, args.pattern.format(f))
        im = Image.open(src).convert("RGB")
        if im.size != (w, h):
            im = im.resize((w, h), Image.LANCZOS)
        base = Image.fromarray(grade(np.asarray(im), f, rng, w, h, vignette, fade_in=not use_cover)).convert("RGBA")
        line_opacity = max([st[0] for name, f_in, f_out, style in CUES if style in ("line", "pill")
                            for st in [cue_state(f, f_in, f_out, style)] if st] or [0])
        if line_opacity > 0:
            base.alpha_composite(faded(bottom_scrim, line_opacity))
        for name, f_in, f_out, style in CUES:
            st = cue_state(f, f_in, f_out, style)
            if st is None:
                continue
            opacity, dy, blur = st
            if style == "hero":
                base.alpha_composite(faded(hero_scrim, opacity))
            layer = layers[name]
            img = layer.im
            if blur > 0.3:
                img = img.filter(ImageFilter.GaussianBlur(blur * args.scale))
            if opacity < 1:
                img = faded(img, opacity)
            x0, y0 = layer.box
            base.alpha_composite(img, (x0, int(round(y0 + dy * args.scale))))
        frame = base.convert("RGB")
        k = f - T.FRAME_START
        if use_cover and k < args.cover_fade:
            frame = Image.blend(cover, frame, ease_out((k + 1) / (args.cover_fade + 1)))
        proc.stdin.write(frame.tobytes())
        if f % 100 == 0:
            print(f"frame {f}/{T.FRAME_END}", flush=True)
    proc.stdin.close()
    proc.wait()
    if proc.returncode:
        raise SystemExit(f"ffmpeg failed ({proc.returncode})")
    if use_cover:
        # embed the cover image as cover art (attached picture)
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-i", args.cover,
            "-map", "0", "-map", "1", "-c", "copy", "-disposition:v:1", "attached_pic",
            "-bsf:v:0", "h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1",
            "-movflags", "+faststart", args.out,
        ], check=True)
        os.remove(tmp)
    else:
        os.replace(tmp, args.out)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
