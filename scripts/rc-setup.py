#!/usr/bin/env python3
"""Wire the Baby Docs App Store products into RevenueCat.

Usage:
    RC_KEY=sk_... python3 scripts/rc-setup.py

Ported from ~/recovery/scripts/rc-setup.py, which is in turn Protein's version.
Two things are different here, and both were real defects rather than porting
noise:

1. **There is no monthly plan.** Baby Docs sells weekly, yearly and lifetime,
   because the need is intense for six to thirteen weeks and then genuinely
   over. The project shipped with the fleet-default `$rc_monthly` package, so
   the weekly product had nowhere to attach; this creates `$rc_weekly`.
2. **The entitlement identifiers did not match.** The project contains
   `Baby Docs Pro`; `StoreService` checks `BabyDocs+`, `pro` and `BabyDocsPro`.
   A purchase would have completed and unlocked nothing. `lookup_key` is
   immutable in both the v2 and the internal API, so this creates `BabyDocs+`
   and attaches every product (Test Store included) to it.

The `sk_` secret key is a RevenueCat management key from Dashboard -> Project
settings -> API keys -> Secret keys. It is deliberately not stored on disk and
must never ship in a binary (App Review 1.4). Pass it in the environment.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

BASE = "https://api.revenuecat.com/v2"
BUNDLE_ID = "com.jackwallner.babydocs"

# The identifier `StoreService` reads. Not "Baby Docs Pro", which is what the
# project was created with; see the module docstring.
ENTITLEMENT_KEY = "BabyDocs+"
ENTITLEMENT_NAME = "BabyDocs+"

# (store identifier, display name, RC product type, offering package key)
PRODUCTS = (
    ("com.jackwallner.babydocs.pro.weekly", "Weekly", "subscription", "$rc_weekly"),
    ("com.jackwallner.babydocs.pro.yearly", "Yearly", "subscription", "$rc_annual"),
    ("com.jackwallner.babydocs.pro.lifetime", "Lifetime", "one_time", "$rc_lifetime"),
)
PACKAGE_NAMES = {"$rc_weekly": "Weekly", "$rc_annual": "Annual", "$rc_lifetime": "Lifetime"}


def request(method: str, path: str, body: dict | None = None) -> dict:
    key = os.environ.get("RC_KEY")
    if not key:
        raise SystemExit(
            "error: set RC_KEY to a RevenueCat secret (sk_...) management key.\n"
            "       Dashboard -> Project settings -> API keys -> Secret keys."
        )
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=120) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:800]
        raise RuntimeError(f"{method} {path} -> {error.code}: {detail}") from error


def main() -> None:
    # V2 secret keys are project-scoped, so a single project in the list is the
    # answer and matching on the name would only add a way to fail.
    projects = request("GET", "/projects")["items"]
    project = (
        projects[0]
        if len(projects) == 1
        else next(p for p in projects if p["name"].lower() == "baby docs")
    )
    project_id = project["id"]
    apps = request("GET", f"/projects/{project_id}/apps")["items"]
    app = next(a for a in apps if a.get("app_store", {}).get("bundle_id") == BUNDLE_ID)
    app_id = app["id"]
    print(f"project: {project['name']}")
    print(f"app: {app['name']}")

    all_products = request("GET", f"/projects/{project_id}/products?limit=100")["items"]
    products_by_identifier = {p["store_identifier"]: p for p in all_products}
    configured_products: dict[str, dict] = {}
    for identifier, display_name, product_type, _ in PRODUCTS:
        product = products_by_identifier.get(identifier)
        if product is None:
            product = request(
                "POST",
                f"/projects/{project_id}/products",
                {
                    "store_identifier": identifier,
                    "app_id": app_id,
                    "type": product_type,
                    "display_name": display_name,
                },
            )
            all_products.append(product)
            print(f"created product: {identifier}")
        else:
            print(f"product exists: {identifier}")
        configured_products[identifier] = product

    entitlements = request("GET", f"/projects/{project_id}/entitlements")["items"]
    entitlement = next(
        (e for e in entitlements if e["lookup_key"] == ENTITLEMENT_KEY), None
    )
    if entitlement is None:
        entitlement = request(
            "POST",
            f"/projects/{project_id}/entitlements",
            {"lookup_key": ENTITLEMENT_KEY, "display_name": ENTITLEMENT_NAME},
        )
        print(f"created entitlement: {ENTITLEMENT_KEY}")
    else:
        print(f"entitlement exists: {ENTITLEMENT_KEY}")

    # Every product in the project, not only the three App Store ones. The Test
    # Store products stay attached to `Baby Docs Pro` as well, and a simulator
    # or Test Store purchase has to unlock the same tier the app checks for.
    attached = request(
        "GET", f"/projects/{project_id}/entitlements/{entitlement['id']}/products?limit=100"
    )["items"]
    attached_ids = {p["id"] for p in attached}
    missing_ids = [p["id"] for p in all_products if p["id"] not in attached_ids]
    if missing_ids:
        request(
            "POST",
            f"/projects/{project_id}/entitlements/{entitlement['id']}/actions/attach_products",
            {"product_ids": missing_ids},
        )
        print(f"attached {len(missing_ids)} products to {entitlement['lookup_key']}")

    offerings = request("GET", f"/projects/{project_id}/offerings")["items"]
    offering = next(o for o in offerings if o.get("is_current"))
    packages = request(
        "GET", f"/projects/{project_id}/offerings/{offering['id']}/packages?limit=100"
    )["items"]
    packages_by_key = {p["lookup_key"]: p for p in packages}
    for identifier, _, _, package_key in PRODUCTS:
        package = packages_by_key.get(package_key)
        if package is None:
            package = request(
                "POST",
                f"/projects/{project_id}/offerings/{offering['id']}/packages",
                {"lookup_key": package_key, "display_name": PACKAGE_NAMES[package_key]},
            )
            packages_by_key[package_key] = package
            print(f"created package: {package_key}")
        attached_items = request(
            "GET", f"/projects/{project_id}/packages/{package['id']}/products?limit=100"
        )["items"]
        attached_product_ids = {item["product"]["id"] for item in attached_items}
        product = configured_products[identifier]
        if product["id"] in attached_product_ids:
            continue
        request(
            "POST",
            f"/projects/{project_id}/packages/{package['id']}/actions/attach_products",
            {"products": [{"product_id": product["id"], "eligibility_criteria": "all"}]},
        )
        print(f"attached {identifier} to {package_key}")

    keys = request("GET", f"/projects/{project_id}/apps/{app_id}/public_api_keys")["items"]
    production_key = next(k["key"] for k in keys if k["environment"] == "production")
    print(f"public SDK key: {production_key}")
    print("done")


if __name__ == "__main__":
    main()
