import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Copies a sensitive string to the system clipboard, then clears it
/// automatically after a delay — but only if the clipboard still holds
/// exactly what we put there. This avoids wiping something the user
/// copied afterward, which is the key correctness detail real password
/// managers handle.
///
/// iOS detail: a backgrounded app has very limited time to perform work,
/// and writing to UIPasteboard from a background timer can silently fail
/// once the app is suspended. We request explicit background task time
/// so the clear is guaranteed to actually execute.
enum ClipboardManager {
    #if canImport(UIKit)
    private static var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    static func copyWithAutoClear(_ value: String, after seconds: TimeInterval = 10) {
        setClipboard(value)

        #if canImport(UIKit)
        // Ask iOS for extra time to finish work even if the app backgrounds
        // in the meantime. Without this, the clear can silently fail once
        // the app is suspended.
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ClipboardClear") {
            // Expiration handler — iOS is about to suspend us regardless.
            // Clear immediately as a last resort, then end the task.
            setClipboard("")
            endBackgroundTask()
        }
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if currentClipboard() == value {
                setClipboard("")
            }
            #if canImport(UIKit)
            endBackgroundTask()
            #endif
        }
    }

    #if canImport(UIKit)
    private static func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
    #endif

    private static func setClipboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #endif
    }

    private static func currentClipboard() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}
