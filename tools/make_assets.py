#!/usr/bin/env python3
"""Generate every asset the showcase needs, from scratch, with no downloads.

Requires: ffmpeg (libvorbis, libmp3lame, libx264, aac), ImageMagick 7 (`magick`),
and the Liberation fonts (Arch: ttf-liberation).

Everything lands in app/assets/ (git-ignored; re-run any time):

  img/      hello.png  photo.jpg  checker.bmp  sprites.png  spinner.gif  texture.png
  fonts/    LiberationSans-{Regular,Bold}.ttf  LiberationMono-Regular.ttf  LICENSE
  audio/    melody.ogg (Vorbis)  melody.mp3 (ID3v2.3!)  melody.wav  melody.aif  melody.mid
  video/    clip.mp4 (H.264 baseline + AAC)  clip.vtt  clip.srt
  model/    torus.obj (v/vt/vn + triangles, what lpp's OBJ parser expects)
  sample/   bundle.zip  legacy.pbp  readme.txt
and the LiveArea art in app/sce_sys/ (8-bit indexed PNGs, as the Vita shell wants).
"""
import math
import shutil
import struct
import subprocess
import sys
import wave
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
A = APP / "assets"
FONT_DIR = Path("/usr/share/fonts/liberation")
BOLD = str(FONT_DIR / "LiberationSans-Bold.ttf")
REG = str(FONT_DIR / "LiberationSans-Regular.ttf")
TMP = ROOT / "build" / "tmp"

sys.path.insert(0, str(Path(__file__).parent))
from sfo import build_sfo  # noqa: E402


def run(*cmd: str) -> None:
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def magick(*args: str) -> None:
    run("magick", *args)


# ----------------------------------------------------------------------------- images
def images() -> None:
    d = A / "img"
    d.mkdir(parents=True, exist_ok=True)
    magick("-size", "256x96", "gradient:#ff5f6d-#5f8bff", "-font", BOLD, "-pointsize", "38",
           "-fill", "white", "-gravity", "center", "-annotate", "0", "Hello, Vita!",
           "PNG32:" + str(d / "hello.png"))
    magick("-seed", "7", "-size", "256x160", "plasma:#1d3557-#e9c46a", "-blur", "0x1",
           "-quality", "88", str(d / "photo.jpg"))
    magick("-size", "64x64", "pattern:checkerboard", "-auto-level", "+level-colors", "#2a9d8f,#e9f5f3",
           "-type", "TrueColor", "BMP3:" + str(d / "checker.bmp"))
    # 4-frame sprite sheet, 64x64 cells (drawPartialImage demo)
    frames = []
    for i, col in enumerate(["#e63946", "#f4a261", "#2a9d8f", "#457b9d"]):
        f = TMP / f"sprite{i}.png"
        r = 14 + i * 5
        magick("-size", "64x64", "xc:none", "-fill", col, "-draw", f"circle 32,32 32,{32 - r}",
               "-font", BOLD, "-pointsize", "22", "-fill", "white", "-gravity", "center",
               "-annotate", "0", str(i + 1), "PNG32:" + str(f))
        frames.append(str(f))
    magick(*frames, "+append", "PNG32:" + str(d / "sprites.png"))
    # 8-frame animated GIF (loadAnimatedImage / setImageFrame demo)
    gif_frames = []
    for i in range(8):
        f = TMP / f"spin{i}.png"
        a0 = i * 45
        magick("-size", "64x64", "xc:#101820", "-stroke", "#f9c74f", "-strokewidth", "7",
               "-fill", "none", "-draw", f"arc 10,10 54,54 {a0},{a0 + 250}", "PNG24:" + str(f))
        gif_frames.append(str(f))
    magick("-delay", "8", "-loop", "0", *gif_frames, str(d / "spinner.gif"))
    # 128x128 power-of-two texture for the 3D scene
    magick("-size", "32x32", "pattern:checkerboard", "-scale", "400%", "-auto-level",
           "+level-colors", "#ef476f,#ffd166", "-font", BOLD, "-pointsize", "28", "-fill", "#073b4c", "-gravity", "center",
           "-annotate", "0", "LPP", "PNG24:" + str(d / "texture.png"))


