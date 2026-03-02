# Turnkey Python SDK - Technical Analysis

> **Repository**: `tkhq/python-sdk` (forked)
> **Analysis Date**: 2026-02-27
> **Key Finding**: The Python SDK is a real, full SDK — NOT the stamper script the docs describe.

---

## Critical Context: Docs Are Wrong

`sdks/python.mdx` currently says:
> "we do not yet offer a full SDK for *Rust*" (copy-paste error — should say Python)

And implies Python has no real client library. **This is false.** The `tkhq/python-sdk` repository contains a complete, generated SDK with Pydantic v2 types and 100+ typed API methods.

**Correct install:**
```bash
pip install turnkey-http turnkey-api-key-stamper
```

---

## Repository Structure

```
python-sdk/
├── turnkey-sdk-types/          # Pydantic v2 models for every API type
│   └── src/turnkey_sdk_types/  # Generated from OpenAPI spec
├── turnkey-http/               # Full generated HTTP client
│   └── src/turnkey_http/       # 100+ typed API methods
├── turnkey-api-key-stamper/    # P-256 ECDSA request stamper
│   └── src/turnkey_api_key_stamper/
├── tests/                      # Integration test suite (pytest)
└── Makefile                    # `make generate` regenerates from OpenAPI spec
```

### Package Hierarchy

```
turnkey-sdk-types (Pydantic v2 models)
        ↓
turnkey-http (HTTP client, uses types)
        ↓
turnkey-api-key-stamper (signs requests)
```

---

## What It Can Do

The SDK exposes the full Turnkey API surface. Key methods (not exhaustive):

### Wallet Operations
- `create_wallet`, `get_wallet`, `get_wallets`, `update_wallet`, `delete_wallets`
- `create_wallet_accounts`, `get_wallet_accounts`
- `export_wallet`, `import_wallet`

### Signing
- `sign_raw_payload`, `sign_raw_payloads`
- `sign_transaction`

### Authentication Flows
- `init_otp`, `verify_otp`, `otp_auth`
- `oauth`, `oauth_login`, `create_oauth_providers`

### Organization Management
- `create_sub_organization`, `get_organization`, `update_organization`, `delete_organization`
- `get_user`, `create_users`, `update_user`, `delete_users`
- `create_api_keys`, `delete_api_keys`

### Policy Management
- `create_policy`, `update_policy`, `delete_policy`, `get_policy`, `get_policies`

### Gas Station
- `eth_send_transaction`, `sol_send_transaction`, `get_nonces`

### Infrastructure
- `get_whoami`, `get_activity`, `get_activities`

**Total: ~100+ typed methods** generated from the same OpenAPI spec used by other SDKs.

---

## Activity Polling

The SDK has built-in activity polling:

```python
# Configurable polling parameters
client = TurnkeyClient(
    api_public_key=os.getenv("TURNKEY_API_PUBLIC_KEY"),
    api_private_key=os.getenv("TURNKEY_API_PRIVATE_KEY"),
    organization_id=os.getenv("TURNKEY_ORGANIZATION_ID"),
    polling_interval_ms=500,    # default: 500ms
    max_polling_retries=3,      # default: 3 — TOO LOW for production
)
```

**⚠️ Production warning:** Default `max_polling_retries=3` is too low. Wallet creation activities can take 2-5+ seconds. Recommend setting to 20-30 for production use.

---

## Known Gaps vs Other SDKs

### No HPKE
Python can call the export API and receive the encrypted bundle, but **cannot decrypt it in-process**. There are no HPKE helpers. Developer must implement their own HPKE decryption or use a different SDK for export flows.

Same limitation as Ruby.

### P-256 Only
The stamper only supports P-256 (secp256r1) ECDSA signing. No secp256k1 or ED25519. This means Python cannot be used for API keys that require those curves (unlike Go, which supports all three).

### Blocking / Synchronous Polling
Polling uses `time.sleep()`:

```python
# Inside the polling loop (simplified)
while retries < max_retries:
    time.sleep(polling_interval_ms / 1000)
    activity = self.get_activity(activity_id)
    if activity.status == "COMPLETE":
        return activity
    retries += 1
```

**This is blocking.** In async Python apps (FastAPI, Starlette, Django async views, Celery with async workers), calling any mutating SDK method will block the event loop for the duration of polling. 

**Workaround options:**
1. Use `asyncio.to_thread()` to run SDK calls in a thread pool
2. Implement your own async polling wrapper using `asyncio.sleep()`
3. Run SDK calls in a separate worker process

### No Express/Next.js Equivalent
Python has no proxy handler pattern. Server-to-server integration only.

---

## Code Generation

The SDK is generated from the Turnkey OpenAPI spec using a custom Python generator:

```bash
make generate   # Regenerates all types and HTTP client from spec
```

This means the SDK will track the full API surface as Turnkey adds new endpoints. The generation pipeline uses the same spec as the TypeScript, Go, and Rust SDKs.

---

## Integration Example: Wallet Creation

```python
from turnkey_http import TurnkeyClient
from turnkey_sdk_types import CreateWalletBody, WalletAccountParams

client = TurnkeyClient(
    api_public_key=os.getenv("TURNKEY_API_PUBLIC_KEY"),
    api_private_key=os.getenv("TURNKEY_API_PRIVATE_KEY"),
    organization_id=os.getenv("TURNKEY_ORGANIZATION_ID"),
    max_polling_retries=20,  # Use higher value in production
)

result = client.create_wallet(
    CreateWalletBody(
        wallet_name="My Wallet",
        accounts=[
            WalletAccountParams(
                path_format="PATH_FORMAT_BIP32",
                path="m/44'/60'/0'/0/0",
                curve="CURVE_SECP256K1",
                address_format="ADDRESS_FORMAT_ETHEREUM",
            )
        ],
    )
)
print(result.wallet_id)
```

## Integration Example: Email OTP

```python
# Step 1: Send OTP
otp_result = client.init_otp(
    InitOtpBody(
        otpType="OTP_TYPE_EMAIL",
        contact=user_email,
        organizationId=sub_org_id,
    )
)

# Step 2: User receives code, submit it
auth_result = client.otp_auth(
    OtpAuthBody(
        otpId=otp_result.otp_id,
        otpCode=user_submitted_code,
        organizationId=sub_org_id,
    )
)
# auth_result contains session token
```

---

## Testing

Integration tests use pytest and require real Turnkey credentials:

```bash
cd tests
pip install -r requirements.txt
TURNKEY_API_PUBLIC_KEY=... TURNKEY_API_PRIVATE_KEY=... TURNKEY_ORGANIZATION_ID=... pytest
```

---

## Documentation Rewrite Requirements

The current `sdks/python.mdx` needs a complete rewrite. Minimum required content:

1. **Correct the false statement** — Python has a real SDK
2. **Installation**: `pip install turnkey-http turnkey-api-key-stamper`
3. **Quick start**: Client initialization + wallet creation
4. **Activity polling**: Explain defaults, warn about production values
5. **Async caveat**: Document the blocking poll issue and workarounds
6. **Feature table**: What's supported vs. gaps (no HPKE, no secp256k1/ED25519)
7. **OTP flow example**
8. **Link to GitHub**: `github.com/tkhq/python-sdk`

---

*Analysis from direct inspection of the `tkhq/python-sdk` repository.*
