import Foundation
import CryptoKit
import Security

/// Public-client OIDC authorization code flow. The server, not the app, verifies ID tokens.
struct TrialAuthorization {
    struct Configuration: Codable, Equatable {
        let issuer: String
        let client_id: String
        let authorization_endpoint: String
        let token_endpoint: String
        let redirect_uri: String
        let scope: String

        func validate(expectedRedirect: String) throws {
            for value in [issuer, authorization_endpoint, token_endpoint] {
                guard let url = URL(string: value), url.scheme == "https", url.host != nil,
                      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                    throw AuthError.invalidConfiguration
                }
            }
            guard redirect_uri == expectedRedirect, !client_id.isEmpty,
                  scope.split(separator: " ").contains("openid"), scope.split(separator: " ").contains("email") else {
                throw AuthError.invalidConfiguration
            }
        }
    }
    enum AuthError: LocalizedError {
        case invalidConfiguration, randomUnavailable, invalidCallback, signInFailed, unverifiedEmail, storageFailed
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: return "Trial sign-in is unavailable. Try again later."
            case .randomUnavailable: return "Couldn't start secure sign-in. Try again."
            case .invalidCallback: return "Couldn't verify the sign-in response. Try signing in again."
            case .signInFailed: return "Couldn't complete sign-in. Try again."
            case .unverifiedEmail: return "Verify your email with the sign-in provider, then sign in again."
            case .storageFailed: return "Couldn't update your sign-in in Keychain. Try again."
            }
        }
    }
    let verifier: String
    let state: String
    let nonce: String

    init() throws {
        verifier = try Self.random()
        state = try Self.random()
        nonce = try Self.random()
    }
    init(verifier: String, state: String, nonce: String) {
        self.verifier = verifier; self.state = state; self.nonce = nonce
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AuthError.randomUnavailable }
        return base64URL(Data(bytes))
    }
    var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    func authorizationURL(_ config: Configuration) throws -> URL {
        guard var parts = URLComponents(string: config.authorization_endpoint) else { throw AuthError.invalidConfiguration }
        parts.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: config.client_id),
            .init(name: "redirect_uri", value: config.redirect_uri), .init(name: "scope", value: config.scope),
            .init(name: "state", value: state), .init(name: "nonce", value: nonce),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "consent")
        ]
        guard let url = parts.url else { throw AuthError.invalidConfiguration }
        return url
    }
    func code(from callback: URL, redirect: String) throws -> String {
        guard let expected = URLComponents(string: redirect), let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.scheme == expected.scheme, parts.host == expected.host, parts.path == expected.path,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else { throw AuthError.invalidCallback }
        let items = parts.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count,
              items.first(where: { $0.name == "state" })?.value == state,
              !items.contains(where: { $0.name == "error" }),
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.count <= 4096 else { throw AuthError.invalidCallback }
        return code
    }
    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let text = fields.sorted(by: { $0.key < $1.key }).map {
            $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        return Data(text.utf8)
    }
}
