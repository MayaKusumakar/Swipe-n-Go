import Foundation
import Testing
@testable import Partner

/// An unsigned ID token with the given claims (the app only reads them; the server checks the signature).
private func idToken(_ claims: [String: Any]) -> String {
    let header = Data(#"{"alg":"RS256","kid":"k1"}"#.utf8).base64URLEncoded
    let body = try! JSONSerialization.data(withJSONObject: claims).base64URLEncoded
    return "\(header).\(body).signature"
}

private let ucdavis: [String: Any] = [
    "sub": "1093", "email": "Maya@ucdavis.edu", "email_verified": true, "hd": "ucdavis.edu",
    "name": "Maya Lee", "exp": 1_900_000_000,
]

struct UCDavisOnlyTests {
    @Test(arguments: ["maya@ucdavis.edu", "Maya@UCDavis.edu"])
    func acceptsUCDavis(_ email: String) {
        #expect(Auth.isUCDavis(email))
    }

    @Test(arguments: ["maya@gmail.com", "@ucdavis.edu", "maya@health.ucdavis.edu", "maya@ucdavis.edu.evil.com", "ucdavis.edu"])
    func refusesEverythingElse(_ email: String) {
        #expect(!Auth.isUCDavis(email))
    }

    @Test func readsGoogleClaims() throws {
        let claims = try GoogleOAuth.Claims(idToken: idToken(ucdavis))
        #expect(claims.sub == "1093")
        #expect(claims.email == "maya@ucdavis.edu")
        #expect(claims.name == "Maya Lee")
        #expect(claims.expiry == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(claims.isUCDavis)
    }

    @Test func personalGmailOrUnverifiedIsNotUCDavis() throws {
        var gmail = ucdavis
        gmail["email"] = "maya@gmail.com"
        gmail["hd"] = nil
        #expect(try !GoogleOAuth.Claims(idToken: idToken(gmail)).isUCDavis)

        var unverified = ucdavis
        unverified["email_verified"] = false
        #expect(try !GoogleOAuth.Claims(idToken: idToken(unverified)).isUCDavis)

        var noWorkspace = ucdavis
        noWorkspace["hd"] = nil
        #expect(try !GoogleOAuth.Claims(idToken: idToken(noWorkspace)).isUCDavis)
    }

    @Test func unreadableTokenThrows() {
        #expect(throws: GoogleOAuth.Failure.self) { try GoogleOAuth.Claims(idToken: "not.a-token") }
    }
}

struct GoogleOAuthTests {
    let clientID = "123-abc.apps.googleusercontent.com"

    @Test func redirectUsesTheReversedClientID() {
        #expect(GoogleOAuth.redirectScheme(clientID: clientID) == "com.googleusercontent.apps.123-abc")
        #expect(GoogleOAuth.redirectURI(clientID: clientID) == "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    @Test func pkceChallengeIsBase64URLOfSHA256() {
        // Expected value computed independently: base64url(sha256(verifier)) without padding.
        #expect(GoogleOAuth.challenge(for: "dBjftJeZ4CVP-mJ0kFNcqrhCo8FDn6tbGKpL2J3aX5g")
                == "1-NfySiorWSlgbfQc1AtSIRqykNd_tBL7o_a5vKF39Y")
        #expect(GoogleOAuth.makeVerifier() != GoogleOAuth.makeVerifier())
    }

    @Test func authorizationURLAsksForUCDavisAndPKCE() throws {
        let url = GoogleOAuth.authorizationURL(clientID: clientID, challenge: "c", state: "s")
        let items = Dictionary(uniqueKeysWithValues: try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            .map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "accounts.google.com")
        #expect(items["hd"] == "ucdavis.edu")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["response_type"] == "code")
        #expect(items["scope"] == "openid email profile")
    }

    @Test func callbackNeedsTheSameState() throws {
        let ok = URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?state=s&code=xyz")!
        #expect(try GoogleOAuth.code(from: ok, expectedState: "s") == "xyz")
        #expect(throws: GoogleOAuth.Failure.self) { try GoogleOAuth.code(from: ok, expectedState: "other") }
        let denied = URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?error=access_denied&state=s")!
        #expect(throws: GoogleOAuth.Failure.self) { try GoogleOAuth.code(from: denied, expectedState: "s") }
    }
}
