import Foundation
import Testing
@testable import SuperPaste

struct LocalEndpointTests {

    @Test func bareHostAndPortBecomesChatCompletionsURL() {
        #expect(LocalEndpoint.chatCompletionsURL(from: "localhost:11434") == "http://localhost:11434/v1/chat/completions")
    }

    @Test func schemeAndHostOnlyGetsV1Path() {
        #expect(LocalEndpoint.chatCompletionsURL(from: "http://localhost:1234") == "http://localhost:1234/v1/chat/completions")
        #expect(LocalEndpoint.chatCompletionsURL(from: "http://localhost:1234/") == "http://localhost:1234/v1/chat/completions")
    }

    @Test func v1BaseGetsLeafAppended() {
        #expect(LocalEndpoint.chatCompletionsURL(from: "http://localhost:11434/v1") == "http://localhost:11434/v1/chat/completions")
        #expect(LocalEndpoint.chatCompletionsURL(from: "http://localhost:11434/v1/") == "http://localhost:11434/v1/chat/completions")
    }

    @Test func fullChatCompletionsURLIsUnchanged() {
        let full = "https://gateway.example.com/openai/v1/chat/completions"
        #expect(LocalEndpoint.chatCompletionsURL(from: full) == full)
    }

    @Test func reverseProxyMountGetsLeafAppended() {
        #expect(LocalEndpoint.chatCompletionsURL(from: "http://nas.local:8080/ollama/v1") == "http://nas.local:8080/ollama/v1/chat/completions")
    }

    @Test func whitespaceIsTrimmed() {
        #expect(LocalEndpoint.chatCompletionsURL(from: "  http://localhost:1234/v1  ") == "http://localhost:1234/v1/chat/completions")
        #expect(LocalEndpoint.chatCompletionsURL(from: "   ") == "")
    }

    @Test func modelsURLSitsBesideChatCompletions() {
        let url = LocalEndpoint.modelsURL(fromChatCompletionsURL: "http://localhost:11434/v1/chat/completions")
        #expect(url?.absoluteString == "http://localhost:11434/v1/models")
    }

    @Test func modelsURLDerivesFromAnyAcceptedInput() {
        #expect(LocalEndpoint.modelsURL(fromChatCompletionsURL: "localhost:1234")?.absoluteString == "http://localhost:1234/v1/models")
        #expect(LocalEndpoint.modelsURL(fromChatCompletionsURL: "https://gateway.example.com/openai/v1/chat/completions")?.absoluteString == "https://gateway.example.com/openai/v1/models")
    }

    @Test func modelsURLDropsQueryString() {
        let url = LocalEndpoint.modelsURL(fromChatCompletionsURL: "http://localhost:8080/v1/chat/completions?token=abc")
        #expect(url?.absoluteString == "http://localhost:8080/v1/models")
    }

    @Test func displayHostShowsHostAndPortOnly() {
        #expect(LocalEndpoint.displayHost("http://localhost:11434/v1/chat/completions") == "localhost:11434")
        #expect(LocalEndpoint.displayHost("https://api.openai.com/v1/chat/completions") == "api.openai.com")
        #expect(LocalEndpoint.displayHost("localhost:1234") == "localhost:1234")
    }

    @Test func loopbackDetection() {
        #expect(LocalEndpoint.isLoopback("http://localhost:11434"))
        #expect(LocalEndpoint.isLoopback("127.0.0.1:1234"))
        #expect(LocalEndpoint.isLoopback("http://127.0.0.2:8080/v1"))
        #expect(LocalEndpoint.isLoopback("http://ollama.localhost:11434"))
        #expect(!LocalEndpoint.isLoopback("http://192.168.1.20:11434"))
        #expect(!LocalEndpoint.isLoopback("https://api.openai.com/v1/chat/completions"))
        #expect(!LocalEndpoint.isLoopback(""))
    }

    @Test func defaultLocalEndpointsAreLoopback() {
        #expect(LocalEndpoint.isLoopback(LLMProviderID.ollama.endpointURL))
        #expect(LocalEndpoint.isLoopback(LLMProviderID.lmstudio.endpointURL))
    }
}

struct ModelCapabilityHintTests {

