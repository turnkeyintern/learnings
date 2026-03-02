# Turnkey Go SDK - Technical Analysis & Learnings

> Comprehensive analysis of the Turnkey Go SDK (`github.com/tkhq/go-sdk`)

---

## SDK Overview

The Turnkey Go SDK provides a native Go interface for interacting with the Turnkey API service. Turnkey is a key management infrastructure that provides:

- **HD Wallet Management**: Create, import, export, and manage hierarchical deterministic wallets
- **Private Key Operations**: Sign transactions and raw payloads using keys secured in Turnkey's enclaves
- **Organization Management**: Create sub-organizations with delegated access patterns
- **Authentication**: Multiple auth methods including API keys, OAuth, and OTP flows
- **Enclave Encryption**: Secure data transfer to/from Turnkey's secure enclaves using HPKE

### Key Characteristics

- **Swagger-Generated**: Core API client is auto-generated from OpenAPI/Swagger specs using `go-swagger`
- **Activity-Based API**: All mutating operations are "activities" with consistent request/response patterns
- **Request Signing**: Every request requires cryptographic signing via "stamps" (X-Stamp header)
- **Multiple Signature Schemes**: Supports P-256, secp256k1, and ED25519 for API keys

---

## Package Structure

```
github.com/tkhq/go-sdk/
├── client.go                    # Main SDK client and configuration
├── VERSION                      # Embedded version for X-Client-Version header
├── pkg/
│   ├── api/
│   │   ├── client/              # go-swagger generated API client
│   │   │   ├── turnkey_api_client.go   # Main TurnkeyAPI client struct
│   │   │   ├── activities/      # Activity operations
│   │   │   ├── api_keys/        # API key management
│   │   │   ├── authenticators/  # WebAuthn authenticator management
│   │   │   ├── organizations/   # Org & sub-org management
│   │   │   ├── policies/        # Policy CRUD operations
│   │   │   ├── private_keys/    # Private key operations
│   │   │   ├── sessions/        # Session management (whoami, OTP login, etc.)
│   │   │   ├── signing/         # Sign transactions and raw payloads
│   │   │   ├── users/           # User management
│   │   │   ├── wallets/         # Wallet CRUD and export
│   │   │   └── ...              # ~20+ API domains
│   │   └── models/              # Request/response models (~300+ types)
│   ├── apikey/                  # API key generation, signing, encoding
│   │   ├── apikey.go            # Key struct and Stamp() function
│   │   ├── ecdsa.go             # P-256 and secp256k1 implementation
│   │   ├── ed25519.go           # ED25519 implementation
│   │   └── schemes.go           # Signature scheme constants
│   ├── enclave_encrypt/         # HPKE encryption for enclave communication
│   │   ├── client.go            # Client-side encryption
│   │   ├── server.go            # Server-side decryption (for testing)
│   │   └── encrypt.go           # Core HPKE primitives
│   ├── encryptionkey/           # Encryption key management (for exports)
│   ├── store/                   # Key storage abstraction
│   │   ├── store.go             # Store interface
│   │   ├── local/               # Filesystem-based storage
│   │   └── ram/                 # In-memory storage
│   ├── common/                  # Shared interfaces (IKey, IMetadata)
│   └── util/                    # Helper functions
├── examples/                    # Usage examples
│   ├── whoami/                  # Basic API call
│   ├── wallets/                 # Wallet creation and export
│   ├── signing/                 # Transaction/payload signing
│   ├── delegated_access/        # Sub-org and policy setup
│   ├── email_otp/               # OTP authentication flow
│   └── go-ethereum/             # Ethereum integration patterns
└── templates/                   # Custom go-swagger templates
```

---

## Core Types & Interfaces

### Client Architecture

```go
// Main SDK client (client.go)
type Client struct {
    Client        *client.TurnkeyAPI  // Generated API client
    Authenticator *Authenticator       // Request signer
    APIKey        *apikey.Key          // Loaded API key
}

// Configuration options
type config struct {
    apiKey          *apikey.Key
    clientVersion   string
    registry        strfmt.Registry
    transportConfig *client.TransportConfig
    logger          Logger
}
```

### API Key Types

```go
// pkg/apikey/apikey.go
type Key struct {
    Metadata
    TkPrivateKey  string           // Hex-encoded private key
    TkPublicKey   string           // Compressed public key (33 bytes)
    scheme        signatureScheme  // P256, SECP256K1, or ED25519
    underlyingKey underlyingKey    // Interface for signing
}

type APIStamp struct {
    PublicKey string          `json:"publicKey"`
    Signature string          `json:"signature"`  // DER-encoded, hex
    Scheme    signatureScheme `json:"scheme"`
}

type Metadata struct {
    Name          string   `json:"name"`
    Organizations []string `json:"organizations"`
    PublicKey     string   `json:"public_key"`
    Scheme        string   `json:"scheme"`
}
```

