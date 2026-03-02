# Turnkey Technical Learnings

> Compiled by OpenClaw subagents via direct repository analysis.  
> Last updated: **2026-03-02**

This repo is a technical knowledge base for the [Turnkey](https://turnkey.com) platform — covering architecture, SDK internals, cross-SDK patterns, and documentation gaps. It's intended as an onboarding accelerator for engineers integrating with or building on Turnkey.

---

## Contents

| File | Description |
|------|-------------|
| [LEARNINGS.md](./LEARNINGS.md) | **Primary guide** — platform overview, architecture, core concepts, and all SDK summaries in one document |
| [sdk-feature-parity.md](./sdk-feature-parity.md) | Cross-SDK capability matrix, API naming consistency, deprecations, and documentation gaps |
| [sdk-learnings.md](./sdk-learnings.md) | TypeScript SDK deep-dive (30+ packages, monorepo architecture) |
| [go-sdk-learnings.md](./go-sdk-learnings.md) | Go SDK deep-dive (swagger-generated client, RoundTripper auth) |
| [rust-sdk-learnings.md](./rust-sdk-learnings.md) | Rust SDK deep-dive (trait-based stamping, built-in exponential backoff polling) |
| [python-sdk-learnings.md](./python-sdk-learnings.md) | Python SDK deep-dive (Pydantic v2, sync-only, 100+ typed methods) |
| [swift-sdk-learnings.md](./swift-sdk-learnings.md) | Swift SDK deep-dive (iOS/macOS, Secure Enclave, async/await, SwiftUI) |
| [kotlin-sdk-learnings.md](./kotlin-sdk-learnings.md) | Kotlin SDK deep-dive (Android, Credential Manager, StateFlow, Coroutines) |
| [frames-learnings.md](./frames-learnings.md) | Frames system deep-dive (iframe isolation, HPKE, postMessage protocol) |
| [docs-learnings.md](./docs-learnings.md) | Docs site structure analysis and content gaps |

---

## Quick Start

If you're new to Turnkey, start with **[LEARNINGS.md](./LEARNINGS.md)**. It covers:

- What Turnkey is and who it's for
- The TEE/enclave architecture (QuorumOS on AWS Nitro)
- The organization/sub-organization model
- How request stamping works (`X-Stamp` header)
- The Activity-based API model
- All 8 SDK surfaces summarized

Then jump to the relevant SDK deep-dive file for your stack.

---

## SDK at a Glance

| SDK | Type | Auth Patterns | Notable |
|-----|------|--------------|---------|
| TypeScript | Client + Server | Passkey, OTP, OAuth, API Key, SIWE | 30+ packages, React hooks, chain adapters |
| Go | Server | API Key (P-256 + ED25519) | Swagger-generated, manual auth attachment, ED25519 unique |
| Rust | Server | API Key (P-256 + secp256k1) | Built-in exponential backoff, `#![forbid(unsafe_code)]`, TVC CLI |
| Python | Server | API Key (P-256) | Pydantic v2, sync-only, no HPKE decrypt |
| Swift | Client (iOS/macOS) | Passkey, OTP, OAuth (4 providers) | Secure Enclave, async/await, SwiftUI-native |
| Kotlin | Client (Android) | Passkey, OTP, OAuth (4 providers) | Credential Manager, StateFlow, lifecycle-aware |

---

## Key Cross-SDK Patterns

1. **Stamp Abstraction** — Every SDK implements the same `Stamper` concept (sign request body → `X-Stamp` header)
2. **HPKE for key transport** — `KEM_P256_HKDF_SHA256 + AES-256-GCM` used across TS, Go, Rust, Swift, Kotlin
3. **Activity-based mutations** — All writes are async activities; auto-polling varies by SDK
4. **Sub-org per user** — The canonical scaling pattern for consumer wallet apps
5. **Generated + handwritten split** — OpenAPI/swagger → types + HTTP client; handwriting handles auth and crypto ergonomics
6. **Mobile TurnkeyContext pattern** — Swift and Kotlin share nearly identical high-level APIs with platform-appropriate reactivity
7. **No raw key exposure** — Enforced at hardware (TEE), isolation (same-origin frames), and API levels

---

## Notable Documentation Gaps (as of 2026-03-02)

From `sdk-feature-parity.md`:

- 🔴 Python docs page incorrectly says no full SDK exists — there is one (`tkhq/python-sdk`)
- 🔴 Go and Rust SDK docs pages are essentially blank despite being full-featured
- 🟡 Activity polling behavior differences (auto vs. manual vs. blocking) are undocumented
- 🟡 Python lacks HPKE — wallet export returns an undecryptable blob (undocumented)
- 🟡 `@turnkey/sdk-react` → `@turnkey/react-wallet-kit` deprecation lacks prominent signage
- 🔵 Go's ED25519 API key support (unique across all SDKs) is unmentioned in docs

---

## Repository Info

- **Account:** `turnkeyintern` (fork account for research)
- **Compiled by:** OpenClaw AI agent via subagent repository analysis
- **Source repos analyzed:** `tkhq/docs`, `tkhq/sdk`, `tkhq/go-sdk`, `tkhq/rust-sdk`, `tkhq/frames`, `tkhq/python-sdk`, `tkhq/swift-sdk`, `tkhq/kotlin-sdk`
