#!/usr/bin/env python3
"""App Store Connect metadata, screenshots, creative assets and review (gated in CI).

Every App Store Connect call goes through the pinned App Store Connect CLI
(`asc`, see asc_cli.py); this script decides what may change and checks the
results.

Submitting for review covers the App Store version and the Ready-to-Submit
subscriptions and in-app purchases in store/catalog/products.json. They are
added to one draft review submission, and nothing reaches App Review until that
draft is submitted, right after this run's build is re-checked. A first-time
subscription must ship with the version, so a product that cannot be added stops
the whole submission.

`--create-version` (IOS_CREATE_VERSION) runs first on a release run, before the
read-only version preflight: it adds the App Store version for the tag when App
Store Connect does not have it yet, and leaves an existing one alone. It refuses
when another version is still on its way to the store or the tag's version is
not newer than every existing one."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_cli  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BUNDLE_ID = "com.apoorvdarshan.calorietracker"
# App Store Connect app record for DEFAULT_BUNDLE_ID. Every run checks that this
# record carries exactly that bundle id before touching anything.
ASC_APP_ID = "6758935726"
PLATFORM = "IOS"
# Screenshot sets in upload order: the folder under --screenshots-dir that
# stage_screenshots.py fills, the ASC display type, asc's --device-type, and a
# label for logs. APP_IPHONE_DUO is missing from Apple's OpenAPI spec (4.5.1),
# but App Store Connect accepts it; one set holds both the outer and the inner
# screen sizes.
SCREENSHOT_SETS = (
    ("6.7", "APP_IPHONE_67", "IPHONE_67", '6.7" iPhone'),
    ("ipad-13", "APP_IPAD_PRO_3GEN_129", "IPAD_PRO_3GEN_129", '13" iPad'),
    ("iphone-duo", "APP_IPHONE_DUO", "IPHONE_DUO", "iPhone Duo"),
)
# App Store Connect per screenshot-set limit.
APP_SCREENSHOT_SET_MAX = 10
# Product page creative assets: the folder under --creative-dir, the placement
# type, and a label for logs. Each folder holds at most one image.
CREATIVE_SLOTS = (
    ("header", "PRODUCT_PAGE_HEADER_ASSET", "product page header"),
    ("search-results", "APP_STORE_SEARCH_RESULTS_ASSET", "search results"),
)
# Apple's image specs per slot (asc asset-library specs): the header is a 21:9
# 3840x1646 PNG; search results are 3:2 PNG or JPEG from 1920x1280 to 3840x2560.
# A 5244x2950 16:9 PNG is a universal image that fits either.
UNIVERSAL_CREATIVE_SIZE = (5244, 2950)
CREATIVE_EXTENSIONS = {".png", ".jpg", ".jpeg"}
# Library image states: still being reviewed, or finished without approval.
CREATIVE_PENDING_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED"}
CREATIVE_UNSUBMITTED_STATES = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "COMPLETE", "UPLOAD_COMPLETE"}
# AWAITING_UPLOAD is a reservation an interrupted upload left behind; it is
# ignored like a failed one, so the next run uploads the image again.
CREATIVE_DEAD_STATES = {"REJECTED", "FAILED", "ARCHIVED", "AWAITING_UPLOAD"}
EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}
# READY_FOR_REVIEW means the version already sits in a draft review submission
# (for example after a failed submit); it can still be submitted.
SUBMITTABLE_VERSION_STATES = EDITABLE_VERSION_STATES | {"READY_FOR_REVIEW"}
# Apple keeps a version's text editable in READY_FOR_REVIEW; only screenshots
# and previews are locked there.
TEXT_EDITABLE_VERSION_STATES = EDITABLE_VERSION_STATES | {"READY_FOR_REVIEW"}
# Nothing can change while the version waits for review. A re-run there (after
# the submit landed but the job failed) only passes when App Store Connect
# already shows exactly what the repository would upload.
COMPARE_ONLY_VERSION_STATES = {"WAITING_FOR_REVIEW"}
# Versions in these states are finished. Any other state means the version is
# still on its way to the store, and App Store Connect allows only one such
# version per platform, so no new version is created next to it.
FINISHED_VERSION_STATES = {
    "READY_FOR_SALE",
    "REPLACED_WITH_NEW_VERSION",
    "REMOVED_FROM_SALE",
    "DEVELOPER_REMOVED_FROM_SALE",
}
# Subscription states in which a version can still be (re)attached to a review.
SUBMITTABLE_PRODUCT_STATES = {"READY_TO_SUBMIT", "DEVELOPER_REJECTED", "READY_FOR_REVIEW"}
RELEASE_TYPE_PUBLIC = "AFTER_APPROVAL"
RELEASE_TYPE_MANUAL = "MANUAL"


def fail(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def truthy(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in {"1", "true", "yes", "on"}


def read_text(path: Path) -> str | None:
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8").strip()
    return text or None


def data(payload: Any) -> Any:
    return (payload or {}).get("data") if isinstance(payload, dict) else None


def rows(payload: Any) -> list[dict[str, Any]]:
    value = data(payload)
    return value if isinstance(value, list) else []


def attrs(row: dict[str, Any] | None) -> dict[str, Any]:
    return (row or {}).get("attributes") or {}


def related_id(row: dict[str, Any], name: str) -> str | None:
    return (((row.get("relationships") or {}).get(name) or {}).get("data") or {}).get("id")


def asc_value(text: str) -> str:
    """A flag value for asc, which reads a leading @ as @file:/@env: (escaped as @@)."""
    return "@" + text if text.startswith("@") else text


def load_credentials() -> tuple[str, str, str]:
    key_id = os.environ.get("APP_STORE_CONNECT_API_KEY_ID", "").strip()
    issuer_id = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    key_p8 = os.environ.get("APP_STORE_CONNECT_API_KEY_P8", "").strip()
    if not key_id or not issuer_id or not key_p8:
        fail(
            "missing ASC credentials — set APP_STORE_CONNECT_API_KEY_ID, "
            "APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8"
        )
    return key_id, issuer_id, key_p8


def asc_from_environment(*, read_only: bool = False) -> asc_cli.Asc:
    load_credentials()
    return asc_cli.Asc(read_only=read_only)


def call(asc: asc_cli.Asc, *args: str) -> Any:
    """Run asc and stop the release with a readable error when it fails."""
    try:
        return asc.run(*args)
    except asc_cli.AscError as exc:
        fail(str(exc))


def find_app(asc: asc_cli.Asc, bundle_id: str, app_id: str = ASC_APP_ID) -> str:
    """The pinned App Store Connect app, after checking it carries exactly bundle_id."""
    record = data(call(asc, "apps", "view", "--id", app_id)) or {}
    if record.get("id") != app_id:
        fail(f"App Store Connect returned app {record.get('id')!r}, expected {app_id}")
    found = attrs(record).get("bundleId")
    if found != bundle_id:
        fail(f"App Store Connect app {app_id} has bundle id {found!r}, expected {bundle_id}")
    return app_id


def list_ios_app_store_versions(asc: asc_cli.Asc, app_id: str) -> list[dict[str, Any]]:
    return rows(call(asc, "versions", "list", "--app", app_id, "--platform", PLATFORM, "--paginate"))


def get_ios_app_store_version(asc: asc_cli.Asc, app_id: str, version_string: str) -> dict[str, Any]:
    matches = [
        row for row in list_ios_app_store_versions(asc, app_id) if attrs(row).get("versionString") == version_string
    ]
    if not matches:
        fail(
            f"no IOS App Store version {version_string!r} for app {app_id} "
            "(turn on IOS_CREATE_VERSION, or create the version in App Store Connect first)"
        )
    if len(matches) > 1:
        fail(f"ambiguous App Store versions for {version_string!r} on IOS — got {len(matches)} records")
    return matches[0]


def version_localization(asc: asc_cli.Asc, version_id: str, locale: str) -> dict[str, Any]:
    found = [
        row
        for row in rows(call(asc, "localizations", "list", "--version", version_id, "--locale", locale))
        if attrs(row).get("locale") == locale
    ]
    if not found:
        fail(f"App Store version {version_id} has no {locale} localization")
    return found[0]


LISTING_FIELDS = (
    ("description", "description.txt", "--description"),
    ("keywords", "keywords.txt", "--keywords"),
    ("promotionalText", "promotional_text.txt", "--promotional-text"),
    ("marketingUrl", "marketing_url.txt", "--marketing-url"),
    ("supportUrl", "support_url.txt", "--support-url"),
)
WHATS_NEW_FIELD = ("whatsNew", "whats_new.txt", "--whats-new")


def same_text(live: Any, wanted: str) -> bool:
    """App Store Connect text equals the repository text (line endings/edges aside)."""
    if not isinstance(live, str):
        return False
    return live.replace("\r\n", "\n").strip() == wanted.replace("\r\n", "\n").strip()


def upload_listing(
    asc: asc_cli.Asc,
    *,
    version_id: str,
    locale: str,
    metadata_dir: Path,
    include_listing: bool = True,
    include_whats_new: bool = False,
    editable: bool = True,
) -> list[str]:
    """Update the version localization. Listing text and What's New are separate gates.

    Only fields that differ from App Store Connect are sent, so a re-run changes
    nothing that is already right. With editable=False (the version waits for
    review) nothing is written: the step fails unless every field already matches.
    App info (name, subtitle, privacy URL) stays locked while a version is live,
    so it is never edited. Returns the fields that were updated.
    """
    loc_dir = metadata_dir / "ios" / locale
    version_loc = version_localization(asc, version_id, locale)
    live = attrs(version_loc)
    fields = (LISTING_FIELDS if include_listing else ()) + ((WHATS_NEW_FIELD,) if include_whats_new else ())
    changes: list[tuple[str, str, str]] = []
    for field, filename, flag in fields:
        value = read_text(loc_dir / filename)
        if value and not same_text(live.get(field), value):
            changes.append((field, flag, value))
    if not changes:
        print(f"  version localization ({locale}) already matches the repository")
        return []
    names = [field for field, _, _ in changes]
    if not editable:
        fail(
            f"cannot change {', '.join(names)} ({locale}) while the version waits for "
            "review; App Store Connect differs from the repository"
        )
    args = ["localizations", "update", "--id", version_loc["id"]]
    for _, flag, value in changes:
        args += [flag, asc_value(value)]
    call(asc, *args)
    print(f"  updated version localization ({locale}): {', '.join(names)}")
    return names


def file_checksum(raw: bytes) -> str:
    """The MD5 App Store Connect records as a screenshot's sourceFileChecksum."""
    return hashlib.md5(raw, usedforsecurity=False).hexdigest()