def livearea() -> None:
    sce = APP / "sce_sys"
    la = sce / "livearea" / "contents"
    la.mkdir(parents=True, exist_ok=True)
    magick("-size", "128x128", "radial-gradient:#5f8bff-#14213d", "-font", BOLD, "-pointsize", "40",
           "-fill", "white", "-gravity", "center", "-annotate", "+0-14", "lpp", "-pointsize", "18",
           "-fill", "#f9c74f", "-annotate", "+0+26", "showcase", "PNG8:" + str(sce / "icon0.png"))
    magick("-size", "840x500", "gradient:#14213d-#5f8bff", "-font", BOLD, "-pointsize", "64",
           "-fill", "white", "-gravity", "center", "-annotate", "+0-30", "Hello, Vita!",
           "-font", REG, "-pointsize", "26", "-fill", "#f9c74f", "-annotate", "+0+40",
           "Lua Player Plus Vita - every API, one app", "PNG8:" + str(la / "bg.png"))
    magick("-size", "280x158", "gradient:#ff5f6d-#5f8bff", "-font", BOLD, "-pointsize", "34",
           "-fill", "white", "-gravity", "center", "-annotate", "0", "START", "PNG8:" + str(la / "startup.png"))
    (la / "template.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<livearea style="a1" format-ver="01.00" content-rev="1">\n'
        "  <livearea-background>\n    <image>bg.png</image>\n  </livearea-background>\n"
        "  <gate>\n    <startup-image>startup.png</startup-image>\n  </gate>\n"
        "</livearea>\n"
    )


# ----------------------------------------------------------------------------- fonts
def fonts() -> None:
    d = A / "fonts"
    d.mkdir(parents=True, exist_ok=True)
    for name in ["LiberationSans-Regular.ttf", "LiberationSans-Bold.ttf", "LiberationMono-Regular.ttf"]:
        shutil.copy(FONT_DIR / name, d / name)
    lic = Path("/usr/share/licenses/ttf-liberation/LICENSE")
    if lic.exists():
        shutil.copy(lic, d / "LICENSE")


# ----------------------------------------------------------------------------- audio
MELODY = [  # (midi note, beats) - a little chiptune loop, 120 bpm
    (72, 1), (76, 1), (79, 1), (84, 1), (83, 1), (79, 1), (76, 2),
    (74, 1), (77, 1), (81, 1), (86, 1), (84, 1), (81, 1), (77, 2),
]
BASS = [48, 48, 55, 55, 50, 50, 57, 57]
BPM = 120


def synth_wav(path: Path, rate: int = 44100) -> None:
    beat = 60 / BPM
    total_beats = sum(b for _, b in MELODY)
    n = int(total_beats * beat * rate)
    lead = [0.0] * n
    pos = 0
    for note, beats in MELODY:
        f = 440 * 2 ** ((note - 69) / 12)
        length = int(beats * beat * rate)
        for i in range(length):
            if pos + i >= n:
                break
            env = min(1.0, i / 200) * max(0.0, 1 - i / length) ** 0.6
            phase = (f * i / rate) % 1
            lead[pos + i] = (0.22 if phase < 0.5 else -0.22) * env  # square lead
        pos += length
    bass = [0.0] * n
    blen = n // len(BASS)
    for k, note in enumerate(BASS):
        f = 440 * 2 ** ((note - 69) / 12)
        for i in range(blen):
            phase = (f * i / rate) % 1
            tri = 4 * abs(phase - 0.5) - 1
            bass[k * blen + i] = 0.25 * tri * max(0.0, 1 - i / blen) ** 0.3
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        for i in range(n):
            l_ = max(-1.0, min(1.0, lead[i] * 0.9 + bass[i] * 0.6))
            r_ = max(-1.0, min(1.0, lead[i] * 0.6 + bass[i] * 0.9))
            frames += struct.pack("<hh", int(l_ * 32000), int(r_ * 32000))
        w.writeframes(bytes(frames))


