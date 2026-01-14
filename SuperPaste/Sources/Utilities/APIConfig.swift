import Foundation

/// API configuration with embedded key.
/// The key is lightly obfuscated to prevent casual inspection.
enum APIConfig {
    // MARK: - Anthropic API Configuration

    static let baseURL = "https://api.anthropic.com/v1/messages"
    static let model = "claude-3-haiku-20240307"  // Fast and cost-effective
    static let anthropicVersion = "2023-06-01"

    // MARK: - API Key
    // Base64 encoded for light obfuscation
    private static let obfuscatedKey = "c2stYW50LWFwaTAzLWliQl8tem5zR0xHS1ZWOVk3NUN4dUlLd1JGRmFZZG5fYUNXSXVoVE5tdTM4WEctYllXMHk3VzVwQnZKZ3MtRFc3MWsySUJ3LXVJT0RyQ2FEbmFzSHB3LXpjS3ppQUFB"

    static var apiKey: String {
        guard let data = Data(base64Encoded: obfuscatedKey),
              let key = String(data: data, encoding: .utf8) else {
            return obfuscatedKey  // Return as-is if not base64
        }
        return key
    }

    // MARK: - Request Configuration

    static let timeoutInterval: TimeInterval = 30.0
    static let maxTokens = 1024

    // MARK: - System Prompt

    static let systemPrompt = """
        You are an AI agent operating through an API.

        ## Input
        - You will receive text extracted from the user's clipboard and window context.
        - The text may be incomplete, messy, or lack clear structure.
        - Assume the content was intentionally provided and is relevant to the user's goal.

        ## Your Task
        - Use all available information to infer the user's intent.
        - Determine what response would be most useful if pasted directly into the user's current workflow.
        - Make reasonable assumptions when details are missing, but do not invent specific facts.
        - Prefer clarity, usefulness, and correctness over verbosity.

        ## Output Rules
        - Respond with only the final answer.
        - Do not explain your reasoning.
        - Do not include disclaimers, metadata, or references to the system behavior.
        - Write the response exactly as it should appear when pasted from the clipboard.
        - Match the tone and format implied by the content (for example: email, message, notes, summary, form response).

        ## Quality Bar
        - The output should feel intentional, polished, and ready to use.
        - If multiple interpretations are possible, choose the one that is most likely and most helpful in context.
        - Keep language clear and direct.
        """
}
