# Turnkey Documentation Learnings

*Comprehensive analysis of the Turnkey docs repository*

---

## What is Turnkey?

### Product Overview

**Turnkey** is a secure, scalable, and programmable crypto infrastructure platform designed for two primary use cases:

1. **Embedded Wallets** — Create in-app wallets for end users with seamless authentication (passkeys, email, social logins)
2. **Transaction Automation** — Automate complex signing workflows at scale with granular policy controls

### Core Value Proposition

- **Security-first architecture**: All private keys are generated, stored, and used within secure enclaves (Trusted Execution Environments). Raw private keys are never exposed to Turnkey, your software, or your team.
- **Non-custodial by design**: Turnkey is the first "verifiable key management system" — users can cryptographically verify that only authorized code runs in enclaves.
- **Flexibility**: Operates at the cryptographic curve level (secp256k1, ed25519) rather than specific chains, making it chain-agnostic.
- **Developer experience**: Pre-built UI components, comprehensive SDKs across platforms, and a powerful policy engine.

### Target Users

- DeFi platforms
- Payments applications  
- AI agents requiring private key signing
- Any application requiring embedded wallets or automated transaction signing

---

## Key Concepts & Terminology

### Organizational Hierarchy

| Term | Definition |
|------|------------|
| **Organization (Parent Org)** | Top-level entity representing a Turnkey-powered application. Contains users, wallets, policies, and other resources. |
| **Sub-Organization (Sub-Org)** | Fully segregated organization nested under a parent org, typically representing an end user. Parent orgs have **read-only** access to sub-orgs. |
| **Resources** | All identifiers within orgs: users, policies, wallets, private keys, API keys, authenticators. |

### Users & Authentication

| Term | Definition |
|------|------------|
| **Root User** | User with root permissions that can bypass the policy engine. Part of the root quorum. |
| **Root Quorum** | A consensus threshold of root users required to execute root-level actions. |
| **Normal User** | Has no permissions unless explicitly granted by policies. |
| **Credentials** | Methods for authenticating to Turnkey: API keys, passkeys (WebAuthn), OAuth, email/SMS OTP. |
| **Authenticator** | A WebAuthn device registered on Turnkey for dashboard/API authentication. |

### Wallets & Keys

| Term | Definition |
|------|------------|
| **Wallet** | An HD (hierarchical deterministic) wallet derived from a seed phrase. Can generate multiple accounts. Preferred over raw private keys. |
| **Wallet Account** | A derived address from a wallet, used for signing. Contains curve, path, and address format info. |
| **Private Key** | Raw private key (not recommended — use wallets instead). Limited to 1,000 per org. |

### Activities & Policies

| Term | Definition |
|------|------------|
| **Activity** | Any action taken by a user (signing, creating users, creating sub-orgs, etc.). All activities are evaluated by the policy engine. |
| **Policy** | JSON-defined rules that govern permissions. Uses a custom policy language with `effect` (ALLOW/DENY), `consensus` (who can act), and `condition` (under what circumstances). |
| **Stamp** | A cryptographic signature over the POST body attached as an HTTP header (`X-Stamp`). Every API request must be stamped. |

### Sessions

| Term | Definition |
|------|------------|
| **Read-Only Session** | Session for retrieving data. Parent orgs have implicit read access to all sub-orgs. |
| **Read-Write Session** | Session allowing multiple authenticated write requests within a time window. Uses client-side generated API keys stored in IndexedDB (web) or SecureStorage (mobile). |

---

## Product Surfaces

### 1. Embedded Wallets

Features:
- **Embedded Wallet Kit**: Pre-built React components for rapid integration
- **Multi-platform SDKs**: React, React Native, Flutter, Swift (iOS), Kotlin (Android), TypeScript
- **Authentication methods**: Passkeys, email OTP, SMS OTP, social logins (Google, Apple, Discord, X, Facebook), wallet auth (SIWE/SIWS)
- **Wallet operations**: Create, import, export wallets; sign messages and transactions
- **Sessions**: Sign multiple transactions without repeated approvals
- **Account abstraction**: Simple integrations for gas sponsorship and smart contract wallets
- **Pre-generated wallets**: Generate wallets before user authentication

