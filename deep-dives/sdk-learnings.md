# Turnkey TypeScript SDK - Technical Analysis

> **Repository**: `tkhq/sdk`  
> **Analysis Date**: 2026-02-25  
> **Primary Languages**: TypeScript, React

---

## SDK Overview

The Turnkey SDK is a comprehensive TypeScript toolkit for building applications with **embedded crypto wallets** powered by Turnkey's secure key management infrastructure. It enables developers to:

- Create and manage crypto wallets without handling private keys directly
- Support multiple authentication methods (passkeys, email OTP, OAuth, external wallets)
- Sign transactions across multiple blockchains (Ethereum, Solana, Cosmos, Bitcoin, etc.)
- Build both server-side and client-side wallet experiences
- Integrate with popular Web3 libraries (Viem, Ethers, CosmJS, Solana Web3.js)

The SDK is built around the concept of **stampers** - pluggable authentication modules that sign API requests to Turnkey's secure backend.

---

## Package Structure

### Monorepo Layout

The SDK uses **pnpm workspaces** with the following structure:

```
sdk/
├── packages/           # NPM packages
│   ├── core/           # Foundation package (browser SDK base)
│   ├── sdk-server/     # Server-side SDK
│   ├── sdk-browser/    # Browser-specific SDK (deprecated, use core)
│   ├── react-wallet-kit/     # React components & hooks
│   ├── react-native-wallet-kit/  # React Native support
│   ├── http/           # Low-level HTTP client
│   ├── viem/           # Viem signer integration
│   ├── ethers/         # Ethers signer integration
│   ├── solana/         # Solana signer
│   ├── cosmjs/         # Cosmos signer
│   ├── api-key-stamper/      # API key authentication
│   ├── webauthn-stamper/     # Passkey authentication
│   ├── wallet-stamper/       # External wallet authentication
│   ├── iframe-stamper/       # Iframe-based auth (recovery/export flows)
│   ├── indexed-db-stamper/   # Browser IndexedDB key storage
│   ├── sdk-types/      # Shared TypeScript types
│   ├── crypto/         # Cryptographic utilities
│   ├── encoding/       # Encoding/decoding utilities
│   └── ...
├── examples/           # 60+ example applications
└── pnpm-workspace.yaml
```

### Package Hierarchy

```
                    ┌─────────────────────┐
                    │  react-wallet-kit   │  ← React apps use this
                    │  react-native-kit   │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │      @turnkey/core  │  ← Foundation for all clients
                    └──────────┬──────────┘
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                  │
   ┌────────▼────────┐  ┌──────▼──────┐  ┌───────▼───────┐
   │   sdk-server    │  │  sdk-browser │  │     http      │
   └────────┬────────┘  └──────┬──────┘  └───────┬───────┘
            │                  │                  │
            └──────────────────┼──────────────────┘
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                  │
   ┌────────▼────────┐  ┌──────▼──────┐  ┌───────▼───────┐
   │  api-key-stamper│  │webauthn-stmpr│  │wallet-stamper │
   └─────────────────┘  └─────────────┘  └───────────────┘
```

### Key Packages & Their Purpose

| Package | Purpose |
|---------|---------|
| `@turnkey/core` | Core client, session management, stampers, utilities. Use for Angular/Vue/Svelte. |
| `@turnkey/react-wallet-kit` | React Provider, hooks (`useTurnkey`), UI components, modal system |
| `@turnkey/sdk-server` | Server-side client with Express proxy handler, server actions |
| `@turnkey/http` | Low-level typed HTTP client, `withAsyncPolling` wrapper |
| `@turnkey/viem` | Viem `LocalAccount` adapter (`createAccount`) |
| `@turnkey/ethers` | Ethers `TurnkeySigner` class |
| `@turnkey/solana` | Solana transaction signing |
| `@turnkey/api-key-stamper` | Sign requests with API key pair |
| `@turnkey/webauthn-stamper` | Sign requests with passkeys/WebAuthn |
| `@turnkey/iframe-stamper` | Recovery, export/import flows via secure iframe |

---

## Core APIs & Classes

### TurnkeyClient (from @turnkey/core)

The main client class that all SDK interactions flow through:

```typescript
import { TurnkeyClient } from "@turnkey/core";

// Configuration options
interface TurnkeyClientConfig {
  baseUrl?: string;                    // Default: "https://api.turnkey.com"
  organizationId: string;              // Your org ID
  stamper?: TStamper;                  // Auth stamper (passkey, API key, etc.)
  defaultOrganizationId?: string;
  sessionManager?: SessionManager;
  storage?: StorageAdapter;
}

// Key methods available on TurnkeyClient
class TurnkeyClient {
  // Wallet Management
  createWallet(params): Promise<CreateWalletResult>
  getWallet(params): Promise<Wallet>
  getWallets(params): Promise<Wallet[]>
  createWalletAccounts(params): Promise<WalletAccount[]>
  
  // Signing
  signRawPayload(params): Promise<SignResult>
  signTransaction(params): Promise<SignedTransaction>
  
  // User Management
  getUser(params): Promise<User>
  createUsers(params): Promise<User[]>
  getWhoami(): Promise<WhoamiResult>
  
  // Sub-Organizations
  createSubOrganization(params): Promise<SubOrg>
  deleteSubOrganization(params): Promise<void>
  
  // Private Keys
  createPrivateKeys(params): Promise<PrivateKey[]>
  getPrivateKey(params): Promise<PrivateKey>
  exportPrivateKey(params): Promise<ExportBundle>
  importPrivateKey(params): Promise<PrivateKey>
  
  // Sessions
  createReadWriteSession(params): Promise<Session>
  createReadOnlySession(params): Promise<Session>
}
```

### Stamper Interface

All authentication methods implement the `TStamper` interface:

```typescript
interface TStamper {
  stamp(input: string): Promise<TStampedRequest>;
}

interface TStampedRequest {
  stampHeaderName: string;    // "X-Stamp-WebAuthn" or "X-Stamp-ApiKey"
  stampHeaderValue: string;   // The signature payload
}
```

### Activity Pattern

Turnkey operations are **asynchronous activities**. The SDK handles polling:

```typescript
import { withAsyncPolling, TurnkeyActivityError } from "@turnkey/http";

// Wrap mutation requests with polling
const createWallet = withAsyncPolling({
  request: client.createWallet,
});

try {
  const activity = await createWallet({
    body: { walletName: "My Wallet", accounts: [...] }
  });
  // Activity completed successfully
  console.log(activity.result.createWalletResult);
} catch (error) {
  if (error instanceof TurnkeyActivityError) {
    // Activity rejected, failed, or requires consensus
    console.log(error.activityId, error.activityStatus);
  }
}
```

---

## Authentication & Signing

### Authentication Methods

The SDK supports multiple authentication strategies:

#### 1. API Key Authentication (Server-side)

```typescript
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import { TurnkeyClient } from "@turnkey/http";

const stamper = new ApiKeyStamper({
  apiPublicKey: process.env.TURNKEY_API_PUBLIC_KEY,
  apiPrivateKey: process.env.TURNKEY_API_PRIVATE_KEY,
});

const client = new TurnkeyClient({ baseUrl: "https://api.turnkey.com" }, stamper);
```

#### 2. Passkey/WebAuthn Authentication (Browser)

```typescript
import { WebauthnStamper } from "@turnkey/webauthn-stamper";

const stamper = new WebauthnStamper({
  rpId: "example.com",  // Your domain
});

// User will be prompted for passkey
const client = new TurnkeyClient({ baseUrl: "..." }, stamper);
```

#### 3. Wallet Authentication (Sign-in with Ethereum/Solana)

```typescript
import { WalletStamper } from "@turnkey/wallet-stamper";

// Connect to user's external wallet (MetaMask, Phantom, etc.)
const stamper = new WalletStamper({
  wallet: connectedWallet,
});
```

#### 4. Iframe Authentication (Recovery/Export flows)

```typescript
import { IframeStamper } from "@turnkey/iframe-stamper";

const iframeStamper = new IframeStamper({
  iframeUrl: "https://auth.turnkey.com/iframe",
  iframeContainer: document.getElementById("turnkey-iframe"),
  iframeElementId: "turnkey-auth",
});

// Initialize and get public key
const publicKey = await iframeStamper.init();

// Inject credential bundle (from email auth, recovery, etc.)
await iframeStamper.injectCredentialBundle(bundle);
```

### Session Management

The SDK manages authentication sessions with automatic refresh:

```typescript
// Sessions have types
enum SessionType {
  READ_ONLY = "SESSION_TYPE_READ_ONLY",
  READ_WRITE = "SESSION_TYPE_READ_WRITE",
}

interface Session {
  sessionType: SessionType;
  userId: string;
  organizationId: string;
  expiry: number;
  token: string;
  publicKey?: string;
}
```

### Signing Transactions

#### Raw Payload Signing

```typescript
const { r, s, v } = await client.signRawPayload({
  signWith: walletAddress,
  payload: messageHash,
  encoding: "PAYLOAD_ENCODING_HEXADECIMAL",
  hashFunction: "HASH_FUNCTION_NO_OP",
});
```

#### Transaction Signing

```typescript
const { signedTransaction } = await client.signTransaction({
  signWith: walletAddress,
  type: "TRANSACTION_TYPE_ETHEREUM",
  unsignedTransaction: serializedTx,
});
```

---

## Integration Patterns

### Pattern 1: Direct API Integration

```typescript
// Simple server-side usage
import { Turnkey } from "@turnkey/sdk-server";

const turnkey = new Turnkey({
  apiBaseUrl: "https://api.turnkey.com",
  apiPublicKey: process.env.API_PUBLIC_KEY,
  apiPrivateKey: process.env.API_PRIVATE_KEY,
  defaultOrganizationId: process.env.ORG_ID,
});

const wallets = await turnkey.apiClient().getWallets();
```

### Pattern 2: Viem Integration

```typescript
import { createAccount } from "@turnkey/viem";
import { createWalletClient, http } from "viem";
import { sepolia } from "viem/chains";

// Create Turnkey-backed account
const account = await createAccount({
  client: turnkeyClient,
  organizationId: "...",
  signWith: privateKeyIdOrAddress,
});

// Use with standard Viem APIs
const walletClient = createWalletClient({
  account,
  chain: sepolia,
  transport: http(),
});

await walletClient.sendTransaction({
  to: "0x...",
  value: parseEther("0.01"),
});
```

### Pattern 3: Ethers Integration

```typescript
import { TurnkeySigner } from "@turnkey/ethers";
import { ethers } from "ethers";

const signer = new TurnkeySigner({
  client: turnkeyClient,
  organizationId: "...",
  signWith: "...",
});

const connectedSigner = signer.connect(provider);
await connectedSigner.sendTransaction({ to: "...", value: "..." });
```

### Pattern 4: Express Proxy Pattern

```typescript
import { Turnkey } from "@turnkey/sdk-server";
import express from "express";

const app = express();
const turnkey = new Turnkey(config);

// Proxy handler for frontend requests
app.post("/api/turnkey", turnkey.expressProxyHandler({}));
```

### Pattern 5: Sub-Organization Pattern

Each end-user gets their own Turnkey sub-organization:

```typescript
// Create sub-org for new user
const subOrg = await turnkey.apiClient().createSubOrganization({
  subOrganizationName: `user-${userId}`,
  rootUsers: [{
    userName: userEmail,
    userEmail: userEmail,
    authenticators: [passkeyAuthenticator],
  }],
  rootQuorumThreshold: 1,
  wallet: {
    walletName: "Default Wallet",
    accounts: DEFAULT_ETHEREUM_ACCOUNTS,
  },
});
```

---

## React/Next.js Integration

### TurnkeyProvider Setup

```tsx
import { TurnkeyProvider, useTurnkey } from "@turnkey/react-wallet-kit";
import "@turnkey/react-wallet-kit/styles.css";

const config = {
  apiBaseUrl: "https://api.turnkey.com",
  defaultOrganizationId: process.env.NEXT_PUBLIC_ORG_ID,
  
  // Auth methods to enable
  auth: {
    passkey: true,
    email: true,
    phone: true,
    oauth: {
      google: true,
      apple: true,
    },
    wallet: {
      ethereum: true,
      solana: true,
    },
  },
  
  // UI customization
  ui: {
    renderModalInProvider: true,
    colors: {
      light: { primary: "#4C48FF" },
      dark: { primary: "#6B68FF" },
    },
  },
};

function App() {
  return (
    <TurnkeyProvider config={config}>
      <MyApp />
    </TurnkeyProvider>
  );
}
```

### useTurnkey Hook

The main hook exposes comprehensive wallet functionality:

```tsx
function WalletComponent() {
  const {
    // State
    client,              // TurnkeyClient instance
    session,             // Current session
    user,                // Current user
    wallets,             // User's wallets
    
    // Auth Methods
    loginWithPasskey,
    signUpWithPasskey,
    loginWithOtp,
    signUpWithOtp,
    loginWithOauth,
    loginWithWallet,
    logout,
    
    // Wallet Operations
    createWallet,
    getWallets,
    exportWallet,
    importWallet,
    
    // Signing
    signMessage,
    signTransaction,
    signAndSendTransaction,
    
    // User Management
    updateUserEmail,
    addPasskey,
    removePasskey,
  } = useTurnkey();
  
  // Example: Sign a message
  const handleSign = async () => {
    const signature = await signMessage({
      message: "Hello, Turnkey!",
      signWith: wallets[0].accounts[0].address,
    });
  };
}
```

### useModal Hook

For controlling the auth/action modal:

```tsx
const { openModal, closeModal } = useModal();

// Open auth modal
openModal({ type: "auth", props: { defaultTab: "login" } });

// Open export modal
openModal({ type: "export", props: { wallet, exportType: ExportType.SEED_PHRASE } });
```

### Server Actions (Next.js)

```typescript
import { server } from "@turnkey/sdk-server";

// Server-side actions for Next.js
export async function initOtp(email: string) {
  return server.sendOtp({
    email,
    organizationId: process.env.ORG_ID,
  });
}

export async function verifyOtp(params: VerifyOtpParams) {
  return server.verifyOtp(params);
}
```

---

## Notable Code Patterns

### 1. Type-Safe API Generation

The SDK generates fully-typed API methods from OpenAPI specs:

```typescript
// Generated types in __generated__/
export type TurnkeyApiTypes = {
  v1CreateWalletRequest: { ... };
  v1CreateWalletResult: { ... };
  v1Activity: { ... };
  // ... hundreds of types
};
```

### 2. Dual Export Pattern

All packages support both ESM and CommonJS:

```json
{
  "main": "./dist/index.js",
  "module": "./dist/index.mjs",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.mjs",
      "require": "./dist/index.js"
    }
  }
}
```

### 3. Comprehensive Error Codes

Error handling is strongly typed:

```typescript
enum TurnkeyErrorCodes {
  NETWORK_ERROR = "NETWORK_ERROR",
  PASSKEY_LOGIN_AUTH_ERROR = "PASSKEY_LOGIN_AUTH_ERROR",
  WALLET_CONNECT_EXPIRED = "WALLET_CONNECT_EXPIRED",
  SESSION_EXPIRED = "SESSION_EXPIRED",
  // ... 80+ error codes
}

class TurnkeyError extends Error {
  constructor(message: string, public code?: TurnkeyErrorCodes, public cause?: unknown);
}
```

### 4. Chain-Specific Account Defaults

Pre-configured account derivation paths:

```typescript
// Ethereum
const DEFAULT_ETHEREUM_ACCOUNTS = [
  { curve: "CURVE_SECP256K1", pathFormat: "PATH_FORMAT_BIP32", path: "m/44'/60'/0'/0/0", addressFormat: "ADDRESS_FORMAT_ETHEREUM" }
];

// Solana  
const DEFAULT_SOLANA_ACCOUNTS = [
  { curve: "CURVE_ED25519", pathFormat: "PATH_FORMAT_BIP32", path: "m/44'/501'/0'/0'", addressFormat: "ADDRESS_FORMAT_SOLANA" }
];

// Bitcoin (multiple types)
const DEFAULT_BITCOIN_MAINNET_P2WPKH_ACCOUNTS = [
  { curve: "CURVE_SECP256K1", pathFormat: "PATH_FORMAT_BIP32", path: "m/84'/0'/0'/0/0", addressFormat: "ADDRESS_FORMAT_BITCOIN_MAINNET_P2WPKH" }
];
```

### 5. Transaction Type Detection

Automatic detection for different transaction formats:

```typescript
function detectTransactionType(serializedTx: string): TTransactionType {
  if (serializedTx.startsWith("76")) {
    return "TRANSACTION_TYPE_TEMPO";
  }
  return "TRANSACTION_TYPE_ETHEREUM";
}
```

### 6. Viem Error Wrapping

Turnkey errors are wrapped in Viem-compatible errors:

```typescript
export class TurnkeyConsensusNeededError extends BaseError {
  activityId: TActivityId | undefined;
  activityStatus: TActivityStatus | undefined;
}

export class TurnkeyActivityError extends BaseError {
  activityId: TActivityId | undefined;
  activityStatus: TActivityStatus | undefined;
}
```

