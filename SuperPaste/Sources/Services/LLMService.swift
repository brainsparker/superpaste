import Foundation

/// Service for communicating with the Anthropic Claude API.
final class LLMService {
    static let shared = LLMService()

    private init() {}

    // MARK: - Request/Response Models

    struct AnthropicRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: String
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
        case invalidAPIKey
        case networkError(Error)
        case rateLimited
        case serverError(Int)
        case timeout
        case invalidResponse
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidAPIKey:
                return "Invalid API key configuration"
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
            }
        }

        var userFriendlyMessage: String {
            switch self {
            case .invalidAPIKey:
                return "Configuration error"
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
            }
        }
    }

    // MARK: - API Call

    /// Process context and get LLM response
    func process(context: ContextService.CapturedContext) async throws -> String {
        // Validate API key
        let apiKey = APIConfig.apiKey
        guard !apiKey.isEmpty, apiKey != "PLACEHOLDER", apiKey != "PLACEHOLDER_API_KEY" else {
            throw LLMError.invalidAPIKey
        }

        // Build the user message with context
        let userMessage = buildUserMessage(context: context)

        let request = AnthropicRequest(
            model: APIConfig.model,
            max_tokens: APIConfig.maxTokens,
            system: APIConfig.systemPrompt,
            messages: [
                .init(role: "user", content: userMessage)
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
            if error.message?.contains("Invalid API Key") == true {
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

    // MARK: - Private

    private func buildUserMessage(context: ContextService.CapturedContext) -> String {
        var parts: [String] = []

        parts.append("## Context")

        if let app = context.appName {
            parts.append("- **Application:** \(app)")
        }
        if let window = context.windowTitle, !window.isEmpty {
            parts.append("- **Window title:** \(window)")
        }

        parts.append("")

        if let clipboard = context.clipboardText, !clipboard.isEmpty {
            parts.append("## Clipboard contents")
            parts.append("```")
            parts.append(clipboard)
            parts.append("```")
        } else {
            parts.append("## Clipboard contents")
            parts.append("(empty)")
        }

        parts.append("")
        parts.append("Generate the appropriate text to paste:")

        return parts.joined(separator: "\n")
    }
}
