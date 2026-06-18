# Thinking Protocol Override Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the "Reasoning Mode Override" feature so it supports multiple upstream thinking protocols (`enable_thinking` / `reasoning_effort` / `anthropic_native` / `none`), auto-infers the right protocol from provider baseURL + model name, and explicitly emits the off state.

**Architecture:** Add a `protocol` field to `ThinkingConfig`. `ProxyEngine.injectParameters` becomes protocol-aware for same-format paths. `FormatTranslator.translateRequest` receives `ThinkingConfig` out-of-band for cross-format translation. UI adds a protocol Picker that switches controls dynamically. Infer defaults from baseURL/model; user can override.

**Tech Stack:** Swift / SwiftUI / Hummingbird / XCTest

---

## File Structure

| File | Responsibility | Action |
|------|---------------|--------|
| `APIBypass/Models/ModelMapping.swift` | `ThinkingConfig` model + `Protocol` enum + `infer` | Modify |
| `APIBypass/Core/ProxyEngine.swift` | Same-format thinking injection (protocol-aware) | Modify |
| `APIBypass/Core/FormatTranslator.swift` | Cross-format thinking translation (protocol-aware) | Modify |
| `APIBypass/Core/HTTPServer.swift` | Pass `thinkingConfig` to `translateRequest` | Modify |
| `APIBypass/Core/LocalizationManager.swift` | New L10n keys for protocol UI | Modify |
| `APIBypass/UI/Views/MappingEditForm.swift` | Protocol Picker + dynamic controls | Modify |
| `APIBypass/UI/Views/NewMappingView.swift` | State + infer + save | Modify |
| `APIBypass/UI/Views/MappingDetailView.swift` | State + load + save | Modify |
| `APIBypass/UI/Views/MappingCardView.swift` | State + load + save | Modify |
| `APIBypassTests/ProxyEngineTests.swift` | Protocol-specific injection tests | Modify |
| `APIBypassTests/ModelMappingTests.swift` | Codable backward-compat test | Modify |
| `Info.plist` | Version bump 0.7.7 → 0.7.8 | Modify |
| `RELEASE_NOTES.md` | v0.7.8 entry | Modify |

---

## Task 1: Extend `ThinkingConfig` with protocol + effort

**Files:**
- Modify: `APIBypass/Models/ModelMapping.swift:3-11`

- [ ] **Step 1: Write the failing test**

Add to `APIBypassTests/ModelMappingTests.swift`:

```swift
func testThinkingConfigCodableWithProtocol() throws {
    let config = ThinkingConfig(
        enabled: true,
        budgetTokens: 5000,
        protocol: .reasoning_effort,
        effort: "high"
    )
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(ThinkingConfig.self, from: data)
    XCTAssertEqual(decoded.enabled, true)
    XCTAssertEqual(decoded.budgetTokens, 5000)
    XCTAssertEqual(decoded.protocol, .reasoning_effort)
    XCTAssertEqual(decoded.effort, "high")
}

func testThinkingConfigBackwardCompatOldFormat() throws {
    // Old format: no protocol/effort fields
    let json = #"{"enabled":true,"budgetTokens":10000}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(ThinkingConfig.self, from: json)
    XCTAssertEqual(decoded.enabled, true)
    XCTAssertEqual(decoded.budgetTokens, 10000)
    XCTAssertEqual(decoded.protocol, .enable_thinking) // default fallback
    XCTAssertNil(decoded.effort)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelMappingTests`
Expected: FAIL — `ThinkingConfig` has no `protocol`/`effort` members

- [ ] **Step 3: Implement the model change**

Replace `APIBypass/Models/ModelMapping.swift:3-11` with:

```swift
struct ThinkingConfig: Codable, Equatable {
    enum `Protocol`: String, Codable, CaseIterable {
        case enable_thinking      // GLM / Qwen / Kimi / Ark
        case reasoning_effort     // OpenAI o-series
        case anthropic_native     // Anthropic 兼容上游
        case none                 // 不发字段（模型自身即开关）

        var displayName: String {
            switch self {
            case .enable_thinking: return "enable_thinking"
            case .reasoning_effort: return "reasoning_effort"
            case .anthropic_native: return "thinking (Anthropic)"
            case .none: return "none"
            }
        }
    }

    let enabled: Bool
    let budgetTokens: Int?
    let `protocol`: `Protocol`
    let effort: String?

    init(enabled: Bool,
         budgetTokens: Int? = nil,
         `protocol`: `Protocol` = .enable_thinking,
         effort: String? = nil) {
        self.enabled = enabled
        self.budgetTokens = budgetTokens
        self.`protocol` = `protocol`
        self.effort = effort
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, budgetTokens, `protocol`, effort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        budgetTokens = try c.decodeIfPresent(Int.self, forKey: .budgetTokens)
        `protocol` = try c.decodeIfPresent(`Protocol`.self, forKey: .protocol) ?? .enable_thinking
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelMappingTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add APIBypass/Models/ModelMapping.swift APIBypassTests/ModelMappingTests.swift
git commit -m "feat: extend ThinkingConfig with protocol and effort fields"
```

