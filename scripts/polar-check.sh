#!/bin/bash
# Read-only audit of the Polar account: lists products and checkout links and
# verifies that the checkout link hardcoded in the app/site sells a $5/month
# subscription (not the old lifetime product).
#
# Usage:
#   export POLAR_ACCESS_TOKEN=polar_oat_...   # Organization Access Token
#   ./scripts/polar-check.sh [--sandbox]
#
# The token never leaves your machine except to api.polar.sh. Nothing is
# created or modified — GET requests only.
set -euo pipefail

API="https://api.polar.sh"
if [[ "${1:-}" == "--sandbox" ]]; then
    API="https://sandbox-api.polar.sh"
fi

if [[ -z "${POLAR_ACCESS_TOKEN:-}" ]]; then
    echo "Set POLAR_ACCESS_TOKEN first (Polar dashboard → Settings → Access Tokens)." >&2
    exit 1
fi

# The checkout link currently hardcoded in TrialExpiredView / SettingsPage /
# ReadyView and the website. Keep in sync if the link is ever replaced.
EXPECTED_LINK="polar_cl_YS3DZpcmFoh7GDvDvRxWezZLUmPKgwf9Mb6T618NFdC"

fetch() {
    curl -sf -H "Authorization: Bearer ${POLAR_ACCESS_TOKEN}" "${API}$1"
}

PRODUCTS_JSON=$(fetch "/v1/products/?limit=100")
LINKS_JSON=$(fetch "/v1/checkout-links/?limit=100")

EXPECTED_LINK="$EXPECTED_LINK" python3 - "$PRODUCTS_JSON" "$LINKS_JSON" <<'PY'
import json, os, sys

products = json.loads(sys.argv[1])["items"]
links = json.loads(sys.argv[2])["items"]
expected = os.environ["EXPECTED_LINK"]

def describe_price(p):
    amount_type = p.get("amount_type")
    if amount_type == "fixed":
        cents = p.get("price_amount", 0)
        cur = p.get("price_currency", "usd").upper()
        return f"{cents / 100:.2f} {cur}"
    return amount_type or "?"

print("== Products ==")
for prod in products:
    interval = prod.get("recurring_interval")
    kind = f"subscription / {interval}" if prod.get("is_recurring") else "one-time"
    prices = ", ".join(describe_price(p) for p in prod.get("prices", [])) or "no prices"
    archived = "  [ARCHIVED]" if prod.get("is_archived") else ""
    print(f"  {prod['name']}: {kind} — {prices}{archived}")

print("\n== Checkout links ==")
target = None
for link in links:
    names = ", ".join(p["name"] for p in link.get("products", []))
    marker = ""
    if expected in (link.get("url") or ""):
        marker = "   <-- hardcoded in app + website"
        target = link
    print(f"  {link.get('label') or '(no label)'}: {link['url']}")
    print(f"      sells: {names}{marker}")

print("\n== Verdict ==")
if target is None:
    print(f"  ✗ No checkout link matching {expected} found — the hardcoded link may")
    print("    belong to a different org or have been deleted. Create a new link and")
    print("    update TrialExpiredView.swift, SettingsPage.swift, ReadyView.swift, index.html.")
    sys.exit(1)

probs = []
for prod in target.get("products", []):
    if not prod.get("is_recurring"):
        probs.append(f"'{prod['name']}' is a ONE-TIME product, not a subscription")
    else:
        for price in prod.get("prices", []):
            if price.get("amount_type") == "fixed" and (
                price.get("price_amount") != 500
                or prod.get("recurring_interval") != "month"
            ):
                probs.append(
                    f"'{prod['name']}' is {describe_price(price)} per "
                    f"{prod.get('recurring_interval')}, expected 5.00 USD per month"
                )
if probs:
    print("  ✗ The hardcoded checkout link does NOT sell a $5/month subscription:")
    for p in probs:
        print(f"      - {p}")
    sys.exit(1)
print("  ✓ Hardcoded checkout link sells a $5/month subscription. Ship it.")
PY