### 2. Transaction Automation

Features:
- **Server-side SDKs**: TypeScript, Go, Ruby, Rust, Python
- **API-based authentication**: Create API keys with scoped permissions
- **Multi-signature approvals**: Set quorum requirements for transactions
- **Webhooks**: Receive activity notification events
- **Compliance/audit trail**: Track all events and changes

### 3. Transaction Management (Gas Sponsorship)

Turnkey provides gasless transaction capabilities:
- **Gas sponsorship**: Users don't need native tokens; Turnkey covers fees
- **Transaction construction & broadcast**: Turnkey handles nonce, gas estimation, signing, and broadcasting
- **Transaction monitoring**: Real-time status updates and enriched error messages
- **Spend limits**: Configure USD gas limits at org and sub-org levels
- **Supported chains**: Base, Polygon, Ethereum (mainnet + testnets)

### 4. Turnkey Dashboard

Web interface for:
- Creating and managing organizations
- User/credential management
- Policy configuration
- Viewing activity logs
- API key generation

### 5. API

- **RPC-over-HTTP**: All requests are POST with stamped bodies
- **Two categories**: Queries (read) and Submissions (write/activities)
- **Comprehensive OpenAPI spec**: `public_api.swagger.json` included

### 6. CLI

Command-line tool (`tkcli`) for:
- Generating stamps
- Debugging stamping logic
- Local development

---

## Architecture Overview

### Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Turnkey Infrastructure                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────┐      ┌────────────────────────────────┐ │
│  │   Host (AWS)   │──────│     Secure Enclave (Nitro)     │ │
│  │                │      │                                 │ │
│  │  • Network I/O │      │  • QuorumOS (minimal Linux)    │ │
│  │  • Metrics     │      │  • Key generation              │ │
│  │  • Routing     │      │  • Transaction signing         │ │
│  │                │      │  • Policy evaluation           │ │
│  │                │      │  • Remote attestation          │ │
│  └────────────────┘      └────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Key Security Components

1. **Secure Enclaves (Trusted Execution Environments)**
   - Hardware-enforced isolation
   - No persistent storage, no interactive access, no external networking
   - Cryptographic attestation via AWS Nitro Security Module (NSM)

2. **QuorumOS**
   - Custom minimal, immutable, deterministic Linux unikernel
   - Every artifact builds deterministically for verification
   - Requires quorum of key shares to initialize enclave

3. **Remote Attestation**
   - Proves exactly what code is running in enclaves
   - Signed by AWS PKI
   - Verifiable by clients

4. **Stamping (Request Signing)**
   - Every API request cryptographically signed
   - Prevents tampering and man-in-the-middle attacks
   - Two methods: API key stamps and WebAuthn stamps

### Request Flow

1. Client constructs request body (JSON)
2. Client stamps request (signs with credential)
3. Request sent to Turnkey API with `X-Stamp` header
4. Host forwards to secure enclave
5. Enclave verifies stamp, evaluates policies
6. Action executed (or denied) within enclave
7. Response returned

---

## Developer Workflow

### Getting Started

