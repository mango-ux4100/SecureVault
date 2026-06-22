import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Watches for screen recording / mirroring and exposes a live flag so
/// any view can react (e.g. blank out sensitive content). iOS-only —
/// macOS has no equivalent API, so this is always `false` there.
@Observable
class ScreenSecurityManager {
    static let shared = ScreenSecurityManager()

    var isBeingRecorded: Bool = false

    private init() {
        #if canImport(UIKit)
        isBeingRecorded = Self.currentCaptureState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(captureStateChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        #endif
    }

    #if canImport(UIKit)
    /// Reads capture state from the active window scene's screen rather
    /// than the deprecated `UIScreen.main` singleton (deprecated iOS 26).
    private static func currentCaptureState() -> Bool {
        let scenes = UIApplication.shared.connectedScenes
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? scenes.first as? UIWindowScene else {
            return false
        }
        return windowScene.screen.isCaptured
    }

    @objc private func captureStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.isBeingRecorded = Self.currentCaptureState()
        }
    }
    #endif
}
