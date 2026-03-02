# Turnkey Python SDK - Technical Learnings

> **Repository:** [turnkeyintern/python-sdk](https://github.com/turnkeyintern/python-sdk)  
> **Analysis Date:** March 2, 2026  
> **Python Version:** 3.8+

---

## SDK Overview

The Turnkey Python SDK provides a type-safe HTTP client for interacting with the Turnkey API. It follows the same patterns established by the TypeScript SDK but adapted to Python idioms.

### Key Features
- **Type-safe API calls** with full Pydantic model definitions
- **Code generation** from OpenAPI spec (Swagger) for types and HTTP client
- **Request stamping** with ECDSA P-256 signatures for authentication
- **Activity polling** for async operations
- **Monorepo architecture** with separate packages for types, HTTP client, and stamper

---

## Package Structure

The SDK is organized as a **monorepo** with three pip-installable packages:

```
python-sdk/
├── packages/
│   ├── sdk-types/              # turnkey-sdk-types
│   │   ├── src/turnkey_sdk_types/
│   │   │   ├── __init__.py
│   │   │   ├── errors.py       # Error classes
│   │   │   ├── types.py        # Non-generated types
│   │   │   └── generated/
│   │   │       └── types.py    # 7,700+ lines of generated Pydantic models
│   │   └── tests/
│   │
│   ├── http/                   # turnkey-http
│   │   ├── src/turnkey_http/
│   │   │   ├── __init__.py
│   │   │   ├── version.py
│   │   │   └── generated/
│   │   │       └── client.py   # ~5,000 lines, auto-generated HTTP methods
│   │   └── tests/
│   │
│   └── api-key-stamper/        # turnkey-api-key-stamper
│       └── src/turnkey_api_key_stamper/
│           ├── __init__.py
│           └── stamper.py      # ~100 lines, ECDSA signing
│
├── codegen/                    # Code generation scripts
│   ├── constants.py
│   ├── utils.py
│   ├── types/
│   │   ├── generate_types.py
│   │   └── pydantic_helpers.py
│   └── http/
│       └── generate_http.py
│
├── schema/
│   └── public_api.swagger.json # OpenAPI spec from Turnkey
│
├── pyproject.toml              # Root project config
└── Makefile                    # Build commands
```

### Packaging Toolchain

| Tool | Purpose |
|------|---------|
| **setuptools** | Build system (not Poetry/uv) |
| **pip** | Package installation |
| **ruff** | Code formatting |
| **mypy** | Type checking |
| **pytest** | Testing |

```toml
# Example from pyproject.toml
[build-system]
requires = ["setuptools>=61.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
requires-python = ">=3.8"
```

### Key Dependencies

| Package | Purpose |
|---------|---------|
| `pydantic>=2.0.0` | Type definitions and validation |
| `requests>=2.31.0` | HTTP client (sync only) |
| `cryptography>=41.0.0` | ECDSA signing for API key stamping |

---

## Core Types & Classes

### 1. TurnkeyClient (HTTP Package)

The main entry point for API interactions:

```python
from turnkey_http import TurnkeyClient
from turnkey_api_key_stamper import ApiKeyStamper, ApiKeyStamperConfig

# Initialize
config = ApiKeyStamperConfig(
    api_public_key="your-api-public-key",
    api_private_key="your-api-private-key"
)
stamper = ApiKeyStamper(config)

client = TurnkeyClient(
    base_url="https://api.turnkey.com",
    stamper=stamper,
    organization_id="your-org-id",
    default_timeout=30,            # seconds
    polling_interval_ms=1000,      # milliseconds
    max_polling_retries=3
)
```

**Key Methods:**
- Query methods: `get_whoami()`, `get_wallets()`, `get_users()`, etc.
- Activity methods: `create_wallet()`, `sign_transaction()`, `create_api_keys()`, etc.
- Stamping methods: `stamp_create_wallet()`, `stamp_get_whoami()`, etc.
- Generic: `send_signed_request(signed_request, response_type)`

### 2. ApiKeyStamper (Stamper Package)

Handles request signing:

```python
@dataclass
class ApiKeyStamperConfig:
    """Configuration for API key stamper."""
    api_public_key: str
    api_private_key: str

@dataclass
class TStamp:
    """Stamp result containing header name and value."""
    stamp_header_name: str
    stamp_header_value: str

class ApiKeyStamper:
    def stamp(self, content: str) -> TStamp:
        """Create an authentication stamp for the given content."""
```

### 3. Pydantic Models (SDK Types)

All API types are Pydantic models with a shared base:

```python
from pydantic import BaseModel, ConfigDict

class TurnkeyBaseModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True)  # Support field aliases

# Example generated type
class v1Wallet(TurnkeyBaseModel):
    walletId: str = Field(description="Unique identifier for a Wallet.")
    walletName: str = Field(description="Human-readable name for a Wallet.")
    accounts: List[v1WalletAccount]
    createdAt: externaldatav1Timestamp
    updatedAt: externaldatav1Timestamp
    ...
```

### 4. Request/Response Types

For each API endpoint, three types are generated:

```python
# Body type (what you pass in)
class CreateWalletBody(TurnkeyBaseModel):
    timestampMs: Optional[str] = None
    organizationId: Optional[str] = None
    walletName: str
    accounts: List[v1WalletAccountParams]
    ...

# Response type (what you get back)
class CreateWalletResponse(TurnkeyBaseModel):
    activity: v1Activity
    walletId: Optional[str] = None  # Flattened from result
    addresses: Optional[List[str]] = None
    ...

# Input type (wrapper, less commonly used)
class CreateWalletInput(TurnkeyBaseModel):
    body: CreateWalletBody
```

### 5. Error Types

```python
class TurnkeyErrorCodes(str, Enum):
    NETWORK_ERROR = "NETWORK_ERROR"
    BAD_RESPONSE = "BAD_RESPONSE"

class TurnkeyError(Exception):
    def __init__(self, message: str, code: Optional[TurnkeyErrorCodes], cause: Any):
        self.code = code
        self.cause = cause

class TurnkeyNetworkError(TurnkeyError):
    def __init__(self, message: str, status_code: int, code: TurnkeyErrorCodes, cause: Any):
        self.status_code = status_code
```

### 6. SignedRequest Type

For stamp-then-send workflows:

```python
class RequestType(Enum):
    QUERY = "query"
    ACTIVITY = "activity"
    ACTIVITY_DECISION = "activityDecision"

@dataclass
class SignedRequest:
    url: str
    body: str
    stamp: TStamp
    type: RequestType = RequestType.QUERY
```

---

## Authentication & Signing

### How Stamping Works

1. **Serialize request body** to JSON string
2. **Sign with ECDSA P-256** using the API private key
3. **Create stamp object** with public key, scheme, and signature
4. **Base64url encode** the stamp JSON (no padding)
5. **Attach as `X-Stamp` header**

```python
def stamp(self, content: str) -> TStamp:
    # Sign content with ECDSA
    signature = _sign_with_api_key(
        self.api_public_key, 
        self.api_private_key, 
        content
    )

    # Build stamp object
    stamp = {
        "publicKey": self.api_public_key,
        "scheme": "SIGNATURE_SCHEME_TK_API_P256",
        "signature": signature,
    }

    # Encode to base64url (no padding)
    stamp_header_value = (
        urlsafe_b64encode(json.dumps(stamp).encode())
        .decode()
        .rstrip("=")  # Remove padding
    )

    return TStamp(
        stamp_header_name="X-Stamp",
        stamp_header_value=stamp_header_value,
    )
```

### Key Validation

The stamper validates that the provided public key matches the private key:

```python
def _sign_with_api_key(public_key: str, private_key: str, content: str) -> str:
    # Derive private key from hex
    ec_private_key = ec.derive_private_key(
        int(private_key, 16), ec.SECP256R1(), default_backend()
    )

    # Get the public key to validate
    public_key_obj = ec_private_key.public_key()
    public_key_bytes = public_key_obj.public_bytes(
        encoding=serialization.Encoding.X962,
        format=serialization.PublicFormat.CompressedPoint,
    )
    derived_public_key = public_key_bytes.hex()

    # Validate
    if derived_public_key != public_key:
        raise ValueError(f"Bad API key. Expected {public_key}, got {derived_public_key}")

    # Sign
    signature = ec_private_key.sign(content.encode(), ec.ECDSA(hashes.SHA256()))
    return signature.hex()
```

---

## Activity Polling

### Terminal Statuses

```python
TERMINAL_ACTIVITY_STATUSES = [
    "ACTIVITY_STATUS_COMPLETED",
    "ACTIVITY_STATUS_FAILED",
    "ACTIVITY_STATUS_CONSENSUS_NEEDED",
    "ACTIVITY_STATUS_REJECTED",
]
```

### Polling Flow

```python
def _poll_for_completion(self, activity: Any) -> Any:
    """Poll until activity reaches terminal status."""
    if activity.status in TERMINAL_ACTIVITY_STATUSES:
        return activity

    attempts = 0
    while attempts < self.max_polling_retries:
        time.sleep(self.polling_interval_ms / 1000.0)
        poll_response = self.get_activity(GetActivityBody(activityId=activity.id))
        activity = poll_response.activity
        if activity.status in TERMINAL_ACTIVITY_STATUSES:
            break
        attempts += 1

    return activity
```

### Result Flattening

When an activity completes, result fields are **flattened** into the response:

```python
def _activity(self, url, body, result_key, response_type):
    # Make initial request
    initial_response = self._request(url, body, GetActivityResponse)

    # Poll for completion
    activity = self._poll_for_completion(initial_response.activity)

    # Flatten result fields if completed
    if activity.status == "ACTIVITY_STATUS_COMPLETED" and activity.result:
        result = activity.result
        if hasattr(result, result_key):
            result_data = getattr(result, result_key)
            if result_data:
                result_dict = result_data.model_dump(by_alias=True, exclude_none=True)
                # Construct response with activity AND result fields
                return response_type(activity=activity, **result_dict)

    return response_type(activity=activity)
```

**Example:** `CreateWalletResponse` has both `activity` and flattened `walletId`/`addresses`.

---

## Async Support

### Current State: **Sync Only**

The Python SDK currently uses the synchronous `requests` library:

```python
import requests

response = requests.post(
    full_url,
    headers=headers,
    data=body_str,
    timeout=self.default_timeout
)
```

### No asyncio Support

Unlike the TypeScript SDK which has native async/await, the Python SDK:
- Uses `time.sleep()` for polling delays
- Blocks on HTTP requests
- Has no `async def` methods

### Potential Async Migration

To add async support, the SDK would need:
1. `httpx` or `aiohttp` for async HTTP
2. `asyncio.sleep()` for polling
3. Parallel `AsyncTurnkeyClient` class

---

## Integration Patterns

### Pattern 1: Direct Method Calls

```python
# Query (sync, no polling)
response = client.get_whoami()
print(response.organizationId)

# Activity (makes request, polls, flattens result)
response = client.create_wallet(CreateWalletBody(
    walletName="My Wallet",
    accounts=[v1WalletAccountParams(
        curve=v1Curve.CURVE_SECP256K1,
        pathFormat=v1PathFormat.PATH_FORMAT_BIP32,
        path="m/44'/60'/0'/0/0",
        addressFormat=v1AddressFormat.ADDRESS_FORMAT_ETHEREUM,
    )]
))
print(response.walletId)  # Flattened from result
```

### Pattern 2: Stamp and Send

For more control (e.g., signing on a different machine):

```python
# Stamp without sending
signed_request = client.stamp_create_wallet(CreateWalletBody(
    walletName="My Wallet",
    accounts=[...]
))

# Later: send the signed request
response = client.send_signed_request(signed_request, CreateWalletResponse)
```

### Pattern 3: Organization ID Override

The client has a default `organization_id`, but it can be overridden per-request:

```python
# Use client's default org
response = client.get_organization()

# Override for this request
response = client.get_organization(GetOrganizationBody(
    organizationId="different-org-id"
))
```

### Pattern 4: Error Handling

```python
from turnkey_sdk_types import TurnkeyNetworkError

try:
    response = client.create_wallet(CreateWalletBody(...))
except TurnkeyNetworkError as e:
    print(f"Error: {e}")
    print(f"Status code: {e.status_code}")
    print(f"Error code: {e.code}")
```

---

## Notable Python Patterns

### 1. Pydantic v2 Usage

The SDK uses Pydantic v2 with modern features:

```python
from pydantic import BaseModel, Field, ConfigDict

class TurnkeyBaseModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True)  # Allow alias OR field name
```

**Key Pydantic patterns:**
- `model_dump(by_alias=True, exclude_none=True)` for serialization
- `Field(alias="@type")` for JSON fields that aren't valid Python identifiers
- `Optional[T] = None` for optional fields

### 2. Dataclasses for Simple Types

Non-Pydantic types use `@dataclass`:

```python
from dataclasses import dataclass

@dataclass
class ApiKeyStamperConfig:
    api_public_key: str
    api_private_key: str

@dataclass
class TStamp:
    stamp_header_name: str
    stamp_header_value: str
```

### 3. Enum Patterns

String enums for API values:

```python
from enum import Enum

class v1Curve(str, Enum):
    CURVE_SECP256K1 = "CURVE_SECP256K1"
    CURVE_ED25519 = "CURVE_ED25519"
```

### 4. Type Overloads

For `send_signed_request`:

```python
from typing import overload, TypeVar

T = TypeVar('T')

@overload
def send_signed_request(self, signed_request: SignedRequest, response_type: type[T]) -> T: ...

@overload
def send_signed_request(self, signed_request: SignedRequest) -> Any: ...

def send_signed_request(self, signed_request, response_type=None):
    # Implementation
```

### 5. Code Generation Approach

- **Types:** Generated from OpenAPI definitions using custom Python scripts
- **HTTP Client:** Generated from OpenAPI paths
- **Version handling:** Automatic resolution of versioned activity types

```python
# From constants.py - version mappings
VERSIONED_ACTIVITY_TYPES = {
    "ACTIVITY_TYPE_CREATE_USERS": (
        "ACTIVITY_TYPE_CREATE_USERS_V3",
        "v1CreateUsersIntentV3",
        "v1CreateUsersResult",
    ),
    ...
}
```

---

## Code Generation Details

### Type Generation (`codegen/types/generate_types.py`)

Generates Pydantic models from OpenAPI definitions:

1. **Base types:** Direct conversion from `#/definitions/`
2. **API types:** Request bodies, responses, inputs for each endpoint
3. **Field handling:** Descriptions, optionality, aliases

### HTTP Generation (`codegen/http/generate_http.py`)

Generates client methods:

1. **Query methods:** Direct request, no polling
2. **Activity methods:** Request + poll + flatten
3. **Activity decision methods:** approve/reject (no polling)
4. **Stamp methods:** Return `SignedRequest` without sending

### Version Resolution

The codegen handles API versioning:

```python
# Unversioned → Versioned
"ACTIVITY_TYPE_CREATE_USERS" → "ACTIVITY_TYPE_CREATE_USERS_V3"

# Intent type resolution
"ACTIVITY_TYPE_CREATE_USERS" → "v1CreateUsersIntentV3"

# Result type resolution  
"ACTIVITY_TYPE_CREATE_USERS" → "v1CreateUsersResult"
```

---

## Comparison with TypeScript SDK

| Aspect | TypeScript SDK | Python SDK |
|--------|---------------|------------|
| **Async** | Native async/await | Sync only (requests) |
| **Types** | Zod schemas | Pydantic v2 models |
| **HTTP Client** | fetch/node-fetch | requests |
| **Monorepo** | npm workspaces | pip editable installs |
| **Build** | tsup/tsc | setuptools |
| **Package Manager** | npm/pnpm | pip |
| **Code Gen** | Custom TS scripts | Custom Python scripts |

### Similarities
- Same OpenAPI spec as source of truth
- Same stamping algorithm (ECDSA P-256)
- Same activity polling pattern
- Same result flattening approach
- Same package split (types, http, stamper)

### Key Differences
- Python SDK is sync-only (no asyncio)
- Uses Pydantic instead of Zod
- Uses dataclasses for simple types
- Simpler module structure (no barrel exports)

---

## Development Workflow

### Setup
```bash
# Clone and create venv
git clone <repo>
cd python-sdk
python3 -m venv venv
source venv/bin/activate

# Install all packages in editable mode
make install
```

### Code Generation
```bash
make generate          # Both types and HTTP client
make generate-types    # Types only
make generate-http     # HTTP client only
```

### Testing
```bash
# Set up .env file with credentials
cp packages/http/tests/.env.example packages/http/tests/.env

# Run tests
make test
```

### Quality
```bash
make format      # Format with ruff
make typecheck   # Type check with mypy
```

---

## Open Questions

### 1. Async Support
- Should an async client be added?
- Would it be a separate package or same package with async variants?
- What HTTP library (httpx, aiohttp)?

### 2. WebAuthn Stamper
- TypeScript SDK has WebAuthn support - should Python have it?
- What's the use case for Python + WebAuthn?

### 3. Session/Caching
- Should there be connection pooling?
- Rate limiting helpers?

### 4. Retry Logic
- Currently only polling retries, no HTTP retries
- Should exponential backoff be added?

### 5. Logging
- No structured logging currently
- Debug mode for request/response logging?

### 6. CLI Tool
- TypeScript has `tkcli` - should Python have a CLI?
- Or focus on being a library only?

### 7. Higher-Level Abstractions
- Transaction builders?
- Wallet helpers?
- Address derivation utilities?

---

## Summary

The Turnkey Python SDK is a well-structured, type-safe SDK that follows Python best practices:

**Strengths:**
- Excellent type coverage with Pydantic
- Clean package separation
- Robust code generation from OpenAPI
- Good test coverage patterns

**Areas for Enhancement:**
- Add async support
- More comprehensive documentation
- Example applications
- Higher-level abstractions

The SDK is production-ready for synchronous use cases and provides a solid foundation for Python developers integrating with Turnkey.