def local_screenshot_fingerprints(pngs: list[Path]) -> list[tuple[str, int, str]]:
    fingerprints = []
    for path in pngs:
        raw = path.read_bytes()
        fingerprints.append((path.name, len(raw), file_checksum(raw)))
    return fingerprints


def staged_screenshot_sets(screenshots_dir: Path) -> list[tuple[str, str, str, list[Path]]]:
    """(display type, device type, label, PNGs) for every set; fails when a set has nothing to upload."""
    sets = []
    for folder, display_type, device_type, label in SCREENSHOT_SETS:
        set_dir = screenshots_dir / folder
        pngs = sorted(set_dir.glob("*.png")) if set_dir.is_dir() else []
        if not pngs:
            fail(f"no PNG screenshots for the {label} set in {set_dir}")
        if len(pngs) > APP_SCREENSHOT_SET_MAX:
            fail(f"too many PNGs ({len(pngs)}) for the ASC {label} set (max {APP_SCREENSHOT_SET_MAX})")
        with_alpha = [p.name for p in pngs if asc_cli.image_has_alpha(p)]
        if with_alpha:
            fail(f"the {label} screenshots {', '.join(with_alpha)} have an alpha channel, which App Store Connect refuses; stage them with stage_screenshots.py")
        sets.append((display_type, device_type, label, pngs))
    return sets


def live_screenshot_sets(
    asc: asc_cli.Asc, *, app_id: str, version_id: str, locale: str
) -> dict[str, list[tuple[Any, Any, Any]]]:
    """Display type -> the (fileName, fileSize, sourceFileChecksum) App Store Connect holds, in order."""
    payload = call(
        asc, "screenshots", "list", "--app", app_id, "--version-id", version_id, "--locale", locale, "--platform", PLATFORM
    )
    live: dict[str, list[tuple[Any, Any, Any]]] = {}
    for entry in (payload or {}).get("sets") or []:
        display_type = attrs(entry.get("set")).get("screenshotDisplayType")
        live[display_type] = [
            (attrs(shot).get("fileName"), attrs(shot).get("fileSize"), attrs(shot).get("sourceFileChecksum"))
            for shot in entry.get("screenshots") or []
        ]
    return live


