# Turnkey Kotlin SDK Learnings

> **Repository:** https://github.com/tkhq/kotlin-sdk  
> **Version analyzed:** 1.0.2  
> **Target platforms:** Android (primary), JVM  
> **License:** Apache-2.0

## SDK Overview

The Turnkey Kotlin SDK is a **comprehensive mobile wallet SDK** designed primarily for Android, with JVM compatibility for lower-level modules. It provides everything needed to build Turnkey-powered Android apps:

- **Typed HTTP access** - Generated client from OpenAPI specs
- **Authentication flows** - OAuth, Passkeys, OTP (email/SMS)
- **Session management** - Persist, select, auto-refresh, expiry timers
- **Key management** - Secure P-256 keypair storage
- **Wallet operations** - Create, import, export, sign
- **Cryptographic primitives** - HPKE encryption/decryption, enclave signature verification

### Key Differentiators from Go/Rust SDKs

| Feature | Kotlin SDK | Go SDK | Rust SDK |
|---------|------------|--------|----------|
| Target | Android/JVM | Server/CLI | Server/WASM |
| Auth flows | OAuth, Passkey, OTP helpers | API keys only | API keys + server signing |
| Session management | Built-in singleton + StateFlow | Manual | Manual |
| Passkey support | Native via Credential Manager | N/A | N/A |
| Code generation | OpenAPI → KotlinPoet | OpenAPI → Go | OpenAPI → Rust |
| UI integration | Android lifecycle-aware | N/A | N/A |

---

## Module Structure

The SDK uses a **multi-module Gradle monorepo** with clear separation of concerns:

```
kotlin-sdk/
├── packages/
│   ├── sdk-kotlin/     # High-level SDK (singleton pattern)
│   ├── http/           # Generated typed HTTP client
│   ├── types/          # Generated DTOs from OpenAPI
│   ├── crypto/         # P-256 key ops, HPKE, bundle encryption
│   ├── encoding/       # Hex, Base64url, secure random
│   ├── stamper/        # Request signing (API keys + passkeys)
│   ├── passkey/        # Android Credential Manager wrappers
│   └── tools/          # Internal codegen (not published)
├── examples/
│   └── kotlin-demo-wallet/
├── openapi/
│   ├── public_api.swagger.json
│   └── auth_proxy.swagger.json
└── build.gradle.kts    # Root build with Vanniktech Maven Publish
```

### Gradle Configuration Highlights

```kotlin
// Root build.gradle.kts
plugins {
    id("io.github.gradle-nexus.publish-plugin") version "2.0.0"
    id("com.vanniktech.maven.publish") version "0.34.0" apply false
    kotlin("jvm") version "2.2.20" apply false
    kotlin("plugin.serialization") version "2.2.20" apply false
    id("com.android.library") version "8.13.0" apply false
}

// JVM toolchain requirement
kotlin {
    jvmToolchain(24)  // Requires JDK 24
}

// Android configuration
android {
    compileSdk = 36
    minSdk = 28  // For passkey/stamper modules
}
```

### Module Dependencies

```
sdk-kotlin
    └── http
        └── types
            └── kotlinx.serialization
        └── stamper
            └── passkey
                └── androidx.credentials
            └── crypto
                └── encoding
                └── bouncy-castle
```

---

## Core Types & Classes

### High-Level SDK (`sdk-kotlin`)

#### `TurnkeyContext` (Singleton)

The central entry point, following Android's singleton pattern for app-wide state:

```kotlin
object TurnkeyContext {
    // Configuration
    fun init(app: Application, config: TurnkeyConfig)
    suspend fun initSuspend(app: Application, config: TurnkeyConfig)
    suspend fun awaitReady()
    
    // State as Kotlin Flows
    val authState: StateFlow<AuthState>      // loading | authenticated | unauthenticated
    val session: StateFlow<Session?>
    val user: StateFlow<V1User?>
    val wallets: StateFlow<List<Wallet>?>
    val selectedSessionKey: StateFlow<String?>
    
    // The HTTP client (recreated on session change)
    val client: TurnkeyClient
    
    // Auth methods
    suspend fun loginWithPasskey(activity: Activity, ...): LoginWithPasskeyResult
    suspend fun signUpWithPasskey(activity: Activity, ...): SignUpWithPasskeyResult
    suspend fun handleGoogleOAuth(activity: Activity, ...): Unit
    suspend fun handleAppleOAuth(activity: Activity, ...): Unit
    suspend fun loginOrSignUpWithOtp(otpId: String, otpCode: String, ...): LoginOrSignUpWithOtpResult
    
    // Session management
    suspend fun createSession(jwt: String, sessionKey: String?): Session
    suspend fun setSelectedSession(sessionKey: String): TurnkeyClient
    suspend fun refreshSession(expirationSeconds: String, ...): Unit
    suspend fun clearSession(sessionKey: String?): Unit
    
    // Wallet operations
    suspend fun createWallet(walletName: String, accounts: List<V1WalletAccountParams>, ...): V1CreateWalletResult
    suspend fun importWallet(walletName: String, mnemonic: String, ...): V1ImportWalletResult
    suspend fun exportWallet(walletId: String): ExportWalletResult
    
    // Signing
    suspend fun signRawPayload(signWith: String, payload: String, ...): V1SignRawPayloadResult
    suspend fun signMessage(signWith: String, message: String, ...): V1SignRawPayloadResult
}
```

#### `TurnkeyConfig`

Configuration object for initialization:

```kotlin
data class TurnkeyConfig(
    val apiBaseUrl: String = "https://api.turnkey.com",
    val authProxyBaseUrl: String = "https://authproxy.turnkey.com",
    val authProxyConfigId: String?,
    val organizationId: String,
    val appScheme: String?,  // For OAuth deep linking
    val authConfig: AuthConfig?,
    val autoRefreshManagedStates: Boolean = true,
    val autoFetchWalletKitConfig: Boolean = true,
    
    // Callbacks
    val onSessionCreated: ((Session) -> Unit)? = null,
    val onSessionSelected: ((Session) -> Unit)? = null,
    val onSessionExpired: ((Session) -> Unit)? = null,
    val onSessionRefreshed: ((Session) -> Unit)? = null,
)
```

#### Session & Auth Models

```kotlin
enum class AuthState {
    loading, authenticated, unauthenticated
}

@Serializable
data class Session(
    val userId: String,
    val organizationId: String,
    val expiry: Double,  // Unix timestamp
    val expirationSeconds: String,
    val publicKey: String,  // Compressed P-256 public key hex
    val token: String,      // JWT
    val sessionType: String
)

@Serializable
data class Wallet(
    val id: String,
    val name: String,
    val accounts: List<V1WalletAccount>
)
```

### HTTP Client (`http`)

#### `TurnkeyClient`

Generated, fully-typed HTTP client:

```kotlin
class TurnkeyClient(
    apiBaseUrl: String? = null,
    private val stamper: Stamper?,
    http: OkHttpClient? = null,
    authProxyUrl: String? = null,
    private val authProxyConfigId: String? = null,
    private val organizationId: String,
    activityPoller: ActivityPollerConfig? = null,
) {
    // Query endpoints (signed)
    suspend fun getWhoami(input: TGetWhoamiBody): TGetWhoamiResponse
    suspend fun getWallets(input: TGetWalletsBody): TGetWalletsResponse
    suspend fun getUser(input: TGetUserBody): TGetUserResponse
    
    // Activity endpoints (signed + polled)
    suspend fun createWallet(input: TCreateWalletBody): TCreateWalletResponse
    suspend fun signRawPayload(input: TSignRawPayloadBody): TSignRawPayloadResponse
    suspend fun stampLogin(input: TStampLoginBody): TStampLoginResponse
    
    // Auth proxy endpoints (unauthenticated)
    suspend fun proxyOAuthLogin(input: ProxyTOAuthLoginBody): ProxyTOAuthLoginResponse
    suspend fun proxySignup(input: ProxyTSignupBody): ProxyTSignupResponse
    suspend fun proxyInitOtp(input: ProxyTInitOtpBody): ProxyTInitOtpResponse
    
    // Pre-sign helpers (for server-side verification)
    suspend fun stampGetWallets(input: TGetWalletsBody): TSignedRequest
}
```

