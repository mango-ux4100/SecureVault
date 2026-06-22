//
//  JailbreakDetector.swift
//  SecureVault
//
//  Created by Amlan Behera on 20/06/26.
//


import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Checks for common signs a device may be jailbroken (rooted), so the
/// app can warn the user before they store sensitive data. This is NOT
/// a guarantee — sophisticated jailbreaks can hide from these checks,
/// and no client-side detection is bulletproof. The goal is raising the
/// bar against casual tampering, which is the same honest trade-off real
/// password managers and banking apps accept.
enum JailbreakDetector {
    /// Runs all checks. Returns true if ANY sign of jailbreak is found.
    static func isCompromised() -> Bool {
        #if targetEnvironment(simulator)
        // Simulator always "fails" path-based checks in confusing ways
        // and is never actually jailbroken — skip entirely.
        return false
        #else
        return hasJailbreakFiles() || canWriteOutsideSandbox() || isDebuggerAttached()
        #endif
    }

    // MARK: - Check 1: Known jailbreak tool file paths

    private static func hasJailbreakFiles() -> Bool {
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }

    // MARK: - Check 2: Sandbox escape test

    private static func canWriteOutsideSandbox() -> Bool {
        let testPath = "/private/jailbreak_test.txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true // writing outside our sandbox should NEVER succeed normally
        } catch {
            return false // expected outcome on a non-jailbroken device
        }
    }

    // MARK: - Check 3: Debugger attached

    /// Uses sysctl to check the P_TRACED flag — a debugger attached to
    /// the process is one sign of active tampering/inspection.
    private static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }

        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
