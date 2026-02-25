# Turnkey Frames - Technical Analysis Report

> **Repository:** `tkhq/frames`  
> **Analysis Date:** 2026-02-25  
> **Primary Purpose:** Secure iframe-based authentication and cryptographic key management components

---

## 📋 Executive Summary

The Turnkey `frames` repository contains **self-contained HTML pages** designed to be embedded as iframes or used standalone for secure cryptographic operations. These are **browser iframes** (not Farcaster frames), specifically architected for:

1. **Email-based authentication and recovery** (auth/recovery)
2. **Private key/wallet export** (export, export-and-sign)
3. **Private key/wallet import** (import)
4. **OAuth authentication flows** (oauth-origin, oauth-redirect)

The key innovation is **client-side cryptographic isolation**: sensitive operations (key generation, signing, encryption/decryption) happen within isolated iframe contexts, preventing the parent application from ever accessing raw private key material.

---

## 🎯 What Problem Does This Solve?

### The Core Challenge
When building wallet infrastructure, a fundamental tension exists:
- **Applications need signing capabilities** to execute transactions
- **Raw private keys must never be exposed** to application code (XSS, supply chain attacks)
- **Users need recovery mechanisms** that don't compromise security

### Turnkey's Solution: Iframe Isolation

Frames solve this by creating **cryptographic trust boundaries**:

```
┌─────────────────────────────────────────────────────────────┐
│  Parent Application (your app)                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Cannot access iframe internals (same-origin policy)  │  │
│  │  Can only communicate via postMessage API             │  │
│  └───────────────────────────────────────────────────────┘  │
│                           │                                  │
│                    postMessage                               │
│                           ↓                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Turnkey Frame (auth.turnkey.com, etc.)               │  │
│  │  • Generates/stores P-256 keypairs                    │  │
│  │  • Performs HPKE encryption/decryption                │  │
│  │  • Signs payloads with API credentials                │  │
│  │  • Keys NEVER leave this context                      │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🏗️ Architecture Overview

### Repository Structure

```
frames/
├── auth/                    # Email auth & recovery iframe
├── export/                  # Key/wallet export (static HTML)
├── export-and-sign/         # Export + signing (webpack-built)
├── import/                  # Key/wallet import (webpack-built)
├── oauth-origin/            # OAuth flow initiator
├── oauth-redirect/          # OAuth callback handler
├── shared/                  # Common crypto utilities
├── Dockerfile               # Multi-stage build
├── nginx.conf               # Serving configuration
└── kustomize/               # Kubernetes deployment
```

### Hosted Endpoints

| Frame | URL | Port (Docker) |
|-------|-----|---------------|
| Auth | https://auth.turnkey.com/ | 8080 |
| Recovery | https://recovery.turnkey.com/ (legacy) | 8082 |
| Export | https://export.turnkey.com/ | 8081 |
| Import | https://import.turnkey.com/ | 8083 |
| Export-and-Sign | (port 8086) | 8086 |
| OAuth Origin | https://oauth-origin.turnkey.com/ | 8084 |
| OAuth Redirect | https://oauth-redirect.turnkey.com/ | 8085 |

### Build Types

| Component | Build Method | Notes |
|-----------|--------------|-------|
| auth, export | Static | Copied as-is, self-contained HTML |
| export-and-sign | Webpack | Bundles Solana SDK, noble-ed25519 |
| import | Webpack | Standalone & index entry points |
| shared | npm ci only | Consumed as dependency |
| oauth-* | Static | Simple redirect handlers |

---

## 🔐 Core Cryptographic Patterns

### 1. Embedded Key Management

Every frame generates and manages a **P-256 ECDH keypair** stored in `localStorage`:

```javascript
// Key generation (from shared/turnkey-core.js)
async function generateTargetKey() {
  const p256key = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveBits"]
  );
  return await crypto.subtle.exportKey("jwk", p256key.privateKey);
}
```

**Key properties:**
- **48-hour TTL** by default (configurable)
- Stored as JWK with expiration timestamp
- Automatically regenerated if expired
- Public key sent to parent frame on initialization

### 2. HPKE (RFC 9180) Encryption

The frames use **Hybrid Public Key Encryption** for secure bundle exchange:

```javascript
// Cipher suite configuration
const suite = new CipherSuite({
  kem: new DhkemP256HkdfSha256(),  // P-256 key encapsulation
  kdf: new HkdfSha256(),            // SHA-256 key derivation
  aead: new Aes256Gcm(),            // AES-256-GCM authenticated encryption
});

