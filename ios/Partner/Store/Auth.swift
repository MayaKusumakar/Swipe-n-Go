import SwiftUI
import AuthenticationServices
import CryptoKit
import Observation
import Security

/// Sign-in with a UC Davis Google account. Only verified @ucdavis.edu accounts
/// get in; the server checks that again on every request (see docs/API.md → Sign-in).
///
/// Uses Google's standard OAuth flow for iOS apps (authorization code + PKCE) in
/// the system sign-in sheet, so there's no SDK to add and nothing to pay for.
/// The refresh token is kept in the Keychain; the short-lived Google ID token is
/// sent to the server as `Authorization: Bearer …` and refreshed before it expires.
///
/// Dev sign-in: when the local server runs with DEV_SIGN_IN=on, you can type a
/// @ucdavis.edu address instead, so the app works before the Google client ID exists.
@MainActor
@Observable
final class Auth {
    enum Mode: String, Codable { case google, dev }

    struct Account: Codable, Equatable {
        var id: String
        var email: String
        var name: String
        var mode: Mode
    }

    private(set) var account: Account?
    var isSignedIn: Bool { account != nil }
    /// Shown on the sign-in screen after a failed or refused sign-in.
    var message: String?

    @ObservationIgnored private var idToken: String?
    @ObservationIgnored private var idTokenExpiry = Date.distantPast
    @ObservationIgnored private var refreshing: Task<String, Error>?

    /// The iOS OAuth client ID from Google Cloud Console (Info.plist → GoogleClientID).
    /// Empty until the team creates one; Google sign-in is hidden until then.
    static let googleClientID: String? = {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? nil : value
    }()

    nonisolated static func isUCDavis(_ email: String) -> Bool {
        let parts = email.lowercased().split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1] == "ucdavis.edu"
    }

    init() {
        guard let data = Keychain.load(Keys.account),
              let saved = try? JSONDecoder().decode(Account.self, from: data) else { return }
        account = saved
    }

    // MARK: Token for requests

    /// The token for the Authorization header, or nil when signed out.
    /// Refreshes Google's ID token when it's about to expire (they last an hour).
    func bearerToken() async throws -> String? {
        guard let account else { return nil }
        switch account.mode {
        case .dev:
            return Keychain.load(Keys.devToken).flatMap { String(data: $0, encoding: .utf8) }
        case .google:
            if let idToken, idTokenExpiry.timeIntervalSinceNow > 60 { return idToken }
            if let refreshing { return try await refreshing.value }
            let task = Task { try await self.refreshGoogleToken() }
            refreshing = task
            defer { refreshing = nil }
            return try await task.value
        }
    }

    private func refreshGoogleToken() async throws -> String {
        guard let clientID = Self.googleClientID,
              let refreshToken = Keychain.load(Keys.refreshToken).flatMap({ String(data: $0, encoding: .utf8) }) else {
            signOut(message: "Please sign in again.")
            throw GoogleOAuth.Failure("Please sign in again.")
        }
        do {
            let tokens = try await GoogleOAuth.refresh(refreshToken: refreshToken, clientID: clientID)
            try use(tokens)
            return tokens.idToken
        } catch let failure as GoogleOAuth.Failure where failure.signInAgain {
            signOut(message: "Your sign-in expired. Please sign in again.")
            throw failure
        }
    }

    // MARK: Signing in and out

    func signInWithGoogle(using session: WebAuthenticationSession) async {
        guard let clientID = Self.googleClientID else {
            message = "Google sign-in isn't set up in this build yet."
            return
        }
        message = nil
        let verifier = GoogleOAuth.makeVerifier()
        let state = UUID().uuidString
        do {
            let url = GoogleOAuth.authorizationURL(clientID: clientID, challenge: GoogleOAuth.challenge(for: verifier),
                                                   state: state)
            let callback = try await session.authenticate(
                using: url, callback: .customScheme(GoogleOAuth.redirectScheme(clientID: clientID)),
                preferredBrowserSession: .ephemeral, additionalHeaderFields: [:])
            let code = try GoogleOAuth.code(from: callback, expectedState: state)
            let tokens = try await GoogleOAuth.exchange(code: code, verifier: verifier, clientID: clientID)
            let claims = try GoogleOAuth.Claims(idToken: tokens.idToken)
            guard claims.isUCDavis else {
                message = "Swipe-n-Go is for UC Davis students. Sign in with your @ucdavis.edu account."
                return
            }
            if let refreshToken = tokens.refreshToken { Keychain.save(Data(refreshToken.utf8), for: Keys.refreshToken) }
            try use(tokens)
            finishSignIn(Account(id: claims.sub, email: claims.email, name: claims.name ?? claims.email, mode: .google))
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            message = error.localizedDescription
        }
    }

    func signInForDevelopment(email: String, name: String) {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        let name = name.trimmingCharacters(in: .whitespaces)
        guard Self.isUCDavis(email) else {
            message = "Use a @ucdavis.edu address."
            return
        }
        let display = name.isEmpty ? String(email.prefix { $0 != "@" }) : name
        Keychain.save(Data("dev:\(email):\(display)".utf8), for: Keys.devToken)
        finishSignIn(Account(id: "dev-" + email, email: email, name: display, mode: .dev))
    }

    func signOut(message: String? = nil) {
        account = nil
        idToken = nil
        idTokenExpiry = .distantPast
        self.message = message
        for key in [Keys.account, Keys.refreshToken, Keys.devToken] { Keychain.delete(key) }
    }

    private func use(_ tokens: GoogleOAuth.Tokens) throws {
        let claims = try GoogleOAuth.Claims(idToken: tokens.idToken)
        idToken = tokens.idToken
        idTokenExpiry = claims.expiry
    }

    private func finishSignIn(_ account: Account) {
        self.account = account
        message = nil
        if let data = try? JSONEncoder().encode(account) { Keychain.save(data, for: Keys.account) }
    }

    private enum Keys {
        static let account = "account"
        static let refreshToken = "google-refresh-token"
        static let devToken = "dev-token"
    }
}

