"""Offline tests for stage_screenshots.py: per-platform sources, cleanup, order and caps."""
from __future__ import annotations

import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import stage_screenshots as ss  # noqa: E402

# The store-automation job runs this file again after installing Pillow, with
# STORE_TESTS_NEED_PILLOW set, so the resizing tests can't skip there.
PILLOW = ss.try_import_pillow()


def png(width: int, height: int, marker: str) -> bytes:
    # Signature + IHDR length/type + size: enough for read_png_size without Pillow.
    return (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR"
        + width.to_bytes(4, "big")
        + height.to_bytes(4, "big")
        + marker.encode()
    )


class SetsFixture(unittest.TestCase):
    """The real screenshot sets under a temporary root. PILLOW picks the staging path."""

    PILLOW = None

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        # The real sets, moved under the temporary root.
        self.asc_sets = [
            ss.AscSet(
                asc_set.label,
                self.root / asc_set.source.relative_to(ss.ROOT),
                self.root / asc_set.dest.relative_to(ss.ROOT),
                asc_set.accepted,
            )
            for asc_set in ss.ASC_SETS
        ]
        self.ios_src, self.ipad_src, self.duo_src = (a.source for a in self.asc_sets)
        self.ios_dest, self.ipad_dest, self.duo_dest = (a.dest for a in self.asc_sets)
        self.play_src = self.root / "store" / "screenshots" / "play"
        self.play_dest = self.root / "store" / "metadata" / "screenshots" / "play" / "phone"
        for patch in (
            mock.patch.object(ss, "ROOT", self.root),
            mock.patch.object(ss, "ASC_SETS", tuple(self.asc_sets)),
            mock.patch.object(ss, "PLAY_SOURCE", self.play_src),
            mock.patch.object(ss, "PLAY_PHONE_DIR", self.play_dest),
            mock.patch.object(ss, "try_import_pillow", return_value=self.PILLOW),
            mock.patch.dict(os.environ, {"STORE_UPLOAD_SCREENSHOTS": ""}),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def write(self, directory: Path, *names: str, size: tuple[int, int] = (1290, 2796)) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        for name in names:
            (directory / name).write_bytes(png(*size, f"{directory.name}/{name}"))

    def write_tablet_sets(self) -> None:
        self.write(self.ipad_src, "01-i.png", size=(2064, 2752))
        self.write(self.duo_src, "01-d.png", size=(1398, 2034))

    def stage(self, **kwargs):
        with redirect_stdout(io.StringIO()):
            return ss.stage(**kwargs)

    def names(self, directory: Path) -> list[str]:
        return sorted(p.name for p in directory.glob("*.png"))


class StageTests(SetsFixture):
    # Raw copies, so staged bytes can be compared with the sources.
    PILLOW = None

    def test_all_stages_each_store_from_its_own_source_in_name_order(self):
        self.write(self.ios_src, "02-b.png", "10-j.png", "01-a.png", "home.png")
        self.write_tablet_sets()
        self.write(self.play_src, "02-y.png", "01-x.png")

        copied = self.stage(dry_run=False, platform="all")

        self.assertEqual(self.names(self.ios_dest), ["01-a.png", "02-b.png", "10-j.png"])
        self.assertEqual(self.names(self.ipad_dest), ["01-i.png"])
        self.assertEqual(self.names(self.duo_dest), ["01-d.png"])
        self.assertEqual(self.names(self.play_dest), ["01-x.png", "02-y.png"])
        self.assertEqual(
            [p.name for p in copied],
            ["01-x.png", "02-y.png", "01-a.png", "02-b.png", "10-j.png", "01-i.png", "01-d.png"],
        )
        for dest, src in (
            (self.ios_dest, self.ios_src),
            (self.ipad_dest, self.ipad_src),
            (self.duo_dest, self.duo_src),
            (self.play_dest, self.play_src),
        ):
            for name in self.names(dest):
                self.assertEqual((dest / name).read_bytes(), (src / name).read_bytes())

    def test_ios_only_replaces_ios_set_and_keeps_staged_play_files(self):
        self.write(self.ios_src, "01-a.png")
        self.write_tablet_sets()
        self.write(self.ios_dest, "09-stale.png")
        self.write(self.ipad_dest, "09-stale.png")
        self.write(self.play_dest, "01-staged.png")

        self.stage(dry_run=False, platform="ios")

        self.assertEqual(self.names(self.ios_dest), ["01-a.png"])
        self.assertEqual(self.names(self.ipad_dest), ["01-i.png"])
        self.assertEqual(self.names(self.play_dest), ["01-staged.png"])

    def test_play_only_replaces_play_set_and_keeps_staged_ios_files(self):
        self.write(self.play_src, "01-x.png")
        self.write(self.play_dest, "09-stale.png")
        self.write(self.ios_dest, "01-staged.png")

        self.stage(dry_run=False, platform="play")

        self.assertEqual(self.names(self.play_dest), ["01-x.png"])
        self.assertEqual(self.names(self.ios_dest), ["01-staged.png"])

    def test_one_platform_does_not_need_the_other_source(self):
        self.write(self.ios_src, "01-a.png")
        self.write_tablet_sets()

        self.stage(dry_run=False, platform="ios")

        self.assertEqual(self.names(self.ios_dest), ["01-a.png"])
        self.assertFalse(self.play_dest.exists())

    def test_play_stages_at_most_the_phone_cap(self):
        names = [f"{i:02d}-p.png" for i in range(1, ss.PLAY_PHONE_MAX + 2)]
        self.write(self.play_src, *names)

        self.stage(dry_run=False, platform="play")

        self.assertEqual(self.names(self.play_dest), names[: ss.PLAY_PHONE_MAX])

    def test_dry_run_writes_and_removes_nothing(self):
        self.write(self.ios_src, "01-a.png")
        self.write_tablet_sets()
        self.write(self.play_src, "01-x.png")
        self.write(self.ios_dest, "09-stale.png")

        copied = self.stage(dry_run=True, platform="all")

        self.assertEqual(copied, [])
        self.assertEqual(self.names(self.ios_dest), ["09-stale.png"])
        self.assertFalse(self.play_dest.exists())

    def test_missing_or_empty_source_fails_before_touching_staged_files(self):
        self.write(self.ios_dest, "01-staged.png")
        self.write_tablet_sets()
        for setup in (lambda: None, lambda: self.write(self.ios_src, "home.png")):
            setup()
            with self.subTest(source_files=self.names(self.ios_src) if self.ios_src.exists() else None):
                with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
                    self.stage(dry_run=False, platform="ios")
                self.assertEqual(self.names(self.ios_dest), ["01-staged.png"])

    def test_every_ios_set_needs_its_own_source(self):
        self.write(self.ios_src, "01-a.png")
        self.write(self.ios_dest, "01-staged.png")
        for source in (self.ipad_src, self.duo_src):
            self.write_tablet_sets()
            for stale in source.glob("*.png"):
                stale.unlink()
            with self.subTest(source=source.name):
                with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
                    self.stage(dry_run=False, platform="ios")
                self.assertEqual(self.names(self.ios_dest), ["01-staged.png"])

    def test_a_frame_from_another_devices_set_fails_even_with_uploads_off(self):
        self.write(self.ios_src, "01-a.png")
        self.write_tablet_sets()
        self.write(self.ipad_dest, "01-staged.png")
        for source, size in ((self.ipad_src, (1290, 2796)), (self.duo_src, (2064, 2752))):
            self.write_tablet_sets()
            self.write(source, "02-misplaced.png", size=size)
            with self.subTest(source=source.name):
                for dry_run in (True, False):
                    stderr = io.StringIO()
                    with self.assertRaises(SystemExit), redirect_stderr(stderr):
                        self.stage(dry_run=dry_run, platform="ios")
                    self.assertIn("02-misplaced.png", stderr.getvalue())
                self.assertEqual(self.names(self.ipad_dest), ["01-staged.png"])
            (source / "02-misplaced.png").unlink()

    def test_a_frame_shaped_like_its_set_is_still_staged(self):
        # 6.5" iPhone frames have the 6.7" shape; staging fits them onto 1290x2796
        # (asc refuses 1284x2778 in the 6.7" set).
        self.assertTrue(ss.asc_frame_fits(self.asc_sets[0], 1284, 2778))
        self.assertNotIn((1284, 2778), self.asc_sets[0].accepted)
        self.write(self.ios_src, "01-a.png", size=(1284, 2778))
        self.write_tablet_sets()

        self.stage(dry_run=False, platform="ios")

        self.assertEqual(self.names(self.ios_dest), ["01-a.png"])

    def test_upload_without_pillow_refuses_alpha(self):
        self.write(self.ios_src, "01-a.png")
        self.write_tablet_sets()
        # Colour type 6 (RGBA) in the IHDR: asc would refuse the upload.
        path = self.ipad_src / "01-i.png"
        raw = bytearray(path.read_bytes())
        raw[25] = 6
        path.write_bytes(bytes(raw))
        with mock.patch.dict(os.environ, {"STORE_UPLOAD_SCREENSHOTS": "true"}):
            stderr = io.StringIO()
            with self.assertRaises(SystemExit), redirect_stderr(stderr):
                self.stage(dry_run=False, platform="ios")
        self.assertIn("alpha channel", stderr.getvalue())

    def test_upload_without_pillow_checks_each_sets_sizes(self):
        self.write(self.ios_src, "01-a.png")
        self.write_tablet_sets()
        # Both Duo screens fit the one Duo set.
        self.write(self.duo_src, "02-inner.png", size=(2007, 2853))
        with mock.patch.dict(os.environ, {"STORE_UPLOAD_SCREENSHOTS": "true"}):
            self.stage(dry_run=False, platform="ios")
            self.assertEqual(self.names(self.duo_dest), ["01-d.png", "02-inner.png"])

            # An iPhone-sized frame in the iPad set is refused before anything is replaced.
            self.write(self.ipad_src, "02-phone.png")
            stderr = io.StringIO()
            with self.assertRaises(SystemExit), redirect_stderr(stderr):
                self.stage(dry_run=False, platform="ios")
        self.assertIn('13" iPad', stderr.getvalue())
        self.assertEqual(self.names(self.ipad_dest), ["01-i.png"])


@unittest.skipIf(
    PILLOW is None and not os.environ.get("STORE_TESTS_NEED_PILLOW"), "Pillow not installed"
)
class PillowStageTests(SetsFixture):
    """The path release runs take: Pillow keeps accepted sizes and fits the rest."""

    PILLOW = PILLOW

    def setUp(self):
        if self.PILLOW is None:
            self.fail("Pillow is required here (STORE_TESTS_NEED_PILLOW is set)")
        super().setUp()

    def image(self, directory: Path, name: str, size: tuple[int, int], color) -> Path:
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / name
        self.PILLOW.new("RGBA", size, color).save(path)
        return path

    def staged_size(self, path: Path) -> tuple[int, int]:
        with self.PILLOW.open(path) as img:
            return img.size

    def test_translucent_pixels_are_blended_once_even_when_resized(self):
        # Half-transparent white over black is mid grey; blending twice made it ~96.
        for size in ((2064, 2752), (1032, 1376)):
            source = self.image(self.ipad_src, "01-glass.png", size, (255, 255, 255, 128))
            self.image(self.ios_src, "01-a.png", (1290, 2796), (0, 0, 0, 255))
            self.image(self.duo_src, "01-d.png", (1398, 2034), (0, 0, 0, 255))
            with mock.patch.dict(os.environ, {"STORE_UPLOAD_SCREENSHOTS": "true"}):
                self.stage(dry_run=False, platform="ios")
            with self.PILLOW.open(self.ipad_dest / source.name) as staged, self.subTest(size=size):
                self.assertEqual(staged.size, (2064, 2752))
                red, green, blue = staged.getpixel((1032, 1376))
                self.assertTrue(126 <= red <= 130 and red == green == blue, (red, green, blue))

    def test_accepted_sizes_stay_unchanged_and_other_shapes_fit_their_set(self):
        cases = [
            # (set index, source size, staged size)
            (0, (1290, 2796), (1290, 2796)),
            (0, (1320, 2868), (1320, 2868)),
            (0, (1284, 2778), (1290, 2796)),
            (1, (2064, 2752), (2064, 2752)),
            (1, (2048, 2732), (2048, 2732)),
            (1, (1032, 1376), (2064, 2752)),
            (2, (1398, 2034), (1398, 2034)),
            (2, (2007, 2853), (2007, 2853)),
            (2, (699, 1017), (1398, 2034)),
        ]
        sources = []
        for i, (index, size, _) in enumerate(cases):
            asc_set = self.asc_sets[index]
            sources.append(self.image(asc_set.source, f"{i + 1:02d}-frame.png", size, (255, 83, 142, 255)))

        with mock.patch.dict(os.environ, {"STORE_UPLOAD_SCREENSHOTS": "true"}):
            self.stage(dry_run=False, platform="ios")

        for source, (index, size, staged) in zip(sources, cases):
            dest = self.asc_sets[index].dest / source.name
            with self.subTest(set=self.asc_sets[index].label, size=size):
                self.assertEqual(self.staged_size(dest), staged)
                # asc refuses any PNG that stores alpha, even an opaque one.
                self.assertFalse(ss.asc_cli.image_has_alpha(dest))
                with self.PILLOW.open(dest) as img:
                    self.assertEqual(img.mode, "RGB")
                if size == staged:
                    with self.PILLOW.open(source) as a, self.PILLOW.open(dest) as b:
                        self.assertEqual(a.convert("RGB").tobytes(), b.convert("RGB").tobytes())


if __name__ == "__main__":
    unittest.main()