def write_midi(path: Path) -> None:
    def vlq(v: int) -> bytes:
        out = [v & 0x7F]
        v >>= 7
        while v:
            out.insert(0, (v & 0x7F) | 0x80)
            v >>= 7
        return bytes(out)

    tpq = 96
    ev = bytearray()
    ev += b"\x00\xff\x51\x03" + (500000).to_bytes(3, "big")  # 120 bpm
    ev += b"\x00\xc0\x50"  # program: square lead
    for _ in range(2):
        for note, beats in MELODY:
            ev += vlq(0) + bytes([0x90, note, 100])
            ev += vlq(beats * tpq) + bytes([0x80, note, 0])
    ev += b"\x00\xff\x2f\x00"
    path.write_bytes(b"MThd" + struct.pack(">IHHH", 6, 0, 1, tpq) + b"MTrk" + struct.pack(">I", len(ev)) + ev)


def audio() -> None:
    d = A / "audio"
    d.mkdir(parents=True, exist_ok=True)
    raw = TMP / "melody_raw.wav"
    synth_wav(raw)
    meta = ["-metadata", "title=Hello Vita Theme", "-metadata", "artist=lpp-showcase"]
    ff = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw)]
    run(*ff, "-ar", "48000", "-c:a", "libvorbis", "-q:a", "4", *meta, str(d / "melody.ogg"))
    # lpp-vita only accepts MP3s that start with an ID3v2.3 tag ("ID3\x03")
    run(*ff, "-ar", "48000", "-c:a", "libmp3lame", "-b:a", "128k", "-id3v2_version", "3", *meta, str(d / "melody.mp3"))
    run(*ff, "-ar", "44100", "-c:a", "pcm_s16le", *meta, str(d / "melody.wav"))
    run(*ff, "-ar", "44100", "-c:a", "pcm_s16be", str(d / "melody.aif"))
    write_midi(d / "melody.mid")


# ----------------------------------------------------------------------------- video
def video() -> None:
    d = A / "video"
    d.mkdir(parents=True, exist_ok=True)
    loop = TMP / "melody_raw.wav"
    run("ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "testsrc2=size=480x272:rate=30:duration=14",
        "-stream_loop", "-1", "-i", str(loop),
        "-vf", f"drawtext=fontfile={BOLD}:text='lpp-vita Video module':x=12:y=12:fontsize=20:"
               "fontcolor=white:box=1:boxcolor=black@0.5",
        "-c:v", "libx264", "-profile:v", "baseline", "-level", "3.0", "-pix_fmt", "yuv420p",
        "-b:v", "700k", "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "96k",
        "-shortest", "-movflags", "+faststart", str(d / "clip.mp4"))
    cues = [(i * 2, i * 2 + 2, f"Subtitle cue #{i + 1} - {['hello', 'hola', 'konnichiwa', 'ciao', 'salut', 'hallo', 'ola'][i]}")
            for i in range(7)]

    def ts(s: int, sep: str) -> str:
        return f"00:00:{s:02d}{sep}000"

    (d / "clip.vtt").write_text("WEBVTT\n\n" + "\n".join(
        f"{ts(a, '.')} --> {ts(b, '.')}\n{t}\n" for a, b, t in cues))
    (d / "clip.srt").write_text("\n".join(
        f"{i + 1}\n{ts(a, ',')} --> {ts(b, ',')}\n{t}\n" for i, (a, b, t) in enumerate(cues)))


