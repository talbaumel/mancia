import Foundation

struct LLMRequestOverrides: Equatable, Sendable {
    let model: String?
    let reasoningEffort: String?

    init?(model: String?, reasoningEffort: String?) {
        let model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningEffort = reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model?.isEmpty == false || reasoningEffort?.isEmpty == false else { return nil }
        self.model = model?.isEmpty == false ? model : nil
        self.reasoningEffort = reasoningEffort?.isEmpty == false ? reasoningEffort : nil
    }
}

/// Availability of a provider, surfaced in menus and settings.
enum ProviderStatus: Sendable, Equatable {
    case ready
    case notFound
    case error(String)

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .notFound: return "Not found"
        case .error: return "Error"
        }
    }

    var detail: String {
        switch self {
        case .ready: return "Copilot CLI is available."
        case .notFound: return ProviderError.notFound.localizedDescription
        case .error(let message): return message
        }
    }

    var menuMark: String {
        switch self {
        case .ready: return "✓"
        case .notFound, .error: return "⚠︎"
        }
    }
}

/// A pluggable large-language-model backend.
protocol LLMProvider: Sendable {
    var displayName: String { get }
    func complete(_ prompt: String) async throws -> String
    func complete(_ prompt: String, overrides: LLMRequestOverrides?) async throws -> String
    func checkAvailability() async -> ProviderStatus
}

extension LLMProvider {
    func complete(_ prompt: String, overrides: LLMRequestOverrides?) async throws -> String {
        try await complete(prompt)
    }
}

/// Optional hook for providers that can report the models their backend offers
/// right now, so the settings picker isn't limited to a cached list.
protocol ModelListingProvider: LLMProvider {
    func availableModels() async -> [CopilotModel]
}

/// Optional latency hook for providers that can keep a one-shot session warm
/// while the floating panel is open.
protocol WarmableLLMProvider: LLMProvider {
    func prepareForPanel() async
    func prepareForPanel(overrides: [LLMRequestOverrides]) async
    func panelDidClose() async
}

extension WarmableLLMProvider {
    func prepareForPanel(overrides: [LLMRequestOverrides]) async {
        await prepareForPanel()
    }
}