// Additional Associated Data (AAD) format
function additionalAssociatedData(senderPubBuf, receiverPubBuf) {
  return new Uint8Array([...senderPubBuf, ...receiverPubBuf]);
}
```

**Info string:** `"turnkey_hpke"` (used for domain separation)

### 3. Enclave Signature Verification

Import bundles are signed by Turnkey's enclave quorum key:

```javascript
// Production quorum public key (P-256, uncompressed)
const TURNKEY_SIGNER_ENCLAVE_QUORUM_PUBLIC_KEY = 
  "04cf288fe433cc4e1aa0ce1632feac4ea26bf2f5a09dcfe5a42c398e06898710330f0572882f4dbdf0f5304b8fc8703acd69adca9a4bbf7f5d00d20a5e364b2569";
```

Bundles include:
- `version`: Currently `"v1.0.0"`
- `data`: Hex-encoded JSON payload
- `dataSignature`: ECDSA signature (DER-encoded)
- `enclaveQuorumPublic`: Signer's public key

### 4. Security Checks

```javascript
// Anti-framing protection
function isDoublyIframed() {
  return window.location.ancestorOrigins?.length > 1 
      || window.parent !== window.top;
}

// Enforced in initEmbeddedKey()
if (isDoublyIframed()) {
  throw new Error("Doubly iframed");
}
```

---

## 📦 Key Components Deep Dive

### Auth Frame (`/auth`)

**Purpose:** Email-based authentication and wallet recovery

**Message Types:**
| Inbound | Outbound |
|---------|----------|
| `INJECT_CREDENTIAL_BUNDLE` | `PUBLIC_KEY_READY` |
| `STAMP_REQUEST` | `BUNDLE_INJECTED` |
| `RESET_EMBEDDED_KEY` | `STAMP` |
| `GET_EMBEDDED_PUBLIC_KEY` | `ERROR` |
| `INIT_EMBEDDED_KEY` | `EMBEDDED_KEY_RESET` |

**Credential Flow:**
1. Frame generates P-256 keypair, sends public key up
2. Server encrypts credential to frame's public key
3. User receives bundle via email (base58check or base64url encoded)
4. Frame decrypts credential, stores in memory (NOT localStorage)
5. Frame can now sign API requests ("stamping")

**Stamp Format:**
```javascript
{
  publicKey: "02...",                    // Compressed P-256 public key
  scheme: "SIGNATURE_SCHEME_TK_API_P256",
  signature: "3045..."                   // DER-encoded ECDSA signature
}
```

### Import Frame (`/import`)

**Purpose:** Securely import private keys or seed phrases into Turnkey

**Flow:**
1. Receive import bundle from server (contains target encryption key)
2. Verify enclave signature on bundle
3. Store server's target public key
4. User enters mnemonic/private key in textarea
5. Encrypt to server's target key using HPKE
6. Send encrypted bundle up to parent

**Key Formats Supported:**
- `HEXADECIMAL` (default)
- `SOLANA` (base58, 64-byte keypair)
- `BITCOIN_MAINNET_WIF` / `BITCOIN_TESTNET_WIF`
- `SUI_BECH32` (bech32 with `suiprivkey` prefix)

**Mnemonic + Passphrase:**
```javascript
const combined = passphrase === "" 
  ? plaintext 
  : `${plaintext}\n--PASS--\n${passphrase}`;