// MARK: - Google OAuth for iOS apps (authorization code + PKCE, no client secret)

enum GoogleOAuth {
    struct Failure: LocalizedError {
        var message: String
        /// The refresh token was revoked or expired: the user has to sign in again.
        var signInAgain = false
        init(_ message: String, signInAgain: Bool = false) { self.message = message; self.signInAgain = signInAgain }
        var errorDescription: String? { message }
    }

    struct Tokens: Decodable {
        var idToken: String
        var refreshToken: String?
    }

    /// The parts of Google's ID token the app uses. The server verifies the signature;
    /// the app only reads it to show who's signed in and when to refresh.
    struct Claims {
        var sub: String
        var email: String
        var emailVerified: Bool
        var hostedDomain: String?
        var name: String?
        var expiry: Date

        var isUCDavis: Bool { emailVerified && hostedDomain == "ucdavis.edu" && Auth.isUCDavis(email) }

        init(idToken: String) throws {
            let parts = idToken.split(separator: ".")
            guard parts.count == 3, let data = Data(base64URL: String(parts[1])),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sub = json["sub"] as? String, let exp = json["exp"] as? Double else {
                throw Failure("Google sent an unreadable sign-in.")
            }
            self.sub = sub
            email = (json["email"] as? String ?? "").lowercased()
            emailVerified = json["email_verified"] as? Bool ?? (json["email_verified"] as? String == "true")
            hostedDomain = json["hd"] as? String
            name = json["name"] as? String
            expiry = Date(timeIntervalSince1970: exp)
        }
    }

    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    static func redirectScheme(clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static func redirectURI(clientID: String) -> String { redirectScheme(clientID: clientID) + ":/oauth2redirect" }

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    static func authorizationURL(clientID: String, challenge: String, state: String) -> URL {
        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI(clientID: clientID)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Suggests UC Davis accounts in Google's picker. The server is what enforces it.
            URLQueryItem(name: "hd", value: "ucdavis.edu"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components.url!
    }

    static func code(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw Failure(error == "access_denied" ? "Sign-in was cancelled." : "Google said: \(error)") }
        guard value("state") == expectedState, let code = value("code") else { throw Failure("Sign-in didn't complete. Try again.") }
        return code
    }

    static func exchange(code: String, verifier: String, clientID: String) async throws -> Tokens {
        try await post([
            "code": code, "client_id": clientID, "code_verifier": verifier,
            "redirect_uri": redirectURI(clientID: clientID), "grant_type": "authorization_code",
        ])
    }

    static func refresh(refreshToken: String, clientID: String) async throws -> Tokens {
        try await post(["refresh_token": refreshToken, "client_id": clientID, "grant_type": "refresh_token"])
    }

    private static func post(_ form: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw Failure("Google sign-in failed (\(error ?? "HTTP \(status)")).", signInAgain: error == "invalid_grant")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Tokens.self, from: data)
    }
}

// MARK: - Keychain (this device only)

enum Keychain {
    private static let service = "com.anantkatiyar.Partner.auth"

    static func save(_ data: Data, for key: String) {
        delete(key)
        SecItemAdd([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key,
            kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary, nil)
    }

    static func load(_ key: String) -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: key] as CFDictionary)
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        var text = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        self.init(base64Encoded: text)
    }
}
