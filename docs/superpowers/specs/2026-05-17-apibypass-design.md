# APIBypass - 大模型 API 代理服务设计文档

**日期**: 2026-05-17
**状态**: 设计完成，待实现

---

## 1. 项目概述

### 1.1 背景

部分调用大模型 API 的软件无法自定义调用参数（如关闭思考模式、调整 temperature 等）。APIBypass 作为本地代理服务，在这些软件和上游 API 之间拦截请求，注入预设参数。

### 1.2 目标

- 在 macOS 后台运行，提供本地 HTTP 代理服务
- 支持配置模型名称映射和参数注入
- 支持 OpenAI 和 Anthropic 两种 API 格式
- 提供简洁的菜单栏配置界面

### 1.3 成功标准

- 用户可通过菜单栏界面配置模型映射
- 客户端软件请求 `localhost:8390` 时，参数被正确注入
- API Key 安全存储在 Keychain
- 流式响应正常工作

---

## 2. 架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    APIBypassApp                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │              MenuBar UI (SwiftUI)                │   │
│  │  • 状态指示器（运行/停止）                          │   │
│  │  • 配置入口                                       │   │
│  │  • 快速切换                                       │   │
│  └─────────────────────────────────────────────────┘   │
│                          │                              │
│  ┌─────────────────────────────────────────────────┐   │
│  │           ConfigManager                          │   │
│  │  • 模型映射配置                                   │   │
│  │  • API 凭证管理（Keychain）                        │   │
│  │  • 参数预设                                       │   │
│  └─────────────────────────────────────────────────┘   │
│                          │                              │
│  ┌─────────────────────────────────────────────────┐   │
│  │         HTTP Server (Hummingbird)               │   │
│  │  • 监听 localhost:8390                           │   │
│  │  • OpenAI 兼容端点                               │   │
│  │  • Anthropic 端点                                │   │
│  └─────────────────────────────────────────────────┘   │
│                          │                              │
│  ┌─────────────────────────────────────────────────┐   │
│  │            ProxyEngine                           │   │
│  │  • 请求转换                                       │   │
│  │  • 参数注入                                       │   │
│  │  • 流式响应转发                                   │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 2.2 技术选型

| 组件 | 技术 | 理由 |
|------|------|------|
| UI 框架 | SwiftUI | 原生、现代化 |
| HTTP 服务器 | Hummingbird | 轻量级、Swift 原生 |
| 安全存储 | Keychain Services | API Key 加密存储 |
| 配置存储 | UserDefaults + JSON | 简单可靠 |

---

## 3. 数据模型

### 3.1 模型映射配置

```swift
struct ModelMapping: Codable, Identifiable {
    var id: UUID
    var name: String              // 配置名称（如"创意写作"）
    var incomingModel: String     // 客户端请求的模型名
    var actualModel: String       // 实际调用的模型
    var apiProvider: APIProvider  // openai / anthropic
    var baseURL: URL
    var parameters: InjectedParameters
    var isEnabled: Bool           // 是否启用此映射
}

enum APIProvider: String, Codable {
    case openai
    case anthropic
}

struct InjectedParameters: Codable {
    // 思考模式
    var thinking: ThinkingConfig?

    // 模型行为
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
    var frequencyPenalty: Double?
    var presencePenalty: Double?

    // 请求配置
    var timeout: TimeInterval?
    var retryCount: Int?

    // 自定义 headers
    var customHeaders: [String: String]?
}

struct ThinkingConfig: Codable {
    var enabled: Bool
    var budgetTokens: Int?
}
```

### 3.2 API 凭证存储

- API Key 存储在 **Keychain**，使用服务名 `com.apibypass.apikey`
- 与模型映射 ID 关联
- 应用卸载时自动清除

---

## 4. 功能模块

### 4.1 菜单栏 UI

**状态指示：**
- 绿色图标：服务运行中
- 红色图标：服务已停止
- 点击切换运行状态

**菜单项：**
- 打开配置窗口
- 快速启用/禁用所有映射
- 退出应用

**配置窗口：**
- 左侧：模型映射列表
- 右侧：选中映射的详细配置
- 底部：添加/删除映射按钮

### 4.2 HTTP 服务器

**监听端点：**
- `POST /v1/chat/completions` - OpenAI 格式
- `POST /v1/messages` - Anthropic 格式
- `GET /v1/models` - 返回配置的模型列表

**请求处理流程：**
1. 解析请求体，提取 `model` 字段
2. 查找匹配的模型映射配置
3. 替换模型名称，注入参数
4. 构建上游 API 请求
5. 发送请求并转发响应

### 4.3 代理引擎

**参数注入逻辑：**
- 合并客户端参数和预设参数（预设参数优先）
- 特殊处理 Anthropic 的 `thinking` 参数
- 保留客户端的 `stream` 设置

**流式响应处理：**
- 支持 SSE（Server-Sent Events）
- 逐块转发，不缓冲完整响应
- 处理 Anthropic 和 OpenAI 的不同流格式

---

## 5. 用户操作流程

### 5.1 初始配置

1. 启动应用 → 菜单栏出现图标
2. 点击"打开配置"
3. 点击"+"添加新映射
4. 填写配置：
   - 配置名称
   - 上游 API 地址（如 `https://api.anthropic.com`）
   - API Key
   - 客户端模型名（如 `gpt-4`）
   - 实际模型名（如 `claude-sonnet-4-6`）
   - 注入参数
5. 保存

### 5.2 客户端使用

1. 在客户端软件中设置：
   - Base URL: `http://localhost:8390`
   - API Key: 任意值（代理会使用预设的 Key）
   - Model: 配置的客户端模型名
2. 发起请求，参数自动注入

---

## 6. 测试策略

### 6.1 单元测试

- ConfigManager: 配置读写、Keychain 操作
- ProxyEngine: 参数合并、请求转换
- Model matching: 模型名称匹配逻辑

### 6.2 集成测试

- 模拟 HTTP 请求，验证端到端流程
- 测试 OpenAI 和 Anthropic 两种格式
- 验证流式响应

### 6.3 手动验证

- 使用 curl 测试基础功能
- 使用真实客户端软件测试
- 验证 macOS 后台运行稳定性

---

## 7. 文件结构

```
APIBypass/
├── App/
│   ├── APIBypassApp.swift          # 应用入口
│   └── AppDelegate.swift           # 后台生命周期
├── UI/
│   ├── MenuBarController.swift     # 菜单栏控制
│   ├── ConfigWindow.swift          # 配置窗口
│   └── Views/                      # SwiftUI 视图
├── Core/
│   ├── ConfigManager.swift         # 配置管理
│   ├── HTTPServer.swift            # HTTP 服务
│   └── ProxyEngine.swift           # 代理引擎
├── Models/
│   ├── ModelMapping.swift          # 数据模型
│   └── APIProvider.swift           # API 提供商枚举
├── Services/
│   ├── KeychainService.swift       # Keychain 操作
│   └── NetworkService.swift        # 网络请求
└── Resources/
    └── Assets.xcassets             # 图标资源
```

---

## 8. 开发计划

详见实现计划文档（待生成）。

---

## 9. 风险与限制

### 9.1 已知限制

- 仅支持 macOS 14+（MenuBarExtra 要求）
- 不支持 WebSocket
- 不支持文件上传端点

### 9.2 风险缓解

- 上游 API 变更：保持 HTTP 客户端灵活性
- 流式响应兼容性：充分测试各种客户端