    @Test func recognizesCommonVisionModelIDs() {
        for id in [
            "qwen3-vl:8b", "qwen2.5vl:7b", "llava:13b", "llama3.2-vision:11b", "gemma4:12b",
            "gemma3:4b", "minicpm-v:8b", "moondream:latest", "mistral-small3.1:24b",
            "lmstudio-community/Qwen3-VL-8B-Instruct-GGUF", "pixtral-12b", "granite3.2-vision:2b",
        ] {
            #expect(ModelCapabilityHint.likelySupportsVision(id), "expected \(id) to look vision-capable")
        }
    }

    @Test func doesNotFlagTextOnlyModels() {
        for id in ["llama3.1:8b", "qwen3:8b", "mistral:7b", "deepseek-r1:14b", "codellama:7b", "phi4:14b", "nomic-embed-text"] {
            #expect(!ModelCapabilityHint.likelySupportsVision(id), "expected \(id) to look text-only")
        }
    }

    @Test func shortVLMarkerNeedsAWordBoundary() {
        // "vl" buried inside an unrelated word must not count.
        #expect(!ModelCapabilityHint.likelySupportsVision("devlab-7b"))
        #expect(ModelCapabilityHint.likelySupportsVision("qwen3-vl"))
        #expect(ModelCapabilityHint.likelySupportsVision("Qwen3-VL:32b"))
    }

    @Test func pickerOrderPutsVisionModelsFirstAndDedupes() {
        let ordered = ModelCapabilityHint.sortedForPicker(["mistral:7b", "qwen3-vl:8b", "llama3.1:8b", "llava:13b", "qwen3-vl:8b"])
        #expect(ordered == ["llava:13b", "qwen3-vl:8b", "llama3.1:8b", "mistral:7b"])
    }
}

struct LocalModelServerTests {

    @Test func parsesOpenAIStyleModelList() throws {
        let body = #"{"object":"list","data":[{"id":"qwen3-vl:8b","object":"model","owned_by":"library"},{"id":"llama3.1:8b","object":"model"}]}"#
        let models = try #require(LocalModelServer.parseModelList(Data(body.utf8)))
        #expect(models.map(\.id) == ["qwen3-vl:8b", "llama3.1:8b"])
        #expect(models[0].likelySupportsVision)
        #expect(!models[1].likelySupportsVision)
    }

    @Test func parsesOllamaNativeTagsShape() throws {
        let body = #"{"models":[{"name":"llava:13b","model":"llava:13b","size":1},{"name":"mistral:7b"}]}"#
        let models = try #require(LocalModelServer.parseModelList(Data(body.utf8)))
        #expect(models.map(\.id) == ["llava:13b", "mistral:7b"])
    }

    @Test func parsesBareArrays() throws {
        let ids = try #require(LocalModelServer.parseModelList(Data(#"["a","b"]"#.utf8)))
        #expect(ids.map(\.id) == ["a", "b"])
        let objects = try #require(LocalModelServer.parseModelList(Data(#"[{"id":"c"}]"#.utf8)))
        #expect(objects.map(\.id) == ["c"])
    }

    @Test func rejectsBodiesThatAreNotModelLists() {
        #expect(LocalModelServer.parseModelList(Data("not json".utf8)) == nil)
        #expect(LocalModelServer.parseModelList(Data(#"{"error":"nope"}"#.utf8)) == nil)
        #expect(LocalModelServer.parseModelList(Data(#"{"data":[]}"#.utf8)) == [])
    }

    @Test func defaultModelPrefersVision() {
        #expect(LocalModelServer.pickDefaultModel(from: ["mistral:7b", "llama3.1:8b", "qwen3-vl:8b"]) == "qwen3-vl:8b")
        #expect(LocalModelServer.pickDefaultModel(from: ["mistral:7b", "llama3.1:8b"]) == "llama3.1:8b")
        #expect(LocalModelServer.pickDefaultModel(from: []) == nil)
    }

    @Test func unreachableServerThrowsUnreachable() async {
        // Port 9 (discard) is not listening on CI runners; the connection is refused immediately.
        do {
            _ = try await LocalModelServer.listModels(chatCompletionsURL: "http://127.0.0.1:9/v1/chat/completions", apiKey: nil, timeout: 2)
            Issue.record("expected the request to fail")
        } catch let error as LocalModelServer.ListError {
            #expect(error == .unreachable)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
