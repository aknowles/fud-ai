#!/usr/bin/env python3
"""Copy store/screenshots/ PNGs into store/metadata/screenshots/ for ASC + Play upload."""
from __future__ import annotations

import argparse
import io
import os
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_cli  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PLAY_SOURCE = ROOT / "store" / "screenshots" / "play"
PLAY_PHONE_DIR = ROOT / "store" / "metadata" / "screenshots" / "play" / "phone"
IOS_STAGED = ROOT / "store" / "metadata" / "screenshots" / "ios"


@dataclass(frozen=True)
class AscSet:
    """One App Store Connect screenshot set: its source folder, staged folder and sizes."""

    label: str
    source: Path
    dest: Path
    # Portrait sizes ASC accepts; anything else is fitted onto the first one.
    accepted: tuple[tuple[int, int], ...]


# Every set the App Store listing gets, in upload order. The staged folder names
# are the ones asc_release.py reads.
ASC_SETS = (
    AscSet(
        '6.7" iPhone',
        ROOT / "store" / "screenshots" / "ios",
        IOS_STAGED / "6.7",
        ((1290, 2796), (1284, 2778)),
    ),
    AscSet(
        '13" iPad',
        ROOT / "store" / "screenshots" / "ipad",
        IOS_STAGED / "ipad-13",
        ((2064, 2752), (2048, 2732)),
    ),
    # One set takes both screens: outer 1398x2034 and inner 2007x2853.
    AscSet(
        "iPhone Duo",
        ROOT / "store" / "screenshots" / "iphone-duo",
        IOS_STAGED / "iphone-duo",
        ((1398, 2034), (2007, 2853)),
    ),
)

# A frame that is not an accepted ASC size is fitted onto the set's first size only
# when its shape is this close, so a frame from another device's set fails staging.
ASC_ASPECT_TOLERANCE = 0.03

# Google Play phone screenshots (portrait ~9:16)
PLAY_MIN_SIDE = 320
PLAY_MAX_SIDE = 3840
PLAY_PORTRAIT_ASPECT = 9 / 16  # width / height
PLAY_ASPECT_TOLERANCE = 0.08
# Play Console phone screenshot cap (App Store allows 10).
PLAY_PHONE_MAX = 8


def fail(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def uploads_enabled() -> bool:
    return os.environ.get("STORE_UPLOAD_SCREENSHOTS", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def try_import_pillow():
    try:
        from PIL import Image  # type: ignore[import-untyped]

        return Image
    except ImportError:
        return None


def read_png_size(path: Path) -> tuple[int, int]:
    Image = try_import_pillow()
    if Image is not None:
        with Image.open(path) as img:
            return img.size
    # PNG IHDR without Pillow
    with path.open("rb") as f:
        header = f.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"not a PNG: {path}")
    w = int.from_bytes(header[16:20], "big")
    h = int.from_bytes(header[20:24], "big")
    return w, h


def fit_and_pad_rgba(
    Image, src, target_w: int, target_h: int, fill=(0, 0, 0, 255)
):
    src_w, src_h = src.size
    scale = min(target_w / src_w, target_h / src_h)
    new_w = max(1, int(round(src_w * scale)))
    new_h = max(1, int(round(src_h * scale)))
    resized = src.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (target_w, target_h), fill)
    ox = (target_w - new_w) // 2
    oy = (target_h - new_h) // 2
    canvas.paste(resized, (ox, oy), resized if resized.mode == "RGBA" else None)
    return canvas


def opaque_rgb(Image, img):
    """The image without an alpha channel, transparent pixels laid over black.

    App Store Connect (and asc) refuse screenshots that store alpha, even when
    every pixel is opaque.
    """
    img = img.convert("RGBA")
    canvas = Image.new("RGB", img.size, (0, 0, 0))
    canvas.paste(img, mask=img.getchannel("A"))
    return canvas


def prepare_asc_png(Image, path: Path, asc_set: AscSet) -> bytes:
    target_w, target_h = asc_set.accepted[0]
    with Image.open(path) as img:
        img = img.convert("RGBA")
        w, h = img.size
        if (w, h) not in asc_set.accepted:
            img = fit_and_pad_rgba(Image, img, target_w, target_h)
        out_img = opaque_rgb(Image, img)
    out = io.BytesIO()
    out_img.save(out, format="PNG")
    return out.getvalue()


def play_portrait_ok(width: int, height: int) -> bool:
    if width <= 0 or height <= 0 or height <= width:
        return False
    if min(width, height) < PLAY_MIN_SIDE or max(width, height) > PLAY_MAX_SIDE:
        return False
    aspect = width / height
    return abs(aspect - PLAY_PORTRAIT_ASPECT) <= PLAY_ASPECT_TOLERANCE


def validate_play_png(path: Path, *, width: int, height: int) -> None:
    if not play_portrait_ok(width, height):
        fail(
            f"{path.name}: Play phone screenshot must be portrait ~9:16 with each side "
            f"between {PLAY_MIN_SIDE} and {PLAY_MAX_SIDE}px (got {width}x{height})"
        )


def clear_destination_pngs(*dest_dirs: Path) -> None:
    for dest_dir in dest_dirs:
        dest_dir.mkdir(parents=True, exist_ok=True)
        for stale in dest_dir.glob("*.png"):
            stale.unlink()


def validate_asc_png(path: Path, asc_set: AscSet, *, width: int, height: int) -> None:
    if (width, height) not in asc_set.accepted:
        accepted = ", ".join(f"{w}x{h}" for w, h in asc_set.accepted)
        fail(
            f"{path.name}: ASC {asc_set.label} screenshot must be {accepted} "
            f"(got {width}x{height}). Install Pillow (requirements-store.txt) "
            "so staging can resize automatically, or pre-export at the required size."
        )


