import SwiftUI

struct ContentView: View {
    @State private var auth = AuthManager()
    @State private var vault = VaultStore()
    @State private var pinInput: String = ""
    @State private var showPINEntry = false
    @State private var showPrivacyOverlay = false
    @State private var showJailbreakWarning = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if auth.isUnlocked {
                    VaultHomeView(auth: auth, vault: vault)
                } else {
                    lockScreen
                }
            }

            // Shown the instant the app backgrounds, so the App Switcher
            // snapshot captures this instead of decrypted vault content.
            if showPrivacyOverlay {
                PrivacyOverlay()
                    .transition(.opacity)
            }
        }
        .onAppear {
            if auth.hasPINConfigured() {
                showPINEntry = true
            }
        }
        .onChange(of: auth.isUnlocked) { _, isUnlocked in
            // Check once per unlock, not on every view refresh.
            if isUnlocked && JailbreakDetector.isCompromised() {
                showJailbreakWarning = true
            }
        }
        .alert("Security Warning", isPresented: $showJailbreakWarning) {
            Button("I Understand, Continue", role: .destructive) {}
        } message: {
            Text("This device shows signs of being jailbroken. Jailbreaking removes iOS's built-in security protections, which may put your vault data at risk. Proceed only if you understand and accept this risk.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .inactive:
                // Fires right before backgrounding — exactly when iOS
                // captures the App Switcher snapshot.
                showPrivacyOverlay = true
            case .background:
                auth.lock()
                vault.lock()
            case .active:
                showPrivacyOverlay = false
            @unknown default:
                break
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("SecureVault")
                .font(.title.bold())

            if !auth.hasPINConfigured() {
                PINSetupView(auth: auth, vault: vault)
            } else {
                PINEntryView(auth: auth, vault: vault, pinInput: $pinInput)

                Button("Unlock with Face ID") {
                    auth.authenticateWithBiometrics()
                    // Note: Face ID alone can't derive the encryption key —
                    // it only proves identity, not the PIN. Real apps solve
                    // this by storing the master key in Keychain WITH a
                    // biometric access control flag instead of PIN-derived
                    // encryption. Addressed properly in a later layer.
                }
                .font(.footnote)
            }

            if let error = auth.authError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
        .padding()
    }
}

struct PINSetupView: View {
    var auth: AuthManager
    var vault: VaultStore
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Set up a PIN").font(.headline)
            SecureField("Enter 4-6 digit PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Button("Save PIN") {
                guard pin.count >= 4 else { return }
                auth.setPIN(pin)
                _ = vault.unlock(withPIN: pin)
                auth.isUnlocked = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(pin.count < 4)
        }
    }
}

struct PINEntryView: View {
    var auth: AuthManager
    var vault: VaultStore
    @Binding var pinInput: String

    var body: some View {
        VStack(spacing: 12) {
            SecureField("Enter PIN", text: $pinInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .disabled(auth.isLockedOut())

            Button("Unlock") {
                let pinCorrect = auth.authenticateWithPIN(pinInput)
                if pinCorrect {
                    let vaultUnlocked = vault.unlock(withPIN: pinInput)
                    if !vaultUnlocked {
                        auth.authError = "Vault decryption failed"
                        auth.isUnlocked = false
                    }
                }
                pinInput = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(auth.isLockedOut())
        }
    }
}

struct VaultHomeView: View {
    var auth: AuthManager
    var vault: VaultStore

    @State private var showAddSheet = false
    @State private var screenSecurity = ScreenSecurityManager.shared

    var body: some View {
        ZStack {
            NavigationStack {
                List {
                    ForEach(vault.entries) { entry in
                        VaultEntryRow(entry: entry, vault: vault)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            vault.deleteEntry(vault.entries[index])
                        }
                    }
                }
                .navigationTitle("Vault")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await vault.performSync()
                            }
                        } label: {
                            if vault.syncManager.isSyncing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(vault.syncManager.isSyncing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Lock") {
                            auth.lock()
                            vault.lock()
                        }
                    }
                    #if DEBUG
                    ToolbarItem(placement: .bottomBar) {
                        Button("🧪 Simulate Remote Entry (DEBUG)") {
                            Task {
                                await vault.debugSimulateRemoteEntry()
                            }
                        }
                        .font(.caption)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("🧪 Simulate Conflict (DEBUG)") {
                            Task {
                                await vault.debugSimulateConflictingEdit()
                            }
                        }
                        .font(.caption)
                    }
                    #endif
                }
                .sheet(isPresented: $showAddSheet) {
                    AddEntryView(vault: vault)
                }
            }

            // Live blank-out while screen recording/mirroring is detected.
            // This catches active recording, separate from the App Switcher
            // snapshot case which PrivacyOverlay already handles.
            if screenSecurity.isBeingRecorded {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white)
                            Text("Vault hidden during screen recording")
                                .foregroundStyle(.white)
                                .font(.subheadline)
                        }
                    }
            }
        }
    }
}

struct VaultEntryRow: View {
    var entry: VaultEntry
    var vault: VaultStore
    @State private var revealed = false
    @State private var justCopied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.headline)
                if revealed {
                    Text(vault.decryptedValue(for: entry))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("••••••••")
                        .foregroundStyle(.secondary)
                }
            }
            .onTapGesture {
                revealed.toggle()
            }

            Spacer()

            Button {
                let value = vault.decryptedValue(for: entry)
                ClipboardManager.copyWithAutoClear(value, after: 10)
                justCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    justCopied = false
                }
            } label: {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(justCopied ? .green : .blue)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct AddEntryView: View {
    var vault: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var secretValue = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title (e.g. Gmail)", text: $title)
                SecureField("Secret value", text: $secretValue)
            }
            .navigationTitle("New Entry")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vault.addEntry(title: title, secretValue: secretValue)
                        dismiss()
                    }
                    .disabled(title.isEmpty || secretValue.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
