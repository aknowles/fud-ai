#!/usr/bin/env python3
"""Offline tests for iOS release switches, build waiting, build selection and the asc runner.

No network: every asc call goes to an in-memory fake of App Store Connect.
Run: python3 -m unittest scripts/store/test_ios_release.py
"""
from __future__ import annotations

import hashlib
import io
import os
import plistlib
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import asc_cli  # noqa: E402
import asc_release  # noqa: E402
import ios_release  # noqa: E402
import prepare_whats_new  # noqa: E402
import print_gates  # noqa: E402
import redact_credential_ids  # noqa: E402
import release_notes  # noqa: E402
from ios_release import ReleaseError, resolve_gates  # noqa: E402

TAG = "ios-v7.2"
VERSION = "7.2"
ALL_ON = {
    "IOS_RELEASE_AUTOMATION": "true",
    "IOS_CREATE_VERSION": "true",
    "IOS_UPLOAD_BUILD": "true",
    "IOS_UPLOAD_LISTING": "true",
    "IOS_UPLOAD_WHATS_NEW": "true",
    "IOS_UPLOAD_SCREENSHOTS": "true",
    "IOS_UPLOAD_CREATIVE_ASSETS": "true",
    "IOS_SUBMIT_REVIEW": "true",
    "IOS_PUBLIC_RELEASE": "true",
}
OPS = ("create_version", "upload_build", "listing", "whats_new", "screenshots", "creative", "submit", "public_release")


def gates(env: dict[str, str], *, event: str = "push", ref: str = TAG) -> dict:
    return resolve_gates(env, event=event, ref_name=ref, marketing_version=VERSION)


class GateTests(unittest.TestCase):
    def test_missing_settings_mean_everything_off(self) -> None:
        result = gates({})
        self.assertEqual(result["mode"], "release")
        self.assertFalse(result["master"])
        self.assertFalse(result["build"])
        self.assertFalse(result["asc"])
        for key in OPS:
            self.assertFalse(result[key], key)
        self.assertEqual(result["poll_seconds"], 30)
        self.assertEqual(result["wait_minutes"], 120)

    def test_master_off_ignores_operation_switches(self) -> None:
        result = gates({**ALL_ON, "IOS_RELEASE_AUTOMATION": "false"})
        for key in OPS:
            self.assertFalse(result[key], key)
        self.assertFalse(result["build"])
        self.assertTrue(any("ignored" in note for note in result["notes"]))

    def test_each_operation_is_independent(self) -> None:
        result = gates({"IOS_RELEASE_AUTOMATION": "yes", "IOS_UPLOAD_LISTING": "on"})
        self.assertTrue(result["listing"])
        self.assertTrue(result["asc"])
        self.assertFalse(result["whats_new"])
        self.assertFalse(result["upload_build"])
        self.assertFalse(result["build"])

    def test_creative_assets_are_their_own_switch(self) -> None:
        result = gates({"IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_CREATIVE_ASSETS": "true"})
        self.assertTrue(result["creative"])
        self.assertTrue(result["asc"])
        self.assertFalse(result["screenshots"])
        self.assertFalse(result["build"])
        with self.assertRaisesRegex(ReleaseError, "IOS_UPLOAD_CREATIVE_ASSETS"):
            gates({"IOS_UPLOAD_CREATIVE_ASSETS": "sometimes"})

    def test_all_on(self) -> None:
        result = gates(ALL_ON)
        for key in OPS:
            self.assertTrue(result[key], key)
        self.assertTrue(result["build"])

    def test_invalid_values_are_rejected_even_when_master_is_off(self) -> None:
        for name in ("IOS_RELEASE_AUTOMATION", "IOS_SUBMIT_REVIEW", "IOS_UPLOAD_WHATS_NEW"):
            with self.subTest(name=name), self.assertRaisesRegex(ReleaseError, name):
                gates({name: "maybe"})

    def test_bad_timing_values_are_rejected(self) -> None:
        for env in (
            {"IOS_BUILD_POLL_SECONDS": "5"},
            {"IOS_BUILD_POLL_SECONDS": "thirty"},
            {"IOS_BUILD_POLL_SECONDS": "٣٠"},
            {"IOS_BUILD_WAIT_MINUTES": "0"},
            {"IOS_BUILD_WAIT_MINUTES": "999"},
        ):
            with self.subTest(env=env), self.assertRaises(ReleaseError):
                gates(env)
        result = gates({"IOS_BUILD_POLL_SECONDS": "45", "IOS_BUILD_WAIT_MINUTES": "90"})
        self.assertEqual((result["poll_seconds"], result["wait_minutes"]), (45, 90))

    def test_submit_requires_this_runs_build(self) -> None:
        env = {"IOS_RELEASE_AUTOMATION": "true", "IOS_SUBMIT_REVIEW": "true"}
        with self.assertRaisesRegex(ReleaseError, "IOS_UPLOAD_BUILD"):
            gates(env)

    def test_public_release_requires_submit(self) -> None:
        env = {"IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_BUILD": "true", "IOS_PUBLIC_RELEASE": "true"}
        with self.assertRaisesRegex(ReleaseError, "IOS_SUBMIT_REVIEW"):
            gates(env)

    def test_tag_must_match_marketing_version(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "does not match"):
            gates({}, ref="ios-v7.3")
        with self.assertRaisesRegex(ReleaseError, "ios-v"):
            gates({}, ref="v7.2")

    def test_manual_run_validates_only(self) -> None:
        result = gates(ALL_ON, event="workflow_dispatch", ref="main")
        self.assertEqual(result["mode"], "validate")
        self.assertTrue(result["build"])
        self.assertFalse(result["master"])
        self.assertFalse(result["asc"])
        for key in OPS:
            self.assertFalse(result[key], key)

    def test_manual_run_can_validate_a_future_version(self) -> None:
        result = resolve_gates({}, event="workflow_dispatch", ref_name="main",
                               marketing_version=VERSION, validation_version="7.3")
        self.assertEqual(result["mode"], "validate")
        self.assertEqual(result["marketing_version"], "7.3")
        self.assertFalse(result["asc"])
        default = resolve_gates({}, event="workflow_dispatch", ref_name="main", marketing_version=VERSION)
        self.assertEqual(default["marketing_version"], VERSION)

    def test_version_override_is_rejected_for_releases_and_bad_values(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "manual validation"):
            resolve_gates({}, event="push", ref_name=TAG, marketing_version=VERSION, validation_version="7.3")
        for bad in ("7.x", "v7.3", "7.3.1.2", "7.3 beta", "٧.٢"):
            with self.subTest(bad=bad), self.assertRaisesRegex(ReleaseError, "must look like"):
                resolve_gates({}, event="workflow_dispatch", ref_name="main",
                              marketing_version=VERSION, validation_version=bad)

    def test_create_version_needs_only_the_master_switch(self) -> None:
        result = gates({"IOS_RELEASE_AUTOMATION": "true", "IOS_CREATE_VERSION": "true"})
        self.assertTrue(result["create_version"])
        self.assertFalse(result["build"])
        self.assertFalse(result["asc"])
        self.assertFalse(gates({"IOS_CREATE_VERSION": "true"})["create_version"])
        self.assertFalse(gates(ALL_ON, event="workflow_dispatch", ref="main")["create_version"])
        with self.assertRaisesRegex(ReleaseError, "IOS_CREATE_VERSION"):
            gates({"IOS_CREATE_VERSION": "maybe"})

    def test_project_versions_are_consistent(self) -> None:
        self.assertRegex(ios_release.single_project_value("MARKETING_VERSION"), r"^\d+(\.\d+)*$")
        self.assertRegex(ios_release.single_project_value("CURRENT_PROJECT_VERSION"), r"^\d+$")
        with tempfile.TemporaryDirectory() as tmp:
            pbx = Path(tmp) / "project.pbxproj"
            pbx.write_text("MARKETING_VERSION = 1.0;\nMARKETING_VERSION = 1.1;\n")
            with self.assertRaisesRegex(ReleaseError, "identical"):
                ios_release.single_project_value("MARKETING_VERSION", pbx)