### Stamper (`stamper`)

#### `Stamper`

Request signing abstraction supporting both API keys and passkeys:

```kotlin
class Stamper private constructor(
    private val apiPublicKey: String?,
    private val apiPrivateKey: String?,
    private val passkeyManager: PasskeyStamper?
) {
    companion object {
        fun configure(context: Context, rpId: String? = null)
        
        // Factory methods
        fun fromPublicKey(publicKey: String): Stamper    // Load from secure storage
        fun fromPasskey(activity: Activity, rpId: String?): Stamper
        operator fun invoke(apiPublicKey: String, apiPrivateKey: String): Stamper
        
        // Key management
        fun createOnDeviceKeyPair(context: Context? = null): String  // Returns compressed pub hex
        fun deleteOnDeviceKeyPair(context: Context? = null, publicKey: String)
        fun hasOnDeviceKeyPair(context: Context? = null, publicKey: String): Boolean
        fun listOnDeviceKeyPairs(context: Context? = null): List<String>
    }
    
    // Signing
    suspend fun stamp(payload: String): Pair<String, String>  // (headerName, headerValue)
    fun sign(payload: String, format: SignatureFormat, ...): String
}
```

**Header names:**
- API key mode → `X-Stamp`
- Passkey mode → `X-Stamp-Webauthn`

### Crypto (`crypto`)

Core cryptographic operations:

```kotlin
// Key generation
fun generateP256KeyPair(): RawP256KeyPair

data class RawP256KeyPair(
    val publicKeyUncompressed: String,  // 65 bytes hex (04 || X || Y)
    val publicKeyCompressed: String,    // 33 bytes hex (02/03 || X)
    val privateKey: String              // 32 bytes hex (scalar d)
)

// Bundle encryption/decryption (HPKE)
fun decryptCredentialBundle(encryptedBundle: String, ephemeralPrivateKey: ECPrivateKey): P256KeyPair
fun decryptExportBundle(exportBundle: String, organizationId: String, embeddedPrivateKey: String, ...): String
fun encryptWalletToBundle(mnemonic: String, importBundle: String, userId: String, organizationId: String, ...): String
```

---

## Authentication & Signing

### Curve: P-256 (secp256r1) — NOT secp256k1

**Important distinction from other crypto projects:** Turnkey uses **NIST P-256** (also known as secp256r1 or prime256v1) for all signing operations, not secp256k1 (used by Bitcoin/Ethereum).

```kotlin
// crypto.kt - Key generation uses secp256r1
val kpg = KeyPairGenerator.getInstance("EC")
kpg.initialize(ECGenParameterSpec("secp256r1"))

// P256 object for Bouncy Castle operations
object P256 {
    private val x9 = NISTNamedCurves.getByName("P-256")
    val domain = ECDomainParameters(x9.curve, x9.g, x9.n, x9.h)
}
```

### Stamp Flow

1. **Payload preparation**: JSON body is serialized
2. **SHA-256 hash**: Payload is hashed with SHA-256
3. **ECDSA signature**: Hash is signed with P-256 private key
4. **Header construction**: 
   - API key: `X-Stamp: base64url(JSON{publicKey, signature, scheme})`
   - Passkey: `X-Stamp-Webauthn: base64url(webauthn assertion)`

