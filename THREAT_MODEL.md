# SecureVault — Threat Model

This document describes what SecureVault protects against, what it
deliberately does not protect against, and why specific security
decisions were made. It's written the way I'd want to explain this
project in a technical interview: honestly, with trade-offs stated
up front rather than discovered under questioning.

## What SecureVault is

A local-first, end-to-end encrypted credential vault for iOS and
macOS, built in SwiftUI. It stores sensitive values (passwords,
secrets) encrypted at rest, gated behind biometric/PIN
authentication, with several layers of defense against common attack
vectors on a single device, plus an architecture for syncing across
a user's own devices without the sync backend ever seeing plaintext.

## Assets being protected

- The plaintext value of each vault entry (e.g. a password)
- The master encryption key
- The user's PIN

## Threat actors considered

| Actor | Capability | In scope? |
|---|---|---|
| Someone who picks up a lost/stolen unlocked device | Full UI access, no code execution | Yes |
| Someone who picks up a locked device | No UI access without biometric/PIN | Yes |
| A malicious app on the same device | Can read shared clipboard, observe App Switcher snapshots | Yes |
| Someone screen-recording or mirroring the device | Visual access while app is open | Yes |
| Someone with a jailbroken copy of the device | Elevated OS-level access, can bypass sandboxing | Partially (detection only) |
| A nation-state actor with physical forensics lab access | Chip-off extraction, cold boot attacks, etc. | **Out of scope** |
| Apple itself / a compromised CloudKit backend | Sees only ciphertext under the current design | Yes, by design |

---

## Defense layers and the reasoning behind each

### 1. Authentication (Face ID / Touch ID + PIN fallback)

Uses Apple's `LocalAuthentication` framework for biometrics, with a
PIN as fallback. The PIN is never stored in plaintext — only used to
derive a key (see Encryption below) and, separately, checked against
a Keychain-stored copy for the unlock gate itself.

**Why Keychain and not UserDefaults:** UserDefaults is an
unencrypted plist file, trivially readable on a compromised or
jailbroken device. Keychain is encrypted at rest by the OS and tied
to the device's Secure Enclave-backed key hierarchy. This is
non-negotiable for anything sensitive.

### 2. Encryption (AES-GCM + key derivation, envelope encryption)

Vault entries are encrypted with **AES-GCM** (authenticated
encryption — protects both confidentiality and integrity, unlike
plain AES-CBC which only hides data and can be tampered with
undetected).

**Key derivation:** the user's PIN is never used directly as an
encryption key — it's low-entropy (4-6 digits), so using it directly
would make brute-forcing the encryption itself trivial. Instead, a
salted, iterated hash (HKDF-style stretching, 50,000 rounds) derives
a key from the PIN. This makes each guess computationally expensive
for an attacker who somehow obtains the ciphertext offline.

**Envelope encryption:** the PIN-derived key doesn't encrypt vault
entries directly. Instead, it encrypts a separate, randomly
generated **master key**, which in turn encrypts the actual entries.
This two-layer design means changing the PIN only requires
re-encrypting the small master key, not every vault entry — the same
pattern real password managers and cloud KMS systems use.

### 3. Brute-force protection

Failed PIN attempts trigger an escalating lockout: 30s → 1m → 5m →
15m → 1hr, with a full vault wipe after 8 consecutive failures.

**Trade-off, stated plainly:** wiping after repeated failures
protects the data at the cost of permanent data loss if it's truly
the owner who forgot their PIN. This is a deliberate choice, not an
oversight — it mirrors what some enterprise MDM tools and banking
apps do for high-sensitivity data. A softer alternative (longer
lockouts without ever wiping) is equally defensible; I chose the
stricter option because this is a security-focused portfolio project
demonstrating the harder trade-off.

### 4. Screen/clipboard protections

- **App Switcher blur:** a cover view is swapped in the instant the
  app backgrounds, so iOS's App Switcher snapshot never captures
  decrypted vault content.
