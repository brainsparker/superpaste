import Foundation

/// Service for producing the paste text through the configured provider.
final class LLMService {
    static let shared = LLMService()

    private init() {}

    // MARK: - Errors

    enum LLMError: LocalizedError {
        case networkError(Error)
        case rateLimited
        case dailyLimitReached
        case trialExpired
        case licenseInvalid
        case serverError(Int)
        case timeout
        case invalidResponse
        case emptyResponse
        case imageEncodingFailed
        case unclearContext
        case truncatedResponse
        case invalidAPIKey
        case providerNotConfigured
        /// A local or custom server did not answer at all (connection refused).
        /// Carries the host:port so the message can say where we looked.
        case localServerUnreachable(String)
        /// The server answered but does not have the requested model installed.
        case modelNotFound(String)
        /// A local or custom server reports no installed models at all.
        case noModelsAvailable
        /// Magic Copy: the share link's campaign has ended.
        case campaignExpired
        /// Magic Copy: the link isn't a usable campaign.
        case campaignInvalid
        /// Magic Copy: the draft broke a campaign guardrail; nothing is pasted.
        case campaignBlocked(String)
        /// Magic Copy needs the SuperPaste backend, not a bring-your-own provider.
        case shareUnavailableInBYOKMode

        var errorDescription: String? {
            switch self {
            case .networkError:
                return "Network error. Check your connection."
            case .rateLimited:
                return "Rate limited. Try again in a moment."
            case .dailyLimitReached:
                return "Daily limit reached. Resets at midnight."
            case .trialExpired:
                return "Your free trial has ended."
            case .licenseInvalid:
                return "License key is not valid."
            case .serverError(let code):
                return "Server error (\(code)). Try again."
            case .timeout:
                return "Request timed out. Try again."
            case .invalidResponse:
                return "Invalid response from server."
            case .emptyResponse:
                return "Empty response from server."
            case .imageEncodingFailed:
                return "Failed to encode screenshot."
            case .unclearContext:
                return "Couldn't tell what to write from this window."
            case .truncatedResponse:
                return "Response was cut off."
            case .invalidAPIKey:
                return "The API key was rejected."
            case .providerNotConfigured:
                return "No provider is configured. Add an API key in Settings."
            case .localServerUnreachable(let host):
                return "No server is answering at \(host)."
            case .modelNotFound(let model):
                return "Model \(model) is not available on the server."
            case .noModelsAvailable:
                return "The server has no models installed."
            case .campaignExpired:
                return "This Smart Share link has expired."
            case .campaignInvalid:
                return "This Smart Share link isn't valid."
            case .campaignBlocked(let reason):
                return reason
            case .shareUnavailableInBYOKMode:
                return "Magic Copy needs the SuperPaste backend."
            }
        }

        var userFriendlyMessage: String {
            switch self {
            case .networkError:
                return "Can't connect \u{2014} check your internet connection."
            case .rateLimited:
                return "Too many requests \u{2014} wait a moment and try again."
            case .dailyLimitReached:
                return "Daily limit reached. Resets at midnight."
            case .trialExpired:
                return "Trial ended \u{2014} subscribe or add your own API key"
            case .licenseInvalid:
                return "License key not valid"
            case .serverError:
                return "Server hiccup \u{2014} try again in a few seconds."
            case .timeout:
                return "Took too long \u{2014} try with a simpler window."
            case .invalidResponse, .emptyResponse:
                return "Got an unexpected response \u{2014} try again."
            case .imageEncodingFailed:
                return "Couldn't process screenshot \u{2014} try a different window."
            case .unclearContext:
                return "Couldn't tell what to write here \u{2014} click into a text field and try again."
            case .truncatedResponse:
                return "The response ran too long \u{2014} try again."
            case .invalidAPIKey:
                return "Your API key was rejected \u{2014} check it in Settings."
            case .providerNotConfigured:
                return "No API key has been saved for this provider \u{2014} add one in Settings."
            case .localServerUnreachable(let host):
                return "Nothing is running at \(host). Start your local model server, then try again."
            case .modelNotFound(let model):
                return "Your server doesn't have \(model). Pull it first, or pick an installed model in Settings."
            case .noModelsAvailable:
                return "Your local server has no models yet. Pull a vision model (for example qwen3-vl) and try again."
            case .campaignExpired:
                return "This Smart Share link has expired \u{2014} ask whoever sent it for a new one."
            case .campaignInvalid:
                return "That Smart Share link isn't valid \u{2014} copy the whole link and try again."
            case .campaignBlocked(let reason):
                return reason
            case .shareUnavailableInBYOKMode:
                return "Magic Copy works through the SuperPaste service \u{2014} switch your provider in Settings to use it."
            }
        }
    }