```kotlin
// Stamper.kt - stamp() implementation
suspend fun stamp(payload: String): Pair<String, String> {
    val payloadBytes = payload.toByteArray(Charsets.UTF_8)
    val digest = MessageDigest.getInstance("SHA-256").digest(payloadBytes)
    
    return when {
        apiPublicKey != null && apiPrivateKey != null -> {
            val value = ApiKeyStamper.stamp(
                payloadSha256 = digest,
                publicKeyHex = apiPublicKey,
                privateKeyHex = apiPrivateKey
            )
            "X-Stamp" to value
        }
        passkeyManager != null -> {
            val value = PasskeyStampBuilder.stamp(
                payloadSha256 = digest,
                passkeyClient = passkeyManager
            )
            "X-Stamp-Webauthn" to value
        }
        else -> throw IllegalStateException("No credentials configured")
    }
}
```

### Key Storage

Keys are stored using Android's SharedPreferences (wrapped in `KeyPairStore`):

```kotlin
// KeyPairStore.kt - simplified
object KeyPairStore {
    private const val PREFS_NAME = "turnkey_keystore"
    
    fun save(context: Context, privateKeyHex: String, publicKeyHex: String)
    fun getPrivateHex(context: Context, publicKeyHex: String): String
    fun delete(context: Context, publicHex: String)
    fun listKeys(context: Context): List<String>
}
```

**Note:** For production, consider using Android Keystore for hardware-backed key protection.

---

## Activity Polling

Turnkey operations that modify state return an `Activity` object. The Kotlin SDK implements automatic polling for async activities:

### Polling Configuration

```kotlin
data class ActivityPollerConfig(
    val intervalMs: Long = 1000L,   // Poll every 1 second
    val numRetries: Int = 3,        // Max 3 retries
)
```

### Terminal Statuses

```kotlin
private val TERMINAL_ACTIVITY_STATUSES: Set<V1ActivityStatus> = setOf(
    V1ActivityStatus.ACTIVITY_STATUS_COMPLETED,
    V1ActivityStatus.ACTIVITY_STATUS_FAILED,
    V1ActivityStatus.ACTIVITY_STATUS_REJECTED
)
```

### Polling Implementation

```kotlin
// TurnkeyClient.kt (generated)
private suspend fun pollActivityStatus(
    activityId: String,
    intervalMs: Long,
    maxRetries: Int,
): V1Activity {
    var attempts = 0
    
    while (attempts <= maxRetries) {
        delay(intervalMs)
        
        val pollResponse = getActivity(TGetActivityBody(activityId = activityId))
        val activity = pollResponse.activity
        
        if (activity.status in TERMINAL_ACTIVITY_STATUSES) {
            return activity
        }
        
        attempts++
    }
    
    // Return last polled activity even if max retries exceeded
    return getActivity(TGetActivityBody(activityId = activityId)).activity
}

private suspend inline fun <reified TBodyType> activity(
    url: String,
    body: TBodyType,
    activityType: String,
): V1Activity {
    // ... make request ...
    
    val initialActivity = // ... parse response ...
    
    // Auto-poll if not terminal
    if (initialActivity.status !in TERMINAL_ACTIVITY_STATUSES) {
        return pollActivityStatus(
            initialActivity.id, 
            activityPoller.intervalMs, 
            activityPoller.numRetries
        )
    }
    
    return initialActivity
}
```

### Comparison with Go/Rust SDKs

| SDK | Polling Approach |
|-----|------------------|
| Kotlin | Automatic with `ActivityPollerConfig`, built into `activity()` wrapper |
| Go | Manual via `WaitForActivityResult()` with configurable poller |
| Rust | Manual polling via `poll_activity_status()` |

---

## Android Integration

### Passkey Support

The SDK wraps Android's Credential Manager for passkey operations:

```kotlin
// Passkey.kt
suspend fun createPasskey(
    activity: Activity,
    user: PasskeyUser,
    rpId: String,
    excludeCredentials: List<ByteArray>? = emptyList(),
): PasskeyRegistrationResult

class PasskeyStamper(
    private val activity: Activity,
    private val allowedCredentials: List<ByteArray>? = null,
    rpId: String
) {
    suspend fun assert(
        challenge: ByteArray,
        allowedCredentials: List<ByteArray>? = null,
    ): AssertionResult
}
```

