# Turnkey Rust SDK - Technical Learnings

> Comprehensive analysis of the [turnkey-rust-sdk](https://github.com/tkhq/rust-sdk) repository

---

## SDK Overview

The Turnkey Rust SDK provides a suite of tools for interacting with the [Turnkey API](https://docs.turnkey.com/), a key management and signing infrastructure that uses AWS Nitro Enclaves for secure cryptographic operations.

### Key Capabilities

1. **API Authentication** - P-256 and secp256k1 API key stamping for request signing
2. **API Client** - Async HTTP client for all Turnkey endpoints with automatic polling and retries
3. **Enclave Encryption** - HPKE-based encryption/decryption for secure communication with Turnkey enclaves
4. **Proof Verification** - Verification of AWS Nitro attestation documents and app proofs
5. **Turnkey Verified Cloud CLI** - Experimental CLI for verifiable cloud deployments

---

## Crate Structure

The SDK is organized as a Cargo workspace with the following members:

```
turnkey-rust-sdk/
├── api_key_stamper/     # turnkey_api_key_stamper - API key management & request signing
├── client/              # turnkey_client - HTTP client with auto-generated endpoint methods
├── codegen/             # Code generation from protobuf definitions
├── enclave_encrypt/     # turnkey_enclave_encrypt - HPKE encryption for enclave comms
├── examples/            # Working examples (whoami, wallet, proofs, sub_organization)
├── proofs/              # turnkey_proofs - AWS Nitro attestation verification
├── proto/               # Protobuf definitions for the API
└── tvc/                 # Turnkey Verified Cloud CLI tool
```

### Crate Dependencies Flow

```
turnkey_api_key_stamper (core signing primitives)
         ↓
turnkey_client (uses stamper for auth)
         ↓
turnkey_proofs (uses client for boot proof fetching)
         
turnkey_enclave_encrypt (independent, uses quorum public keys)
```

### Version Info (as of analysis)
- Current version: `0.6.0` for all published crates
- Uses `release-plz` for automated releases

---

## Core Types & Traits

### `turnkey_api_key_stamper`

#### `Stamp` Trait
The central abstraction for request authentication:

```rust
pub trait Stamp {
    fn stamp(&self, body: &[u8]) -> Result<StampHeader, StamperError>;
}
```

Returns a `StampHeader` containing:
- `name`: The HTTP header name (`"X-Stamp"`)
- `value`: Base64 URL-safe encoded JSON stamp

#### `TurnkeyP256ApiKey`
Primary API key type using the P-256 (secp256r1) curve:

```rust
pub struct TurnkeyP256ApiKey {
    signing_key: P256SigningKey,
}
```

Key methods:
- `generate()` - Create new random key
- `from_bytes(private, Optional<public>)` - Load from raw bytes
- `from_strings(private_hex, Optional<public_hex>)` - Load from hex strings
- `from_files(priv_path, pub_path)` - Load from tkcli-generated files
- `compressed_public_key()` - Get SEC1 compressed public key
- `private_key()` - Get raw private key bytes

#### `TurnkeySecp256k1ApiKey`
Alternative API key type using secp256k1:

```rust
pub struct TurnkeySecp256k1ApiKey {
    signing_key: K256SigningKey,
}
```

Same interface as P256, with `SIGNATURE_SCHEME_TK_API_SECP256K1`.

#### Stamp Format
The stamp is a JSON object encoded as Base64 URL-safe:

```rust
struct TurnkeyApiStamp {
    public_key: String,   // hex-encoded compressed public key
    signature: String,    // hex-encoded DER signature
    scheme: String,       // "SIGNATURE_SCHEME_TK_API_P256" or "SIGNATURE_SCHEME_TK_API_SECP256K1"
}
```

### `turnkey_client`

#### `TurnkeyClient<S: Stamp>`
Generic HTTP client parameterized over any `Stamp` implementor:

```rust
pub struct TurnkeyClient<S: Stamp> {
    http: reqwest::Client,
    base_url: String,
    api_key: S,
    retry_config: RetryConfig,
    generate_app_proofs: Option<bool>,
}
```

Builder pattern construction:
```rust
let client = TurnkeyClient::builder()
    .api_key(TurnkeyP256ApiKey::generate())
    .base_url("https://api.turnkey.com")
    .timeout(Duration::from_secs(30))
    .retry_config(RetryConfig::default())
    .build()?
    .with_app_proofs(); // Enable proof generation
```

#### `ActivityResult<T>`
Wrapper for activity responses with metadata:

```rust
pub struct ActivityResult<T> {
    pub result: T,           // Typed result (e.g., CreateWalletResult)
    pub activity_id: String,
    pub status: ActivityStatus,
    pub app_proofs: Vec<AppProof>,
}
```

#### `RetryConfig`
Exponential backoff configuration:

```rust
pub struct RetryConfig {
    pub initial_delay: Duration,    // Default: 500ms
    pub multiplier: f64,            // Default: 2.0
    pub max_delay: Duration,        // Default: 5s
    pub max_retries: usize,         // Default: 5
}
```

### `turnkey_enclave_encrypt`

#### Client Types
Three specialized clients for different flows:

```rust
// For email/SMS/social authentication bundles
pub struct AuthenticationClient {
    encrypt_client: EnclaveEncryptClient,
}

// For wallet/key export decryption
pub struct ExportClient {
    encrypt_client: EnclaveEncryptClient,
}

// For wallet/key import encryption
pub struct ImportClient {
    encrypt_client: EnclaveEncryptClient,
}
```

#### `QuorumPublicKey`
Represents the Turnkey signer enclave's public key:

```rust
impl QuorumPublicKey {
    pub fn production_signer() -> Self; // Returns hardcoded production key
    pub fn from_string(hex: &str) -> Result<Self, Error>;
    pub fn verifying_key(&self) -> Result<VerifyingKey, Error>;
}
```

#### HPKE Message Types
Strongly-typed message structs for protocol versions:

```rust
// Server → Client messages
pub struct ServerSendMsgV1 {
    version: String,
    data: Vec<u8>,               // hex-encoded
    data_signature: P256Signature,
    enclave_quorum_public: P256Public,
}

// Client → Server messages  
pub struct ClientSendMsg {
    encapped_public: P256Public,
    ciphertext: Vec<u8>,
}
```

### `turnkey_proofs`

#### Verification Functions

```rust
// Verify app proof signature
pub fn verify_app_proof_signature(app_proof: &AppProof) -> Result<(), AppProofError>;

// Full verification of app + boot proof pair
pub fn verify(app_proof: &AppProof, boot_proof: &BootProof) -> Result<(), VerifyError>;

// Parse and verify AWS attestation document
pub fn parse_and_verify_aws_nitro_attestation(
    encoded: &str,
    validation_time: Option<SystemTime>,
) -> Result<AttestationDoc, AttestError>;
```

---

## Authentication & Signing

### Request Signing Flow

1. **Serialize Request** - Convert request body to JSON string
2. **Compute Signature** - Sign the JSON bytes with the API key
3. **Create Stamp** - Build `TurnkeyApiStamp` with public key, signature, and scheme
4. **Encode Header** - Base64 URL-safe encode the JSON stamp
5. **Attach Header** - Add `X-Stamp` header to the HTTP request

```rust
// Internal flow in stamp()
let sig: P256Signature = self.signing_key.sign(body);
let stamp = TurnkeyApiStamp {
    public_key: hex::encode(self.compressed_public_key()),
    signature: hex::encode(sig.to_der()),
    scheme: SIGNATURE_SCHEME_P256.to_string(),
};
let json_stamp = serde_json::to_string(&stamp)?;
Ok(StampHeader {
    name: API_KEY_STAMP_HEADER_NAME.to_string(),
    value: BASE64_URL_SAFE_NO_PAD.encode(json_stamp.as_bytes()),
})
```

### Enclave Authentication

#### HPKE Configuration
- **KEM**: P256-HKDF-SHA256
- **KDF**: HKDF-SHA256
- **AEAD**: AES-256-GCM
- **INFO**: `b"turnkey_hpke"`
- **AAD**: `EncappedPublicKey || ReceiverPublicKey`

#### Pre-flight Authentication
- **Client → Server**: Client verifies server's target key is signed by enclave auth key
- **Server → Client**: Server relies on Ump policy engine + activity signing scheme

#### One-Shot Semantics
Target keys are designed for single use to improve forward secrecy:
```rust
// After decryption, keys are cleared
self.target_public = None;
self.target_private = None;
```

---

## Async Patterns

### Tokio Runtime
All async operations use Tokio:

```rust
#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let client = TurnkeyClient::builder()...build()?;
    let result = client.create_wallet(...).await?;
}
```

### Activity Polling
The client automatically polls pending activities:

```rust
pub async fn process_activity<Request: Serialize>(
    &self,
    request: Request,
    path: String,
) -> Result<Activity, TurnkeyClientError> {
    let mut retry_count = 0;
    
    loop {
        let response: ActivityResponse = self.process_request(&request, path.clone()).await?;
        let activity = response.activity.ok_or(TurnkeyClientError::MissingActivity)?;

        match activity.status {
            ActivityStatus::Completed => return Ok(activity),
            ActivityStatus::Pending => {
                if retry_count >= self.retry_config.max_retries {
                    return Err(TurnkeyClientError::ExceededRetries(retry_count));
                }
                retry_count += 1;
                let delay = self.retry_config.compute_delay(retry_count);
                tokio::time::sleep(delay).await;
                continue;
            }
            ActivityStatus::Failed => return Err(TurnkeyClientError::ActivityFailed(...)),
            ActivityStatus::ConsensusNeeded => return Err(TurnkeyClientError::ActivityRequiresApproval(...)),
            _ => return Err(TurnkeyClientError::UnexpectedActivityStatus(...)),
        }
    }
}
```

### HTTP Client Configuration
Built on `reqwest` with sensible defaults:

```rust
// Default timeout: 20 seconds
// TLS: rustls
// Features: json, http2
self.reqwest_builder = self.reqwest_builder
    .timeout(Duration::from_secs(20))
    .user_agent("turnkey-rust-client/0.6.0");
```

---

## Integration Patterns

### Basic Wallet Operations

```rust
use turnkey_client::TurnkeyClient;
use turnkey_client::generated::*;

// 1. Create client
let client = TurnkeyClient::builder()
    .api_key(TurnkeyP256ApiKey::from_env()?)
    .build()?;

// 2. Create wallet
let result = client.create_wallet(
    org_id.clone(),
    client.current_timestamp(),
    CreateWalletIntent {
        wallet_name: "My Wallet".to_string(),
        accounts: vec![WalletAccountParams {
            curve: Curve::Secp256k1,
            path_format: PathFormat::Bip32,
            path: "m/44'/60'/0'/0".to_string(),
            address_format: AddressFormat::Ethereum,
        }],
        mnemonic_length: None,
    },
).await?;

// 3. Sign with the wallet
let signature = client.sign_raw_payload(
    org_id.clone(),
    client.current_timestamp(),
    SignRawPayloadIntentV2 {
        sign_with: result.result.addresses[0].clone(),
        payload: "hello".to_string(),
        encoding: PayloadEncoding::TextUtf8,
        hash_function: HashFunction::Keccak256,
    },
).await?;
```

### Export & Decryption

```rust
use turnkey_enclave_encrypt::{ExportClient, QuorumPublicKey};

// 1. Create export client with production quorum key
let mut export_client = ExportClient::new(&QuorumPublicKey::production_signer());

// 2. Request export (target_public_key goes to Turnkey)
let export_result = client.export_wallet(
    org_id.clone(),
    client.current_timestamp(),
    ExportWalletIntent {
        wallet_id: wallet_id.clone(),
        target_public_key: export_client.target_public_key()?,
        language: None,
    },
).await?;

// 3. Decrypt the bundle locally
let mnemonic = export_client.decrypt_wallet_mnemonic_phrase(
    export_result.result.export_bundle,
    org_id,
)?;
```

### Proof Verification

```rust
use turnkey_proofs::{verify, get_boot_proof_for_app_proof};

// Enable app proofs on client
let client = TurnkeyClient::builder()
    .api_key(api_key)
    .build()?
    .with_app_proofs();

// Create wallet and get proofs
let result = client.create_wallet(...).await?;

// Verify each app proof
for app_proof in result.app_proofs {
    let boot_proof_response = get_boot_proof_for_app_proof(&client, org_id.clone(), &app_proof).await?;
    let boot_proof = boot_proof_response.boot_proof.unwrap();
    
    verify(&app_proof, &boot_proof)?; // Throws on failure
}
```

---

## Notable Rust Patterns

### 1. Generic Stamper Abstraction
The `Stamp` trait allows different signing mechanisms:

```rust
// Client works with any Stamp implementor
pub struct TurnkeyClient<S: Stamp> { ... }

// Can use P256 or secp256k1
let p256_client: TurnkeyClient<TurnkeyP256ApiKey> = ...;
let k256_client: TurnkeyClient<TurnkeySecp256k1ApiKey> = ...;
```

### 2. Builder Pattern with Fluent API

```rust
TurnkeyClient::builder()
    .api_key(api_key)           // Required
    .base_url("...")            // Optional, has default
    .timeout(Duration::...)     // Optional
    .retry_config(...)          // Optional
    .with_reqwest_builder(|b| b.connection_verbose(true))  // Escape hatch
    .build()?
    .with_app_proofs()          // Post-build configuration
```

### 3. Newtype Wrappers for Crypto Types

```rust
// Typed wrapper with serde hex serialization
#[derive(PartialEq, Eq, Debug, Serialize, Deserialize)]
pub struct P256Public(#[serde(with = "hex::serde")] pub [u8; 65]);

impl TryFrom<Vec<u8>> for P256Public {
    type Error = EnclaveEncryptError;
    fn try_from(vec: Vec<u8>) -> Result<Self, EnclaveEncryptError> {
        let inner = vec.try_into()
            .map_err(|_| EnclaveEncryptError::InvalidP256PublicKeyLength)?;
        Ok(Self(inner))
    }
}

impl Deref for P256Public {
    type Target = [u8; 65];
    fn deref(&self) -> &Self::Target { &self.0 }
}
```

### 4. Error Handling with thiserror

```rust
#[derive(Error, Debug)]
pub enum TurnkeyClientError {
    #[error("Client builder is missing its API key")]
    BuilderMissingApiKey,
    
    #[error("HTTP request failed: {0}")]
    Http(#[from] reqwest::Error),
    
    #[error("Activity failed processing: {0:?}")]
    ActivityFailed(Option<Status>),
    
    #[error("This activity ({0}) requires consensus")]
    ActivityRequiresApproval(String),
}
```

### 5. Code Generation from Protobuf
The `codegen` crate generates Rust client code from `.proto` files:

```rust
// Uses tonic_build with custom serde attributes
tonic_build::configure()
    .build_server(false)
    .build_client(false)
    .type_attribute(".services", "#[derive(::serde::Serialize, ::serde::Deserialize)]")
    .type_attribute(".services", "#[serde(rename_all = \"camelCase\")]")
    .compile_protos(&[PUBLIC_API_PROTO_PATH], &[INCLUDE_PROTO_PATH])?;
```

Then generates typed client methods:
```rust
// Auto-generated from proto definitions
pub async fn create_wallet(
    &self,
    organization_id: String,
    timestamp_ms: u128,
    params: CreateWalletIntent,
) -> Result<ActivityResult<CreateWalletResult>, TurnkeyClientError>
```

### 6. Strict Linting with forbid/deny

```rust
// In enclave_encrypt
#![forbid(unsafe_code)]
#![deny(clippy::all, clippy::unwrap_used)]
#![warn(missing_docs, clippy::pedantic)]
```

### 7. Test Organization
Comprehensive test coverage with:
- Unit tests inline in modules
- Integration tests using `wiremock`
- Static test vectors for crypto operations
- Custom test responders for retry logic

```rust
// Custom mock responder for testing retries
struct FailThenSucceedResponder {
    failures_left: Arc<Mutex<usize>>,
}

impl Respond for FailThenSucceedResponder {
    fn respond(&self, _req: &Request) -> ResponseTemplate {
        let mut lock = self.failures_left.lock().unwrap();
        if *lock > 0 {
            *lock -= 1;
            ResponseTemplate::new(200).set_body_json(pending_activity())
        } else {
            ResponseTemplate::new(200).set_body_json(completed_activity())
        }
    }
}
```

---

## Crypto Primitives Used

| Primitive | Crate | Usage |
|-----------|-------|-------|
| P-256 (secp256r1) | `p256` | API key signing, HPKE |
| secp256k1 | `k256` | Alternative API key signing |
| P-384 | `p384` | AWS attestation verification |
| HPKE | `hpke` | Enclave encryption |
| SHA-256/384/512 | `sha2` | Hashing |
| AES-256-GCM | via HPKE | Authenticated encryption |
| Base58Check | `bs58` | Auth bundle encoding |
| COSE/CBOR | `aws-nitro-enclaves-cose`, `ciborium` | Attestation documents |

---

## Open Questions & Future Investigation

1. **Passkey/WebAuthn Support**
   - The proto definitions include WebAuthn types, but no Rust client support exists yet
   - Could investigate adding passkey authentication support

2. **Session Management**
   - The current design is stateless; each request is independently signed
   - Investigate session-based auth for reduced overhead

3. **Streaming Support**
   - Activity polling is request-based
   - Could benefit from WebSocket or SSE for real-time updates

4. **WASM Compatibility**
   - Current dependencies may not be WASM-compatible
   - Would enable browser-based Rust usage

5. **Custom Stamper Implementations**
   - Hardware security module (HSM) integration
   - Hardware wallet signing support

6. **Batch Operations**
   - API supports batch activities, but ergonomics could improve
   - Consider higher-level batch signing abstractions

7. **TVC (Turnkey Verified Cloud)**
   - Marked as "experimental"
   - Worth monitoring for verifiable deployment patterns

8. **QuorumOS Integration**
   - The SDK depends on `qos_core` and `qos_p256` from QuorumOS
   - Worth exploring the full QuorumOS stack

---

## References

- [Turnkey API Documentation](https://docs.turnkey.com/api-reference/overview)
- [Turnkey Security Overview](https://docs.turnkey.com/security)
- [Enclave Secure Channels](https://docs.turnkey.com/security/enclave-secure-channels)
- [Turnkey Verified](https://docs.turnkey.com/security/turnkey-verified)
- [QuorumOS Repository](https://github.com/tkhq/qos)
- [RFC 9180 - HPKE](https://datatracker.ietf.org/doc/rfc9180/)
- [AWS Nitro Enclaves](https://docs.aws.amazon.com/enclaves/latest/user/nitro-enclave.html)