    // MARK: - Settings helpers

    static func responseSettings() -> (tone: ResponseTone, length: ResponseLength, personalContext: String) {
        let personalContext = UserDefaults.standard.string(forKey: "personalContext") ?? ""
        let tone = ResponseTone(
            rawValue: UserDefaults.standard.string(forKey: "responseTone") ?? ""
        ) ?? .matchContext
        let length = ResponseLength(
            rawValue: UserDefaults.standard.string(forKey: "responseLength") ?? ""
        ) ?? .balanced
        return (tone, length, personalContext)
    }

    /// Current provider config from UserDefaults.
    static func currentConfig() -> LLMProviderConfig {
        guard let data = UserDefaults.standard.data(forKey: "llmProviderConfig"),
              let config = try? JSONDecoder().decode(LLMProviderConfig.self, from: data) else {
            return .default
        }
        return config
    }

    static func saveConfig(_ config: LLMProviderConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: "llmProviderConfig")
    }

    /// Applies common headers that identify the request as coming from SuperPaste
    /// — User-Agent with version/URL so providers see where traffic originates,
    /// plus a stable device ID for rate limiting.
    private static func applyAttributionHeaders(_ request: inout URLRequest) {
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(DeviceID.current, forHTTPHeaderField: "X-Device-ID")
    }

    // MARK: - API Call

    func process(context: ScreenCaptureService.CapturedContext) async throws -> String {
        guard let base64Image = context.base64EncodedJPEG() else {
            throw LLMError.imageEncodingFailed
        }

        let config = Self.currentConfig()

        switch config.provider {
        case .superpaste:
            return try await processWithSuperPaste(
                context: context,
                base64Image: base64Image
            )
        case .anthropic:
            guard let key = UserCredentialStore.apiKey(for: .anthropic) else {
                throw LLMError.providerNotConfigured
            }
            return try await processWithAnthropic(
                context: context,
                base64Image: base64Image,
                apiKey: key,
                model: config.model.isEmpty ? config.provider.defaultModel : config.model
            )
        case .openai:
            guard let key = UserCredentialStore.apiKey(for: .openai) else {
                throw LLMError.providerNotConfigured
            }
            return try await processWithOpenAICompatible(
                baseURL: "https://api.openai.com/v1/chat/completions",
                apiKey: key,
                model: config.model.isEmpty ? config.provider.defaultModel : config.model,
                context: context,
                base64Image: base64Image
            )
        case .openrouter:
            guard let key = UserCredentialStore.apiKey(for: .openrouter) else {
                throw LLMError.providerNotConfigured
            }
            return try await processWithOpenAICompatible(
                baseURL: "https://openrouter.ai/api/v1/chat/completions",
                apiKey: key,
                model: config.model.isEmpty ? config.provider.defaultModel : config.model,
                context: context,
                base64Image: base64Image
            )
        case .ollama, .lmstudio, .custom:
            // Endpoint-configured providers. Local servers need no key; a
            // custom endpoint may have one saved, which is sent when present.
            guard let endpoint = config.resolvedEndpoint else {
                throw LLMError.providerNotConfigured
            }
            let apiKey = UserCredentialStore.apiKey(for: config.provider)
            let model = try await resolveModel(for: config, endpoint: endpoint, apiKey: apiKey)
            return try await processWithOpenAICompatible(
                baseURL: endpoint,
                apiKey: apiKey,
                model: model,
                context: context,
                base64Image: base64Image
            )
        }
    }

    /// The model to request from an endpoint-configured provider. When the
    /// user left the field empty, ask the server what it has and prefer a
    /// vision-capable model, so a fresh Ollama install works with zero typing.
    private func resolveModel(
        for config: LLMProviderConfig,
        endpoint: String,
        apiKey: String?
    ) async throws -> String {
        let trimmed = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard config.provider.supportsModelDiscovery else { return "gpt-4o" }

        let models: [LocalModelServer.Model]
        do {
            models = try await LocalModelServer.listModels(chatCompletionsURL: endpoint, apiKey: apiKey)
        } catch LocalModelServer.ListError.unreachable where config.provider.isLocal {
            throw LLMError.localServerUnreachable(LocalEndpoint.displayHost(endpoint))
        } catch LocalModelServer.ListError.unauthorized {
            throw LLMError.invalidAPIKey
        } catch {
            // Custom gateways without a model list (or briefly unreachable ones)
            // still deserve a sensible default; the chat call reports its own errors.
            if config.provider == .custom { return "gpt-4o" }
            throw LLMError.noModelsAvailable
        }
        guard let picked = LocalModelServer.pickDefaultModel(from: models.map(\.id)) else {
            throw LLMError.noModelsAvailable
        }
        return picked
    }

    // MARK: - SuperPaste hosted backend

    private struct ProxyRequest: Encodable {
        struct Image: Encodable {
            let data: String
            let media_type: String
        }
        let image: Image
        let app_name: String?
        let window_title: String?
        let tone: String
        let length: String
        let personal_context: String?
    }

    /// Magic Copy: a Smart Share campaign link plus where the user is posting.
    /// No screenshot — the campaign supplies the content and the frontmost app
    /// supplies the destination. The Worker decodes the campaign, picks the
    /// platform, and owns the prompt.
    private struct ShareRequest: Encodable {
        let share_link: String
        let bundle_id: String?
        let app_name: String?
        let window_title: String?
    }

    private struct WorkerErrorResponse: Decodable {
        let error: String?
        let message: String?
    }

    private func processWithSuperPaste(
        context: ScreenCaptureService.CapturedContext,
        base64Image: String
    ) async throws -> String {
        let settings = Self.responseSettings()
        let request = ProxyRequest(
            image: .init(data: base64Image, media_type: "image/jpeg"),
            app_name: context.appName,
            window_title: context.windowTitle?.isEmpty == false ? context.windowTitle : nil,
            tone: settings.tone.rawValue,
            length: settings.length.rawValue,
            personal_context: settings.personalContext.isEmpty ? nil : settings.personalContext
        )

        guard let url = URL(string: APIConfig.baseURL) else {
            throw LLMError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyAttributionHeaders(&urlRequest)
        if let licenseKey = LicenseService.shared.currentLicenseKey, !licenseKey.isEmpty {
            urlRequest.setValue(licenseKey, forHTTPHeaderField: "X-License-Key")
        }
        urlRequest.timeoutInterval = APIConfig.timeoutInterval
        urlRequest.httpBody = try JSONEncoder().encode(request)

        return try await sendHostedRequest(urlRequest)
    }

    /// Magic Copy: write a post for the Smart Share campaign on the clipboard,
    /// aimed at whatever app the user is in.
    ///
    /// Goes through the SuperPaste backend on the same `/v1/messages` route as a
    /// normal paste, so it is metered by the same trial and license limits. The
    /// Worker decodes the campaign, picks the platform from the window metadata,
    /// and owns the prompt — the app deliberately knows none of that.
    func processShareCampaign(
        link: String,
        target: ScreenCaptureService.WindowTarget
    ) async throws -> String {
        // Bring-your-own and local providers talk straight to their own endpoint
        // and never reach the Worker, so they cannot get the campaign prompt.
        // Fail clearly instead of quietly pasting something unrelated.
        guard Self.currentConfig().provider == .superpaste else {
            throw LLMError.shareUnavailableInBYOKMode
        }

        let request = ShareRequest(
            share_link: link,
            bundle_id: target.bundleIdentifier,
            app_name: target.appName,
            window_title: target.windowTitle?.isEmpty == false ? target.windowTitle : nil
        )

        guard let url = URL(string: APIConfig.baseURL) else {
            throw LLMError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyAttributionHeaders(&urlRequest)
        if let licenseKey = LicenseService.shared.currentLicenseKey, !licenseKey.isEmpty {
            urlRequest.setValue(licenseKey, forHTTPHeaderField: "X-License-Key")
        }
        urlRequest.timeoutInterval = APIConfig.timeoutInterval

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw LLMError.invalidResponse
        }

        return try await sendHostedRequest(urlRequest)
    }

    /// Shared tail of every hosted-backend call: status mapping and the
    /// Anthropic-shaped response parse. Used by normal pastes and Magic Copy.
    private func sendHostedRequest(_ urlRequest: URLRequest) async throws -> String {
        let (data, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 402:
            throw LLMError.trialExpired
        case 403:
            throw LLMError.licenseInvalid
        case 422:
            // Magic Copy only: the campaign link is unusable, or the draft broke
            // one of the campaign's guardrails and must not be pasted.
            let body = try? JSONDecoder().decode(WorkerErrorResponse.self, from: data)
            switch body?.error {
            case "campaign_expired":
                throw LLMError.campaignExpired
            case "campaign_blocked":
                throw LLMError.campaignBlocked(
                    body?.message ?? "That draft broke one of the campaign's rules \u{2014} nothing was pasted."
                )
            default:
                throw LLMError.campaignInvalid
            }
        case 429:
            if let errorBody = try? JSONDecoder().decode(WorkerErrorResponse.self, from: data),
               errorBody.error == "rate_limited" {
                throw LLMError.dailyLimitReached
            }
            throw LLMError.rateLimited
        default:
            throw LLMError.serverError(httpResponse.statusCode)
        }

        return try parseAnthropicResponse(data: data)
    }

    // MARK: - Anthropic direct

    private struct AnthropicRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let thinking: Thinking
        let output_config: OutputConfig
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: [ContentPart]
        }

        struct Thinking: Encodable { let type: String }
        struct OutputConfig: Encodable { let effort: String }
    }

    private enum ContentPart: Encodable {
        case text(String)
        case image(base64Data: String, mediaType: String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(TextContent(type: "text", text: text))
            case .image(let data, let mediaType):
                try container.encode(ImageContent(
                    type: "image",
                    source: ImageSource(type: "base64", media_type: mediaType, data: data)
                ))
            }
        }

        private struct TextContent: Encodable { let type: String; let text: String }
        private struct ImageContent: Encodable { let type: String; let source: ImageSource }
        private struct ImageSource: Encodable { let type: String; let media_type: String; let data: String }
    }

    struct AnthropicResponse: Decodable {
        let content: [Content]?
        let stop_reason: String?
        let error: ErrorInfo?
        struct Content: Decodable { let type: String; let text: String? }
        struct ErrorInfo: Decodable { let message: String? }
    }

    private func processWithAnthropic(
        context: ScreenCaptureService.CapturedContext,
        base64Image: String,
        apiKey: String,
        model: String
    ) async throws -> String {
        let settings = Self.responseSettings()

        var contentParts: [ContentPart] = []
        contentParts.append(.image(base64Data: base64Image, mediaType: "image/jpeg"))
        contentParts.append(.text(buildTextPrompt(context: context)))

        let request = AnthropicRequest(
            model: model,
            max_tokens: APIConfig.maxTokens,
            system: APIConfig.buildSystemPrompt(
                personalContext: settings.personalContext,
                tone: settings.tone,
                length: settings.length
            ),
            thinking: .init(type: "disabled"),
            output_config: .init(effort: "low"),
            messages: [.init(role: "user", content: contentParts)]
        )

        guard let url = URL(string: LLMProviderID.anthropic.endpointURL) else {
            throw LLMError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(APIConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        // Attribution — lets Anthropic identify SuperPaste traffic in their dashboards.
        Self.applyAttributionHeaders(&urlRequest)
        urlRequest.setValue("https://superpaste.ai", forHTTPHeaderField: "Anthropic-Origin")
        urlRequest.timeoutInterval = APIConfig.timeoutInterval
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await performRequest(urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw LLMError.invalidAPIKey
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.serverError(httpResponse.statusCode)
        }

        return try parseAnthropicResponse(data: data)
    }

    /// Parse an Anthropic-format response body.
    private func parseAnthropicResponse(data: Data) throws -> String {
        let anthropicResponse: AnthropicResponse
        do {
            anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse
        }

        if anthropicResponse.error != nil {
            throw LLMError.serverError(500)
        }

        guard let content = anthropicResponse.content,
              let firstContent = content.first,
              firstContent.type == "text",
              let text = firstContent.text,
              !text.isEmpty else {
            throw LLMError.emptyResponse
        }

        if anthropicResponse.stop_reason == "max_tokens" {
            throw LLMError.truncatedResponse
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(APIConfig.unclearSentinel) {
            throw LLMError.unclearContext
        }

        return trimmed
    }

    // MARK: - OpenAI-compatible (OpenAI, OpenRouter, Custom)

    private struct OpenAIRequest: Encodable {
        let model: String
        let messages: [Message]
        let max_tokens: Int

        struct Message: Encodable {
            let role: String
            let content: [Content]
        }

        struct Content: Encodable {
            let type: String
            var text: String? = nil
            var image_url: ImageURL? = nil

            struct ImageURL: Encodable {
                let url: String
            }
        }
    }

    private struct OpenAIResponse: Decodable {
        let choices: [Choice]?
        let error: OpenAIError?

        struct Choice: Decodable {
            let message: Message
            struct Message: Decodable {
                let content: String?
            }
        }

        struct OpenAIError: Decodable {
            let message: String?
        }
    }

    private func processWithOpenAICompatible(
        baseURL: String,
        apiKey: String?,
        model: String,
        context: ScreenCaptureService.CapturedContext,
        base64Image: String
    ) async throws -> String {
        let settings = Self.responseSettings()

        let systemMessage = APIConfig.buildSystemPrompt(
            personalContext: settings.personalContext,
            tone: settings.tone,
            length: settings.length
        )

        let imageContent = OpenAIRequest.Content(
            type: "image_url",
            image_url: .init(url: "data:image/jpeg;base64,\(base64Image)")
        )
        let textContent = OpenAIRequest.Content(
            type: "text",
            text: buildTextPrompt(context: context)
        )

        let request = OpenAIRequest(
            model: model,
            messages: [
                .init(role: "system", content: [.init(type: "text", text: systemMessage)]),
                .init(role: "user", content: [imageContent, textContent]),
            ],
            max_tokens: APIConfig.maxTokens
        )

        guard let url = URL(string: baseURL) else {
            throw LLMError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Local servers (Ollama, LM Studio) accept requests with no key at all,
        // so the header is only sent when the user saved one.
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // Attribution — lets every provider identify SuperPaste traffic.
        Self.applyAttributionHeaders(&urlRequest)

        // OpenRouter-specific attribution: referer and title appear in their dashboard.
        if baseURL.contains("openrouter.ai") {
            urlRequest.setValue("https://superpaste.ai", forHTTPHeaderField: "HTTP-Referer")
            urlRequest.setValue("SuperPaste", forHTTPHeaderField: "X-Title")
        }

        urlRequest.timeoutInterval = APIConfig.timeoutInterval
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await performRequest(urlRequest)
        } catch LLMError.networkError(let underlying) {
            // A refused connection on a local endpoint means the server isn't
            // running, which deserves a more useful message than "network error".
            if let urlError = underlying as? URLError,
               urlError.code == .cannotConnectToHost || urlError.code == .cannotFindHost,
               LocalEndpoint.isLoopback(baseURL) {
                throw LLMError.localServerUnreachable(LocalEndpoint.displayHost(baseURL))
            }
            throw LLMError.networkError(underlying)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw LLMError.invalidAPIKey
        }
        if httpResponse.statusCode == 404 {
            // Ollama answers 404 with "model 'x' not found, try pulling it first".
            // LM Studio uses the same status for an unloaded model.
            throw LLMError.modelNotFound(model)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(OpenAIResponse.self, from: data).error,
               let message = apiError.message?.lowercased(),
               message.contains("not found") || message.contains("no model") || message.contains("not loaded") {
                throw LLMError.modelNotFound(model)
            }
            throw LLMError.serverError(httpResponse.statusCode)
        }

        let openAIResponse: OpenAIResponse
        do {
            openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse
        }

        if let apiError = openAIResponse.error {
            if apiError.message?.contains("API key") == true {
                throw LLMError.invalidAPIKey
            }
            throw LLMError.serverError(500)
        }

        guard let choice = openAIResponse.choices?.first,
              let text = choice.message.content,
              !text.isEmpty else {
            throw LLMError.emptyResponse
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(APIConfig.unclearSentinel) {
            throw LLMError.unclearContext
        }

        return trimmed
    }

    // MARK: - Shared

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMError.timeout
        } catch {
            throw LLMError.networkError(error)
        }
    }

    private func buildTextPrompt(context: ScreenCaptureService.CapturedContext) -> String {
        var parts: [String] = []
        if let app = context.appName { parts.append("Application: \(app)") }
        if let window = context.windowTitle, !window.isEmpty { parts.append("Window: \(window)") }
        parts.append("")
        parts.append("Generate the appropriate response based on what you see.")
        return parts.joined(separator: "\n")
    }
}