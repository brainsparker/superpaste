#!/bin/bash
# Makes sure the product sold by the hardcoded checkout link grants a License
# Key benefit, so buyers get a key in their receipt email and customer portal
# (polar.sh/superpaste/portal). Without it, checkout succeeds but no key exists.
#
# Usage:
#   export POLAR_ACCESS_TOKEN=polar_oat_...   # Organization Access Token
#   ./scripts/polar-attach-license-key.sh            # dry run: report only
#   ./scripts/polar-attach-license-key.sh --apply    # create + attach benefit
#
# Token scopes: checkout_links:read, products:read, products:write,
# benefits:read, benefits:write, license_keys:read.
#
# Attaching sets the product's full benefit list, so existing benefits are
# kept. Re-running is safe: it stops once a License Key benefit is attached.
set -euo pipefail

if [[ -z "${POLAR_ACCESS_TOKEN:-}" ]]; then
    echo "Set POLAR_ACCESS_TOKEN first (Polar dashboard → Settings → Access Tokens)." >&2
    exit 1
fi

APPLY=false
[[ "${1:-}" == "--apply" ]] && APPLY=true

# Keep in sync with scripts/polar-check.sh.
EXPECTED_LINK="polar_cl_YS3DZpcmFoh7GDvDvRxWezZLUmPKgwf9Mb6T618NFdC"

APPLY="$APPLY" EXPECTED_LINK="$EXPECTED_LINK" python3 -I - <<'PY'
import json, os, sys, time, urllib.error, urllib.request

API = "https://api.polar.sh"
TOKEN = os.environ["POLAR_ACCESS_TOKEN"]
APPLY = os.environ["APPLY"] == "true"
EXPECTED = os.environ["EXPECTED_LINK"]

def call(method, path, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.exit(f"✗ {method} {path} → HTTP {e.code}: {e.read().decode()[:500]}")

# 1. Find the product behind the hardcoded checkout link.
links = call("GET", "/v1/checkout-links/?limit=100")["items"]
link = next((l for l in links if EXPECTED in (l.get("url") or "")), None)
if link is None:
    sys.exit(f"✗ No checkout link matching {EXPECTED}. Run scripts/polar-check.sh.")
products = link.get("products") or []
if len(products) != 1:
    sys.exit(f"✗ Expected the checkout link to sell 1 product, found {len(products)}.")
product = call("GET", f"/v1/products/{products[0]['id']}")
print(f"Product: {product['name']} ({product['id']})")

current = product.get("benefits") or []
for b in current:
    print(f"  benefit: {b['type']} — {b.get('description')}")
if any(b["type"] == "license_keys" for b in current):
    print("✓ A License Key benefit is already attached. Nothing to do.")
    sys.exit(0)
print("✗ No License Key benefit attached — buyers receive no key.")

# 2. Reuse an existing license-key benefit if one was created but never attached.
existing = call("GET", "/v1/benefits/?type=license_keys&limit=100")["items"]
benefit = existing[0] if existing else None
if benefit:
    print(f"Found unattached License Key benefit: {benefit['description']} ({benefit['id']})")

if not APPLY:
    action = "attach it" if benefit else "create 'SuperPaste license key' and attach it"
    print(f"\nDry run. Re-run with --apply to {action}.")
    sys.exit(0)

if benefit is None:
    benefit = call("POST", "/v1/benefits/", {
        "type": "license_keys",
        "description": "SuperPaste license key",
        "properties": {
            "prefix": "SUPERPASTE",
            "expires": None,
            "activations": None,
            "limit_usage": None,
        },
    })
    print(f"Created benefit {benefit['id']}")

# 3. Attach, keeping whatever benefits were already there.
ids = [b["id"] for b in current] + [benefit["id"]]
call("POST", f"/v1/products/{product['id']}/benefits", {"benefits": ids})

product = call("GET", f"/v1/products/{product['id']}")
if not any(b["type"] == "license_keys" for b in product.get("benefits") or []):
    sys.exit("✗ Attach call succeeded but the product still lists no License Key benefit.")
print("✓ License Key benefit attached. New buyers get a key in their receipt and portal.")

# 4. Existing subscribers are granted asynchronously; give Polar a moment.
time.sleep(10)
keys = call("GET", f"/v1/license-keys/?benefit_id={benefit['id']}&limit=100")
items = keys.get("items", [])
print(f"\nLicense keys issued so far for this benefit: {len(items)}")
for k in items:
    print(f"  {k.get('display_key')}  status={k.get('status')}  customer={k.get('customer_id')}")
if not items:
    print("  None yet. Check the portal in a minute; if existing subscribers still")
    print("  have no key, grant the benefit to them from the Polar dashboard.")
PY
