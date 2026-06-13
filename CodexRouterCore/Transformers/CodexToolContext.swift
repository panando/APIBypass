import Foundation

// MARK: - Constants

private let toolSearchProxyName = "tool_search"
private let customToolInputField = "input"
private let chatToolNameMaxLen = 64
private let customToolInputDescription = "Raw string input for the original custom tool. Preserve formatting exactly and follow the original tool definition embedded in the description."
private let customToolPreservedMetadataHeading = "Original tool definition:"

// MARK: - Tool kind

public enum CodexToolKind: Sendable {
    case function
    case namespace
    case custom
    case toolSearch
}

// MARK: - Tool spec

public struct CodexToolSpec: Sendable {
    public let kind: CodexToolKind
    public let name: String
    public let namespace: String?

    public init(kind: CodexToolKind, name: String, namespace: String? = nil) {
        self.kind = kind
        self.name = name
        self.namespace = namespace
    }
}

// MARK: - Tool context

/// Maps tool names between Responses API and Chat Completions format for round-trip fidelity.
/// Follows cc-switch's CodexToolContext in transform_codex_chat.rs.
/// @unchecked Sendable: chatTools uses [String: Any] for JSON-like tool definitions.
/// All contained values are JSON-safe Sendable types; used within actor-isolated context.
public struct CodexToolContext: @unchecked Sendable {

    public private(set) var chatTools: [[String: Any]] = []
    private var seenChatNames: Set<String> = []
    private var chatNameToSpec: [String: CodexToolSpec] = [:]
    private var namespaceNameToChatName: [String: String] = [:] // "namespace\u{1f}name" → chatName

    public init() {}

    /// Build tool context from a Responses API request body.
    public init(responsesBody: [String: Any]) {
        if let tools = responsesBody["tools"] as? [[String: Any]] {
            for tool in tools {
                addResponseTool(tool)
            }
        }
        if let input = responsesBody["input"] {
            collectToolSearchOutputTools(input)
        }
    }

    // MARK: - Public lookup

    public func lookupChatName(_ chatName: String) -> CodexToolSpec? {
        chatNameToSpec[chatName]
    }

    public func isCustomToolChatName(_ chatName: String) -> Bool {
        if let spec = lookupChatName(chatName), case .custom = spec.kind {
            return true
        }
        return false
    }

    /// Reverse mapping: given a Responses function name + namespace, return the Chat tool name.
    public func chatNameForResponseFunction(name: String, namespace: String?) -> String {
        if let ns = namespace, !ns.isEmpty {
            let key = "\(ns)\u{1f}\(name)"
            if let chatName = namespaceNameToChatName[key] {
                return chatName
            }
            return flattenNamespaceToolName(namespace: ns, name: name)
        }
        return name
    }

    // MARK: - Build from Responses tools

    private mutating func addChatTool(chatName: String, spec: CodexToolSpec, chatTool: [String: Any]) {
        guard !chatName.trimmingCharacters(in: .whitespaces).isEmpty,
              !seenChatNames.contains(chatName) else { return }
        seenChatNames.insert(chatName)
        if let ns = spec.namespace {
            let key = "\(ns)\u{1f}\(spec.name)"
            namespaceNameToChatName[key] = chatName
        }
        chatNameToSpec[chatName] = spec
        chatTools.append(chatTool)
    }

    private mutating func addFunctionTool(_ tool: [String: Any], namespace: String?) {
        guard let originalName = responsesToolName(tool) else { return }
        let chatName: String
        if let ns = namespace {
            chatName = flattenNamespaceToolName(namespace: ns, name: originalName)
        } else {
            chatName = originalName
        }
        guard let chatTool = responsesFunctionToolToChat(tool, chatName: chatName) else { return }
        let spec = CodexToolSpec(
            kind: namespace != nil ? .namespace : .function,
            name: originalName,
            namespace: namespace
        )
        addChatTool(chatName: chatName, spec: spec, chatTool: chatTool)
    }

