import SwiftUI

/// A full-screen cover shown the instant the app backgrounds, so the
/// App Switcher snapshot shows this instead of decrypted vault content.
/// Without this, iOS captures whatever was on-screen (e.g. a revealed
/// password) and displays it in the App Switcher thumbnail — a real,
/// commonly-overlooked leak in apps that handle sensitive data.
struct PrivacyOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)
                Text("SecureVault")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