def asc_frame_fits(asc_set: AscSet, width: int, height: int) -> bool:
    if (width, height) in asc_set.accepted:
        return True
    if width <= 0 or height <= 0:
        return False
    target_w, target_h = asc_set.accepted[0]
    return abs(width / height - target_w / target_h) <= ASC_ASPECT_TOLERANCE * target_w / target_h


def check_asc_frames(asc_set: AscSet, pngs: list[Path]) -> None:
    for path in pngs:
        w, h = read_png_size(path)
        if not asc_frame_fits(asc_set, w, h):
            accepted = ", ".join(f"{aw}x{ah}" for aw, ah in asc_set.accepted)
            fail(
                f"{asc_set.source.name}/{path.name}: {w}x{h} is not shaped like an ASC "
                f"{asc_set.label} screenshot ({accepted}); is it in the wrong folder?"
            )


def numbered_pngs(source: Path) -> list[Path]:
    if not source.is_dir():
        fail(f"screenshot source missing: {source.relative_to(ROOT)}")

    # Store uploads use numbered frames only (01-….png), in file-name order.
    pngs = sorted(
        p
        for p in source.glob("*.png")
        if len(p.name) >= 3 and p.name[0:2].isdigit() and p.name[2] == "-"
    )
    if not pngs:
        fail(
            f"no numbered PNG files (NN-name.png) under {source.relative_to(ROOT)}"
        )
    return pngs


def stage(*, dry_run: bool, platform: str = "all") -> list[Path]:
    ios_sets = (
        [(asc_set, numbered_pngs(asc_set.source)) for asc_set in ASC_SETS]
        if platform in ("ios", "all")
        else []
    )
    play_pngs = numbered_pngs(PLAY_SOURCE) if platform in ("play", "all") else []

    if len(play_pngs) > PLAY_PHONE_MAX:
        skipped = ", ".join(p.name for p in play_pngs[PLAY_PHONE_MAX:])
        print(f"note: Play phone cap is {PLAY_PHONE_MAX}; not staging: {skipped}")
        play_pngs = play_pngs[:PLAY_PHONE_MAX]

    for asc_set, pngs in ios_sets:
        check_asc_frames(asc_set, pngs)

    will_upload = uploads_enabled()
    Image = try_import_pillow()
    if will_upload and Image is None:
        for path in play_pngs:
            w, h = read_png_size(path)
            validate_play_png(path, width=w, height=h)
        for asc_set, pngs in ios_sets:
            for path in pngs:
                w, h = read_png_size(path)
                validate_asc_png(path, asc_set, width=w, height=h)
                if asc_cli.image_has_alpha(path):
                    fail(
                        f"{path.name}: App Store screenshots cannot have an alpha channel; install Pillow "
                        "(requirements-store.txt) so staging can flatten it, or re-export it as RGB"
                    )

    if not dry_run:
        clear_destination_pngs(
            *([PLAY_PHONE_DIR] if play_pngs else []),
            *(asc_set.dest for asc_set, _ in ios_sets),
        )

    copied: list[Path] = []
    for path in play_pngs:
        w, h = read_png_size(path)

        if dry_run:
            print(
                f"dry-run: would stage play/{path.name} ({w}x{h}) → "
                f"{PLAY_PHONE_DIR.relative_to(ROOT)}"
            )
            continue

        play_dest = PLAY_PHONE_DIR / path.name
        if will_upload:
            if Image is not None and not play_portrait_ok(w, h):
                with Image.open(path) as img:
                    img = img.convert("RGBA")
                    target_h = min(PLAY_MAX_SIDE, max(h, PLAY_MIN_SIDE * 16 // 9))
                    target_w = int(round(target_h * PLAY_PORTRAIT_ASPECT))
                    target_w = min(PLAY_MAX_SIDE, max(PLAY_MIN_SIDE, target_w))
                    play_img = fit_and_pad_rgba(Image, img, target_w, target_h)
                out = io.BytesIO()
                play_img.save(out, format="PNG")
                play_bytes = out.getvalue()
            else:
                validate_play_png(path, width=w, height=h)
                play_bytes = path.read_bytes()
        else:
            play_bytes = path.read_bytes()

        play_dest.write_bytes(play_bytes)
        copied.append(play_dest)

    for asc_set, pngs in ios_sets:
        for path in pngs:
            w, h = read_png_size(path)

            if dry_run:
                print(
                    f"dry-run: would stage {asc_set.source.name}/{path.name} ({w}x{h}) → "
                    f"{asc_set.dest.relative_to(ROOT)}"
                )
                continue

            ios_dest = asc_set.dest / path.name
            if Image is not None:
                ios_bytes = prepare_asc_png(Image, path, asc_set)
            elif will_upload:
                validate_asc_png(path, asc_set, width=w, height=h)
                ios_bytes = path.read_bytes()
            else:
                ios_bytes = path.read_bytes()
            ios_dest.write_bytes(ios_bytes)
            copied.append(ios_dest)

    if not dry_run:
        ios_counts = "".join(
            f" + {len(pngs)} ASC {asc_set.label}" for asc_set, pngs in ios_sets
        )
        print(f"staged {len(play_pngs)} Play phone{ios_counts} screenshot(s)")
    return copied


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned copies only (no filesystem changes)",
    )
    parser.add_argument(
        "--platform",
        choices=("play", "ios", "all"),
        default="all",
        help="Which store's screenshots to stage (default: all)",
    )
    args = parser.parse_args()
    stage(dry_run=args.dry_run, platform=args.platform)


if __name__ == "__main__":
    main()
