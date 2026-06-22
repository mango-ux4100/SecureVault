import Foundation
import CryptoKit

/// Handles all encryption/decryption for vault entries.
/// Uses AES-GCM (authenticated encryption — protects against both
/// reading AND tampering, unlike plain AES-CBC which only hides data).
class CryptoManager {
    static let shared = CryptoManager()
    private init() {}

    private let saltService = "com.securevault.salt"
    private let masterKeyService = "com.securevault.masterkey"

    // MARK: - Key Derivation (PIN -> Key)

    /// Derives a symmetric key from the user's PIN using HKDF, with manual
    /// "stretching" (repeated hashing) to slow down brute-force attempts.
    /// We never use the PIN directly as a key — it's low-entropy (4-6 digits),
    /// so stretching it thousands of times makes guessing expensive.
    func deriveKey(fromPIN pin: String) -> SymmetricKey {
        let salt = getOrCreateSalt()
        var pinData = Data(pin.utf8)

        // Manual stretching: hash repeatedly with the salt mixed in.
        // This is a simplified stand-in for PBKDF2's iteration count —
        // same goal (make brute-forcing slow), simpler implementation.
        let iterations = 50_000
        for _ in 0..<iterations {
            var hasher = SHA256()
            hasher.update(data: pinData)
            hasher.update(data: salt)
            pinData = Data(hasher.finalize())
        }

        return SymmetricKey(data: pinData)
    }

    private func getOrCreateSalt() -> Data {
        if let existing = KeychainHelper.shared.read(service: saltService, account: "salt"),
           let data = Data(base64Encoded: existing) {
            return data
        }

        // First time — generate a random 16-byte salt and persist it.
        // The salt ensures two users with the same PIN get different keys.
        var saltBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        let salt = Data(saltBytes)

        KeychainHelper.shared.save(
            Data(salt.base64EncodedString().utf8),
            service: saltService,
            account: "salt"
        )
        return salt
    }

    // MARK: - Master Key (the key that actually encrypts vault entries)

    /// Gets the master key, decrypting it with the PIN-derived key.
    /// Generates a new random master key on first use.
    ///
    /// Why a separate master key instead of just using the PIN-derived key
    /// directly to encrypt entries? Because if the user changes their PIN,
    /// we only need to re-encrypt this one small master key — not every
    /// vault entry. This is exactly how real password managers work.
    func getMasterKey(pinDerivedKey: SymmetricKey) -> SymmetricKey? {
        if let storedEncrypted = KeychainHelper.shared.read(service: masterKeyService, account: "masterKey"),
           let encryptedData = Data(base64Encoded: storedEncrypted) {
            // Decrypt the stored master key using the PIN-derived key.
            guard let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
                  let decrypted = try? AES.GCM.open(sealedBox, using: pinDerivedKey) else {
                // Wrong PIN was used to derive the key — decryption fails.
                return nil
            }
            return SymmetricKey(data: decrypted)
        }

        // No master key yet — generate one, encrypt it with the PIN-derived
        // key, and store it.
        let newMasterKey = SymmetricKey(size: .bits256)
        saveMasterKey(newMasterKey, encryptedWith: pinDerivedKey)
        return newMasterKey
    }

    private func saveMasterKey(_ masterKey: SymmetricKey, encryptedWith pinDerivedKey: SymmetricKey) {
        let masterKeyData = masterKey.withUnsafeBytes { Data($0) }

        guard let sealedBox = try? AES.GCM.seal(masterKeyData, using: pinDerivedKey),
              let combined = sealedBox.combined else {
            print("Failed to encrypt master key")
            return
        }

        KeychainHelper.shared.save(
            Data(combined.base64EncodedString().utf8),
            service: masterKeyService,
            account: "masterKey"
        )
    }

    // MARK: - Encrypting/Decrypting Vault Entries

    func encrypt(_ plaintext: String, using key: SymmetricKey) -> String? {
        let data = Data(plaintext.utf8)
        guard let sealedBox = try? AES.GCM.seal(data, using: key),
              let combined = sealedBox.combined else {
            return nil
        }
        return combined.base64EncodedString()
    }

    func decrypt(_ ciphertext: String, using key: SymmetricKey) -> String? {
        guard let data = Data(base64Encoded: ciphertext),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let decrypted = try? AES.GCM.open(sealedBox, using: key) else {
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }
}