### Key Interface (Generics Pattern)

```go
// pkg/common/interfaces.go
type IKey[M IMetadata] interface {
    GetPublicKey() string
    GetPrivateKey() string
    GetCurve() string
    GetMetadata() M
    LoadMetadata(s string) (*M, error)
    MergeMetadata(m M) error
}

type IMetadata interface{}
```

### Generated API Client

```go
// pkg/api/client/turnkey_api_client.go (auto-generated)
type TurnkeyAPI struct {
    Activities       activities.ClientService
    APIKeys          api_keys.ClientService
    Authenticators   authenticators.ClientService
    Organizations    organizations.ClientService
    Policies         policies.ClientService
    PrivateKeys      private_keys.ClientService
    Sessions         sessions.ClientService
    Signing          signing.ClientService
    Users            users.ClientService
    Wallets          wallets.ClientService
    // ... 15+ more service interfaces
    Transport        runtime.ClientTransport
}
```

---

## Authentication & Request Signing

### The Stamp Mechanism

Every Turnkey API request requires an `X-Stamp` header containing a signed payload:

```go
// pkg/apikey/apikey.go
func Stamp(message []byte, apiKey *Key) (out string, err error) {
    // 1. Sign the request body with the API key
    signature, err := apiKey.underlyingKey.sign(message)
    
    // 2. Create stamp structure
    stamp := APIStamp{
        PublicKey: apiKey.TkPublicKey,
        Signature: signature,
        Scheme:    apiKey.scheme,
    }
    
    // 3. JSON-encode and base64url-encode (no padding)
    jsonStamp, _ := json.Marshal(stamp)
    return base64.RawURLEncoding.EncodeToString(jsonStamp), nil
}
```

### Authenticator Implementation

```go
// client.go
type Authenticator struct {
    Key *apikey.Key
}

// Implements runtime.ClientAuthInfoWriter
func (auth *Authenticator) AuthenticateRequest(req runtime.ClientRequest, reg strfmt.Registry) error {
    stamp, err := apikey.Stamp(req.GetBody(), auth.Key)
    if err != nil {
        return err
    }
    return req.SetHeaderParam("X-Stamp", stamp)
}
```

### Signing Implementation

```go
// pkg/apikey/ecdsa.go
func (k *ecdsaKey) sign(msg []byte) (string, error) {
    hash := sha256.Sum256(msg)
    sigBytes, _ := ecdsa.SignASN1(rand.Reader, k.privKey, hash[:])
    return hex.EncodeToString(sigBytes), nil
}
```

### Signature Schemes

```go
const (
    SchemeP256      = signatureScheme("SIGNATURE_SCHEME_TK_API_P256")
    SchemeSECP256K1 = signatureScheme("SIGNATURE_SCHEME_TK_API_SECP256K1")  
    SchemeED25519   = signatureScheme("SIGNATURE_SCHEME_TK_API_ED25519")
)
```

---

## API Client Pattern

### Initialization

```go
client, err := sdk.New(
    sdk.WithAPIKeyName("default"),           // Load from ~/.config/turnkey/keys/
    // OR
    sdk.WithAPIKey(apiKey),                   // Use in-memory key
    sdk.WithLogger(&myLogger{}),              // Custom logging
    sdk.WithTransportConfig(customConfig),    // Custom host/schemes
)
```

### Option Functions Pattern

```go
type OptionFunc func(c *config) error

func WithAPIKeyName(keyname string) OptionFunc {
    return func(c *config) error {
        apiKey, err := local.New[*apikey.Key]().Load(keyname)
        c.apiKey = apiKey
        return err
    }
}
```

### HTTP Transport Layering

The SDK layers multiple `RoundTripper` implementations:

```go
transport := httptransport.New(host, basePath, schemes)

// Layer 1: Logging (captures error responses)
base := &loggingRoundTripper{inner: transport.Transport, logger: c.logger}

// Layer 2: Client version header
base = SetClientVersion(base, c.clientVersion)  // X-Client-Version

transport.Transport = base
```

### Making API Calls

```go
// 1. Create parameters with request body
params := sessions.NewGetWhoamiParams().WithBody(&models.GetWhoamiRequest{
    OrganizationID: client.DefaultOrganization(),
})

// 2. Call the API method with authenticator
resp, err := client.V0().Sessions.GetWhoami(params, client.Authenticator)

// 3. Access response payload
fmt.Println(*resp.Payload.UserID)
```

---

## Integration Patterns

### Pattern 1: Basic API Call