class ExportComplianceTests(unittest.TestCase):
    """ITSAppUsesNonExemptEncryption must be declared, or App Store Connect asks about every build
    and review submission fails with usesNonExemptEncryption missing (HTTP 409)."""

    KEY = "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption"
    CODE = {"INFOPLIST_KEY_ITSEncryptionExportComplianceCode": "ABC123"}
    GENERATED = {"GENERATE_INFOPLIST_FILE": "YES"}
    APP_PLIST = {"INFOPLIST_FILE": "calorietracker/Info.plist", **GENERATED}

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "calorietracker.xcodeproj").mkdir()
        (self.root / "calorietracker").mkdir()

    def plist(self, values: dict, *, binary: bool = False, name: str = "calorietracker/Info.plist") -> Path:
        fmt = plistlib.FMT_BINARY if binary else plistlib.FMT_XML
        path = self.root / name
        path.write_bytes(plistlib.dumps({"CFBundleName": "Fud AI", **values}, fmt=fmt))
        return path

    def project(self, app: dict[str, dict[str, str]], *, project: dict[str, dict[str, str]] | None = None,
                other: dict[str, dict[str, str]] | None = None) -> Path:
        """A minimal project.pbxproj: the app target, an optional other target, project-level settings."""
        ids = iter(f"{n:024X}" for n in range(1, 1000))
        objects: list[str] = []

        def config_list(owner: str, configs: dict[str, dict[str, str]]) -> str:
            list_id = next(ids)
            refs = []
            for name, settings in configs.items():
                config_id = next(ids)
                refs.append(f"\t\t\t\t{config_id} /* {name} */,\n")
                lines = "".join(f"\t\t\t\t{key} = {value};\n" for key, value in settings.items())
                objects.append(f"\t\t{config_id} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
                               f"\t\t\tbuildSettings = {{\n{lines}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")
            objects.append(f"\t\t{list_id} /* Build configuration list for {owner} */ = {{\n"
                           f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n{''.join(refs)}\t\t\t);\n"
                           "\t\t\tdefaultConfigurationName = Release;\n\t\t};\n")
            return list_id

        def target(name: str, configs: dict[str, dict[str, str]]) -> None:
            list_id = config_list(f'PBXNativeTarget "{name}"', configs)
            objects.append(f"\t\t{next(ids)} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
                           f"\t\t\tbuildConfigurationList = {list_id} /* Build configuration list */;\n"
                           f"\t\t\tname = {name};\n\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t}};\n")

        target("calorietracker", app)
        if other is not None:
            target("FudAIWatchApp", other)
        project_list = config_list('PBXProject "calorietracker"', project or {"Debug": {}, "Release": {}})
        objects.append(f"\t\t{next(ids)} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n"
                       f"\t\t\tbuildConfigurationList = {project_list} /* Build configuration list */;\n\t\t}};\n")
        path = self.root / "calorietracker.xcodeproj" / "project.pbxproj"
        path.write_text("// !$*UTF8*$!\n{\n\tobjects = {\n" + "".join(objects) + "\t};\n}\n", encoding="utf-8")
        return path

    def check(self, app: dict[str, dict[str, str]], **kwargs) -> str:
        return ios_release.check_export_compliance(self.project(app, **kwargs))

    def both(self, settings: dict[str, str]) -> dict[str, dict[str, str]]:
        return {"Debug": dict(settings), "Release": dict(settings)}

    def test_the_app_declares_no_non_exempt_encryption(self) -> None:
        self.assertEqual(ios_release.check_export_compliance(), "NO")
        configs = ios_release.app_configurations()
        self.assertEqual(set(configs), {"Debug", "Release"})
        for name, settings in configs.items():
            self.assertEqual(settings.get("INFOPLIST_FILE"), "calorietracker/Info.plist", name)
        with (ios_release.PBXPROJ.parents[1] / "calorietracker" / "Info.plist").open("rb") as handle:
            self.assertIs(plistlib.load(handle)[ios_release.ENCRYPTION_KEY], False)

    def test_no_from_the_info_plist_or_every_configuration_passes(self) -> None:
        self.plist({"ITSAppUsesNonExemptEncryption": False})
        self.assertEqual(self.check(self.both(self.APP_PLIST)), "NO")
        self.assertEqual(self.check(self.both({**self.GENERATED, self.KEY: "NO"})), "NO")
        self.assertEqual(self.check(self.both({**self.APP_PLIST, self.KEY: "NO"})), "NO")
        # Inherited from the project-level configurations.
        self.assertEqual(self.check(self.both(self.GENERATED), project=self.both({self.KEY: "NO"})), "NO")
        self.assertEqual(self.check(self.both({"INFOPLIST_FILE": "\"$(SRCROOT)/calorietracker/Info.plist\""})), "NO")

    def test_a_configuration_without_the_declaration_fails(self) -> None:
        debug_only = {"Debug": {**self.GENERATED, self.KEY: "NO"}, "Release": dict(self.GENERATED)}
        with self.assertRaisesRegex(ReleaseError, "Release configuration does not declare export compliance"):
            self.check(debug_only)
        self.plist({})
        with self.assertRaisesRegex(ReleaseError, "does not declare export compliance"):
            self.check(self.both(self.APP_PLIST))
        # INFOPLIST_KEY_ settings only reach the Info.plist when Xcode generates it.
        with self.assertRaisesRegex(ReleaseError, "does not declare export compliance"):
            self.check(self.both({"GENERATE_INFOPLIST_FILE": "NO", self.KEY: "NO"}))

    def test_other_targets_do_not_count(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "does not declare export compliance"):
            self.check(self.both(self.GENERATED), other=self.both({**self.GENERATED, self.KEY: "NO"}))
        self.assertEqual(self.check(self.both({**self.GENERATED, self.KEY: "NO"}),
                                    other=self.both({**self.GENERATED, self.KEY: "maybe"})), "NO")

    def test_yes_needs_the_compliance_code(self) -> None:
        yes = {**self.GENERATED, self.KEY: "YES"}
        with self.assertRaisesRegex(ReleaseError, "needs ITSEncryptionExportComplianceCode"):
            self.check(self.both(yes))
        self.assertEqual(self.check(self.both({**yes, **self.CODE})), "YES")
        self.plist({"ITSAppUsesNonExemptEncryption": True, "ITSEncryptionExportComplianceCode": " "})
        with self.assertRaisesRegex(ReleaseError, "needs ITSEncryptionExportComplianceCode"):
            self.check(self.both(self.APP_PLIST))
        self.plist({"ITSAppUsesNonExemptEncryption": True, "ITSEncryptionExportComplianceCode": "ABC123"})
        self.assertEqual(self.check(self.both(self.APP_PLIST)), "YES")

    def test_mixed_unknown_or_non_boolean_values_fail(self) -> None:
        cases = [
            (self.both({**self.GENERATED, self.KEY: "maybe"}), None),
            (self.both({**self.GENERATED, self.KEY: "NO", f'"{self.KEY}[sdk=iphoneos*]"': "YES", **self.CODE}), None),
            (self.both(self.APP_PLIST), {"ITSAppUsesNonExemptEncryption": "NO"}),
            (self.both(self.APP_PLIST), {"ITSAppUsesNonExemptEncryption": "$(ENCRYPTION)"}),
            (self.both({**self.APP_PLIST, self.KEY: "NO"}),
             {"ITSAppUsesNonExemptEncryption": True, "ITSEncryptionExportComplianceCode": "X"}),
        ]
        for app, plist in cases:
            if plist is not None:
                self.plist(plist)
            with self.subTest(app=app, plist=plist), self.assertRaisesRegex(ReleaseError, "must be NO or YES"):
                self.check(app)
        split = {"Debug": {**self.GENERATED, self.KEY: "NO"}, "Release": {**self.GENERATED, self.KEY: "YES", **self.CODE}}
        with self.assertRaisesRegex(ReleaseError, "same in every calorietracker configuration"):
            self.check(split)

    def test_unreadable_project_inputs_fail(self) -> None:
        with self.assertRaisesRegex(ReleaseError, "cannot read"):
            self.check(self.both({"INFOPLIST_FILE": "calorietracker/Missing.plist"}))
        with self.assertRaisesRegex(ReleaseError, "cannot resolve INFOPLIST_FILE"):
            self.check(self.both({"INFOPLIST_FILE": "$(OTHER_DIR)/Info.plist"}))
        with self.assertRaisesRegex(ReleaseError, "expected one 'Missing' target"):
            ios_release.check_export_compliance(self.project(self.both(self.GENERATED)), target="Missing")
        with self.assertRaisesRegex(ReleaseError, "no build configurations"):
            self.check({})

    def test_archived_info_plist_is_checked_the_same_way(self) -> None:
        check = ios_release.check_archived_export_compliance
        self.assertEqual(check(self.plist({"ITSAppUsesNonExemptEncryption": False}, binary=True)), "NO")
        self.assertEqual(check(self.plist({"ITSAppUsesNonExemptEncryption": True,
                                           "ITSEncryptionExportComplianceCode": "ABC123"}, binary=True)), "YES")
        with self.assertRaisesRegex(ReleaseError, "archived app does not declare"):
            check(self.plist({}, binary=True))
        with self.assertRaisesRegex(ReleaseError, "needs ITSEncryptionExportComplianceCode"):
            check(self.plist({"ITSAppUsesNonExemptEncryption": True}, binary=True))
        broken = self.root / "Broken.plist"
        broken.write_bytes(b"not a plist")
        with self.assertRaisesRegex(ReleaseError, "cannot read"):
            check(broken)
        with self.assertRaisesRegex(ReleaseError, "cannot read"):
            check(self.root / "no-such-dir" / "Info.plist")

    def test_export_compliance_command_exit_codes(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            ios_release.main(["export-compliance", "--info-plist",
                              str(self.plist({"ITSAppUsesNonExemptEncryption": False}, binary=True))])
        self.assertIn("ITSAppUsesNonExemptEncryption = NO", out.getvalue())
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(err), self.assertRaises(SystemExit) as exit_:
            ios_release.main(["export-compliance", "--info-plist", str(self.plist({}, binary=True))])
        self.assertEqual(exit_.exception.code, 1)
        self.assertIn("does not declare export compliance", err.getvalue())

    def test_gates_check_it_only_when_this_run_builds(self) -> None:
        cases = (
            ({"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF_NAME": "main"}, True),
            ({"GITHUB_EVENT_NAME": "push", "GITHUB_REF_NAME": TAG,
              "IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_BUILD": "true"}, True),
            ({"GITHUB_EVENT_NAME": "push", "GITHUB_REF_NAME": TAG,
              "IOS_RELEASE_AUTOMATION": "true", "IOS_UPLOAD_LISTING": "true"}, False),
            ({"GITHUB_EVENT_NAME": "push", "GITHUB_REF_NAME": TAG}, False),
        )
        for env, builds in cases:
            missing = mock.patch.object(ios_release, "check_export_compliance",
                                        side_effect=ReleaseError("the app does not declare export compliance"))
            with self.subTest(env=env), missing as check, \
                    mock.patch.object(ios_release, "single_project_value", return_value=VERSION), \
                    mock.patch.dict(os.environ, env, clear=True), redirect_stdout(io.StringIO()), \
                    redirect_stderr(io.StringIO()) as err:
                if builds:
                    with self.assertRaises(SystemExit):
                        ios_release.main(["gates"])
                    self.assertIn("export compliance", err.getvalue())
                else:
                    ios_release.main(["gates"])
                    check.assert_not_called()


class BuildNumberTests(unittest.TestCase):
    def test_next_build_number(self) -> None:
        self.assertEqual(ios_release.next_build_number(39, ["13", "35", "12"]), 39)
        self.assertEqual(ios_release.next_build_number(39, ["13", "39"]), 40)
        self.assertEqual(ios_release.next_build_number(1, []), 1)
        self.assertEqual(ios_release.next_build_number(5, ["7.1", "abc", "9"]), 10)
        self.assertEqual(ios_release.next_build_number(5, ["٩٩"]), 5)  # only ASCII digits count


APP = asc_release.ASC_APP_ID
BUNDLE = asc_release.DEFAULT_BUNDLE_ID
STARTED = 1_800_000_000.0  # this run's upload start (epoch seconds)


def iso(epoch: float) -> str:
    import datetime as dt

    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat()


def build_row(
    build_id: str = "B1",
    *,
    number: str = "40",
    state: str = "VALID",
    expired: bool = False,
    uploaded: float | None = STARTED + 60,
    uploaded_raw: object = None,
    app: str = APP,
    pre: str = "P1",
) -> dict:
    attributes = {"version": number, "processingState": state, "expired": expired}
    if uploaded_raw is not None:
        attributes["uploadedDate"] = uploaded_raw
    elif uploaded is not None:
        attributes["uploadedDate"] = iso(uploaded)
    return {
        "type": "builds",
        "id": build_id,
        "attributes": attributes,
        "relationships": {
            "preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": pre}},
            "app": {"data": {"type": "apps", "id": app}},
        },
    }


def pre_row(pre_id: str = "P1", version: str = VERSION, platform: str = "IOS") -> dict:
    return {"type": "preReleaseVersions", "id": pre_id, "attributes": {"version": version, "platform": platform}}


def png_header(color_type: int, *, trns: bool = False) -> bytes:
    """A PNG signature and IHDR (plus an optional tRNS chunk) with the given colour type."""
    import zlib

    def chunk(kind: bytes, body: bytes) -> bytes:
        return len(body).to_bytes(4, "big") + kind + body + zlib.crc32(kind + body).to_bytes(4, "big")

    ihdr = (16).to_bytes(4, "big") + (16).to_bytes(4, "big") + bytes([8, color_type, 0, 0, 0])
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + (chunk(b"tRNS", b"\x00\x00") if trns else b"") + chunk(b"IDAT", b"x")


def asc_error(code: int) -> asc_cli.AscError:
    return asc_cli.AscError(("builds", "list"), code, "failed")


class FakeClock:
    def __init__(self, start: float) -> None:
        self.time = start
        self.sleeps: list[float] = []

    def now(self) -> float:
        return self.time

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.time += seconds


class SequenceAsc:
    """Returns queued `asc builds list` payloads (or raises queued exceptions) per call."""

    def __init__(self, responses: list) -> None:
        self.responses = list(responses)
        self.calls: list[tuple[str, ...]] = []

    def run(self, *args: str, **_: object) -> dict:
        self.calls.append(args)
        item = self.responses.pop(0) if len(self.responses) > 1 else self.responses[0]
        if isinstance(item, BaseException):
            raise item
        return item


def wait(client: SequenceAsc, clock: FakeClock, *, minutes: int = 120, transient=None) -> dict:
    with redirect_stdout(io.StringIO()):
        return ios_release.wait_for_build(
            client,
            app_id=APP,
            marketing_version=VERSION,
            build_number="40",
            uploaded_after=STARTED,
            deadline=STARTED + minutes * 60,
            poll_seconds=30,
            now=clock.now,
            sleep=clock.sleep,
            is_transient=transient,
        )


def quiet(fn, *args, **kwargs):
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        return fn(*args, **kwargs)


