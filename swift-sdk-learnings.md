# Turnkey Swift SDK Analysis

> Analysis Date: 2026-03-02
> SDK Version: 3.2.2
> Repository: `github.com/turnkeyintern/swift-sdk`

---

## SDK Overview

The Turnkey Swift SDK provides native iOS and macOS integration for Turnkey's key management and wallet infrastructure. It's designed as an **all-in-one solution** for building fully functional wallet apps with native Apple platform features.

### Target Platforms

| Platform | Minimum Version |
|----------|-----------------|
| iOS | 17.0 |
| macOS | 14.0 |
| tvOS | 16.0 |
| watchOS | 9.0 |
| visionOS | 1.0 |

### Key Capabilities

- **Passkey authentication** via ASAuthorization (Face ID, Touch ID, hardware keys)
- **Secure Enclave** integration for on-device private key generation and signing
- **OAuth** flows (Google, Apple, Discord, X/Twitter)
- **OTP authentication** (email and SMS)
- **Wallet operations** (create, import, export, sign)
- **Session management** with auto-refresh
- **Activity polling** for async operations

---

## Package Structure

The SDK uses **Swift Package Manager (SPM)** exclusively — no CocoaPods support. The architecture is modular, allowing developers to import only what they need.

### Module Dependency Graph

```
TurnkeySwift (all-in-one)
├── TurnkeyHttp (HTTP client)
│   ├── TurnkeyTypes (generated types)
│   └── TurnkeyStamper (request signing)
├── TurnkeyStamper
│   ├── TurnkeyPasskeys (ASAuthorization)
│   ├── TurnkeyCrypto (P-256, HPKE)
│   └── TurnkeyKeyManager (Secure Enclave/Storage)
├── TurnkeyPasskeys
│   ├── TurnkeyEncoding
│   ├── TurnkeyCrypto
│   └── TurnkeyTypes
└── TurnkeyKeyManager
    └── TurnkeyCrypto
```

### Module Descriptions

| Module | Purpose |
|--------|---------|
| **TurnkeySwift** | All-in-one package. `TurnkeyContext` singleton manages auth state, sessions, wallets |
| **TurnkeyStamper** | Signs API requests. Supports API keys, passkeys, Secure Enclave, and Secure Storage |
| **TurnkeyPasskeys** | Wrapper around `AuthenticationServices` for passkey registration/assertion |
| **TurnkeyCrypto** | P-256 key generation, HPKE encryption/decryption for bundle handling |
| **TurnkeyHttp** | Low-level HTTP client with activity polling |
| **TurnkeyKeyManager** | Manages Secure Enclave and Keychain-based key storage |
| **TurnkeyEncoding** | Hex/Base58/Base64URL encoding utilities |
| **TurnkeyTypes** | Auto-generated Codable types from Swagger spec |

### External Dependencies

- `swift-http-types` (Apple) — HTTP type definitions
- `Base58Check` — Bitcoin-style Base58 encoding

---

## Core Types & Protocols

### TurnkeyContext (Main Entry Point)

The `TurnkeyContext` is an `ObservableObject` singleton that serves as the primary interface:

```swift
public final class TurnkeyContext: NSObject, ObservableObject {
    @Published public internal(set) var authState: AuthState
    @Published public internal(set) var client: TurnkeyClient?
    @Published public internal(set) var session: Session?
    @Published public internal(set) var user: v1User?
    @Published public internal(set) var wallets: [Wallet]
    
    public static let shared = TurnkeyContext(config: _config)
    
    public static func configure(_ config: TurnkeyConfig)
}
```

**Design Pattern**: Classic SwiftUI-friendly singleton with `@Published` properties for reactive UI updates.

### AuthState Enum

```swift
public enum AuthState {
    case loading
    case authenticated
    case unAuthenticated
}
```

### Session Model

```swift
public struct Session: Codable, Equatable, Identifiable {
    public let exp: TimeInterval
    public let publicKey: String
    public let sessionType: SessionType  // readWrite or readOnly
    public let userId: String
    public let organizationId: String
    public let token: String?  // Raw JWT for backend auth
}
```

### TurnkeyClient (HTTP Layer)

Multiple initialization patterns:

```swift
// API key pair
TurnkeyClient(apiPrivateKey: String, apiPublicKey: String)

// On-device key (Secure Enclave or Keychain)
TurnkeyClient(apiPublicKey: String) throws

// Passkey-based
TurnkeyClient(rpId: String, presentationAnchor: ASPresentationAnchor)

// Auth Proxy only
TurnkeyClient(authProxyConfigId: String)
```