    private mutating func addCustomTool(_ tool: [String: Any]) {
        guard let name = responsesToolName(tool) else { return }
        let description = responsesCustomToolDescription(tool)
        let chatTool: [String: Any] = [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": [
                        customToolInputField: [
                            "type": "string",
                            "description": customToolInputDescription
                        ]
                    ],
                    "required": [customToolInputField]
                ]
            ]
        ]
        let spec = CodexToolSpec(kind: .custom, name: name)
        addChatTool(chatName: name, spec: spec, chatTool: chatTool)
    }

    private mutating func addToolSearchTool() {
        let chatTool: [String: Any] = [
            "type": "function",
            "function": [
                "name": toolSearchProxyName,
                "description": "Search and load Codex tools, plugins, connectors, and MCP namespaces for the current task.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Search query for tools or connectors to load."
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of tool groups to return."
                        ]
                    ],
                    "required": ["query"]
                ]
            ]
        ]
        let spec = CodexToolSpec(kind: .toolSearch, name: toolSearchProxyName)
        addChatTool(chatName: toolSearchProxyName, spec: spec, chatTool: chatTool)
    }

    private mutating func addNamespaceTool(_ namespaceTool: [String: Any]) {
        guard let namespace = namespaceTool["name"] as? String else { return }
        let children = (namespaceTool["tools"] as? [[String: Any]]) ?? (namespaceTool["children"] as? [[String: Any]]) ?? []
        for child in children {
            if (child["type"] as? String) == "function" {
                addFunctionTool(child, namespace: namespace)
            }
        }
    }

    public mutating func addResponseTool(_ tool: Any) {
        if let name = tool as? String {
            addCustomTool(["type": "custom", "name": name])
            return
        }
        guard let dict = tool as? [String: Any] else { return }
        switch dict["type"] as? String {
        case "function": addFunctionTool(dict, namespace: nil)
        case "custom": addCustomTool(dict)
        case "tool_search": addToolSearchTool()
        case "namespace": addNamespaceTool(dict)
        default: break
        }
    }

    // MARK: - Collect tools from history (tool_search_output)

    private mutating func collectToolSearchOutputTools(_ value: Any) {
        if let items = value as? [Any] {
            for item in items { collectToolSearchOutputTools(item) }
        } else if let dict = value as? [String: Any] {
            if dict["type"] as? String == "tool_search_output" {
                if let tools = dict["tools"] as? [Any] {
                    for tool in tools { addResponseTool(tool) }
                }
            }
            for (_, v) in dict { collectToolSearchOutputTools(v) }
        }
    }

    // MARK: - Helpers

    private func responsesToolName(_ tool: [String: Any]) -> String? {
        let name = (tool["function"] as? [String: Any])?["name"] as? String
            ?? tool["name"] as? String
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return name
    }

    private func responsesCustomToolDescription(_ tool: [String: Any]) -> String {
        var desc = customToolPreservedMetadataHeading
        desc += "\n```json\n"
        if let data = try? JSONSerialization.data(withJSONObject: tool, options: .sortedKeys),
           let json = String(data: data, encoding: .utf8) {
            desc += json
        }
        desc += "\n```"
        return desc
    }

    private func responsesFunctionToolToChat(_ tool: [String: Any], chatName: String) -> [String: Any]? {
        guard tool["type"] as? String == "function" else { return nil }

        if let function = tool["function"] as? [String: Any] {
            var chatTool: [String: Any] = ["type": "function", "function": function]
            if var funcObj = chatTool["function"] as? [String: Any] {
                funcObj["name"] = chatName
                if let strict = tool["strict"] { funcObj["strict"] = strict }
                chatTool["function"] = funcObj
            }
            return chatTool
        }

        // Flat Responses format → wrap in function
        var function: [String: Any] = [
            "name": chatName,
            "description": tool["description"] ?? NSNull(),
            "parameters": tool["parameters"] ?? ["type": "object"]
        ]
        if let strict = tool["strict"] { function["strict"] = strict }

        return ["type": "function", "function": function]
    }

    private func flattenNamespaceToolName(namespace: String, name: String) -> String {
        let fullName = "\(namespace)__\(name)"
        if fullName.count <= chatToolNameMaxLen { return fullName }

        let hash = sha256Prefix(fullName, length: 8)
        let suffix = "__\(hash)"
        let prefixLen = chatToolNameMaxLen - suffix.count
        let prefix = String(fullName.prefix(prefixLen))
        return "\(prefix)\(suffix)"
    }

    private func sha256Prefix(_ input: String, length: Int) -> String {
        // Simple deterministic hash for tool name shortening
        var hash = 0
        for byte in input.utf8 {
            hash = ((hash << 5) &- hash) &+ Int(byte)
        }
        let positive = abs(hash)
        return String(format: "%0\(length)x", positive % (1 << (length * 4)))
    }
}