class WaitForBuildTests(unittest.TestCase):
    def test_waits_through_missing_and_processing_then_returns_build(self) -> None:
        client = SequenceAsc(
            [
                {"data": []},
                {"data": [build_row(state="PROCESSING")], "included": [pre_row()]},
                {"data": [build_row()], "included": [pre_row()]},
            ]
        )
        clock = FakeClock(STARTED + 120)
        build = wait(client, clock)
        self.assertEqual(build["id"], "B1")
        self.assertEqual(clock.sleeps, [30, 30])
        query = client.calls[0]
        self.assertEqual(query[:2], ("builds", "list"))
        self.assertEqual(query[query.index("--app") + 1], APP)
        self.assertEqual(query[query.index("--build-number") + 1], "40")
        self.assertIn("preReleaseVersion,app", query)

    def test_times_out_without_using_another_build(self) -> None:
        client = SequenceAsc([{"data": [build_row(state="PROCESSING")], "included": [pre_row()]}])
        clock = FakeClock(STARTED)
        with self.assertRaisesRegex(ReleaseError, "timed out"):
            wait(client, clock, minutes=10)
        self.assertLessEqual(clock.time, STARTED + 10 * 60 + 30)

    def test_ready_build_after_the_deadline_is_still_a_timeout(self) -> None:
        client = SequenceAsc([{"data": [build_row()], "included": [pre_row()]}])
        clock = FakeClock(STARTED + 121 * 60)  # job started after the 120-minute budget
        with self.assertRaisesRegex(ReleaseError, "timed out"):
            wait(client, clock)
        self.assertEqual(client.calls, [], "must not poll once the budget is spent")

    def test_processing_failure_stops(self) -> None:
        for state in ("FAILED", "INVALID"):
            client = SequenceAsc([{"data": [build_row(state=state)], "included": [pre_row()]}])
            with self.subTest(state=state), self.assertRaisesRegex(ReleaseError, state):
                wait(client, FakeClock(STARTED))

    def test_expired_build_is_rejected(self) -> None:
        client = SequenceAsc([{"data": [build_row(expired=True)], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "expired"):
            wait(client, FakeClock(STARTED))

    def test_ambiguous_match_stops(self) -> None:
        client = SequenceAsc([{"data": [build_row("B1"), build_row("B2")], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "ambiguous"):
            wait(client, FakeClock(STARTED))

    def test_older_upload_is_never_substituted(self) -> None:
        old = build_row(uploaded=STARTED - 3600)
        client = SequenceAsc([{"data": [old], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "older build"):
            wait(client, FakeClock(STARTED))

    def test_build_without_an_upload_time_is_never_ready(self) -> None:
        # Fail closed: a VALID build that cannot be proven to be this run's upload
        # keeps the wait going until the deadline instead of passing the check.
        for missing in (None, ""):
            client = SequenceAsc([{"data": [build_row(uploaded=None, uploaded_raw=missing)], "included": [pre_row()]}])
            with self.subTest(missing=missing), self.assertRaisesRegex(ReleaseError, "timed out"):
                wait(client, FakeClock(STARTED), minutes=10)
        state, message, build = ios_release.evaluate_builds(
            {"data": [build_row(uploaded=None)], "included": [pre_row()]},
            app_id=APP, marketing_version=VERSION, build_number="40", uploaded_after=STARTED,
        )
        self.assertEqual((state, build), (ios_release.BuildState.WAITING, None))
        self.assertIn("upload time", message)

    def test_unreadable_upload_time_stops(self) -> None:
        for raw in ("yesterday", 1_800_000_060):
            client = SequenceAsc([{"data": [build_row(uploaded_raw=raw)], "included": [pre_row()]}])
            with self.subTest(raw=raw), self.assertRaisesRegex(ReleaseError, "unreadable uploadedDate"):
                wait(client, FakeClock(STARTED))

    def test_other_versions_and_platforms_are_ignored(self) -> None:
        other_version = build_row("BX", pre="P2")
        other_platform = build_row("BY", pre="P3")
        client = SequenceAsc(
            [
                {"data": [other_version, other_platform], "included": [pre_row("P2", "7.1"), pre_row("P3", VERSION, "MAC_OS")]},
                {"data": [other_version, build_row("B1")], "included": [pre_row("P2", "7.1"), pre_row()]},
            ]
        )
        self.assertEqual(wait(client, FakeClock(STARTED))["id"], "B1")

    def test_build_from_another_app_is_a_mismatch(self) -> None:
        client = SequenceAsc([{"data": [build_row(app="OTHER")], "included": [pre_row()]}])
        with self.assertRaisesRegex(ReleaseError, "another app"):
            wait(client, FakeClock(STARTED))

    def test_transient_errors_are_retried_and_others_raise(self) -> None:
        client = SequenceAsc([asc_error(63), {"data": [build_row()], "included": [pre_row()]}])
        with redirect_stderr(io.StringIO()):
            build = wait(client, FakeClock(STARTED), transient=ios_release.is_transient_error)
        self.assertEqual(build["id"], "B1")
        fatal = SequenceAsc([asc_error(3)])
        with self.assertRaises(asc_cli.AscError):
            wait(fatal, FakeClock(STARTED), transient=ios_release.is_transient_error)


class TransientErrorTests(unittest.TestCase):
    def test_retry_rule_follows_asc_exit_codes(self) -> None:
        # 408, 429, any 5xx and a call that ran out of time are retried.
        for code in (18, 39, 60, 62, 63, 99, 124):
            with self.subTest(code=code):
                self.assertTrue(ios_release.is_transient_error(asc_error(code)))
        # Generic, usage, auth, not found, conflict, read-only refusal, 4xx.
        for code in (1, 2, 3, 4, 5, 6, 10, 32, 127):
            with self.subTest(code=code):
                self.assertFalse(ios_release.is_transient_error(asc_error(code)))
        for exc in (ValueError("bad"), ReleaseError("mismatch"), SystemExit(1)):
            with self.subTest(exc=repr(exc)):
                self.assertFalse(ios_release.is_transient_error(exc))

    def test_network_drops_reported_as_exit_1_are_retried(self) -> None:
        for detail in ('Get "https://api.appstoreconnect.apple.com/v1/builds": read tcp: connection reset by peer',
                       "dial tcp: lookup api.appstoreconnect.apple.com: no such host",
                       "net/http: TLS handshake timeout", "unexpected EOF"):
            with self.subTest(detail=detail):
                self.assertTrue(ios_release.is_transient_error(asc_cli.AscError(("builds", "list"), 1, detail)))
        for detail in ("invalid character '<' looking for beginning of value", "build not found"):
            with self.subTest(detail=detail):
                self.assertFalse(ios_release.is_transient_error(asc_cli.AscError(("builds", "list"), 1, detail)))


class AscRunnerTests(unittest.TestCase):
    ENV = {
        "APP_STORE_CONNECT_API_KEY_ID": "TESTKEY0001",
        "APP_STORE_CONNECT_ISSUER_ID": "00000000-test-4000-8000-issuer000001",
        "APP_STORE_CONNECT_API_KEY_P8": "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----",
        "ASC_PROFILE": "personal",
        "ASC_CONFIG_PATH": "/home/me/.asc/config.json",
    }

    def run_once(self, *, returncode: int = 0, stdout: str = '{"data": []}', stderr: str = "", read_only=False, env=None):
        seen: dict = {}

        def runner(argv, **kwargs):
            seen["argv"], seen["env"] = argv, kwargs["env"]
            return mock.Mock(returncode=returncode, stdout=stdout, stderr=stderr)

        with mock.patch.dict(os.environ, env or self.ENV, clear=True):
            result = asc_cli.Asc(binary="asc", read_only=read_only, runner=runner).run("apps", "view", "--id", APP)
        return result, seen

    def test_credentials_come_from_the_release_secrets_and_nothing_else(self) -> None:
        result, seen = self.run_once()
        self.assertEqual(result, {"data": []})
        self.assertEqual(seen["argv"], ["asc", "apps", "view", "--id", APP, "--output", "json"])
        env = seen["env"]
        self.assertEqual(env["ASC_KEY_ID"], "TESTKEY0001")
        self.assertEqual(env["ASC_ISSUER_ID"], self.ENV["APP_STORE_CONNECT_ISSUER_ID"])
        self.assertIn("\nabc\n", env["ASC_PRIVATE_KEY"])
        for name in ("ASC_PROFILE", "ASC_CONFIG_PATH"):
            self.assertNotIn(name, env)
        for name, value in (("ASC_BYPASS_KEYCHAIN", "1"), ("ASC_TELEMETRY_DISABLED", "1"), ("DO_NOT_TRACK", "1"),
                            ("ASC_SKILLS_AUTO_CHECK", "0"), ("ASC_STRICT_AUTH", "1"), ("ASC_MAX_RETRIES", "5")):
            self.assertEqual(env[name], value, name)
        self.assertNotIn("ASC_READ_ONLY", env)

    def test_read_only_from_the_caller_or_the_job(self) -> None:
        _, seen = self.run_once(read_only=True)
        self.assertEqual(seen["env"]["ASC_READ_ONLY"], "1")
        _, seen = self.run_once(env={**self.ENV, "ASC_READ_ONLY": "1"})
        self.assertEqual(seen["env"]["ASC_READ_ONLY"], "1")

    def test_failures_keep_the_exit_code_and_hide_the_ids(self) -> None:
        stderr = f"401 for key {self.ENV['APP_STORE_CONNECT_API_KEY_ID']} issuer {self.ENV['APP_STORE_CONNECT_ISSUER_ID']}"
        with self.assertRaises(asc_cli.AscError) as caught:
            self.run_once(returncode=3, stderr=stderr)
        self.assertEqual(caught.exception.exit_code, 3)
        self.assertNotIn("TESTKEY0001", str(caught.exception))
        self.assertNotIn("issuer000001", str(caught.exception))
        with self.assertRaises(asc_cli.AscError):
            self.run_once(stdout="not json")

    def test_install_accepts_only_the_pinned_binary(self) -> None:
        good = b"pinned-binary"
        with mock.patch.dict(asc_cli.ASC_SHA256, {"linux_amd64": hashlib.sha256(good).hexdigest()}):
            with tempfile.TemporaryDirectory() as tmp:
                opener = lambda url, timeout: io.BytesIO(good)  # noqa: E731
                target = quiet(asc_cli.install, Path(tmp), key="linux_amd64", opener=opener)
                self.assertEqual(target.read_bytes(), good)
                self.assertTrue(os.access(target, os.X_OK))
                bad = lambda url, timeout: io.BytesIO(b"tampered")  # noqa: E731
                with self.assertRaises(SystemExit):
                    quiet(asc_cli.install, Path(tmp) / "other", key="linux_amd64", opener=bad)
                self.assertFalse((Path(tmp) / "other" / "asc").exists())

    def test_the_pin_is_one_exact_release_with_both_ci_platforms(self) -> None:
        self.assertRegex(asc_cli.ASC_VERSION, r"^[0-9]+\.[0-9]+\.[0-9]+$")
        self.assertEqual(set(asc_cli.ASC_SHA256), {"linux_amd64", "macOS_arm64"})
        for digest in asc_cli.ASC_SHA256.values():
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
        self.assertEqual(asc_cli.platform_key("Linux", "x86_64"), "linux_amd64")
        self.assertEqual(asc_cli.platform_key("Darwin", "arm64"), "macOS_arm64")
        with self.assertRaises(SystemExit):
            asc_cli.platform_key("Windows", "x86_64")

    def test_only_the_pinned_binary_receives_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "asc"
            binary.write_bytes(b"pinned-binary")
            pinned = {asc_cli.platform_key(): hashlib.sha256(b"pinned-binary").hexdigest()}
            with mock.patch.dict(asc_cli.ASC_SHA256, pinned), mock.patch.object(asc_cli.shutil, "which", return_value=str(binary)):
                self.assertEqual(asc_cli.verified_binary("asc"), str(binary))
                binary.write_bytes(b"something else")
                with self.assertRaises(asc_cli.AscError) as caught:
                    asc_cli.verified_binary("asc")
                self.assertEqual(caught.exception.exit_code, 126)
                # A real run checks the binary before anything is executed.
                with mock.patch.object(asc_cli.subprocess, "run") as run, self.assertRaises(asc_cli.AscError):
                    asc_cli.Asc().run("apps", "view", "--id", APP)
                run.assert_not_called()
            with mock.patch.object(asc_cli.shutil, "which", return_value=None), self.assertRaises(asc_cli.AscError):
                asc_cli.verified_binary("asc")
        # No environment variable can point the release at another executable.
        with mock.patch.dict(os.environ, {"ASC_BIN": "/tmp/evil"}):
            self.assertEqual(asc_cli.Asc().binary, "asc")

    def test_alpha_is_detected_the_way_asc_refuses_it(self) -> None:
        cases = {"rgb": (png_header(2), False), "rgba": (png_header(6), True), "gray-alpha": (png_header(4), True),
                 "rgb-trns": (png_header(2, trns=True), True), "jpeg": (b"\xff\xd8\xff\xe0rest", False)}
        with tempfile.TemporaryDirectory() as tmp:
            for name, (content, expected) in cases.items():
                path = Path(tmp) / name
                path.write_bytes(content)
                with self.subTest(name=name):
                    self.assertEqual(asc_cli.image_has_alpha(path), expected)

    def test_a_leading_at_sign_is_escaped(self) -> None:
        self.assertEqual(asc_release.asc_value("@apoorvdarshan on X"), "@@apoorvdarshan on X")
        self.assertEqual(asc_release.asc_value("Track food"), "Track food")


MUTATIONS = {
    ("versions", "create"), ("versions", "update"), ("versions", "attach-build"), ("localizations", "update"),
    ("screenshots", "upload"), ("asset-library", "images", "upload"), ("localizations", "placements", "create"),
    ("localizations", "placements", "swap"), ("review", "submissions-create"), ("review", "items-add"),
    ("review", "submissions-submit"),
}


def is_write(call: tuple[str, ...]) -> bool:
    return call[:2] in MUTATIONS or call[:3] in MUTATIONS


def flag(call: tuple[str, ...], name: str) -> str:
    return call[call.index(name) + 1]


class FakeAsc:
    """A stateful App Store Connect behind `asc`, for asc_release (no network)."""

    def __init__(
        self,
        *,
        state: str = "PREPARE_FOR_SUBMISSION",
        attached: str | None = "OLD",
        revert_after_select: bool = False,
        live_text: dict | None = None,
        live_shots: list[dict] | None = None,
        versions: list[dict] | None = None,
        bundle: str = BUNDLE,
        subscriptions: list[dict] | None = None,
        iaps: list[dict] | None = None,
        drafts: list[str] | None = None,
        draft_items: dict[str, list[dict]] | None = None,
        library: list[dict] | None = None,
        placements: list[dict] | None = None,
        refuse_items: set[str] | None = None,
        listed_after_create: bool = True,
    ) -> None:
        self.state = state
        self.attached = attached
        self.revert_after_select = revert_after_select
        self.live_text = dict(live_text or {})
        self.live_shots = live_shots
        self.versions = versions if versions is not None else [
            {"id": "V1", "attributes": {"versionString": VERSION, "appStoreState": state}}
        ]
        self.bundle = bundle
        self.subscriptions = subscriptions or []
        self.iaps = iaps or []
        self.drafts = list(drafts or [])
        self.items = {k: list(v) for k, v in (draft_items or {}).items()}
        self.library = list(library or [])
        self.placements = list(placements or [])
        self.refuse_items = refuse_items or set()
        self.listed_after_create = listed_after_create
        self.uploaded_sets: list[str] = []
        self.created_versions: list[str] = []
        self.calls: list[tuple[str, ...]] = []
        self.version_views = 0

    def run(self, *args: str, **_: object):
        self.calls.append(args)
        head = args[:3] if args[:3] in MUTATIONS or args[:2] in {("localizations", "placements"), ("asset-library", "images")} else args[:2]
        if head == ("apps", "view"):
            return {"data": {"type": "apps", "id": flag(args, "--id"), "attributes": {"bundleId": self.bundle}}}
        if head == ("versions", "list"):
            return {"data": self.versions}
        if head == ("versions", "create"):
            self.created_versions.append(flag(args, "--version"))
            if self.listed_after_create:
                self.versions.append({"id": "NEW", "attributes": {"versionString": flag(args, "--version"),
                                                                  "appStoreState": "PREPARE_FOR_SUBMISSION"}})
            return {"data": {"id": "NEW"}}
        if head == ("versions", "view"):
            self.version_views += 1
            build = self.attached
            if self.revert_after_select and self.version_views >= 2:
                build = "OLD"
            rel = {"build": {"data": {"type": "builds", "id": build} if build else None}}
            return {"data": {"id": flag(args, "--version-id"), "relationships": rel}}
        if head == ("versions", "attach-build"):
            self.attached = flag(args, "--build-id")
            return {"data": {}}
        if head == ("versions", "update"):
            return {"data": {}}
        if head == ("builds", "list"):
            return {"data": [build_row("B9")], "included": [pre_row()]}
        if head == ("localizations", "list"):
            return {"data": [{"id": "LOC1", "attributes": {"locale": flag(args, "--locale"), **self.live_text}}]}
        if head == ("localizations", "update"):
            return {"data": {}}
        if head == ("screenshots", "list"):
            if self.live_shots is None:
                return {"sets": []}
            return {"sets": [
                {"set": {"attributes": {"screenshotDisplayType": display}},
                 "screenshots": [{"attributes": shot} for shot in self.live_shots]}
                for _, display, _, _ in asc_release.SCREENSHOT_SETS
            ]}
        if head == ("screenshots", "upload"):
            self.uploaded_sets.append(flag(args, "--device-type"))
            # Upload makes the set hold exactly the files in --path.
            folder = Path(flag(args, "--path"))
            self.live_shots = [
                {"fileName": p.name, "fileSize": p.stat().st_size,
                 "sourceFileChecksum": hashlib.md5(p.read_bytes()).hexdigest()}
                for p in sorted(folder.glob("*.png"))
            ]
            return {}
        if head == ("asset-library", "view"):
            return {"data": {"id": "LIB1"}}
        if head == ("asset-library", "images", "list"):
            return {"data": self.library}
        if head == ("asset-library", "images", "upload"):
            path = Path(flag(args, "--file"))
            image_id = f"IMG{len(self.library) + 1}"
            self.library.append({"id": image_id, "attributes": {"fileName": path.name, "fileSize": path.stat().st_size,
                                                                "state": "PREPARE_FOR_SUBMISSION", "createdDate": "z"}})
            return {"imageId": image_id, "ready": True, "state": "PREPARE_FOR_SUBMISSION"}
        if head == ("localizations", "placements", "list"):
            wanted = flag(args, "--placement-type")
            return {"data": [p for p in self.placements if p["attributes"]["placementType"] == wanted]}
        if head in {("localizations", "placements", "create"), ("localizations", "placements", "swap")}:
            self.placements = [p for p in self.placements if p["attributes"]["placementType"] != flag(args, "--placement-type")]
            self.placements.append({"id": "PL-new", "attributes": {"placementType": flag(args, "--placement-type")},
                                    "relationships": {"image": {"data": {"id": flag(args, "--image-id")}}}})
            return {"data": {}}
        if head == ("review", "submissions-list"):
            return {"data": [{"id": d} for d in self.drafts]}
        if head == ("review", "submissions-create"):
            new = f"SUB{len(self.drafts) + 1}"
            self.drafts.append(new)
            return {"data": {"id": new}}
        if head == ("review", "items-list"):
            return {"data": self.items.get(flag(args, "--submission"), [])}
        if head == ("review", "items-add"):
            item_type, item_id = flag(args, "--item-type"), flag(args, "--item-id")
            if item_id in self.refuse_items:
                raise asc_cli.AscError(args, 5, "conflict")
            relation = {"appStoreVersions": "appStoreVersion", "subscriptionVersions": "subscriptionVersion",
                        "inAppPurchaseVersions": "inAppPurchaseVersion",
                        "appAssetLibraryImages": "appAssetLibraryImage"}[item_type]
            held = self.items.setdefault(flag(args, "--submission"), [])
            if any(related == item_id for item in held
                   for related in [((item.get("relationships") or {}).get(relation) or {}).get("data", {}).get("id")]):
                if flag(args, "--if-exists") != "skip":
                    raise asc_cli.AscError(args, 5, "already on the submission")
                return {"data": {}}
            held.append({"id": f"ITEM-{item_id}", "relationships": {relation: {"data": {"id": item_id}}}})
            return {"data": {}}
        if head == ("review", "submissions-submit"):
            return {"data": {}}
        if head == ("subscriptions", "list"):
            return {"data": self.subscriptions}
        if args[:3] == ("subscriptions", "versions", "list"):
            return {"data": [{"id": f"{flag(args, '--subscription-id')}v2", "attributes": {"version": 2}},
                             {"id": f"{flag(args, '--subscription-id')}v1", "attributes": {"version": 1}}]}
        if head == ("iap", "list"):
            return {"data": self.iaps}
        if args[:3] == ("iap", "versions", "list"):
            return {"data": [{"id": f"{flag(args, '--iap-id')}v1", "attributes": {"version": 1}}]}
        raise AssertionError(f"unexpected asc call {args}")

    def writes(self) -> list[tuple[str, ...]]:
        return [c for c in self.calls if is_write(c)]


def run_main(fake: FakeAsc, env: dict[str, str], argv: list[str]) -> int:
    full_env = {k: v for k, v in os.environ.items() if k not in {
        "UPLOAD_LISTING", "UPLOAD_WHATS_NEW", "UPLOAD_SCREENSHOTS", "UPLOAD_CREATIVE_ASSETS", "SUBMIT_IOS_REVIEW",
        "PUBLIC_RELEASE", "CREATE_IOS_VERSION"}}
    full_env.update(env)
    code = 0
    with mock.patch.dict(os.environ, full_env, clear=True), mock.patch.object(sys, "argv", ["asc_release.py", *argv]), \
            mock.patch.object(asc_release, "asc_from_environment", return_value=fake), \
            mock.patch.object(asc_release, "intended_product_ids", return_value=PRODUCT_IDS), \
            redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        try:
            asc_release.main()
        except SystemExit as exc:
            code = exc.code if isinstance(exc.code, int) else 1
    return code


PRODUCT = "com.apoorvdarshan.calorietracker.plus.monthly"
CREDITS = "com.apoorvdarshan.calorietracker.credits.50"
PRODUCT_IDS = {PRODUCT, CREDITS}
SUBMIT = {"SUBMIT_IOS_REVIEW": "true"}
SUBMIT_ARGS = ["--version", VERSION, "--build-id", "B9", "--build-number", "40"]


class BuildSelectionTests(unittest.TestCase):
    def test_selects_and_reads_back_this_runs_build(self) -> None:
        fake = FakeAsc()
        quiet(asc_release.select_build, fake, "V1", "B9", VERSION, "40")
        self.assertEqual(fake.attached, "B9")
        names = [c[:2] for c in fake.calls]
        self.assertEqual(names, [("builds", "list"), ("versions", "attach-build"), ("versions", "view")])

    def test_selection_that_does_not_stick_fails(self) -> None:
        fake = FakeAsc(revert_after_select=True)
        quiet(asc_release.confirm_selected_build, fake, "V1", "OLD")
        with self.assertRaises(SystemExit):
            quiet(asc_release.select_build, fake, "V1", "B9", VERSION, "40")

    def test_unprocessed_expired_or_wrong_build_is_refused(self) -> None:
        cases = {
            "processing": ([build_row("B9", state="PROCESSING")], [pre_row()]),
            "expired": ([build_row("B9", expired=True)], [pre_row()]),
            "number": ([build_row("B9", number="41")], [pre_row()]),
            "version": ([build_row("B9")], [pre_row(version="7.1")]),
            "missing": ([build_row("B8")], [pre_row()]),
        }
        for label, (builds, included) in cases.items():
            fake = FakeAsc()
            fake_run = fake.run
            fake.run = lambda *a, _b=builds, _i=included, _r=fake_run, **k: (  # type: ignore[method-assign]
                {"data": _b, "included": _i} if a[:2] == ("builds", "list") else _r(*a, **k))
            with self.subTest(label), self.assertRaises(SystemExit):
                quiet(asc_release.select_build, fake, "V1", "B9", VERSION, "40")
            self.assertEqual(fake.attached, "OLD", label)

    def test_release_type(self) -> None:
        for public, expected in ((True, "AFTER_APPROVAL"), (False, "MANUAL")):
            fake = FakeAsc()
            quiet(asc_release.set_release_type, fake, "V1", public_release=public)
            self.assertEqual(flag(fake.calls[-1], "--release-type"), expected)


class MainArgumentTests(unittest.TestCase):
    def run_cli(self, env: dict[str, str], *args: str) -> tuple[int, str]:
        out = io.StringIO()
        full_env = {k: v for k, v in os.environ.items() if k not in {
            "UPLOAD_LISTING", "UPLOAD_WHATS_NEW", "UPLOAD_SCREENSHOTS", "UPLOAD_CREATIVE_ASSETS", "SUBMIT_IOS_REVIEW",
            "PUBLIC_RELEASE"}}
        full_env.update(env)
        with mock.patch.dict(os.environ, full_env, clear=True), mock.patch.object(
            sys, "argv", ["asc_release.py", "--dry-run", *args]
        ), redirect_stdout(out), redirect_stderr(out):
            try:
                asc_release.main()
            except SystemExit as exc:
                return (exc.code if isinstance(exc.code, int) else 1), out.getvalue()
        return 0, out.getvalue()

    def test_everything_off_is_a_no_op(self) -> None:
        code, output = self.run_cli({})
        self.assertEqual(code, 0)
        self.assertIn("skipped", output)

    def test_submit_without_this_runs_build_fails(self) -> None:
        code, output = self.run_cli({"SUBMIT_IOS_REVIEW": "true"})
        self.assertEqual(code, 1)
        self.assertIn("--build-id", output)

    def test_dry_run_submit_runs_the_offline_self_check(self) -> None:
        code, output = self.run_cli({"SUBMIT_IOS_REVIEW": "true"}, "--build-id", "B", "--build-number", "1")
        self.assertEqual(code, 0, output)
        self.assertIn("self-check: product submission selection OK", output)

    def test_public_release_without_submit_fails(self) -> None:
        code, _ = self.run_cli({"UPLOAD_LISTING": "true", "PUBLIC_RELEASE": "true"})
        self.assertEqual(code, 1)

    def test_only_the_fud_ai_bundle_is_supported(self) -> None:
        code, output = self.run_cli({"UPLOAD_LISTING": "true"}, "--bundle-id", "com.example.other")
        self.assertEqual(code, 1)
        self.assertIn("Fud AI iOS bundle", output)

    def test_whats_new_requires_text(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "ios" / "en-US").mkdir(parents=True)
            code, output = self.run_cli({"UPLOAD_WHATS_NEW": "true"}, "--metadata-dir", tmp)
            self.assertEqual(code, 1)
            self.assertIn("whats_new.txt", output)
            (Path(tmp) / "ios" / "en-US" / "whats_new.txt").write_text("Fixes\n")
            code, output = self.run_cli({"UPLOAD_WHATS_NEW": "true"}, "--metadata-dir", tmp)
            self.assertEqual(code, 0, output)

    def test_creative_assets_need_an_image(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            code, output = self.run_cli({"UPLOAD_CREATIVE_ASSETS": "true"}, "--creative-dir", tmp)
            self.assertEqual(code, 1)
            self.assertIn("no header or search results image", output)
            (Path(tmp) / "header").mkdir()
            (Path(tmp) / "header" / "a.png").write_bytes(b"x")
            (Path(tmp) / "header" / "b.png").write_bytes(b"y")
            code, output = self.run_cli({"UPLOAD_CREATIVE_ASSETS": "true"}, "--creative-dir", tmp)
            self.assertEqual(code, 1)
            self.assertIn("takes one image", output)
            (Path(tmp) / "header" / "b.png").unlink()
            code, output = self.run_cli({"UPLOAD_CREATIVE_ASSETS": "true"}, "--creative-dir", tmp)
            self.assertEqual(code, 0, output)

    def test_the_repository_creative_assets_are_valid(self) -> None:
        sources = asc_release.creative_sources(asc_release.ROOT / "store" / "creative" / "ios")
        self.assertEqual([placement for placement, _, _ in sources],
                         ["PRODUCT_PAGE_HEADER_ASSET", "APP_STORE_SEARCH_RESULTS_ASSET"])

    def test_listing_excludes_whats_new_unless_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            loc = Path(tmp) / "ios" / "en-US"
            loc.mkdir(parents=True)
            (loc / "description.txt").write_text("Desc")
            (loc / "whats_new.txt").write_text("New")
            for whats_new, expected in ((False, {"--description"}), (True, {"--description", "--whats-new"})):
                fake = FakeAsc()
                quiet(asc_release.upload_listing, fake, version_id="V1", locale="en-US", metadata_dir=Path(tmp),
                      include_listing=True, include_whats_new=whats_new)
                update = [c for c in fake.calls if c[:2] == ("localizations", "update")][0]
                self.assertEqual({a for a in update if a.startswith("--")} - {"--id"}, expected)
                self.assertEqual(flag(update, "--id"), "LOC1")


class CmdWaitBuildTests(unittest.TestCase):
    def test_deadline_counts_from_upload_start_and_app_lookup_is_retried(self) -> None:
        import argparse

        lookups = []

        class Lookup:
            def run(self, *args: str, **_: object):
                lookups.append(args)
                if len(lookups) == 1:
                    raise asc_error(63)
                return {"data": {"id": APP, "attributes": {"bundleId": ios_release.BUNDLE_ID}}}

        captured = {}

        def fake_wait(client, **kwargs):
            captured.update(kwargs)
            return {"id": "B9"}

        args = argparse.Namespace(version=VERSION, build=40, started_at=STARTED, wait_minutes=120, poll_seconds=30)
        with tempfile.NamedTemporaryFile("r", suffix=".out") as out, mock.patch.object(
            ios_release, "asc_client", return_value=(asc_release, Lookup())
        ), mock.patch.object(ios_release, "wait_for_build", side_effect=fake_wait), mock.patch.object(
            ios_release.time, "sleep"
        ), mock.patch.object(ios_release.time, "time", return_value=STARTED + 30), mock.patch.dict(
            os.environ, {"GITHUB_OUTPUT": out.name}
        ), redirect_stdout(io.StringIO()):
            ios_release.cmd_wait_build(args)
            written = Path(out.name).read_text()
        self.assertEqual(len(lookups), 2)
        self.assertEqual(captured["deadline"], STARTED + 120 * 60)
        self.assertEqual(captured["uploaded_after"], STARTED)
        self.assertEqual(captured["build_number"], "40")
        self.assertIs(captured["is_transient"], ios_release.is_transient_error)
        self.assertIn("build_id=B9", written)

    def test_another_app_record_stops_the_wait(self) -> None:
        import argparse

        class Other:
            def run(self, *args: str, **_: object):
                return {"data": {"id": APP, "attributes": {"bundleId": "com.example.other"}}}

        args = argparse.Namespace(version=VERSION, build=40, started_at=STARTED, wait_minutes=120, poll_seconds=30)
        with mock.patch.object(ios_release, "asc_client", return_value=(asc_release, Other())), \
                mock.patch.object(ios_release.time, "time", return_value=STARTED), \
                redirect_stdout(io.StringIO()), self.assertRaises(ReleaseError):
            ios_release.cmd_wait_build(args)

    def test_app_lookup_gives_up_at_the_deadline(self) -> None:
        def boom():
            raise asc_error(63)

        clock = FakeClock(STARTED)
        with redirect_stdout(io.StringIO()), self.assertRaises(asc_cli.AscError):
            ios_release.call_with_retries(boom, deadline=STARTED + 90, poll_seconds=30, now=clock.now, sleep=clock.sleep)
        self.assertEqual(clock.sleeps, [30, 30, 30])

    def test_checks_run_asc_read_only(self) -> None:
        env = {"APP_STORE_CONNECT_API_KEY_ID": "K", "APP_STORE_CONNECT_ISSUER_ID": "I", "APP_STORE_CONNECT_API_KEY_P8": "P"}
        with mock.patch.dict(os.environ, env, clear=True):
            _, client = ios_release.asc_client()
        self.assertTrue(client.read_only)


class LiveSubmitFlowTests(unittest.TestCase):
    def test_selects_rechecks_then_submits(self) -> None:
        fake = FakeAsc(subscriptions=[{"id": "S1", "attributes": {"name": "Plus", "productId": PRODUCT,
                                                                   "state": "READY_TO_SUBMIT"}}])
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 0)
        writes = [c[:2] for c in fake.writes()]
        self.assertEqual(writes, [("versions", "attach-build"), ("versions", "update"), ("review", "submissions-create"),
                                  ("review", "items-add"), ("review", "items-add"), ("review", "submissions-submit")])
        items = [flag(c, "--item-type") for c in fake.writes() if c[:2] == ("review", "items-add")]
        self.assertEqual(items, ["subscriptionVersions", "appStoreVersions"])
        # The build is re-read and the selection re-checked after the products are attached.
        submit = fake.calls.index(fake.writes()[-1])
        last_items_add = max(i for i, c in enumerate(fake.calls) if c[:2] == ("review", "items-add"))
        rechecks = [i for i, c in enumerate(fake.calls) if c[:2] in {("builds", "list"), ("versions", "view")}]
        self.assertTrue(any(last_items_add < i < submit for i in rechecks))
        self.assertEqual(flag([c for c in fake.calls if c[:2] == ("versions", "update")][0], "--release-type"), "MANUAL")

    def test_selection_changed_before_submit_aborts(self) -> None:
        fake = FakeAsc(revert_after_select=True)
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 1)
        self.assertNotIn(("review", "submissions-submit"), [c[:2] for c in fake.calls])

    def test_waiting_for_review_with_another_build_aborts(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="OTHER")
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 1)
        self.assertEqual(fake.writes(), [])

    def test_waiting_for_review_with_this_build_is_idempotent(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9")
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 0)
        self.assertNotIn(("review", "submissions-submit"), [c[:2] for c in fake.writes()])
        self.assertNotIn(("versions", "attach-build"), [c[:2] for c in fake.writes()])

    def test_late_products_go_out_in_a_product_only_draft(self) -> None:
        iap = [{"id": "IAP1", "attributes": {"name": "Credits", "productId": CREDITS, "state": "READY_TO_SUBMIT"}}]
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9", iaps=iap)
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 0)
        self.assertEqual(flag([c for c in fake.writes() if c[:2] == ("review", "items-add")][0], "--item-id"), "IAP1v1")
        self.assertEqual(fake.writes()[-1][:2], ("review", "submissions-submit"))
        # A draft that also holds an app version is never submitted from here.
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9", iaps=iap, drafts=["D1"],
                       draft_items={"D1": [{"id": "X", "relationships": {"appStoreVersion": {"data": {"id": "V0"}}}}]})
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 1)
        self.assertNotIn(("review", "submissions-submit"), [c[:2] for c in fake.writes()])

    def test_a_rerun_with_nothing_to_send_leaves_no_empty_draft(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9")
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 0)
        self.assertEqual(fake.writes(), [])

    def test_a_draft_without_this_version_is_never_submitted(self) -> None:
        # READY_FOR_REVIEW says a draft holds the version; the one reused here does not.
        held = [{"id": "P", "relationships": {"subscriptionVersion": {"data": {"id": "S1v2"}}}}]
        subs = [{"id": "S1", "attributes": {"name": "Plus", "productId": PRODUCT, "state": "READY_TO_SUBMIT"}}]
        fake = FakeAsc(state="READY_FOR_REVIEW", subscriptions=subs, drafts=["D1"], draft_items={"D1": held})
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 1)
        self.assertNotIn(("review", "submissions-submit"), [c[:2] for c in fake.writes()])

    def test_a_product_that_cannot_be_added_keeps_the_version_out_of_review(self) -> None:
        subs = [{"id": "S1", "attributes": {"name": "Plus", "productId": PRODUCT, "state": "READY_TO_SUBMIT"}}]
        fake = FakeAsc(subscriptions=subs, refuse_items={"S1v2"})
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 1)
        self.assertNotIn(("review", "submissions-submit"), [c[:2] for c in fake.writes()])
        added = [flag(c, "--item-type") for c in fake.writes() if c[:2] == ("review", "items-add")]
        self.assertNotIn("appStoreVersions", added)

    def test_reused_draft_skips_what_it_already_holds(self) -> None:
        subs = [{"id": "S1", "attributes": {"name": "Plus", "productId": PRODUCT, "state": "DEVELOPER_REJECTED"}}]
        held = [{"id": "I1", "relationships": {"subscriptionVersion": {"data": {"id": "S1v2"}}}},
                {"id": "I2", "relationships": {"appStoreVersion": {"data": {"id": "V1"}}}}]
        fake = FakeAsc(subscriptions=subs, drafts=["D1"], draft_items={"D1": held})
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 0)
        self.assertEqual([c[:2] for c in fake.writes() if c[:1] == ("review",)], [("review", "submissions-submit")])
        self.assertEqual(flag(fake.writes()[-1], "--id"), "D1")

    def test_products_outside_the_catalog_or_already_approved_are_left_alone(self) -> None:
        subs = [{"id": "S9", "attributes": {"name": "Legacy", "productId": "com.example.legacy", "state": "READY_TO_SUBMIT"}},
                {"id": "S1", "attributes": {"name": "Plus", "productId": PRODUCT, "state": "APPROVED"}}]
        iaps = [{"id": "IAP1", "attributes": {"name": "Credits", "productId": CREDITS, "state": "APPROVED"}}]
        fake = FakeAsc(subscriptions=subs, iaps=iaps)
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 0)
        added = [flag(c, "--item-type") for c in fake.writes() if c[:2] == ("review", "items-add")]
        self.assertEqual(added, ["appStoreVersions"])
        self.assertFalse([c for c in fake.calls if "S9" in c], "a product outside the catalog was read")

    def test_a_reused_draft_with_items_this_release_did_not_choose_is_not_submitted(self) -> None:
        stray = [{"id": "STRAY", "relationships": {"inAppPurchaseVersion": {"data": {"id": "OTHER-IAPv1"}}}}]
        fake = FakeAsc(drafts=["D1"], draft_items={"D1": stray})
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 1)
        self.assertNotIn(("review", "submissions-submit"), [c[:2] for c in fake.writes()])
        # A catalog product's version (in any state) and this version are fine.
        iaps = [{"id": "IAP1", "attributes": {"name": "Credits", "productId": CREDITS, "state": "APPROVED"}}]
        held = [{"id": "OK", "relationships": {"inAppPurchaseVersion": {"data": {"id": "IAP1v1"}}}}]
        fake = FakeAsc(iaps=iaps, drafts=["D1"], draft_items={"D1": held})
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 0)
        self.assertEqual(fake.writes()[-1][:2], ("review", "submissions-submit"))

    def test_a_creative_draft_is_never_used_for_the_version(self) -> None:
        creative = [{"id": "IMG", "relationships": {"appAssetLibraryImage": {"data": {"id": "H"}}}}]
        fake = FakeAsc(drafts=["CREATIVE"], draft_items={"CREATIVE": creative})
        self.assertEqual(run_main(fake, SUBMIT, SUBMIT_ARGS), 0)
        self.assertIn(("review", "submissions-create"), [c[:2] for c in fake.writes()])
        self.assertNotEqual(flag(fake.writes()[-1], "--id"), "CREATIVE")

    def test_public_release_sets_after_approval(self) -> None:
        fake = FakeAsc()
        self.assertEqual(run_main(fake, {**SUBMIT, "PUBLIC_RELEASE": "true"}, SUBMIT_ARGS), 0)
        update = [c for c in fake.calls if c[:2] == ("versions", "update")][0]
        self.assertEqual(flag(update, "--release-type"), "AFTER_APPROVAL")