- **Screen recording detection:** the vault blanks live if iOS
  reports the screen is being captured or mirrored.
- **Clipboard auto-clear:** copying a secret clears the clipboard
  after 10 seconds, but only if the clipboard still holds exactly
  what was copied (so it doesn't wipe something the user copied
  afterward). Uses `beginBackgroundTask` to request extra execution
  time, since a plain background timer can silently fail to write to
  the clipboard once iOS suspends the app.

**Known limitation:** iOS gives apps no API to block the system
screenshot gesture itself (unlike Android). This is a platform
constraint, not a gap in this app's design — even commercial
password managers can't fully prevent screenshots on iOS.

### 5. Jailbreak/tamper detection

Checks for known jailbreak file paths, a sandbox-escape write test,
and an attached-debugger check (`P_TRACED` flag via `sysctl`). If
any signal fires, the user sees a warning and can choose to proceed.

**Honest limitation:** this is inherently a cat-and-mouse game.
Sophisticated jailbreaks can hide from basic detection, and no
client-side check is bulletproof against a determined attacker who
can patch the binary. The value is raising the bar against casual
tampering, not stopping a nation-state adversary — this is the same
trade-off real banking and password-manager apps accept.

**Why "warn, don't block":** full blocking is arguably user-hostile
(some legitimate users jailbreak their own devices and still want a
password manager); silently ignoring defeats the point of detecting
it at all. Warning and letting the user decide mirrors what apps
like 1Password actually do.

### 6. Sync architecture

Sync is built behind a `SyncProvider` protocol, so the conflict
resolution logic is fully testable without depending on a live
backend. The current implementation (`MockCloudProvider`) is a local
stand-in; a real `CloudKitProvider` conforming to the same protocol
is the natural next step, requiring no changes to `SyncManager` or
`VaultStore`.

**Conflict resolution:** last-write-wins, decided per-record by
comparing `dateModified`. This is the same strategy CloudKit's own
default conflict handling uses. I considered CRDTs for
conflict-free merging, but last-write-wins is simpler to reason
about and appropriate here — this is single-user data synced across
one person's own devices, not concurrent multi-user collaboration,
so the cases where last-write-wins loses information are rare and
low-stakes (overwriting your own slightly-older edit from another
device).

**What "end-to-end encrypted" means here, precisely:** entries are
encrypted locally before ever being handed to the sync layer. The
sync backend — mock today, CloudKit in the future — only ever
receives and stores ciphertext. It cannot decrypt vault contents
even in principle, since it never has access to the master key or
PIN.

---

## Explicitly out of scope

- **Physical forensic extraction** (chip-off, JTAG, cold boot
  attacks against device RAM). Defending against this requires
  hardware-level protections beyond what an app can control.
- **Compromise of the device's OS itself** (e.g. a malicious actor
  with root access reading process memory directly). Jailbreak
  detection raises the bar but cannot fully prevent this.
- **Side-channel attacks** (timing attacks, power analysis). Not
  addressed; would require constant-time cryptographic operations
  throughout, which this project's CryptoKit usage doesn't
  specifically guarantee beyond what Apple's framework provides by
  default.
- **Supply chain attacks** (a compromised dependency). This project
  has no third-party dependencies for its cryptography, deliberately
  — everything routes through Apple's own CryptoKit and Keychain
  Services rather than a third-party crypto library, reducing
  supply-chain surface area.

## What I'd do differently with more time

- Replace the manual HKDF-style PIN stretching with Argon2id via a
  vetted library, which is more resistant to GPU-based brute-force
  than a simple iterated SHA-256 construction.
- Add a biometric-gated Keychain access control flag
  (`kSecAttrAccessControl` with `.biometryCurrentSet`) so Face ID can
  directly gate master key access, rather than the current design
  where Face ID only proves identity while the PIN does the actual
  key derivation.
- Replace last-write-wins with field-level merging or a CRDT-based
  approach if this ever needed genuine multi-user collaboration
  rather than single-user multi-device sync.
