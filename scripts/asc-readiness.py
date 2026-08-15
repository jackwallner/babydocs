#!/usr/bin/env python3
"""Report what the App Store Connect record still needs before submission.

Read-only. Run it before a submission pass to see every gap at once rather than
discovering them in the web UI one blocked field at a time.

    python3 scripts/asc-readiness.py

This exists because the gaps that sink a first submission are the ones nothing
in the repo mentions. The build, the metadata and the IAP products all lived in
git and were fine; the age-rating declaration was empty, no build was attached
to the 1.0 draft, and there were no screenshots at all, none of which is visible
from a checkout. A drift check is the only thing that sees the record itself.

Three things it deliberately checks that a "does the field have a value" script
would not:

  * **Which** build is attached, not merely that one is. A draft version keeps
    whatever build was attached first, so an app that has uploaded five more
    since then still reads as "a build is attached" while pointing at a binary
    that predates half the description.
  * That the free/paid split in the description matches the split in the
    binary. The gate lives in `SummaryShareControl` and `DocumentsView`; a
    description that gives away something the app charges for is a refund
    request and a metadata-accuracy rejection, and it drifts silently because
    nothing recompiles when a .txt file changes.
  * That the URLs resolve. App Review rejects on a dead privacy URL, and these
    are served from a static host that knows nothing about this repo.

Two things it cannot check, because Apple does not expose them in the public
API at all:

  * attaching the **first** IAP to a version, which is web-UI only. See the
    `ios-dev` skill for the sequence.
  * whether the screenshots show the build that is attached.
"""
from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_lib import ASC  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"

BUNDLE_ID = "com.jackwallner.babydocs"
EXPECTED_NAME = "Baby Docs: Newborn Paperwork"
EXPECTED_PRIMARY_CATEGORY = "PRODUCTIVITY"
EXPECTED_SECONDARY_CATEGORY = "UTILITIES"
# One 6.7-inch set covers the sizes a submission needs. The exact count is
# asserted rather than "more than zero": a fastlane retry double-uploads, and a
# store page with each frame twice looks like a bug in the app.
EXPECTED_SCREENSHOTS = {"APP_IPHONE_67": 6}
# Weekly only. The yearly exists to make the comparison legible and is not the
# CTA, so it carries no intro offer. See CLAUDE.md on why the trial is 3 days.
EXPECTED_TRIAL_TERRITORIES = 175
EXPECTED_TRIAL_PRODUCT = "com.jackwallner.babydocs.pro.weekly"

# What the binary actually charges for. Every one is a real gate in the shipping
# code (`SummaryShareControl`, `DocumentsView.addButton`, `ChildrenView`), and
# both the description and the review notes have to agree with all four.
#
# Two vocabularies, because they are written for different readers: the store
# copy sells "the document vault", the review notes tell a reviewer which tab to
# tap. Matching on either is what keeps this a check on meaning rather than on
# wording.
PAID_FEATURES = {
    "further children": ("further children", "additional children"),
    "the vault": ("vault", "Documents tab"),
    "the summary": ("summary",),
    "the employer packet": ("employer packet",),
}

ready: list[str] = []
gaps: list[str] = []


def check(label: str, value, good: bool | None = None) -> None:
    good = bool(value) if good is None else good
    (ready if good else gaps).append(f"{label}: {value}")


def url_status(url: str) -> str:
    try:
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=20) as response:
            return str(response.status)
    except urllib.error.HTTPError as error:
        return str(error.code)
    except Exception as error:  # noqa: BLE001 - any network failure is a gap
        return type(error).__name__


def editable_version(client: ASC, app_id: str) -> dict | None:
    editable = {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
    }
    for version in client.get(f"/apps/{app_id}/appStoreVersions", limit=20).get("data", []):
        if version["attributes"].get("appStoreState") in editable:
            return version
    return None


