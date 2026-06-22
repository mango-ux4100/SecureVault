# SecureVault

A security-hardened credential vault for iOS and macOS, built in
SwiftUI. A portfolio project exploring how real password managers
handle authentication, encryption, attack resistance, and sync —
implemented from first principles rather than via a third-party
crypto library.

## Why this project

Most student portfolios have a to-do app or a weather app. This one
exists because mobile security engineering is a real, currently
under-supplied specialization — and because building the security
primitives yourself (rather than dropping in a library) is the only
way to actually be able to explain *why* a design decision was made,
not just that it works.

See [THREAT_MODEL.md](./THREAT_MODEL.md) for the full security
design writeup, including trade-offs and explicit limitations.

## Features

- **Authentication** — Face ID / Touch ID with PIN fallback, backed
  by Keychain (never UserDefaults)
- **Encryption** — AES-GCM via CryptoKit, with salted key derivation
  from the PIN and envelope encryption (a master key wraps each
  entry, so changing the PIN doesn't require re-encrypting
  everything)
- **Brute-force protection** — escalating lockout (30s → 1hr) with a
  live countdown, full wipe after repeated failures
- **App Switcher privacy** — a cover view replaces the live UI the
  instant the app backgrounds, so iOS's snapshot never captures
  decrypted content
- **Screen recording detection** — vault content blanks live if
  screen recording/mirroring is detected
- **Clipboard auto-clear** — copied secrets clear from the clipboard
  after 10 seconds, using a background task to guarantee the clear
  actually executes even if the app has backgrounded
- **Jailbreak detection** — warns (without blocking) if common
  jailbreak signals are present
- **Sync architecture** — a protocol-based sync layer
  (`SyncProvider`) with last-write-wins conflict resolution, built
  against a local mock backend so the logic is fully testable
  without a live cloud dependency; designed so a real CloudKit
  implementation can be swapped in without touching the sync or
  merge logic

## Tech stack

- SwiftUI (multiplatform: iOS + macOS from one codebase)
- CryptoKit (AES-GCM, key derivation)
- Keychain Services
- LocalAuthentication
- Swift Concurrency (async/await)

## Project structure

```
SecureVault/
├── AuthManager.swift          # Biometric/PIN auth, lockout logic
├── KeychainHelper.swift       # Keychain Services wrapper
├── CryptoManager.swift        # Key derivation, AES-GCM encrypt/decrypt
├── VaultEntry.swift           # Vault entry data model
├── VaultStore.swift           # Entry CRUD, persistence, sync coordination
├── PrivacyOverlay.swift       # App Switcher snapshot cover
├── ScreenSecurityManager.swift # Screen recording detection
├── ClipboardManager.swift     # Auto-clearing clipboard copy
├── JailbreakDetector.swift    # Tamper/jailbreak signal checks
├── SyncProvider.swift         # Sync transport protocol + SyncRecord
├── MockCloudProvider.swift    # Local stand-in for a real backend
├── SyncManager.swift          # Merge/conflict resolution logic
├── ContentView.swift          # All views
└── SecureVaultApp.swift       # App entry point
```

## Status

Functional on iOS Simulator and macOS, single-device tested. Sync is
built and tested against a mock backend (see THREAT_MODEL.md for
why); swapping in real CloudKit is the natural next step once a paid
Apple Developer account is available for provisioning.

## What I'd build next

See the "What I'd do differently" section in
[THREAT_MODEL.md](./THREAT_MODEL.md) for specific planned
improvements, including Argon2id key derivation and biometric-gated
Keychain access control.