def upload_screenshots(
    asc: asc_cli.Asc,
    *,
    app_id: str,
    version_id: str,
    locale: str,
    screenshots_dir: Path,
    editable: bool = True,
) -> bool:
    """Replace each screenshot set unless App Store Connect already has its files.

    With editable=False (screenshots are locked once the version is in a review
    submission) nothing is written: the step fails unless every set already holds
    exactly these files, in order. Returns True when screenshots were uploaded.
    """
    sets = staged_screenshot_sets(screenshots_dir)
    live = live_screenshot_sets(asc, app_id=app_id, version_id=version_id, locale=locale)
    uploaded = False
    for display_type, device_type, label, pngs in sets:
        wanted = local_screenshot_fingerprints(pngs)
        if live.get(display_type) == wanted:
            print(f"  {label} ({locale}) screenshots already match the repository")
            continue
        if not editable:
            fail(
                f"cannot replace the {label} ({locale}) screenshots once the version is in a review "
                "submission; App Store Connect differs from the repository"
            )
        # --replace deletes the set's screenshots before uploading. If an upload
        # fails part-way, fix the error and re-run: the set is replaced again.
        call(
            asc,
            "screenshots", "upload", "--app", app_id, "--version-id", version_id, "--locale", locale,
            "--path", str(pngs[0].parent), "--device-type", device_type, "--replace", "--confirm",
        )
        after = live_screenshot_sets(asc, app_id=app_id, version_id=version_id, locale=locale)
        if after.get(display_type) != wanted:
            fail(f"after uploading, App Store Connect's {label} ({locale}) set does not match the repository")
        print(f"  uploaded {len(pngs)} {label} ({locale}) screenshot(s)")
        uploaded = True
    return uploaded