```go
client, _ := sdk.New(sdk.WithAPIKeyName("default"))

params := wallets.NewCreateWalletParams().WithBody(&models.CreateWalletRequest{
    OrganizationID: client.DefaultOrganization(),
    TimestampMs:    util.RequestTimestamp(),
    Type:           (*string)(models.ActivityTypeCreateWallet.Pointer()),
    Parameters: &models.CreateWalletIntent{
        WalletName: &walletName,
        Accounts: []*models.WalletAccountParams{{
            AddressFormat: models.AddressFormatEthereum.Pointer(),
            Curve:         models.CurveSecp256k1.Pointer(),
            Path:          &path,
            PathFormat:    models.PathFormatBip32.Pointer(),
        }},
    },
})

resp, _ := client.V0().Wallets.CreateWallet(params, client.Authenticator)
walletID := resp.Payload.Activity.Result.CreateWalletResult.WalletID
```

### Pattern 2: Transaction Signing

```go
params := signing.NewSignTransactionParams().WithBody(&models.SignTransactionRequest{
    OrganizationID: &orgID,
    TimestampMs:    util.RequestTimestamp(),
    Type:           (*string)(models.ActivityTypeSignTransactionV2.Pointer()),
    Parameters: &models.SignTransactionIntentV2{
        SignWith:            &address,
        Type:                models.TransactionTypeEthereum.Pointer(),
        UnsignedTransaction: &unsignedHex,  // RLP-encoded tx
    },
})

resp, _ := client.V0().Signing.SignTransaction(params, client.Authenticator)
signedTx := resp.Payload.Activity.Result.SignTransactionResult.SignedTransaction
```

### Pattern 3: Ethereum Integration (bind.SignerFn)

```go
func MakeTurnkeySignerFn(client *sdk.Client, signWith string, chainID *big.Int, orgID string) bind.SignerFn {
    return func(from common.Address, tx *types.Transaction) (*types.Transaction, error) {
        // Build unsigned EIP-1559 payload
        unsignedPayload := []any{
            tx.ChainId(), tx.Nonce(), tx.GasTipCap(), tx.GasFeeCap(),
            tx.Gas(), tx.To(), tx.Value(), tx.Data(), tx.AccessList(),
        }
        rlpBytes, _ := rlp.EncodeToBytes(unsignedPayload)
        unsigned := append([]byte{types.DynamicFeeTxType}, rlpBytes...)
        
        // Sign with Turnkey
        params := signing.NewSignTransactionParams().WithBody(&models.SignTransactionRequest{
            // ... populate request
        })
        resp, _ := client.V0().Signing.SignTransaction(params, client.Authenticator)
        
        // Decode signed transaction
        rawSigned, _ := hex.DecodeString(*resp.Payload.Activity.Result.SignTransactionResult.SignedTransaction)
        finalTx := new(types.Transaction)
        finalTx.UnmarshalBinary(rawSigned)
        return finalTx, nil
    }
}
```

### Pattern 4: Delegated Access (Sub-Organizations)

```go
// 1. Create sub-org with root user and wallet
createSubOrgParams := organizations.NewCreateSubOrganizationParams().WithBody(&models.CreateSubOrganizationRequest{
    OrganizationID: &parentOrgID,
    Type:           StringPointer(string(models.ActivityTypeCreateSubOrganizationV7)),
    Parameters: &models.CreateSubOrganizationIntentV7{
        SubOrganizationName: StringPointer("My Sub Org"),
        RootUsers: []*models.RootUserParamsV4{{
            UserName: StringPointer("Delegated User"),
            APIKeys: []*models.APIKeyParamsV2{{
                PublicKey: &delegatedPublicKey,
            }},
        }},
        Wallet: &models.WalletParams{...},
    },
})

// 2. Create policy for delegated account
createPolicyParams := policies.NewCreatePolicyParams().WithBody(&models.CreatePolicyRequest{
    OrganizationID: &subOrgID,
    Parameters: &models.CreatePolicyIntentV3{
        PolicyName: StringPointer("Allow specific recipient"),
        Effect:     models.EffectAllow.Pointer(),
        Condition:  StringPointer("eth.tx.to == '0x...'"),
        Consensus:  StringPointer(fmt.Sprintf("approvers.any(user, user.id == '%s')", delegatedUserID)),
    },
})
```

### Pattern 5: Wallet Export with Enclave Encryption

```go
// 1. Generate client-side encryption key
encryptionKey, _ := encryptionkey.New(userId, organizationId)

// 2. Export wallet (encrypted to target key)
params := wallets.NewExportWalletParams().WithBody(&models.ExportWalletRequest{
    Parameters: &models.ExportWalletIntent{
        WalletID:        &walletId,
        TargetPublicKey: &encryptionKey.TkPublicKey,
    },
})
result, _ := client.V0().Wallets.ExportWallet(params, client.Authenticator)

// 3. Decrypt locally
kemPrivateKey, _ := encryptionkey.DecodeTurnkeyPrivateKey(encryptionKey.GetPrivateKey())
signerKey, _ := hexToPublicKey(encryptionkey.SignerProductionPublicKey)
encryptClient, _ := enclave_encrypt.NewEnclaveEncryptClientFromTargetKey(signerKey, *kemPrivateKey)
plaintext, _ := encryptClient.Decrypt([]byte(exportBundle), organizationId)
```

