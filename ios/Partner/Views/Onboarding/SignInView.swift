import SwiftUI
import AuthenticationServices

/// First screen: Swipe-n-Go is for UC Davis students, so you sign in with your
/// @ucdavis.edu Google account before anything else (see Auth.swift).
struct SignInView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var working = false
    @State private var devAvailable = false
    @State private var devEmail = ""
    @State private var devName = ""

    var body: some View {
        ZStack {
            Brand.gradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 60)
                    header
                    if let message = store.auth.message {
                        notice(message)
                    }
                    if Auth.googleClientID != nil {
                        googleButton
                    } else if devAvailable {
                        devSignIn
                    } else {
                        // TEMPORARY (until the team server is online): with no way to sign in,
                        // guest keeps the app usable. Hidden whenever UC Davis sign-in works.
                        guestButton
                    }
                    #if DEBUG
                    Button("Continue in Demo Mode") {
                        store.enterDemoMode()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    #endif
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task { devAvailable = await store.devSignInAvailable() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white)
            Text("Swipe-n-Go")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(Auth.googleClientID == nil
                 ? "For UC Davis students.\nFind people to go to club events with."
                 : "For UC Davis students.\nSign in with your @ucdavis.edu Google account.")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// For testers (TestFlight) until sign-in and the shared server are ready.
    private var guestButton: some View {
        VStack(spacing: 8) {
            Button {
                store.continueAsGuest()
            } label: {
                Text("Continue as guest")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("continueAsGuest")
            Text("Try it with sample club events. Plans you make stay on this iPhone.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
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
        // TEMPORARY: dev sign-in on the local server, styled as the main sign-in
        // until Google sign-in and the team server are online.
        VStack(spacing: 12) {
            TextField("you@ucdavis.edu", text: $devEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.white, in: Capsule())
                .accessibilityIdentifier("devEmail")
            TextField("Your name", text: $devName)
                .textContentType(.name)
                .accessibilityLabel("Display name")
                .padding(14)
                .background(.white, in: Capsule())
            Button {
                store.auth.signInForDevelopment(email: devEmail, name: devName)
                if store.auth.isSignedIn { Task { await store.confirmSignIn() } }
            } label: {
                Text("Sign in with UC Davis")
                    .font(.headline)
                    .foregroundStyle(devEmail.isEmpty ? .white.opacity(0.6) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(Capsule().strokeBorder(.white.opacity(devEmail.isEmpty ? 0.4 : 0.9), lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(devEmail.isEmpty)
            .accessibilityIdentifier("devContinue")
        }
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