### 7. Re-export Strategy for Type Safety

Complex re-export handling for TypeScript compatibility:

```typescript
// From react-wallet-kit/src/index.ts
// Files with only types need `export type *` (no JS output)
export type * from "@turnkey/core/dist/__types__/auth";
export type * from "@turnkey/core/dist/__types__/config";

// Enums generate JS, so use regular export
export * from "@turnkey/core/dist/__types__/enums";
```

---

## Open Questions

### Worth Investigating Further

1. **Auth Proxy vs Self-Hosted**
   - The SDK supports both Turnkey's managed Auth Proxy and self-hosted backends
   - What are the trade-offs? When to use each?

2. **Consensus/Multi-sig Flows**
   - `TurnkeyConsensusNeededError` suggests multi-party approval flows exist
   - How are these configured and what activities require consensus?

3. **Sub-organization Patterns**
   - Best practices for sub-org lifecycle management
   - When to share sub-orgs vs create new ones

4. **Session Security**
   - How are IndexedDB sessions protected?
   - What's the refresh token rotation strategy?

5. **Rate Limiting & Quotas**
   - What are Turnkey's API rate limits?
   - How does the SDK handle throttling?

6. **Offline/Airgapped Signing**
   - There's a `with-offline` example - how does this work?
   - What's the transaction preparation flow?

7. **Policy System**
   - `FetchOrCreatePolicies` suggests a policy engine
   - How do spending limits, approvals work?

8. **EIP-7702 Support**
   - The Viem package mentions TRANSACTION_TYPE_TEMPO
   - Is this related to account abstraction / EIP-7702?

9. **Telegram Integration**
   - `@turnkey/telegram-cloud-storage-stamper` exists
   - How does Telegram Cloud Storage authentication work?

10. **Gas Station Package**
    - `@turnkey/gas-station` for gasless transactions
    - How does the paymaster integration work?

---

## Example Applications (60+)

The SDK includes comprehensive examples:

| Category | Examples |
|----------|----------|
| **Auth Flows** | `email-auth`, `otp-auth`, `oauth`, `magic-link-auth`, `wallet-auth` |
| **React** | `react-wallet-kit`, `react-components` |
| **Chains** | `with-ethers`, `with-viem`, `with-solana`, `with-cosmjs`, `with-bitcoin`, `with-aptos` |
| **DeFi** | `with-uniswap`, `with-aave`, `eth-usdc-swap`, `with-0x` |
| **Account Abstraction** | `with-biconomy-aa`, `with-zerodev-aa` |
| **Import/Export** | `import-export-with-iframe-stamper`, `import-export-with-rwk` |
| **Advanced** | `rebalancer`, `trading-runner`, `sweeper`, `deployer` |

---

## Quick Start Reference

### Minimal React Setup

```tsx
// 1. Install
// pnpm add @turnkey/react-wallet-kit

// 2. Configure
import { TurnkeyProvider, useTurnkey } from "@turnkey/react-wallet-kit";
import "@turnkey/react-wallet-kit/styles.css";

const config = {
  apiBaseUrl: "https://api.turnkey.com",
  defaultOrganizationId: "your-org-id",
  auth: { passkey: true, email: true },
};

// 3. Wrap app
<TurnkeyProvider config={config}>
  <App />
</TurnkeyProvider>

// 4. Use hook
const { loginWithPasskey, signMessage, wallets } = useTurnkey();
```

### Minimal Server Setup

```typescript
// 1. Install
// pnpm add @turnkey/sdk-server

// 2. Configure
import { Turnkey } from "@turnkey/sdk-server";

const turnkey = new Turnkey({
  apiBaseUrl: "https://api.turnkey.com",
  apiPublicKey: process.env.TURNKEY_API_PUBLIC_KEY!,
  apiPrivateKey: process.env.TURNKEY_API_PRIVATE_KEY!,
  defaultOrganizationId: process.env.TURNKEY_ORG_ID!,
});

// 3. Use client
const client = turnkey.apiClient();
const wallets = await client.getWallets();
```

---

*This analysis was generated from the Turnkey SDK source code. For the most up-to-date information, refer to the [official documentation](https://docs.turnkey.com) and [GitHub repository](https://github.com/tkhq/sdk).*
