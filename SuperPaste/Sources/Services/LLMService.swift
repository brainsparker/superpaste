import Foundation

/// Service for communicating with the SuperPaste backend proxy.
final class LLMService {
    static let shared = LLMService()

    private init() {}

    // MARK: - Request/Response Models

    struct VisionRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: [ContentPart]
        }
    }

    enum ContentPart: Encodable {
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
            }
        }

        var userFriendlyMessage: String {
            switch self {
            case .networkError:
                return "Check your internet connection"
            case .rateLimited:
                return "Too many requests, try again soon"
            case .dailyLimitReached:
                return "Daily limit reached. Resets at midnight."
            case .trialExpired:
                return "Trial ended — enter your license key"
            case .licenseInvalid:
                return "License key not valid"
            case .serverError:
                return "Server error, try again"
            case .timeout:
                return "Request timed out"
            case .invalidResponse, .emptyResponse:
                return "Something went wrong"
            case .imageEncodingFailed:
                return "Failed to process screenshot"
            }
        }
    }

    // MARK: - API Call

    func process(context: ScreenCaptureService.CapturedContext) async throws -> String {
        guard let base64Image = context.base64EncodedPNG() else {
            throw LLMError.imageEncodingFailed
        }

        var contentParts: [ContentPart] = []
        contentParts.append(.image(base64Data: base64Image, mediaType: "image/png"))
        contentParts.append(.text(buildTextPrompt(context: context)))

        let personalContext = UserDefaults.standard.string(forKey: "personalContext") ?? ""
        let request = VisionRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: APIConfig.maxTokens,
            system: APIConfig.buildSystemPrompt(personalContext: personalContext),
            messages: [
                .init(role: "user", content: contentParts)
            ]
        )

        guard let url = URL(string: APIConfig.baseURL) else {
            throw LLMError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(DeviceID.current, forHTTPHeaderField: "X-Device-ID")
        if let licenseKey = UserDefaults.standard.string(forKey: "licenseKey"), !licenseKey.isEmpty {
            urlRequest.setValue(licenseKey, forHTTPHeaderField: "X-License-Key")
        }
        urlRequest.timeoutInterval = APIConfig.timeoutInterval

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw LLMError.invalidResponse
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

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - License Validation

    func validateLicense(_ key: String) async throws -> Bool {
        guard let url = URL(string: APIConfig.validateLicenseURL) else { return false }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(DeviceID.current, forHTTPHeaderField: "X-Device-ID")
        urlRequest.timeoutInterval = 15

        let body = try JSONEncoder().encode(["key": key])
        urlRequest.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return false
        }

        struct ValidateResponse: Decodable { let valid: Bool }
        let result = try JSONDecoder().decode(ValidateResponse.self, from: data)
        return result.valid
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
