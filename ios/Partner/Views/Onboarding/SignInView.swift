import SwiftUI
import AuthenticationServices

/// First screen: Swipe-n-Go is for UC Davis students, so you sign in with your
/// @ucdavis.edu Google account before anything else (see Auth.swift).
struct SignInView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var working = false
    @State private var serverCheck = ServerCheck.checking
    @State private var serverDraft = ""
    @State private var editingServer = false
    @State private var devEmail = ""
    @State private var devName = ""

    /// What the server at `store.serverURL` said about dev sign-in.
    private enum ServerCheck: Equatable { case noServer, checking, unreachable, devOff, ready }

    private var devAvailable: Bool { serverCheck == .ready }

    var body: some View {
        ZStack {
            Brand.gradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 60)
                    header
                    if Auth.googleClientID != nil {
                        googleButton
                    } else {
                        notice("Google sign-in isn't set up in this build yet. Add the iOS client ID as GoogleClientID in Partner/Info.plist.")
                    }
                    if let message = store.auth.message {
                        notice(message)
                    }
                    if devAvailable { devSignIn }
                    serverSection
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task(id: store.serverURLString) { await watchServer() }
    }

    /// Asks the server every few seconds until dev sign-in is available, so the screen updates by
    /// itself once the server starts, or once iOS's "local network" prompt is answered (the first
    /// request on an iPhone fails while that prompt is up).
    private func watchServer() async {
        serverCheck = store.serverURL == nil ? .noServer : .checking
        while !Task.isCancelled, let url = store.serverURL {
            do {
                serverCheck = try await EventServer.authConfig(baseURL: url).devSignIn ? .ready : .devOff
            } catch {
                serverCheck = .unreachable
            }
            if serverCheck == .ready { return }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// Where the app finds the server. On an iPhone the address starts empty, and dev sign-in only
    /// appears once a server with DEV_SIGN_IN=on answers, so it has to be settable before signing in.
    private var serverSection: some View {
        VStack(spacing: 10) {
            if editingServer || serverCheck == .noServer {
                Text("Server address")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("http://192.168.1.20:8080", text: $serverDraft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(saveServer)
                    .padding(12)
                    .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("serverAddress")
                Text("Your Mac's Wi‑Fi address and port, with the server started with DEV_SIGN_IN=on. Keep this iPhone on the same Wi‑Fi.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: saveServer) {
                    Text("Connect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .disabled(serverDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if serverCheck != .ready { ProgressView().tint(.white).controlSize(.small) }
                    Text(serverStatusText)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Change server") {
                    serverDraft = store.serverURLString
                    editingServer = true
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
    }

    private var serverStatusText: String {
        let address = store.serverURLString
        return switch serverCheck {
        case .noServer, .checking: "Connecting to \(address)…"
        case .unreachable: "Can't reach \(address). Is the server running with --host 0.0.0.0 and this iPhone on the same Wi‑Fi? If iOS asks about your local network, tap Allow. Still trying…"
        case .devOff: "\(address) is running, but dev sign-in is off. Restart it with DEV_SIGN_IN=on."
        case .ready: "Server: \(address)"
        }
    }

    private func saveServer() {
        store.serverURLString = serverDraft.trimmingCharacters(in: .whitespaces)
        editingServer = false
        if store.serverURL == nil { serverCheck = .noServer }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white)
            Text("Swipe-n-Go")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("For UC Davis students.\nSign in with your @ucdavis.edu Google account.")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var googleButton: some View {
        Button {
            working = true
            Task {
                await store.auth.signInWithGoogle(using: webAuthenticationSession)
                if store.auth.isSignedIn { await store.confirmSignIn() }
                working = false
            }
        } label: {
            HStack(spacing: 10) {
                if working { ProgressView().tint(Brand.accent) } else { Image(systemName: "person.crop.circle.badge.checkmark") }
                Text("Sign in with UC Davis Google")
            }
            .font(.headline)
            .foregroundStyle(Brand.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.white, in: Capsule())
        }
        .disabled(working)
        .accessibilityIdentifier("googleSignIn")
    }

    private var devSignIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dev sign-in (local server only)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            TextField("you@ucdavis.edu", text: $devEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("devEmail")
            Text("Display name (no password needed). People see this on your events.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            TextField("Display name, e.g. Anant K", text: $devName)
                .textContentType(.name)
                .accessibilityLabel("Display name")
                .padding(12)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
            Button {
                store.auth.signInForDevelopment(email: devEmail, name: devName)
                if store.auth.isSignedIn { Task { await store.confirmSignIn() } }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(devEmail.isEmpty)
            .accessibilityIdentifier("devContinue")
        }
        .padding(16)
        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
    }
}
