#!/usr/bin/env python3
"""Report whether the RevenueCat project still matches what the binary expects.

Read-only. The write-side sibling is `rc-setup.py`.

    python3 scripts/rc-verify.py              # public key only
    RC_KEY=sk_... python3 scripts/rc-verify.py  # everything

This exists because the failure it checks for is silent and expensive: a
purchase completes, Apple charges the card, and the app unlocks nothing. That
happens when the entitlement `StoreService` reads has a different identifier
from the one the products are attached to, and it already happened once here
(the project was created with `Baby Docs Pro` while the code checked
`BabyDocs+`). Nothing in a build, a test run or App Store Connect can see it,
because the mismatch lives in a dashboard.

Two tiers, because they need different keys:

  * **Public tier**, no secret needed. The `appl_` key in the binary is asked
    for its own current offering, which is the exact call the app makes at
    launch. This proves the key resolves to this project, and shows every
    package a buyer would be offered. A legacy `$rc_monthly` package would
    appear here.
  * **Secret tier**, needs `RC_KEY`. Confirms the entitlement `BabyDocs+`
    exists and that every product is attached to it. Attachment is the half the
    public API cannot see, and it is the half that decides whether a payment
    unlocks anything.

The `sk_` key is a management key from Dashboard -> Project settings -> API
keys -> Secret keys. It is deliberately not stored on disk and must never ship
in a binary (App Review 1.4). Pass it in the environment.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

V2 = "https://api.revenuecat.com/v2"
V1 = "https://api.revenuecat.com/v1"

ROOT = Path(__file__).resolve().parent.parent
STORE_SERVICE = ROOT / "Shared/Services/StoreService.swift"

BUNDLE_ID = "com.jackwallner.babydocs"
ENTITLEMENT_KEY = "BabyDocs+"
# Store identifier -> the offering package it must sit in. Weekly leads, yearly
# makes the comparison legible, lifetime keeps the vault. There is no monthly.
EXPECTED_PACKAGES = {
    "com.jackwallner.babydocs.pro.weekly": "$rc_weekly",
    "com.jackwallner.babydocs.pro.yearly": "$rc_annual",
    "com.jackwallner.babydocs.pro.lifetime": "$rc_lifetime",
}

ready: list[str] = []
gaps: list[str] = []
skipped: list[str] = []


def check(label: str, value, good: bool) -> None:
    (ready if good else gaps).append(f"{label}: {value}")


def fetch(url: str, key: str, headers: dict[str, str] | None = None) -> dict:
    request = urllib.request.Request(url)
    request.add_header("Authorization", f"Bearer {key}")
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read()
        return json.loads(raw) if raw else {}


def read_binary_config() -> tuple[str, str, list[str]]:
    """The three constants the app actually ships, read from source.

    Parsed rather than duplicated, so this script cannot drift into checking a
    key the binary stopped using.
    """
    source = STORE_SERVICE.read_text()

    def literal(name: str) -> str:
        match = re.search(rf'static let {name} = "([^"]+)"', source)
        if not match:
            raise SystemExit(f"error: could not find {name} in {STORE_SERVICE.name}")
        return match.group(1)

    products = [literal(name) for name in ("weekly", "yearly", "lifetime")]
    return literal("apiKey"), literal("proEntitlement"), products


def public_checks(api_key: str, expected_products: list[str]) -> None:
    """The call the app makes at launch, made the same way the app makes it."""
    url = f"{V1}/subscribers/babydocs-release-readiness-probe/offerings"
    try:
        body = fetch(url, api_key, {"X-Platform": "ios"})
    except urllib.error.HTTPError as error:
        check("public key resolves an offering", f"HTTP {error.code}", False)
        return
    except Exception as error:  # noqa: BLE001 - any network failure is a gap
        check("public key resolves an offering", type(error).__name__, False)
        return

    current = body.get("current_offering_id")
    check("current offering", current or "NONE", bool(current))
    offering = next(
        (o for o in body.get("offerings", []) if o.get("identifier") == current), None
    )
    if offering is None:
        check("current offering is served", "not in the offerings list", False)
        return

    served = {p["platform_product_identifier"]: p["identifier"] for p in offering["packages"]}
    for product in expected_products:
        package = served.get(product)
        expected = EXPECTED_PACKAGES.get(product)
        check(f"{product} in {expected}", package or "NOT OFFERED", package == expected)

    # A leftover `$rc_monthly` is the specific defect this project shipped with:
    # the fleet default, with no weekly product able to attach to it.
    extra = [f"{pkg} ({sku})" for sku, pkg in served.items() if sku not in expected_products]
    check("no extra packages", ", ".join(extra) if extra else "clean", not extra)


def secret_checks(secret: str, entitlement_key: str, expected_products: list[str]) -> None:
    projects = fetch(f"{V2}/projects", secret)["items"]
    project = (
        projects[0]
        if len(projects) == 1
        else next(p for p in projects if p["name"].lower() == "baby docs")
    )
    project_id = project["id"]

    apps = fetch(f"{V2}/projects/{project_id}/apps", secret)["items"]
    app = next((a for a in apps if a.get("app_store", {}).get("bundle_id") == BUNDLE_ID), None)
    check("app bundle id", BUNDLE_ID if app else "NOT FOUND", bool(app))
    if app is None:
        return

    keys = fetch(f"{V2}/projects/{project_id}/apps/{app['id']}/public_api_keys", secret)["items"]
    production = next((k["key"] for k in keys if k["environment"] == "production"), None)
    shipped, _, _ = read_binary_config()
    check(
        "shipped key is this app's production key",
        "match" if production == shipped else f"dashboard has {production}",
        production == shipped,
    )

    entitlements = fetch(f"{V2}/projects/{project_id}/entitlements", secret)["items"]
    entitlement = next((e for e in entitlements if e["lookup_key"] == entitlement_key), None)
    keys_found = ", ".join(sorted(e["lookup_key"] for e in entitlements))
    check(
        f"entitlement {entitlement_key}",
        "present" if entitlement else f"MISSING (project has: {keys_found})",
        bool(entitlement),
    )
    if entitlement is None:
        return

    attached = fetch(
        f"{V2}/projects/{project_id}/entitlements/{entitlement['id']}/products?limit=100",
        secret,
    )["items"]
    attached_ids = {p["store_identifier"] for p in attached}
    for product in expected_products:
        # The one that matters. Unattached means the payment goes through and
        # `store.isPro` stays false.
        check(f"{product} attached to {entitlement_key}",
              "attached" if product in attached_ids else "NOT ATTACHED",
              product in attached_ids)


def main() -> int:
    api_key, entitlement_key, products = read_binary_config()
    print(f"binary: key {api_key[:12]}..., entitlement {entitlement_key}\n")
    check("binary entitlement is the expected one", entitlement_key,
          entitlement_key == ENTITLEMENT_KEY)
    check("binary products", f"{len(products)} of 3",
          sorted(products) == sorted(EXPECTED_PACKAGES))

    public_checks(api_key, products)

    secret = os.environ.get("RC_KEY")
    if secret:
        secret_checks(secret, entitlement_key, products)
    else:
        skipped.append(
            "entitlement attachment (set RC_KEY to a sk_... management key). "
            "Until this runs, a purchase unlocking nothing is still possible."
        )

    if ready:
        print("READY:")
        for line in ready:
            print(f"  + {line}")
    if gaps:
        print("\nGAPS:")
        for line in gaps:
            print(f"  - {line}")
    if skipped:
        print("\nNOT CHECKED:")
        for line in skipped:
            print(f"  * {line}")

    print("\nNEITHER TIER CAN SEE THIS, CONFIRM ON A DEVICE:")
    print("  * that a real sandbox purchase flips store.isPro, and that")
    print("    restore, cancellation and lapse behave. An entitlement can be")
    print("    correct in the dashboard and still fail against a StoreKit")
    print("    configuration that never reaches it.")

    return 1 if gaps else 0


if __name__ == "__main__":
    sys.exit(main())
