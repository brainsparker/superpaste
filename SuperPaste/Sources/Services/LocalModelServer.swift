import Foundation

/// Endpoint arithmetic for OpenAI-compatible servers. Users paste all kinds
/// of things into the endpoint field (`localhost:11434`, `http://host/v1`, a
/// full chat-completions URL); every form is accepted and normalized here.
enum LocalEndpoint {
    private static let chatPath = "/v1/chat/completions"
    private static let modelsPath = "/v1/models"

    /// Normalizes whatever the user typed into a chat-completions URL.
    ///
    /// - `localhost:11434` becomes `http://localhost:11434/v1/chat/completions`
    /// - `http://localhost:1234/v1` becomes `http://localhost:1234/v1/chat/completions`
    /// - a full `.../v1/chat/completions` URL is returned unchanged (minus trailing slash)
    /// - other paths (reverse proxies, custom mounts) get `/chat/completions` appended
    static func chatCompletionsURL(from input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if !value.contains("://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }

        guard var components = URLComponents(string: value) else { return value }
        let path = components.path
        if path.isEmpty {
            components.path = chatPath
        } else if !path.hasSuffix("/chat/completions") {
            // `/v1`, or a reverse-proxy mount like `/ollama/v1`: append the leaf.
            components.path = path + "/chat/completions"
        }
        return components.string ?? value
    }

    /// Derives the `GET /v1/models` URL that sits beside a chat-completions URL.
    /// `http://localhost:11434/v1/chat/completions` becomes `http://localhost:11434/v1/models`.
    static func modelsURL(fromChatCompletionsURL chatURL: String) -> URL? {
        let normalized = chatCompletionsURL(from: chatURL)
        guard var components = URLComponents(string: normalized) else { return nil }
        var path = components.path
        if path.hasSuffix("/chat/completions") {
            path = String(path.dropLast("/chat/completions".count))
        }
        if path.isEmpty || path == "/" {
            path = modelsPath
        } else {
            path += "/models"
        }
        components.path = path
        components.query = nil
        return components.url
    }

    /// The `host:port` the request will reach, for display in Settings and
    /// Diagnostics (never the full URL, which could carry a token in a query).
    static func displayHost(_ endpoint: String) -> String {
        guard let components = URLComponents(string: chatCompletionsURL(from: endpoint)),
              let host = components.host else {
            return endpoint
        }
        if let port = components.port {
            return "\(host):\(port)"
        }
        return host
    }

    /// True when the endpoint resolves to this machine, which is what lets the
    /// UI promise that screenshots never leave the Mac.
    static func isLoopback(_ endpoint: String) -> Bool {
        guard let components = URLComponents(string: chatCompletionsURL(from: endpoint)),
              let host = components.host?.lowercased() else {
            return false
        }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" || host == "0.0.0.0" {
            return true
        }
        if host.hasPrefix("127.") { return true }
        if host.hasSuffix(".localhost") { return true }
        return false
    }
}

/// Heuristics about model identifiers reported by local servers. Servers
/// don't expose capability metadata through `/v1/models`, so the name is the
/// only signal available before a request is spent.
enum ModelCapabilityHint {
    private static let visionMarkers: [String] = [
        "vl", "vision", "llava", "bakllava", "moondream", "minicpm-v",
        "pixtral", "gemma3", "gemma-3", "gemma4", "gemma-4", "qwen2.5vl",
        "qwen2-vl", "qwen3-vl", "granite3.2-vision", "mistral-small3",
        "mistral-small-3", "llama3.2-vision", "llama-3.2-11b-vision",
        "llama-3.2-90b-vision", "phi-4-multimodal", "phi4-multimodal",
        "internvl", "idefics", "smolvlm", "paligemma", "florence",
    ]

    /// Whether a model id looks like it accepts images. False negatives are
    /// fine (the user can still pick the model); the hint only orders and
    /// labels the list.
    static func likelySupportsVision(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        for marker in visionMarkers {
            if marker == "vl" {
                // "vl" is short enough to appear inside unrelated words, so
                // require it to stand as its own token: qwen3-vl, qwen2.5vl:7b.
                if lower.range(of: #"(^|[^a-z])vl([^a-z]|$)"#, options: .regularExpression) != nil
                    || lower.range(of: #"\dvl([^a-z]|$)"#, options: .regularExpression) != nil {
                    return true
                }
                continue
            }
            if lower.contains(marker) { return true }
        }
        return false
    }

    /// Vision-capable models first, each group alphabetical, duplicates removed.
    static func sortedForPicker(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        let unique = ids.filter { seen.insert($0).inserted }
        let vision = unique.filter(likelySupportsVision).sorted()
        let other = unique.filter { !likelySupportsVision($0) }.sorted()
        return vision + other
    }
}

/// Talks to a local (or any OpenAI-compatible) server's model list.
enum LocalModelServer {
    struct Model: Equatable, Identifiable {
        let id: String
        var likelySupportsVision: Bool { ModelCapabilityHint.likelySupportsVision(id) }
    }

    enum ListError: LocalizedError, Equatable {
        case invalidEndpoint
        case unreachable
        case unauthorized
        case serverError(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "That endpoint isn't a valid URL."
            case .unreachable: return "Nothing is answering at that address. Is the server running?"
            case .unauthorized: return "The server wants an API key."
            case .serverError(let code): return "The server answered with status \(code)."
            case .invalidResponse: return "The server answered, but not with a model list."
            }
        }
    }

    /// Parses an OpenAI-style `{ "data": [ { "id": "..." } ] }` body. Also
    /// accepts Ollama's native `/api/tags` shape (`{ "models": [ { "name": "..." } ] }`)
    /// in case a reverse proxy maps that path, and a bare array of ids.
    static func parseModelList(_ data: Data) -> [Model]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let dict = json as? [String: Any] {
            if let entries = dict["data"] as? [[String: Any]] {
                return entries.compactMap { ($0["id"] as? String).map(Model.init(id:)) }
            }
            if let entries = dict["models"] as? [[String: Any]] {
                return entries.compactMap { entry in
                    ((entry["name"] as? String) ?? (entry["model"] as? String)).map(Model.init(id:))
                }
            }
            return nil
        }
        if let ids = json as? [String] {
            return ids.map(Model.init(id:))
        }
        if let entries = json as? [[String: Any]] {
            return entries.compactMap { ($0["id"] as? String).map(Model.init(id:)) }
        }
        return nil
    }

    /// Chooses the model to use when the user left the field empty: the first
    /// vision-capable model, otherwise the first model the server reports.
    static func pickDefaultModel(from ids: [String]) -> String? {
        let ordered = ModelCapabilityHint.sortedForPicker(ids)
        return ordered.first
    }

    /// Fetches the model list for a chat-completions endpoint. Pass an empty
    /// key for servers that don't need one (Ollama, LM Studio by default).
    static func listModels(
        chatCompletionsURL: String,
        apiKey: String?,
        timeout: TimeInterval = 5
    ) async throws -> [Model] {
        guard let url = LocalEndpoint.modelsURL(fromChatCompletionsURL: chatCompletionsURL) else {
            throw ListError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ListError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw ListError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw ListError.unauthorized }
        guard (200...299).contains(http.statusCode) else { throw ListError.serverError(http.statusCode) }
        guard let models = parseModelList(data) else { throw ListError.invalidResponse }
        return models
    }
}