class FindAppTests(unittest.TestCase):
    def test_the_pinned_app_must_carry_the_bundle_id(self) -> None:
        self.assertEqual(quiet(asc_release.find_app, FakeAsc(), BUNDLE), APP)
        with self.assertRaises(SystemExit):
            quiet(asc_release.find_app, FakeAsc(bundle="com.example.other"), BUNDLE)

    def test_asc_failures_stop_with_a_readable_error(self) -> None:
        class Broken:
            def run(self, *args: str, **_: object):
                raise asc_cli.AscError(args, 3, "unauthorized")

        err = io.StringIO()
        with redirect_stderr(err), self.assertRaises(SystemExit):
            asc_release.find_app(Broken(), BUNDLE)
        self.assertIn("exit 3", err.getvalue())


def asc_version(state: str, version: str = VERSION) -> dict:
    return {"id": f"V-{version}", "attributes": {"versionString": version, "appStoreState": state}}


class VersionPreflightTests(unittest.TestCase):
    def preflight(self, fake: FakeAsc, **kwargs) -> str:
        return quiet(ios_release.version_preflight, fake, asc_release, version=VERSION, **kwargs)

    def test_versions_the_store_step_can_use_pass(self) -> None:
        for state in sorted(asc_release.SUBMITTABLE_VERSION_STATES):
            with self.subTest(state=state):
                fake = FakeAsc(versions=[asc_version(state)])
                self.assertEqual(self.preflight(fake, metadata=True, submit=True), state)
                self.assertEqual(fake.writes(), [])

    def test_missing_version_fails_with_the_fix(self) -> None:
        fake = FakeAsc(versions=[asc_version("READY_FOR_SALE", "7.1")])
        err = io.StringIO()
        with redirect_stderr(err), redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
            ios_release.version_preflight(fake, asc_release, version=VERSION, metadata=False, submit=True)
        self.assertIn("IOS_CREATE_VERSION", err.getvalue())

    def test_versions_in_review_or_released_fail(self) -> None:
        for state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_SALE"):
            with self.subTest(state=state), self.assertRaises(ReleaseError):
                self.preflight(FakeAsc(versions=[asc_version(state)]), metadata=False, submit=True)

    def test_command_reads_switches_and_skips_without_store_work(self) -> None:
        import argparse

        args = argparse.Namespace(version=VERSION)
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(ios_release, "asc_client") as client, \
                redirect_stdout(io.StringIO()):
            ios_release.cmd_version_preflight(args)
        client.assert_not_called()
        fake = FakeAsc()
        with mock.patch.dict(os.environ, {"UPLOAD_CREATIVE_ASSETS": "true"}, clear=True), mock.patch.object(
            ios_release, "asc_client", return_value=(asc_release, fake)
        ), redirect_stdout(io.StringIO()):
            ios_release.cmd_version_preflight(args)
        self.assertIn(("localizations", "list"), [c[:2] for c in fake.calls])