**Requirements:**
- `minSdk 28` (Android 9.0+)
- Digital Asset Links for RP ID verification
- Dependencies:
  ```kotlin
  implementation("androidx.credentials:credentials:<latest>")
  implementation("androidx.credentials:credentials-play-services-auth:<latest>")
  ```

### OAuth Deep Linking

The SDK handles OAuth redirects via a dedicated Activity:

```xml
<!-- AndroidManifest.xml -->
<activity 
    android:name="com.turnkey.core.OAuthRedirectActivity"
    android:launchMode="singleTop"
    android:noHistory="true"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="<your-app-scheme>" />
    </intent-filter>
</activity>
```

```kotlin
// OAuthEvents.kt - SharedFlow for deep link events
object OAuthEvents {
    private val _deepLinks = MutableSharedFlow<Uri>(replay = 1)
    val deepLinks: SharedFlow<Uri> = _deepLinks.asSharedFlow()
    
    fun emit(uri: Uri) {
        _deepLinks.tryEmit(uri)
    }
}
```

### Lifecycle Integration

```kotlin
// TurnkeyContext uses ProcessLifecycleOwner
ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
    override fun onStart(owner: LifecycleOwner) {
        // Called when app enters foreground
        scope.launch(io) {
            PendingKeysStore.purge(appContext)
            SessionRegistryStore.purgeExpiredSessions(appContext)
        }
    }
})
```

### Coroutine Scopes

```kotlin
// TurnkeyContext scopes
private val io = Dispatchers.IO           // For I/O operations
private val bg = Dispatchers.Default      // For CPU-bound work
private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
private val timerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
```

---

## Integration Patterns

### Basic Initialization

```kotlin
class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        
        val createSubOrgParams = CreateSubOrgParams(
            customWallet = CustomWallet(
                walletName = "Wallet 1",
                walletAccounts = listOf(
                    V1WalletAccountParams(
                        addressFormat = V1AddressFormat.ADDRESS_FORMAT_ETHEREUM,
                        curve = V1Curve.CURVE_SECP256K1,
                        path = "m/44'/60'/0'/0/0",
                        pathFormat = V1PathFormat.PATH_FORMAT_BIP32
                    )
                )
            )
        )
        
        TurnkeyContext.init(
            app = this,
            config = TurnkeyConfig(
                apiBaseUrl = "https://api.turnkey.com",
                authProxyBaseUrl = "https://authproxy.turnkey.com",
                authProxyConfigId = "<config-id>",
                organizationId = "<org-id>",
                appScheme = "myapp",
                authConfig = AuthConfig(
                    rpId = "myapp.example.com",
                    createSubOrgParams = MethodCreateSubOrgParams(
                        emailOtpAuth = createSubOrgParams,
                        passkeyAuth = createSubOrgParams,
                        oAuth = createSubOrgParams
                    )
                )
            )
        )
    }
}
```

### OTP Authentication Flow

```kotlin
// Step 1: Initialize OTP
val initResult = TurnkeyContext.initOtp(
    otpType = OtpType.OTP_TYPE_EMAIL,
    contact = "user@example.com"
)

// Step 2: User enters code, login or sign up
val session = TurnkeyContext.loginOrSignUpWithOtp(
    otpId = initResult.otpId,
    otpCode = userEnteredCode,
    contact = "user@example.com",
    otpType = OtpType.OTP_TYPE_EMAIL
)
```

### Google OAuth Flow

```kotlin
TurnkeyContext.handleGoogleOAuth(
    activity = requireActivity(),
    // Optional: override clientId from config
    // clientId = "...",
    onSuccess = { oidcToken, publicKey, providerName ->
        // Custom handling
        Log.d("OAuth", "Got token: $oidcToken")
    }
)
```

### Passkey Authentication

```kotlin
// Login with existing passkey
val result = TurnkeyContext.loginWithPasskey(
    activity = requireActivity(),
    rpId = "myapp.example.com"
)

// Sign up with new passkey
val result = TurnkeyContext.signUpWithPasskey(
    activity = requireActivity(),
    passkeyDisplayName = "My Passkey",
    rpId = "myapp.example.com"
)
```

