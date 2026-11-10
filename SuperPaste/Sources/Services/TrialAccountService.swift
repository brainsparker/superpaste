import AppKit
import AuthenticationServices
import Combine
import Foundation

/// Hosted trials use verified provider accounts. Tokens are kept only in Keychain.
@MainActor
final class TrialAccountService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = TrialAccountService()
    struct Credential: Codable {
        let config: TrialAuthorization.Configuration
        let idToken: String
        let refreshToken: String?
        let tokenExpiresAt: Date
        let email: String
        var trialExpiresAt: Date?
    }
    struct Store {
        var read: () -> String?
        var write: (String) throws -> Void
        var delete: () throws -> Void
        static func keychain(bundleID: String) -> Self {
            let keychain = Keychain(service: bundleID + ".trial-account")
            return .init(read: keychain.read, write: keychain.write, delete: {
                keychain.delete()
                guard keychain.read() == nil else { throw TrialAuthorization.AuthError.storageFailed }
            })
        }
    }
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    typealias Browser = (URL, String) async throws -> URL
    @Published private(set) var email: String?
    @Published private(set) var isSigningIn = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var revision = 0
    private(set) var credential: Credential?
    var hasSession: Bool { credential != nil }
    var trialExpired: Bool { credential?.trialExpiresAt.map { $0 <= Date() } ?? false }
    var daysRemaining: Int? {
        guard let credential else { return nil }
        guard let expires = credential.trialExpiresAt else { return 7 }
        let remaining = ceil(expires.timeIntervalSinceNow / 86400)
        guard remaining.isFinite else { return 0 }
        return Int(min(7, max(0, remaining)))
    }
    private let store: Store
    private let transport: Transport
    private let browser: Browser?
    private let baseURL: URL
    private let redirectURI: String
    private(set) var generation = 0
    private var refreshTask: Task<String, Error>?
    private var webSession: ASWebAuthenticationSession?
    private var browserContinuation: CheckedContinuation<URL, Error>?

    init(store: Store? = nil, transport: Transport? = nil, browser: Browser? = nil,
         baseURL: URL = URL(string: APIConfig.baseURL)!, bundleID: String = Bundle.main.bundleIdentifier ?? "com.superpaste.app") {
        self.store = store ?? .keychain(bundleID: bundleID)
        self.transport = transport ?? { try await ProviderTransport.session.data(for: $0) }
        self.browser = browser
        self.baseURL = baseURL.deletingLastPathComponent().appendingPathComponent("trial-auth")
        self.redirectURI = bundleID + ":/oauth/callback"
        super.init()
        if let value = self.store.read(), let data = value.data(using: .utf8),
           let saved = try? JSONDecoder().decode(Credential.self, from: data),
           (try? saved.config.validate(expectedRedirect: redirectURI)) != nil {
            credential = saved; email = saved.email
        }
    }
    private func current(_ ticket: Int) throws {
        try Task.checkCancellation()
        guard ticket == generation else { throw CancellationError() }
    }
    private func persist(_ value: Credential, ticket: Int) throws {
        try current(ticket)
        guard let encoded = String(data: try JSONEncoder().encode(value), encoding: .utf8) else { throw TrialAuthorization.AuthError.storageFailed }
        do { try store.write(encoded) } catch { throw TrialAuthorization.AuthError.storageFailed }
        credential = value; email = value.email; errorMessage = nil; revision += 1
    }
    private func request(_ url: URL, body: Data? = nil, bearer: String? = nil, form: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let body {
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue(form ? "application/x-www-form-urlencoded" : "application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, data.count <= 128*1024 else { throw TrialAuthorization.AuthError.signInFailed }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 403 { throw TrialAuthorization.AuthError.unverifiedEmail }
            if response.statusCode == 401 { throw LLMService.LLMError.trialSignInRequired }
            throw TrialAuthorization.AuthError.signInFailed
        }
        return data
    }
    private func configuration() async throws -> TrialAuthorization.Configuration {
        var parts = URLComponents(url: baseURL.appendingPathComponent("config"), resolvingAgainstBaseURL: false)!
        if redirectURI.hasPrefix("com.superpaste.app.dev:") { parts.queryItems = [.init(name: "client", value: "development")] }
        let config = try JSONDecoder().decode(TrialAuthorization.Configuration.self, from: await request(parts.url!))
        try config.validate(expectedRedirect: redirectURI)
        return config
    }
    private struct Tokens: Decodable { let id_token: String; let refresh_token: String? }
    private struct Verification: Decodable { let verified: Bool; let email: String; let token_expires_at: Double; let trial_expires_at: Double? }
    private func exchange(_ config: TrialAuthorization.Configuration, fields: [String: String], nonce: String?, ticket: Int, oldRefresh: String? = nil) async throws -> Credential {
        let data = try await request(URL(string: config.token_endpoint)!, body: TrialAuthorization.form(fields), form: true)
        try current(ticket)
        let tokens = try JSONDecoder().decode(Tokens.self, from: data)
        guard !tokens.id_token.isEmpty, tokens.id_token.count <= 16384 else { throw TrialAuthorization.AuthError.signInFailed }
        let body = try JSONSerialization.data(withJSONObject: nonce.map { ["nonce": $0] } ?? [:])
        let verification = try JSONDecoder().decode(Verification.self, from: await request(baseURL.appendingPathComponent("verify"), body: body, bearer: tokens.id_token))
        try current(ticket)
        let now = Date().timeIntervalSince1970
        guard verification.verified, !verification.email.isEmpty, verification.token_expires_at.isFinite,
              verification.token_expires_at/1000 > now, verification.token_expires_at/1000 < now+366*86400,
              verification.trial_expires_at.map({ $0.isFinite && $0 >= 0 && $0/1000 < now+8*86400 }) ?? true else {
            throw TrialAuthorization.AuthError.signInFailed
        }
        return Credential(config: config, idToken: tokens.id_token, refreshToken: tokens.refresh_token ?? oldRefresh,
                          tokenExpiresAt: Date(timeIntervalSince1970: verification.token_expires_at/1000), email: verification.email,
                          trialExpiresAt: verification.trial_expires_at.map { Date(timeIntervalSince1970: $0/1000) })
    }
    func signIn() async {
        guard !isSigningIn else { return }
        generation += 1
        let ticket = generation
        refreshTask?.cancel(); refreshTask = nil
        isSigningIn = true; errorMessage = nil
        defer { if ticket == generation { isSigningIn = false } }
        do {
            let config = try await configuration()
            try current(ticket)
            let flow = try TrialAuthorization()
            let url = try flow.authorizationURL(config)
            let callback: URL
            if let browser { callback = try await browser(url, URL(string: redirectURI)!.scheme!) }
            else { callback = try await openBrowser(url) }
            try current(ticket)
            let code = try flow.code(from: callback, redirect: redirectURI)
            let value = try await exchange(config, fields: ["grant_type": "authorization_code", "code": code, "client_id": config.client_id,
                                                            "redirect_uri": redirectURI, "code_verifier": flow.verifier], nonce: flow.nonce, ticket: ticket)
            try persist(value, ticket: ticket)
        } catch is CancellationError { }
        catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin { }
        catch { if ticket == generation { errorMessage = error.localizedDescription } }
    }
    /// Refresh never opens a browser. The hotkey can fail before capture and direct the user to sign in.
    func authorizationHeader() async throws -> String {
        guard !isSigningIn, let saved = credential else { throw LLMService.LLMError.trialSignInRequired }
        if saved.tokenExpiresAt > Date().addingTimeInterval(60) { return "Bearer " + saved.idToken }
        if let task = refreshTask { return try await task.value }
        guard let refresh = saved.refreshToken else { throw LLMService.LLMError.trialSignInRequired }
        let ticket = generation
        let task = Task { @MainActor in
            let config = try await self.configuration()
            try self.current(ticket)
            guard config.issuer == saved.config.issuer, config.client_id == saved.config.client_id,
                  config.token_endpoint == saved.config.token_endpoint else { throw LLMService.LLMError.trialSignInRequired }
            let renewed = try await self.exchange(config, fields: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": config.client_id], nonce: nil, ticket: ticket, oldRefresh: refresh)
            try self.persist(renewed, ticket: ticket)
            return "Bearer " + renewed.idToken
        }
        refreshTask = task
        defer { if ticket == generation { refreshTask = nil } }
        do { return try await task.value }
        catch is CancellationError { throw CancellationError() }
        catch { throw LLMService.LLMError.trialSignInRequired }
    }
    func recordTrialExpiration(_ date: Date, authorization: String?) {
        guard var value = credential, authorization == "Bearer " + value.idToken else { return }
        value.trialExpiresAt = date
        do { try persist(value, ticket: generation) } catch { errorMessage = error.localizedDescription }
    }
    func signOut() {
        generation += 1
        refreshTask?.cancel(); refreshTask = nil
        webSession?.cancel(); finishBrowser(.failure(CancellationError()))
        credential = nil; email = nil; isSigningIn = false; errorMessage = nil; revision += 1
        do { try store.delete() } catch { errorMessage = error.localizedDescription }
    }
    private func openBrowser(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            browserContinuation = continuation
            let ticket = generation
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: URL(string: redirectURI)!.scheme) { [weak self] callback, error in
                Task { @MainActor in
                    guard self?.generation == ticket else { return }
                    if let callback { self?.finishBrowser(.success(callback)) }
                    else { self?.finishBrowser(.failure(error ?? TrialAuthorization.AuthError.signInFailed)) }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session
            if !session.start() { finishBrowser(.failure(TrialAuthorization.AuthError.signInFailed)) }
        }
    }
    private func finishBrowser(_ result: Result<URL, Error>) {
        let continuation = browserContinuation
        browserContinuation = nil; webSession = nil
        continuation?.resume(with: result)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
