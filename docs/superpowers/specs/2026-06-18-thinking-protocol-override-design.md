# Thinking Protocol Override

## Context

### 问题

APIBypass 的「覆盖思考推理模式」功能（model mapping 配置 → Thinking Override）当前只识别 `enable_thinking` 一种上游协议。`FormatTranslator.anthropicToOpenAIRequest`（`APIBypass/Core/FormatTranslator.swift:199-209`）硬编码：

```swift
if type == "enabled" {
    out["enable_thinking"] = true
    if let budget = thinking["budget_tokens"] as? Int {
        out["thinking_budget"] = budget
    }
}
```

这只对 GLM / Qwen / Kimi / Ark 系生效。其他上游用不同字段控制思考：

- OpenAI o-series（o1 / o3 / o4）：`reasoning_effort: low|medium|high`
- Anthropic 兼容上游：`thinking.type=enabled` + `budget_tokens`（原生协议，不需要翻译）
- DeepSeek-reasoner 等：模型自身即开关，任何字段都不发

此外当前实现只在 `type=="enabled"` 时发字段，**关闭态什么都不发**——对 GLM 这种「默认开」的上游无法显式关闭。

### 影响范围

- 仅影响 Anthropic-client → OpenAI-upstream 翻译路径（`anthropicToOpenAIRequest`）
- `openAIToAnthropicRequest`（反向）已能处理 `enable_thinking: false` → `thinking.type=disabled`，只需补一条 `reasoning_effort` 识别
- `StreamTranslator`（流式响应）按字段名读 `reasoning_content`，协议无关，不动
- 同格式直通（OpenAI→OpenAI / Anthropic→Anthropic）不进翻译，不受影响

## 修复

### 1. 数据模型扩展

文件：`APIBypass/Models/ModelMapping.swift`

`ThinkingConfig` 增加两个字段：

```swift
struct ThinkingConfig: Codable, Equatable {
    enum Protocol: String, Codable, CaseIterable {
        case enable_thinking      // GLM / Qwen / Kimi / Ark
        case reasoning_effort     // OpenAI o-series
        case anthropic_native     // Anthropic 兼容上游
        case none                 // 不发字段（模型自身即开关）
    }

    let enabled: Bool
    let budgetTokens: Int?
    let `protocol`: Protocol
    let effort: String?          // "low" / "medium" / "high"，仅 reasoning_effort 用

    init(enabled: Bool,
         budgetTokens: Int? = nil,
         `protocol`: Protocol = .enable_thinking,
         effort: String? = nil) {
        self.enabled = enabled
        self.budgetTokens = budgetTokens
        self.`protocol` = `protocol`
        self.effort = effort
    }
}
```

**向后兼容**：旧数据没有 `protocol` / `effort` 字段，`Codable` 解码时回退到默认值 `.enable_thinking` / `nil`。旧 `thinking.enabled=true` 的语义本来就只在 GLM 系生效，回退到 `.enable_thinking` 等价于行为不变。

`InjectedParameters` 不动——`thinking: ThinkingConfig?` 字段签名不变，只是内容更丰富。

### 2. 协议推断

新增 `ThinkingProtocol.infer(baseURL:model:) -> ThinkingConfig.Protocol`，放在 `APIBypass/Models/ModelMapping.swift` 同文件（作为 enum 的静态方法）：

```swift
extension ThinkingConfig.Protocol {
    static func infer(baseURL: String, model: String) -> ThinkingConfig.Protocol {
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
        return .enable_thinking   // 保守默认
    }
}
```

**规则**：

- `anthropic` 在 host → `.anthropic_native`
- model 名 `o1` / `o3` / `o4` 开头（含 `-mini` / `-preview`）→ `.reasoning_effort`
- `deepseek-r` 开头 → `.none`
- GLM / Kimi / 通义 / 火山 / Ark 域名 → `.enable_thinking`
- 其他 → `.enable_thinking`

**推断只影响 UI 默认值，不覆盖用户已选**。用户在 UI 上手改后存什么就是什么。

### 3. 翻译层改动

文件：`APIBypass/Core/FormatTranslator.swift`

#### `anthropicToOpenAIRequest`（199-209 行）

按 `protocol` 分支产出，关闭态显式化：

```swift
// thinking 字段在 HTTPServer parameters 注入阶段已 merge 进 body["thinking"]，
// 其中包含 InjectedParameters.thinking.protocol（内部字段，需剥离）
if let thinking = json["thinking"] as? [String: Any] {
    let protoStr = thinking["protocol"] as? String
    let proto = protoStr.flatMap(ThinkingConfig.Protocol.init(rawValue:)) ?? .enable_thinking
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
            out["reasoning_effort"] = thinking["effort"] as? String ?? "medium"
        }
    case .anthropic_native:
        var t = thinking
        t.removeValue(forKey: "protocol")   // 剥离内部字段
        if !enabled { t = ["type": "disabled"] }
        out["thinking"] = t
        // 不删 thinking，保留原生字段
    case .none:
        break   // 什么都不发
    }

    // 除 anthropic_native 外都删 thinking
    if proto != .anthropic_native {
        out.removeValue(forKey: "thinking")
    }
}
```

