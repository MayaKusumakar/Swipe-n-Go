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
                    if Auth.googleClientID != nil {
                        googleButton
                    } else {
                        notice("Google sign-in isn't set up in this build yet. Add the iOS client ID as GoogleClientID in Partner/Info.plist.")
                    }
                    if let message = store.auth.message {
                        notice(message)
                    }
                    if devAvailable { devSignIn }
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
            TextField("Your name", text: $devName)
                .textContentType(.name)
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
