import Foundation

/// Service for communicating with the Anthropic Claude Vision API.
final class LLMService {
    static let shared = LLMService()

    private init() {}

    // MARK: - Request/Response Models

    /// Request structure for Anthropic Vision API
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

    /// Content part for vision messages - can be text or image
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
        case noAPIKey
        case invalidAPIKey
        case networkError(Error)
        case rateLimited
        case serverError(Int)
        case timeout
        case invalidResponse
        case emptyResponse
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured"
            case .invalidAPIKey:
                return "Invalid API key"
            case .networkError:
                return "Network error. Check your connection."
            case .rateLimited:
                return "Rate limited. Try again in a moment."
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
            case .noAPIKey:
                return "API key not configured"
            case .invalidAPIKey:
                return "Invalid API key. Check Settings."
            case .networkError:
                return "Check your internet connection"
            case .rateLimited:
                return "Too many requests, try again soon"
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

    /// Process screenshot context and get LLM response using Claude Vision.
    func process(context: ScreenCaptureService.CapturedContext) async throws -> String {
        // Validate API key
        guard let apiKey = APIConfig.apiKey, !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }

        // Convert screenshot to base64
        guard let base64Image = context.base64EncodedPNG() else {
            throw LLMError.imageEncodingFailed
        }

        // Build the content parts
        var contentParts: [ContentPart] = []

        // Add the image first
        contentParts.append(.image(base64Data: base64Image, mediaType: "image/png"))

        // Add text context
        let textPrompt = buildTextPrompt(context: context)
        contentParts.append(.text(textPrompt))

        let request = VisionRequest(
            model: APIConfig.model,
            max_tokens: APIConfig.maxTokens,
            system: APIConfig.systemPrompt,
            messages: [
                .init(role: "user", content: contentParts)
            ]
        )

        // Create URL request
        guard let url = URL(string: APIConfig.baseURL) else {
            throw LLMError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(APIConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = APIConfig.timeoutInterval

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw LLMError.invalidResponse
        }

        // Make request
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMError.timeout
        } catch {
            throw LLMError.networkError(error)
        }

        // Check response status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        default:
            throw LLMError.serverError(httpResponse.statusCode)
        }

        // Parse response
        let anthropicResponse: AnthropicResponse
        do {
            anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse
        }

        // Check for error in response
        if let error = anthropicResponse.error {
            if error.message?.contains("Invalid API Key") == true ||
               error.message?.contains("invalid x-api-key") == true {
                throw LLMError.invalidAPIKey
            }
            throw LLMError.serverError(500)
        }

        // Extract the text content
        guard let content = anthropicResponse.content,
              let firstContent = content.first,
              firstContent.type == "text",
              let text = firstContent.text,
              !text.isEmpty else {
            throw LLMError.emptyResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Test the API key by making a simple request.
    func testAPIKey(_ key: String) async throws -> Bool {
        guard !key.isEmpty else {
            throw LLMError.noAPIKey
        }

        // Make a simple text-only request to validate the key
        struct TestRequest: Encodable {
            let model: String
            let max_tokens: Int
            let messages: [Message]

            struct Message: Encodable {
                let role: String
                let content: String
            }
        }

        let request = TestRequest(
            model: APIConfig.model,
            max_tokens: 10,
            messages: [
                .init(role: "user", content: "Say 'ok'")
            ]
        )

        guard let url = URL(string: APIConfig.baseURL) else {
            throw LLMError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(APIConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 15.0  // Shorter timeout for test

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw LLMError.invalidResponse
        }

        let response: URLResponse

        do {
            (_, response) = try await URLSession.shared.data(for: urlRequest)
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
            return true
        case 401:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        default:
            throw LLMError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Private

    private func buildTextPrompt(context: ScreenCaptureService.CapturedContext) -> String {
        var parts: [String] = []

        if let app = context.appName {
            parts.append("Application: \(app)")
        }
        if let window = context.windowTitle, !window.isEmpty {
            parts.append("Window: \(window)")
        }

        parts.append("")
        parts.append("Generate the appropriate response based on what you see.")

        return parts.joined(separator: "\n")
    }
}
