import Foundation

/// Service for producing the paste text, either through the SuperPaste backend
/// (default) or directly against the Anthropic API when the user has supplied
/// their own key (bring-your-own-key mode — free, no SuperPaste servers).
final class LLMService {
    static let shared = LLMService()

    private init() {}

    // MARK: - Request models

    /// The SuperPaste backend contract: just the captured context. The Worker
    /// owns the model, system prompt, and token limits — clients can't be
    /// used as a general-purpose Anthropic proxy.
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

    /// Full Anthropic request, used only in bring-your-own-key mode where the
    /// app talks to api.anthropic.com directly.
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

        struct Thinking: Encodable {
            let type: String
        }

        struct OutputConfig: Encodable {
            let effort: String
        }
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

        private struct TextContent: Encodable {
            let type: String
            let text: String
        }

        private struct ImageContent: Encodable {
            let type: String
            let source: ImageSource
        }

        private struct ImageSource: Encodable {
            let type: String
            let media_type: String
            let data: String
        }
    }

    struct AnthropicResponse: Decodable {
        let content: [Content]?
        let stop_reason: String?
        let error: ErrorInfo?

        struct Content: Decodable {
            let type: String
            let text: String?
        }

        struct ErrorInfo: Decodable {
            let message: String?
        }
    }

    // MARK: - Errors

    enum LLMError: LocalizedError {
        case networkError(Error)
        case rateLimited        // Anthropic-side 429
        case dailyLimitReached  // Our 429 — daily cap hit
        case trialExpired       // 402 — trial over, needs license
        case licenseInvalid     // 403 — bad license key
        case serverError(Int)
        case timeout
        case invalidResponse
        case emptyResponse
        case imageEncodingFailed
        case unclearContext     // model couldn't infer what to write
        case truncatedResponse  // hit max_tokens; pasting half a sentence helps nobody
        case invalidAPIKey      // BYO-key mode: Anthropic rejected the user's key

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
                return "Anthropic rejected your API key."
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
                return "Trial ended \u{2014} enter your license key"
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
                return "Your Anthropic API key was rejected \u{2014} check it in Settings."
            }
        }
    }

    // MARK: - API Call

    func process(context: ScreenCaptureService.CapturedContext) async throws -> String {
        guard let base64Image = context.base64EncodedJPEG() else {
            throw LLMError.imageEncodingFailed
        }

        let urlRequest: URLRequest
        let usingDirectMode: Bool
        if let userKey = UserAPIKey.current {
            urlRequest = try buildDirectAnthropicRequest(context: context, base64Image: base64Image, apiKey: userKey)
            usingDirectMode = true
        } else {
            urlRequest = try buildProxyRequest(context: context, base64Image: base64Image)
            usingDirectMode = false
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMError.timeout
        } catch {
            throw LLMError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401 where usingDirectMode, 403 where usingDirectMode:
            // Talking straight to Anthropic: 401/403 mean the USER's key is
            // bad, not our trial/license machinery.
            throw LLMError.invalidAPIKey
        case 402:
            throw LLMError.trialExpired
        case 403:
            throw LLMError.licenseInvalid
        case 429:
            // Distinguish our rate limit (error: "rate_limited") from Anthropic's 429
            if let errorBody = try? JSONDecoder().decode(WorkerErrorResponse.self, from: data),
               errorBody.error == "rate_limited" {
                throw LLMError.dailyLimitReached
            }
            throw LLMError.rateLimited
        default:
            throw LLMError.serverError(httpResponse.statusCode)
        }

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

        // A response that hit the token ceiling ends mid-sentence — pasting it
        // silently is worse than failing loudly.
        if anthropicResponse.stop_reason == "max_tokens" {
            throw LLMError.truncatedResponse
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // The prompt tells the model to emit this sentinel when it can't infer
        // what belongs in the field. It must never be pasted as literal text.
        if trimmed.contains(APIConfig.unclearSentinel) {
            throw LLMError.unclearContext
        }

        return trimmed
    }

    // MARK: - Request builders

    private func responseSettings() -> (tone: ResponseTone, length: ResponseLength, personalContext: String) {
        let personalContext = UserDefaults.standard.string(forKey: "personalContext") ?? ""
        let tone = ResponseTone(
            rawValue: UserDefaults.standard.string(forKey: "responseTone") ?? ""
        ) ?? .matchContext
        let length = ResponseLength(
            rawValue: UserDefaults.standard.string(forKey: "responseLength") ?? ""
        ) ?? .balanced
        return (tone, length, personalContext)
    }

    private func buildProxyRequest(
        context: ScreenCaptureService.CapturedContext,
        base64Image: String
    ) throws -> URLRequest {
        let settings = responseSettings()
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
        urlRequest.setValue(DeviceID.current, forHTTPHeaderField: "X-Device-ID")
        if let licenseKey = LicenseService.shared.currentLicenseKey, !licenseKey.isEmpty {
            urlRequest.setValue(licenseKey, forHTTPHeaderField: "X-License-Key")
        }
        urlRequest.timeoutInterval = APIConfig.timeoutInterval

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw LLMError.invalidResponse
        }
        return urlRequest
    }

    private func buildDirectAnthropicRequest(
        context: ScreenCaptureService.CapturedContext,
        base64Image: String,
        apiKey: String
    ) throws -> URLRequest {
        let settings = responseSettings()

        var contentParts: [ContentPart] = []
        contentParts.append(.image(base64Data: base64Image, mediaType: "image/jpeg"))
        contentParts.append(.text(buildTextPrompt(context: context)))

        let request = AnthropicRequest(
            model: APIConfig.model,
            max_tokens: APIConfig.maxTokens,
            system: APIConfig.buildSystemPrompt(
                personalContext: settings.personalContext,
                tone: settings.tone,
                length: settings.length
            ),
            // Keep the no-thinking, low-latency profile the product is built around.
            thinking: .init(type: "disabled"),
            output_config: .init(effort: "low"),
            messages: [
                .init(role: "user", content: contentParts)
            ]
        )

        guard let url = URL(string: APIConfig.anthropicDirectURL) else {
            throw LLMError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(APIConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = APIConfig.timeoutInterval

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw LLMError.invalidResponse
        }
        return urlRequest
    }

    // MARK: - Private

    private struct WorkerErrorResponse: Decodable {
        let error: String?
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
