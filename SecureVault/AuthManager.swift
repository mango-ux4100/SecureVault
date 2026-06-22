import Foundation
import LocalAuthentication
import SwiftUI

/// Handles biometric + PIN authentication, lockout/brute-force protection,
/// and tracks lock state. This is the gatekeeper for the whole app.
@Observable
class AuthManager {
    var isUnlocked: Bool = false
    var authError: String?
    var lockoutEndTime: Date?          // when the current lockout expires
    var isWiped: Bool = false          // vault was wiped due to too many fails
    var lockoutSecondsRemaining: Int = 0  // live countdown value, updated every second

    private let keychainService = "com.securevault.pin"
    private let attemptsKey = "failedAttempts"
    private let lockoutKey = "lockoutEndTime"
    private var countdownTimer: Timer?

    // MARK: - Biometric Auth

    func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            authError = "Biometrics not available"
            return
        }

        let reason = "Unlock your vault"

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, evalError in
            DispatchQueue.main.async {
                if success {
                    self?.isUnlocked = true
                    self?.authError = nil
                } else {
                    self?.authError = evalError?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }

    // MARK: - PIN Auth (with lockout protection)

    func authenticateWithPIN(_ enteredPIN: String) -> Bool {
        if isLockedOut() {
            // authError is kept up to date by the countdown timer already,
            // but set it here too in case this is the very first check.
            updateCountdownMessage()
            return false
        }

        guard let storedPIN = KeychainHelper.shared.read(service: keychainService, account: "userPIN") else {
            authError = "No PIN configured"
            return false
        }

        if enteredPIN == storedPIN {
            resetFailedAttempts()
            isUnlocked = true
            authError = nil
            return true
        } else {
            recordFailedAttempt()
            let attemptsLeft = max(0, 8 - getFailedAttempts())
            if !isWiped {
                if isLockedOut() {
                    // recordFailedAttempt() just triggered a new lockout —
                    // start the live countdown immediately.
                    updateCountdownMessage()
                } else {
                    authError = "Incorrect PIN. \(attemptsLeft) attempts before wipe."
                }
            }
            return false
        }
    }

    func setPIN(_ pin: String) {
        let data = Data(pin.utf8)
        KeychainHelper.shared.save(data, service: keychainService, account: "userPIN")
    }

    func hasPINConfigured() -> Bool {
        KeychainHelper.shared.read(service: keychainService, account: "userPIN") != nil
    }

    func lock() {
        isUnlocked = false
    }

    // MARK: - Brute-force protection

    private func getFailedAttempts() -> Int {
        guard let stored = KeychainHelper.shared.read(service: keychainService, account: attemptsKey),
              let count = Int(stored) else {
            return 0
        }
        return count
    }

    private func setFailedAttempts(_ count: Int) {
        KeychainHelper.shared.save(Data(String(count).utf8), service: keychainService, account: attemptsKey)
    }

    /// Checks if we're currently in a lockout window. If so, starts (or
    /// keeps running) the live countdown timer so the UI ticks down
    /// second-by-second instead of showing a static message.
    func isLockedOut() -> Bool {
        guard let stored = KeychainHelper.shared.read(service: keychainService, account: lockoutKey),
              let interval = Double(stored) else {
            stopCountdownTimer()
            return false
        }
        let endTime = Date(timeIntervalSince1970: interval)
        if Date() < endTime {
            lockoutEndTime = endTime
            startCountdownTimer()
            return true
        }
        // Lockout has expired naturally — clean up.
        stopCountdownTimer()
        return false
    }

    /// Starts a 1-second repeating timer that updates `lockoutSecondsRemaining`
    /// and `authError` live, and stops itself automatically once time is up.
    private func startCountdownTimer() {
        guard countdownTimer == nil else { return } // already running
        updateCountdownMessage() // set initial value immediately, don't wait 1s

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let endTime = self.lockoutEndTime else {
                self.stopCountdownTimer()
                return
            }
            if Date() >= endTime {
                self.stopCountdownTimer()
                self.authError = nil
                self.lockoutSecondsRemaining = 0
            } else {
                self.updateCountdownMessage()
            }
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateCountdownMessage() {
        guard let endTime = lockoutEndTime else { return }
        let remaining = max(0, Int(endTime.timeIntervalSinceNow))
        lockoutSecondsRemaining = remaining
        authError = "Locked out. Try again in \(formattedTime(remaining))"
    }

    /// Formats seconds as "Xm Ys" for longer lockouts, or just "Xs" for short ones.
    private func formattedTime(_ totalSeconds: Int) -> String {
        if totalSeconds >= 60 {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes)m \(seconds)s"
        }
        return "\(totalSeconds)s"
    }

    private func lockoutDuration(forAttempt count: Int) -> TimeInterval? {
        switch count {
        case 3: return 30
        case 4: return 60
        case 5: return 300
        case 6: return 900
        case 7: return 3600
        default: return nil
        }
    }

    private func recordFailedAttempt() {
        let newCount = getFailedAttempts() + 1
        setFailedAttempts(newCount)

        if newCount >= 8 {
            wipeVault()
            return
        }

        if let duration = lockoutDuration(forAttempt: newCount) {
            let endTime = Date().addingTimeInterval(duration)
            KeychainHelper.shared.save(
                Data(String(endTime.timeIntervalSince1970).utf8),
                service: keychainService,
                account: lockoutKey
            )
            lockoutEndTime = endTime
        }
    }

    private func resetFailedAttempts() {
        setFailedAttempts(0)
        KeychainHelper.shared.delete(service: keychainService, account: lockoutKey)
        lockoutEndTime = nil
        stopCountdownTimer()
    }

    private func wipeVault() {
        KeychainHelper.shared.delete(service: keychainService, account: "userPIN")
        KeychainHelper.shared.delete(service: "com.securevault.salt", account: "salt")
        KeychainHelper.shared.delete(service: "com.securevault.masterkey", account: "masterKey")
        setFailedAttempts(0)
        KeychainHelper.shared.delete(service: keychainService, account: lockoutKey)
        stopCountdownTimer()
        isWiped = true
        authError = "Too many failed attempts. Vault wiped for security."
    }
}
