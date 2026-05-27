import Foundation

enum AppLanguage: String, CaseIterable {
    case chinese = "zh"
    case english = "en"

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh"
        currentLanguage = AppLanguage(rawValue: raw) ?? .chinese
    }
}

// MARK: - String Keys
struct L10n {
    let key: String

    private static let manager = LocalizationManager.shared

    // 通过 LocalizationManager 翻译
    var text: String {
        let lang = L10n.manager.currentLanguage
        return L10n.dict[key]?[lang] ?? key
    }

    private static let dict: [String: [AppLanguage: String]] = [
        // 菜单栏
        "server_running": [.chinese: "服务运行中", .english: "Server Running"],
        "server_stopped": [.chinese: "服务已停止", .english: "Server Stopped"],
        "start_server": [.chinese: "启动服务", .english: "Start Server"],
        "stop_server": [.chinese: "停止服务", .english: "Stop Server"],
        "configure": [.chinese: "配置...", .english: "Configure..."],
        "settings": [.chinese: "设置...", .english: "Settings..."],
        "quit": [.chinese: "退出", .english: "Quit"],
        "port": [.chinese: "端口", .english: "Port"],
        "version": [.chinese: "版本", .english: "Version"],

        // 设置面板
        "settings_title": [.chinese: "设置", .english: "Settings"],
        "language": [.chinese: "语言", .english: "Language"],
        "language_hint": [.chinese: "切换语言后立即生效", .english: "Changes take effect immediately"],
        "server_port": [.chinese: "服务端口", .english: "Server Port"],
        "port_hint": [.chinese: "修改端口后需重启服务生效", .english: "Restart the server to apply port changes"],
        "about": [.chinese: "关于", .english: "About"],
        "about_description": [.chinese: "APIBypass 是一款 API 模型映射代理工具，可拦截客户端请求并注入自定义参数，无缝切换模型提供商。", .english: "APIBypass is an API model mapping proxy that intercepts client requests and injects custom parameters for seamless model provider switching."],
        "license": [.chinese: "许可证: MIT License", .english: "License: MIT License"],
        "github_repo": [.chinese: "GitHub: https://github.com/panando/APIBypass", .english: "GitHub: https://github.com/panando/APIBypass"],

        // 配置窗口
        "model_mapping": [.chinese: "模型映射", .english: "Model Mapping"],
        "add_mapping": [.chinese: "添加映射", .english: "Add Mapping"],
        "delete_mapping": [.chinese: "删除映射", .english: "Delete Mapping"],
        "select_or_create": [.chinese: "选择或创建配置", .english: "Select or Create Config"],
        "select_or_create_hint": [.chinese: "从左侧列表选择一个配置进行编辑，或点击 + 按钮创建新配置", .english: "Select a configuration from the left panel, or click + to create a new one"],
        "create_new_config": [.chinese: "创建新配置", .english: "Create New Config"],
        "new_model_mapping": [.chinese: "新建模型映射", .english: "New Model Mapping"],

        // 配置详情
        "config_status": [.chinese: "配置状态", .english: "Configuration Status"],
        "config_enabled": [.chinese: "此配置已启用，请求将被代理转发", .english: "This configuration is enabled, requests will be proxied"],
        "config_disabled": [.chinese: "此配置已禁用，请求不会匹配此规则", .english: "This configuration is disabled, requests will not match"],
        "basic_info": [.chinese: "基本信息", .english: "Basic Info"],
        "config_name": [.chinese: "配置名称", .english: "Config Name"],
        "incoming_model": [.chinese: "客户端模型名", .english: "Incoming Model"],
        "actual_model": [.chinese: "实际模型名", .english: "Actual Model"],
        "api_provider": [.chinese: "API接口类型", .english: "API Provider"],
        "base_url": [.chinese: "Base URL", .english: "Base URL"],
        "api_key": [.chinese: "API Key", .english: "API Key"],
        "reasoning_override": [.chinese: "更改默认推理模式", .english: "Reasoning Mode Override"],
        "reasoning_hint": [.chinese: "通过 enable_thinking 参数控制思考模式", .english: "Control thinking mode via enable_thinking parameter"],
        "enable_thinking": [.chinese: "是否启用思考模式", .english: "Enable Thinking Mode"],
        "thinking_budget": [.chinese: "思考预算", .english: "Thinking Budget"],
        "thinking_budget_hint": [.chinese: "tokens 数量", .english: "tokens count"],
        "thinking_budget_eg": [.chinese: "如 10000", .english: "e.g. 10000"],
        "param_injection": [.chinese: "参数注入", .english: "Parameter Injection"],
        "custom_params": [.chinese: "自定义参数", .english: "Custom Parameters"],
        "add_field": [.chinese: "添加字段", .english: "Add Field"],
        "add_custom_hint": [.chinese: "添加自定义 JSON 参数字段", .english: "Add custom JSON parameter fields"],
        "custom_hint": [.chinese: "提示: 值支持 JSON 格式，如 \"enable_thinking\":true, \"thinking\": {\"type\": \"disabled\"}", .english: "Tip: Values support JSON format, e.g. \"enable_thinking\":true, \"thinking\": {\"type\": \"disabled\"}"],
        "enable_config": [.chinese: "启用此配置", .english: "Enable This Config"],
        "save": [.chinese: "保存", .english: "Save"],
        "saved": [.chinese: "已保存", .english: "Saved"],
        "ok": [.chinese: "好的", .english: "OK"],

        // 新建配置
        "config_name_placeholder": [.chinese: "名称", .english: "Name"],
        "incoming_model_placeholder": [.chinese: "如 gpt-4", .english: "e.g. gpt-4"],
        "actual_model_placeholder": [.chinese: "如 claude-sonnet-4-6", .english: "e.g. claude-sonnet-4-6"],
        "base_url_placeholder": [.chinese: "Base URL", .english: "Base URL"],
        "api_key_placeholder": [.chinese: "sk-...", .english: "sk-..."],
        "field_name_placeholder": [.chinese: "字段名", .english: "Field Name"],
        "field_value_placeholder": [.chinese: "值 (JSON格式)", .english: "Value (JSON format)"],

        // 参数 placeholder
        "temp_placeholder": [.chinese: "0.0 - 2.0，创造性程度", .english: "0.0 - 2.0, creativity"],
        "max_tokens_placeholder": [.chinese: "最大输出长度", .english: "Max output length"],
        "top_p_placeholder": [.chinese: "0.0 - 1.0，核采样", .english: "0.0 - 1.0, nucleus sampling"],
        "freq_penalty_placeholder": [.chinese: "-2.0 - 2.0，频率惩罚", .english: "-2.0 - 2.0, frequency penalty"],
        "pres_penalty_placeholder": [.chinese: "-2.0 - 2.0，存在惩罚", .english: "-2.0 - 2.0, presence penalty"],

        // 确认与提示
        "confirm_delete": [.chinese: "确认删除", .english: "Confirm Delete"],
        "confirm_delete_msg": [.chinese: "确定要删除配置", .english: "Are you sure you want to delete config"],
        "confirm_delete_hint": [.chinese: "此操作无法撤销。", .english: "This action cannot be undone."],
        "confirm_delete_generic": [.chinese: "确定要删除此配置吗？", .english: "Are you sure you want to delete this config?"],
        "cancel": [.chinese: "取消", .english: "Cancel"],
        "delete": [.chinese: "删除", .english: "Delete"],
        "unsaved_changes": [.chinese: "未保存的更改", .english: "Unsaved Changes"],
        "unsaved_changes_msg": [.chinese: "当前配置有未保存的更改，是否保存？", .english: "The current configuration has unsaved changes. Save?"],
        "discard_changes": [.chinese: "放弃更改", .english: "Discard Changes"],
        "save_and_switch": [.chinese: "保存并切换", .english: "Save & Switch"],
        "create": [.chinese: "创建", .english: "Create"],
        "duplicate_model_title": [.chinese: "模型名重复", .english: "Duplicate Model Name"],
        "duplicate_model_msg": [.chinese: "客户端模型名已存在，请使用其他名称", .english: "This client model name already exists. Please use a different name."],

        // 右键菜单
        "copy_config": [.chinese: "复制配置", .english: "Copy Config"],
        "copy_provider": [.chinese: "复制提供商", .english: "Copy Provider"],
        "delete_config": [.chinese: "删除配置", .english: "Delete Config"],

        // 列表
        "new_config": [.chinese: "新配置", .english: "New Config"],
        "config_name_field": [.chinese: "请求的模型名", .english: "Requested model"],
        "actual_model_field": [.chinese: "实际调用的模型", .english: "Actual model called"],

        // 提供商相关
        "providers": [.chinese: "提供商", .english: "Providers"],
        "provider_info": [.chinese: "提供商信息", .english: "Provider Info"],
        "provider_name": [.chinese: "名称", .english: "Name"],
        "provider_name_placeholder": [.chinese: "例如：我的 OpenAI", .english: "e.g. My OpenAI"],
        "new_provider": [.chinese: "新建提供商", .english: "New Provider"],
        "add_provider": [.chinese: "添加提供商", .english: "Add Provider"],
        "delete_provider": [.chinese: "删除提供商", .english: "Delete Provider"],
        "add_short": [.chinese: "添加", .english: "Add"],
        "delete_short": [.chinese: "删除", .english: "Delete"],
        "create_provider": [.chinese: "新建提供商", .english: "Create Provider"],
        "provider": [.chinese: "提供商", .english: "Provider"],
        "provider_missing": [.chinese: "提供商缺失", .english: "Provider Missing"],
        "provider_deleted_warning": [.chinese: "提供商已删除，请重新选择", .english: "Provider deleted, please reselect"],

        // 映射分组
        "model_mappings": [.chinese: "模型映射", .english: "Model Mappings"],
        "related_mappings": [.chinese: "模型映射", .english: "Model Mappings"],
        "mapping_status": [.chinese: "映射状态", .english: "Mapping Status"],
        "no_mappings": [.chinese: "暂无映射", .english: "No Mappings"],

        // 边栏
        "hide_provider_sidebar": [.chinese: "隐藏提供商边栏", .english: "Hide Provider Sidebar"],
        "show_provider_sidebar": [.chinese: "显示提供商边栏", .english: "Show Provider Sidebar"],
        "toggle_mapping_panel": [.chinese: "显示/隐藏模型映射总览", .english: "Show/Hide Mapping Panel"],

        // 删除确认
        "confirm_delete_mapping": [.chinese: "确认删除映射", .english: "Confirm Delete Mapping"],
        "confirm_delete_provider": [.chinese: "确认删除提供商", .english: "Confirm Delete Provider"],
        "confirm_delete_provider_msg": [.chinese: "确定要删除", .english: "Are you sure you want to delete"],
        "confirm_delete_provider_hint_prefix": [.chinese: "？该提供商已被 ", .english: "? This provider is used by "],
        "confirm_delete_provider_hint_suffix": [.chinese: " 个映射使用，删除后这些映射将失效", .english: " mapping(s). They will become invalid after deletion"],

        // 其他
        "delete_selected": [.chinese: "删除选中项", .english: "Delete Selected"],
    ]
}

extension L10n {
    // 快捷访问
    static func t(_ key: String) -> String {
        L10n(key: key).text
    }

    // 带参数的格式化（用于删除确认等需要嵌入名称的场景）
    static func format(_ key: String, _ arg: String) -> String {
        let pattern = L10n(key: key).text
        return pattern.replacingOccurrences(of: "{name}", with: arg)
    }
}
