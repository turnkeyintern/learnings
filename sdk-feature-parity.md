# Turnkey SDK Feature Parity Analysis

> **Compiled:** 2026-02-27 (updated 2026-03-02)
> **Sources:** TypeScript SDK monorepo, Go SDK, Rust SDK, Python SDK (fork), Ruby SDK, Flutter, iOS, Android, docs repo
> **Purpose:** Cross-SDK capability comparison, end-product flow parity, and documentation gap audit

---

## Table of Contents

1. [SDK Inventory](#sdk-inventory)
2. [Client SDK Auth Method Parity](#client-sdk-auth-method-parity)
3. [Client SDK Wallet Operations Parity](#client-sdk-wallet-operations-parity)
4. [Server SDK Parity](#server-sdk-parity)
5. [End-to-End Flow Parity: Email OTP](#end-to-end-flow-parity-email-otp)
6. [API Naming Consistency](#api-naming-consistency)
7. [Deprecation Landscape](#deprecation-landscape)
8. [Identified Documentation Gaps](#identified-documentation-gaps)
9. [Bottom Line](#bottom-line)

---

## SDK Inventory

### Client SDKs
| SDK | Package |
|-----|---------|
| TypeScript Browser | `@turnkey/core` |
| React | `@turnkey/react-wallet-kit` |
| React Native | `@turnkey/react-native-wallet-kit` |
| Flutter | `turnkey_flutter` |
| iOS (Swift) | `TurnkeyiOS` |
| Android (Kotlin) | `turnkey-android` |

### Server SDKs
| SDK | Package |
|-----|---------|
| TypeScript Server | `@turnkey/sdk-server` |
| Go | `github.com/tkhq/go-sdk` |
| Rust | `turnkey_client` (crates.io) |
| Python | `turnkey-http` + `turnkey-api-key-stamper` (pip) |
| Ruby | `turnkey-sdk` gem |

---

## Client SDK Auth Method Parity

| Auth Method | TS/React | React Native | Flutter | iOS | Android | Notes |
|-------------|----------|--------------|---------|-----|---------|-------|
| Email OTP | ✅ | ✅ | ✅ | ✅ | ✅ | Full parity |
| SMS OTP | ✅ | ✅ | ✅ | ✅ | ✅ | Full parity |
| Passkey / WebAuthn | ✅ | ✅ | ✅ | ✅ | ✅ | Full parity |
| Google OAuth | ✅ | ✅ | ✅ | ✅ | ✅ | Full parity |
| Apple OAuth | ✅ | ✅ | ✅ | ✅ | ✅ | Full parity |
| Discord OAuth | ✅ | ✅ | ✅ | ✅ | ✅ | Full parity |
| X / Twitter OAuth | ✅ | ✅ | ✅ | ✅ | ✅ | Full parity |
| **Facebook OAuth** | ✅ | ✅ | ❌ | ❌ | ❌ | **GAP** — Missing from Flutter, iOS, Android. No explanation in docs. |
| **Web3 Wallet (SIWE/SIWS)** | ✅ | ❌ | ❌ | ❌ | ❌ | **WEB ONLY** — requires browser wallet extension. Not portable to native. |
| **handleLogin() modal** | ✅ | ❌ | ❌ | ❌ | ❌ | **WEB ONLY** — one-liner shows full configured auth modal. Native requires custom UI. Never explained in docs. |

---

## Client SDK Wallet Operations Parity

All 6 client SDKs have full parity on core wallet operations:

| Operation | TS/React | React Native | Flutter | iOS | Android |
|-----------|----------|--------------|---------|-----|---------|
| Wallet Creation | ✅ | ✅ | ✅ | ✅ | ✅ |
| Transaction Signing | ✅ | ✅ | ✅ | ✅ | ✅ |
| Wallet Import | ✅ | ✅ | ✅ | ✅ | ✅ |
| Wallet Export | ✅ | ✅ | ✅ | ✅ | ✅ |
| Sub-org Management | ✅ | ✅ | ✅ | ✅ | ✅ |
| Session Management | ✅ | ✅ | ✅ | ✅ | ✅ |
| Request Stamping | ✅ | ✅ | ✅ | ✅ | ✅ |
| MetaMask/Phantom Connect | ✅ | ❌ | ❌ | ❌ | ❌ |
| pollTransactionStatus (gas station) | ✅ | ✅ | ❌ | ❌ | ❌ |

---

## Server SDK Parity

| Capability | TypeScript | Go | Rust | Python | Ruby |
|------------|------------|----|------|--------|------|
| Wallet Management | ✅ | ✅ | ✅ | ✅ | ✅ |
| Policy Management | ✅ | ✅ | ✅ | ✅ | ✅ |
| Signing | ✅ | ✅ | ✅ | ✅ | ✅ |
| OTP Flows | ✅ | ✅ | ✅ | ✅ | ~partial |
| OAuth / Social Login | ✅ | ✅ | ✅ | ✅ | ~partial |
| Activity Auto-Polling | ✅ | ❌ | ✅ | ✅ (blocking) | ❌ |
| HPKE (wallet export decrypt) | ✅ | ✅ | ✅ | ❌ | ❌ |
| Nitro Attestation Verification | ❌ | ✅ | ✅ | ❌ | ❌ |
| Gas Station | ✅ | ❌ | ✅ | ❌ | ❌ |
| ED25519 API Key Signing | ❌ | ✅ | ❌ | ❌ | ❌ |
| Express/Next.js Proxy Handler | ✅ | ❌ | ❌ | ❌ | ❌ |
| Server Actions (sendOtp, verifyOtp…) | ✅ | ❌ | ❌ | ❌ | ❌ |
| TVC (Verifiable Cloud) CLI | ❌ | ❌ | ✅ | ❌ | ❌ |
| Async/Non-blocking poll | ✅ | ❌ | ✅ | ❌ | ❌ |

### Server SDK Notable Quirks

**Go:**
- Must pass `client.Authenticator` as a parameter to every single API call — no global default. Awkward ergonomics vs TypeScript where the client holds auth state.
- No auto-polling. Caller must manually poll for activity completion. Easy to miss in production.
- Unique: only SDK with ED25519 API key signing (useful for Near, Aptos, Sui).

**Rust:**
- Built-in exponential backoff polling (better than Go).
- Only 4 examples: whoami, wallet, proofs, sub_org. Zero OTP or OAuth examples — developers can't discover these features.
- Supports full API surface: wallet, policy, OTP, OAuth, gas station, TVC — but none of this is documented.

**Python:**
- Full SDK with 100+ typed methods (Pydantic v2 models), NOT just a stamper script.
- Polling uses blocking `time.sleep()`. Breaking for async Python apps (FastAPI, Starlette, Django async).
- Default `max_polling_retries=3` is too low for production.
- P-256 signing only (no secp256k1 or ED25519).
- No HPKE — can call export API but can't decrypt the result.

**Ruby:**
- Can call the export API but cannot decrypt the result (no HPKE helpers).
- No activity polling.
- Only 2 examples: whoami + signing.

---

## End-to-End Flow Parity: Email OTP

How each SDK handles the complete Email OTP authentication flow:

### TypeScript Server — Named actions
```
1. server.sendOtp({ email })
2. User receives code
3. server.verifyOtp({ code, ... })
4. server.createOtpSession()
```

### React / React Native — Named actions (shared via @turnkey/core)
```
1. initOtp({ email })
2. User receives code
3. verifyOtp({ otpCode })
4. loginWithOtp() or signUpWithOtp()
```

### Flutter / Android — One-liner
```
loginOrSignUpWithOtp(email)   ← SDK manages full flow internally
```

### Go — Raw calls, no auto-poll
```
1. client.InitOtp(...)
2. User receives code
3. client.VerifyOtp(...)
4. Manual polling loop (no auto-poll!)
5. client.OtpAuth(...)
```

### Rust — Raw calls + auto-poll
```
1. client.init_otp(body)
2. User receives code
3. client.verify_otp(body)
4. client.otp_auth(body)  ← auto-polls with exponential backoff
```

### Python — Raw calls + blocking poll
```
1. client.init_otp(body)
2. User receives code
3. client.verify_otp(body)
4. client.otp_auth() + blocking time.sleep() poll
```

### Ruby — Raw API calls, no flow helpers
```
Raw API calls, no flow helpers, no auto-polling, no OTP session helper
```

---

## API Naming Consistency

### TypeScript / React / React Native — Identical (shared @turnkey/core base)

**Shared (web + native):**
- `initOtp` → `verifyOtp` → `loginWithOtp` / `signUpWithOtp`
- `loginWithPasskey` / `signUpWithPasskey`
- `loginWithOauth` / `signUpWithOauth`
- `createWallet`, `importWallet`, `exportWallet`
- `signMessage`, `signTransaction`, `signAndSendTransaction`
- `logout`

**Web-only (no native equivalent):**
- `handleLogin()` — one-liner that shows full configured auth modal (huge DX win)
- `connectWalletAccount`, `disconnectWalletAccount`, `fetchWalletProviders` — MetaMask/Phantom/WalletConnect
- `loginWithWallet`, `signUpWithWallet` — SIWE/SIWS flows

**Native-only:**
- `handleGoogleOauth`, `handleAppleOauth`, `handleFacebookOauth`, `handleDiscordOauth`, `handleXOauth` — native in-app browser handlers
- `getProxyAuthConfig` — fetch Auth Proxy config at runtime

### Flutter / Android — Different naming (separate implementations, not shared-core)
- `loginOrSignUpWithOtp` vs. `loginWithOtp` (TS/React)

---

## Deprecation Landscape

There is a quiet but significant migration happening in the TypeScript ecosystem that is poorly communicated in docs:

| Old Package | New Package | Migration Impact |
|-------------|-------------|-----------------|
| `@turnkey/sdk-react` | `@turnkey/react-wallet-kit` | Old: manage 4 clients manually. New: single `useTurnkey()` hook. Huge DX improvement. No deprecated badge on docs page. |
| `@turnkey/sdk-react-native` | `@turnkey/react-native-wallet-kit` | Old: ~10 methods exposed. New: 60+ methods. Enormous difference. No "use this for new projects" guidance. |
| `@turnkey/sdk-browser` | `@turnkey/core` | Being superseded. |

---

## Identified Documentation Gaps

### 🔴 Critical

**#1 — Python docs page is completely wrong**
`sdks/python.mdx` has a copy-paste error that says "we do not yet offer a full SDK for *Rust*" (should say Python). It implies Python has no real SDK — but `tkhq/python-sdk` is a full generated client with 100+ typed methods, Pydantic v2 models, and activity polling. Page needs rewrite from scratch.
Correct install: `pip install turnkey-http turnkey-api-key-stamper`

**#2 — Go SDK docs are essentially blank**
`sdks/golang.mdx` contains only a title and a GitHub link. Go is a full production SDK with 300+ types, ED25519 support, HPKE encryption, Nitro proof verification, and working examples (email OTP, delegated access, Ethereum integration).

**#3 — Rust SDK docs are essentially blank**
`sdks/rust.mdx` — same problem. Rust is a fully-capable Turnkey API client (wallet, policy, OTP, OAuth, gas station, TVC). Only 4 examples exist and the docs page is effectively empty. The server SDK intro table also has wrong checkmarks for Rust.

### 🟡 Significant

**#4 — Server SDK intro table is incomplete**
The table in `sdks/introduction.mdx` only has 3 rows for server SDKs (Auth, Wallet, Policy). Missing: HPKE support, activity polling behavior, proof verification, session management, gas station, ED25519, TVC.

**#5 — Activity polling gap not documented**
TypeScript + Rust auto-poll; Go + Ruby do not. Python polls but blocks. This is a critical production consideration developers will hit and suffer for.

**#6 — Ruby wallet export limitation not documented**
Ruby can call the export API but cannot decrypt the result (no HPKE). Developer will silently get an unusable encrypted blob.

**#7 — Facebook OAuth gap on mobile unexplained**
Facebook OAuth is supported on TS/React/React Native but absent from Flutter, iOS, Android. No explanation or workaround in docs.

**#8 — Python async/blocking poll is undocumented**
Python SDK uses synchronous `time.sleep()` for polling. Breaking for async Python apps. Also default retry count (3) is too low for production.

**#9 — @turnkey/sdk-react deprecation lacks prominent labeling**
No deprecated badge. Migration guide exists but is not linked from the main docs page.

**#10 — React Native old vs. new package is confusing**
Old `@turnkey/sdk-react-native` (~10 methods) vs new `@turnkey/react-native-wallet-kit` (60+ methods). No "use this for new projects" guidance.

**#11 — handleLogin() vs native UI not explained**
Web React has a one-liner `handleLogin()` that shows a full configured auth modal. Native SDKs have no equivalent — developers must build their own auth UI. Never explained or compared in docs.

### 🔵 Minor

**#12 — Go's ED25519 support isn't highlighted**
Go is the only SDK that supports ED25519 API key signing (useful for Near, Aptos, Sui). Not mentioned anywhere in docs.

**#13 — @turnkey/telegram-cloud-storage-stamper is completely undocumented**
Exists in the TS monorepo. No mention anywhere in docs.

**#14 — @turnkey/gas-station and @turnkey/eip-1193-provider absent from intro table**
Both packages exist and are in use but missing from the SDK intro table.

**#15 — Rust TVC CLI is unmentioned**
Experimental but real feature in the Rust SDK. Zero documentation.

**#16 — Rust server SDK intro table has wrong checkmarks**
Table should reflect that Rust supports wallet, policy, OTP, OAuth, gas station, and TVC.

**#17 — Zero Rust examples for OTP, OAuth, or user management**
API client supports it, but no examples exist. Developers can't discover these features.

**#18 — pollTransactionStatus undocumented**
Method exists in React + React Native wallet kits for gas station tx tracking. Never documented.

**#19 — Go ergonomics quirk undocumented**
Requirement to pass `client.Authenticator` to every single API call is undocumented. First-time Go users will be confused.

**#20 — Python's lack of HPKE undocumented**
Python can call export API but can't decrypt the result. Not documented (same issue as Ruby).

**#21 — Python polling defaults undocumented**
`polling_interval_ms` and `max_polling_retries` (default: 3) are configurable but undocumented. 3 retries is too low for production.

---

## Bottom Line

- **TypeScript** is the canonical reference implementation — everything else is downstream
- **Go / Rust** are solid for server automation but have real ergonomic and doc gaps
- **Mobile SDKs** have high parity with each other; Facebook + Web3 wallet auth is the main gap vs. web
- **Python** has a real full SDK (`tkhq/python-sdk`) but docs actively mislead developers — needs a full rewrite
- **Ruby** is functional but limited: no HPKE, no polling, 2 examples
- **Deprecations** in the TS ecosystem (sdk-react, sdk-react-native, sdk-browser) are not clearly communicated

---

*Analysis from direct repository inspection. For current state, verify against source repos.*
