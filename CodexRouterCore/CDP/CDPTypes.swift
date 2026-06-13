import Foundation

/// Represents a debuggable page target from /json endpoint.
public struct CDPTarget: Codable, Sendable {
    public let id: String
    public let type: String
    public let title: String
    public let url: String
    public let webSocketDebuggerUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case url
        case webSocketDebuggerUrl
    }
}

/// CDP evaluation result.
public struct CDPEvaluationResult: Sendable {
    public let value: String?
    public let exceptionDetails: String?
}

/// Errors for CDP operations.
public enum CDPError: Error, LocalizedError {
    case noTargetsFound
    case noWebSocketURL
    case evaluationFailed(String)
    case connectionFailed(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .noTargetsFound: return "No debuggable Codex page targets found"
        case .noWebSocketURL: return "No WebSocket debugger URL available"
        case .evaluationFailed(let msg): return "JS evaluation failed: \(msg)"
        case .connectionFailed(let msg): return "CDP connection failed: \(msg)"
        case .timeout: return "CDP operation timed out"
        }
    }
}

/// CDP settings exposed to injected JavaScript via /settings/get endpoint.
public struct CDPInjectionSettings: Codable, Sendable {
    public var codexAppPluginEntryUnlock: Bool
    public var codexAppForcePluginInstall: Bool
    public var enhancementsEnabled: Bool
    public var launchMode: String
    public var codexAppVersion: String
    public var codexAppPluginMarketplaceUnlock: Bool

    public init(
        codexAppPluginEntryUnlock: Bool = true,
        codexAppForcePluginInstall: Bool = true,
        enhancementsEnabled: Bool = true,
        launchMode: String = "patch",
        codexAppVersion: String = "",
        codexAppPluginMarketplaceUnlock: Bool = true
    ) {
        self.codexAppPluginEntryUnlock = codexAppPluginEntryUnlock
        self.codexAppForcePluginInstall = codexAppForcePluginInstall
        self.enhancementsEnabled = enhancementsEnabled
        self.launchMode = launchMode
        self.codexAppVersion = codexAppVersion
        self.codexAppPluginMarketplaceUnlock = codexAppPluginMarketplaceUnlock
    }
}
