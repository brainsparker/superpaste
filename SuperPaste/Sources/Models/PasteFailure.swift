import Foundation

struct PasteFailure: Equatable {
    enum Code: String {
        case screenPermission, accessibilityPermission, capture, protectedContext
        case destinationChanged, pasteUnavailable, clipboardChanged
        case network, rateLimited, dailyLimit, trialExpired, licenseInvalid
        case providerConfiguration, providerResponse, timeout, unknown
    }

    let code: Code
    let message: String
    let recovery: HUDRecoveryAction?

    static func provider(_ error: LLMService.LLMError) -> Self {
        let code: Code
        let recovery: HUDRecoveryAction?
        switch error {
        case .networkError: (code, recovery) = (.network, .retry)
        case .rateLimited: (code, recovery) = (.rateLimited, .retry)
        case .dailyLimitReached: (code, recovery) = (.dailyLimit, nil)
        case .trialExpired: (code, recovery) = (.trialExpired, .openSettings)
        case .licenseInvalid: (code, recovery) = (.licenseInvalid, .openSettings)
        case .serverError, .invalidResponse, .emptyResponse, .truncatedResponse:
            (code, recovery) = (.providerResponse, .retry)
        case .timeout: (code, recovery) = (.timeout, .retry)
        case .invalidAPIKey, .providerNotConfigured:
            (code, recovery) = (.providerConfiguration, .openSettings)
        case .imageEncodingFailed, .unclearContext:
            (code, recovery) = (.capture, nil)
        }
        return Self(code: code, message: error.userFriendlyMessage, recovery: recovery)
    }

    static let destinationChanged = Self(
        code: .destinationChanged,
        message: "Your reply is ready, but the destination changed or couldn't be verified. Copy it when you're ready.",
        recovery: .copyResponse
    )
}