---

## Task 2: Add protocol inference

**Files:**
- Modify: `APIBypass/Models/ModelMapping.swift` (append extension)

- [ ] **Step 1: Write the failing test**

Add to `APIBypassTests/ModelMappingTests.swift`:

```swift
func testInferProtocolGLM() {
    let p = ThinkingConfig.Protocol.infer(baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-5.2")
    XCTAssertEqual(p, .enable_thinking)
}

func testInferProtocolOpenAIOSeries() {
    let p = ThinkingConfig.Protocol.infer(baseURL: "https://api.openai.com/v1", model: "o3-mini")
    XCTAssertEqual(p, .reasoning_effort)
}

func testInferProtocolDeepSeekReasoner() {
    let p = ThinkingConfig.Protocol.infer(baseURL: "https://api.deepseek.com/v1", model: "deepseek-r1")
    XCTAssertEqual(p, .none)
}

func testInferProtocolAnthropic() {
    let p = ThinkingConfig.Protocol.infer(baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-6")
    XCTAssertEqual(p, .anthropic_native)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelMappingTests`
Expected: FAIL — `infer` does not exist

- [ ] **Step 3: Implement inference**

Append to `APIBypass/Models/ModelMapping.swift` (after the `ThinkingConfig` struct):

```swift
extension ThinkingConfig.`Protocol` {
    static func infer(baseURL: String, model: String) -> ThinkingConfig.`Protocol` {
        let lower = baseURL.lowercased()
        let m = model.lowercased()

        if lower.contains("anthropic") { return .anthropic_native }
        if m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") { return .reasoning_effort }
        if m.hasPrefix("deepseek-r") { return .none }
        if lower.contains("bigmodel") || lower.contains("z.ai")
            || lower.contains("moonshot") || lower.contains("aliyuncs")
            || lower.contains("volces") || lower.contains("ark.cn-beijing") {
            return .enable_thinking
        }
        return .enable_thinking
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelMappingTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add APIBypass/Models/ModelMapping.swift APIBypassTests/ModelMappingTests.swift
git commit -m "feat: add ThinkingConfig.Protocol.infer for auto-detecting upstream protocol"
```

---

## Task 3: Make `ProxyEngine.injectParameters` protocol-aware (OpenAI branch)

**Files:**
- Modify: `APIBypass/Core/ProxyEngine.swift:74-90`

- [ ] **Step 1: Write the failing test**

Add to `APIBypassTests/ProxyEngineTests.swift`:

```swift
func testTransformOpenAIRequest_enableThinkingProtocol() throws {
    let mapping = ModelMapping(
        name: "Test", incomingModel: "glm", actualModel: "glm-5.2",
        apiProvider: .openai, baseURL: URL(string: "https://open.bigmodel.cn")!,
        parameters: InjectedParameters(
            thinking: ThinkingConfig(enabled: true, budgetTokens: 8000, protocol: .enable_thinking),
            thinkingOverrideEnabled: true
        )
    )
    let body: [String: Any] = ["model": "glm", "messages": [["role": "user", "content": "hi"]]]
    let data = try JSONSerialization.data(withJSONObject: body)
    let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
    let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
    XCTAssertEqual(json["enable_thinking"] as? Bool, true)
    XCTAssertEqual(json["thinking_budget"] as? Int, 8000)
}

func testTransformOpenAIRequest_enableThinkingProtocolOff() throws {
    let mapping = ModelMapping(
        name: "Test", incomingModel: "glm", actualModel: "glm-5.2",
        apiProvider: .openai, baseURL: URL(string: "https://open.bigmodel.cn")!,
        parameters: InjectedParameters(
            thinking: ThinkingConfig(enabled: false, protocol: .enable_thinking),
            thinkingOverrideEnabled: true
        )
    )
    let body: [String: Any] = ["model": "glm", "messages": [["role": "user", "content": "hi"]]]
    let data = try JSONSerialization.data(withJSONObject: body)
    let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
    let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
    XCTAssertEqual(json["enable_thinking"] as? Bool, false)
}

func testTransformOpenAIRequest_reasoningEffortProtocol() throws {
    let mapping = ModelMapping(
        name: "Test", incomingModel: "o3", actualModel: "o3-mini",
        apiProvider: .openai, baseURL: URL(string: "https://api.openai.com")!,
        parameters: InjectedParameters(
            thinking: ThinkingConfig(enabled: true, protocol: .reasoning_effort, effort: "high"),
            thinkingOverrideEnabled: true
        )
    )
    let body: [String: Any] = ["model": "o3", "messages": [["role": "user", "content": "hi"]]]
    let data = try JSONSerialization.data(withJSONObject: body)
    let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
    let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
    XCTAssertEqual(json["reasoning_effort"] as? String, "high")
    XCTAssertNil(json["enable_thinking"])
}

func testTransformOpenAIRequest_noneProtocolEmitsNothing() throws {
    let mapping = ModelMapping(
        name: "Test", incomingModel: "ds", actualModel: "deepseek-r1",
        apiProvider: .openai, baseURL: URL(string: "https://api.deepseek.com")!,
        parameters: InjectedParameters(
            thinking: ThinkingConfig(enabled: true, protocol: .none),
            thinkingOverrideEnabled: true
        )
    )
    let body: [String: Any] = ["model": "ds", "messages": [["role": "user", "content": "hi"]]]
    let data = try JSONSerialization.data(withJSONObject: body)
    let transformed = try engine.transformRequest(data: data, mapping: mapping, format: .openai)
    let json = try JSONSerialization.jsonObject(with: transformed) as! [String: Any]
    XCTAssertNil(json["enable_thinking"])
    XCTAssertNil(json["reasoning_effort"])
    XCTAssertNil(json["thinking"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProxyEngineTests`