### Stamper (Request Signing)

The `Stamper` class handles request signing with multiple backends:

```swift
public enum OnDeviceStamperPreference {
    case auto           // Prefers Secure Enclave, falls back to Keychain
    case secureEnclave  // Forces Secure Enclave (throws if unavailable)
    case secureStorage  // Forces Keychain storage
}

public class Stamper {
    // API key mode
    init(apiPublicKey: String, apiPrivateKey: String)
    
    // Passkey mode
    init(rpId: String, presentationAnchor: ASPresentationAnchor)
    
    // On-device key mode
    init(apiPublicKey: String, onDevicePreference: OnDeviceStamperPreference) throws
    
    // Creates a new key pair and initializes stamper
    init(onDevicePreference: OnDeviceStamperPreference) throws
    
    func stamp(payload: String) async throws -> (stampHeaderName: String, stampHeaderValue: String)
    func sign(payload: String, format: SignatureFormat) async throws -> String
}
```

---

## Authentication & Signing

### Stamp Headers

The SDK uses two stamp header types:

| Header | Use Case |
|--------|----------|
| `X-Stamp` | API key, Secure Enclave, Secure Storage (ECDSA P-256) |
| `X-Stamp-WebAuthn` | Passkey/WebAuthn assertions |

### Stamp Format (X-Stamp)

```json
{
  "publicKey": "<compressed-p256-hex>",
  "scheme": "SIGNATURE_SCHEME_TK_API_P256",
  "signature": "<der-encoded-signature-hex>"
}
```

This JSON is base64url-encoded for the header value.

### Secure Enclave Integration

The `EnclaveManager` wraps Apple's Security framework for Secure Enclave operations:

```swift
public final class EnclaveManager {
    public static func isSecureEnclaveAvailable() -> Bool
    
    public static func createKeyPair(
        authPolicy: AuthPolicy = .none,  // .none, .userPresence, .biometryAny, .biometryCurrentSet
        label: String = "TurnkeyEnclaveManager"
    ) throws -> KeyPair
    
    public func sign(
        message: Data,
        algorithm: SecKeyAlgorithm = .ecdsaSignatureDigestX962SHA256
    ) throws -> Data
}
```

**Key Insight**: Secure Enclave keys **cannot be exported** — the private key never leaves the TEE. This is ideal for on-device authentication but means the key is device-bound.

### Secure Storage (Keychain)

For devices without Secure Enclave (e.g., simulators, some Macs), `SecureStorageManager` stores keys as Keychain Generic Password entries:

```swift
public final class SecureStorageManager {
    public static func createKeyPair(config: Config) throws -> String
    public static func getPrivateKey(publicKeyHex: String) throws -> String?
    public static func deleteKeyPair(publicKeyHex: String) throws
}

public struct Config {
    var accessibility: Accessibility  // .whenUnlockedThisDeviceOnly, etc.
    var accessControlPolicy: AccessControlPolicy  // .none, .userPresence, .biometryAny
    var authPrompt: String?
    var biometryReuseWindowSeconds: Int
    var synchronizable: Bool
    var accessGroup: String?
}
```

### Passkey Flow

Passkeys leverage `ASAuthorizationPlatformPublicKeyCredentialProvider`:

```swift
// Registration
public func createPasskey(
    user: PasskeyUser,
    rp: RelyingParty,
    presentationAnchor: ASPresentationAnchor,
    authenticatorType: AuthenticatorType = .platformKey
) async throws -> PasskeyRegistrationResult

// Assertion (via PasskeyStamper)
public func assert(
    challenge: Data,
    allowedCredentials: [Data]? = nil,
    authenticatorType: AuthenticatorType = .platformKey
) async throws -> AssertionResult
```

---

## Activity Polling

Activities in Turnkey are asynchronous operations. The SDK implements automatic polling:

```swift
public struct ActivityPollerConfig {
    public let intervalMs: Int      // Default: 1000ms
    public let numRetries: Int      // Default: 3
}

private let TERMINAL_ACTIVITY_STATUSES: Set<String> = [
    "ACTIVITY_STATUS_COMPLETED",
    "ACTIVITY_STATUS_FAILED",
    "ACTIVITY_STATUS_CONSENSUS_NEEDED",
    "ACTIVITY_STATUS_REJECTED",
]
```

The `activity()` method internally:
1. Makes the initial request
2. If status is non-terminal, polls `/public/v1/query/get_activity` 
3. Uses `Task.sleep` for the polling interval
4. Returns when terminal status reached or max retries exceeded