def check_description(text: str) -> None:
    check("description length", f"{len(text)} chars", 200 < len(text) <= 4000)
    # Guideline 3.1.2 wants the renewal terms on the product page as well as in
    # the binary.
    disclosure = ("renews automatically", "24 hours", "Privacy Policy", "Terms of Use")
    missing = [term for term in disclosure if term not in text]
    check(
        "subscription disclosure",
        "complete" if not missing else f"missing {', '.join(missing)}",
        not missing,
    )
    # A price here is true in at most one of 175 storefronts and goes stale on
    # every price move. The paywall discloses the real localized figure.
    check(
        "no hardcoded price",
        "clean" if not re.search(r"[$€£]\s*\d", text) else "found a currency figure",
        not re.search(r"[$€£]\s*\d", text),
    )
    check("no em dashes", "clean" if "—" not in text else "found one", "—" not in text)
    # Anything the binary gates has to sit in the sentence that says what Plus
    # adds, and nowhere in the sentence that lists what is free. Matching on the
    # whole Plus section instead would pass on the description this replaced,
    # which named the summary and the employer packet in that section while
    # calling them free.
    paragraphs = text.split("\n\n")
    adds = next((p for p in paragraphs if p.startswith("Plus adds")), "")
    free = next((p for p in paragraphs if "is free, for one child" in p), "")
    check("description names what Plus adds", "found" if adds else "MISSING", bool(adds))
    for feature, aliases in PAID_FEATURES.items():
        in_adds = any(alias in adds for alias in aliases)
        in_free = any(alias in free for alias in aliases)
        where = "paid" if in_adds else ("FREE" if in_free else "ABSENT")
        check(f"'{feature}'", where, where == "paid")
    # There is no server and there is not going to be one, so no copy may imply
    # two phones staying in step.
    sync_claims = [w for w in ("sync", "syncs", "synced", "in the cloud") if w in text.lower()]
    check("no sync claim", "clean" if not sync_claims else f"found {sync_claims}", not sync_claims)