Expected: FAIL — current code always emits `enable_thinking` regardless of protocol

- [ ] **Step 3: Implement protocol-aware injection**

Replace `APIBypass/Core/ProxyEngine.swift:74-90` (the thinking block inside `injectParameters`) with:

```swift
        // 思考模式控制 (Anthropic + OpenAI 兼容)
        if let thinking = params.thinking, params.thinkingOverrideEnabled == true {
            switch format {
            case .anthropic:
                // Anthropic 上游始终用原生 thinking 协议，protocol 字段不影响
                if thinking.enabled {
                    var thinkingDict: [String: Any] = ["type": "enabled"]
                    if let budget = thinking.budgetTokens {
                        thinkingDict["budget_tokens"] = budget
                    }
                    json["thinking"] = thinkingDict
                } else {
                    json["thinking"] = ["type": "disabled"]
                }
            case .openai:
                switch thinking.`protocol` {
                case .enable_thinking:
                    json["enable_thinking"] = thinking.enabled
                    if thinking.enabled, let budget = thinking.budgetTokens {
                        json["thinking_budget"] = budget
                    }
                case .reasoning_effort:
                    if thinking.enabled {
                        json["reasoning_effort"] = thinking.effort ?? "medium"
                    }
                case .anthropic_native:
                    if thinking.enabled {
                        var t: [String: Any] = ["type": "enabled"]
                        if let budget = thinking.budgetTokens { t["budget_tokens"] = budget }
                        json["thinking"] = t
                    } else {
                        json["thinking"] = ["type": "disabled"]
                    }
                case .none:
                    break
                }
            }
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProxyEngineTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add APIBypass/Core/ProxyEngine.swift APIBypassTests/ProxyEngineTests.swift
git commit -m "feat: protocol-aware thinking injection in ProxyEngine (OpenAI branch)"
```

---

## Task 4: Make `FormatTranslator.anthropicToOpenAIRequest` protocol-aware

**Files:**
- Modify: `APIBypass/Core/FormatTranslator.swift:168-226` (signature + thinking block)
- Modify: `APIBypass/Core/FormatTranslator.swift:435-449` (`translateRequest` signature)

- [ ] **Step 1: Write the failing test**

Add to `APIBypassTests/ProxyEngineTests.swift`:

```swift
func testAnthropicToOpenAI_reasoningEffortProtocol() throws {
    let translator = FormatTranslator()
    let anthropicBody: [String: Any] = [
        "model": "o3",
        "messages": [["role": "user", "content": "hi"]],
        "max_tokens": 1024,
        "thinking": ["type": "enabled"]
    ]
    let data = try JSONSerialization.data(withJSONObject: anthropicBody)
    let translated = try translator.translateRequest(
        data, from: .anthropic, to: .openai,
        thinkingConfig: ThinkingConfig(enabled: true, protocol: .reasoning_effort, effort: "high")
    )
    let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
    XCTAssertEqual(json["reasoning_effort"] as? String, "high")
    XCTAssertNil(json["enable_thinking"])
    XCTAssertNil(json["thinking"])
}

func testAnthropicToOpenAI_noneProtocolStripsThinking() throws {
    let translator = FormatTranslator()
    let anthropicBody: [String: Any] = [
        "model": "ds", "messages": [["role": "user", "content": "hi"]],
        "max_tokens": 1024,
        "thinking": ["type": "enabled"]
    ]
    let data = try JSONSerialization.data(withJSONObject: anthropicBody)
    let translated = try translator.translateRequest(
        data, from: .anthropic, to: .openai,
        thinkingConfig: ThinkingConfig(enabled: true, protocol: .none)
    )
    let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
    XCTAssertNil(json["enable_thinking"])
    XCTAssertNil(json["reasoning_effort"])
    XCTAssertNil(json["thinking"])
}

func testAnthropicToOpenAI_anthropicNativePreservesThinking() throws {
    let translator = FormatTranslator()
    let anthropicBody: [String: Any] = [
        "model": "claude", "messages": [["role": "user", "content": "hi"]],
        "max_tokens": 1024,
        "thinking": ["type": "enabled", "budget_tokens": 5000]
    ]
    let data = try JSONSerialization.data(withJSONObject: anthropicBody)
    let translated = try translator.translateRequest(
        data, from: .anthropic, to: .openai,
        thinkingConfig: ThinkingConfig(enabled: true, budgetTokens: 5000, protocol: .anthropic_native)
    )
    let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
    let thinking = json["thinking"] as? [String: Any]
    XCTAssertEqual(thinking?["type"] as? String, "enabled")
    XCTAssertEqual(thinking?["budget_tokens"] as? Int, 5000)
    XCTAssertNil(json["enable_thinking"])
}

func testAnthropicToOpenAI_enableThinkingOffEmitsFalse() throws {
    let translator = FormatTranslator()
    let anthropicBody: [String: Any] = [
        "model": "glm", "messages": [["role": "user", "content": "hi"]],
        "max_tokens": 1024,
        "thinking": ["type": "disabled"]
    ]
    let data = try JSONSerialization.data(withJSONObject: anthropicBody)
    let translated = try translator.translateRequest(
        data, from: .anthropic, to: .openai,
        thinkingConfig: ThinkingConfig(enabled: false, protocol: .enable_thinking)
    )
    let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
    XCTAssertEqual(json["enable_thinking"] as? Bool, false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProxyEngineTests`
Expected: FAIL — `translateRequest` doesn't accept `thinkingConfig` param

- [ ] **Step 3: Update `translateRequest` signature**

Replace `APIBypass/Core/FormatTranslator.swift:435-449` with:

```swift
    func translateRequest(_ data: Data, from source: APIFormat, to target: APIFormat, thinkingConfig: ThinkingConfig? = nil) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProxyError.invalidJSON
        }
        let result: [String: Any]
        switch (source, target) {
        case (.anthropic, .openai):
            result = anthropicToOpenAIRequest(json, thinkingConfig: thinkingConfig)
        case (.openai, .anthropic):
            result = openAIToAnthropicRequest(json)
        default:
            return data
        }
        return try JSONSerialization.data(withJSONObject: result)
    }
```

- [ ] **Step 4: Update `anthropicToOpenAIRequest` signature + thinking block**

Replace `APIBypass/Core/FormatTranslator.swift:168` (the function declaration line) with:

```swift
    func anthropicToOpenAIRequest(_ json: [String: Any], thinkingConfig: ThinkingConfig? = nil) -> [String: Any] {
```

Then replace the thinking block at `APIBypass/Core/FormatTranslator.swift:199-209` (the `// thinking → enable_thinking` comment through the closing `}`) with:

```swift
        // thinking → protocol-specific fields
        if let thinking = json["thinking"] as? [String: Any] {
            let proto = thinkingConfig?.protocol ?? .enable_thinking
            let type = thinking["type"] as? String ?? ""
            let enabled = (type == "enabled")

            switch proto {
            case .enable_thinking:
                out["enable_thinking"] = enabled
                if enabled, let budget = thinking["budget_tokens"] as? Int {
                    out["thinking_budget"] = budget
                }
            case .reasoning_effort:
                if enabled {
                    out["reasoning_effort"] = thinkingConfig?.effort ?? "medium"
                }
            case .anthropic_native:
                var t = thinking
                if !enabled { t = ["type": "disabled"] }
                out["thinking"] = t
            case .none:
                break
            }

            if proto != .anthropic_native {
                out.removeValue(forKey: "thinking")
            }
        }
```

