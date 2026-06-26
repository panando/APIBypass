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
        "apibypass_service": [.chinese: "APIBypass服务", .english: "APIBypass Service"],
        "codex_adaptor_service": [.chinese: "Codex适配服务", .english: "Codex Adaptor Service"],
        "launch_codex": [.chinese: "启动 Codex", .english: "Launch Codex"],
        "bypass_mode": [.chinese: "纯代理模式", .english: "Bypass Mode"],
        "configure_apibypass": [.chinese: "配置: APIBypass", .english: "Configure: APIBypass"],
        "configure_codex_adaptor": [.chinese: "配置: Codex适配", .english: "Configure: Codex Adaptor"],
        "settings": [.chinese: "设置", .english: "Settings"],
        "quit": [.chinese: "退出", .english: "Quit"],
        "help": [.chinese: "帮助", .english: "Help"],
        "port": [.chinese: "端口", .english: "Port"],
        "version": [.chinese: "版本", .english: "Version"],
        "help_window_title": [.chinese: "APIBypass 帮助", .english: "APIBypass Help"],
        "help_quick_start": [.chinese: "快速入门", .english: "Quick Start"],
        "help_model_mapping": [.chinese: "模型映射", .english: "Model Mapping"],
        "help_parameter_injection": [.chinese: "参数注入", .english: "Parameter Injection"],
        "help_launcher": [.chinese: "启动 Claude Code", .english: "Launch Claude Code"],
        "help_bypass_mode": [.chinese: "纯代理模式", .english: "Bypass Mode"],
        "help_settings": [.chinese: "设置", .english: "Settings"],
        "help_faq": [.chinese: "常见问题", .english: "FAQ"],
        "help_menu_bar": [.chinese: "菜单栏", .english: "Menu Bar"],
        "help_thinking_protocol": [.chinese: "思考控制字段", .english: "Thinking Protocol"],
        "help_custom_models": [.chinese: "自定义模型", .english: "Custom Models"],

        // App Capabilities (empty state)
        "app_capabilities_title": [.chinese: "APIBypass 能做什么？", .english: "What can APIBypass do?"],
        "capability_model_mapping": [.chinese: "模型映射", .english: "Model Mapping"],
        "capability_model_mapping_desc": [.chinese: "透明切换模型，客户端无需修改代码", .english: "Switch models transparently without client code changes"],
        "capability_api_protocol": [.chinese: "API 协议转换", .english: "API Protocol Translation"],
        "capability_api_protocol_desc": [.chinese: "自动识别并转换 Chat Completions / Responses / Anthropic 格式", .english: "Auto-detect and convert Chat Completions / Responses / Anthropic formats"],
        "capability_thinking_protocol": [.chinese: "思考协议转换", .english: "Thinking Protocol Translation"],
        "capability_thinking_protocol_desc": [.chinese: "翻译 thinking/reasoning_effort 字段，跨模型保持兼容", .english: "Translate thinking/reasoning_effort fields for cross-model compatibility"],
        "capability_param_injection": [.chinese: "参数注入", .english: "Parameter Injection"],
        "capability_param_injection_desc": [.chinese: "统一注入 temperature、max_tokens 等采样参数", .english: "Inject temperature, max_tokens, and other sampling parameters"],
        "capability_claude_code": [.chinese: "Claude Code 支持", .english: "Claude Code Support"],
        "capability_claude_code_desc": [.chinese: "一键配置环境变量，无缝对接 Claude Code CLI", .english: "One-click environment setup for Claude Code CLI integration"],
        "capability_codex_adaptor": [.chinese: "Codex 适配器", .english: "Codex Adaptor"],
        "capability_codex_adaptor_desc": [.chinese: "支持 Chat Completions 和 Responses API 两种协议接入", .english: "Support both Chat Completions and Responses API protocols"],
        "capability_codex_unlock": [.chinese: "Codex 插件解锁", .english: "Codex Plugin Unlock"],
        "capability_codex_unlock_desc": [.chinese: "解锁插件入口、市场安装限制，扩展 Codex 能力", .english: "Unlock plugin entry, marketplace install restrictions to extend Codex"],

        // 设置面板
        "settings_title": [.chinese: "设置", .english: "Settings"],
        "language": [.chinese: "语言", .english: "Language"],
        "language_hint": [.chinese: "切换语言后立即生效", .english: "Changes take effect immediately"],
        "server_port": [.chinese: "API中转服务端口", .english: "API Relay Server Port"],
        "port_hint": [.chinese: "修改端口后需重启服务生效", .english: "Restart the server to apply port changes"],
        "trace_log": [.chinese: "追踪日志", .english: "Trace Log"],
        "trace_log_desc": [.chinese: "记录请求追踪日志到磁盘，用于调试", .english: "Write request trace logs to disk for debugging"],
        "trace_log_path": [.chinese: "日志路径", .english: "Log path"],
        "preserve_model_name": [.chinese: "模型名校正", .english: "Model Name Fix"],
        "preserve_model_name_desc": [.chinese: "开启后，API 响应中的 model 字段将返回客户端请求的模型名，而非上游实际模型名。适用于客户端对响应模型名做严格校验的场景。", .english: "When enabled, the model field in API responses returns the client's requested model name instead of the upstream actual model name. Useful when clients strictly validate the response model name."],
        "preserve_model_name_example": [.chinese: "示例：客户端请求 glm-5.1-ark → 上游实际调用 glm-5.1 → 响应返回 glm-5.1-ark", .english: "Example: Client requests glm-5.1-ark → upstream uses glm-5.1 → response returns glm-5.1-ark"],
        "about": [.chinese: "关于", .english: "About"],
        "about_description": [.chinese: "APIBypass 是一款 API 模型映射代理工具，可拦截客户端请求并注入自定义参数，无缝切换模型提供商。", .english: "APIBypass is an API model mapping proxy that intercepts client requests and injects custom parameters for seamless model provider switching."],
        "license": [.chinese: "许可证: MIT License", .english: "License: MIT License"],
        "github_repo": [.chinese: "https://github.com/panando/APIBypass", .english: "https://github.com/panando/APIBypass"],

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
        "api_provider": [.chinese: "API接口类型", .english: "API Format"],
        "base_url": [.chinese: "Base URL", .english: "Base URL"],
        "api_key": [.chinese: "API Key", .english: "API Key"],
        "reasoning_override": [.chinese: "更改默认推理模式", .english: "Reasoning Mode Override"],
        "enable_thinking": [.chinese: "是否启用思考模式", .english: "Enable Thinking Mode"],
        "thinking_protocol": [.chinese: "思考控制字段", .english: "Thinking Field"],
        "thinking_effort": [.chinese: "推理强度", .english: "Reasoning Effort"],
        "thinking_effort_hint": [.chinese: "如 none / minimal / low / medium / high / xhigh；留空则不注入", .english: "e.g. none / minimal / low / medium / high / xhigh; leave empty to skip"],
        "thinking_none_hint": [.chinese: "该模型自身控制思考，无需发送开关字段", .english: "This model controls thinking internally, no switch field needed"],
        "thinking_models_enable_thinking": [.chinese: "适用于 Qwen 系列：Qwen3.7-Max/Plus、Qwen3.6-Max/Flash、Qwen3 系列。此字段控制是否启用思考模式。", .english: "For Qwen series: Qwen3.7-Max/Plus, Qwen3.6-Max/Flash, Qwen3 series. Controls whether thinking is enabled."],
        "thinking_models_anthropic_native": [.chinese: "适用于 DeepSeek V4、GLM-4.5+/5、Kimi K2.5/K2.6、Doubao Seed、MiniMax M3、Claude 4.5。此字段控制思考模式开关。", .english: "For DeepSeek V4, GLM-4.5+/5, Kimi K2.5/K2.6, Doubao Seed, MiniMax M3, Claude 4.5. Controls thinking mode toggle."],
        "thinking_models_none": [.chinese: "适用于 OpenAI o1/o3/o4-mini、GPT-5.x、Grok、Mistral。此字段控制思考深度，none 表示关闭。", .english: "For OpenAI o1/o3/o4-mini, GPT-5.x, Grok, Mistral. Controls thinking depth; none disables thinking."],
        "thinking_not_supported": [.chinese: "该模型不支持思考模式", .english: "This model does not support thinking mode"],
        "thinking_always_on": [.chinese: "该模型强制开启思考模式，无法关闭", .english: "This model has thinking always on and cannot be disabled"],
        "unknown_model_warning": [.chinese: "未识别的模型，参数可见性可能不准确", .english: "Unknown model, parameter visibility may be inaccurate"],
        "protocol_mismatch_warning": [.chinese: "该模型推荐使用", .english: "Recommended protocol for this model:"],
        "param_injection": [.chinese: "参数注入", .english: "Parameter Injection"],
        "custom_params": [.chinese: "自定义参数", .english: "Custom Parameters"],
        "add_field": [.chinese: "添加字段", .english: "Add Field"],
        "add_custom_hint": [.chinese: "添加自定义 JSON 参数字段", .english: "Add custom JSON parameter fields"],
        "custom_hint": [.chinese: "提示: 值支持 JSON 格式，如 \"enable_thinking\":true, \"thinking\": {\"type\": \"disabled\"}", .english: "Tip: Values support JSON format, e.g. \"enable_thinking\":true, \"thinking\": {\"type\": \"disabled\"}"],
        "enable_config": [.chinese: "启用此配置", .english: "Enable This Config"],
        "save": [.chinese: "保存", .english: "Save"],
        "saved": [.chinese: "已保存", .english: "Saved"],
        "ok": [.chinese: "好的", .english: "OK"],
        "rename": [.chinese: "重命名", .english: "Rename"],
        "update": [.chinese: "更新", .english: "Update"],

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
        "stream_usage_toggle": [.chinese: "请求流式 token 用量", .english: "Request streaming token usage"],
        "stream_usage_desc": [.chinese: "开启后，APIBypass 会为该供应商的 OpenAI 兼容流式请求添加 stream_options.include_usage=true，让 Claude Code 等客户端可以显示上下文比例和 token 用量。\n\n当流式响应中的 token 用量显示为 0、缺失或不更新时，建议开启。\n\n如果开启后该供应商请求失败，或错误提示不支持 stream_options / include_usage，请关闭。", .english: "When enabled, APIBypass adds stream_options.include_usage=true to OpenAI-compatible streaming requests for this provider, allowing clients like Claude Code to display context percentage and token usage.\n\nEnable this when token usage in streaming responses shows as 0, is missing, or does not update.\n\nDisable it if requests to this provider fail after enabling it, or if the error says stream_options / include_usage is unsupported."],

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

        // Claude Code Launcher
        "launch_claude_code": [.chinese: "启动 Claude Code", .english: "Launch Claude Code"],
        "claude_code_launcher_title": [.chinese: "启动 Claude Code", .english: "Launch Claude Code"],
        "select_provider": [.chinese: "选择提供商", .english: "Select Provider"],
        "select_model_mapping": [.chinese: "选择模型映射", .english: "Select Model Mapping"],
        "environment_variables": [.chinese: "环境变量", .english: "Environment Variables"],
        "environment_variables_preview": [.chinese: "环境变量预览", .english: "Environment Variables Preview"],
        "envvar_manual": [.chinese: "手动输入", .english: "Manual Input"],
        "envvar_model_mapping": [.chinese: "模型映射", .english: "Model Mapping"],
        "envvar_keychain_token": [.chinese: "API Token", .english: "API Token"],
        "envvar_base_url": [.chinese: "Base URL", .english: "Base URL"],
        "envvar_name": [.chinese: "变量名", .english: "Variable Name"],
        "envvar_type": [.chinese: "类型", .english: "Type"],
        "envvar_value": [.chinese: "值", .english: "Value"],
        "add_envvar": [.chinese: "添加环境变量", .english: "Add Environment Variable"],
        "reset_to_default": [.chinese: "重置为默认", .english: "Reset to Default"],
        "use_first_mapping": [.chinese: "使用第一个可用映射", .english: "Use First Available Mapping"],
        "claude_code_not_found": [.chinese: "未找到 Claude Code", .english: "Claude Code Not Found"],
        "claude_code_not_found_msg": [.chinese: "请确保已安装 Claude Code 并在 PATH 中可用", .english: "Please ensure Claude Code is installed and available in PATH"],
        "no_mappings_for_provider": [.chinese: "该提供商没有可用的模型映射", .english: "No enabled mappings for this provider"],
        "edit_envvar": [.chinese: "编辑", .english: "Edit"],
        "claude_code_env_vars_title": [.chinese: "Claude Code 环境变量", .english: "Claude Code Environment Variables"],
        "claude_code_env_vars_desc": [.chinese: "配置启动 Claude Code 时注入的环境变量", .english: "Configure environment variables to inject when launching Claude Code"],
        "add_env_var": [.chinese: "添加环境变量", .english: "Add Environment Variable"],
        "env_var_name": [.chinese: "变量名", .english: "Variable Name"],
        "env_var_type": [.chinese: "类型", .english: "Type"],
        "env_var_value": [.chinese: "值", .english: "Value"],
        "select_model": [.chinese: "选择模型", .english: "Select Model"],
        "auto_select_first": [.chinese: "自动选择第一个", .english: "Auto Select First"],
        "read_from_keychain": [.chinese: "从 Keychain 读取", .english: "Read from Keychain"],
        "please_select": [.chinese: "请选择", .english: "Please Select"],
        "none": [.chinese: "无", .english: "None"],
        "launch": [.chinese: "启动", .english: "Launch"],
        "optional": [.chinese: "可选", .english: "Optional"],
        "no_provider_selected": [.chinese: "未选择提供商", .english: "No Provider Selected"],
        "api_key_not_set": [.chinese: "(未设置)", .english: "(Not Set)"],
        "select_terminal": [.chinese: "终端", .english: "Terminal"],
        "model_settings": [.chinese: "模型配置", .english: "Model Settings"],
        "launch_claude_code_desc": [.chinese: "在终端中启动 Claude Code 并注入环境变量", .english: "Launch Claude Code in terminal with environment variables"],
        "launcher_terminal_not_found": [.chinese: "未找到可用的终端应用", .english: "No terminal application found"],
        "working_directory": [.chinese: "工作目录", .english: "Working Directory"],
        "working_directory_hint": [.chinese: "留空使用用户主目录", .english: "Leave empty for home directory"],

        // Launcher errors
        "launcher_claude_not_found": [.chinese: "未找到 Claude Code", .english: "Claude Code not found"],
        "launcher_failed": [.chinese: "启动失败", .english: "Launch failed"],
        "launcher_keychain_failed": [.chinese: "Keychain 读取失败", .english: "Keychain read failed"],
        "launcher_accessibility_denied": [.chinese: "需要辅助功能权限：请前往「系统设置 > 隐私与安全性 > 辅助功能」，将本应用添加到允许列表", .english: "Accessibility permission required: go to System Settings > Privacy & Security > Accessibility and add this app to the allowed list"],
        "launcher_open_accessibility": [.chinese: "打开系统设置", .english: "Open System Settings"],

        // API Provider types
        "provider_type_openai": [.chinese: "OpenAI Chat API", .english: "OpenAI Chat API"],
        "provider_type_anthropic": [.chinese: "Anthropic API", .english: "Anthropic API"],
        "provider_type_responses": [.chinese: "Responses API", .english: "Responses API"],

        // Provider groups
        "provider_group_chat_completions": [.chinese: "Chat Completions 提供商", .english: "Chat Completions Providers"],
        "provider_group_anthropic": [.chinese: "Anthropic 提供商", .english: "Anthropic Providers"],
        "provider_group_responses": [.chinese: "Responses API 提供商", .english: "Responses API Providers"],

        // Responses API warnings
        "provider_responses_warning_title": [.chinese: "Responses API 提供商", .english: "Responses API Provider"],
        "provider_responses_warning_desc": [.chinese: "Responses API 提供商仅适用于支持 Responses API 格式的客户端（如 Codex），无法用于 Chat Completions 格式的请求。请求将直接透传，不进行格式转换。", .english: "Responses API providers only support clients that use Responses API format (e.g., Codex). They cannot be used with Chat Completions format requests. Requests will be passed through directly without format conversion."],
        "provider_responses_note_title": [.chinese: "仅限 Responses API", .english: "Responses API Only"],
        "provider_responses_note_desc": [.chinese: "此提供商仅接受 /v1/responses 端点的请求，适用于 Codex 等 Responses API 客户端。请求将直接透传，不进行格式转换。", .english: "This provider only accepts requests to /v1/responses endpoint. It works with Codex and other Responses API clients. Requests are passed through directly without format conversion."],

        "attribution_header": [.chinese: "禁用 attribution header", .english: "Disable Attribution Header"],
        "attribution_header_desc": [.chinese: "设置 CLAUDE_CODE_ATTRIBUTION_HEADER=0，从源头避免动态 cch 值破坏 prompt 前缀缓存", .english: "Set CLAUDE_CODE_ATTRIBUTION_HEADER=0 to prevent dynamic cch values from breaking prompt prefix caching at the source"],
        "attribution_header_note": [.chinese: "即使不开启此开关，代理层也会自动过滤掉请求中的 billing header", .english: "The proxy layer also automatically filters billing headers from requests even without this switch"],

        "rectifier": [.chinese: "启用整流器", .english: "Enable Rectifier"],
        "rectifier_desc": [.chinese: "当上游 API 返回 thinking signature 或 budget 错误时，自动修复请求并重试。不影响正常请求。", .english: "Automatically fix and retry requests when upstream returns thinking signature or budget errors. No impact on normal requests."],

        // Parameter names
        "param_temperature": [.chinese: "温度", .english: "Temperature"],
        "param_max_tokens": [.chinese: "最大Token数", .english: "Max Tokens"],
        "param_top_p": [.chinese: "Top P", .english: "Top P"],
        "param_frequency_penalty": [.chinese: "频率惩罚", .english: "Frequency Penalty"],
        "param_presence_penalty": [.chinese: "存在惩罚", .english: "Presence Penalty"],

        // 工作目录历史
        "no_recent_dirs": [.chinese: "暂无历史目录", .english: "No Recent Directories"],
        "clear_history": [.chinese: "清除历史", .english: "Clear History"],

        // 帮助内容 - 快速入门
        "help_quick_start_title": [.chinese: "欢迎使用 APIBypass", .english: "Welcome to APIBypass"],
        "help_quick_start_desc": [.chinese: "APIBypass 是一个跑在本地的 API 中转代理。客户端把请求发给它，它按你设定的规则改写请求（换模型、改参数、转格式），再转发到真正的上游模型提供商，最后把响应原样或转格式后送回客户端。这样一来，客户端无需改代码，就能在不同模型与提供商之间自由切换；它还集成了思考协议转换、Codex 适配器、一键启动 Claude Code 等能力，覆盖常见的工作流需求。", .english: "APIBypass is a local API relay proxy. The client sends requests to it; it rewrites them according to your rules (swap model, tweak params, convert format), forwards to the real upstream model provider, and returns the response — converted back if needed. The client never changes code, yet can freely switch between models and providers. It also bundles thinking-protocol translation, a Codex adaptor, one-click Claude Code launching, and more, covering common workflow needs."],
        "help_quick_start_features_title": [.chinese: "核心特性", .english: "Key Features"],
        "help_quick_start_feature_mapping": [.chinese: "模型映射 — 很多客户端把模型名写死在配置里。模型映射让你在客户端继续用「gpt-4」这样的名字，后端却实际调用「claude-sonnet-4-6」或任意其他模型，切换模型不必改客户端。", .english: "Model Mapping — many clients hard-code the model name. Model mapping lets the client keep using a name like \"gpt-4\" while the backend actually calls \"claude-sonnet-4-6\" or any other model — switch models without touching the client."],
        "help_quick_start_feature_params": [.chinese: "参数注入 — 自动注入或覆盖 temperature、max_tokens、Top P 等标准参数，也可添加任意自定义 JSON 字段。用来统一多客户端的采样策略，或补上客户端没发但上游需要的字段。", .english: "Parameter Injection — auto-inject or override standard params like temperature/max_tokens/Top P, or add arbitrary custom JSON fields. Use it to unify sampling policy across clients, or to supply fields the client omits but the upstream requires."],
        "help_quick_start_feature_thinking": [.chinese: "思考协议转换 — 不同模型用不同字段控制思考（enable_thinking / thinking.type / reasoning_effort），互不兼容，换了模型思考往往就失效。APIBypass 按目标模型自动翻译这些字段，让思考在跨模型时仍能正确开关。", .english: "Thinking Protocol Translation — different models control thinking with different fields (enable_thinking / thinking.type / reasoning_effort) that are mutually incompatible, so thinking often breaks when you switch models. APIBypass auto-translates these fields for the target model, keeping thinking correctly toggled across models."],
        "help_quick_start_feature_namefix": [.chinese: "模型名校正 — 响应里的 model 字段会被改回客户端请求的名字，而不是上游实际模型名。当客户端会校验响应模型名是否与请求一致（不一致就报错）时开启。", .english: "Model Name Fix — the model field in responses is rewritten back to the client-requested name instead of the upstream actual name. Enable it when the client validates that the response model matches the request and errors out otherwise."],
        "help_quick_start_feature_bypass": [.chinese: "纯代理模式 — 当上游提供商原生就支持客户端的 API 格式（例如客户端发 OpenAI 格式、上游也是 OpenAI 兼容）时，跳过格式转换、原样透传，避免不必要的改写。", .english: "Bypass Mode — when the upstream provider natively supports the client's API format (e.g. client sends OpenAI format and the upstream is OpenAI-compatible), skip format conversion and pass through as-is to avoid unnecessary rewrites."],
        "help_quick_start_feature_codex": [.chinese: "Codex 适配器 — OpenAI Codex 只走 Responses API，而很多提供商（尤其国内的 Anthropic 兼容接口）只提供 Chat Completions。适配器把 Codex 的 Responses API 翻译成 Chat Completions，再交给 APIBypass 中转；两层叠加后，OpenAI 兼容与 Anthropic 接口的提供商都能接入 Codex。", .english: "Codex Adaptor — OpenAI Codex speaks only the Responses API, while many providers (especially Anthropic-compatible ones) only offer Chat Completions. The adaptor translates Codex's Responses API into Chat Completions and forwards to APIBypass; with the two chained, both OpenAI-compatible and Anthropic-API providers can be used with Codex."],
        "help_quick_start_feature_custom_models": [.chinese: "自定义模型 — Codex 默认只能看到 OpenAI 官方模型列表，无法直接选用你接的其他模型。自定义模型让你给经 APIBypass 中转的模型起一个别名、配上上下文长度，之后就能在 Codex 里像选普通模型一样选用它们。", .english: "Custom Models — Codex only lists OpenAI's official models by default and can't directly use your other models. Custom Models lets you alias APIBypass-relayed models and set their context length, after which they show up in Codex and can be picked like any built-in model."],
        "help_quick_start_feature_launcher": [.chinese: "一键启动 Claude Code — 自动注入 ANTHROPIC_BASE_URL、ANTHROPIC_AUTH_TOKEN、ANTHROPIC_MODEL 等环境变量，从钥匙串读取 API Key，还支持按角色（Opus/Sonnet/Haiku/子代理）指定模型、缓存优化、整流器、配置模板等。", .english: "One-click Claude Code Launch — auto-injects env vars like ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, ANTHROPIC_MODEL, reads the API Key from Keychain, and supports per-role model assignment (Opus/Sonnet/Haiku/Subagent), cache optimization, the rectifier, config templates, and more."],
        "help_quick_start_feature_trace": [.chinese: "请求追踪日志 — 开启后，每个请求的上下游原始报文、SSE 事件、字段翻译过程都会写入日志文件。当流式响应出现丢字、截断或内容错乱时，可据此定位是哪一段出了问题。", .english: "Request Trace Logs — when enabled, the raw upstream/downstream payloads, SSE events, and field-translation process for each request are written to a log file. When a streaming response loses characters, gets truncated, or shows garbled content, use it to pinpoint which stage went wrong."],
        "help_quick_start_feature_bilingual": [.chinese: "中英双语界面 — 随时切换语言。", .english: "Bilingual UI (Chinese/English) — switch anytime."],
        "help_quick_start_steps_title": [.chinese: "快速上手", .english: "Quick Start"],
        "help_quick_start_step1": [.chinese: "点击菜单栏图标，选择「配置: APIBypass」打开配置窗口。", .english: "Click the menu bar icon and select \"Configure: APIBypass\" to open the config window."],
        "help_quick_start_step2": [.chinese: "创建至少一个提供商（Provider，填 Base URL、接口类型、API Key），再建一条模型映射（客户端模型名 → 实际模型名，挂在该提供商下）。", .english: "Create at least one provider (Base URL, API format, API Key), then a model mapping (incoming model name → actual model name) attached to it."],
        "help_quick_start_step3": [.chinese: "启动服务后，把客户端的 API base URL 指向 http://127.0.0.1:8390/v1，model 字段填你在映射里设置的客户端模型名即可。", .english: "Start the server, then point the client's API base URL at http://127.0.0.1:8390/v1 and set the model field to the incoming model name you configured in the mapping."],
        "help_quick_start_codex_title": [.chinese: "使用 Codex 桌面端", .english: "Using Codex Desktop"],
        "help_quick_start_codex_desc": [.chinese: "如果你使用 OpenAI Codex 桌面端，可以通过以下步骤接入：", .english: "If you use OpenAI Codex desktop, follow these steps to connect:"],
        "help_quick_start_codex_step1": [.chinese: "在菜单栏点击「启动Codex」，或选择「配置: Codex适配」打开窗口后在「增强」标签页点击启动按钮。", .english: "Click \"Launch Codex\" in the menu bar, or open \"Configure: Codex Adaptor\" and click the launch button in the \"Enhancements\" tab."],
        "help_quick_start_codex_step2": [.chinese: "系统会自动启动 Codex 适配服务和 Codex 应用，并注入 CDP 脚本启用插件增强功能。", .english: "The system will automatically start the Codex adaptor service and the Codex app, and inject the CDP script to enable plugin enhancements."],
        "help_quick_start_codex_step3": [.chinese: "在「配置: Codex适配」的「服务」标签页配置自定义模型，映射到你的 APIBypass 模型映射。", .english: "Configure custom models in the \"Service\" tab of \"Configure: Codex Adaptor\", mapping them to your APIBypass model mappings."],
        "help_quick_start_note": [.chinese: "提示：默认服务端口为 8390，可在「设置」中修改。各功能的详细说明见左侧目录对应章节。", .english: "Tip: the default server port is 8390, changeable in \"Settings.\" See the sidebar for detailed docs on each feature."],

        // 帮助内容 - 菜单栏
        "help_menu_bar_desc": [.chinese: "点击菜单栏中的 APIBypass 图标，可以看到以下选项：", .english: "Click the APIBypass icon in the menu bar to see the following options:"],
        "help_menu_icon_status": [.chinese: "图标状态 — 菜单栏图标上有两个小圆点：左上角显示 Codex 适配服务状态，右上角显示 APIBypass 服务状态。绿色表示运行中，灰色表示未运行。", .english: "Icon Status — the menu bar icon shows two small dots: the top-left dot indicates Codex Adaptor status, the top-right dot indicates APIBypass server status. Green means running, gray means stopped."],
        "help_menu_indicator": [.chinese: "菜单项状态指示器 — 菜单项左侧的 ●（实心圆）表示运行中/已开启，○（空心圆）表示未运行/已关闭。", .english: "Menu Item Indicators — ● (solid circle) on the left of a menu item means running/enabled, ○ (hollow circle) means stopped/disabled."],
        "help_menu_apibypass_service": [.chinese: "APIBypass服务 — 切换代理服务的启停。服务运行时菜单项显示 ●，未运行时显示 ○。", .english: "APIBypass Service — toggle the proxy server on/off. Shows ● when running, ○ when stopped."],
        "help_menu_codex_service": [.chinese: "Codex适配服务 — 切换 Codex 适配服务的启停。服务运行时菜单项显示 ●，未运行时显示 ○。", .english: "Codex Adaptor Service — toggle the Codex adaptor on/off. Shows ● when running, ○ when stopped."],
        "help_menu_bypass": [.chinese: "纯代理模式 — 切换是否跳过 API 格式转换。开启时菜单项显示 ●，关闭时显示 ○。", .english: "Bypass Mode — toggle whether to skip API format conversion. Shows ● when enabled, ○ when disabled."],
        "help_menu_launch_codex": [.chinese: "启动Codex — 启动 Codex 桌面应用并注入 CDP 脚本，启用插件增强功能。如果 Codex 已在运行，此菜单项会被禁用。点击后会自动启动 Codex 适配服务（如果未运行）。", .english: "Launch Codex — start the Codex desktop app with CDP script injection to enable plugin enhancements. Disabled when Codex is already running. Automatically starts the Codex adaptor service if not running."],
        "help_menu_launcher": [.chinese: "启动Claude Code — 打开 Claude Code 启动器，配置环境变量后一键启动 Claude Code。", .english: "Launch Claude Code — open the launcher to configure env vars and launch Claude Code."],
        "help_menu_configure": [.chinese: "配置: APIBypass — 打开模型映射配置窗口，管理提供商和映射规则。", .english: "Configure: APIBypass — open the model mapping config window to manage providers and mappings."],
        "help_menu_codex_window": [.chinese: "配置: Codex适配 — 打开 Codex 适配器配置窗口，设置服务端口、CDP 注入、插件增强等。", .english: "Configure: Codex Adaptor — open the Codex adaptor config window to set service port, CDP injection, plugin enhancements, etc."],
        "help_menu_settings": [.chinese: "设置 — 打开应用设置窗口，切换语言、修改端口、管理追踪日志。", .english: "Settings — open the settings window to switch language, change port, and manage trace logs."],
        "help_menu_help": [.chinese: "帮助 — 打开本帮助文档。", .english: "Help — open this help document."],
        "help_menu_about": [.chinese: "关于 — 查看 APIBypass 版本信息。", .english: "About — view APIBypass version info."],
        "help_menu_quit": [.chinese: "退出 — 关闭应用。", .english: "Quit — close the app."],

        // 帮助内容 - 模型映射
        "help_model_mapping_title": [.chinese: "模型映射", .english: "Model Mapping"],
        "help_model_mapping_desc": [.chinese: "模型映射把客户端请求的模型名映射到上游提供商的实际模型名。例如客户端请求「gpt-4」，实际可以被映射到「claude-sonnet-4-6」。这样客户端无需改动代码，就能透明地切换到任意模型。", .english: "Model mapping maps the model name requested by the client to the actual model name on the upstream provider. For example, a client requesting \"gpt-4\" can be mapped to \"claude-sonnet-4-6\". The client switches to any model transparently, without code changes."],
        "help_model_mapping_provider_title": [.chinese: "提供商", .english: "Provider"],
        "help_model_mapping_provider_desc": [.chinese: "「提供商」是 Base URL、API 接口类型（OpenAI / Anthropic）与 API Key 的集合，可被多条模型映射复用。在配置窗口左侧管理提供商，每条映射挂在某个提供商下。API Key 安全保存在 macOS 钥匙串中，不写入配置文件。", .english: "A \"Provider\" bundles a Base URL, API format (OpenAI / Anthropic), and API Key, and can be reused by multiple model mappings. Manage providers on the left of the config window; each mapping belongs to one provider. The API Key is stored securely in the macOS Keychain, never in config files."],
        "help_model_mapping_fields_title": [.chinese: "映射字段", .english: "Mapping Fields"],
        "help_model_mapping_fields": [.chinese: "每条映射规则包含：客户端模型名、实际模型名、所属提供商、推理模式覆盖、参数注入、自定义参数等。", .english: "Each mapping rule includes: incoming model name, actual model name, parent provider, reasoning mode override, parameter injection, custom parameters, and more."],
        "help_model_mapping_enable_title": [.chinese: "启用 / 禁用", .english: "Enable / Disable"],
        "help_model_mapping_enable_desc": [.chinese: "每条映射可单独启用或禁用（「启用此配置」开关）。禁用的映射不会匹配任何请求，方便临时切换而不删除配置。", .english: "Each mapping can be enabled or disabled individually (the \"Enable This Config\" toggle). A disabled mapping never matches requests — handy for temporary switches without deleting the config."],
        "help_model_mapping_reasoning": [.chinese: "「更改默认推理模式」通过 enable_thinking 参数设置；如果模型提供商使用其他字段控制思考模式，请在「自定义参数」中手动添加，或使用「思考控制字段」选择对应协议。", .english: "Reasoning Mode Override is set via the enable_thinking parameter. If your provider uses a different field for thinking mode, add it manually in Custom Parameters, or pick the matching protocol in Thinking Protocol."],
        "help_model_mapping_name_fix_title": [.chinese: "模型名校正", .english: "Model Name Fix"],
        "help_model_mapping_name_fix": [.chinese: "开启后，API 响应中的 model 字段会返回客户端请求的模型名，而不是上游实际模型名。适用于客户端对响应模型名做严格校验的场景。", .english: "When enabled, the model field in API responses returns the client's requested model name instead of the upstream actual name. Useful when clients strictly validate the response model name."],
        "help_model_mapping_stream_usage_title": [.chinese: "流式 token 用量", .english: "Streaming Token Usage"],
        "help_model_mapping_stream_usage_desc": [.chinese: "这是提供商级开关。开启后，APIBypass 会为该提供商的 OpenAI 兼容流式请求自动添加 stream_options.include_usage=true，让 Claude Code 等客户端能显示上下文比例和 token 用量。当流式响应中的 token 用量显示为 0、缺失或不更新时建议开启；若开启后该提供商请求失败或报错不支持 stream_options / include_usage，请关闭。", .english: "This is a provider-level toggle. When enabled, APIBypass adds stream_options.include_usage=true to OpenAI-compatible streaming requests for that provider, so clients like Claude Code can display the context percentage and token usage. Enable it when streaming token usage shows 0, is missing, or doesn't update; disable it if the provider errors out or says stream_options / include_usage is unsupported."],

        // 帮助内容 - 参数注入
        "help_param_injection_title": [.chinese: "参数注入", .english: "Parameter Injection"],
        "help_param_injection_desc": [.chinese: "参数注入在转发请求时自动添加或覆盖特定参数，省去逐个改客户端的麻烦。支持温度（temperature）、最大 Token 数（max_tokens）、Top P、频率惩罚和存在惩罚。例如可把所有客户端的 temperature 统一压到 0.7，或强制 max_tokens 不超过某上限。", .english: "Parameter injection automatically adds or overrides specific parameters when forwarding requests, saving you from editing each client. It supports temperature, max_tokens, Top P, frequency penalty, and presence penalty. For example, clamp every client's temperature to 0.7, or cap max_tokens at a ceiling."],
        "help_custom_params": [.chinese: "此外，你还可以通过「自定义参数」添加任意 JSON 字段（例如 enable_thinking、thinking），用来注入标准参数之外的自定义开关或配置。", .english: "You can also add arbitrary JSON fields via \"Custom Parameters\" (e.g. enable_thinking, thinking) to inject custom switches or config beyond the standard parameters."],

        // 帮助内容 - 启动 Claude Code
        "help_launcher_title": [.chinese: "启动 Claude Code", .english: "Launch Claude Code"],
        "help_launcher_desc": [.chinese: "启动器可以一键启动 Claude Code，自动注入 ANTHROPIC_BASE_URL、ANTHROPIC_AUTH_TOKEN、ANTHROPIC_MODEL 等环境变量，并从 macOS 钥匙串读取 API Key，无需手动配置。它还支持按角色指定模型、关闭归因 Header 以保护缓存、保存配置模板等进阶用法。", .english: "The launcher starts Claude Code with one click, auto-injecting env vars like ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, and ANTHROPIC_MODEL, and reads the API Key from the macOS Keychain — no manual setup needed. It also supports per-role model assignment, disabling the attribution header to preserve caching, saving config templates, and more."],
        "help_launcher_features_title": [.chinese: "主要功能", .english: "Features"],
        "help_launcher_feature_terminal": [.chinese: "选择终端应用与工作目录，支持在新窗口或新标签页中启动。", .english: "Choose terminal app and working directory; launch in a new window or a new tab."],
        "help_launcher_feature_role_models": [.chinese: "为 Opus / Sonnet / Haiku / 子代理（Subagent）分别指定模型，并自动为已知 1M 上下文模型追加 [1m] 后缀。", .english: "Assign models per role (Opus / Sonnet / Haiku / Subagent); automatically appends the [1m] suffix for known 1M-context models."],
        "help_launcher_feature_effort": [.chinese: "通过 CLAUDE_CODE_EFFORT_LEVEL 设置推理强度。", .english: "Set reasoning effort via CLAUDE_CODE_EFFORT_LEVEL."],
        "help_launcher_feature_custom_env": [.chinese: "手动添加任意额外环境变量（如 MAX_THINKING_TOKENS、API_TIMEOUT 等），满足自定义需求。", .english: "Manually add arbitrary extra env vars (e.g. MAX_THINKING_TOKENS, API_TIMEOUT) for custom needs."],
        "help_launcher_feature_cache": [.chinese: "可选关闭动态归因 Header（设置 CLAUDE_CODE_ATTRIBUTION_HEADER=0），避免破坏 prompt 前缀缓存，提升缓存命中率与响应速度。", .english: "Optionally disable the dynamic attribution header (sets CLAUDE_CODE_ATTRIBUTION_HEADER=0) to preserve prompt-prefix caching, improving cache hits and response speed."],
        "help_launcher_feature_templates": [.chinese: "把一组配置保存为模板，快速切换不同提供商或模型组合。", .english: "Save a set of configurations as a template to quickly switch between provider/model setups."],
        "help_launcher_feature_keychain": [.chinese: "API Key 从 macOS 钥匙串读取，不会写入文件，也不会出现在进程参数中，避免泄露。", .english: "API Key is read from the macOS Keychain — never written to a file or exposed in process arguments, preventing leakage."],
        "help_launcher_feature_rectifier": [.chinese: "整流器（默认开启）：当上游返回 thinking signature 或 budget 相关错误时，自动修复请求并重试，不影响正常请求。", .english: "Rectifier (on by default): when the upstream returns thinking-signature or budget errors, automatically fixes the request and retries — no impact on normal requests."],
        "help_launcher_workflow_title": [.chinese: "典型工作流", .english: "Typical Workflow"],
        "help_launcher_workflow_1": [.chinese: "在「配置」窗口创建好模型映射（例如把 claude-sonnet-4-6 映射到你的上游模型）。", .english: "Create a model mapping in the \"Configure\" window (e.g. map claude-sonnet-4-6 to your upstream model)."],
        "help_launcher_workflow_2": [.chinese: "在启动器中选择该映射对应的提供商，按需为 Opus / Sonnet / Haiku / 子代理指定模型。", .english: "In the launcher, pick the provider tied to that mapping and, optionally, assign models per role (Opus / Sonnet / Haiku / Subagent)."],
        "help_launcher_workflow_3": [.chinese: "选择终端应用与工作目录，按需开启缓存优化、添加额外环境变量。", .english: "Choose the terminal app and working directory; optionally enable the cache optimization and add extra env vars."],
        "help_launcher_workflow_4": [.chinese: "点击启动，Claude Code 会在终端中打开，环境变量已就绪，可直接使用。", .english: "Click launch — Claude Code opens in the terminal with env vars ready; you can start using it right away."],
        "help_launcher_note": [.chinese: "提示：首次启动可能需要授予辅助功能权限，以便在终端中自动输入命令。如遇权限提示，按指引在「系统设置 > 隐私与安全性 > 辅助功能」中授权即可。", .english: "Tip: the first launch may prompt for Accessibility permission so the launcher can type the command into the terminal automatically. If prompted, grant access under System Settings > Privacy & Security > Accessibility."],

        // 帮助内容 - 纯代理模式
        "help_bypass_title": [.chinese: "纯代理模式", .english: "Bypass Mode"],
        "help_bypass_desc": [.chinese: "开启纯代理模式后，应用会原样透传上下游之间的请求和响应，不做任何 API 格式转换。适用于上游提供商原生支持客户端 API 格式的场景。", .english: "When Bypass Mode is enabled, the app passes all requests and responses between client and upstream as-is, with no API format conversion. Suitable when the upstream provider natively supports the client's API format."],
        "help_bypass_note": [.chinese: "注意：纯代理模式下，模型映射配置（参数注入、自定义参数、推理模式等）仍然生效。", .english: "Note: in Bypass Mode, model mapping configurations (parameter injection, custom parameters, reasoning mode, etc.) still take effect."],

        // 帮助内容 - 设置
        "help_settings_title": [.chinese: "设置", .english: "Settings"],
        "help_settings_desc": [.chinese: "在「设置」窗口中，你可以：", .english: "In the \"Settings\" window, you can:"],
        "help_settings_lang": [.chinese: "切换界面语言（中文 / 英文）。", .english: "Switch the interface language (Chinese / English)."],
        "help_settings_port": [.chinese: "修改服务监听端口（修改后需重启服务）。", .english: "Change the server listening port (requires a server restart)."],
        "help_settings_trace_log": [.chinese: "开启或关闭请求追踪日志（用于排查流式翻译丢包问题），开启后会显示日志文件路径。", .english: "Enable or disable request trace logs (for debugging stream-translation packet loss); the log file path is shown when enabled."],

        // 帮助内容 - 思考控制字段
        "help_thinking_protocol_title": [.chinese: "思考控制字段", .english: "Thinking Protocol"],
        "help_thinking_protocol_desc": [.chinese: "不同模型提供商使用不同字段控制思考模式。APIBypass 支持三种协议，按模型实际支持的字段选择即可：", .english: "Different model providers use different fields to control thinking mode. APIBypass supports three protocols — pick the one matching your model's supported field:"],
        "help_thinking_protocol_opt_enable": [.chinese: "enable_thinking — 适用于 Qwen3 系列（DashScope），通过 enable_thinking 布尔字段开关思考。", .english: "enable_thinking — for the Qwen3 series (DashScope), toggles thinking via the enable_thinking boolean field."],
        "help_thinking_protocol_opt_anthropic": [.chinese: "thinking.type — 适用于 Claude、GLM、Kimi、DeepSeek、Doubao 等模型，通过 thinking.type 字段控制。", .english: "thinking.type — for Claude, GLM, Kimi, DeepSeek, Doubao, etc., controlled via the thinking.type field."],
        "help_thinking_protocol_opt_none": [.chinese: "none — 不发送开关字段，由模型自身控制思考；对 o 系列、gpt-5 等可附加 reasoning_effort 程度。", .english: "none — no switch field sent; the model controls thinking internally. For o-series, gpt-5, etc., a reasoning_effort level can be attached."],
        "help_thinking_protocol_effort": [.chinese: "推理强度：可选 none / minimal / low / medium / high / xhigh，留空则不注入。仅在思考控制字段为 none 时生效。", .english: "Reasoning Effort: none / minimal / low / medium / high / xhigh; leave empty to skip. Only effective when Thinking Protocol is none."],
        "help_thinking_protocol_note": [.chinese: "在新建或编辑模型映射时选择对应字段，APIBypass 会在转发请求时自动按目标协议注入或翻译思考参数。", .english: "Select the matching field when creating or editing a model mapping; APIBypass will automatically inject or translate thinking parameters in the target protocol when forwarding."],

        // 帮助内容 - 自定义模型
        "help_custom_models_title": [.chinese: "自定义模型", .english: "Custom Models"],
        "help_custom_models_desc": [.chinese: "自定义模型是 Codex 适配器的功能，用于把经 APIBypass 中转的模型暴露给 Codex。每个自定义模型由以下字段定义：", .english: "Custom Models is a Codex Adaptor feature that exposes APIBypass-relayed models to Codex. Each custom model is defined by:"],
        "help_custom_models_alias": [.chinese: "别名 — 在 Codex 中显示的模型名。", .english: "Alias — the model name shown in Codex."],
        "help_custom_models_source": [.chinese: "模型（来自 APIBypass）— 从已配置的模型映射中选择实际上游模型。", .english: "Model (from APIBypass) — select the actual upstream model from configured model mappings."],
        "help_custom_models_ctx": [.chinese: "上下文窗口 — 设置该模型的上下文长度。", .english: "Context Window — set the context length for the model."],
        "help_custom_models_note": [.chinese: "配置完成后，在 Codex 中即可通过别名调用对应模型，请求会经由 Codex 适配器转发到 APIBypass，再到上游提供商。", .english: "Once configured, you can call the model by its alias in Codex; requests are forwarded via the Codex Adaptor to APIBypass, and then to the upstream provider."],

        // 帮助内容 - Codex Adaptor
        "help_codex_adaptor_title": [.chinese: "Codex 适配器", .english: "Codex Adaptor"],
        "help_codex_adaptor_desc": [.chinese: "Codex 适配器是面向 OpenAI Codex 的本地 Responses API 代理。Codex 原生只走 Responses API，而很多模型提供商（尤其是国内的 Anthropic 兼容接口）只提供 Chat Completions。适配器把 Codex 的 Responses API 调用翻译成 Chat Completions 格式，再交给 APIBypass 中转。两层服务叠加之后，无论提供商是 OpenAI 兼容还是 Anthropic 接口，都能接入 Codex。", .english: "The Codex Adaptor is a local Responses API proxy for OpenAI Codex. Codex natively speaks only the Responses API, while many providers (especially Anthropic-compatible ones) only offer Chat Completions. The adaptor translates Codex's Responses API calls into Chat Completions format, then forwards them to APIBypass. With the two services chained, both OpenAI-compatible and Anthropic-API providers can be used with Codex."],
        "help_codex_usage_title": [.chinese: "使用方法", .english: "How to Use"],
        "help_codex_usage_1": [.chinese: "从菜单栏选择「配置: Codex适配」打开 Codex 适配器窗口。", .english: "Select \"Configure: Codex Adaptor\" from the menu bar to open the Codex adaptor window."],
        "help_codex_usage_2": [.chinese: "在窗口中设置监听端口（默认 15721，可改为 1–65535 任意空闲端口），点击「启动」。", .english: "Set the listening port in the window (default 15721; any free port 1–65535), then click \"Start\"."],
        "help_codex_usage_3": [.chinese: "把 Codex 的 API base URL 配置为 http://127.0.0.1:<端口>/v1。", .english: "Point Codex's API base URL to http://127.0.0.1:<port>/v1."],
        "help_codex_usage_note": [.chinese: "提示：Codex 默认会校验 API Key。适配器不要求真实 Key，任意非空字符串即可；真正的鉴权由 APIBypass 在转发时用模型映射中配置的 Key 完成。端口被占用时可在窗口里直接改。", .english: "Tip: Codex validates the API Key by default. The adaptor does not require a real key — any non-empty string works; actual authentication is handled by APIBypass using the key configured in the model mapping. If the port is in use, change it directly in the window."],
        "help_codex_config_title": [.chinese: "配置项", .english: "Configuration"],
        "help_codex_config_1": [.chinese: "监听端口 — 默认 15721，可改为任意空闲端口；修改后重启适配服务生效。", .english: "Listening Port — default 15721; change to any free port. Restart the adaptor to apply."],
        "help_codex_config_2": [.chinese: "通信协议 — 在 Chat Completions 与 Responses API 两种线格式之间选择。若上游接入了 Responses API 模型可选 Responses API，否则保持 Chat Completions。", .english: "Communication Protocol — choose between Chat Completions and Responses API wire formats. Pick Responses API only if your upstream exposes a Responses-API model; otherwise keep Chat Completions."],
        "help_codex_config_3": [.chinese: "输出格式 — 上游 API 返回推理文本的格式，用于正确还原思考内容。", .english: "Output Format — how the upstream API returns reasoning text, used to correctly reconstruct thinking content."],
        "help_codex_config_4": [.chinese: "推理配置 — 可开启「覆盖推理配置」手动指定 thinking / effort 参数，或使用「自动检测」。", .english: "Reasoning Configuration — toggle \"Override Reasoning Config\" to manually set thinking/effort params, or use \"Auto Detect\"."],
        "help_codex_config_5": [.chinese: "自定义模型 — 定义模型别名，映射到 APIBypass 的模型映射。", .english: "Custom Models — define model aliases that map to your APIBypass model mappings."],
        "help_codex_autodetect_title": [.chinese: "自动检测说明", .english: "Auto-Detection"],
        "help_codex_autodetect_desc": [.chinese: "自动检测根据提供商名称、Base URL 和模型名中的关键词匹配，选择对应的推理参数组合。已支持的提供商/平台：DeepSeek、OpenRouter、SiliconFlow、Kimi/Moonshot、GLM/智谱、通义千问/DashScope、MiniMax、阶跃星辰、Mimo。若无法识别，则不注入任何推理参数，请求原样转发。", .english: "Auto-detection matches keywords in the provider name, Base URL, and model name to pick a reasoning parameter set. Supported providers/platforms: DeepSeek, OpenRouter, SiliconFlow, Kimi/Moonshot, GLM/Zhipu, Qwen/DashScope, MiniMax, StepFun, Mimo. If unrecognized, no reasoning params are injected and the request is forwarded as-is."],
        "help_codex_logs_title": [.chinese: "日志与排错", .english: "Logs & Troubleshooting"],
        "help_codex_logs_desc": [.chinese: "适配器窗口内置实时日志，支持过滤、自动滚动、复制与导出。遇到请求异常时，可先在此查看请求与响应原文，再结合 APIBypass 的追踪日志定位问题。", .english: "The adaptor window shows live logs with filtering, auto-scroll, copy, and export. When a request misbehaves, check the raw request/response here first, then combine with APIBypass's trace logs to narrow down the cause."],
        "help_codex_cdp_title": [.chinese: "CDP 增强", .english: "CDP Enhancements"],
        "help_codex_cdp_desc": [.chinese: "通过 Chrome DevTools Protocol 注入 Codex 桌面端，提供强制解锁入口、插件市场解锁、特殊插件强制安装等功能。适用于需要扩展 Codex 桌面端能力的高级用户。", .english: "Injects into the Codex desktop app via the Chrome DevTools Protocol, enabling force entry unlock, plugin marketplace unlock, and force plugin install. Intended for advanced users who need to extend the Codex desktop client."],

        // Codex 适配器 - 界面结构
        "help_codex_ui_title": [.chinese: "界面结构", .english: "UI Structure"],
        "help_codex_ui_desc": [.chinese: "Codex 适配器窗口分为三个标签页，通过左侧边栏切换：", .english: "The Codex Adaptor window has three tabs, switchable via the left sidebar:"],
        "help_codex_ui_tab_service": [.chinese: "服务 — 配置监听端口、通信协议、推理参数、自定义模型等基础设置。", .english: "Service — configure listening port, wire protocol, reasoning params, custom models, and other basic settings."],
        "help_codex_ui_tab_enhancements": [.chinese: "增强 — CDP 注入设置，包括启动 Codex、调试端口、插件增强开关等。", .english: "Enhancements — CDP injection settings, including launch Codex, debug port, and plugin enhancement toggles."],
        "help_codex_ui_tab_logs": [.chinese: "日志 — 实时请求/响应日志查看器，支持过滤和导出。", .english: "Logs — live request/response log viewer with filtering and export."],

        // Codex 适配器 - CDP 注入
        "help_codex_cdp_injection_title": [.chinese: "CDP 注入", .english: "CDP Injection"],
        "help_codex_cdp_injection_desc": [.chinese: "CDP 注入功能可以让 Codex 桌面端获得额外的增强能力。在「增强」标签页中：", .english: "CDP injection enables extra enhancement capabilities for the Codex desktop app. In the \"Enhancements\" tab:"],
        "help_codex_cdp_launch": [.chinese: "启动 Codex — 点击按钮启动 Codex 桌面应用并自动注入 CDP 脚本。如果 Codex 适配服务未运行，会自动启动。Codex 已运行时按钮会被禁用。", .english: "Launch Codex — click the button to start the Codex desktop app with CDP script injection. Automatically starts the adaptor service if not running. The button is disabled when Codex is already running."],
        "help_codex_cdp_debug_port": [.chinese: "调试端口 — Codex 启动时使用的 Chrome DevTools 协议端口，默认 9222。如果端口被占用，可修改为其他端口。点击旁边的 ⓘ 按钮可查看手动启动命令。", .english: "Debug Port — the Chrome DevTools Protocol port used when launching Codex, default 9222. Change it if the port is occupied. Click the ⓘ button to see the manual launch command."],
        "help_codex_cdp_status": [.chinese: "CDP 状态 — 显示当前 CDP 连接状态：已连接（绿色）、已注入（绿色）、断开（灰色）。已注入表示 CDP 脚本已成功注入到 Codex。", .english: "CDP Status — shows the current CDP connection status: Connected (green), Injected (green), Disconnected (gray). Injected means the CDP script has been successfully injected into Codex."],

        // Codex 适配器 - 插件设置
        "help_codex_plugin_settings_title": [.chinese: "插件设置", .english: "Plugin Settings"],
        "help_codex_plugin_settings_desc": [.chinese: "在「增强」标签页的插件设置区域，可以开启以下增强功能：", .english: "In the \"Plugin Settings\" section of the Enhancements tab, you can enable these enhancements:"],
        "help_codex_plugin_entry": [.chinese: "插件入口解锁 — 解锁 Codex 桌面端的插件入口，让插件功能可见。", .english: "Plugin Entry Unlock — unlock the plugin entry in Codex desktop, making plugin features visible."],
        "help_codex_plugin_whitelist": [.chinese: "模型白名单解锁 — 移除 Codex 对可用模型的限制，允许使用自定义模型。", .english: "Model Whitelist Unlock — remove Codex's model restrictions, allowing use of custom models."],
        "help_codex_plugin_marketplace": [.chinese: "插件市场解锁 — 解锁插件市场，允许浏览和安装插件。", .english: "Plugin Marketplace Unlock — unlock the plugin marketplace for browsing and installing plugins."],
        "help_codex_plugin_force_install": [.chinese: "强制插件安装 — 允许安装未在官方市场发布的插件。", .english: "Force Plugin Install — allow installing plugins not published in the official marketplace."],

        // 帮助内容 - 分组标题
        "help_group_fields": [.chinese: "字段说明", .english: "Fields"],
        "help_group_standard_params": [.chinese: "标准参数", .english: "Standard Parameters"],
        "help_group_protocol_options": [.chinese: "协议选项", .english: "Protocol Options"],

        // 帮助内容 - 常见问题
        "help_faq_q1": [.chinese: "为什么请求返回 404？", .english: "Why does the request return 404?"],
        "help_faq_a1": [.chinese: "请检查模型映射中的「客户端模型名」是否与请求中的 model 字段匹配，且该映射已启用。", .english: "Check that the \"Incoming Model\" in the model mapping matches the model field in the request, and that the mapping is enabled."],
        "help_faq_q2": [.chinese: "如何修改服务端口？", .english: "How do I change the server port?"],
        "help_faq_a2": [.chinese: "APIBypass 服务端口在「设置」窗口修改，Codex 适配器端口在「配置: Codex适配」窗口修改。修改后重启对应服务即可生效。", .english: "APIBypass server port is changed in the \"Settings\" window, Codex adaptor port is changed in the \"Configure: Codex Adaptor\" window. Restart the corresponding service to apply."],
        "help_faq_q3": [.chinese: "纯代理模式和普通模式有什么区别？", .english: "What is the difference between Bypass Mode and normal mode?"],
        "help_faq_a3": [.chinese: "普通模式下，应用会在 OpenAI 和 Anthropic API 格式之间转换。纯代理模式则原样透传，不做任何转换。", .english: "In normal mode, the app converts between OpenAI and Anthropic API formats. Bypass Mode passes through as-is with no conversion."],
        "help_faq_q4": [.chinese: "整流器是做什么的？", .english: "What does the Rectifier do?"],
        "help_faq_a4": [.chinese: "整流器在上游返回 thinking signature 或 budget 相关错误时，自动修复请求并重试，不影响正常请求。启动器中默认开启，可按需关闭。", .english: "The Rectifier automatically fixes and retries requests when the upstream returns thinking-signature or budget errors. It has no impact on normal requests. It's on by default in the launcher and can be toggled off."],
        "help_faq_q5": [.chinese: "流式响应里的 token 用量显示为 0 或不更新怎么办？", .english: "Streaming token usage shows 0 or doesn't update — what should I do?"],
        "help_faq_a5": [.chinese: "在对应提供商设置里开启「请求流式 token 用量」。APIBypass 会为该提供商的 OpenAI 兼容流式请求添加 stream_options.include_usage=true，让客户端能显示 token 用量。若开启后该提供商报错不支持，请关闭。", .english: "Enable \"Request streaming token usage\" in that provider's settings. APIBypass will add stream_options.include_usage=true to its OpenAI-compatible streaming requests so clients can display token usage. If the provider errors out, turn it off."],
        "help_faq_q6": [.chinese: "启动服务时报端口被占用怎么办？", .english: "The port is already in use when starting the service — what now?"],
        "help_faq_a6": [.chinese: "在「设置」中改成空闲端口（APIBypass 服务）或在「配置: Codex适配」窗口改端口（Codex 服务），再重启对应服务。", .english: "Switch to a free port in \"Settings\" (for APIBypass server) or in \"Configure: Codex Adaptor\" window (for Codex server), then restart the corresponding service."],
        "help_faq_q7": [.chinese: "Codex 适配器和 APIBypass 服务是什么关系？", .english: "What's the relationship between the Codex Adaptor and the APIBypass server?"],
        "help_faq_a7": [.chinese: "两者是独立运行的本地服务。Codex 适配器把 Codex 的 Responses API 翻译成 Chat Completions，再转发到 APIBypass 服务做模型映射与参数注入，最后到上游提供商。它们可以各自启停，端口也可分别配置。", .english: "They are independent local services. The Codex Adaptor translates Codex's Responses API into Chat Completions, then forwards to the APIBypass server for model mapping and parameter injection, and finally to the upstream provider. Each can be started/stopped separately, with its own port."],
        "help_faq_q8": [.chinese: "点击「启动 Codex」后 CDP 状态一直是「已断开」怎么办？", .english: "CDP status stays \"Disconnected\" after clicking \"Launch Codex\" — what should I do?"],
        "help_faq_a8": [.chinese: "检查 Codex 是否以调试模式启动。在「增强」标签页点击调试端口旁的 ⓘ 按钮，查看正确的启动命令。确保 Codex 使用 --remote-debugging-port=9222（或你配置的端口）参数启动。也可在「日志」标签页查看详细错误信息。", .english: "Check if Codex started with debug mode enabled. Click the ⓘ button next to the debug port in the \"Enhancements\" tab to see the correct launch command. Make sure Codex is launched with --remote-debugging-port=9222 (or your configured port). You can also check the \"Logs\" tab for detailed error messages."],
        "help_faq_q9": [.chinese: "CDP 注入失败怎么办？", .english: "CDP injection failed — what should I do?"],
        "help_faq_a9": [.chinese: "确保 Codex 适配服务已启动，调试端口正确（默认 9222），且没有其他应用占用该端口。在「日志」标签页查看详细错误信息。如果问题持续，尝试重启 Codex 和 Codex 适配服务。", .english: "Make sure the Codex adaptor service is running, the debug port is correct (default 9222), and no other app is using that port. Check the \"Logs\" tab for detailed error messages. If the problem persists, try restarting both Codex and the Codex adaptor service."],
        "help_faq_q10": [.chinese: "如何手动启动 Codex 并启用调试模式？", .english: "How do I manually launch Codex with debug mode?"],
        "help_faq_a10": [.chinese: "在「增强」标签页，点击调试端口旁的 ⓘ 按钮，复制显示的命令到终端执行即可。命令格式类似：/Applications/Codex.app/Contents/MacOS/Codex --remote-debugging-port=9222", .english: "In the \"Enhancements\" tab, click the ⓘ button next to the debug port, then copy and run the displayed command in your terminal. The command format is similar to: /Applications/Codex.app/Contents/MacOS/Codex --remote-debugging-port=9222"],

        // 配置模板 / Template management
        "config_template": [.chinese: "配置模板", .english: "Config Template"],
        "no_templates": [.chinese: "暂无模板", .english: "No Templates"],
        "save_as_template": [.chinese: "保存为模板", .english: "Save as Template"],
        "default_template": [.chinese: "默认", .english: "Default"],
        "template_name": [.chinese: "模板名称", .english: "Template Name"],
        "rename_template": [.chinese: "重命名模板", .english: "Rename Template"],
        "delete_template": [.chinese: "删除模板", .english: "Delete Template"],
        "delete_template_confirm": [.chinese: "确定要删除模板 \"{name}\" 吗？此操作无法撤销。", .english: "Are you sure you want to delete template \"{name}\"? This cannot be undone."],
        "restore_defaults": [.chinese: "恢复默认模板", .english: "Restore Default Templates"],
        "custom_config": [.chinese: "自定义配置", .english: "Custom"],
        "update_template": [.chinese: "更新模板", .english: "Update Template"],
        "save_as_new_template": [.chinese: "另存为新模板", .english: "Save as New Template"],

        // 终端检测
        "terminal_already_running": [.chinese: "终端已在运行", .english: "Terminal Already Running"],
        "terminal_running_message": [.chinese: "{name} 已在运行，请选择启动方式", .english: "{name} is already running. Choose launch mode."],
        "new_tab": [.chinese: "新建标签页", .english: "New Tab"],
        "new_window": [.chinese: "新建窗口", .english: "New Window"],

        // Codex Adaptor
        "codex_adaptor": [.chinese: "Codex适配器", .english: "Codex Adaptor"],
        "codex_service": [.chinese: "服务", .english: "Service"],
        "codex_start": [.chinese: "启动", .english: "Start"],
        "codex_stop": [.chinese: "停止", .english: "Stop"],
        "codex_port": [.chinese: "端口", .english: "Port"],
        "codex_status_running": [.chinese: "运行中", .english: "Running"],
        "codex_status_stopped": [.chinese: "已停止", .english: "Stopped"],
        "codex_wire_api": [.chinese: "通信协议", .english: "Communication Protocol"],
        "codex_wire_api_desc": [.chinese: "如果你在纯代理模式模式下接入了 Response API 的模型，可以选择 Responses API，否则你应该总是选择 Chat Completions", .english: "If you have a Responses API model connected in bypass mode, you can choose Responses API. Otherwise, you should always choose Chat Completions."],
        "codex_reasoning": [.chinese: "推理配置", .english: "Reasoning Configuration"],
        "codex_override_reasoning": [.chinese: "覆盖推理配置", .english: "Override Reasoning Config"],
        "codex_auto_detect": [.chinese: "自动检测", .english: "Auto Detect"],
        "codex_thinking_param": [.chinese: "思考参数", .english: "Thinking Param"],
        "codex_effort_param": [.chinese: "Effort 参数", .english: "Effort Param"],
        "codex_effort_value": [.chinese: "Effort 值映射", .english: "Effort Value"],
        "codex_output_format": [.chinese: "输出格式", .english: "Output Format"],
        "codex_custom_models": [.chinese: "自定义模型", .english: "Custom Models"],
        "codex_model_alias": [.chinese: "别名", .english: "Alias"],
        "codex_model_from_apibypass": [.chinese: "模型（来自 APIBypass）", .english: "Model (from APIBypass)"],
        "codex_context_window": [.chinese: "上下文窗口", .english: "Context Window"],
        "codex_add_model": [.chinese: "添加模型", .english: "Add Model"],
        "codex_enhancements": [.chinese: "增强", .english: "Enhancements"],
        "codex_launch_codex": [.chinese: "CDP 注入", .english: "CDP Injection"],
        "codex_launch_description": [.chinese: "启动 Codex 并注入 CDP 脚本以启用增强功能", .english: "Launch Codex and inject CDP script to enable enhancements"],
        "codex_cdp_status": [.chinese: "CDP 状态", .english: "CDP Status"],
        "codex_plugin_settings": [.chinese: "插件设置", .english: "Plugin Settings"],
        "cdp_status_disconnected": [.chinese: "CDP: 未连接", .english: "CDP: Disconnected"],
        "cdp_status_connecting": [.chinese: "CDP: 连接中", .english: "CDP: Connecting"],
        "cdp_status_injected": [.chinese: "CDP: 已注入", .english: "CDP: Injected"],
        "cdp_status_failed": [.chinese: "CDP: 失败", .english: "CDP: Failed"],
        "codex_debug_port": [.chinese: "调试端口", .english: "Debug Port"],
        "codex_debug_port_help": [.chinese: "重启 Codex 后生效", .english: "Restarts Codex to apply"],
        "codex_debug_port_invalid": [.chinese: "端口必须是 1-65535 的数字", .english: "Port must be 1-65535"],
        "codex_launch_button": [.chinese: "启动 Codex", .english: "Launch Codex"],
        "codex_launch_progress_starting_service": [.chinese: "正在启动适配服务…", .english: "Starting adaptor service…"],
        "codex_launch_progress_detect": [.chinese: "正在检测 Codex.app…", .english: "Detecting Codex.app…"],
        "codex_launch_progress_launch": [.chinese: "正在启动 Codex…", .english: "Launching Codex…"],
        "codex_launch_progress_wait": [.chinese: "等待调试端口就绪…", .english: "Waiting for debug port…"],
        "codex_launch_progress_done": [.chinese: "Codex 已就绪", .english: "Codex is ready"],
        "codex_launch_confirm_title": [.chinese: "重启 Codex？", .english: "Restart Codex?"],
        "codex_launch_confirm_message": [.chinese: "Codex 正在运行，重启会中断当前会话（未保存内容会丢失）。", .english: "Codex is running. Restart will interrupt the current session."],
        "codex_launch_confirm_restart": [.chinese: "重启", .english: "Restart"],
        "codex_launch_app_not_found": [.chinese: "未找到 Codex.app（已检查 /Applications 和 ~/Applications）", .english: "Codex.app not found (checked /Applications and ~/Applications)"],
        "codex_launch_failed": [.chinese: "启动 Codex 失败", .english: "Failed to launch Codex"],
        "codex_launch_port_timeout": [.chinese: "启动后端口 15 秒内未响应", .english: "Port did not respond within 15s"],
        "codex_manual_command_help": [.chinese: "手动启动命令（终端执行）：", .english: "Manual launch command (run in terminal):"],
        "codex_plugin_entry_unlock": [.chinese: "强制解锁入口", .english: "Force Entry Unlock"],
        "codex_model_whitelist_unlock": [.chinese: "模型白名单解锁", .english: "Model Whitelist Unlock"],
        "codex_marketplace_unlock": [.chinese: "插件市场解锁", .english: "Plugin Marketplace Unlock"],
        "codex_force_plugin_install": [.chinese: "特殊插件强制安装", .english: "Force Plugin Install"],
        "codex_logs": [.chinese: "日志", .english: "Logs"],
        "codex_clear_logs": [.chinese: "清除", .english: "Clear"],
        "codex_export_logs": [.chinese: "导出", .english: "Export"],
        "codex_filter": [.chinese: "过滤", .english: "Filter"],
        "codex_auto_scroll": [.chinese: "自动滚动", .english: "Auto Scroll"],
        "codex_copy_all": [.chinese: "复制全部", .english: "Copy All"],
        "codex_copied": [.chinese: "已复制", .english: "Copied"],
        "codex_entries": [.chinese: "条记录", .english: "entries"],
        "codex_adaptor_title": [.chinese: "Codex Adaptor 设置", .english: "Codex Adaptor Settings"],
        "codex_alias": [.chinese: "别名", .english: "Alias"],
        "codex_cdp_title": [.chinese: "CDP 设置", .english: "CDP Settings"],
        "codex_clear": [.chinese: "清除", .english: "Clear"],
        "codex_communication": [.chinese: "通信", .english: "Communication"],
        "codex_copy": [.chinese: "复制", .english: "Copy"],
        "codex_export": [.chinese: "导出", .english: "Export"],
        "codex_log_filter": [.chinese: "日志过滤", .english: "Log Filter"],
        "codex_no_custom_models": [.chinese: "无自定义模型", .english: "No Custom Models"],
        "codex_no_reasoning_config": [.chinese: "无推理配置", .english: "No Reasoning Config"],
        "codex_reasoning_override": [.chinese: "覆盖推理配置", .english: "Reasoning Override"],
        "help_codex_adaptor": [.chinese: "Codex适配器", .english: "Codex Adaptor"],

        // Codex Adaptor - Server tab
        "codex_runtime_status": [.chinese: "运行状态", .english: "Runtime Status"],
        "codex_proxy_server": [.chinese: "代理服务器", .english: "Proxy Server"],
        "codex_proxy_port": [.chinese: "代理端口", .english: "Proxy Port"],
        "codex_proxy_url": [.chinese: "代理 URL", .english: "Proxy URL"],
        "codex_requires_restart": [.chinese: "需要重启生效", .english: "Requires restart to apply"],
        "codex_auto_configured": [.chinese: "自动配置", .english: "Auto-configured"],
        "codex_select_section": [.chinese: "请选择一个分区", .english: "Select a section"],

        // Codex Adaptor - Reasoning
        "codex_enable_thinking": [.chinese: "启用思考（推理）", .english: "Enable Thinking (Reasoning)"],
        "codex_thinking_desc": [.chinese: "注入思考模式参数到请求中", .english: "Inject thinking mode parameter into requests"],
        "codex_enable_effort": [.chinese: "启用推理努力级别", .english: "Enable Reasoning Effort"],
        "codex_effort_desc": [.chinese: "转发推理努力级别参数到上游", .english: "Forward reasoning effort level parameter to upstream"],
        "codex_reasoning_auto_footer": [.chinese: "未设置覆盖时使用自动检测。代理根据提供商名称和 Base URL 推断参数。", .english: "Auto-detection is used when no override is set. The proxy infers parameters from the provider name and base URL."],
        "codex_output_format_desc": [.chinese: "上游 API 返回推理文本的格式", .english: "How the upstream API returns reasoning text"],
        "codex_reasoning_info_title": [.chinese: "自动检测说明", .english: "Auto-Detection Info"],
        "codex_reasoning_info_basis": [.chinese: "推断依据", .english: "Inference Basis"],
        "codex_reasoning_info_basis_desc": [.chinese: "根据提供商名称、Base URL 和模型名称中的关键词进行匹配，自动选择对应的推理参数组合。", .english: "Matches keywords in the provider name, base URL, and model name to automatically select the corresponding reasoning parameter set."],
        "codex_reasoning_info_supported": [.chinese: "已支持的提供商/平台", .english: "Supported Providers/Platforms"],
        "codex_reasoning_info_supported_list": [.chinese: "DeepSeek、OpenRouter、SiliconFlow、Kimi/Moonshot、GLM/智谱、通义千问/DashScope、MiniMax、阶跃星辰、Mimo", .english: "DeepSeek, OpenRouter, SiliconFlow, Kimi/Moonshot, GLM/Zhipu, Qwen/DashScope, MiniMax, StepFun, Mimo"],
        "codex_reasoning_info_unmatched": [.chinese: "未匹配时", .english: "When Unmatched"],
        "codex_reasoning_info_unmatched_desc": [.chinese: "如果无法识别提供商，代理将不注入任何推理参数，请求原样转发。", .english: "If the provider cannot be recognized, the proxy will not inject any reasoning parameters and forwards the request as-is."],

        // Codex Adaptor - Custom Models
        "codex_model_slug": [.chinese: "模型名称", .english: "Model Name"],
        "codex_model_alias_desc": [.chinese: "Codex 显示名称", .english: "Codex display name"],
        "codex_model_slug_desc": [.chinese: "上游 API 模型 ID", .english: "Upstream API model ID"],
        "codex_model_footer": [.chinese: "这些模型会出现在 Codex 的模型选择器中。", .english: "These models appear in Codex's model selector."],
        "codex_context_window_eg": [.chinese: "如 128,000", .english: "e.g. 128,000"],

        // Codex Adaptor - CDP descriptions
        "codex_plugin_entry_unlock_desc": [.chinese: "通过身份伪装强制显示插件入口按钮。", .english: "Force the Plugins button visible via auth spoofing."],
        "codex_model_whitelist_unlock_desc": [.chinese: "未登录 ChatGPT 时，将本地模型列表注入 Codex 的模型选择器。", .english: "Inject local model list into Codex's selector when not logged into ChatGPT."],
        "codex_marketplace_unlock_desc": [.chinese: "API Key 模式下扩展插件市场请求，尽量显示完整插件列表。", .english: "Expand marketplace requests under API Key mode to show full plugin list."],
        "codex_force_plugin_install_desc": [.chinese: "解除应用不可用导致的前端安装禁用。", .english: "Unblock install buttons disabled due to app unavailability restrictions."],

        // Codex Adaptor - Help
        "codex_help_subtitle": [.chinese: "Responses API 代理，为 OpenAI Codex CLI 提供支持", .english: "Responses API proxy for OpenAI Codex CLI"],
        "codex_how_it_works": [.chinese: "工作原理", .english: "How It Works"],
        "codex_how_it_works_desc": [.chinese: "Codex Adaptor 是一个本地 HTTP 代理，将 Codex CLI 的 Responses API 调用转换为 Chat Completions 格式，然后转发到 APIBypass 进行模型映射和参数注入。", .english: "Codex Adaptor is a local HTTP proxy that translates Codex CLI's Responses API calls into Chat Completions format, then forwards them to APIBypass for model mapping and parameter injection."],
        "codex_setup_guide": [.chinese: "设置指南", .english: "Setup Guide"],
        "codex_setup_step1": [.chinese: "在上方「Server」标签中启动 Codex Adaptor 服务", .english: "Start the Codex Adaptor service in the Server tab above"],
        "codex_setup_step2": [.chinese: "配置通信协议（Chat Completions 或 Responses API）", .english: "Configure the communication protocol (Chat Completions or Responses API)"],
        "codex_setup_step3": [.chinese: "根据需要配置推理参数和自定义模型", .english: "Configure reasoning parameters and custom models as needed"],
        "codex_setup_step4": [.chinese: "将 Codex CLI 的 API 地址指向 http://127.0.0.1:15721/v1", .english: "Point Codex CLI's API base URL to http://127.0.0.1:15721/v1"],
        "codex_setup_step5": [.chinese: "在 Codex 中使用 — 所有请求将通过 APIBypass 代理转发", .english: "Use Codex as usual — all requests will be proxied through APIBypass"],
        "codex_config_files": [.chinese: "配置文件", .english: "Configuration Files"],
        "codex_file_config_desc": [.chinese: "Codex CLI 读取的主配置文件", .english: "Main configuration file read by Codex CLI"],
        "codex_file_providers_desc": [.chinese: "代理内部元数据", .english: "Proxy-internal metadata"],
        "codex_file_catalog_desc": [.chinese: "每个提供商的模型目录", .english: "Per-provider model catalog"],
        "codex_file_backup_desc": [.chinese: "配置文件备份", .english: "Configuration file backup"],

        // Codex Adaptor - About
        "codex_about_subtitle": [.chinese: "将 OpenAI Codex CLI 的 Responses API 调用转换为 Chat Completions 格式的本地代理", .english: "A local proxy that translates OpenAI Codex CLI's Responses API calls into Chat Completions format"],
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