def image_dimensions(path: Path) -> tuple[str | None, int, int]:
    """(format, width, height) of a PNG or JPEG, read from its headers."""
    raw = Path(path).read_bytes()
    if raw.startswith(asc_cli.PNG_SIGNATURE) and len(raw) >= 24:
        return "png", int.from_bytes(raw[16:20], "big"), int.from_bytes(raw[20:24], "big")
    if raw[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(raw):
            if raw[i] != 0xFF:
                i += 1
                continue
            marker = raw[i + 1]
            if marker == 0xFF or marker in (0x01, 0xD8) or 0xD0 <= marker <= 0xD7:
                i += 1 if marker == 0xFF else 2
                continue
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                return "jpeg", int.from_bytes(raw[i + 7:i + 9], "big"), int.from_bytes(raw[i + 5:i + 7], "big")
            i += 2 + int.from_bytes(raw[i + 2:i + 4], "big")
    return None, 0, 0


def creative_size_problem(placement_type: str, path: Path) -> str | None:
    """Why Apple would refuse this image for the slot, or None when it fits."""
    kind, width, height = image_dimensions(path)
    if kind is None:
        return "is not a PNG or JPEG"
    if kind == "png" and (width, height) == UNIVERSAL_CREATIVE_SIZE:
        return None
    if placement_type == "PRODUCT_PAGE_HEADER_ASSET":
        if kind != "png" or (width, height) != (3840, 1646):
            return f"is a {width}x{height} {kind.upper()}; the header must be a 3840x1646 PNG"
        return None
    if not (1920 <= width <= 3840 and width * 2 == height * 3):
        return f"is {width}x{height}; search results images are 3:2, from 1920x1280 to 3840x2560"
    return None


def creative_sources(creative_dir: Path) -> list[tuple[str, str, Path]]:
    """(placement type, label, image) for every creative slot that has an image."""
    found = []
    for folder, placement_type, label in CREATIVE_SLOTS:
        slot_dir = creative_dir / folder
        images = sorted(
            p for p in slot_dir.glob("*") if p.is_file() and p.suffix.lower() in CREATIVE_EXTENSIONS
        ) if slot_dir.is_dir() else []
        if len(images) > 1:
            fail(f"the {label} slot takes one image; {slot_dir} has {len(images)}")
        if images and asc_cli.image_has_alpha(images[0]):
            fail(f"the {label} image {images[0].name} has an alpha channel, which App Store Connect refuses; re-export it as RGB")
        problem = creative_size_problem(placement_type, images[0]) if images else None
        if problem:
            fail(f"the {label} image {images[0].name} {problem}")
        if images:
            found.append((placement_type, label, images[0]))
    if not found:
        fail(f"creative asset upload is on, but {creative_dir} has no header or search results image")
    return found


def library_images(asc: asc_cli.Asc, library_id: str) -> list[dict[str, Any]]:
    return rows(
        call(asc, "asset-library", "images", "list", "--library-id", library_id, "--category", "CREATIVE_ASSETS", "--paginate")
    )


def library_image_for(images: list[dict[str, Any]], path: Path) -> dict[str, Any] | None:
    """The newest usable library image uploaded from this exact file (name and size)."""
    size = path.stat().st_size
    matches = [
        image
        for image in images
        if attrs(image).get("fileName") == path.name
        and attrs(image).get("fileSize") == size
        and attrs(image).get("state") not in CREATIVE_DEAD_STATES
    ]
    rejected = [
        image
        for image in images
        if attrs(image).get("fileName") == path.name
        and attrs(image).get("fileSize") == size
        and attrs(image).get("state") == "REJECTED"
    ]
    if not matches and rejected:
        fail(
            f"App Review rejected {path.name}; replace the image (a new file name) and re-run. "
            f"Details: {json.dumps(attrs(rejected[0]).get('stateDetails'))}"
        )
    return max(matches, key=lambda image: attrs(image).get("createdDate") or "") if matches else None


def sync_creative_assets(
    asc: asc_cli.Asc,
    *,
    app_id: str,
    version_id: str,
    locale: str,
    creative_dir: Path,
    editable: bool,
) -> dict[str, str]:
    """Put the repository's header and search results images on the version.

    An image is uploaded to the Asset Library once (matched by file name and size)
    and reviewed on its own. Only approved images are placed, because a version
    that is already approved only takes approved assets; one that is still in
    review or not yet submitted is placed on a later run. Placements change only
    while the version is editable. Returns placement type -> outcome.
    """
    sources = creative_sources(creative_dir)
    library_id = (data(call(asc, "asset-library", "view", "--app", app_id)) or {}).get("id")
    if not library_id:
        fail(f"App Store Connect returned no Asset Library for app {app_id}")
    images = library_images(asc, library_id)
    version_loc = version_localization(asc, version_id, locale)
    outcomes: dict[str, str] = {}
    to_review: list[tuple[str, dict[str, Any]]] = []
    for placement_type, label, path in sources:
        image = library_image_for(images, path)
        if image is None:
            if not editable:
                fail(f"cannot upload the {label} image while the version waits for review")
            # asc waits for processing and prints a receipt (imageId, ready, state).
            receipt = call(asc, "asset-library", "images", "upload", "--library-id", library_id, "--file", str(path))
            if not receipt.get("imageId") or not receipt.get("ready"):
                fail(f"Apple did not finish processing the {label} image {path.name}: {json.dumps(receipt)}")
            image = {"id": receipt["imageId"], "attributes": {"fileName": path.name, "state": receipt.get("state")}}
            print(f"  uploaded {path.name} to the Asset Library ({image['id']})")
        state = attrs(image).get("state") or ""
        if state in CREATIVE_UNSUBMITTED_STATES or not state:
            if not editable:
                fail(
                    f"cannot send the {label} image {path.name} to App Review while the version waits for "
                    "review; re-run once the version can be edited, or submit it in App Store Connect"
                )
            to_review.append((label, image))
            outcomes[placement_type] = "submitted for review"
            continue
        if state in CREATIVE_PENDING_STATES:
            outcomes[placement_type] = f"in App Review ({state}); placed on a later run"
            print(f"  {label}: {path.name} is {state}; it is placed once App Review approves it")
            continue
        if state != "APPROVED":
            fail(f"the {label} image {path.name} is {state}; resolve it in App Store Connect")
        current = rows(
            call(
                asc, "localizations", "placements", "list", "--localization-id", version_loc["id"],
                "--placement-type", placement_type, "--include", "image",
            )
        )
        if any(related_id(row, "image") == image["id"] for row in current):
            outcomes[placement_type] = "already placed"
            print(f"  {label}: {path.name} is already on the product page")
            continue
        if not editable:
            # Approval can land between a submit and a rerun; that is not a
            # mismatch, so the rerun passes and placement waits for an editable version.
            outcomes[placement_type] = "approved; placed once the version can be edited"
            print(f"  {label}: {path.name} is approved; it is placed on a later run, once the version can be edited")
            continue
        if current:
            call(
                asc, "localizations", "placements", "swap", "--localization-id", version_loc["id"],
                "--image-id", image["id"], "--placement-type", placement_type, "--placement-id", current[0]["id"],
                "--confirm",
            )
        else:
            call(
                asc, "localizations", "placements", "create", "--localization-id", version_loc["id"],
                "--image-id", image["id"], "--placement-type", placement_type, "--placement-group", "DEFAULT_PROFILE",
            )
        outcomes[placement_type] = "placed"
        print(f"  {label}: placed {path.name} on the product page")
    if to_review:
        submit_creative_review(asc, app_id, to_review)
    return outcomes


def submit_creative_review(asc: asc_cli.Asc, app_id: str, images: list[tuple[str, dict[str, Any]]]) -> str:
    """Send not-yet-reviewed creative images to App Review in a submission of their own.

    A draft an earlier attempt left behind holding only some of these images
    (or nothing yet) is finished instead of starting another one.
    """
    wanted = {image["id"] for _, image in images}
    submission_id = None
    for draft in draft_submission_ids(asc, app_id):
        held = {related_id(item, "appAssetLibraryImage") for item in submission_items(asc, draft)}
        if held <= wanted:
            submission_id = draft
            print(f"  finishing creative review submission {draft} from an earlier attempt")
            break
    if submission_id is None:
        submission = data(call(asc, "review", "submissions-create", "--app", app_id, "--platform", PLATFORM)) or {}
        submission_id = submission.get("id")
    if not submission_id:
        fail("asc did not report the new review submission's id")
    for label, image in images:
        call(
            asc, "review", "items-add", "--submission", submission_id, "--item-type", "appAssetLibraryImages",
            "--item-id", image["id"], "--if-exists", "skip",
        )
        print(f"  {label}: {attrs(image).get('fileName')} added to creative review submission {submission_id}")
    items = submission_items(asc, submission_id)
    unexpected = [item["id"] for item in items if related_id(item, "appAssetLibraryImage") not in wanted]
    if unexpected or len(items) != len(images):
        fail(f"review submission {submission_id} holds unexpected items {unexpected}; not submitting it")
    call(asc, "review", "submissions-submit", "--id", submission_id, "--confirm")
    print(f"  submitted {len(images)} creative image(s) for App Review ({submission_id})")
    return submission_id


def intended_product_ids() -> set[str]:
    """Product IDs the release is allowed to submit, from the canonical catalog."""
    catalog = json.loads((ROOT / "store" / "catalog" / "products.json").read_text(encoding="utf-8"))
    ids: set[str] = set()
    for group in ("subscriptions", "consumables", "tips"):
        for item in catalog.get(group) or []:
            pid = item.get("id")
            if isinstance(pid, str) and pid:
                ids.add(pid)
    return ids


class ProductSubmitError(Exception):
    """A required product could not be added to App Review."""


class ProductSubmitResult:
    """Outcome of attaching products to a review submission."""

    def __init__(
        self,
        submission_id: str,
        attached: int,
        added_items: bool,
        has_products: bool = False,
        allowed_versions: set[str] | None = None,
    ) -> None:
        self.submission_id = submission_id
        # Every version of every catalog product: the only product items a
        # draft may hold when it is submitted.
        self.allowed_versions = allowed_versions or set()
        # Intended products the draft now holds (attached now or by an earlier run).
        self.attached = attached
        self.added_items = added_items
        # True when the draft holds intended products, so a catch-up retry can
        # still submit the draft even when nothing new was attached.
        self.has_products = has_products


def draft_submission_ids(asc: asc_cli.Asc, app_id: str) -> list[str]:
    payload = call(
        asc, "review", "submissions-list", "--app", app_id, "--platform", PLATFORM, "--state", "READY_FOR_REVIEW",
        "--paginate",
    )
    return [row["id"] for row in rows(payload)]


def find_draft_submission(asc: asc_cli.Asc, app_id: str, version_id: str | None = None) -> str | None:
    """The app's READY_FOR_REVIEW draft to use for the version and products, if there is one.

    The draft already holding version_id wins. Otherwise only a draft holding no
    app version is reused, so another version's draft is never touched. A draft
    holding creative images belongs to their own review and is skipped.
    """
    drafts = []
    for submission_id in draft_submission_ids(asc, app_id):
        items = submission_items(asc, submission_id)
        if not any(related_id(item, "appAssetLibraryImage") for item in items):
            drafts.append((submission_id, {related_id(item, "appStoreVersion") for item in items} - {None, ""}))
    if version_id:
        for submission_id, versions in drafts:
            if version_id in versions:
                return submission_id
    for submission_id, versions in drafts:
        if not versions:
            return submission_id
    return None


def create_draft_submission(asc: asc_cli.Asc, app_id: str) -> str:
    created = data(call(asc, "review", "submissions-create", "--app", app_id, "--platform", PLATFORM)) or {}
    if not created.get("id"):
        fail("asc did not report the new review submission's id")
    return created["id"]


def get_or_create_draft_submission(asc: asc_cli.Asc, app_id: str, version_id: str | None = None) -> str:
    return find_draft_submission(asc, app_id, version_id) or create_draft_submission(asc, app_id)


ITEM_RELATIONSHIPS = ("appStoreVersion", "subscriptionVersion", "inAppPurchaseVersion", "appAssetLibraryImage")


def submission_items(asc: asc_cli.Asc, submission_id: str) -> list[dict[str, Any]]:
    """The submission's items with their related ids (asc asks for them explicitly)."""
    return rows(
        call(
            asc, "review", "items-list", "--submission", submission_id, "--include", ",".join(ITEM_RELATIONSHIPS),
            "--paginate",
        )
    )


def draft_item_version_ids(asc: asc_cli.Asc, submission_id: str) -> set[str]:
    """The app, subscription and in-app purchase version ids already in a draft."""
    ids: set[str] = set()
    for item in submission_items(asc, submission_id):
        for name in ITEM_RELATIONSHIPS[:3]:
            found = related_id(item, name)
            if found:
                ids.add(found)
    return ids


def draft_holds_app_version(asc: asc_cli.Asc, submission_id: str) -> bool:
    return any(related_id(item, "appStoreVersion") for item in submission_items(asc, submission_id))


def current_version_id(versions: list[dict[str, Any]]) -> str | None:
    """The highest-numbered version (App Store Connect allows one in flight per product)."""
    numbered = [v for v in versions if attrs(v).get("version") is not None]
    if not numbered:
        return versions[0]["id"] if versions else None
    return max(numbered, key=lambda v: int(attrs(v)["version"]))["id"]


def attach_products(
    asc: asc_cli.Asc,
    app_id: str,
    *,
    submission_id: str | None,
    intended_ids: set[str] | None = None,
) -> ProductSubmitResult:
    """Add the catalog's Ready-to-Submit subscriptions and in-app purchases to a draft.

    Subscriptions attach through their current version; a version left
    DEVELOPER_REJECTED by an earlier submission is attached again. In-app
    purchases attach through their current version the same way. Only products
    in store/catalog/products.json are considered, so an unrelated
    Ready-to-Submit product is never dragged into a release. Nothing reaches App
    Review until the caller submits the draft. With submission_id None, an
    existing draft is reused, and a new one is created only when a product has to
    be added, so a rerun with nothing to send leaves no empty draft behind.
    """
    if intended_ids is None:
        intended_ids = intended_product_ids()
    if not intended_ids:
        print("  catalog has no products to submit")
        return ProductSubmitResult(submission_id or "", 0, False)
    if submission_id is None:
        submission_id = find_draft_submission(asc, app_id)
    # A retry reuses the same draft: skip what is already attached.
    already = draft_item_version_ids(asc, submission_id) if submission_id else set()
    attached = 0
    added = False
    failures: list[str] = []

    candidates: list[tuple[str, str, str, str, list[dict[str, Any]]]] = []
    allowed: set[str] = set()
    for sub in rows(call(asc, "subscriptions", "list", "--app", app_id, "--paginate")):
        a = attrs(sub)
        if a.get("productId") not in intended_ids:
            continue
        versions = rows(call(asc, "subscriptions", "versions", "list", "--subscription-id", sub["id"], "--paginate"))
        allowed |= {v["id"] for v in versions}
        if a.get("state") in SUBMITTABLE_PRODUCT_STATES:
            candidates.append(("subscription", "subscriptionVersions", a.get("name") or sub["id"], a["productId"], versions))
    for iap in rows(call(asc, "iap", "list", "--app", app_id, "--paginate")):
        a = attrs(iap)
        if a.get("productId") not in intended_ids:
            continue
        versions = rows(call(asc, "iap", "versions", "list", "--iap-id", iap["id"], "--paginate"))
        allowed |= {v["id"] for v in versions}
        if a.get("state") == "READY_TO_SUBMIT":
            candidates.append(("in-app purchase", "inAppPurchaseVersions", a.get("name") or iap["id"], a["productId"], versions))

    for kind, item_type, name, pid, versions in candidates:
        version_id = current_version_id(versions)
        if not version_id:
            failures.append(f"{kind} {name} ({pid}): no version to submit")
            continue
        if version_id in already:
            attached += 1
            print(f"  {kind} {name}: already attached (idempotent)")
            continue
        if submission_id is None:
            submission_id = create_draft_submission(asc, app_id)
        try:
            asc.run(
                "review", "items-add", "--submission", submission_id, "--item-type", item_type, "--item-id", version_id,
                "--if-exists", "skip",
            )
        except asc_cli.AscError as exc:
            failures.append(f"{kind} {name} ({pid}): {exc}")
            continue
        attached += 1
        added = True
        print(f"  {kind} {name}: attached to review submission")
    print(f"  in-app purchases / subscriptions in the draft: {attached}")
    if failures:
        raise ProductSubmitError(
            "these required products were not added to App Review: "
            + "; ".join(failures)
            + ". Resolve them in App Store Connect and rerun the release."
        )
    return ProductSubmitResult(submission_id or "", attached, added, attached > 0, allowed)


def check_draft_items(
    asc: asc_cli.Asc, submission_id: str, *, version_id: str | None, allowed_products: set[str]
) -> None:
    """Refuse to submit a draft holding anything but this version and catalog products.

    A reused draft can hold items added by hand or by another tool; they must
    not ride along into App Review.
    """
    unexpected = []
    items = submission_items(asc, submission_id)
    if version_id and not any(related_id(item, "appStoreVersion") == version_id for item in items):
        fail(f"review submission {submission_id} does not hold App Store version {version_id}; not submitting it")
    for item in items:
        app_version = related_id(item, "appStoreVersion")
        product = related_id(item, "subscriptionVersion") or related_id(item, "inAppPurchaseVersion")
        if app_version and app_version == version_id:
            continue
        if product and not app_version and product in allowed_products:
            continue
        unexpected.append(item.get("id"))
    if unexpected:
        fail(
            f"review submission {submission_id} holds items this release did not choose ({', '.join(map(str, unexpected))}); "
            "remove them in App Store Connect and rerun"
        )


def submit_draft(asc: asc_cli.Asc, submission_id: str) -> None:
    call(asc, "review", "submissions-submit", "--id", submission_id, "--confirm")
    print(f"  submitted review submission {submission_id}")


def add_version_to_draft(asc: asc_cli.Asc, version_id: str, version_state: str, *, submission_id: str) -> None:
    # READY_FOR_REVIEW means the version is already held by a draft submission.
    if version_state == "READY_FOR_REVIEW" or version_id in draft_item_version_ids(asc, submission_id):
        return
    call(
        asc, "review", "items-add", "--submission", submission_id, "--item-type", "appStoreVersions",
        "--item-id", version_id, "--if-exists", "skip",
    )


def verify_build(asc: asc_cli.Asc, build_id: str, version_string: str, build_number: str) -> None:
    """Re-read the build and refuse anything but this run's processed build."""
    payload = call(asc, "builds", "list", "--app", ASC_APP_ID, "--build-number", build_number, "--version",
                   version_string, "--platform", PLATFORM, "--processing-state", "all", "--include", "preReleaseVersion")
    included = {(row.get("type"), row.get("id")): row for row in (payload or {}).get("included") or []}
    build = next((row for row in rows(payload) if row.get("id") == build_id), None)
    problems = []
    if build is None:
        problems.append("not listed for this app, version and build number")
        a: dict[str, Any] = {}
        pre: dict[str, Any] = {}
    else:
        a = attrs(build)
        pre = attrs(included.get(("preReleaseVersions", related_id(build, "preReleaseVersion"))))
    if build is not None and a.get("version") != build_number:
        problems.append(f"build number {a.get('version')!r}")
    if build is not None and a.get("processingState") != "VALID":
        problems.append(f"processing state {a.get('processingState')!r}")
    if a.get("expired"):
        problems.append("expired")
    if build is not None and (pre.get("version") != version_string or pre.get("platform") != PLATFORM):
        problems.append(f"version {pre.get('platform')} {pre.get('version')!r}")
    if problems:
        fail(
            f"build {build_id} is not {version_string} ({build_number}), VALID and unexpired: " + ", ".join(problems)
        )


def attached_build_id(asc: asc_cli.Asc, version_id: str) -> str | None:
    payload = call(asc, "versions", "view", "--version-id", version_id, "--include", "build")
    return related_id(data(payload) or {}, "build")


def confirm_selected_build(asc: asc_cli.Asc, version_id: str, build_id: str) -> None:
    current = attached_build_id(asc, version_id)
    if current != build_id:
        fail(f"App Store version {version_id} has build {current or 'none'} selected, expected {build_id}; not submitting")


def select_build(asc: asc_cli.Asc, version_id: str, build_id: str, version_string: str, build_number: str) -> None:
    """Explicitly select this run's build for the version, then read it back."""
    verify_build(asc, build_id, version_string, build_number)
    call(asc, "versions", "attach-build", "--version-id", version_id, "--build-id", build_id)
    confirm_selected_build(asc, version_id, build_id)
    print(f"  selected build {build_number} ({build_id}) for version {version_string}")


def set_release_type(asc: asc_cli.Asc, version_id: str, *, public_release: bool) -> None:
    release_type = RELEASE_TYPE_PUBLIC if public_release else RELEASE_TYPE_MANUAL
    call(asc, "versions", "update", "--version-id", version_id, "--release-type", release_type)
    print(
        "  release type: "
        + ("release automatically after approval" if public_release else "manual release after approval")
    )


class _ScriptedAsc:
    """Offline asc stand-in for the dry-run self-check: answers by command prefix."""

    def __init__(self, answers: dict[tuple[str, ...], Any]) -> None:
        self.answers = answers
        self.calls: list[tuple[str, ...]] = []

    def run(self, *args: str, **_: Any) -> Any:
        self.calls.append(args)
        for prefix, answer in sorted(self.answers.items(), key=lambda kv: -len(kv[0])):
            if args[: len(prefix)] == prefix:
                return answer(args) if callable(answer) else answer
        if args[:2] in {("review", "items-add"), ("review", "submissions-submit")}:
            return {"data": {"id": "ITEM"}}
        raise AssertionError(f"unexpected asc call {args}")


def dry_run_self_check() -> None:
    """Exercise product selection and the submit order offline so dry-run covers them."""
    pid = "com.apoorvdarshan.calorietracker"
    subs = [
        {"id": f"S{i}", "attributes": {"name": n, "productId": f"{pid}.{n}", "state": s}}
        for i, (n, s) in enumerate(
            [("plus.monthly", "DEVELOPER_REJECTED"), ("plus.yearly", "READY_TO_SUBMIT"), ("legacy", "READY_TO_SUBMIT")]
        )
    ]
    iaps = [
        {"id": "IAP1", "attributes": {"name": "Credits 50", "productId": f"{pid}.credits.50", "state": "READY_TO_SUBMIT"}},
        {"id": "IAP2", "attributes": {"name": "Tip", "productId": f"{pid}.tip.snack", "state": "APPROVED"}},
    ]
    versions = {"data": [{"id": "Vold", "attributes": {"version": 1}}, {"id": "Vnew", "attributes": {"version": 2}}]}
    fake = _ScriptedAsc(
        {
            ("review", "items-list"): {"data": [{"id": "ITEM0", "relationships": {"subscriptionVersion": {"data": {"id": "S1v"}}}}]},
            ("subscriptions", "list"): {"data": subs},
            ("subscriptions", "versions", "list", "--subscription-id", "S0"): versions,
            ("subscriptions", "versions", "list", "--subscription-id", "S1"): {"data": [{"id": "S1v", "attributes": {"version": 1}}]},
            ("iap", "list"): {"data": iaps},
            ("iap", "versions", "list"): {"data": [{"id": "IAPv", "attributes": {"version": 1}}]},
        }
    )
    intended = {f"{pid}.plus.monthly", f"{pid}.plus.yearly", f"{pid}.credits.50", f"{pid}.tip.snack"}
    result = attach_products(fake, "APP", submission_id="SUB1", intended_ids=intended)  # type: ignore[arg-type]
    added = [c for c in fake.calls if c[:2] == ("review", "items-add")]
    assert [c[c.index("--item-id") + 1] for c in added] == ["Vnew", "IAPv"], f"wrong items added: {added}"
    assert result.attached == 3 and result.has_products, "already-attached product must still count"
    assert not [c for c in fake.calls if "S2" in c], "a product outside the catalog was considered"
    assert not [c for c in fake.calls if c[:2] == ("review", "submissions-submit")], "attaching must not submit"
    print("  dry-run self-check: product submission selection OK")


def version_key(version_string: str) -> tuple[int, ...] | None:
    """7.2.1 -> (7, 2, 1), padded to three parts; None when it is not numeric."""
    if not re.fullmatch(r"[0-9]+(\.[0-9]+){0,2}", version_string or ""):
        return None
    parts = [int(part) for part in version_string.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def ensure_ios_app_store_version(
    asc: asc_cli.Asc, *, bundle_id: str, expected_app_id: str, version_string: str
) -> None:
    """Create the App Store version for this release when it does not exist yet.

    An existing version with this number is left as it is (the read-only
    preflight then checks its state). Nothing is created when another version is
    still on its way to the store, or when this number is not newer than every
    existing version; the created version is read back before the run continues.
    """
    wanted = version_key(version_string)
    if wanted is None:
        fail(f"version {version_string!r} must look like 7.2 or 7.2.1")
    app_id = find_app(asc, bundle_id, expected_app_id)
    versions = list_ios_app_store_versions(asc, app_id)
    existing = [row for row in versions if attrs(row).get("versionString") == version_string]
    if len(existing) > 1:
        fail(f"ambiguous App Store versions for {version_string!r} on IOS — got {len(existing)} records")
    if existing:
        state = attrs(existing[0]).get("appStoreState") or ""
        print(f"App Store version {version_string} already exists ({state}); nothing to create")
        return
    problems: list[str] = []
    for row in versions:
        other = attrs(row).get("versionString") or ""
        state = attrs(row).get("appStoreState") or ""
        if state not in FINISHED_VERSION_STATES:
            problems.append(
                f"version {other!r} is still {state or 'in an unknown state'}; release or remove it "
                f"in App Store Connect before {version_string} can be created"
            )
        other_key = version_key(other)
        if other_key is not None and other_key >= wanted:
            problems.append(f"version {version_string} is not newer than the existing version {other}")
    if problems:
        fail(f"not creating App Store version {version_string} (nothing was changed):\n  " + "\n  ".join(problems))
    response = call(asc, "versions", "create", "--app", app_id, "--version", version_string, "--platform", PLATFORM)
    new_id = (data(response) or {}).get("id") or "unknown id"
    created = [row for row in list_ios_app_store_versions(asc, app_id) if attrs(row).get("versionString") == version_string]
    if len(created) != 1:
        fail(
            f"created App Store version {version_string} ({new_id}), but reading it back found "
            f"{len(created)} matching records; check App Store Connect, then re-run (a version "
            "that exists by then is reused, never created twice)"
        )
    state = attrs(created[0]).get("appStoreState") or ""
    print(f"created App Store version {version_string} ({state or 'state not reported yet'})")


def validate_local_inputs(
    *,
    upload_listing: bool,
    upload_screenshots: bool,
    metadata_dir: Path,
    screenshots_dir: Path,
    locale: str,
    upload_whats_new: bool = False,
    upload_creative: bool = False,
    creative_dir: Path | None = None,
) -> None:
    loc_dir = metadata_dir / "ios" / locale
    if (upload_listing or upload_whats_new) and not loc_dir.is_dir():
        fail(f"metadata dir missing: {loc_dir}")
    if upload_whats_new and not read_text(loc_dir / WHATS_NEW_FIELD[1]):
        fail(f"What's New upload is on, but {loc_dir / WHATS_NEW_FIELD[1]} is missing or empty")
    if upload_screenshots:
        staged_screenshot_sets(screenshots_dir)
    if upload_creative:
        creative_sources(creative_dir or ROOT / "store" / "creative" / "ios")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata-dir", type=Path, default=ROOT / "store" / "metadata", help="Prepared listing + what's new tree")
    parser.add_argument(
        "--screenshots-dir",
        type=Path,
        default=ROOT / "store" / "metadata" / "screenshots" / "ios",
        help="Staged screenshots, one folder per set: " + ", ".join(s[0] for s in SCREENSHOT_SETS),
    )
    parser.add_argument(
        "--creative-dir",
        type=Path,
        default=ROOT / "store" / "creative" / "ios",
        help="Product page header and search results images: " + ", ".join(s[0] for s in CREATIVE_SLOTS),
    )
    parser.add_argument("--locale", default="en-US")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--version", help="Marketing version from release tag (e.g. 1.2.3 when tag is v1.2.3)")
    parser.add_argument("--build-id", help="App Store Connect id of the build uploaded by this run (required to submit)")
    parser.add_argument("--build-number", help="CFBundleVersion of the build uploaded by this run (required to submit)")
    parser.add_argument("--dry-run", action="store_true", help="Validate flags and local files only — no asc calls")
    parser.add_argument(
        "--create-version", action="store_true", help="Create the App Store version for --version when it is missing (CREATE_IOS_VERSION)"
    )
    args = parser.parse_args()

    # find_app() checks the pinned app's bundle id, so only this app is accepted.
    if args.bundle_id != DEFAULT_BUNDLE_ID:
        fail(f"this publisher only supports the Fud AI iOS bundle ({DEFAULT_BUNDLE_ID})")

    if args.create_version:
        if not truthy("CREATE_IOS_VERSION"):
            print("App Store version creation skipped — CREATE_IOS_VERSION is off")
            return
        if not args.version:
            fail("--create-version needs --version (the marketing version from the tag)")
        if version_key(args.version) is None:
            fail(f"version {args.version!r} must look like 7.2 or 7.2.1")
        if args.dry_run:
            print(f"ASC dry-run — would create App Store version {args.version} if it is missing")
            return
        ensure_ios_app_store_version(
            asc_from_environment(), bundle_id=args.bundle_id, expected_app_id=ASC_APP_ID, version_string=args.version
        )
        return

    do_listing = truthy("UPLOAD_LISTING")
    do_whats_new = truthy("UPLOAD_WHATS_NEW")
    do_screenshots = truthy("UPLOAD_SCREENSHOTS")
    do_creative = truthy("UPLOAD_CREATIVE_ASSETS")
    do_submit = truthy("SUBMIT_IOS_REVIEW")
    do_public = truthy("PUBLIC_RELEASE")

    if not (do_listing or do_whats_new or do_screenshots or do_creative or do_submit):
        print(
            "ASC release skipped — UPLOAD_LISTING / UPLOAD_WHATS_NEW / UPLOAD_SCREENSHOTS / "
            "UPLOAD_CREATIVE_ASSETS / SUBMIT_IOS_REVIEW are off"
        )
        return
    if do_public and not do_submit:
        fail("PUBLIC_RELEASE only applies when SUBMIT_IOS_REVIEW is on")
    if do_submit and not (args.build_id and args.build_number):
        fail("submitting needs --build-id and --build-number for the build uploaded by this run; an older build is never substituted")

    validate_local_inputs(
        upload_listing=do_listing,
        upload_screenshots=do_screenshots,
        metadata_dir=args.metadata_dir,
        screenshots_dir=args.screenshots_dir,
        locale=args.locale,
        upload_whats_new=do_whats_new,
        upload_creative=do_creative,
        creative_dir=args.creative_dir,
    )

    if args.dry_run:
        print("ASC dry-run — local inputs OK; no asc calls")
        print(
            f"  bundle={args.bundle_id} listing={do_listing} whats_new={do_whats_new} screenshots={do_screenshots} "
            f"creative={do_creative} submit={do_submit} public_release={do_public}"
        )
        if do_submit:
            dry_run_self_check()
        return

    asc = asc_from_environment()
    if not args.version:
        fail("--version is required for live ASC calls (pass marketing version from tag)")

    app_id = find_app(asc, args.bundle_id)
    version = get_ios_app_store_version(asc, app_id, args.version)
    version_id = version["id"]
    state = attrs(version).get("appStoreState") or ""
    print(f"ASC app={app_id} version={args.version} id={version_id} state={state}")
    edits_text = do_listing or do_whats_new
    text_parts = " + ".join(name for name, on in (("listing", do_listing), ("What's New", do_whats_new)) if on)
    # WAITING_FOR_REVIEW: nothing can change, so a re-run (the submit landed but
    # the job failed afterwards) only checks that App Store Connect already
    # matches. READY_FOR_REVIEW (a draft submission, e.g. after a failed submit)
    # keeps text editable but locks screenshots.
    waiting = state in COMPARE_ONLY_VERSION_STATES
    screenshots_locked = state == "READY_FOR_REVIEW" or waiting

    # Decide what each step may do before anything is written.
    if edits_text and not waiting and state not in TEXT_EDITABLE_VERSION_STATES:
        fail(
            f"version {args.version!r} is not editable for listing/What's New (state={state}); "
            f"expected one of: {', '.join(sorted(TEXT_EDITABLE_VERSION_STATES))}"
        )
    if (do_screenshots or do_creative) and not screenshots_locked and state not in EDITABLE_VERSION_STATES:
        fail(
            f"version {args.version!r} is not editable for screenshots or creative assets (state={state}); "
            f"expected one of: {', '.join(sorted(EDITABLE_VERSION_STATES))}"
        )
    if do_submit and not waiting and state not in SUBMITTABLE_VERSION_STATES:
        fail(f"version {args.version!r} cannot be submitted for review (state={state})")
    # Pick and check the version's draft before any write (text, screenshots,
    # images or the build), so a run that has to stop here changes nothing.
    submission_id: str | None = None
    if do_submit and not waiting:
        submission_id = find_draft_submission(asc, app_id, version_id)
        if state == "READY_FOR_REVIEW" and (
            submission_id is None
            or not any(related_id(item, "appStoreVersion") == version_id for item in submission_items(asc, submission_id))
        ):
            fail(
                f"version {args.version} is READY_FOR_REVIEW, but no draft review submission holds it; "
                "remove the version from its submission in App Store Connect and rerun"
            )

    # Read-only comparisons first, so a mismatch stops the run before any write.
    if do_screenshots and screenshots_locked:
        print(f"checking ASC screenshots (locked while the version is {state})…")
        upload_screenshots(
            asc, app_id=app_id, version_id=version_id, locale=args.locale, screenshots_dir=args.screenshots_dir, editable=False
        )
    if edits_text and waiting:
        print(f"checking ASC {text_parts} (locked while the version is {state})…")
        upload_listing(
            asc, version_id=version_id, locale=args.locale, metadata_dir=args.metadata_dir,
            include_listing=do_listing, include_whats_new=do_whats_new, editable=False,
        )

    if edits_text and not waiting:
        print(f"uploading ASC {text_parts}…")
        upload_listing(
            asc, version_id=version_id, locale=args.locale, metadata_dir=args.metadata_dir,
            include_listing=do_listing, include_whats_new=do_whats_new,
        )
    if do_screenshots and not screenshots_locked:
        print("uploading ASC screenshots…")
        upload_screenshots(asc, app_id=app_id, version_id=version_id, locale=args.locale, screenshots_dir=args.screenshots_dir)
    if do_creative:
        print("syncing ASC product page header and search results images…")
        sync_creative_assets(
            asc, app_id=app_id, version_id=version_id, locale=args.locale, creative_dir=args.creative_dir,
            editable=not screenshots_locked,
        )

    if waiting:
        if do_submit:
            # A rerun after a successful submit: only accept it if review holds
            # exactly this run's build.
            confirm_selected_build(asc, version_id, args.build_id)
            print("ASC submit skipped — version already WAITING_FOR_REVIEW (idempotent)")
            # Products that missed the version's submission go out in a draft of
            # their own. Only a product-only draft is submitted, so an unrelated
            # app version never ships from here; no draft is created when there
            # is nothing to send.
            try:
                result = attach_products(asc, app_id, submission_id=None)
            except ProductSubmitError as exc:
                fail(str(exc))
            draft = result.submission_id
            if result.has_products:
                if draft_holds_app_version(asc, draft):
                    fail("refusing to submit a draft that contains an app version; remove it in App Store Connect and rerun")
                check_draft_items(asc, draft, version_id=None, allowed_products=result.allowed_versions)
                submit_draft(asc, draft)
        print("ASC release step finished")
        return

    if do_submit:
        print("selecting this run's build…")
        select_build(asc, version_id, args.build_id, args.version, args.build_number)
        set_release_type(asc, version_id, public_release=do_public)
        print("adding in-app purchases / subscriptions to the review submission…")
        submission_id = submission_id or create_draft_submission(asc, app_id)
        try:
            # A first-time subscription must ship with the version, so a failed
            # required product blocks the whole submission.
            result = attach_products(asc, app_id, submission_id=submission_id)
        except ProductSubmitError as exc:
            fail(f"{exc} Not submitting the app version.")
        add_version_to_draft(asc, version_id, state, submission_id=submission_id)
        # Recheck immediately before anything goes to App Review: the selection
        # must still be this run's processed build.
        verify_build(asc, args.build_id, args.version, args.build_number)
        confirm_selected_build(asc, version_id, args.build_id)
        check_draft_items(asc, submission_id, version_id=version_id, allowed_products=result.allowed_versions)
        print("submitting for App Store review…")
        submit_draft(asc, submission_id)
        print(f"  {result.attached} product(s) went out with the version")

    print("ASC release step finished")


if __name__ == "__main__":
    main()