class CreateVersionTests(unittest.TestCase):
    def create(self, fake: FakeAsc, *, env: dict[str, str] | None = None, version: str = VERSION) -> int:
        return run_main(fake, {"CREATE_IOS_VERSION": "true"} if env is None else env, ["--create-version", "--version", version])

    def test_switch_off_makes_no_calls(self) -> None:
        fake = FakeAsc()
        self.assertEqual(self.create(fake, env={}), 0)
        self.assertEqual(fake.calls, [])

    def test_existing_version_is_left_alone(self) -> None:
        fake = FakeAsc(versions=[asc_version("PREPARE_FOR_SUBMISSION")])
        self.assertEqual(self.create(fake), 0)
        self.assertEqual(fake.writes(), [])

    def test_missing_version_is_created_for_this_app_and_read_back(self) -> None:
        fake = FakeAsc(versions=[asc_version("READY_FOR_SALE", "7.1")])
        self.assertEqual(self.create(fake), 0)
        create = fake.writes()[0]
        self.assertEqual(create[:2], ("versions", "create"))
        self.assertEqual((flag(create, "--app"), flag(create, "--version"), flag(create, "--platform")), (APP, VERSION, "IOS"))
        self.assertEqual([c[:2] for c in fake.calls].count(("versions", "list")), 2)

    def test_read_back_miss_fails(self) -> None:
        fake = FakeAsc(versions=[asc_version("READY_FOR_SALE", "7.1")], listed_after_create=False)
        self.assertEqual(self.create(fake), 1)

    def test_another_version_on_its_way_blocks_creation(self) -> None:
        for state in ("PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "PENDING_DEVELOPER_RELEASE"):
            fake = FakeAsc(versions=[asc_version("READY_FOR_SALE", "7.0"), asc_version(state, "7.1")])
            with self.subTest(state=state):
                self.assertEqual(self.create(fake), 1)
                self.assertEqual(fake.writes(), [])

    def test_version_not_newer_than_an_existing_one_is_refused(self) -> None:
        fake = FakeAsc(versions=[asc_version("READY_FOR_SALE", "7.3")])
        self.assertEqual(self.create(fake), 1)
        self.assertEqual(fake.writes(), [])

    def test_older_finished_versions_allow_creation(self) -> None:
        fake = FakeAsc(versions=[asc_version("READY_FOR_SALE", "7.1"), asc_version("REPLACED_WITH_NEW_VERSION", "7.0")])
        self.assertEqual(self.create(fake), 0)
        self.assertEqual(fake.created_versions, [VERSION])

    def test_other_app_or_bad_version_fails_without_writing(self) -> None:
        fake = FakeAsc(bundle="com.example.other", versions=[])
        self.assertEqual(self.create(fake), 1)
        self.assertEqual(fake.writes(), [])
        fake = FakeAsc(versions=[])
        self.assertEqual(self.create(fake, version="7.x"), 1)
        self.assertEqual(fake.calls, [])

    def test_ambiguous_version_fails_without_writing(self) -> None:
        fake = FakeAsc(versions=[asc_version("PREPARE_FOR_SUBMISSION"), asc_version("PREPARE_FOR_SUBMISSION")])
        self.assertEqual(self.create(fake), 1)
        self.assertEqual(fake.writes(), [])

    def test_dry_run_makes_no_calls(self) -> None:
        fake = FakeAsc(versions=[])
        self.assertEqual(run_main(fake, {"CREATE_IOS_VERSION": "true"}, ["--create-version", "--version", VERSION, "--dry-run"]), 0)
        self.assertEqual(fake.calls, [])


class MetadataRerunTests(unittest.TestCase):
    """Re-running the store job after a partial review submission."""

    PNG = b"\x89PNG\r\n\x1a\n" + b"screenshot" * 4
    LISTING = {"UPLOAD_LISTING": "true", "UPLOAD_WHATS_NEW": "true"}

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        loc = self.root / "meta" / "ios" / "en-US"
        loc.mkdir(parents=True)
        (loc / "description.txt").write_text("Track food with AI\n")
        (loc / "whats_new.txt").write_text("Fixes.\n")
        self.shots = self.root / "shots"
        for folder, _, _, _ in asc_release.SCREENSHOT_SETS:
            (self.shots / folder).mkdir(parents=True)
            (self.shots / folder / "01-home.png").write_bytes(self.PNG)
        self.same_text = {"description": "Track food with AI", "whatsNew": "Fixes."}
        self.same_shots = [{"fileName": "01-home.png", "fileSize": len(self.PNG),
                            "sourceFileChecksum": hashlib.md5(self.PNG).hexdigest()}]

    def run_store(self, fake: FakeAsc, env: dict[str, str], *, submit: bool = False) -> int:
        argv = ["--version", VERSION, "--metadata-dir", str(self.root / "meta"), "--screenshots-dir", str(self.shots)]
        if submit:
            argv += ["--build-id", "B9", "--build-number", "40"]
            env = {**env, **SUBMIT}
        return run_main(fake, env, argv)

    def test_ready_for_review_rerun_updates_text_and_submits(self) -> None:
        fake = FakeAsc(state="READY_FOR_REVIEW", live_text={"description": "Old", "whatsNew": "Fixes."}, drafts=["D1"],
                       draft_items={"D1": [{"id": "I", "relationships": {"appStoreVersion": {"data": {"id": "V1"}}}}]})
        self.assertEqual(self.run_store(fake, self.LISTING, submit=True), 0)
        update = [c for c in fake.writes() if c[:2] == ("localizations", "update")][0]
        self.assertEqual(flag(update, "--description"), "Track food with AI")
        self.assertNotIn("--whats-new", update)
        self.assertEqual(fake.writes()[-1][:2], ("review", "submissions-submit"))
        self.assertNotIn("appStoreVersions", [flag(c, "--item-type") for c in fake.writes() if c[:2] == ("review", "items-add")])

    def test_waiting_for_review_rerun_with_matching_text_is_idempotent(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9", live_text=self.same_text)
        self.assertEqual(self.run_store(fake, self.LISTING, submit=True), 0)
        self.assertEqual([c for c in fake.writes() if c[:1] != ("review",)], [])

    def test_waiting_for_review_with_changed_text_fails_before_any_write(self) -> None:
        for submit in (True, False):
            fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9", live_text={**self.same_text, "description": "Older"})
            with self.subTest(submit=submit):
                self.assertEqual(self.run_store(fake, self.LISTING, submit=submit), 1)
                self.assertEqual(fake.writes(), [])

    def test_locked_screenshots_are_compared_not_replaced(self) -> None:
        fake = FakeAsc(state="READY_FOR_REVIEW", live_shots=self.same_shots)
        self.assertEqual(self.run_store(fake, {"UPLOAD_SCREENSHOTS": "true"}), 0)
        self.assertEqual(fake.uploaded_sets, [])
        # A different file must stop the run before the text update writes anything.
        changed = [{**self.same_shots[0], "sourceFileChecksum": "0" * 32}]
        fake = FakeAsc(state="READY_FOR_REVIEW", live_shots=changed, live_text={"description": "Old"})
        self.assertEqual(self.run_store(fake, {"UPLOAD_SCREENSHOTS": "true", **self.LISTING}), 1)
        self.assertEqual(fake.writes(), [])

    def test_editable_version_skips_what_already_matches(self) -> None:
        fake = FakeAsc(live_text=self.same_text, live_shots=self.same_shots)
        self.assertEqual(self.run_store(fake, {**self.LISTING, "UPLOAD_SCREENSHOTS": "true"}), 0)
        self.assertEqual(fake.writes(), [])

    def test_editable_version_replaces_every_set_with_its_device_type(self) -> None:
        fake = FakeAsc()
        self.assertEqual(self.run_store(fake, {"UPLOAD_SCREENSHOTS": "true"}), 0)
        self.assertEqual(fake.uploaded_sets, ["IPHONE_67", "IPAD_PRO_3GEN_129", "IPHONE_DUO"])
        upload = [c for c in fake.writes() if c[:2] == ("screenshots", "upload")][0]
        self.assertIn("--replace", upload)
        self.assertIn("--confirm", upload)
        self.assertEqual(flag(upload, "--locale"), "en-US")
        self.assertEqual(Path(flag(upload, "--path")).name, "6.7")

    def test_each_set_uploads_with_its_own_device_type(self) -> None:
        fake = FakeAsc()
        live = {}

        def run(*args, _orig=fake.run, **kwargs):
            if args[:2] == ("screenshots", "list"):
                return {"sets": [{"set": {"attributes": {"screenshotDisplayType": d}}, "screenshots": [{"attributes": s} for s in shots]}
                                 for d, shots in live.items()]}
            if args[:2] == ("screenshots", "upload"):
                fake.calls.append(args)
                display = {dev: disp for _, disp, dev, _ in asc_release.SCREENSHOT_SETS}[flag(args, "--device-type")]
                live[display] = self.same_shots
                return {}
            return _orig(*args, **kwargs)

        fake.run = run  # type: ignore[method-assign]
        self.assertEqual(self.run_store(fake, {"UPLOAD_SCREENSHOTS": "true"}), 0)
        uploads = [flag(c, "--device-type") for c in fake.calls if c[:2] == ("screenshots", "upload")]
        self.assertEqual(uploads, ["IPHONE_67", "IPAD_PRO_3GEN_129", "IPHONE_DUO"])

    def test_an_upload_that_does_not_land_fails(self) -> None:
        fake = FakeAsc()
        fake_run = fake.run
        fake.run = lambda *a, **k: {} if a[:2] == ("screenshots", "upload") else fake_run(*a, **k)  # type: ignore[method-assign]
        self.assertEqual(self.run_store(fake, {"UPLOAD_SCREENSHOTS": "true"}), 1)

    def test_a_screenshot_with_alpha_fails_before_any_call(self) -> None:
        (self.shots / "ipad-13" / "02-alpha.png").write_bytes(png_header(6))
        fake = FakeAsc()
        self.assertEqual(self.run_store(fake, {"UPLOAD_SCREENSHOTS": "true"}), 1)
        self.assertEqual(fake.calls, [])

    def test_a_set_without_screenshots_fails_before_any_call(self) -> None:
        for folder, _, _, _ in asc_release.SCREENSHOT_SETS:
            with self.subTest(folder=folder):
                (self.shots / folder / "01-home.png").unlink()
                fake = FakeAsc()
                self.assertEqual(self.run_store(fake, {"UPLOAD_SCREENSHOTS": "true"}), 1)
                self.assertEqual(fake.calls, [])
                (self.shots / folder / "01-home.png").write_bytes(self.PNG)

    def test_other_states_still_refuse_metadata(self) -> None:
        for state in ("IN_REVIEW", "READY_FOR_SALE"):
            fake = FakeAsc(state=state, live_text={"description": "Old"})
            with self.subTest(state=state):
                self.assertEqual(self.run_store(fake, self.LISTING), 1)
                self.assertEqual(fake.writes(), [])


class CreativeAssetTests(unittest.TestCase):
    ENV = {"UPLOAD_CREATIVE_ASSETS": "true"}

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        for folder, data in (("header", b"header-image"), ("search-results", b"search-image")):
            (self.dir / folder).mkdir()
            (self.dir / folder / f"{folder}.png").write_bytes(data)

    def image(self, image_id: str, folder: str, state: str) -> dict:
        path = self.dir / folder / f"{folder}.png"
        return {"id": image_id, "attributes": {"fileName": path.name, "fileSize": path.stat().st_size, "state": state,
                                               "createdDate": "2026-10-20"}}

    def run_creative(self, fake: FakeAsc) -> int:
        return run_main(fake, self.ENV, ["--version", VERSION, "--creative-dir", str(self.dir)])

    def test_new_images_are_uploaded_and_reviewed_on_their_own(self) -> None:
        fake = FakeAsc()
        self.assertEqual(self.run_creative(fake), 0)
        uploads = [Path(flag(c, "--file")).name for c in fake.writes() if c[:3] == ("asset-library", "images", "upload")]
        self.assertEqual(uploads, ["header.png", "search-results.png"])
        review = [c for c in fake.writes() if c[:1] == ("review",)]
        self.assertEqual([c[:2] for c in review], [("review", "submissions-create"), ("review", "items-add"),
                                                   ("review", "items-add"), ("review", "submissions-submit")])
        self.assertEqual({flag(c, "--item-type") for c in review if c[:2] == ("review", "items-add")}, {"appAssetLibraryImages"})
        self.assertFalse([c for c in fake.writes() if c[:2] == ("localizations", "placements")])

    def test_images_in_review_are_neither_reuploaded_nor_placed(self) -> None:
        fake = FakeAsc(library=[self.image("H", "header", "WAITING_FOR_REVIEW"), self.image("S", "search-results", "IN_REVIEW")])
        self.assertEqual(self.run_creative(fake), 0)
        self.assertEqual(fake.writes(), [])

    def test_approved_images_are_placed_and_existing_ones_swapped(self) -> None:
        old = {"id": "PL-old", "attributes": {"placementType": "PRODUCT_PAGE_HEADER_ASSET"},
               "relationships": {"image": {"data": {"id": "OLDIMG"}}}}
        fake = FakeAsc(library=[self.image("H", "header", "APPROVED"), self.image("S", "search-results", "APPROVED")],
                       placements=[old])
        self.assertEqual(self.run_creative(fake), 0)
        swap = [c for c in fake.writes() if c[:3] == ("localizations", "placements", "swap")][0]
        self.assertEqual((flag(swap, "--image-id"), flag(swap, "--placement-id")), ("H", "PL-old"))
        self.assertIn("--confirm", swap)
        create = [c for c in fake.writes() if c[:3] == ("localizations", "placements", "create")][0]
        self.assertEqual((flag(create, "--image-id"), flag(create, "--placement-type"), flag(create, "--placement-group")),
                         ("S", "APP_STORE_SEARCH_RESULTS_ASSET", "DEFAULT_PROFILE"))
        # A second run finds both placed and writes nothing.
        writes = len(fake.writes())
        self.assertEqual(self.run_creative(fake), 0)
        self.assertEqual(len(fake.writes()), writes)

    def test_an_image_with_alpha_fails_before_any_call(self) -> None:
        (self.dir / "header" / "header.png").write_bytes(png_header(6))
        fake = FakeAsc()
        self.assertEqual(self.run_creative(fake), 1)
        self.assertEqual(fake.calls, [])

    def test_a_rejected_image_stops_the_run(self) -> None:
        fake = FakeAsc(library=[self.image("H", "header", "REJECTED")])
        self.assertEqual(self.run_creative(fake), 1)
        self.assertEqual(fake.writes(), [])

    def test_a_locked_version_takes_no_new_images(self) -> None:
        fake = FakeAsc(state="WAITING_FOR_REVIEW", attached="B9")
        self.assertEqual(self.run_creative(fake), 1)
        self.assertEqual(fake.writes(), [])

    def test_a_locked_version_sends_nothing_to_review(self) -> None:
        for state in ("WAITING_FOR_REVIEW", "READY_FOR_REVIEW"):
            for image_state in ("UPLOAD_COMPLETE", "PREPARE_FOR_SUBMISSION"):
                fake = FakeAsc(state=state, attached="B9", library=[self.image("H", "header", image_state)])
                with self.subTest(state=state, image_state=image_state):
                    self.assertEqual(self.run_creative(fake), 1)
                    self.assertEqual(fake.writes(), [])

    def test_a_retry_finishes_the_creative_draft_it_left_behind(self) -> None:
        library = [self.image("H", "header", "PREPARE_FOR_SUBMISSION"), self.image("S", "search-results", "PREPARE_FOR_SUBMISSION")]
        held = [{"id": "I-H", "relationships": {"appAssetLibraryImage": {"data": {"id": "H"}}}}]
        fake = FakeAsc(library=library, drafts=["OLD"], draft_items={"OLD": held})
        self.assertEqual(self.run_creative(fake), 0)
        self.assertNotIn(("review", "submissions-create"), [c[:2] for c in fake.writes()])
        submit = fake.writes()[-1]
        self.assertEqual(flag(submit, "--id"), "OLD")
        # A draft holding anything else is left alone and a new one is used.
        other = [{"id": "X", "relationships": {"appStoreVersion": {"data": {"id": "V1"}}}}]
        fake = FakeAsc(library=library, drafts=["VERSION"], draft_items={"VERSION": other})
        self.assertEqual(self.run_creative(fake), 0)
        self.assertNotEqual(flag(fake.writes()[-1], "--id"), "VERSION")

    def test_a_creative_submission_with_other_items_is_not_submitted(self) -> None:
        fake = FakeAsc()
        fake_run = fake.run

        def run(*args, **kwargs):
            result = fake_run(*args, **kwargs)
            if args[:2] == ("review", "submissions-create"):
                fake.items[result["data"]["id"]] = [{"id": "X", "relationships": {"appStoreVersion": {"data": {"id": "V1"}}}}]
            return result

        fake.run = run  # type: ignore[method-assign]
        self.assertEqual(self.run_creative(fake), 1)
        self.assertNotIn(("review", "submissions-submit"), [c[:2] for c in fake.writes()])


class RedactionTests(unittest.TestCase):
    """IOS-REL-6: failure artifacts never carry the key or issuer ID."""

    KEY = "TESTKEY0001"
    ISSUER = "00000000-test-4000-8000-issuer000001"

    def secrets(self) -> dict[str, str]:
        return {"ASC_KEY_ID": self.KEY, "ASC_ISSUER_ID": self.ISSUER}

    def test_text_binary_and_utf16_copies_never_survive(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp) / "logs"
            dist = logs / "Fud.xcdistributionlogs"
            dist.mkdir(parents=True)
            (logs / "archive.log").write_text(
                f"-authenticationKeyID {self.KEY} -authenticationKeyIssuerID {self.ISSUER}\nAuthKey_{self.KEY}.p8\n"
            )
            (dist / "options.plist").write_bytes(
                b"bplist00\x00\x01" + self.KEY.encode() + b"\x00" + self.ISSUER.upper().encode() + b"\xff"
            )
            (dist / "upload.log").write_bytes(f"key {self.KEY}".encode("utf-16-le"))
            (logs / "clean.log").write_text("nothing to hide")
            outside = Path(tmp) / "outside.txt"
            outside.write_text(self.KEY)
            (logs / "link.txt").symlink_to(outside)

            changed, removed = redact_credential_ids.redact_folder(logs, self.secrets())

            text = (logs / "archive.log").read_text()
            self.assertEqual(
                text,
                "-authenticationKeyID <ASC_KEY_ID> -authenticationKeyIssuerID <ASC_ISSUER_ID>\nAuthKey_<ASC_KEY_ID>.p8\n",
            )
            plist = (dist / "options.plist").read_bytes()
            self.assertTrue(plist.startswith(b"bplist00\x00\x01<ASC_KEY_ID>\x00<ASC_ISSUER_ID>"))
            self.assertFalse((dist / "upload.log").exists(), "UTF-16 copies are removed")
            self.assertFalse((logs / "link.txt").exists(), "links out of the folder are removed")
            self.assertEqual(outside.read_text(), self.KEY, "the link target is untouched")
            self.assertEqual((logs / "clean.log").read_text(), "nothing to hide")
            self.assertEqual(changed, 2)
            self.assertEqual(len(removed), 2)
            for path in logs.rglob("*"):
                if path.is_file():
                    self.assertFalse(
                        redact_credential_ids.remaining_ids(path.read_bytes(), [self.KEY, self.ISSUER]), path
                    )

    def test_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "export.log").write_text(f"--apiKey {self.KEY}")
            out = io.StringIO()
            with mock.patch.dict(os.environ, self.secrets()), redirect_stdout(out):
                self.assertEqual(redact_credential_ids.main(["redact", tmp]), 0)
            self.assertEqual((Path(tmp) / "export.log").read_text(), "--apiKey <ASC_KEY_ID>")
            with mock.patch.dict(os.environ, {"ASC_KEY_ID": "", "ASC_ISSUER_ID": ""}), redirect_stdout(io.StringIO()):
                self.assertEqual(redact_credential_ids.main(["redact", tmp]), 0)
            with redirect_stderr(io.StringIO()):
                self.assertEqual(redact_credential_ids.main(["redact"]), 2)


class PrintGatesTests(unittest.TestCase):
    """P-21: the printed summary never shows an invalid switch as off."""

    def run_print(self, env: dict[str, str]) -> str:
        clean = {k: v for k, v in os.environ.items() if not k.startswith(("IOS_", "ANDROID_", "STORE_"))}
        clean.update(env)
        out = io.StringIO()
        with mock.patch.dict(os.environ, clean, clear=True), \
                mock.patch.object(sys, "argv", ["print_gates.py", "--platform", "all"]), redirect_stdout(out):
            print_gates.main()
        return out.getvalue()

    def test_invalid_values_are_shown_as_invalid(self) -> None:
        output = self.run_print({"IOS_SUBMIT_REVIEW": "maybe", "ANDROID_RELEASE_AUTOMATION": " ON "})
        self.assertIn("IOS_SUBMIT_REVIEW=INVALID 'maybe' (a release run fails)", output)
        self.assertIn("ANDROID_RELEASE_AUTOMATION=true", output)
        self.assertIn("IOS_UPLOAD_BUILD=false (unset)", output)
        self.assertIn("invalid value", output)
        self.assertIn("one or more live gates are on", output)

    def test_create_version_switch_is_listed(self) -> None:
        output = self.run_print({"IOS_RELEASE_AUTOMATION": "true", "IOS_CREATE_VERSION": "true"})
        self.assertIn("IOS_CREATE_VERSION=true\n", output)
        self.assertIn("one or more live gates are on", output)
        self.assertIn("IOS_CREATE_VERSION=INVALID", self.run_print({"IOS_CREATE_VERSION": "maybe"}))

    def test_creative_assets_switch_is_listed(self) -> None:
        self.assertIn("IOS_UPLOAD_CREATIVE_ASSETS=false (unset)", self.run_print({}))
        self.assertIn("IOS_UPLOAD_CREATIVE_ASSETS=INVALID", self.run_print({"IOS_UPLOAD_CREATIVE_ASSETS": "maybe"}))

    def test_everything_off(self) -> None:
        output = self.run_print({"IOS_RELEASE_AUTOMATION": "false"})
        self.assertIn("IOS_RELEASE_AUTOMATION=false\n", output)
        self.assertIn("all gates off", output)
        self.assertNotIn("INVALID", output)


class ReleaseNotesTests(unittest.TestCase):
    TEXT = (
        "# Release notes\n\n## Unreleased\n\nWork in progress.\n\n"
        "## ios-v7.2\n\nShipped.\n\n## android-v7.2\n\nBeta.\n\n## ios-v7.3\n\n## v7.0\n\nOld.\n"
    )

    def run_cli(self, *args: str, text: str | None = TEXT) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory() as root:
            if text is not None:
                (Path(root) / "RELEASE_NOTES.md").write_text(text, encoding="utf-8")
            with mock.patch.object(release_notes, "ROOT", Path(root)), redirect_stdout(out), redirect_stderr(err):
                try:
                    release_notes.main(list(args))
                except SystemExit as exc:
                    return (exc.code if isinstance(exc.code, int) else 1), out.getvalue(), err.getvalue()
        return 0, out.getvalue(), err.getvalue()

    def test_exact_tag_sections(self) -> None:
        self.assertEqual(release_notes.notes_for_tag("ios-v7.2", self.TEXT), "Shipped.")
        self.assertEqual(release_notes.notes_for_tag("android-v7.2", self.TEXT), "Beta.")
        self.assertEqual(release_notes.notes_for_tag("v7.0", self.TEXT), "Old.")
        self.assertIsNone(release_notes.section_for_tag("ios-v7.4", self.TEXT))
        with self.assertRaisesRegex(ValueError, "Add a reviewed ## ios-v7.4"):
            release_notes.notes_for_tag("ios-v7.4", self.TEXT)

    def test_empty_section_and_unreleased_always_fail(self) -> None:
        for strict in (True, False):
            lookup = release_notes.notes_for_tag if strict else release_notes.section_for_tag
            with self.subTest(strict=strict):
                with self.assertRaisesRegex(ValueError, "empty"):
                    lookup("ios-v7.3", self.TEXT)
                with self.assertRaisesRegex(ValueError, "Unreleased"):
                    lookup("Unreleased", self.TEXT)

    def test_missing_notes_fail_unless_optional(self) -> None:
        code, out, _ = self.run_cli("ios-v7.4")
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        # A tag without notes still gets a GitHub Release (generated notes).
        code, out, err = self.run_cli("--if-present", "ios-v7.4")
        self.assertEqual((code, out), (0, ""))
        self.assertIn("no ## ios-v7.4 section", err)
        code, out, _ = self.run_cli("--if-present", "ios-v7.2")
        self.assertEqual((code, out), (0, "Shipped.\n"))
        code, _, _ = self.run_cli("--if-present", "ios-v7.3")
        self.assertEqual(code, 2, "an empty section is malformed even when notes are optional")

    def test_duplicate_sections_fail(self) -> None:
        text = self.TEXT + "\n## ios-v7.2\n\nShipped again.\n"
        for lookup in (release_notes.notes_for_tag, release_notes.section_for_tag):
            with self.subTest(lookup=lookup.__name__), self.assertRaisesRegex(ValueError, "2 ## ios-v7.2 sections"):
                lookup("ios-v7.2", text)
        self.assertEqual(release_notes.notes_for_tag("android-v7.2", text), "Beta.")
        code, out, err = self.run_cli("--if-present", "ios-v7.2", text=text)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("keep exactly one", err)

    def test_missing_notes_file_is_missing_notes(self) -> None:
        code, out, err = self.run_cli("--if-present", "ios-v7.2", text=None)
        self.assertEqual((code, out), (0, ""))
        self.assertIn("no ## ios-v7.2 section", err)
        code, out, err = self.run_cli("ios-v7.2", text=None)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("Add a reviewed ## ios-v7.2", err)


class IosWhatsNewTests(unittest.TestCase):
    def prepare(self, appstore: str) -> tuple[int, str, Path]:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        (root / "APPSTORE.md").write_text(appstore, encoding="utf-8")
        argv = ["prepare_whats_new.py", "--platform", "ios", "--tag", TAG, "--out", str(root / "out")]
        out = io.StringIO()
        with mock.patch.object(prepare_whats_new, "ROOT", root), mock.patch.object(sys, "argv", argv), \
                redirect_stdout(out), redirect_stderr(out):
            try:
                prepare_whats_new.main()
            except SystemExit as exc:
                return (exc.code if isinstance(exc.code, int) else 1), out.getvalue(), root
        return 0, out.getvalue(), root

    def test_writes_whats_new_for_asc(self) -> None:
        code, output, root = self.prepare("## What's New (v7.2)\n```\n  Fixes.\n```\n")
        self.assertEqual(code, 0, output)
        written = root / "out" / "ios" / "en-US" / "whats_new.txt"
        self.assertEqual(written.read_text(encoding="utf-8"), "Fixes.\n")

    def test_missing_empty_or_too_long_text_fails(self) -> None:
        cases = {
            "no heading": "## Description\n```\nApp\n```\n",
            "no fence": "## What's New\nFixes.\n## Privacy URL\n",
            "empty": "## What's New\n```\n\n```\n",
            "too long": "## What's New\n```\n" + "x" * 4001 + "\n```\n",
        }
        for label, text in cases.items():
            with self.subTest(label):
                code, _, _ = self.prepare(text)
                self.assertEqual(code, 1)
        code, output, _ = self.prepare("## What's New\n```\n" + "x" * 4000 + "\n```\n")
        self.assertEqual(code, 0, output)

    def test_markdown_is_rejected_plain_bullets_are_fine(self) -> None:
        for label, body in {
            "bold": "**New** logging",
            "link": "Read [the notes](https://fud-ai.app)",
            "code": "Use `Settings` to switch",
            "heading": "# What changed",
        }.items():
            with self.subTest(label):
                code, output, _ = self.prepare(f"## What's New\n```\n{body}\n```\n")
                self.assertEqual(code, 1)
                self.assertIn("plain text", output)
        plain = "NEW\n• Faster logging → fewer taps\n- Fixes\n5*3 = 15, snake_case stays"
        code, output, _ = self.prepare(f"## What's New\n```\n{plain}\n```\n")
        self.assertEqual(code, 0, output)


if __name__ == "__main__":
    unittest.main()