---

## Notable Go Patterns

### 1. Functional Options Pattern

```go
type OptionFunc func(c *config) error

func New(options ...OptionFunc) (*Client, error) {
    c := &config{defaults...}
    for _, o := range options {
        if err := o(c); err != nil {
            return nil, err
        }
    }
    // build client...
}
```

### 2. Generics for Key Storage

```go
type Store[T common.IKey[M], M common.IMetadata] interface {
    Load(name string) (T, error)
    Store(name string, key common.IKey[M]) error
}

// Usage:
store := local.New[*apikey.Key]()
key, _ := store.Load("default")
```

### 3. Interface-Based Key Abstraction

```go
type underlyingKey interface {
    sign(message []byte) (string, error)
}

// ecdsaKey implements underlyingKey
// ed25519Key implements underlyingKey
```

### 4. Embedded Version

```go
//go:embed VERSION
var embeddedVersion string
var DefaultClientVersion = "turnkey-go/" + strings.TrimSpace(embeddedVersion)
```

### 5. RoundTripper Middleware Chain

```go
type loggingRoundTripper struct {
    inner  http.RoundTripper
    logger Logger
}

func (lrt *loggingRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
    resp, err := lrt.inner.RoundTrip(req)
    // log errors...
    return resp, err
}
```

### 6. Custom go-swagger Templates

Modified `schemavalidator.gotmpl` for:
- Cleaner enum variant names (avoids `AllCapsALLCAPSALLTHETIME`)
- Typed enum slices (`[]ActivityType` instead of `[]interface{}`)

### 7. Pointer Helper Methods on Enums

```go
func (m ActivityType) Pointer() *ActivityType {
    return &m
}

// Usage:
Type: (*string)(models.ActivityTypeCreateWallet.Pointer())
```

---

## Enclave Encryption (HPKE)

The SDK includes a complete HPKE implementation for secure communication with Turnkey enclaves:

### Configuration

```go
const (
    KemId           = hpke.KEM_P256_HKDF_SHA256
    KdfId           = hpke.KDF_HKDF_SHA256
    AeadId          = hpke.AEAD_AES256GCM
    TurnkeyHpkeInfo = "turnkey_hpke"
)
```

### Protocol

1. **Client → Server**: Client generates target keypair, encrypts with enclave's public key
2. **Server → Client**: Server encrypts response with client's target public key
3. **Authentication**: Enclave quorum key signs encapsulated public keys for verification

### AAD (Additional Associated Data)

```go
aad = EncappedPublicKey || ReceiverPublicKey
```

---

## Open Questions

1. **Activity Polling**: The SDK doesn't expose activity status polling. For async activities, how should clients wait for completion?

2. **Rate Limiting**: No built-in rate limiting or retry logic. Is this expected to be handled by the caller?

3. **WebSocket Support**: The API appears to support WebSocket connections for real-time updates—is this planned for the SDK?

4. **Batch Operations**: Some endpoints support batch operations (`SignRawPayloads`). Are there best practices for batch size limits?

5. **Key Rotation**: What's the recommended pattern for rotating API keys without downtime?

6. **Error Recovery**: The `loggingRoundTripper` logs error bodies but doesn't expose structured error types. Consider adding typed errors?

7. **Context Propagation**: The current API doesn't accept `context.Context` for cancellation. Is this a go-swagger limitation?

8. **Enclave Key Rotation**: How often does `SignerProductionPublicKey` rotate, and how should clients handle this?

9. **Sub-module Design**: The `enclave_encrypt` package is a separate Go module (`github.com/tkhq/go-sdk/pkg/enclave_encrypt`). What drove this decision? Does it simplify versioning?

10. **Activity Versioning**: Many activity types have multiple versions (e.g., `CreateSubOrganizationV7`). What's the deprecation policy for older versions?

---

## Summary

The Turnkey Go SDK is a well-structured, production-ready library that follows Go best practices:

- **Clean separation**: Generated code (`pkg/api/`) vs. handwritten logic (`pkg/apikey/`, `client.go`)
- **Extensible**: Functional options, interface-based abstractions
- **Secure**: HPKE for enclave communication, multiple signature schemes
- **Ergonomic**: Helper methods, sensible defaults, logging hooks

The main integration complexity comes from the activity-based API model and the manual `Authenticator` attachment pattern, which requires passing `client.Authenticator` to every API call.