```

### Export-and-Sign Frame (`/export-and-sign`)

**Purpose:** Export private keys AND perform in-iframe signing (Solana focused)

**Key Innovation:** Private keys loaded into memory can sign transactions without leaving the iframe.

**Message Types:**
| Inbound | Purpose |
|---------|---------|
| `INJECT_KEY_EXPORT_BUNDLE` | Load encrypted key into memory |
| `INJECT_WALLET_EXPORT_BUNDLE` | Load wallet key |
| `SIGN_TRANSACTION` | Sign Solana transaction |
| `SIGN_MESSAGE` | Sign arbitrary message |
| `CLEAR_EMBEDDED_PRIVATE_KEY` | Clear from memory |
| `SET_EMBEDDED_KEY_OVERRIDE` | Override decryption key |

**In-Memory Key Store:**
```javascript
inMemoryKeys = {
  [address]: {
    organizationId,
    privateKey,           // Encoded key string
    format,               // "SOLANA" | "HEXADECIMAL"
    expiry,               // Timestamp (24h TTL)
    keypair,              // Cached Solana Keypair object
  }
}
```

**Transaction Signing:**
```javascript
const transaction = VersionedTransaction.deserialize(transactionBytes);
transaction.sign([keypair]);
const signedTransaction = transaction.serialize();
```

### OAuth Frames

**oauth-origin:** Constructs OAuth authorization URLs and redirects:
- Google: `accounts.google.com/o/oauth2/v2/auth`
- Apple: `appleid.apple.com/auth/authorize`
- Facebook: `facebook.com/v23.0/dialog/oauth` (with PKCE)

**oauth-redirect:** Handles callbacks, extracts tokens from hash/query, redirects to app deep link:
```javascript
// Redirects to: myapp://?id_token=...&code=...
window.location.href = `${scheme}?${paramsToForward.toString()}`;
```

---

## 🔌 Integration with Turnkey Ecosystem

### SDK Integration (`@turnkey/iframe-stamper`)

The frames are designed to work with Turnkey's `@turnkey/iframe-stamper` package:

```javascript
// Parent application code (simplified)
import { IframeStamper } from "@turnkey/iframe-stamper";

const stamper = new IframeStamper({
  iframeUrl: "https://auth.turnkey.com/",
  iframeContainer: document.getElementById("turnkey-iframe"),
});

await stamper.init();
const publicKey = stamper.iframePublicKey;

// Later, inject credential bundle from email
await stamper.injectCredentialBundle(bundleFromEmail);

// Sign a Turnkey API request
const stamp = await stamper.stamp(JSON.stringify(activityPayload));
```

### Communication Protocol

**MessageChannel (v2.1.0+):**
```javascript
// Parent sends
postMessage({ type: "TURNKEY_INIT_MESSAGE_CHANNEL" }, "*", [port]);

// Iframe receives port, uses for bidirectional communication
iframeMessagePort.onmessage = messageEventListener;
```

**Legacy postMessage (pre-v2.1.0):**
```javascript
window.parent.postMessage({ type, value }, "*");
```

### Bundle Format Evolution

**v1.0.0 Bundle (current):**
```json
{
  "version": "v1.0.0",
  "data": "7b226f7267616e697a6174696f6e4964223a22...}",
  "dataSignature": "3045022100...",
  "enclaveQuorumPublic": "04cf288fe433..."
}
```

**Signed data contains:**
```json
{
  "organizationId": "org-xxx",
  "userId": "user-xxx",
  "targetPublic": "04...",  // or encappedPublic + ciphertext for exports
}
```

---

## 🧩 Notable Design Decisions

### 1. No External Dependencies in Auth/Export

The `auth` and `export` frames are **completely self-contained HTML files** with all JavaScript inline. This:
- Eliminates supply chain attack vectors
- Makes security auditing simpler
- Allows the page to work offline after initial load

### 2. HPKE for Forward Secrecy

Using HPKE instead of simpler encryption schemes provides:
- **Forward secrecy**: Each encryption uses ephemeral keys
- **Authenticated encryption**: AEAD prevents tampering
- **Standards compliance**: RFC 9180 is well-audited

### 3. Base58Check for Bundle Encoding

Email bundles use Bitcoin's base58check encoding:
- No ambiguous characters (0/O, l/1)
- Built-in checksum validation
- Human-readable format

### 4. In-Memory vs localStorage

| Data | Storage | Rationale |
|------|---------|-----------|
| Embedded P-256 key | localStorage (48h TTL) | Survives page refresh |
| Decrypted credentials | In-memory only | Never persisted |
| Target encryption keys | localStorage (import) | Needed across requests |
| Signing keys | In-memory (24h TTL) | Security-sensitive |

### 5. CSS Sanitization

Custom styles are validated against a strict allowlist:

```javascript
const cssValidationRegex = {
  padding: "^(\\d+(px|em|%|rem) ?){1,4}$",
  fontSize: "^(\\d+(px|em|rem|%|vh|vw|...))$",
  // ... etc
};
```

This prevents CSS injection attacks while allowing theming.

---

## 👨‍💻 Developer Usage

### Embedding the Auth Frame

```html
<iframe
  id="turnkey-auth-iframe"
  src="https://auth.turnkey.com/"
  allow="clipboard-write"
  sandbox="allow-scripts allow-same-origin"