**关闭态显式化**：`.enable_thinking` 关闭时发 `enable_thinking: false`（修复当前只发 true 的 bug，对 GLM 这种默认开的上游可显式关闭）。

#### `openAIToAnthropicRequest`（283-294 行）

补 `reasoning_effort` 识别：

```swift
// enable_thinking → thinking
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
}
// reasoning_effort → thinking（无 budget，OpenAI 不接受 budget_tokens）
else if let effort = json["reasoning_effort"] as? String, effort != "none" {
    out["thinking"] = ["type": "enabled"]
}
```

放在现有 `enable_thinking` 分支后，用 `else if` 互斥（同时出现时优先 `enable_thinking`，因为它是 GLM 系的显式开关）。

### 4. UI 改动

文件：`APIBypass/UI/Views/MappingEditForm.swift`（NewMappingView / MappingDetailView / MappingCardView 共用）

思考区块重新组织：

- 保留 `thinkingOverrideEnabled` 总开关
- 总开关下新增**协议 Picker**（4 选项），新建 mapping 时调 `infer` 填默认值
- Picker 下方根据协议动态切换 UI：

| 协议 | 控件 |
|------|------|
| `.enable_thinking` | 现有 Toggle + budget TextField |
| `.reasoning_effort` | Toggle + low/medium/high Picker（Toggle 关时不发字段）|
| `.anthropic_native` | Toggle + budget TextField（不再限定 `provider.apiProvider == .anthropic`）|
| `.none` | 只显示一行说明文字「该模型自身控制思考，无需字段」|

**Binding**：`MappingEditForm` 新增两个 binding：
- `thinkingProtocol: Binding<ThinkingConfig.Protocol>`
- `thinkingEffort: Binding<String>`

**三个调用方 View** 各加 `@State thinkingProtocol` / `@State thinkingEffort`：
- NewMappingView：新建时调 `infer` 填默认
- MappingDetailView / MappingCardView：load 时从 `mapping.parameters.thinking?.protocol` 读；缺省（旧数据）回退到 `.enable_thinking`

现有「`thinkingEnabled` + 仅 anthropic provider 显示 budget」的特判逻辑被协议 Picker 取代，删除。

### 5. 内部字段剥离

`protocol` 和 `effort` 是 APIBypass 内部字段，不能发到上游。剥离点：

- `anthropicToOpenAIRequest`：`.anthropic_native` 分支保留 `thinking` 但删 `protocol` 子键；其他分支删整个 `thinking`，自然连带删除
- `openAIToAnthropicRequest`：不涉及（OpenAI 上游不会发 `protocol` 字段）
- 同格式直通路径（OpenAI→OpenAI / Anthropic→Anthropic）：**需要确认 HTTPServer 的 parameters 注入是否会把 `protocol` 带进 body**——如果会，直通路径也要剥离。实施阶段在 `translateRequest` 的 `default: return data` 分支前检查并剥离

## 不做的事

- 不动 `StreamTranslator`——响应端按字段名读 `reasoning_content`，协议无关
- 不动 Codex Adaptor 的 `ReasoningConfig`——那是 Codex 路径独立配置，不与主 mapping 共享
- 不处理 `redacted_thinking`——保持现状
- 不加端到端测试——主路径翻译已有 `ProxyEngineTests`，实施阶段补几个 case 覆盖四个协议即可

## 验证

### 1. 构建
重新构建 debug .app 包，`open` 启动监听 8390。

### 2. 单元测试（ProxyEngineTests）
新增四个 case 覆盖四个协议：
- `.enable_thinking` 开 → upstream body 含 `enable_thinking: true`
- `.enable_thinking` 关 → upstream body 含 `enable_thinking: false`（修复回归）
- `.reasoning_effort` 开 → upstream body 含 `reasoning_effort: medium`（默认值）
- `.anthropic_native` 开 → upstream body 保留 `thinking.type=enabled`，且不含 `protocol` 子键
- `.none` → upstream body 不含任何思考字段

### 3. UI 回归
- 新建 mapping 指向 GLM provider → 协议默认 `.enable_thinking`
- 新建 mapping 指向 o3 模型 → 协议默认 `.reasoning_effort`
- 旧数据（无 `protocol` 字段）打开 → 回退 `.enable_thinking`，行为不变
- 手动切换协议后保存 → 重新打开显示用户选择，未被推断覆盖

### 4. 端到端
- GLM-5.2-ark 经 APIBypass：`.enable_thinking` 开 → 上游返回 reasoning_content → thinking 正常显示
- GLM-5.2-ark 经 APIBypass：`.enable_thinking` 关 → 上游不返回 reasoning_content（验证关闭态显式化生效）
- o3 经 APIBypass：`.reasoning_effort=high` → 上游按 high 推理

## 发布

本版本为 **v0.7.8**（v0.7.7 已推送，含 tool_result / thinking 上下文 / TraceLogger 修复）。
