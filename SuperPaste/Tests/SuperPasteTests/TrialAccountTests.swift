import Foundation
import Testing
@testable import SuperPaste

@MainActor
struct TrialAccountTests {
    static let config = TrialAuthorization.Configuration(issuer: "https://identity.example.test", client_id: "native-client",
        authorization_endpoint: "https://identity.example.test/authorize", token_endpoint: "https://identity.example.test/token",
        redirect_uri: "com.superpaste.app:/oauth/callback", scope: "openid email offline_access")
    @MainActor final class Harness {
        var stored: String?
        var requests: [URLRequest] = []
        var verificationStatus = 200
        var failStorage = false
        var invalidState = false
        var token = "signed-id-token"
        var tokenExpires = Date().addingTimeInterval(3600)
        var gate: CheckedContinuation<Void, Never>?
        var blockTokens = false
        var nonce: String?
        func store() -> TrialAccountService.Store {
            .init(read: { self.stored }, write: { value in
                if self.failStorage { throw TrialAuthorization.AuthError.storageFailed }
                self.stored = value
            }, delete: { self.stored = nil })
        }
        func service() -> TrialAccountService {
            TrialAccountService(store: store(), transport: { request in
                self.requests.append(request)
                let path = request.url!.path
                let body: Data
                var status = 200
                if path.hasSuffix("/config") { body = try JSONEncoder().encode(TrialAccountTests.config) }
                else if path == "/token" {
                    if self.blockTokens { await withCheckedContinuation { self.gate = $0 } }
                    body = try JSONSerialization.data(withJSONObject: ["id_token":self.token,"refresh_token":"refresh-secret"])
                } else {
                    status = self.verificationStatus
                    body = try JSONSerialization.data(withJSONObject: ["verified":true,"email":"person@example.test",
                        "token_expires_at":self.tokenExpires.timeIntervalSince1970*1000, "trial_expires_at":NSNull()])
                }
                return (body, HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
            }, browser: { url, scheme in
                #expect(scheme == "com.superpaste.app")
                let items = URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!
                self.nonce = items.first(where:{$0.name == "nonce"})!.value
                let state = self.invalidState ? "attacker-state" : items.first(where:{$0.name == "state"})!.value!
                return URL(string:"com.superpaste.app:/oauth/callback?code=code%2Bwith%26reserved&state="+state)!
            }, baseURL:URL(string:"https://api.example/v1/messages")!, bundleID:"com.superpaste.app")
        }
    }
    @Test func pkceMatchesRFC7636Vector() throws {
        let flow = TrialAuthorization(verifier:"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",state:"state",nonce:"nonce")
        #expect(flow.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let items = URLComponents(url:try flow.authorizationURL(Self.config),resolvingAgainstBaseURL:false)!.queryItems!
        #expect(items.first(where:{$0.name == "code_challenge_method"})?.value == "S256")
        #expect(items.first(where:{$0.name == "nonce"})?.value == "nonce")
        #expect(!items.contains(where:{$0.name == "client_secret"}))
    }
    @Test func callbackRequiresExactPathStateAndUnambiguousParameters() throws {
        let flow = TrialAuthorization(verifier:"verifier",state:"expected",nonce:"nonce")
        #expect(try flow.code(from:URL(string:"com.superpaste.app:/oauth/callback?code=abc&state=expected")!,redirect:Self.config.redirect_uri) == "abc")
        for value in ["other:/oauth/callback?code=a&state=expected", "com.superpaste.app:/wrong?code=a&state=expected",
                      "com.superpaste.app://attacker/oauth/callback?code=a&state=expected", "com.superpaste.app:/oauth/callback?code=a&state=wrong",
                      "com.superpaste.app:/oauth/callback?code=a&state=expected&state=expected", "com.superpaste.app:/oauth/callback?code=a&code=b&state=expected",
                      "com.superpaste.app:/oauth/callback?code=a&state=expected#error", "com.superpaste.app:/oauth/callback?error=denied&state=expected"] {
            #expect(throws: TrialAuthorization.AuthError.self) { try flow.code(from:URL(string:value)!,redirect:Self.config.redirect_uri) }
        }
    }
    @Test func credentialsAreStoredOnlyAfterServerVerification() async throws {
        let h = Harness(); let service = h.service()
        await service.signIn()
        #expect(service.email == "person@example.test")
        #expect(service.daysRemaining == 7)
        #expect(try await service.authorizationHeader() == "Bearer signed-id-token")
        let tokenRequest = try #require(h.requests.first(where:{$0.url?.path == "/token"}))
        let form = String(data:try #require(tokenRequest.httpBody),encoding:.utf8)!
        #expect(form.contains("code=code%2Bwith%26reserved"))
        #expect(form.contains("code_verifier=")); #expect(!form.contains("client_secret"))
        let verify = try #require(h.requests.first(where:{$0.url?.path.hasSuffix("/verify") == true}))
        let json = try JSONSerialization.jsonObject(with:try #require(verify.httpBody)) as! [String:String]
        #expect(json["nonce"] == h.nonce)
        #expect(verify.value(forHTTPHeaderField:"Authorization") == "Bearer signed-id-token")
        #expect(h.stored?.contains("refresh-secret") == true)
        #expect(h.service().email == "person@example.test")
        service.signOut()
        #expect(h.stored == nil); #expect(!service.hasSession)
        await #expect(throws: LLMService.LLMError.self) { try await service.authorizationHeader() }
    }
    @Test func rejectedEmailAndCallbackCannotPersistCredentials() async {
        let h = Harness(); h.verificationStatus = 403
        let service = h.service(); await service.signIn()
        #expect(!service.hasSession); #expect(h.stored == nil)
        #expect(service.errorMessage?.contains("Verify your email") == true)
        let wrong = Harness(); wrong.invalidState = true
        let wrongService = wrong.service(); await wrongService.signIn()
        #expect(!wrongService.hasSession); #expect(wrong.requests.count == 1)
    }
    @Test func keychainFailureNeverReportsSignedIn() async {
        let h = Harness(); h.failStorage = true
        let service = h.service(); await service.signIn()
        #expect(!service.hasSession); #expect(service.errorMessage?.contains("Keychain") == true)
    }
    @Test func signOutWhileExchangeIsPendingCannotResurrectAccount() async {
        let h = Harness(); h.blockTokens = true; let service = h.service()
        let signingIn = Task { await service.signIn() }
        while h.gate == nil { await Task.yield() }
        service.signOut(); h.gate?.resume(); h.gate = nil
        await signingIn.value
        #expect(!service.hasSession); #expect(h.stored == nil); #expect(!service.isSigningIn)
        #expect(!h.requests.contains(where:{$0.url?.path.hasSuffix("/verify") == true}))
    }
    @Test func concurrentRefreshUsesOneExchangeAndLogoutDiscardsStaleExpiry() async throws {
        let h = Harness(); h.tokenExpires = Date().addingTimeInterval(30)
        let service = h.service(); await service.signIn()
        #expect(service.hasSession)
        h.token = "refreshed-id-token"; h.tokenExpires = Date().addingTimeInterval(3600)
        async let first = service.authorizationHeader()
        async let second = service.authorizationHeader()
        #expect(try await first == "Bearer refreshed-id-token")
        #expect(try await second == "Bearer refreshed-id-token")
        #expect(h.requests.filter({$0.url?.path == "/token"}).count == 2)
        service.recordTrialExpiration(Date().addingTimeInterval(-1),authorization:"Bearer signed-id-token")
        #expect(!service.trialExpired)
        service.recordTrialExpiration(Date().addingTimeInterval(-1),authorization:"Bearer refreshed-id-token")
        #expect(service.trialExpired); #expect(service.daysRemaining == 0)
        service.signOut()
        service.recordTrialExpiration(Date(),authorization:"Bearer refreshed-id-token")
        #expect(!service.hasSession)
    }
    @Test func onlyExplicitHostedErrorsChangeAccountState() {
        for (status, code) in [(401,"trial_sign_in_required"),(401,"trial_session_invalid"),(402,"trial_expired"),(403,"trial_email_unverified"),(403,"license_invalid")] {
            let data = Data(("{\"error\":\""+code+"\"}").utf8)
            let error = LLMService.hostedAccessError(status:status,data:data)
            #expect(PasteFailure.provider(error).recovery == .openSettings)
        }
        for status in [401,402,403] {
            let error = LLMService.hostedAccessError(status:status,data:Data("{\"error\":{\"message\":\"upstream auth failed\"}}".utf8))
            if case .serverError(let actual) = error { #expect(actual == status) }
            else { Issue.record("An upstream failure changed trial state") }
        }
    }
    @Test func failedRefreshCannotReuseTheExpiredCredential() async {
        let h = Harness(); h.tokenExpires = Date().addingTimeInterval(30)
        let service = h.service(); await service.signIn()
        h.verificationStatus = 401
        await #expect(throws: LLMService.LLMError.self) { try await service.authorizationHeader() }
        #expect(h.requests.filter({$0.url?.path == "/token"}).count == 2)
    }
    @Test func signOutDuringRefreshCannotResurrectCredentials() async {
        let h = Harness(); h.tokenExpires = Date().addingTimeInterval(30)
        let service = h.service(); await service.signIn()
        h.blockTokens = true
        let refreshing = Task { try await service.authorizationHeader() }
        while h.gate == nil { await Task.yield() }
        service.signOut(); h.gate?.resume(); h.gate = nil
        _ = try? await refreshing.value
        #expect(h.stored == nil); #expect(!service.hasSession)
        #expect(h.requests.filter({$0.url?.path.hasSuffix("/verify") == true}).count == 1)
    }
    @Test func configurationRejectsInsecureEndpointsAndWrongAppCallback() throws {
        try Self.config.validate(expectedRedirect:"com.superpaste.app:/oauth/callback")
        #expect(throws: TrialAuthorization.AuthError.self) { try Self.config.validate(expectedRedirect:"com.superpaste.app.dev:/oauth/callback") }
        let unsafe = TrialAuthorization.Configuration(issuer:"http://identity.example.test",client_id:"client",
            authorization_endpoint:Self.config.authorization_endpoint,token_endpoint:Self.config.token_endpoint,
            redirect_uri:Self.config.redirect_uri,scope:"openid email")
        #expect(throws: TrialAuthorization.AuthError.self) { try unsafe.validate(expectedRedirect:Self.config.redirect_uri) }
        #expect(String(data:TrialAuthorization.form(["code":"a+b &=é"]),encoding:.utf8) == "code=a%2Bb%20%26%3D%C3%A9")
        let first = try TrialAuthorization(); let second = try TrialAuthorization()
        #expect(first.state != second.state); #expect(first.verifier.count >= 43); #expect(first.nonce != second.nonce)
    }
}