# ----------------------------------------------------------------------------- model
def torus_obj(path: Path, R: float = 1.0, r: float = 0.42, seg: int = 24, side: int = 12) -> None:
    """Triangulated torus with UVs + normals, in the strict layout lpp's parser needs:
    all `v` lines, then all `vt`, then all `vn`, then `f a/b/c` triangles, no comments."""
    vs, vts, vns, fs = [], [], [], []
    for i in range(seg + 1):
        u = i / seg * 2 * math.pi
        for j in range(side + 1):
            v = j / side * 2 * math.pi
            cx, cz = math.cos(u), math.sin(u)
            nx, ny, nz = math.cos(v) * cx, math.sin(v), math.cos(v) * cz
            vs.append(((R + r * math.cos(v)) * cx, r * math.sin(v), (R + r * math.cos(v)) * cz))
            vts.append((i / seg * 4 % 1.0 if i != seg else 1.0, j / side))
            vns.append((nx, ny, nz))
    w = side + 1
    for i in range(seg):
        for j in range(side):
            a, b, c, d = i * w + j + 1, (i + 1) * w + j + 1, (i + 1) * w + j + 2, i * w + j + 2
            fs.append((a, b, c))
            fs.append((a, c, d))
    lines = [f"v {x:.5f} {y:.5f} {z:.5f}" for x, y, z in vs]
    lines += [f"vt {u:.5f} {v:.5f}" for u, v in vts]
    lines += [f"vn {x:.5f} {y:.5f} {z:.5f}" for x, y, z in vns]
    lines += [f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}" for a, b, c in fs]
    path.write_text("\n".join(lines) + "\n")


def model() -> None:
    d = A / "model"
    d.mkdir(parents=True, exist_ok=True)
    torus_obj(d / "torus.obj")


# ----------------------------------------------------------------------------- sample data
def sample() -> None:
    d = A / "sample"
    d.mkdir(parents=True, exist_ok=True)
    readme = "Hello from inside a ZIP!\nThis file was packed on the PC and unpacked on the Vita.\n"
    (d / "readme.txt").write_text(readme)
    with zipfile.ZipFile(d / "bundle.zip", "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("readme.txt", readme)
        z.write(A / "img" / "hello.png", "images/hello.png")
        z.writestr("data/numbers.csv", "n,square\n" + "".join(f"{i},{i * i}\n" for i in range(1, 11)))
    # A minimal PSP-style EBOOT.PBP: PARAM.SFO + ICON0.PNG, the other 6 sections empty
    sfo = build_sfo({"TITLE": ("str", "Legacy PBP sample"), "DISC_ID": ("str", "LPPX00001"),
                     "CATEGORY": ("str", "MG"), "DISC_VERSION": ("str", "1.00"),
                     "PSP_SYSTEM_VER": ("str", "6.60"), "PARENTAL_LEVEL": ("int", 1),
                     "BOOTABLE": ("int", 1), "REGION": ("int", 0x8000)}, defaults=False)
    icon = TMP / "pbp_icon.png"
    magick("-size", "144x80", "gradient:#2a9d8f-#264653", "-font", BOLD, "-pointsize", "22",
           "-fill", "white", "-gravity", "center", "-annotate", "0", "PBP", "PNG24:" + str(icon))
    sections = [sfo, icon.read_bytes(), b"", b"", b"", b"", b"", b""]
    offs, cur = [], 0x28
    for s in sections:
        offs.append(cur)
        cur += len(s)
    hdr = b"\x00PBP" + struct.pack("<I", 0x00010000) + struct.pack("<8I", *offs)
    (d / "legacy.pbp").write_bytes(hdr + b"".join(sections))


def main() -> None:
    TMP.mkdir(parents=True, exist_ok=True)
    steps = [("images", images), ("livearea", livearea), ("fonts", fonts), ("audio", audio),
             ("video", video), ("model", model), ("sample", sample)]
    for name, fn in steps:
        print(f"  assets: {name}")
        try:
            fn()
        except subprocess.CalledProcessError as e:
            sys.exit(f"{name} failed: {' '.join(e.cmd)}\n{e.stderr.decode(errors='ignore')}")
    total = sum(f.stat().st_size for f in A.rglob("*") if f.is_file())
    print(f"  assets: done, {total / 1024:.0f} KiB in {A.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