### Message Signing

```kotlin
lifecycleScope.launch {
    // With Ethereum prefix
    val sig = TurnkeyContext.signMessage(
        signWith = "0x1234...",
        addressFormat = V1AddressFormat.ADDRESS_FORMAT_ETHEREUM,
        message = "Hello, Turnkey!",
        addEthereumPrefix = true  // Adds "\x19Ethereum Signed Message:\n{len}"
    )
    
    Log.d("Signature", "${sig.r}${sig.s}${sig.v}")
}
```

### Using the Low-Level HTTP Client

```kotlin
// Direct HTTP client usage (for DI scenarios)
val stamper = Stamper(apiPublicKey = "...", apiPrivateKey = "...")

val client = TurnkeyClient(
    apiBaseUrl = "https://api.turnkey.com",
    stamper = stamper,
    organizationId = "org-id"
)

val whoami = client.getWhoami(TGetWhoamiBody(organizationId = "org-id"))
```

---

## Notable Kotlin Patterns

### 1. Sealed Class Error Hierarchy

```kotlin
sealed class TurnkeyKotlinError(message: String, cause: Throwable? = null) :
    Exception(
        if (cause != null) "$message - error: ${cause.message}" else message,
        cause
    ) {
    
    data class FailedToCreateSession(override val cause: Throwable? = null) :
        TurnkeyKotlinError("Failed to create session from jwt", cause)
    
    data class ClientNotInitialized(override val cause: Throwable? = null) : 
        TurnkeyKotlinError("""
            Turnkey client not ready. 
            Did you:
            1. Call TurnkeyContext.init(app, config)?
            2. Wait with TurnkeyContext.awaitReady()?
        """.trimIndent())
    
    // ... many more specific error types
}
```

This provides exhaustive error handling with `when` expressions.

### 2. StateFlow for Reactive State

```kotlin
private val _authState = MutableStateFlow(AuthState.loading)
val authState: StateFlow<AuthState> = _authState.asStateFlow()

// UI layer
lifecycleScope.launch {
    TurnkeyContext.authState.collect { state ->
        when (state) {
            AuthState.loading -> showLoading()
            AuthState.authenticated -> showDashboard()
            AuthState.unauthenticated -> showLogin()
        }
    }
}
```

### 3. CompletableDeferred for Init Synchronization

```kotlin
private val clientReady = CompletableDeferred<Unit>()

suspend fun awaitReady() {
    clientReady.await()
}

suspend fun initSuspend(app: Application, cfg: TurnkeyConfig) {
    // ... initialization ...
    clientReady.complete(Unit)
}
```

### 4. Companion Object Factories

```kotlin
class Stamper private constructor(...) {
    companion object {
        fun fromPublicKey(publicKey: String): Stamper { ... }
        fun fromPasskey(activity: Activity, rpId: String?): Stamper { ... }
        operator fun invoke(apiPublicKey: String, apiPrivateKey: String): Stamper { ... }
    }
}
```

### 5. Coroutine Extension Functions

```kotlin
// OkHttp Call to suspend function
private suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    this@await.enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
            if (!cont.isCompleted) cont.resumeWithException(e)
        }
        override fun onResponse(call: Call, response: Response) {
            if (!cont.isCompleted) cont.resume(response)
        }
    })
    cont.invokeOnCancellation { runCatching { cancel() } }
}
```

### 6. KotlinPoet for Code Generation

```kotlin
// TypesGenerator.kt - Generating data classes
val dataClass = TypeSpec.classBuilder(typeName)
    .addModifiers(KModifier.PUBLIC)
    .addModifiers(KModifier.DATA)
    .addAnnotation(Serializable::class)
    .primaryConstructor(
        FunSpec.constructorBuilder()
            .addParameters(properties.map { it.second })
            .build()
    )
    .addProperties(properties.map { 
        PropertySpec.builder(it.first, it.second.type)
            .initializer(it.first)
            .build()
    })
    .build()
```