def main() -> int:
    client = ASC()
    apps = [a for a in client.apps() if a["attributes"].get("bundleId") == BUNDLE_ID]
    if not apps:
        print(f"No app record for {BUNDLE_ID}")
        return 1
    app = apps[0]
    app_id = app["id"]
    name = app["attributes"].get("name")
    check("app record name", name, name == EXPECTED_NAME)

    info = client.get(f"/apps/{app_id}/appInfos")["data"][0]
    version = editable_version(client, app_id)
    if not version:
        print("No editable version. Nothing to report against.")
        return 1
    vid = version["id"]
    print(f"App {app_id}, version {version['attributes'].get('versionString')} "
          f"({version['attributes'].get('appStoreState')})\n")

    for relationship, expected in (
        ("primaryCategory", EXPECTED_PRIMARY_CATEGORY),
        ("secondaryCategory", EXPECTED_SECONDARY_CATEGORY),
    ):
        category = client.get_optional(f"/appInfos/{info['id']}/{relationship}").get("data")
        check(relationship, category and category["id"], bool(category) and category["id"] == expected)

    check("copyright", version["attributes"].get("copyright"))

    urls: list[str] = []
    for localization in client.get_all(f"/appInfos/{info['id']}/appInfoLocalizations"):
        attributes = localization["attributes"]
        locale = attributes.get("locale")
        localized_name = attributes.get("name") or ""
        subtitle = attributes.get("subtitle") or ""
        check(f"{locale} name", f"{len(localized_name)} chars", 24 <= len(localized_name) <= 30)
        check(f"{locale} subtitle", f"{len(subtitle)} chars", 24 <= len(subtitle) <= 30)
        privacy = attributes.get("privacyPolicyUrl")
        check(f"{locale} privacy url", privacy)
        if privacy:
            urls.append(privacy)

    for localization in client.get_all(
        f"/appStoreVersions/{vid}/appStoreVersionLocalizations"
    ):
        attributes = localization["attributes"]
        locale = attributes.get("locale")
        check_description(attributes.get("description") or "")
        keywords = attributes.get("keywords") or ""
        check(f"{locale} keywords", f"{len(keywords)} chars", 94 <= len(keywords) <= 100)
        for field in ("supportUrl", "marketingUrl"):
            value = attributes.get(field)
            check(f"{locale} {field}", value)
            if value:
                urls.append(value)

        found_types: dict[str, int] = {}
        for screenshot_set in client.get_all(
            f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets"
        ):
            display_type = screenshot_set["attributes"].get("screenshotDisplayType")
            images = client.get_all(f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots")
            found_types[display_type] = len(images)
            # An upload that failed mid-way leaves a row with no asset, and ASC
            # blocks the submit without ever saying which one.
            incomplete = [
                i for i in images
                if (i["attributes"].get("assetDeliveryState") or {}).get("state") != "COMPLETE"
            ]
            check(f"{display_type} assets delivered", f"{len(images) - len(incomplete)}/{len(images)}",
                  not incomplete)
        for display_type, expected_count in EXPECTED_SCREENSHOTS.items():
            check(f"{locale} screenshots {display_type}", found_types.get(display_type, 0),
                  found_types.get(display_type) == expected_count)

    declaration = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]["attributes"]
    # Every field null is the state a brand-new record is in, and it is the one
    # that blocks the submit while showing nothing wrong on any page.
    answered = [k for k, v in declaration.items() if v is not None]
    check("age rating declared", f"{len(answered)} fields answered", len(answered) > 10)
    check("computed age rating", info["attributes"].get("appStoreAgeRating"))

    review_detail = client.get_optional(f"/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    check("review detail", "present" if review_detail else None)
    if review_detail:
        attributes = review_detail["attributes"]
        for field in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail"):
            check(f"review {field}", "present" if attributes.get(field) else None)
        # The notes are hard-wrapped in the Fastfile heredoc, so "employer\n
        # packet" is one phrase to a reviewer and two to a substring match.
        notes = " ".join((attributes.get("notes") or "").split())
        # The notes tell the reviewer what is free. When they disagree with the
        # binary the reviewer tests the wrong thing and rejects the right app.
        missing = [
            feature for feature, aliases in PAID_FEATURES.items()
            if not any(alias in notes for alias in aliases)
        ]
        check("review notes list the paid features",
              "current" if not missing else f"missing {', '.join(missing)}", not missing)

    for group in client.get_all(f"/apps/{app_id}/subscriptionGroups"):
        for subscription in client.get_all(f"/subscriptionGroups/{group['id']}/subscriptions"):
            attributes = subscription["attributes"]
            product_id = attributes.get("productId")
            check(f"sub {product_id}", attributes.get("state"),
                  attributes.get("state") in ("READY_TO_SUBMIT", "APPROVED", "WAITING_FOR_REVIEW"))
            check(f"sub {product_id} review note", "present" if attributes.get("reviewNote") else None)
            offers = client.get_all(
                f"/subscriptions/{subscription['id']}/introductoryOffers?limit=200"
            )
            if product_id == EXPECTED_TRIAL_PRODUCT:
                check(f"sub {product_id} trial territories", len(offers),
                      len(offers) == EXPECTED_TRIAL_TERRITORIES)

    for purchase in client.get_all(f"/apps/{app_id}/inAppPurchasesV2"):
        attributes = purchase["attributes"]
        check(f"iap {attributes.get('productId')}", attributes.get("state"),
              attributes.get("state") in ("READY_TO_SUBMIT", "APPROVED", "WAITING_FOR_REVIEW"))

    build = client.get_optional(f"/appStoreVersions/{vid}/build").get("data")
    attached = None
    if build:
        attached = client.get(f"/builds/{build['id']}")["data"]["attributes"].get("version")
    check("attached build", attached)
    valid = [
        b["attributes"]["version"]
        for b in client.get_all(f"/builds?filter[app]={app_id}&limit=200")
        if b["attributes"].get("processingState") == "VALID" and not b["attributes"].get("expired")
    ]
    newest = max(valid, key=lambda v: int(v) if v.isdigit() else -1, default=None)
    if attached:
        check("attached build is the newest VALID one",
              f"attached {attached}, newest {newest}", attached == newest)
    else:
        check("builds available to attach", f"newest VALID is {newest}", bool(newest))

    price_schedule = client.get_optional(f"/apps/{app_id}/appPriceSchedule").get("data")
    check("price schedule", "present" if price_schedule else None)

    print("READY:")
    for line in ready:
        print("  +", line)
    print("\nGAPS:")
    for line in gaps or ["(none)"]:
        print("  -", line)

    print("\nURL REACHABILITY (App Review rejects on a dead privacy URL):")
    # PlanSeed.webBase points every shared plan link here, and those messages sit
    # in inboxes far longer than the build that wrote them.
    urls.append("https://jackwallner.com/ios/babydocs/plan.html")
    for url in dict.fromkeys(urls):
        status = url_status(url)
        print(f"  {'+' if status == '200' else '-'} {status}  {url}")

    print("\nNOT VISIBLE TO THE API, CHECK BY HAND:")
    print("  * the FIRST subscription and non-consumable must be added to the")
    print("    draft submission through the ASC web UI (see the ios-dev skill)")
    print("  * that the screenshots show the build that is attached")
    return 1 if gaps else 0


if __name__ == "__main__":
    raise SystemExit(main())