1. **Create account** at [app.turnkey.com](https://app.turnkey.com)
2. **Get Organization ID** from dashboard
3. **Generate API key** (in-browser or via CLI)
4. **Install SDK** for your platform
5. **Integrate** using quickstart guides

### SDK Architecture

**Client-Side SDKs:**
- `@turnkey/react-wallet-kit` — React components with full auth flows
- `@turnkey/sdk-browser` — Core browser SDK
- `@turnkey/sdk-react` — React hooks and context
- Platform-native: React Native, Flutter, Swift, Kotlin

**Server-Side SDKs:**
- `@turnkey/sdk-server` — Node.js/TypeScript
- Go, Ruby, Rust, Python packages

**Web3 Integrations:**
- `@turnkey/ethers` — Ethers.js signer
- `@turnkey/viem` — Viem signer
- `@turnkey/solana` — Solana Web3.js integration
- `@turnkey/cosmjs` — CosmJS integration

### Stampers

Different stampers for different contexts:
- `@turnkey/api-key-stamper` — Server-side API key signing
- `@turnkey/webauthn-stamper` — Browser passkey signing
- `@turnkey/iframe-stamper` — Embedded iframe signing
- `@turnkey/wallet-stamper` — External wallet signing
- `@turnkey/indexed-db-stamper` — Persistent browser sessions

### Typical Integration Pattern

**Embedded Wallet (End-User Controlled):**
```
1. User authenticates (passkey/email/social)
2. Create sub-organization for user (one-time)
3. Create wallet within sub-org
4. User signs transactions with their credentials
```

**Transaction Automation (Backend Controlled):**
```
1. Create parent org API key
2. Use server SDK to create wallets
3. Define policies for signing permissions
4. Automate signing via API calls
```

---

## Multi-Chain Support

### Tiered Approach

| Tier | Support Level | Description |
|------|--------------|-------------|
| **Tier 1** | Curve-level | Any chain using secp256k1 or ed25519 |
| **Tier 2** | Address derivation | Automatic address generation for supported formats |
| **Tier 3** | SDK support | Transaction construction and signing helpers |
| **Tier 4** | Policy parsing | Transaction parsing and policy evaluation |

### Chain Support Matrix

| Chain | Address Derivation | SDK | Policy Parsing |
|-------|-------------------|-----|----------------|
| EVM (Ethereum, etc.) | ✓ | ✓ | ✓ |
| Solana | ✓ | ✓ | ✓ |
| Bitcoin | ✓ | - | ✓ |
| Tron | ✓ | - | ✓ |
| Cosmos | ✓ | - | - |
| Sui | ✓ | - | - |
| Aptos | ✓ | - | - |
| TON | ✓ | - | - |
| XRP | ✓ | - | - |

---

## Policy Engine

### Policy Structure

```json
{
  "effect": "EFFECT_ALLOW",
  "consensus": "approvers.any(user, user.id == '<USER_ID>')",
  "condition": "eth.tx.to == '<ALLOWED_ADDRESS>'"
}
```

- **effect**: `EFFECT_ALLOW` or `EFFECT_DENY`
- **consensus**: Who must approve (references `approvers`, `credentials`)
- **condition**: When the policy applies (references transaction data, wallets, etc.)

### Policy Language Features

- Logical operators: `&&`, `||`
- Comparisons: `==`, `!=`, `<`, `>`, `<=`, `>=`, `in`
- Array functions: `all()`, `any()`, `contains()`, `count()`, `filter()`
- Field access: dot notation for struct fields
- Chain-specific keywords: `eth.tx`, `solana.tx`, `bitcoin.tx`, `tron.tx`

### Evaluation Rules

1. Root quorum bypasses all policies
2. Explicit `DENY` wins over everything
3. At least one `ALLOW` required (else implicit deny)
4. Users can always manage their own credentials (unless denied)

---

## Notable Design Decisions & Patterns

### 1. **Sub-Organizations for User Isolation**
Each end-user gets their own sub-org, providing complete isolation. Parent can read but not write to sub-orgs.

### 2. **Cryptographic Stamps Instead of Tokens**
All requests are cryptographically signed rather than using bearer tokens. This provides:
- Non-repudiation
- Tamper-evidence
- No credential leakage risk

### 3. **Policy Engine in Enclave**
Policy evaluation happens inside secure enclaves, ensuring policies can't be bypassed even if external systems are compromised.

### 4. **Deterministic Builds for Verification**
All enclave code builds deterministically, allowing anyone to verify what's running.

### 5. **Curve-Level Rather Than Chain-Level**
Supporting cryptographic curves rather than specific chains provides maximum flexibility and future-proofing.

### 6. **Sessions with Non-Extractable Keys**
Client-side sessions use WebCrypto API to generate non-extractable keys stored in IndexedDB, preventing credential theft via JavaScript.

### 7. **Read-Only Parent Access to Sub-Orgs**
Enables parent orgs to serve data to clients without requiring separate sub-org authentication for reads.

---

## Resource Limits

| Resource | Parent Org Limit | Sub-Org Limit |
|----------|-----------------|---------------|
| Sub-Organizations | Unlimited | 0 |
| HD Wallets | 100 | 100 |
| HD Wallet Accounts | Unlimited | Unlimited |
| Private Keys | 1,000 | 1,000 |
| Users | 100 | 100 |
| Policies | 100 | 100 |
| API Keys per User | 10 (long-lived) + 10 (expiring) | Same |
| Authenticators per User | 10 | 10 |

### Rate Limits

| Tier | Limit |
|------|-------|
| Free | 1 RPS |
| Pay-as-you-go | 1 RPS |
| Pro | 3 RPS |
| Enterprise | 60 RPS |
| Per sub-org (all tiers) | 10 RPS |

---

## Documentation Structure

The docs are organized as:

```
/
├── home.mdx                    # Landing page
├── getting-started/            # Quickstarts and setup
├── concepts/                   # Core concepts (orgs, users, wallets, policies)
├── authentication/             # Auth methods (passkeys, email, OAuth, etc.)
├── embedded-wallets/           # Embedded wallet product docs
├── signing-automation/         # Transaction automation docs
├── sdks/                       # SDK documentation by platform
├── api-reference/              # API endpoint documentation
├── networks/                   # Chain-specific guides
├── security/                   # Security architecture docs
├── developer-reference/        # API overview, stamps, LLM integration
├── production-checklist/       # Pre-launch checklists
├── cookbook/                   # Integration recipes (Morpho, Aave, Jupiter, etc.)
└── changelogs/                 # SDK version history
```

---

## Open Questions & Areas for Further Investigation

### Technical Questions

1. **Enclave Disaster Recovery**: The docs mention disaster recovery but details are in a separate security page. How exactly do recovery flows work if enclaves fail?

2. **Multi-Region Deployment**: No clear documentation on geographic distribution of enclaves or latency considerations.

3. **Key Rotation**: Limited guidance on rotating organization-level secrets or API keys at scale.

4. **Webhook Security**: How are webhooks authenticated? Is there signature verification?

5. **Rate Limit Handling**: Best practices for handling rate limits in high-throughput scenarios.

### Product Questions

1. **Enterprise Features**: What specific features differentiate Enterprise tier beyond rate limits?

2. **SLA Guarantees**: No clear documentation on uptime SLAs or response time guarantees.

3. **Audit Logs**: How long are activity logs retained? Export capabilities?

4. **Compliance Certifications**: SOC 2, ISO 27001 status not prominently documented.

### Integration Questions

1. **Account Abstraction**: Deeper integration with ERC-4337, paymasters, and bundlers.

2. **MPC vs Enclave Tradeoffs**: Why enclaves over MPC? What are the trust assumptions?

3. **Key Derivation Customization**: Can custom derivation paths be used beyond standard BIPs?

4. **Cross-Chain Signing**: How to handle signing for chains with unique requirements?

---

## Key Takeaways

1. **Turnkey is infrastructure, not a product** — It provides building blocks for building wallet experiences, not a pre-built wallet.

2. **Security is the differentiator** — The enclave-based architecture with deterministic builds and remote attestation is unique in the market.

3. **Sub-orgs are the scaling primitive** — Most resource limits apply per-org, but sub-orgs are unlimited.

4. **Policy engine is powerful** — Chain-specific parsing enables sophisticated access control at the transaction level.

5. **Stamps prevent many attack vectors** — By signing entire request bodies, tampering and replay attacks are prevented.

6. **Gas sponsorship is built-in** — Unlike competitors requiring separate paymaster integrations.

7. **Multi-platform first** — Native SDKs for React Native, Flutter, iOS, Android alongside web.

---

*Report generated: 2026-02-25*
*Source: github.com/turnkeyintern/docs*
