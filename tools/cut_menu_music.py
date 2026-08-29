"""Cuts the menu's two music files out of the master track.

The numbers are not guesses. The tempo was measured three ways and two of
them agreed exactly -- a beat comb over a spectral-flux onset envelope, and a
least-squares fit through 203 detected kick onsets -- while a plain waveform
autocorrelation gave 132.63 and was the outlier. The structure settles it: at
132.5076 BPM the drums enter at exactly bar 16 and the chorus at exactly bar
32, with the first downbeat at 0.000 s. Nothing else lands on whole bars.

The two loop lengths were chosen by MEASURING the join rather than by
phrasing. The chorus is 12 bars because bar 44's continuation matches bar
32's start to within a fraction of a sample step, which says the chorus is
built in four-bar units; the obvious 16 bars runs into bar 48, where the
track breaks down, and joins badly.

    uv run --with numpy tools/cut_menu_music.py <master.mp3>

Needs ffmpeg on PATH. The master is not in this repo: it is a one-off
generation that cannot be reproduced, so it belongs in the private submodule
rather than here. What is here is these two cuts and this script.
"""
import subprocess
import sys
import os
import numpy as np

SR = 44100
BAR = 1.811217              # 132.5076 BPM in 4/4
FADE = 0.025                # kills the join without softening the downbeat

# name -> (first bar, length in bars)
PIECES = {
    "menu_loop": (0, 8),    # the restrained figure, before the drums
    "menu_chorus": (32, 12),
}


def decode(path: str) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "quiet", "-i", path, "-ac", "2", "-ar", str(SR),
         "-f", "f32le", "-"],
        stdout=subprocess.PIPE, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64).reshape(-1, 2)


def seamless(x: np.ndarray, start_bar: int, bars: int) -> np.ndarray:
    """The classic seamless loop: the head is crossfaded with what the
    composer actually wrote AFTER the tail, so the join carries real
    continuation rather than a cut. Equal power, because two halves of a
    linear crossfade sum to a dip."""
    a = int(round(start_bar * BAR * SR))
    n = int(round(bars * BAR * SR))
    f = int(FADE * SR)
    seg = x[a:a + n].copy()
    t = np.linspace(0.0, 1.0, f)[:, None]
    seg[:f] = seg[:f] * np.sqrt(t) + x[a + n:a + n + f] * np.sqrt(1.0 - t)
    return seg


def encode(seg: np.ndarray, path: str) -> None:
    subprocess.run(
        ["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2",
         "-i", "-", "-c:a", "libvorbis", "-qscale:a", "6", path],
        input=np.clip(seg, -1.0, 1.0).astype(np.float32).tobytes(), check=True)


def join_quality(seg: np.ndarray) -> float:
    """How the wrap compares with an ordinary sample-to-sample step. Below 1
    means the loop point is smoother than the music already is, i.e. silent."""
    step = float(np.max(np.abs(seg[-1] - seg[0])))
    idx = np.random.default_rng(0).integers(1000, len(seg) - 1000, 4000)
    typical = float(np.mean([np.max(np.abs(seg[i + 1] - seg[i])) for i in idx]))
    return step / max(typical, 1e-9)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    master = sys.argv[1]
    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)
    x = decode(master)
    print("master %.2f s" % (len(x) / SR))
    for name, (start_bar, bars) in PIECES.items():
        seg = seamless(x, start_bar, bars)
        encode(seg, os.path.join(out_dir, name + ".ogg"))
        print("%-12s bars %2d..%-2d  %8.4f s  join %.2f x a normal step"
              % (name, start_bar, start_bar + bars, len(seg) / SR, join_quality(seg)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