### 7. Inline JSON Building

```kotlin
val bodyObj = kotlinx.serialization.json.buildJsonObject {
    put("parameters", params)
    put("organizationId", finalOrgId)
    put("timestampMs", JsonPrimitive(ts))
    put("type", JsonPrimitive(activityType))
}
```

---

## Open Questions

### 1. Android Keystore Integration
The current implementation uses SharedPreferences for key storage. Should hardware-backed Android Keystore be used for production deployments?

```kotlin
// Current: SharedPreferences-based
object KeyPairStore {
    private const val PREFS_NAME = "turnkey_keystore"
    // ...
}

// Potential: Android Keystore
val keyStore = KeyStore.getInstance("AndroidKeyStore")
```

### 2. Biometric Authentication for Key Access
Passkeys require biometrics via Credential Manager, but API key signing doesn't. Should biometric gating be added for high-value operations?

### 3. Multi-Wallet Account Management
The current `createSubOrgParams` pattern creates wallets at sign-up time. How should post-auth wallet creation flow work for multi-chain wallets?

### 4. Session Token Encryption at Rest
JWTs are stored as-is. Should they be encrypted with a device-bound key?

### 5. Offline Signing Capability
The SDK requires network access for all signing operations. Could a local signing mode be supported for pre-signed transactions?

### 6. Proguard/R8 Rules
What are the recommended Proguard rules for release builds? The kotlinx.serialization dependency may need keep rules.

### 7. Thread Safety of TurnkeyContext
The singleton uses `@Volatile` and `Mutex` for some operations but not all. Full thread-safety audit needed for concurrent access patterns.

### 8. Error Recovery Patterns
When `refreshSession` fails, what's the recommended recovery flow? Current code calls `clearSession` but doesn't retry.

---

## Code Generation Deep Dive

The SDK generates both types and HTTP client from OpenAPI specs using KotlinPoet:

### Input Specs
- `openapi/public_api.swagger.json` (~465KB) - Main Turnkey API
- `openapi/auth_proxy.swagger.json` (~29KB) - Auth proxy endpoints

### Generated Output
- `packages/types/src/main/kotlin/com/turnkey/types/Models.kt` - All DTOs
- `packages/http/src/main/kotlin/com/turnkey/http/TurnkeyClient.kt` - HTTP client

### Generation Commands
```bash
# Generate everything
./gradlew generate

# Generate individually
./gradlew :packages:types:regenerateModels
./gradlew :packages:http:regenerateHttpClient
```

### Generator Architecture
```kotlin
// TypesGenerator.kt
fun main(args: Array<String>) {
    val specs = listOf(
        SpecCfg(projectRoot.resolve("openapi/public_api.swagger.json"), prefix = ""),
        SpecCfg(projectRoot.resolve("openapi/auth_proxy.swagger.json"), prefix = "Proxy")
    )
    
    val fileBuilder = FileSpec.builder(pkg, "Models")
    generateDefinitionsFromComponents(swaggerSpecs, fileBuilder, pkg)
    generateApiTypes(swaggerSpecs, fileBuilder, pkg)
    fileBuilder.build().writeTo(outRoot)
}
```

---

## Summary

The Turnkey Kotlin SDK is a well-architected, production-ready mobile SDK with:

✅ **Modern Kotlin patterns** - Coroutines, Flow, sealed classes  
✅ **Type-safe API** - Generated from OpenAPI specs  
✅ **Comprehensive auth** - OAuth, Passkeys, OTP out of the box  
✅ **Android-first** - Lifecycle-aware, Credential Manager integration  
✅ **Flexible architecture** - Use high-level SDK or low-level primitives  

The layered design (sdk-kotlin → http → stamper → crypto) allows teams to choose their integration depth based on requirements.

---

*Last updated: 2026-03-02*  
*Analyzed by: Technical Research Agent*