></iframe>
```

### Local Development

```bash
# Auth frame
cd auth && npm install && npm start  # Port 3000

# Import frame (webpack)
cd import && npm ci && npm run dev   # Port 8080 (hot reload)

# Export-and-sign frame
cd export-and-sign && npm ci && npm run dev  # Port 8080

# Set environment variable in SDK example
NEXT_PUBLIC_AUTH_IFRAME_URL="http://localhost:3000/"
```

### Docker Deployment

```bash
# Build image
docker build . -t frames

# Run with port mapping
docker run -p18080:8080 -p18081:8081 -p18082:8082 \
           -p18083:8083 -p18084:8084 -p18085:8085 \
           -p18086:8086 -t frames
```

### Kubernetes (k3d)

```bash
k3d cluster create frames
kubectl kustomize kustomize | kubectl --context k3d-frames apply -f-
kubectl port-forward svc/frames 8080:8080
```

---

## ❓ Open Questions & Areas for Investigation

### Security
1. **Double-iframe protection bypass?** The `isDoublyIframed()` check uses `ancestorOrigins` - worth verifying all browsers handle this correctly.

2. **localStorage isolation**: Are there scenarios where malicious extensions could access the embedded key?

3. **MessageChannel vs postMessage**: What's the security improvement in v2.1.0's MessageChannel approach?

### Architecture
4. **Why separate export vs export-and-sign?** The export frame is static HTML, export-and-sign has signing. Is export deprecated?

5. **Preprod enclave key**: There's a separate key for `preprod` environment - how is environment selection handled?

### Future
6. **Multi-chain signing**: Currently focused on Solana - what's the plan for EVM chains in export-and-sign?

7. **WebAuthn integration**: How do frames interact with passkey-based authentication?

8. **Session management**: The 48h/24h TTLs seem arbitrary - is there research behind these values?

---

## 📚 Key File Reference

| File | Purpose |
|------|---------|
| `shared/turnkey-core.js` | Core crypto utilities, key management |
| `shared/crypto-utils.js` | HPKE encrypt/decrypt functions |
| `auth/index.html` | Complete auth/recovery implementation |
| `import/src/index.js` | Import frame entry point |
| `export-and-sign/src/event-handlers.js` | Signing logic, key store |
| `oauth-origin/oauth-origin.js` | OAuth URL construction |
| `nginx.conf` | Routing configuration |

---

## 🔗 Related Resources

- **Turnkey SDK:** https://github.com/tkhq/sdk
- **HPKE RFC:** https://datatracker.ietf.org/doc/rfc9180/
- **iframe-stamper package:** `@turnkey/iframe-stamper`
- **Security disclosures:** https://docs.turnkey.com/security/reporting-a-vulnerability

---

*Report generated by technical analysis of the `tkhq/frames` repository.*