**Pattern**: This is a clean async/await implementation — no completion handlers or Combine.

---

## iOS/macOS Integration

### Platform-Specific Features

| Feature | Framework | Notes |
|---------|-----------|-------|
| Passkeys | `AuthenticationServices` | Requires iOS 16+, macOS 13+ |
| Secure Enclave | `Security` | P-256 keys only, requires device support |
| Keychain | `Security` | Fallback for non-enclave devices |
| Biometrics | `LocalAuthentication` | Face ID, Touch ID via LAContext |
| OAuth UI | `ASWebAuthenticationSession` | System browser for OAuth flows |

### Associated Domains

Passkeys require Apple's associated domains capability:

```
webcredentials:your-domain.com
```

### OAuth Flow Implementation

The SDK uses `ASWebAuthenticationSession` for OAuth:

```swift
func runOAuthSession(
    provider: String,
    clientId: String,
    scheme: String,      // Your app's URL scheme
    anchor: ASPresentationAnchor,
    nonce: String,
    additionalState: [String: String]?
) async throws -> String  // Returns OIDC token
```

For PKCE flows (Discord, X), the SDK handles code_verifier/challenge generation:

```swift
func generatePKCEPair() throws -> (verifier: String, challenge: String)
```

---

## Integration Patterns

### Configuration

```swift
// App startup (typically in App.init or SceneDelegate)
TurnkeyContext.configure(TurnkeyConfig(
    apiUrl: "https://api.turnkey.com",
    authProxyUrl: "https://authproxy.turnkey.com",
    authProxyConfigId: "your-config-id",
    rpId: "your-domain.com",
    organizationId: "your-org-id",
    auth: .init(
        oauth: .init(
            appScheme: "yourapp",
            providers: .init(
                google: .init(clientId: "..."),
                apple: .init(clientId: "...")
            )
        ),
        autoRefreshSession: true
    )
))
```

### Passkey Sign-Up

```swift
// One-tap passkey signup with ephemeral API key
try await TurnkeyContext.shared.signUpWithPasskey(
    anchor: presentationAnchor,
    passkeyDisplayName: "My Passkey",
    createSubOrgParams: CreateSubOrgParams(
        organizationName: "User's Org",
        wallet: .init(walletName: "Default Wallet", accounts: [...])
    )
)
```

**Pattern**: The SDK creates a temporary P-256 API key during signup to avoid requiring a second passkey assertion for session creation.

### OTP Flow

```swift
// 1. Init OTP
let result = try await TurnkeyContext.shared.initOtp(
    contact: "user@example.com",
    otpType: .email
)

// 2. Verify OTP code
let verify = try await TurnkeyContext.shared.verifyOtp(
    otpId: result.otpId,
    otpCode: "123456"
)

// 3. Complete (auto-detects login vs signup)
try await TurnkeyContext.shared.completeOtp(
    otpId: result.otpId,
    otpCode: "123456",
    contact: "user@example.com",
    otpType: .email
)
```

### Wallet Operations

```swift
// Create wallet
try await TurnkeyContext.shared.createWallet(
    walletName: "My Wallet",
    accounts: [
        WalletAccountParams(addressFormat: .address_format_ethereum, curve: .curve_secp256k1, pathFormat: .path_format_bip32),
        WalletAccountParams(addressFormat: .address_format_solana, curve: .curve_ed25519, pathFormat: .path_format_bip32)
    ]
)

// Sign message
let result = try await TurnkeyContext.shared.signMessage(
    signWith: account,
    message: "Hello, World!",
    addEthereumPrefix: true
)
// Returns SignRawPayloadResult with r, s, v components
```

---

## Notable Swift Patterns

### 1. Sendable Compliance

All configuration types are marked `Sendable` for Swift concurrency safety:

```swift
public struct TurnkeyConfig: Sendable { ... }
public struct TurnkeySession: Codable, Equatable { ... }
extension Stamper: @unchecked Sendable {}  // Manually marked
```

### 2. ObservableObject for SwiftUI

`TurnkeyContext` is an `@ObservableObject` with `@Published` properties, enabling direct SwiftUI bindings:

```swift
@EnvironmentObject var context: TurnkeyContext

if context.authState == .authenticated {
    DashboardView()
} else {
    LoginView()
}
```

### 3. async/await Throughout

**No Combine publishers or completion handlers** — the entire API uses Swift's structured concurrency:

```swift
public func loginWithPasskey(anchor: ASPresentationAnchor) async throws -> PasskeyAuthResult
public func signRawPayload(signWith: String, payload: String, ...) async throws -> SignRawPayloadResult
```

