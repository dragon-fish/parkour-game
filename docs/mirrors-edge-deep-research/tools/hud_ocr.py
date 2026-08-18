"""Read Mirror's Edge Tweaks' debug HUD out of a video, frame by frame, into CSV.

The HUD is a fixed-position, fixed-font overlay, so this does template matching
against a glyph library rather than general OCR: OCR has to cope with arbitrary
fonts and gets confused by the game rendering behind the text, while template
matching only has to tell ~70 known bitmaps apart and is effectively exact.

The glyph library is not shipped -- it is built once, from a single frame whose
contents you type out by hand ("calib"), and reused for every video after that.

Three subcommands, meant to be run in this order:

  probe <image>              diagnostic: draw the detected line and glyph boxes
                             onto a copy of the image so you can see whether the
                             segmentation is right BEFORE trusting any numbers.
  calib <image> <truth.txt>  build glyphs.npz from one frame plus its true text.
  run <video>                emit CSV, one row per frame.

Why the HUD's own T (IGT) matters: it makes the recording frame rate irrelevant
as a time base. We do not have to lock 62 FPS and count frames -- every row
carries the game's own clock, so dropped frames show up as a gap in IGT instead
of silently shifting every later sample.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

# ---------------------------------------------------------------------------
# Segmentation
# ---------------------------------------------------------------------------

# The HUD sits in the right-hand margin. Everything left of this fraction of the
# frame width is scene, never text, so cropping first removes most false hits.
HUD_X_FRAC = 0.70

# The glyphs are white with a dark outline. A top-hat keeps small bright
# structures and flattens large bright regions, so white text survives even in
# front of a sunlit white building -- which a plain brightness threshold does
# not. The kernel must be comfortably wider than a glyph stroke but narrower
# than the smallest background feature we want gone.
TOPHAT_KERNEL = (15, 15)
# A top-hat measures how much brighter a pixel is THAN ITS SURROUNDINGS, not how
# bright it is, so a threshold set by absolute brightness is meaningless here.
# Measured on a real capture, glyph pixels score 127-221 even where the HUD sits
# on a sunlit white facade, so 80 keeps a wide margin while still cutting the
# soft gradients of the scene.
BINARY_THRESHOLD = 80

# This is the single most important threshold in the file. The HUD is drawn in
# PURE white (255); the brightest thing the renderer puts behind it -- a sunlit
# white building -- tops out near 250. Demanding 245 exploits that 5-level gap
# and is what makes the whole approach work: measured on a worst-case frame
# (HUD over a white facade and steel railings), moving 185 -> 245 dropped the
# non-HUD component count from 716 to 15, a 98% cut, while the glyph count went
# UP (81 -> 173) because bright background had been bridging glyphs together.
#
# Raise-with-care: video encoding, unlike a PNG screenshot, can pull 255 down a
# few levels (YUV 4:2:0 chroma subsampling, low bitrate). If a video yields far
# fewer lines than a screenshot of the same HUD, lower this before touching
# anything else -- see --white-min.
WHITE_MIN = 245
WHITE_CHROMA = 50

# A text line is a run of rows with ink in it. These bounds throw away specular
# highlights on windows (too short) and lens flare (too tall).
MIN_LINE_HEIGHT = 8
MAX_LINE_HEIGHT = 40
# Rows with fewer lit pixels than this are treated as blank, which stops a
# stray highlight from welding two lines together. Every real HUD line is at
# least a label, an '=' and a value, so its widest rows carry far more ink.
LINE_INK_MIN = 6
# A single rendered line is ~14px tall here; anything appreciably taller is two
# lines bridged by background ink, and gets split by _unbridge().
MAX_SINGLE_LINE_H = 25

# Columns inside a line. Measured on a real capture, adjacent glyphs are
# separated by exactly ONE blank column, so any stitching at all merges them --
# "100%" collapses into two blobs. 1 disables stitching entirely, which is
# correct here: the multi-part glyphs that stitching would exist to repair ('=',
# '%', the dot of an 'i') all have their pieces stacked vertically, and a
# vertical projection already merges those by column overlap.
GLYPH_GAP_MIN = 1
MIN_GLYPH_WIDTH = 1

# Every glyph is scaled into this box before matching, so the library does not
# depend on the resolution the calibration frame happened to be captured at.
GLYPH_H = 24
GLYPH_W = 20

# The baseline-anchored cut window (see segment()). CAP_HEIGHT covers the tall
# glyphs above the baseline, DESCENDER the tails below it. Their sum must stay
# under the line PITCH (~22px here) or a window would reach into its neighbour.
CAP_HEIGHT = 13
DESCENDER = 4


def hud_mask(image: np.ndarray, x_frac: float = HUD_X_FRAC) -> tuple[np.ndarray, int]:
    """Return (binary mask of HUD text, x offset of the mask within the frame).

    x_frac=0 means the caller already cropped to the HUD column (see cmd_run,
    which makes ffmpeg do the crop so it never has to decode the other 70% of
    each frame).
    """
    height, width = image.shape[:2]
    x0 = int(width * x_frac)
    roi = image[:, x0:]
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, TOPHAT_KERNEL)
    tophat = cv2.morphologyEx(gray, cv2.MORPH_TOPHAT, kernel)
    _, bright = cv2.threshold(tophat, BINARY_THRESHOLD, 255, cv2.THRESH_BINARY)
    hi = roi.max(axis=2).astype(np.int16)
    lo = roi.min(axis=2).astype(np.int16)
    white = ((hi >= WHITE_MIN) & (hi - lo <= WHITE_CHROMA)).astype(np.uint8) * 255
    return cv2.bitwise_and(bright, white), x0


def _runs(counts: np.ndarray, floor: int) -> list[tuple[int, int]]:
    """Index ranges [start, end) where counts stays above floor."""
    lit = counts > floor
    spans: list[tuple[int, int]] = []
    start: int | None = None
    for i, on in enumerate(lit):
        if on and start is None:
            start = i
        elif not on and start is not None:
            spans.append((start, i))
            start = None
    if start is not None:
        spans.append((start, len(lit)))
    return spans


def find_lines(mask: np.ndarray) -> list[tuple[int, int]]:
    """Vertical extents of each text line, by horizontal projection."""
    ink_per_row = (mask > 0).sum(axis=1)
    out: list[tuple[int, int]] = []
    for top, bottom in _runs(ink_per_row, LINE_INK_MIN - 1):
        if not MIN_LINE_HEIGHT <= bottom - top <= MAX_LINE_HEIGHT:
            continue
        if bottom - top <= MAX_SINGLE_LINE_H:
            out.append((top, bottom))
        else:
            out.extend(_unbridge(ink_per_row, top, bottom))
    return out


def _unbridge(ink: np.ndarray, top: int, bottom: int) -> list[tuple[int, int]]:
    """Split one over-tall block back into the text lines it really contains.

    Background ink sometimes bridges the gap between two HUD lines, yielding a
    single ~35px "line" where two ~14px ones belong -- and a merged block reads
    as garbage AND shifts every later line's index. The bridge is always
    thinner than the text rows it joins, so raising the ink floor inside just
    this block breaks it without disturbing lines that segmented correctly.
    """
    for floor in range(LINE_INK_MIN, LINE_INK_MIN + 40):
        parts = [(top + a, top + b) for a, b in _runs(ink[top:bottom], floor)
                 if MIN_LINE_HEIGHT <= b - a <= MAX_SINGLE_LINE_H]
        if len(parts) >= 2:
            return parts
    return [(top, bottom)]


def find_glyphs(line: np.ndarray) -> list[tuple[int, int]]:
    """Horizontal extents of each glyph in one line, by vertical projection.

    Projection rather than connected components on purpose: it merges the parts
    of a multi-blob glyph automatically, because the dot of an 'i' shares its
    column range with the stem. Connected components would split them.
    """
    ink_per_col = (line > 0).sum(axis=0)
    spans = _runs(ink_per_col, 0)
    if not spans:
        return []
    # Stitch together spans separated by less than a real inter-glyph gap.
    merged = [list(spans[0])]
    for left, right in spans[1:]:
        if left - merged[-1][1] < GLYPH_GAP_MIN:
            merged[-1][1] = right
        else:
            merged.append([left, right])
    return [(l, r) for l, r in merged if r - l >= MIN_GLYPH_WIDTH]


def normalize(patch: np.ndarray) -> np.ndarray:
    """Scale a glyph bitmap into the fixed matching box, keeping aspect ratio.

    Aspect ratio has to be preserved or '1', '.', and '0' all stretch into the
    same box and stop being distinguishable -- the width is most of what tells
    them apart.
    """
    height, width = patch.shape
    scale = GLYPH_H / max(height, 1)
    new_w = max(1, min(GLYPH_W, int(round(width * scale))))
    resized = cv2.resize(patch, (new_w, GLYPH_H), interpolation=cv2.INTER_AREA)
    canvas = np.zeros((GLYPH_H, GLYPH_W), np.uint8)
    canvas[:, :new_w] = resized
    return canvas


def segment(image: np.ndarray, x_frac: float = HUD_X_FRAC
            ) -> list[list[tuple[np.ndarray, tuple[int, int, int, int]]]]:
    """Full segmentation: per line, a list of (normalized glyph, bbox in frame).

    Glyphs are cut from a window anchored to the line's BASELINE, not from the
    line's own ink bounds. This matters more than it looks: a line's ink height
    depends on whether it happens to contain a descender ('g' in 'deg') or only
    caps and digits, so it varies 13-17px across the same HUD. Scaling each line
    to a fixed box by its own height therefore renders the SAME character at
    different sizes depending on its neighbours, which was collapsing match
    confidence (median 0.125) and losing whole lines. A baseline-anchored window
    is the same size everywhere, so a '9' looks like a '9' on every line.
    """
    mask, x0 = hud_mask(image, x_frac)
    height = mask.shape[0]
    out = []
    for top, bottom in find_lines(mask):
        spans = find_glyphs(mask[top:bottom])
        if not spans:
            continue
        bottoms = []
        for left, right in spans:
            rows = np.nonzero(mask[top:bottom, left:right].any(axis=1))[0]
            if len(rows):
                bottoms.append(int(rows[-1]))
        if not bottoms:
            continue
        # Most glyphs sit ON the baseline, so the median bottom IS the baseline
        # -- descenders are always the minority on a line.
        base = top + int(np.median(bottoms))
        y1 = max(0, base - CAP_HEIGHT + 1)
        y2 = min(height, base + DESCENDER + 1)
        strip = mask[y1:y2]
        out.append([(normalize(strip[:, left:right]), (x0 + left, y1, x0 + right, y2))
                    for left, right in spans])
    return out


# ---------------------------------------------------------------------------
# probe
# ---------------------------------------------------------------------------


def cmd_probe(args: argparse.Namespace) -> int:
    image = cv2.imread(str(args.image), cv2.IMREAD_COLOR)
    if image is None:
        print(f"cannot read {args.image}", file=sys.stderr)
        return 1
    lines = segment(image)
    overlay = image.copy()
    for row, glyphs in enumerate(lines):
        xs = [b[0] for _, b in glyphs] + [b[2] for _, b in glyphs]
        ys = [b[1] for _, b in glyphs] + [b[3] for _, b in glyphs]
        cv2.rectangle(overlay, (min(xs) - 2, min(ys) - 2), (max(xs) + 2, max(ys) + 2),
                      (0, 200, 255), 1)
        for _, (x1, y1, x2, y2) in glyphs:
            cv2.rectangle(overlay, (x1, y1), (x2, y2), (0, 255, 0), 1)
        cv2.putText(overlay, f"L{row}:{len(glyphs)}", (min(xs) - 90, max(ys)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 200, 255), 1)
        print(f"line {row:2d}  y={min(ys):4d}-{max(ys):4d}  glyphs={len(glyphs)}")
    out = args.out or args.image.with_name(args.image.stem + "_probe.png")
    cv2.imwrite(str(out), overlay)
    print(f"\n{len(lines)} lines -> {out}")
    return 0


# ---------------------------------------------------------------------------
# calib
# ---------------------------------------------------------------------------


def cmd_calib(args: argparse.Namespace) -> int:
    image = cv2.imread(str(args.image), cv2.IMREAD_COLOR)
    if image is None:
        print(f"cannot read {args.image}", file=sys.stderr)
        return 1
    truth = [l.strip() for l in args.truth.read_text(encoding="utf-8").splitlines()]
    truth = [l for l in truth if l]
    lines = segment(image)

    if len(lines) != len(truth):
        print(f"segmented {len(lines)} lines but truth has {len(truth)}; "
              f"run 'probe' and fix the segmentation before calibrating",
              file=sys.stderr)
        for i, glyphs in enumerate(lines):
            got = truth[i] if i < len(truth) else "<none>"
            print(f"  line {i:2d}: {len(glyphs):2d} glyphs   truth: {got!r}")
        return 1

    # Spaces leave no ink, so the glyph count must equal the space-free length.
    # A line that does not match is SKIPPED rather than fatal: one bad line
    # (a lowercase glyph that splits, an annotation drawn over the HUD) should
    # not throw away the dozen good lines in the same frame. What matters is
    # only that the charset ends up complete, which is checked at the end.
    bank: dict[str, list[np.ndarray]] = {}
    if args.append and args.out.exists():
        prior = np.load(args.out, allow_pickle=False)
        for ch, tpl, wid in zip(prior["chars"], prior["templates"], prior["widths"]):
            bank.setdefault(str(ch), []).append((tpl.astype(np.float32), float(wid)))
        print(f"appending to {len(bank)} glyphs already in {args.out}")

    skipped = []
    for i, (glyphs, text) in enumerate(zip(lines, truth)):
        # A truth line of "-" means "I did not transcribe this one". Useful for
        # topping up the library from a frame where only one line matters --
        # typically a move state the glyph set has never seen.
        if text.strip() == "-":
            continue
        chars = text.replace(" ", "")
        if len(chars) != len(glyphs):
            skipped.append(f"  line {i:2d}: {len(glyphs):2d} glyphs vs "
                           f"{len(chars):2d} chars in {text!r}")
            continue
        for (patch, (x1, y1, x2, y2)), ch in zip(glyphs, chars):
            bank.setdefault(ch, []).append((patch.astype(np.float32), x2 - x1))

    if skipped:
        print(f"skipped {len(skipped)}/{len(lines)} lines whose glyph count "
              f"disagreed with the truth text:")
        print("\n".join(skipped))
    if not bank:
        print("no usable line at all -- nothing to calibrate", file=sys.stderr)
        return 1

    # Average the samples of each character: identical glyphs rendered at the
    # same size differ only by antialiasing, so the mean is a cleaner template
    # than any single instance.
    names = sorted(bank)
    stack = np.stack([np.mean([p for p, _ in bank[c]], axis=0)
                      for c in names]).astype(np.float32)
    widths = np.array([float(np.mean([w for _, w in bank[c]])) for c in names],
                      dtype=np.float32)
    np.savez(args.out, chars=np.array(names), templates=stack, widths=widths)
    print(f"\n{len(names)} glyphs from {sum(len(v) for v in bank.values())} samples "
          f"-> {args.out}")
    print("charset: " + "".join(names))

    # Digits are the whole point of this tool; a missing one silently corrupts
    # any value containing it, so say so loudly rather than let 'run' guess.
    missing = [d for d in "0123456789.-" if d not in bank]
    if missing:
        print(f"\nINCOMPLETE: missing {''.join(missing)} -- calibrate again with "
              f"--append on a frame whose HUD contains them", file=sys.stderr)
        return 1
    return 0


# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------

# Rows whose best match scores below this are emitted as '?', so a bad frame
# shows up in the CSV instead of quietly turning into a plausible wrong number.
MATCH_MIN = 0.55


# How hard a mismatched width counts against an otherwise good shape match.
# normalize() preserves aspect ratio but left-aligns into a fixed box, which
# leaves a narrow glyph as a thin stripe in a mostly-empty canvas -- so '1'
# carries almost no shape information and correlates happily with anything.
# Measured: '1' was being read as 'G'. Scoring width alongside shape fixes it,
# since those two differ by 3x in pixel width.
#
# Width is compared in ABSOLUTE PIXELS, not as an aspect ratio against the
# glyph box: the box takes its height from the whole text line, and line height
# varies (10-17 px here) with whether that line happens to contain a descender.
# A ratio therefore changes per line for the SAME character, which made the
# penalty fire on correct matches. Pixel width is stable as long as the capture
# resolution matches the calibration frame, which it must anyway for the
# templates to apply at all.
WIDTH_PENALTY = 0.5


class Matcher:
    def __init__(self, path: Path):
        data = np.load(path, allow_pickle=False)
        self.chars = [str(c) for c in data["chars"]]
        templates = data["templates"].astype(np.float32)
        self.widths = data["widths"].astype(np.float32)
        self.flat = templates.reshape(len(self.chars), -1)
        # Pre-centre and pre-scale for correlation, so matching is one dot product.
        self.flat = self.flat - self.flat.mean(axis=1, keepdims=True)
        norms = np.linalg.norm(self.flat, axis=1, keepdims=True)
        self.flat /= np.maximum(norms, 1e-6)

    def read(self, patch: np.ndarray, width: float) -> tuple[str, float]:
        vec = patch.astype(np.float32).reshape(-1)
        vec -= vec.mean()
        norm = np.linalg.norm(vec)
        if norm < 1e-6:
            return "?", 0.0
        scores = self.flat @ (vec / norm)
        rel = np.abs(self.widths - width) / np.maximum(
            np.maximum(self.widths, width), 1e-6)
        scores = scores * (1.0 - WIDTH_PENALTY * np.minimum(rel, 1.0))
        best = int(np.argmax(scores))
        return self.chars[best], float(scores[best])

    def read_line(self, glyphs) -> tuple[str, float]:
        chars, worst = [], 1.0
        for patch, (x1, y1, x2, y2) in glyphs:
            ch, score = self.read(patch, x2 - x1)
            chars.append(ch if score >= MATCH_MIN else "?")
            worst = min(worst, score)
        return "".join(chars), worst


# The HUD always renders these fifteen lines, in this order.
LINE_ORDER = ["t_rta", "t_igt", "health", "reaction", "move_state", "v_kmh",
              "vt_kmh", "x", "y", "z", "zt", "sz", "szd", "yaw_deg", "pitch_deg"]

# Positional assignment is the PRIMARY path, and deliberately so: it needs only
# the value to be read correctly, not the label. That distinction matters here
# because the labels carry the lowercase glyphs ('km/h', 'Walking') that segment
# least reliably, while the values are digits, which segment cleanly. Insisting
# the label match would discard rows whose number was read perfectly.
#
# These label patterns are the fallback for when the line count is NOT the
# expected 15 -- position means nothing then, and the label is all there is. The
# two 'Y' lines are told apart by the 'deg' suffix on the yaw one.
FIELDS: list[tuple[str, re.Pattern]] = [
    ("t_rta", re.compile(r"^T\(RTA\)=(-?[\d.]+)s")),
    ("t_igt", re.compile(r"^T\(IGT\)=(-?[\d.]+)s")),
    ("health", re.compile(r"^H=(-?[\d.]+)%")),
    ("reaction", re.compile(r"^RT=(-?[\d.]+)%")),
    ("move_state", re.compile(r"^MS=(.+)$")),
    ("v_kmh", re.compile(r"^V=(-?[\d.]+)")),
    ("vt_kmh", re.compile(r"^VT=(-?[\d.]+)")),
    ("x", re.compile(r"^X=(-?[\d.]+)$")),
    ("y", re.compile(r"^Y=(-?[\d.]+)$")),
    ("z", re.compile(r"^Z=(-?[\d.]+)$")),
    ("zt", re.compile(r"^ZT=(-?[\d.]+)$")),
    ("sz", re.compile(r"^SZ=(-?[\d.]+)$")),
    ("szd", re.compile(r"^SZD=(-?[\d.]+)$")),
    ("yaw_deg", re.compile(r"^Y=(-?[\d.]+)deg")),
    ("pitch_deg", re.compile(r"^P=(-?[\d.]+)deg")),
]

# Every move state the HUD can show is a TdMove_* class name minus its prefix,
# so the readable set is closed and known -- extracted from the CDO dump in
# appendix/A1. Snapping to it repairs the state name without a hand-written
# table of misreadings, which would go stale the moment the glyph library is
# recalibrated.
KNOWN_STATES = (
    '180Turn',
    '180TurnInAir',
    'AISpecialMove',
    'AirBarge',
    'AnimationPlayback',
    'AutoStepUp',
    'Balance',
    'Barge',
    'BotBlock',
    'BotJump',
    'BotLanding',
    'BotMelee',
    'BotStart',
    'BotStartRunning',
    'BotStartWalking',
    'BotStop',
    'BotTurnStanding',
    'Climb',
    'Coil',
    'Crouch',
    'Cutscene',
    'Disarmed',
    'DisarmedTutorial',
    'DodgeJump',
    'Falling',
    'FallingBot',
    'FallingUncontrolled',
    'Grab',
    'GrabJump',
    'GrabPullUp',
    'GrabPullUpBot',
    'GrabTransfer',
    'Interact',
    'IntoClimb',
    'IntoGrab',
    'IntoGrabBot',
    'IntoZipLine',
    'Jump',
    'JumpIntoGrabBot',
    'Landing',
    'LayOnGround',
    'LayOnGroundBot',
    'LedgeWalk',
    'Melee',
    'MeleeAir',
    'MeleeAirAbove',
    'MeleeCrouch',
    'MeleeSlide',
    'MeleeVault',
    'MeleeWallrun',
    'PursuitMelee',
    'RumpSlide',
    'SkillRoll',
    'Slide',
    'SlideBot',
    'SoftLanding',
    'SpeedVault',
    'SpringBoard',
    'StepUp',
    'Stumble',
    'Swing',
    'SwingJump',
    'Vault',
    'VaultOntoHigh',
    'VaultOverHigh',
    'Grabbing',
    'VaultOnto',
    'VaultOver',
    'VaultBot',
    'Vertigo',
    'Walking',
    'WallClimb',
    'WallClimbing',
    'WallClimb180TurnJump',
    'WallClimbDodgeJump',
    'WallKick',
    'WallRun',
    'WallRunningLeft',
    'WallRunningRight',
    'WallrunDodgeJump',
    'WallrunJump',
    'ZipLine',
)


def snap_state(text: str) -> str:
    """Pull a misread state name onto the nearest real one.

    Matching is by LENGTH plus per-position agreement, not edit distance:
    template matching substitutes characters but never inserts or deletes, so
    the misread string is always exactly as long as the truth ('3hmg' for
    'Jump'). Edit-distance ratios drop below any usable cutoff on a string that
    short, while length-locked positional agreement still identifies it
    uniquely -- among 4-character states only 'Jump' shares a character with it.
    """
    if not text or text in KNOWN_STATES:
        return text
    best, hits, tied = None, 0, False
    for candidate in KNOWN_STATES:
        if len(candidate) != len(text):
            continue
        agree = sum(a == b for a, b in zip(text, candidate))
        if agree > hits:
            best, hits, tied = candidate, agree, False
        elif agree == hits and agree > 0:
            tied = True
    if best is None or tied or hits < max(1, len(text) * 0.25):
        return text
    return best


def _aligned(reads) -> bool:
    """Is this frame's line list safe to assign by position?

    A count of exactly 15 is necessary but NOT sufficient: a dropped HUD line
    plus a spurious noise line also totals 15, and then every field lands one
    row off -- observed as a speed reading showing up in move_state. So also
    check two anchors whose shape survives misreading: the speed rows carry a
    '/' from "km/h", and the last two rows carry "deg". If those are not where
    they belong, fall back to label matching instead of emitting shifted data.
    """
    if len(reads) != len(LINE_ORDER):
        return False
    texts = [t for t, _ in reads]
    if "/" not in texts[5] and "/" not in texts[6]:
        return False
    if "de" not in texts[13] and "de" not in texts[14]:
        return False
    return True


AFTER_EQUALS = re.compile(r"=\s*(.+)$")
NUMBER = re.compile(r"-?\d+\.?\d*")

COLUMNS = (["frame", "line_count", "by_position", "worst_score"]
           + LINE_ORDER + ["move_state_raw", "raw_unmatched"])


def parse_frame(matcher: Matcher, image: np.ndarray,
                x_frac: float = HUD_X_FRAC) -> dict:
    reads = [matcher.read_line(g) for g in segment(image, x_frac)]
    row: dict = {"line_count": len(reads),
                 "by_position": _aligned(reads)}
    unmatched = []

    if row["by_position"]:
        for name, (text, _) in zip(LINE_ORDER, reads):
            value = AFTER_EQUALS.search(text)
            if value is None:
                unmatched.append(text)
                continue
            if name == "move_state":
                raw = value.group(1)
                row["move_state_raw"] = raw
                row[name] = snap_state(raw)
                continue
            hit = NUMBER.search(value.group(1))
            if hit:
                row[name] = hit.group(0)
            else:
                unmatched.append(text)
    else:
        for text, _ in reads:
            for name, pattern in FIELDS:
                if name in row:
                    continue
                hit = pattern.match(text)
                if hit:
                    row[name] = hit.group(1)
                    break
            else:
                unmatched.append(text)

    row["worst_score"] = round(min((s for _, s in reads), default=0.0), 3)
    row["raw_unmatched"] = "|".join(unmatched)
    return row


def probe_video(path: Path) -> tuple[int, int, float, int]:
    """(width, height, fps, frame count) via ffprobe."""
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height,r_frame_rate,nb_frames", "-of", "json", str(path)],
        capture_output=True, text=True, check=True)
    stream = json.loads(out.stdout)["streams"][0]
    num, den = stream["r_frame_rate"].split("/")
    return (int(stream["width"]), int(stream["height"]),
            int(num) / int(den), int(stream.get("nb_frames", 0)))


def probe_hud_rows(video: Path, x0: int, crop_w: int, height: int,
                   at_frame: int = 120) -> tuple[int, int]:
    """Row range the HUD occupies, measured on one frame partway in.

    The HUD is a fixed overlay, so this is constant for the whole video and
    worth finding once: the morphology below is the hot loop, and it costs in
    proportion to area. Here it cuts ~1080 rows down to ~480.
    """
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(video),
         "-vf", f"crop={crop_w}:{height}:{x0}:0,select=gte(n\\,{at_frame})",
         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "bgr24", "-"],
        capture_output=True)
    need = crop_w * height * 3
    if len(out.stdout) < need:
        return 0, height
    frame = np.frombuffer(out.stdout[:need], np.uint8).reshape(height, crop_w, 3)
    lines = find_lines(hud_mask(frame, 0.0)[0])
    if len(lines) < len(LINE_ORDER):
        return 0, height
    top = max(0, min(t for t, _ in lines) - 25)
    bottom = min(height, max(b for _, b in lines) + 25)
    return top, bottom


def cmd_run(args: argparse.Namespace) -> int:
    global WHITE_MIN
    if args.white_min is not None:
        WHITE_MIN = args.white_min
        print(f"WHITE_MIN overridden to {WHITE_MIN}")

    matcher = Matcher(args.glyphs)
    width, height, fps, total = probe_video(args.video)
    x0 = int(width * HUD_X_FRAC)
    crop_w = width - x0
    y0, y1 = probe_hud_rows(args.video, x0, crop_w, height)
    crop_h = y1 - y0
    print(f"{width}x{height} @ {fps:g} fps, {total} frames; "
          f"decoding only the {crop_w}x{crop_h} HUD box at ({x0},{y0})")
    if args.stride > 1:
        print(f"stride {args.stride}: reading every {args.stride}th frame "
              f"({fps / args.stride:g} effective fps)")

    # Decode through ffmpeg rather than cv2.VideoCapture: OpenCV ships an
    # ancient libaom that refuses modern AV1 streams (NVIDIA's capture writes
    # one), while ffmpeg has dav1d. Cropping in the filter graph also keeps 70%
    # of every frame from ever reaching Python.
    vf = f"crop={crop_w}:{crop_h}:{x0}:{y0}"
    if args.stride > 1:
        # Decimate in ffmpeg, not Python, so the skipped frames never get
        # converted or copied. The game runs at 62fps while these captures are
        # 120fps, so every game frame is recorded ~twice -- stride 2 loses
        # almost nothing and halves the work.
        vf += f",select=not(mod(n\\,{args.stride})),setpts=N/FRAME_RATE/TB"
    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", str(args.video),
         "-vf", vf, "-vsync", "0",
         "-f", "rawvideo", "-pix_fmt", "bgr24", "-"],
        stdout=subprocess.PIPE, bufsize=crop_w * crop_h * 3 * 4)

    frame_bytes = crop_w * crop_h * 3
    out = args.out or args.video.with_suffix(".csv")
    written = suspect = 0
    with out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=COLUMNS, restval="")
        writer.writeheader()
        index = 0
        while True:
            raw = proc.stdout.read(frame_bytes)
            if len(raw) < frame_bytes:
                break
            frame = np.frombuffer(raw, np.uint8).reshape(crop_h, crop_w, 3)
            row = parse_frame(matcher, frame, x_frac=0.0)
            # Frame numbers stay in the ORIGINAL video's numbering even when
            # striding, so timestamps remain frame/fps regardless of stride.
            row["frame"] = index * args.stride
            writer.writerow(row)
            written += 1
            if not row["by_position"] or "v_kmh" not in row:
                suspect += 1
            if total and index % 200 == 0:
                print(f"  {index}/{total} frames", file=sys.stderr)
            index += 1
    proc.stdout.close()
    proc.wait()

    print(f"{written} frames -> {out}")
    if suspect:
        print(f"WARNING: {suspect} frames ({suspect / max(written, 1):.1%}) did not "
              f"segment into {len(LINE_ORDER)} lines or lost the speed field; "
              f"check line_count and raw_unmatched")
    return 0


# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    subparsers = parser.add_subparsers(dest="command", required=True)

    p = subparsers.add_parser("probe", help="draw detected lines/glyphs onto an image")
    p.add_argument("image", type=Path)
    p.add_argument("--out", type=Path)
    p.set_defaults(func=cmd_probe)

    p = subparsers.add_parser("calib", help="build the glyph library from one frame")
    p.add_argument("image", type=Path)
    p.add_argument("truth", type=Path,
                   help="the HUD's exact text, one line per HUD line; a line of "
                        '"-" skips that line')
    p.add_argument("--out", type=Path, default=Path("glyphs.npz"))
    p.add_argument("--append", action="store_true",
                   help="merge into an existing library instead of replacing it; "
                        "needed because no single frame shows every digit")
    p.set_defaults(func=cmd_calib)

    p = subparsers.add_parser("run", help="extract a whole video to CSV")
    p.add_argument("video", type=Path)
    p.add_argument("--glyphs", type=Path, default=Path("glyphs.npz"))
    p.add_argument("--out", type=Path)
    p.add_argument("--stride", type=int, default=1,
                   help="process every Nth frame (2 is nearly free: 120fps "
                        "capture of a 62fps game records each frame twice)")
    p.add_argument("--white-min", type=int,
                   help="override WHITE_MIN; lower it if a video segments far "
                        "worse than a screenshot of the same HUD")
    p.set_defaults(func=cmd_run)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
