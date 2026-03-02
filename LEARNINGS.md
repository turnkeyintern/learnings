# Turnkey Product Learnings

> **Compiled:** 2026-02-25 | **Updated:** 2026-03-02  
> **Sources:** Analyzed via subagents across 8 repositories: `docs`, `sdk` (TypeScript), `go-sdk`, `rust-sdk`, `frames`, `python-sdk`, `swift-sdk`, `kotlin-sdk`  
> **Purpose:** Shared onboarding guide for understanding the Turnkey platform and its developer surfaces

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [What is Turnkey?](#what-is-turnkey)
3. [Core Architecture](#core-architecture)
4. [Key Concepts & Terminology](#key-concepts--terminology)
5. [Product Surfaces Overview](#product-surfaces-overview)
6. [The Frames System (Iframe Security Layer)](#the-frames-system)
7. [TypeScript SDK](#typescript-sdk)
8. [Go SDK](#go-sdk)
9. [Rust SDK](#rust-sdk)
10. [Python SDK](#python-sdk)
11. [Swift SDK (iOS/macOS)](#swift-sdk-iosmacos)
12. [Kotlin SDK (Android)](#kotlin-sdk-android)
13. [Cross-Cutting Themes](#cross-cutting-themes)
14. [Open Questions](#open-questions)

---

## Executive Summary

Turnkey is a **verifiable, non-custodial key management infrastructure** platform. Its core promise: private keys are generated, stored, and used *exclusively* within Trusted Execution Environments (TEEs) — hardware-isolated enclaves that neither Turnkey, developers, nor attackers can access raw key material from.

**Two primary use cases:**
- **Embedded Wallets** — In-app crypto wallets with seamless UX (passkeys, email OTP, social login)
- **Transaction Automation** — Automated signing workflows with policy-governed access controls

**What makes it interesting architecturally:**
- Operates at the *cryptographic curve* level (secp256k1, ed25519, P-256, Stark) — not chain-specific, giving it broad blockchain compatibility
- Every API call is cryptographically stamped (signed) — prevents MITM and tampering
- The organization/sub-organization model is the scaling primitive: each end user gets their own isolated sub-org
- All SDKs share a consistent `Stamper` abstraction for authentication

---

## What is Turnkey?

### Product Overview

Turnkey sits between an application and the blockchain. Developers integrate Turnkey to:

1. **Create and manage wallets** without handling private keys in their codebase
2. **Sign transactions** through a policy-controlled API
3. **Authenticate users** via passkeys, email OTP, OAuth (Google/Apple/Facebook), or external wallets (SIWE)
4. **Automate signing** for AI agents, DeFi protocols, payments systems

### Target Customers

- DeFi platforms needing secure, automated signing
- Consumer wallet apps needing smooth onboarding (no seed phrase UX)
- Payments / fintech applications
- AI agent infrastructure requiring autonomous signing
- Any product embedding crypto without wanting to be the key custodian

### Key Differentiators vs. Alternatives

| Aspect | Turnkey | Traditional HSM | MPC Wallets |
|--------|---------|----------------|-------------|
| Key storage | TEE enclave | Hardware | Distributed shares |
| Auditability | Cryptographic remote attestation | Vendor trust | Protocol-dependent |
| Policy engine | Built-in DSL | Manual | Limited |
| Developer API | REST + SDKs | Low-level | SDK-dependent |
| Scale primitive | Sub-orgs (unlimited) | Limited | Limited |

---

## Core Architecture

### The Enclave Stack

```
┌──────────────────────────────────────────────────────┐
│  Developer Application                                │
│  (uses SDK / REST API with stamped requests)          │
└───────────────────────┬──────────────────────────────┘
                        │ HTTPS + X-Stamp header
                        ▼
┌──────────────────────────────────────────────────────┐
│  Turnkey API Layer                                    │
│  (routes requests, validates stamps)                  │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│  QuorumOS (custom Linux unikernel)                   │
│  running inside AWS Nitro TEE                         │
│  ┌────────────────────────────────────────────────┐  │
│  │  Private keys live here. Never exposed.        │  │
│  │  Deterministic builds + remote attestation     │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

**QuorumOS** is Turnkey's custom minimal Linux unikernel. Its deterministic builds allow cryptographic verification that the code running in the enclave is exactly what was audited. This is the "verifiable" in "verifiable key management."

### Organization Model

```
Parent Organization (your app)
│
├── Policies (govern all actions)
├── Users (admin/developer users)
├── Wallets (company-level wallets)
│
└── Sub-Organizations (one per end user)
    ├── Root User (the end user's credentials)
    ├── Policies
    ├── Wallets
    └── Private Keys
```

- **Parent org** has read-only access to sub-orgs (cannot sign on behalf of users)
- **Sub-orgs are unlimited** — the scaling primitive for millions of users
- Each sub-org has its own root quorum, policies, wallets

### API Model: Activities

Every mutating operation is an **Activity** — an async job that:
1. Gets submitted via API
2. May require policy approval
3. Returns a result (with polling until complete)
4. Is immutably logged

This is why all SDKs implement activity polling with retry/backoff logic.

### Request Authentication: The Stamp

Every API request must carry an `X-Stamp` header containing a cryptographic signature:

```
X-Stamp: {
  publicKey: <API key public key>,
  scheme: "SIGNATURE_SCHEME_TK_API_P256",
  signature: <ECDSA signature over SHA-256(request body)>
}
```

This prevents any MITM or request tampering. The stamp is what "Stampers" in the SDK produce.

---

## Key Concepts & Terminology

### Organizational Structure

| Term | Definition |
|------|-----------|
| **Organization** | Top-level entity for a Turnkey-powered application |
| **Sub-Organization** | Isolated org for an end user; parent has read-only access |
| **Root User** | User who can bypass the policy engine; part of root quorum |
| **Root Quorum** | Consensus threshold of root users for root-level actions |
| **Normal User** | Has no permissions unless explicitly granted by policies |

### Authentication & Credentials

| Term | Definition |
|------|-----------|
| **API Key** | P-256 or secp256k1 key pair used for programmatic auth |
| **Passkey / Authenticator** | WebAuthn device for browser/dashboard auth |
| **Stamp** | Cryptographic signature over request body proving auth |
| **Stamper** | SDK module that produces stamps (API key, WebAuthn, wallet, iframe) |
| **Email OTP** | One-time password sent to email for auth/recovery |
| **OAuth** | Google/Apple/Facebook social login support |

### Wallets & Keys

| Term | Definition |
|------|-----------|
| **Wallet** | HD wallet derived from a seed phrase; generates multiple accounts |
| **Wallet Account** | A derived address from a wallet (curve + derivation path + address format) |
| **Private Key** | Raw private key (not recommended; prefer Wallets) |
| **Credential Bundle** | Encrypted private key material sent via secure channels (email/iframe) |

### Activities & Policies

| Term | Definition |
|------|-----------|
| **Activity** | Async mutating operation (create wallet, sign transaction, etc.) |
| **Policy** | Rule governing who can perform which actions under what conditions |
| **Policy Engine** | Turnkey's built-in DSL for access control (supports EVM, Solana, Bitcoin parsing) |
| **Consensus** | Multi-user approval requirement for sensitive activities |
| **Effect** | What a policy does: `ALLOW`, `DENY`, or `ALLOW_WITH_CONSENSUS` |

### Supported Cryptographic Curves

- **secp256k1** — Ethereum, Bitcoin, and most EVM chains
- **ed25519** — Solana, Near, Aptos, Sui
- **P-256** — Used for API keys, passkeys, and iframe/frame crypto
- **secp256r1** — Passkeys (same as P-256, different alias)
- **Stark** — StarkNet

---

## Product Surfaces Overview

Turnkey exposes multiple surfaces depending on use case:

| Surface | Purpose | Primary Users |
|---------|---------|--------------|
| **Dashboard** | Web UI for managing orgs, policies, users | DevOps / Admin |
| **REST API** | Core API with stamped requests | All developers |
| **TypeScript SDK** | 30+ packages for JS/TS apps | Web / Node devs |
| **Go SDK** | Go client with generated API types | Backend Go devs |
| **Rust SDK** | Rust client for systems/CLI use | Backend Rust devs |
| **Frames** | Iframe pages for secure browser crypto | Browser UX flows |
| **React Wallet Kit** | Drop-in React components + hooks | React app devs |
| **Chain Signers** | Viem, Ethers, Solana, CosmJS adapters | dApp devs |
| **Policy Engine** | DSL for access control | Security-conscious builders |

---

## The Frames System

*Full details in: `frames-learnings.md`*

### What Frames Are

Frames are **self-contained HTML pages** hosted on Turnkey's domains (`auth.turnkey.com`, `import.turnkey.com`, `export.turnkey.com`) that handle sensitive cryptographic operations in an isolated browser context.

They are **not** Farcaster frames — they are browser iframes using same-origin policy for security isolation.

### Frame Types

| Frame | Domain | Purpose |
|-------|--------|---------|
| `auth` | auth.turnkey.com | Email OTP auth + credential recovery |
| `import` | import.turnkey.com | Securely import private keys/mnemonics |
| `export` | export.turnkey.com | Export private keys (decrypt from enclave) |
| `export-and-sign` | — | Export keys + sign Solana txns in-iframe |
| `oauth-origin` | — | Google/Apple/Facebook OAuth flows |
| `oauth-redirect` | — | OAuth callback handler |

### How Isolation Works

```
Parent App                          Turnkey Frame
(your-app.com)                      (auth.turnkey.com)
      │                                     │
      │──── postMessage(init) ─────────────►│
      │                                     │  Generates P-256 keypair
      │                                     │  (keys never leave iframe)
      │◄─── postMessage(publicKey) ─────────│
      │                                     │
      │  [App calls Turnkey API with        │
      │   iframe public key as target key]  │
      │                                     │
      │──── postMessage(encryptedBundle) ──►│
      │                                     │  HPKE decrypt
      │                                     │  Use credential
      │◄─── postMessage(result/stamp) ──────│
```

### Cryptographic Stack in Frames

- **P-256 ECDH** — Key generation for enclave communication
- **HPKE (RFC 9180)** — Hybrid encryption (KEM_P256_HKDF_SHA256 + AES-256-GCM)
- **Base58check** — Encoding for email auth bundles
- **WebCrypto API** — Browser-native crypto (no external crypto libs)
- **ECDSA** — Enclave attestation signatures

### Key Design Decision

The parent application *can never access raw key material*. It only communicates intent via `postMessage`. The frame performs all sensitive operations internally. This is enforced by browser same-origin policy — not application-level trust.

---

## TypeScript SDK

*Full details in: `sdk-learnings.md`*

### Architecture

The SDK is a **pnpm monorepo** with 30+ packages organized in tiers:

```
Tier 1: Core Foundation
  @turnkey/core          → Session management, stamper interface, utilities
  @turnkey/http          → Low-level generated HTTP client (OpenAPI)
  @turnkey/sdk-types     → Shared TypeScript types

Tier 2: Platform SDKs
  @turnkey/sdk-server    → Server-side client (Node.js)
  @turnkey/react-wallet-kit → React Provider + hooks

Tier 3: Stampers (Authentication)
  @turnkey/api-key-stamper     → API key auth (server-side)
  @turnkey/webauthn-stamper    → Passkey auth (browser)
  @turnkey/wallet-stamper      → External wallet auth (SIWE)
  @turnkey/iframe-stamper      → Recovery/export flows
  @turnkey/indexed-db-stamper  → Browser IndexedDB key storage

Tier 4: Chain Adapters
  @turnkey/viem    → Viem LocalAccount adapter
  @turnkey/ethers  → Ethers.js TurnkeySigner
  @turnkey/solana  → Solana Web3.js signer
  @turnkey/cosmjs  → CosmJS signer
```

### The Stamper Pattern

Every SDK client takes a `stamper` parameter. Stampers are interchangeable — switching auth method means swapping the stamper:

```typescript
// Server-side with API key
const client = new TurnkeyServerClient({
  apiBaseUrl: "https://api.turnkey.com",
  organizationId: process.env.ORGANIZATION_ID,
  stamper: new ApiKeyStamper({
    apiPublicKey: process.env.API_PUBLIC_KEY,
    apiPrivateKey: process.env.API_PRIVATE_KEY,
  }),
});

// Browser with passkey
const client = new TurnkeyBrowserClient({
  stamper: new WebauthnStamper({ rpId: "your-app.com" }),
  // ...
});
```

### React Integration

```typescript
// App wrapper
<TurnkeyProvider config={{ apiBaseUrl, organizationId }}>
  <YourApp />
</TurnkeyProvider>

// In components
const { turnkey, passkeyClient, authIframeClient } = useTurnkey();
```

### Server Actions (Next.js pattern)

```typescript
// server.ts — runs on server
export const { sendOtp, verifyOtp, createWallet } = 
  turnkeyServer.serverActions();

// component.tsx — calls as regular async function
await sendOtp({ organizationId, otpType: "OTP_TYPE_EMAIL", contact: email });
const result = await verifyOtp({ organizationId, otpId, otpCode });
```

### Activity-Based Mutations

All mutations follow an async activity pattern:

```typescript
const { activity } = await client.createWallet({ ... });
// activity.status may be PENDING → COMPLETE
// SDK auto-polls until resolution
```

### 60+ Examples Available

The repo includes examples for: passkey auth, email OTP, OAuth, magic links, ERC-4337 account abstraction, Uniswap integration, cross-chain signing, Farcaster frames, and more.

---

## Go SDK

*Full details in: `go-sdk-learnings.md`*

### Architecture

```
go-sdk/
├── pkg/
│   ├── api/          # Swagger-generated client (do not edit manually)
│   ├── apikey/       # Handwritten API key stamping logic
│   ├── enclave/      # HPKE enclave encryption
│   ├── proofs/       # AWS Nitro attestation verification
│   └── version/      # Embedded version constant
├── client.go         # Main TurnkeyClient with RoundTripper middleware
└── examples/         # Integration examples
```

### Key Types

```go
// Main client
type TurnkeyClient struct {
    APIClient     *apiclient.TurnkeyAPI  // swagger-generated
    Authenticator runtime.ClientAuthInfoWriter
}

// Auth stamp
type APIStamp struct {
    PublicKey  string `json:"publicKey"`
    Signature  string `json:"signature"`
    Scheme     string `json:"scheme"`
}

// Key abstraction (supports P-256 and secp256k1)
type Key interface {
    TkPublicKey() string
    Sign(payload []byte) ([]byte, error)
}
```

### Authentication Pattern

The Go SDK uses a **RoundTripper middleware** to automatically stamp every request:

```go
key, _ := apikey.FromTurnkeyPrivateKey(privateKeyHex, apikey.Secp256k1)
client := &TurnkeyClient{
    APIClient: apiclient.NewHTTPClientWithConfig(nil, cfg),
}
// Attach authenticator to each call (required — no global default)
params.WithHTTPClient(&http.Client{
    Transport: &apikey.Signer{Key: key},
})
```

### Enclave Encryption (HPKE)

Used for wallet export flows:

```go
targetKey, _ := enclave.NewTargetKey()  // generates P-256 keypair
// Send targetKey.TkPublicKey() to Turnkey API
// Receive encrypted bundle back
decrypted, _ := targetKey.Decrypt(bundle)
```

### Key Observations

- The activity-based API requires manual `Authenticator` attachment to every call — the SDK doesn't set a global default
- Code is split: swagger-generated (`pkg/api/`) vs. handwritten logic (`apikey/`, `client.go`)
- Generics are used for key storage abstraction
- Functional options pattern for client construction

---

## Rust SDK

*Full details in: `rust-sdk-learnings.md`*

### Crate Structure

```
rust-sdk/
├── turnkey_api_key_stamper/   # API request signing (P-256 or secp256k1)
├── turnkey_client/            # Main async HTTP client with retry logic
├── turnkey_enclave_encrypt/   # HPKE encryption for key export/import
├── turnkey_proofs/            # AWS Nitro attestation verification
├── codegen/                   # Proto → Rust code generation (internal)
└── tvc/                       # Experimental Turnkey Vault CLI
```

**Published on crates.io** at version 0.6.0.

### The `Stamp` Trait

```rust
pub trait Stamp: Send + Sync {
    fn stamp(&self, body: &str) -> Result<ApiStamp>;
    fn public_key(&self) -> &str;
}

// Implementations:
// - P256Stamper (standard API key)
// - Secp256k1Stamper (alternative)
```

### Client Pattern

```rust
let stamper = P256Stamper::from_pem(private_key_pem)?;
let client = TurnkeyClient::builder()
    .base_url("https://api.turnkey.com")
    .organization_id(&org_id)
    .stamper(Arc::new(stamper))
    .build()?;

// All mutations auto-poll until complete:
let result = client.create_wallet(request).await?;
```

### Automatic Activity Polling

Unlike Go, the Rust client has **built-in polling with exponential backoff**:

```rust
// Internally, after submitting an activity:
// 1. Submits activity
// 2. Polls with backoff: 1s, 2s, 4s... until COMPLETE/FAILED
// 3. Returns typed result
```

### Crypto Stack

| Operation | Algorithm |
|-----------|-----------|
| API signing | P-256 or secp256k1 ECDSA |
| Enclave communication | HPKE (KEM_P256_HKDF_SHA256 + AES-256-GCM) |
| AWS attestation | P-384 ECDSA |
| Encoding | Base58Check for auth bundles |

### Code Quality Signals

```rust
#![forbid(unsafe_code)]
#![deny(clippy::unwrap_used)]
```

Strong linting stance. Comprehensive tests with `wiremock` for HTTP mocking. Newtype wrappers for crypto types with hex serde serialization.

---

## Python SDK

*Full details in: `python-sdk-learnings.md`*

### Architecture

The Python SDK is a **pip monorepo** with three packages following the same patterns as the TypeScript SDK:

```
python-sdk/
├── packages/
│   ├── sdk-types/          # turnkey-sdk-types (7,700+ lines of Pydantic models)
│   ├── http/               # turnkey-http (5,000+ lines auto-generated HTTP client)
│   └── api-key-stamper/    # turnkey-api-key-stamper (~100 lines ECDSA signing)
├── codegen/                # Custom Python scripts (not third-party generators)
└── schema/
    └── public_api.swagger.json
```

### Usage Pattern

```python
from turnkey_http import TurnkeyClient
from turnkey_api_key_stamper import ApiKeyStamper, ApiKeyStamperConfig

stamper = ApiKeyStamper(ApiKeyStamperConfig(
    api_public_key="your-api-public-key",
    api_private_key="your-api-private-key"
))

client = TurnkeyClient(
    base_url="https://api.turnkey.com",
    stamper=stamper,
    organization_id="your-org-id",
    polling_interval_ms=1000,
    max_polling_retries=3
)

# Activity call — auto-polls and flattens result
response = client.create_wallet(CreateWalletBody(
    walletName="My Wallet",
    accounts=[...]
))
print(response.walletId)  # Flattened from activity result
```

### Key Characteristics

- **Sync only** — uses `requests` + `time.sleep()` for polling; no asyncio support
- **Pydantic v2** — all API types are Pydantic models with alias support
- **Activity flattening** — result fields merged into response object post-poll
- **Stamp-then-send pattern** — `stamp_create_wallet()` returns a `SignedRequest` without sending, enabling server-side signing workflows
- **Public key validation** — stamper derives and validates the public key from the private key at call time

### ⚠️ Notable Limitations

- Blocking `time.sleep()` poll breaks async frameworks (FastAPI, Starlette, Django async)
- Default `max_polling_retries=3` is low for production use
- No HPKE — can call the wallet export API but cannot decrypt the result
- P-256 signing only (no secp256k1 or ED25519)

---

## Swift SDK (iOS/macOS)

*Full details in: `swift-sdk-learnings.md`*

### Architecture

The Swift SDK uses **Swift Package Manager (SPM)** with a layered module design:

```
TurnkeySwift (all-in-one)
├── TurnkeyHttp          → Generated HTTP client + activity polling
│   └── TurnkeyTypes     → Auto-generated Codable types (~16k+ lines)
├── TurnkeyStamper       → Request signing (API keys, passkeys, Secure Enclave)
│   ├── TurnkeyPasskeys  → ASAuthorization wrappers (Face ID / Touch ID)
│   ├── TurnkeyCrypto    → P-256, HPKE
│   └── TurnkeyKeyManager → Secure Enclave + Keychain storage
└── TurnkeyEncoding      → Hex, Base58, Base64URL
```

**Target platforms:** iOS 17+, macOS 14+, tvOS 16+, watchOS 9+, visionOS 1.0

### Usage Pattern

```swift
// App startup
TurnkeyContext.configure(TurnkeyConfig(
    apiUrl: "https://api.turnkey.com",
    authProxyConfigId: "your-config-id",
    rpId: "your-domain.com",
    organizationId: "your-org-id",
    auth: .init(oauth: .init(appScheme: "yourapp", providers: ...))
))

// SwiftUI binding — TurnkeyContext is an @ObservableObject
@EnvironmentObject var context: TurnkeyContext

if context.authState == .authenticated {
    DashboardView()
} else {
    LoginView()
}

// Auth flows (all async/await)
try await TurnkeyContext.shared.signUpWithPasskey(anchor: anchor, ...)
try await TurnkeyContext.shared.verifyOtp(otpId: id, otpCode: "123456")
let sig = try await TurnkeyContext.shared.signMessage(signWith: account, message: "Hello!")
```

### Key Characteristics

- **Secure Enclave** — on-device P-256 key generation; private key never leaves the TEE (device-bound)
- **Keychain fallback** — `SecureStorageManager` for simulators and non-enclave devices
- **Pure async/await** — no Combine publishers or completion handlers anywhere
- **SwiftUI-native** — `@ObservableObject` + `@Published` properties for reactive bindings
- **Extension-based** — `TurnkeyContext` split across `+Session`, `+Wallet`, `+OAuth`, `+Otp`, `+Passkey` files
- **4 OAuth providers** — Google, Apple, Discord, X (via `ASWebAuthenticationSession`)
- **Auth Proxy support** — backend-optional pattern via Turnkey's managed proxy

### Platform-Specific Highlights

| Feature | Framework Used |
|---------|---------------|
| Passkeys | `AuthenticationServices` (ASAuthorization) |
| Secure Enclave | `Security` framework |
| Biometrics | `LocalAuthentication` (Face ID / Touch ID) |
| OAuth | `ASWebAuthenticationSession` |
| PKCE | Built-in verifier/challenge generation |

---

## Kotlin SDK (Android)

*Full details in: `kotlin-sdk-learnings.md`*

### Architecture

The Kotlin SDK uses a **multi-module Gradle monorepo** with clear separation of concerns:

```
kotlin-sdk/packages/
├── sdk-kotlin/    → TurnkeyContext singleton (high-level, Android lifecycle-aware)
├── http/          → Generated typed HTTP client (OkHttp + Kotlin coroutines)
├── types/         → Generated DTOs from OpenAPI (kotlinx.serialization)
├── stamper/       → Request signing (API keys + passkeys)
├── passkey/       → Android Credential Manager wrappers
├── crypto/        → P-256 key ops, HPKE, bundle encryption (Bouncy Castle)
├── encoding/      → Hex, Base64url, secure random
└── tools/         → Internal codegen with KotlinPoet (not published)
```

**Target:** Android (minSdk 28 / Android 9+), with JVM compatibility for lower modules.

### Usage Pattern

```kotlin
// App initialization
TurnkeyContext.init(app = this, config = TurnkeyConfig(
    authProxyConfigId = "<config-id>",
    organizationId = "<org-id>",
    appScheme = "myapp",
    authConfig = AuthConfig(rpId = "myapp.example.com", ...)
))

// Reactive state (StateFlow)
lifecycleScope.launch {
    TurnkeyContext.authState.collect { state ->
        when (state) {
            AuthState.authenticated -> showDashboard()
            AuthState.unauthenticated -> showLogin()
            AuthState.loading -> showSpinner()
        }
    }
}

// Auth + wallet ops
TurnkeyContext.loginWithPasskey(activity = requireActivity(), rpId = "myapp.example.com")
TurnkeyContext.loginOrSignUpWithOtp(otpId = id, otpCode = code, contact = email)
TurnkeyContext.signMessage(signWith = address, message = "Hello, Turnkey!", addEthereumPrefix = true)
```

### Key Characteristics

- **Object singleton** — `TurnkeyContext` as a Kotlin `object` (vs Swift's class singleton)
- **StateFlow-based reactivity** — `authState`, `session`, `wallets`, `user` as `StateFlow<T>`
- **Sealed class errors** — `TurnkeyKotlinError` hierarchy for exhaustive `when` handling
- **CompletableDeferred init** — `awaitReady()` suspends until init completes (vs Swift's `@Published` approach)
- **Lifecycle-aware** — uses `ProcessLifecycleOwner` to purge expired sessions/keys on foreground
- **Credential Manager** — wraps `androidx.credentials` for passkey registration and assertion
- **SharedPreferences key store** — current default; Android Keystore recommended for production
- **4 OAuth providers** — Google, Apple, Discord, X (via OAuth deep-link Activity + `OAuthEvents` SharedFlow)

### Key Differences vs Swift SDK

| Aspect | Kotlin (Android) | Swift (iOS/macOS) |
|--------|-----------------|-------------------|
| Singleton pattern | `object TurnkeyContext` | `class TurnkeyContext` (NSObject) |
| Reactivity | `StateFlow` (Kotlin Flows) | `@Published` (ObservableObject) |
| Passkeys | Credential Manager | ASAuthorization |
| Key storage | SharedPreferences (⚠️ consider Keystore) | Secure Enclave / Keychain |
| Concurrency | Kotlin Coroutines | Swift async/await |
| Init sync | `CompletableDeferred` + `awaitReady()` | Static `configure()` |
| Facebook OAuth | ❌ Not supported | ❌ Not supported |

---

## Cross-Cutting Themes

These patterns appear consistently across all SDKs and repos:

### 1. The Stamp Abstraction is Universal
Every SDK (TS, Go, Rust) implements the same conceptual Stamper pattern. The specifics differ (trait/interface/class), but the contract is identical: take a request body, return a signed stamp for the `X-Stamp` header.

### 2. HPKE Everywhere for Key Material Transport
All three SDKs implement HPKE (RFC 9180) with `KEM_P256_HKDF_SHA256 + AES-256-GCM` for secure key export/import flows. This is how encrypted credential bundles are transported between the enclave and the client.

### 3. Activity-Based API Model
All mutations are async activities. TypeScript and Rust SDKs handle polling automatically. The Go SDK is more manual — requires the caller to attach authenticators and handle polling.

### 4. Sub-Org Per User Pattern
The canonical scaling pattern across all docs and examples is: one sub-org per end user, with the parent org acting as an administrative overlay. This gives users full custody semantics.

### 5. Policy Engine as the Security Layer
The policy DSL is the mechanism for everything from simple allowlists to complex multi-party approval workflows. It supports chain-specific parsing (EVM calldata, Solana instructions, Bitcoin outputs) — not just metadata matching.

### 6. Generated + Handwritten Split
All SDKs follow the same architecture: OpenAPI/protobuf-generated code for API types + handwritten code for auth stamping, enclave crypto, and client ergonomics.

### 7. No Raw Key Exposure by Design
This is enforced at multiple levels: TEE hardware, frame isolation (same-origin policy), and SDK APIs that never surface raw key bytes to the caller.

### 8. Mobile SDKs Share the TurnkeyContext Pattern
Both the Swift (iOS) and Kotlin (Android) SDKs use a singleton `TurnkeyContext` with reactive state bindings (`@Published` / `StateFlow`), standardized `AuthState` enum, and the same auth-flow surface (passkeys, OTP, OAuth). They mirror each other closely while adapting to platform idioms. Key divergence: Swift uses Secure Enclave for hardware-bound keys; Kotlin currently uses SharedPreferences (Android Keystore recommended for production).

### 9. Python is the Odd One Out in the Server Tier
Unlike TypeScript and Rust (which have native async polling), the Python SDK blocks with `time.sleep()`. It also lacks HPKE decryption, making wallet export a half-story. Despite being a full, well-typed SDK (Pydantic v2, 100+ methods), its docs actively mislead developers — this is the single biggest documentation gap across the entire platform.

---

## Open Questions

These came up across multiple repos and are worth investigating:

1. **Rate limiting** — No docs/code on rate limits. What are the API quotas per org/sub-org?

2. **Key rotation** — How do you rotate API keys or wallet keys without service interruption?

3. **Policy ordering** — When multiple policies match, how is the evaluation order determined?

4. **Attestation verification in practice** — How often should clients verify enclave attestations? Is there a client-side library for this beyond the Rust proof crate?

5. **Billing model** — How does billing work? Per sub-org? Per activity? Per wallet?

6. **Frame versioning** — How are breaking changes handled in frames without breaking embedded apps?

7. **Disaster recovery** — What happens if Turnkey has an outage? Can keys be exported ahead of time?

8. **Sub-org limits** — The docs say parent keys are limited to 1,000 private keys, but sub-orgs are "unlimited." Is there any practical limit?

9. **OAuth security** — How does Turnkey verify OAuth claims? What prevents impersonation if an OAuth token is compromised?

10. **Solana export-and-sign** — The `export-and-sign` frame is unusual (sign a tx inside the iframe). When is this the right pattern vs. regular signing via API?

---

*Initially compiled from analysis of `tkhq/docs`, `tkhq/sdk`, `tkhq/go-sdk`, `tkhq/rust-sdk`, and `tkhq/frames` by OpenClaw subagents on 2026-02-25. Updated 2026-03-02 with `tkhq/python-sdk`, `tkhq/swift-sdk`, and `tkhq/kotlin-sdk`.*