Then **remove** the existing unconditional `out.removeValue(forKey: "thinking")` at line 219 (it's now handled inside the block above). The line to remove is:

```swift
        out.removeValue(forKey: "thinking")
```

(This appears in the "Remove Anthropic-specific fields" group around line 219. Leave `system`, `stop_sequences`, `metadata`, `top_k`, `context_management`, `output_config` removals intact.)

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ProxyEngineTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add APIBypass/Core/FormatTranslator.swift APIBypassTests/ProxyEngineTests.swift
git commit -m "feat: protocol-aware Anthropic→OpenAI thinking translation"
```

---

## Task 5: Add `reasoning_effort` recognition to `openAIToAnthropicRequest`

**Files:**
- Modify: `APIBypass/Core/FormatTranslator.swift:283-294`

- [ ] **Step 1: Write the failing test**

Add to `APIBypassTests/ProxyEngineTests.swift`:

```swift
func testOpenAIToAnthropic_reasoningEffort() throws {
    let translator = FormatTranslator()
    let oaiBody: [String: Any] = [
        "model": "o3",
        "messages": [["role": "user", "content": "hi"]],
        "reasoning_effort": "high"
    ]
    let data = try JSONSerialization.data(withJSONObject: oaiBody)
    let translated = try translator.translateRequest(data, from: .openai, to: .anthropic)
    let json = try JSONSerialization.jsonObject(with: translated) as! [String: Any]
    let thinking = json["thinking"] as? [String: Any]
    XCTAssertEqual(thinking?["type"] as? String, "enabled")
    XCTAssertNil(json["reasoning_effort"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProxyEngineTests`
Expected: FAIL — `reasoning_effort` not translated

- [ ] **Step 3: Implement `reasoning_effort` handling**

Replace `APIBypass/Core/FormatTranslator.swift:283-294` (the `// enable_thinking → thinking` block) with:

```swift
        // enable_thinking / reasoning_effort → thinking
        if let et = json["enable_thinking"] as? Bool {
            if et {
                var thinking: [String: Any] = ["type": "enabled"]
                if let budget = json["thinking_budget"] as? Int {
                    thinking["budget_tokens"] = budget
                }
                out["thinking"] = thinking
            } else {
                out["thinking"] = ["type": "disabled"]
            }
        } else if let effort = json["reasoning_effort"] as? String, effort != "none" {
            out["thinking"] = ["type": "enabled"]
        }
```

Then add `reasoning_effort` to the remove list. Find the "Remove OpenAI-specific fields" block (around line 301-305) and add `reasoning_effort`:

```swift
        // Remove OpenAI-specific fields
        out.removeValue(forKey: "stop")
        out.removeValue(forKey: "enable_thinking")
        out.removeValue(forKey: "thinking_budget")
        out.removeValue(forKey: "reasoning_effort")
        out.removeValue(forKey: "stream_options")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProxyEngineTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add APIBypass/Core/FormatTranslator.swift APIBypassTests/ProxyEngineTests.swift
git commit -m "feat: translate reasoning_effort → thinking in OpenAI→Anthropic path"
```

---

## Task 6: Pass `thinkingConfig` from `HTTPServer` to `translateRequest`

**Files:**
- Modify: `APIBypass/Core/HTTPServer.swift:339-341`

- [ ] **Step 1: Locate the call site**

Read `APIBypass/Core/HTTPServer.swift:336-351` — the `if needsConversion` block. The call at line 341 is:

```swift
finalRequestData = try translator.translateRequest(transformedData, from: format, to: upstreamFormat)
```

- [ ] **Step 2: Update the call to pass thinkingConfig**

Replace line 341 with:

```swift
                let thinkingConfig = (mapping.parameters.thinkingOverrideEnabled == true) ? mapping.parameters.thinking : nil
                finalRequestData = try translator.translateRequest(transformedData, from: format, to: upstreamFormat, thinkingConfig: thinkingConfig)
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build`
Expected: BUILD SUCCEEDS

- [ ] **Step 4: Run full test suite**

Run: `swift test`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add APIBypass/Core/HTTPServer.swift
git commit -m "feat: pass thinkingConfig to translateRequest for cross-format thinking protocol"
```

---

## Task 7: Add L10n keys for protocol UI

**Files:**
- Modify: `APIBypass/Core/LocalizationManager.swift:102-107`

- [ ] **Step 1: Add new keys**

In `APIBypass/Core/LocalizationManager.swift`, after line 107 (`"thinking_budget_eg"` entry), add:

```swift
        "thinking_protocol": [.chinese: "思考协议", .english: "Thinking Protocol"],
        "thinking_protocol_hint": [.chinese: "选择上游供应商使用的思考控制字段", .english: "Select which field the upstream provider uses to control thinking"],
        "thinking_effort": [.chinese: "推理强度", .english: "Reasoning Effort"],
        "thinking_none_hint": [.chinese: "该模型自身控制思考，无需发送字段", .english: "This model controls thinking internally, no field needed"],
```

Also update line 103 (`reasoning_hint`) to be protocol-generic:

```swift
        "reasoning_hint": [.chinese: "根据上游供应商选择对应的思考控制字段", .english: "Select the thinking control field that matches your upstream provider"],
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDS

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/LocalizationManager.swift
git commit -m "feat: add L10n keys for thinking protocol UI"
```

---

## Task 8: Add protocol Picker to `MappingEditForm`

**Files:**
- Modify: `APIBypass/UI/Views/MappingEditForm.swift:21-24` (bindings)
- Modify: `APIBypass/UI/Views/MappingEditForm.swift:110-153` (thinking section UI)

- [ ] **Step 1: Add new bindings**

In `APIBypass/UI/Views/MappingEditForm.swift`, after line 24 (`@Binding var thinkingBudget: String`), add:

```swift
    @Binding var thinkingProtocol: ThinkingConfig.`Protocol`
    @Binding var thinkingEffort: String
```

- [ ] **Step 2: Replace the thinking section UI**

Replace `APIBypass/UI/Views/MappingEditForm.swift:110-153` (from `// Thinking Override` comment through the closing `.cornerRadius(8)`) with:

```swift
            // Thinking Override
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.t("reasoning_override"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: $thinkingOverrideEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .fixedSize()
                }

                Text(L10n.t("reasoning_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    // Protocol picker
                    HStack {
                        Text(L10n.t("thinking_protocol"))
                            .frame(width: 120, alignment: .trailing)
                        Picker("", selection: $thinkingProtocol) {
                            ForEach(ThinkingConfig.`Protocol`.allCases, id: \.self) { p in
                                Text(p.displayName).tag(p)
                            }
                        }
                        .labelsHidden()
                        .disabled(!thinkingOverrideEnabled)
                    }

                    // Protocol-specific controls
                    switch thinkingProtocol {
                    case .enable_thinking:
                        HStack {
                            Text(L10n.t("enable_thinking"))
                            Spacer()
                            Toggle("", isOn: $thinkingEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .fixedSize()
                                .disabled(!thinkingOverrideEnabled)
                        }
                        if thinkingEnabled {
                            HStack {
                                Text(L10n.t("thinking_budget"))
                                    .frame(width: 120, alignment: .trailing)
                                TextField(L10n.t("thinking_budget_hint"), text: $thinkingBudget)
                                    .disabled(!thinkingOverrideEnabled)
                                Text(L10n.t("thinking_budget_eg"))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    case .reasoning_effort:
                        HStack {
                            Text(L10n.t("enable_thinking"))
                            Spacer()
                            Toggle("", isOn: $thinkingEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .fixedSize()
                                .disabled(!thinkingOverrideEnabled)
                        }
                        if thinkingEnabled {
                            HStack {
                                Text(L10n.t("thinking_effort"))
                                    .frame(width: 120, alignment: .trailing)
                                Picker("", selection: $thinkingEffort) {
                                    Text("low").tag("low")
                                    Text("medium").tag("medium")
                                    Text("high").tag("high")
                                }
                                .labelsHidden()
                                .disabled(!thinkingOverrideEnabled)
                            }
                        }
                    case .anthropic_native:
                        HStack {
                            Text(L10n.t("enable_thinking"))
                            Spacer()
                            Toggle("", isOn: $thinkingEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .fixedSize()
                                .disabled(!thinkingOverrideEnabled)
                        }
                        if thinkingEnabled {
                            HStack {
                                Text(L10n.t("thinking_budget"))
                                    .frame(width: 120, alignment: .trailing)
                                TextField(L10n.t("thinking_budget_hint"), text: $thinkingBudget)
                                    .disabled(!thinkingOverrideEnabled)
                                Text(L10n.t("thinking_budget_eg"))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    case .none:
                        Text(L10n.t("thinking_none_hint"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity(thinkingOverrideEnabled ? 1.0 : 0.4)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: FAIL — the three caller Views don't pass the new bindings yet. This is expected; we fix them in Tasks 9-11.

- [ ] **Step 4: Commit (WIP, will compile after Tasks 9-11)**

```bash
git add APIBypass/UI/Views/MappingEditForm.swift
git commit -m "wip: add protocol picker to MappingEditForm (callers not yet updated)"
```

---

## Task 9: Update `NewMappingView` state + save

**Files:**
- Modify: `APIBypass/UI/Views/NewMappingView.swift:24-26` (state)
- Modify: `APIBypass/UI/Views/NewMappingView.swift:177-210` (form call)
- Modify: `APIBypass/UI/Views/NewMappingView.swift:320-340` (save/build)

- [ ] **Step 1: Add state variables**

In `NewMappingView.swift`, after the existing `@State private var thinkingBudget = ""` (around line 26), add:

```swift
    @State private var thinkingProtocol: ThinkingConfig.`Protocol` = .enable_thinking
    @State private var thinkingEffort = "medium"
```

- [ ] **Step 2: Pass bindings to MappingEditForm**

Find the `MappingEditForm(...)` call in `NewMappingView.swift` (around line 150-210). After the existing `thinkingBudget: $thinkingBudget` line, add:

```swift
                thinkingProtocol: $thinkingProtocol,
                thinkingEffort: $thinkingEffort,
```

- [ ] **Step 3: Infer protocol when provider/model changes**

Find where `selectedProviderId` or `actualModel` changes (or add an `.onChange` to the provider picker). Add a helper and call it on appear / provider change:

```swift
    private func inferThinkingProtocol() {
        guard let pid = selectedProviderId,
              let provider = configManager.providers.first(where: { $0.id == pid }) else { return }
        thinkingProtocol = ThinkingConfig.`Protocol`.infer(
            baseURL: provider.baseURL.absoluteString,
            model: actualModel
        )
    }
```

Call `inferThinkingProtocol()` in `.onAppear` and in an `.onChange(of: selectedProviderId)` (add if not present). If an `.onChange(of: selectedProviderId)` already exists, add the call inside it; otherwise add:

```swift
        .onChange(of: selectedProviderId) { _ in
            inferThinkingProtocol()
        }
```

- [ ] **Step 4: Update save/build to include protocol + effort**

Find the `ThinkingConfig(...)` construction in the save function (around line 320-340). Replace it with:

```swift
        let thinking = ThinkingConfig(
            enabled: thinkingEnabled,
            budgetTokens: thinkingEnabled ? Int(thinkingBudget) : nil,
            protocol: thinkingProtocol,
            effort: thinkingProtocol == .reasoning_effort ? thinkingEffort : nil
        )
```

- [ ] **Step 5: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDS (NewMappingView now passes all bindings)

- [ ] **Step 6: Commit**

```bash
git add APIBypass/UI/Views/NewMappingView.swift
git commit -m "feat: NewMappingView protocol inference + save"
```

---

## Task 10: Update `MappingDetailView` state + load + save

**Files:**
- Modify: `APIBypass/UI/Views/MappingDetailView.swift:36-38` (state)
- Modify: `APIBypass/UI/Views/MappingDetailView.swift:189-224` (form call)
- Modify: `APIBypass/UI/Views/MappingDetailView.swift:414-429` (load)
- Modify: `APIBypass/UI/Views/MappingDetailView.swift:479-482` (build)

- [ ] **Step 1: Add state variables**

In `MappingDetailView.swift`, after `@State private var thinkingBudget = ""` (around line 38), add:

```swift
    @State private var thinkingProtocol: ThinkingConfig.`Protocol` = .enable_thinking
    @State private var thinkingEffort = "medium"
```

- [ ] **Step 2: Pass bindings to MappingEditForm**

Find the `MappingEditForm(...)` call (around line 189-224). After `thinkingBudget: $thinkingBudget`, add:

```swift
                    thinkingProtocol: $thinkingProtocol,
                    thinkingEffort: $thinkingEffort,
```

- [ ] **Step 3: Load protocol + effort from mapping**

In `loadMappingData()` (around line 414-429), after the existing thinking load block, add protocol + effort loading. Replace the block at lines 414-422 with:

```swift
        if let thinking = mapping.parameters.thinking {
            thinkingEnabled = thinking.enabled
            if let budget = thinking.budgetTokens {
                thinkingBudget = String(budget)
            }
            thinkingProtocol = thinking.`protocol`
            thinkingEffort = thinking.effort ?? "medium"
        } else {
            thinkingEnabled = false
            thinkingBudget = ""
            thinkingProtocol = ThinkingConfig.`Protocol`.infer(
                baseURL: provider?.baseURL.absoluteString ?? "",
                model: mapping.actualModel
            )
            thinkingEffort = "medium"
        }
```

(Where `provider` is the resolved provider for this mapping — use `configManager.providers.first(where: { $0.id == mapping.providerConfigId })` if `provider` isn't in scope.)

- [ ] **Step 4: Update buildParameters**

In `buildParameters()` (around line 479-482), replace the `ThinkingConfig(...)` construction with:

```swift
        let thinking = ThinkingConfig(
            enabled: thinkingEnabled,
            budgetTokens: thinkingEnabled ? Int(thinkingBudget) : nil,
            protocol: thinkingProtocol,
            effort: thinkingProtocol == .reasoning_effort ? thinkingEffort : nil
        )
```

- [ ] **Step 5: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDS

- [ ] **Step 6: Commit**

```bash
git add APIBypass/UI/Views/MappingDetailView.swift
git commit -m "feat: MappingDetailView protocol load + save"
```

---

## Task 11: Update `MappingCardView` state + load + save

**Files:**
- Modify: `APIBypass/UI/Views/MappingCardView.swift:38-40` (state)
- Modify: `APIBypass/UI/Views/MappingCardView.swift:151` (form call)
- Modify: `APIBypass/UI/Views/MappingCardView.swift:257-265` (load)
- Modify: `APIBypass/UI/Views/MappingCardView.swift:343` (build)

- [ ] **Step 1: Add state variables**

In `MappingCardView.swift`, after `@State private var thinkingBudget = ""` (around line 40), add:

```swift
    @State private var thinkingProtocol: ThinkingConfig.`Protocol` = .enable_thinking
    @State private var thinkingEffort = "medium"
```

- [ ] **Step 2: Pass bindings to MappingEditForm**

Find the `MappingEditForm(...)` call (around line 151). After `thinkingBudget: $thinkingBudget`, add:

```swift
                    thinkingProtocol: $thinkingProtocol,
                    thinkingEffort: $thinkingEffort,
```

- [ ] **Step 3: Load protocol + effort**

Find the load block (around line 257-265). After the existing thinking load, add protocol + effort. Replace lines 257-265 with:

```swift
            thinkingEnabled = thinking.enabled
            thinkingBudget = thinking.budgetTokens.map { String($0) } ?? ""
            thinkingProtocol = thinking.`protocol`
            thinkingEffort = thinking.effort ?? "medium"
        } else {
            thinkingEnabled = false
            thinkingBudget = ""
            thinkingProtocol = .enable_thinking
            thinkingEffort = "medium"
        }
```

- [ ] **Step 4: Update build**

Find the `ThinkingConfig(...)` construction in the save/build (around line 343). Replace with:

```swift
            thinking: ThinkingConfig(
                enabled: thinkingEnabled,
                budgetTokens: thinkingEnabled ? Int(thinkingBudget) : nil,
                protocol: thinkingProtocol,
                effort: thinkingProtocol == .reasoning_effort ? thinkingEffort : nil
            ),
```

- [ ] **Step 5: Build + run full test suite**

Run: `swift build && swift test`
Expected: BUILD SUCCEEDS, ALL TESTS PASS

- [ ] **Step 6: Commit**

```bash
git add APIBypass/UI/Views/MappingCardView.swift
git commit -m "feat: MappingCardView protocol load + save"
```

---

## Task 12: End-to-end manual verification

**Files:** None (manual testing)

- [ ] **Step 1: Build debug app**

Run: `swift build -c debug` (or Xcode build with `CFBundleIdentifier=com.apibypass.app`)

- [ ] **Step 2: Launch app, configure GLM mapping**

- Open APIBypass config
- Create/edit a mapping pointing to a GLM provider
- Verify the Protocol Picker defaults to `enable_thinking`
- Toggle thinking on, set budget 10000
- Save

- [ ] **Step 3: Test GLM via 8390 with thinking ON**

Send a request through APIBypass to GLM-5.2-ark. Verify upstream body contains `enable_thinking: true` + `thinking_budget: 10000` (check `~/Library/Logs/com.apibypass.app/trace/debug/upstream_*.json`). Verify thinking displays in client.

- [ ] **Step 4: Test GLM with thinking OFF**

Toggle thinking off, save, resend. Verify upstream body contains `enable_thinking: false`. Verify no thinking in client (this confirms the off-state fix).

- [ ] **Step 5: Test o3 model protocol inference**

Create a mapping with model `o3-mini`. Verify Protocol Picker defaults to `reasoning_effort`. Set effort to `high`. Verify upstream body contains `reasoning_effort: high`.

- [ ] **Step 6: Test backward compat**

Open an existing mapping saved before this change (no `protocol` field). Verify it loads with `enable_thinking` protocol and behavior is unchanged.

- [ ] **Step 7: No commit needed (verification only)**

---

## Task 13: Release v0.7.8

**Files:**
- Modify: `Info.plist:18`
- Modify: `RELEASE_NOTES.md`

- [ ] **Step 1: Bump version**

In `Info.plist`, change `0.7.7` to `0.7.8` (line 18, `CFBundleShortVersionString`).

- [ ] **Step 2: Add release notes**

Prepend to `RELEASE_NOTES.md`:

```markdown
# APIBypass v0.7.8

## What's New

### Multi-Protocol Thinking Override

The "Reasoning Mode Override" feature now supports multiple upstream thinking protocols instead of only `enable_thinking`:

- **`enable_thinking`** — GLM / Qwen / Kimi / Ark (existing behavior)
- **`reasoning_effort`** — OpenAI o-series (o1 / o3 / o4), with low/medium/high selector
- **`thinking (Anthropic)`** — Anthropic-compatible upstreams using native `thinking.type=enabled`
- **`none`** — Models that control thinking internally (e.g. DeepSeek-R1), no field emitted

The protocol is **auto-inferred** from the provider baseURL and model name, and can be manually overridden per mapping.

**Bug fix**: the off state is now explicitly emitted (`enable_thinking: false`) for protocols that support it, instead of omitting the field. This allows disabling thinking on upstreams that default to thinking-on (e.g. GLM-5.2 on Ark).

---

```

- [ ] **Step 3: Commit + tag**

```bash
git add Info.plist RELEASE_NOTES.md
git commit -m "release: v0.7.8 — multi-protocol thinking override"
git tag v0.7.8
```

- [ ] **Step 4: Push (if user approves)**

```bash
git push origin main
git push origin v0.7.8
```