### 4. Extension-Based Organization

`TurnkeyContext` functionality is split across extensions by feature:
- `TurnkeyContext+Session.swift`
- `TurnkeyContext+Wallet.swift`
- `TurnkeyContext+Signing.swift`
- `TurnkeyContext+OAuth.swift`
- `TurnkeyContext+Otp.swift`
- `TurnkeyContext+Passkey.swift`

### 5. Code Generation

Types and client methods are **auto-generated** from Swagger specs:

```bash
make generate
```

Generates:
- `Sources/TurnkeyTypes/Generated/Types.swift` (~16k+ lines)
- `Sources/TurnkeyHttp/Public/TurnkeyClient+Public.swift`
- `Sources/TurnkeyHttp/Public/TurnkeyClient+AuthProxy.swift`

### 6. Error Handling

Rich error types with underlying error extraction:

```swift
public enum TurnkeySwiftError: LocalizedError, Sendable {
    case failedToLoginWithPasskey(underlying: Error)
    case failedToSignPayload(underlying: Error)
    // ...
    
    public var underlyingTurnkeyError: TurnkeyRequestError? { ... }
}

extension Error {
    public var turnkeyRequestError: TurnkeyRequestError? { ... }
}
```

---

## Comparison with Other SDKs

| Feature | Swift SDK | React SDK | Node SDK |
|---------|-----------|-----------|----------|
| Secure Enclave | ✅ Native | ❌ N/A | ❌ N/A |
| Passkeys | ✅ ASAuthorization | ✅ WebAuthn | ❌ Server-only |
| Activity Polling | ✅ async/await | ✅ Promises | ✅ Promises |
| Code Generation | ✅ Swift executables | ✅ TypeScript | ✅ TypeScript |
| Session Management | ✅ TurnkeyContext | ✅ TurnkeyContext | ❌ Manual |
| Auth Proxy | ✅ Built-in | ✅ Built-in | ❌ N/A |
| OAuth | ✅ 4 providers | ✅ 4 providers | ❌ N/A |

**Unique Swift Features**:
- Device-bound keys via Secure Enclave (P-256 keys that never leave the TEE)
- Native biometric prompts via LocalAuthentication
- System OAuth browser via ASWebAuthenticationSession

---

## Example App Architecture

The repo includes two demo apps demonstrating both backend patterns:

### `Examples/with-backend/`

Uses a custom backend for authentication:
- Backend handles sub-org creation
- Backend exchanges OAuth tokens for sessions
- Backend verifies OTP codes

### `Examples/without-backend/`

Uses Turnkey's managed Auth Proxy:
- Direct API calls to Auth Proxy endpoints
- No backend infrastructure required
- Origin validation handled by Turnkey

Both apps showcase:
- SwiftUI + MVVM pattern
- `AuthContext` as authentication coordinator
- `NavigationCoordinator` for routing
- `ToastContext` for error display

---

## Open Questions

1. **Credential ID Return**: The passkey login flow currently returns an empty credential ID — could this be extracted from the assertion response?

2. **Session Auto-Refresh Timing**: The TTL calculation during `storeSession` loses a few seconds due to timing. Is this intentional, or should it preserve the exact server TTL?

3. **Key Rotation**: How should apps handle Secure Enclave key rotation? The SDK provides `deleteKeyPair` but no migration helper.

4. **visionOS Testing**: The SDK declares visionOS 1.0 support — has Secure Enclave been tested on Apple Vision Pro?

5. **Error Recovery**: When `authState` becomes `.unAuthenticated` due to session expiry, what's the recommended UX pattern? The SDK clears state but doesn't trigger a callback.

6. **Multi-Account Support**: The `SessionRegistryStore` and `selectedSessionKey` suggest multi-session support — is this intended for multi-account wallets?

7. **Keychain Sync**: `SecureStorageManager` supports `synchronizable` — are there security implications for iCloud Keychain sync of wallet keys?

---

## Summary

The Swift SDK is a mature, production-ready implementation that leverages Apple platform features deeply. Key strengths:

- **Platform-native**: Secure Enclave, ASAuthorization, LocalAuthentication
- **Modern Swift**: async/await, Sendable, SwiftUI-ready
- **Flexible auth**: Passkeys, OAuth (4 providers), OTP, API keys
- **Developer experience**: Auto-generated types, comprehensive error handling

The architecture closely mirrors the React SDK's `TurnkeyContext` pattern while taking full advantage of iOS-specific capabilities like Secure Enclave key storage.
