# 提供商配置功能设计

## 概述

将"提供商配置"（baseURL + API Key）从"模型映射"中分离，实现按提供商分类管理，避免重复配置。

## 数据模型

### 新增 ProviderConfig

```swift
// APIBypass/Models/ProviderConfig.swift

struct ProviderConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String              // 显示名称，如 "我的 DashScope"
    var apiProvider: APIProvider  // openai / anthropic
    var baseURL: URL
}
```

### 修改 ModelMapping

```swift
struct ModelMapping: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var incomingModel: String
    var actualModel: String
    var providerConfigId: UUID    // 替换原来的 apiProvider + baseURL
    var parameters: InjectedParameters
    var isEnabled: Bool
}
```

移除字段：`apiProvider`、`baseURL`

### API Key 存储

- Keychain key 从 `mapping.id.uuidString` 改为 `providerConfig.id.uuidString`
- 多个映射共享同一提供商时，共享同一个 API Key

## UI 结构

### 主窗口左侧列表重组

```
┌──────────────┐
│ ▼ 提供商     │
│   DashScope  │
│   OpenAI     │
│   + 新建提供商│
├──────────────┤
│ ▼ 模型映射   │
│   qwen-plus  │
│   deepseek   │
│   + 新建映射  │
└──────────────┘
```

### 提供商详情视图

- 名称输入框
- 提供商类型选择（OpenAI / Anthropic）
- Base URL 输入框
- API Key 输入框（安全存储）
- 删除按钮

删除有关联映射时，二次确认提示："该提供商已被 N 个映射使用，删除后这些映射将失效"

### 模型映射详情视图

修改后：
- 启用开关
- 名称输入框
- 客户端模型名
- 实际模型名
- 提供商下拉选择（显示所有 ProviderConfig.name）
- 提供商无效时显示红色警告："提供商已删除，请重新选择"
- 参数注入区域（保持不变）

移除：baseURL 输入框、API Key 输入框

### 新建映射时内联创建提供商

- 提供商下拉框底部显示"➕ 添加新提供商"选项
- 点击后弹出 Sheet 创建提供商
- 创建成功后自动选中新提供商

## 数据流

### ConfigManager 扩展

```swift
@Published var providers: [ProviderConfig] = []

func loadProviders()
func saveProviders()
func addProvider(_ provider: ProviderConfig)
func updateProvider(_ provider: ProviderConfig)
func deleteProvider(_ provider: ProviderConfig)
func isProviderValid(for mapping: ModelMapping) -> Bool
func mappingsForProvider(_ provider: ProviderConfig) -> [ModelMapping]
```

### 删除提供商逻辑

1. 从 providers 列表移除
2. 不删除关联的 mappings
3. 关联的 mappings 的 providerConfigId 指向已删除的 id，运行时标记为无效

## 数据迁移

首次启动新版本时自动迁移：

1. 遍历所有现有 ModelMapping
2. 按 (apiProvider, baseURL) 分组
3. 每组创建一个 ProviderConfig，名称自动生成：
   - 第一组："OpenAI" 或 "Anthropic"
   - 后续组："OpenAI 2"、"OpenAI 3" 等
4. API Key 迁移：从 keychain 中将 `mapping.id` key 的值复制到 `provider.id` key
5. 更新 mapping.providerConfigId
6. 保存新的 providers 列表和更新后的 mappings
7. 清理旧的 keychain entries（可选，或保留兼容）

迁移标记：UserDefaults 存储迁移完成标志，避免重复迁移

## 错误处理

| 场景 | 处理方式 |
|------|---------|
| 删除有关联的提供商 | 二次确认弹窗，说明影响 |
| 打开无效映射详情 | 红色提示"提供商已删除"，提供商选择框高亮 |
| 新建映射但无提供商 | 下拉框显示"暂无提供商，点击添加" |
| 内联创建提供商失败 | 显示错误提示，不关闭 Sheet |

## 文件修改清单

| 文件 | 操作 |
|------|------|
| `Models/ProviderConfig.swift` | 新增 |
| `Models/ModelMapping.swift` | 修改：移除 apiProvider/baseURL，新增 providerConfigId |
| `Core/ConfigManager.swift` | 修改：新增 providers 管理、迁移逻辑 |
| `Services/KeychainService.swift` | 可能调整：支持批量迁移 |
| `UI/ConfigWindow.swift` | 修改：左侧列表分组 |
| `UI/Views/MappingListView.swift` | 修改：分组显示提供商和映射 |
| `UI/Views/MappingDetailView.swift` | 修改：替换提供商选择 |
| `UI/Views/ProviderDetailView.swift` | 新增：提供商编辑视图 |
| `UI/Views/NewProviderView.swift` | 新增：新建提供商表单 |

## 测试验证

1. **全新安装**：添加提供商 → 添加映射 → 验证代理工作
2. **升级迁移**：旧数据自动迁移，API Key 正确迁移，代理工作
3. **删除提供商**：关联映射显示无效状态，代理返回错误
4. **共享提供商**：多个映射使用同一提供商，修改 API Key 一次生效
5. **内联创建**：新建映射时内联创建提供商，流程顺畅
