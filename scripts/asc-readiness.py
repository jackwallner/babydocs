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

Two things still need a human eye:

  * performing the **first** IAP attachment, which is web-UI only. Once it has
    happened, the review-submission item audit below verifies the result.
  * whether the screenshots show the build that is attached.
"""
from __future__ import annotations

import base64
from collections import Counter
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
EXPECTED_ASC_LOCALES = {"en-US"}
EXPECTED_TERRITORIES = 175
# Weekly only. The yearly exists to make the comparison legible and is not the
# CTA, so it carries no intro offer. See CLAUDE.md on why the trial is 3 days.
EXPECTED_TRIAL_TERRITORIES = EXPECTED_TERRITORIES
EXPECTED_TRIAL_PRODUCT = "com.jackwallner.babydocs.pro.weekly"
EXPECTED_SUBSCRIPTIONS = {
    "com.jackwallner.babydocs.pro.weekly": {
        "period": "ONE_WEEK",
        "usa_price": "4.99",
        "trial": "THREE_DAYS",
        "name": "Weekly",
        "description": "For the weeks the paperwork is happening.",
    },
    "com.jackwallner.babydocs.pro.yearly": {
        "period": "ONE_YEAR",
        "usa_price": "29.99",
        "trial": None,
        "name": "Yearly",
        "description": "A year of the vault, packet and summary.",
    },
}
EXPECTED_LIFETIME_PRODUCT = "com.jackwallner.babydocs.pro.lifetime"
EXPECTED_LIFETIME_PRICE = "59.99"
EXPECTED_LIFETIME_COPY = ("Keep it forever", "Keeps the document vault for good.")
V2 = "https://api.appstoreconnect.apple.com/v2"

# What the binary actually charges for. Every one is a real gate in the shipping
# code (`SummaryShareControl`, `TaskDetailView`, `DocumentsView.addButton`,
# `PlusToolsView`, `DeadlineReminderScheduler.Options`), and both the
# description and the review notes have to agree with all of them.
#
# Two vocabularies, because they are written for different readers: the store
# copy sells "the document vault", the review notes tell a reviewer which tab to
# tap. Matching on either is what keeps this a check on meaning rather than on
# wording.
#
# **Further children left this list on purpose** and must not come back without
# the binary changing first: twins are one birth and one household, so charging
# for the second child billed the family that had the harder delivery.
PAID_FEATURES = {
    "suggested-date reminders": ("suggest", "reminders for the dates"),
    "the recommended order": ("order", "sequence", "timeline"),
    "the calendar export": ("calendar",),
    "follow-up tracking": ("follow-up tracking", "follow-ups", "chasing", "Follow-up tracking"),
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


def get_all_with_included(client: ASC, path: str, **params) -> tuple[list[dict], list[dict]]:
    """Collect paginated JSON:API data and its included records together."""
    data: list[dict] = []
    included: list[dict] = []
    page = client.get(path, **params)
    while True:
        data.extend(page.get("data", []))
        included.extend(page.get("included", []))
        next_url = (page.get("links") or {}).get("next")
        if not next_url:
            return data, included
        page = client._request("GET", next_url)


def relationship_id(resource: dict, name: str) -> str | None:
    return (
        ((resource.get("relationships") or {}).get(name, {}).get("data") or {}).get("id")
    )


def included_attributes(included: list[dict], resource_id: str | None) -> dict:
    if not resource_id:
        return {}
    return next(
        (resource.get("attributes", {}) for resource in included if resource.get("id") == resource_id),
        {},
    )


def local_metadata(path: str) -> str:
    return (META / path).read_text(encoding="utf-8").strip()


def editable_version(client: ASC, app_id: str) -> dict | None:
    editable = {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "READY_FOR_REVIEW",
        "WAITING_FOR_REVIEW",
    }
    for version in client.get(f"/apps/{app_id}/appStoreVersions", limit=20).get("data", []):
        if version["attributes"].get("appStoreState") in editable:
            return version
    return None


def review_item_type(item_id: str) -> str | None:
    try:
        padded = item_id + "=" * ((4 - len(item_id) % 4) % 4)
        return base64.urlsafe_b64decode(padded).decode().split("|")[1]
    except (IndexError, UnicodeDecodeError, ValueError):
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
    adds = next((p for p in paragraphs if p.startswith("Plus is") or p.startswith("Plus adds")), "")
    free = next((p for p in paragraphs if "is free, for every child" in p), "")
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


def check_keyword_quality(keywords: str, name: str, subtitle: str) -> None:
    words = re.findall(r"[a-z0-9]+", keywords.lower())
    duplicate_words = sorted(word for word, count in Counter(words).items() if count > 1)
    indexed_elsewhere = set(re.findall(r"[a-z0-9]+", f"{name} {subtitle}".lower()))
    overlap = sorted(set(words) & indexed_elsewhere)
    check(
        "keywords have no duplicate tokens",
        "clean" if not duplicate_words else ", ".join(duplicate_words),
        not duplicate_words,
    )
    check(
        "keywords do not repeat name or subtitle tokens",
        "clean" if not overlap else ", ".join(overlap),
        not overlap,
    )


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
    check(
        "copyright matches repo",
        "matched" if version["attributes"].get("copyright") == local_metadata("copyright.txt") else "DRIFT",
        version["attributes"].get("copyright") == local_metadata("copyright.txt"),
    )

    # Required app information, and null by default rather than defaulted, so a
    # first submission blocks on it with nothing in the repo to say why. The
    # answer is "no": every rule in the catalog is original writing about public
    # government requirements, and a link to an official page is not third-party
    # content shown inside the app. The Fastfile's submission_information says
    # the same thing, and these two are the pair that must not drift.
    rights = app["attributes"].get("contentRightsDeclaration")
    check("content rights declaration", rights or "UNSET",
          rights == "DOES_NOT_USE_THIRD_PARTY_CONTENT")

    urls: list[str] = []
    app_locales: set[str] = set()
    app_copy_by_locale: dict[str, tuple[str, str]] = {}
    for localization in client.get_all(f"/appInfos/{info['id']}/appInfoLocalizations"):
        attributes = localization["attributes"]
        locale = attributes.get("locale")
        app_locales.add(locale)
        localized_name = attributes.get("name") or ""
        subtitle = attributes.get("subtitle") or ""
        app_copy_by_locale[locale] = (localized_name, subtitle)
        check(f"{locale} name", f"{len(localized_name)} chars", 24 <= len(localized_name) <= 30)
        check(f"{locale} subtitle", f"{len(subtitle)} chars", 24 <= len(subtitle) <= 30)
        privacy = attributes.get("privacyPolicyUrl")
        check(f"{locale} privacy url", privacy)
        if privacy:
            urls.append(privacy)
        if locale == "en-US":
            for field, path, value in (
                ("name", "en-US/name.txt", localized_name),
                ("subtitle", "en-US/subtitle.txt", subtitle),
                ("privacy url", "en-US/privacy_url.txt", privacy or ""),
            ):
                expected = local_metadata(path)
                check(
                    f"{locale} {field} matches repo",
                    "matched" if value == expected else "DRIFT",
                    value == expected,
                )
    check("App Store information locales", sorted(app_locales), app_locales == EXPECTED_ASC_LOCALES)

    version_locales: set[str] = set()
    for localization in client.get_all(
        f"/appStoreVersions/{vid}/appStoreVersionLocalizations"
    ):
        attributes = localization["attributes"]
        locale = attributes.get("locale")
        version_locales.add(locale)
        check_description(attributes.get("description") or "")
        if locale == "en-US":
            for field, path in (
                ("description", "en-US/description.txt"),
                ("keywords", "en-US/keywords.txt"),
                ("promotional text", "en-US/promotional_text.txt"),
                ("support url", "en-US/support_url.txt"),
                ("marketing url", "en-US/marketing_url.txt"),
            ):
                live_value = attributes.get(
                    {"promotional text": "promotionalText", "support url": "supportUrl", "marketing url": "marketingUrl"}.get(field, field),
                    "",
                ) or ""
                expected = local_metadata(path)
                check(
                    f"{locale} {field} matches repo",
                    "matched" if live_value == expected else "DRIFT",
                    live_value == expected,
                )
        keywords = attributes.get("keywords") or ""
        check(f"{locale} keywords", f"{len(keywords)} chars", 94 <= len(keywords) <= 100)
        if locale in app_copy_by_locale:
            check_keyword_quality(keywords, *app_copy_by_locale[locale])
        promotional_text = attributes.get("promotionalText") or ""
        check(
            f"{locale} promotional text",
            f"{len(promotional_text)} chars",
            1 <= len(promotional_text) <= 170,
        )
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
            checksums = [i["attributes"].get("sourceFileChecksum") for i in images]
            check(
                f"{locale} {display_type} screenshot checksums",
                f"{len(set(checksums))}/{len(checksums)} unique",
                all(checksum for checksum in checksums) and len(set(checksums)) == len(checksums),
            )
        for display_type, expected_count in EXPECTED_SCREENSHOTS.items():
            check(f"{locale} screenshots {display_type}", found_types.get(display_type, 0),
                  found_types.get(display_type) == expected_count)
    check(
        "App Store version locales",
        sorted(version_locales),
        version_locales == EXPECTED_ASC_LOCALES,
    )

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
        notes = " ".join((attributes.get("notes") or "").split()).lower()
        # The notes tell the reviewer what is free. When they disagree with the
        # binary the reviewer tests the wrong thing and rejects the right app.
        missing = [
            feature for feature, aliases in PAID_FEATURES.items()
            if not any(alias in notes for alias in aliases)
        ]
        check("review notes list the paid features",
              "current" if not missing else f"missing {', '.join(missing)}", not missing)

    territory_ids = {
        territory["id"] for territory in client.get_all("/territories", limit=200)
    }
    check("App Store territories", len(territory_ids), len(territory_ids) == EXPECTED_TERRITORIES)

    groups = client.get_all(f"/apps/{app_id}/subscriptionGroups", limit=50)
    check("subscription groups", len(groups), len(groups) == 1)
    subscription_products: set[str] = set()
    for group in groups:
        group_attributes = group["attributes"]
        check(
            "subscription group name",
            group_attributes.get("referenceName"),
            group_attributes.get("referenceName") == "Baby Docs Plus",
        )
        group_localizations = client.get_all(
            f"/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations", limit=50
        )
        group_locales = {localization["attributes"].get("locale") for localization in group_localizations}
        check("subscription group locales", sorted(group_locales), group_locales == EXPECTED_ASC_LOCALES)

        for subscription in client.get_all(f"/subscriptionGroups/{group['id']}/subscriptions", limit=50):
            attributes = subscription["attributes"]
            product_id = attributes.get("productId")
            subscription_products.add(product_id)
            expected = EXPECTED_SUBSCRIPTIONS.get(product_id)
            check(
                f"sub {product_id}",
                attributes.get("state"),
                attributes.get("state") in ("READY_TO_SUBMIT", "APPROVED", "WAITING_FOR_REVIEW"),
            )
            check(f"sub {product_id} review note", "present" if attributes.get("reviewNote") else None)
            check(
                f"sub {product_id} is recognized",
                "recognized" if expected else "unexpected product",
                expected is not None,
            )
            if not expected:
                continue

            check(
                f"sub {product_id} period",
                attributes.get("subscriptionPeriod"),
                attributes.get("subscriptionPeriod") == expected["period"],
            )
            check(
                f"sub {product_id} family sharing",
                attributes.get("familySharable"),
                attributes.get("familySharable") is True,
            )
            localizations = client.get_all(
                f"/subscriptions/{subscription['id']}/subscriptionLocalizations", limit=50
            )
            locales = {localization["attributes"].get("locale") for localization in localizations}
            check(f"sub {product_id} locales", sorted(locales), locales == EXPECTED_ASC_LOCALES)
            for localization in localizations:
                localized = localization["attributes"]
                expected_copy = (expected["name"], expected["description"])
                actual_copy = (localized.get("name"), localized.get("description"))
                check(
                    f"sub {product_id} {localized.get('locale')} copy",
                    "complete" if localized.get("name") and localized.get("description") else "MISSING",
                    bool(localized.get("name")) and bool(localized.get("description")),
                )
                check(
                    f"sub {product_id} {localized.get('locale')} copy matches repo",
                    "matched" if actual_copy == expected_copy else "DRIFT",
                    actual_copy == expected_copy,
                )

            availability = client.get_optional(
                f"/subscriptions/{subscription['id']}/subscriptionAvailability"
            ).get("data")
            available = (
                {
                    territory["id"]
                    for territory in client.get_all(
                        f"/subscriptionAvailabilities/{availability['id']}/availableTerritories",
                        limit=200,
                    )
                }
                if availability
                else set()
            )
            check(
                f"sub {product_id} availability",
                f"{len(available)}/{len(territory_ids)} territories",
                available == territory_ids,
            )

            prices, included = get_all_with_included(
                client,
                f"/subscriptions/{subscription['id']}/prices",
                include="territory,subscriptionPricePoint",
                limit=200,
            )
            price_territories = {relationship_id(price, "territory") for price in prices}
            price_values = {
                relationship_id(price, "territory"): included_attributes(
                    included, relationship_id(price, "subscriptionPricePoint")
                ).get("customerPrice")
                for price in prices
            }
            check(
                f"sub {product_id} price rows",
                f"{len(prices)}/{len(territory_ids)} territories",
                len(prices) == len(territory_ids) and price_territories == territory_ids,
            )
            check(
                f"sub {product_id} USA price",
                price_values.get("USA"),
                price_values.get("USA") == expected["usa_price"],
            )
            check(
                f"sub {product_id} price points complete",
                f"{sum(value is not None for value in price_values.values())}/{len(prices)}",
                len(price_values) == len(prices) and all(value is not None for value in price_values.values()),
            )

            offers = client.get_all(
                f"/subscriptions/{subscription['id']}/introductoryOffers",
                limit=200,
                include="territory",
            )
            offer_territories = {relationship_id(offer, "territory") for offer in offers}
            expected_trial = expected["trial"]
            if expected_trial:
                exact_offers = all(
                    offer["attributes"].get("duration") == expected_trial
                    and offer["attributes"].get("offerMode") == "FREE_TRIAL"
                    and offer["attributes"].get("numberOfPeriods") == 1
                    for offer in offers
                )
                check(
                    f"sub {product_id} trial territories",
                    f"{len(offers)}/{len(territory_ids)}",
                    len(offers) == EXPECTED_TRIAL_TERRITORIES
                    and offer_territories == territory_ids
                    and exact_offers,
                )
            else:
                check(f"sub {product_id} trial", len(offers), len(offers) == 0)

    check(
        "subscription products",
        sorted(subscription_products),
        subscription_products == set(EXPECTED_SUBSCRIPTIONS),
    )

    purchases = client.get_all(f"/apps/{app_id}/inAppPurchasesV2", limit=50)
    purchase_products: set[str] = set()
    for purchase in purchases:
        attributes = purchase["attributes"]
        product_id = attributes.get("productId")
        purchase_products.add(product_id)
        check(
            f"iap {product_id}",
            attributes.get("state"),
            attributes.get("state") in ("READY_TO_SUBMIT", "APPROVED", "WAITING_FOR_REVIEW"),
        )
        check(
            f"iap {product_id} type",
            attributes.get("inAppPurchaseType"),
            attributes.get("inAppPurchaseType") == "NON_CONSUMABLE",
        )
        check(
            f"iap {product_id} family sharing",
            attributes.get("familySharable"),
            attributes.get("familySharable") is True,
        )
        localizations = client.get_all(
            f"{V2}/inAppPurchases/{purchase['id']}/inAppPurchaseLocalizations", limit=50
        )
        locales = {localization["attributes"].get("locale") for localization in localizations}
        check(f"iap {product_id} locales", sorted(locales), locales == EXPECTED_ASC_LOCALES)
        for localization in localizations:
            localized = localization["attributes"]
            actual_copy = (localized.get("name"), localized.get("description"))
            check(
                f"iap {product_id} {localized.get('locale')} copy",
                "complete" if localized.get("name") and localized.get("description") else "MISSING",
                bool(localized.get("name")) and bool(localized.get("description")),
            )
            check(
                f"iap {product_id} {localized.get('locale')} copy matches repo",
                "matched" if actual_copy == EXPECTED_LIFETIME_COPY else "DRIFT",
                actual_copy == EXPECTED_LIFETIME_COPY,
            )

        availability = client.get_optional(
            f"{V2}/inAppPurchases/{purchase['id']}/inAppPurchaseAvailability"
        ).get("data")
        available = (
            {
                territory["id"]
                for territory in client.get_all(
                    f"/inAppPurchaseAvailabilities/{availability['id']}/availableTerritories",
                    limit=200,
                )
            }
            if availability
            else set()
        )
        check(
            f"iap {product_id} availability",
            f"{len(available)}/{len(territory_ids)} territories",
            available == territory_ids,
        )

        schedule = client.get_optional(
            f"{V2}/inAppPurchases/{purchase['id']}/iapPriceSchedule"
        ).get("data")
        check(f"iap {product_id} price schedule", "present" if schedule else None)
        if schedule:
            manual, manual_included = get_all_with_included(
                client,
                f"/inAppPurchasePriceSchedules/{schedule['id']}/manualPrices",
                include="inAppPurchasePricePoint,territory",
                limit=50,
            )
            automatic, automatic_included = get_all_with_included(
                client,
                f"/inAppPurchasePriceSchedules/{schedule['id']}/automaticPrices",
                include="inAppPurchasePricePoint,territory",
                limit=50,
            )
            manual_territories = {relationship_id(price, "territory") for price in manual}
            automatic_territories = {relationship_id(price, "territory") for price in automatic}
            manual_price = (
                included_attributes(
                    manual_included,
                    relationship_id(manual[0], "inAppPurchasePricePoint"),
                ).get("customerPrice")
                if manual
                else None
            )
            check(
                f"iap {product_id} manual price",
                f"{manual_price} in {sorted(manual_territories)}",
                manual_price == EXPECTED_LIFETIME_PRICE and manual_territories == {"USA"},
            )
            check(
                f"iap {product_id} automatic prices",
                f"{len(automatic)}/{len(territory_ids) - 1} territories",
                len(automatic) == len(territory_ids) - 1
                and automatic_territories == territory_ids - {"USA"}
                and all(
                    included_attributes(
                        automatic_included,
                        relationship_id(price, "inAppPurchasePricePoint"),
                    ).get("customerPrice")
                    for price in automatic
                ),
            )

    check(
        "in-app purchase products",
        sorted(purchase_products),
        purchase_products == {EXPECTED_LIFETIME_PRODUCT},
    )

    submissions = client.get_all(f"/apps/{app_id}/reviewSubmissions", limit=50)
    ios_submissions = [s for s in submissions if s["attributes"].get("platform") == "IOS"]
    active_submissions = [
        submission
        for submission in ios_submissions
        if submission["attributes"].get("state") in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW")
    ]
    if active_submissions:
        submission = max(
            active_submissions,
            key=lambda s: s["attributes"].get("createdDate") or "",
        )
        submission_attributes = submission["attributes"]
        items = client.get_all(f"/reviewSubmissions/{submission['id']}/items", limit=50)
        item_states = {item["attributes"].get("state") for item in items}
        check(
            "iOS review submission",
            submission_attributes.get("state"),
            submission_attributes.get("state") in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW"),
        )
        item_types = Counter(review_item_type(item["id"]) for item in items)
        expected_item_types = Counter({"6": 1, "17": 1, "18": 2, "19": 1})
        check("iOS review submission item count", len(items), len(items) == 5)
        check(
            "iOS review submission item types",
            dict(sorted(item_types.items())),
            item_types == expected_item_types,
        )
        check(
            "iOS review submission item states",
            sorted(item_states),
            item_states <= {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW"},
        )
    elif ios_submissions:
        submission = max(
            ios_submissions,
            key=lambda s: s["attributes"].get("submittedDate") or "",
        )
        submission_attributes = submission["attributes"]
        items = client.get_all(f"/reviewSubmissions/{submission['id']}/items", limit=50)
        item_states = {item["attributes"].get("state") for item in items}
        historical = (
            submission_attributes.get("state") == "REMOVED"
            or item_states == {"REMOVED"}
        )
        check(
            "historical iOS review submission",
            f"{submission_attributes.get('state')}, {len(items)} removed items",
            historical,
        )
    else:
        check("iOS review submission", "not created, draft is ready for Add for Review", True)

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

    print("\nCHECK BY HAND:")
    print("  * that the screenshots show the build that is attached")
    return 1 if gaps else 0


if __name__ == "__main__":
    raise SystemExit(main())
