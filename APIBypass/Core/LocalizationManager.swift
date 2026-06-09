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
        "help": [.chinese: "帮助", .english: "Help"],
        "bypass_mode": [.chinese: "✓ 纯代理模式", .english: "✓ Bypass Mode"],
        "bypass_mode_off": [.chinese: "纯代理模式", .english: "Bypass Mode"],
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

        // 设置面板
        "settings_title": [.chinese: "设置", .english: "Settings"],
        "language": [.chinese: "语言", .english: "Language"],
        "language_hint": [.chinese: "切换语言后立即生效", .english: "Changes take effect immediately"],
        "server_port": [.chinese: "服务端口", .english: "Server Port"],
        "port_hint": [.chinese: "修改端口后需重启服务生效", .english: "Restart the server to apply port changes"],
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
        "provider_type_openai_responses": [.chinese: "OpenAI Response API", .english: "OpenAI Response API"],
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
        "help_quick_start_desc": [.chinese: "APIBypass 是一款 API 模型映射代理工具，可拦截客户端请求并注入自定义参数，实现无缝切换模型提供商。", .english: "APIBypass is an API model mapping proxy that intercepts client requests and injects custom parameters for seamless model provider switching."],
        "help_quick_start_step1": [.chinese: "点击菜单栏图标，选择「配置...」打开配置窗口", .english: "Click the menu bar icon and select \"Configure...\" to open the config window"],
        "help_quick_start_step2": [.chinese: "创建至少一个提供商（Provider）和一条模型映射规则", .english: "Create at least one provider and one model mapping rule"],
        "help_quick_start_step3": [.chinese: "启动服务后，将客户端 API 地址指向本服务即可", .english: "Start the server and point your client API address to this service"],
        "help_quick_start_note": [.chinese: "注意：默认服务端口为 8390，可在「设置」中修改。", .english: "Note: The default server port is 8390, which can be changed in \"Settings.\""],

        // 帮助内容 - 菜单栏
        "help_menu_bar_desc": [.chinese: "点击菜单栏中的 APIBypass 图标可查看以下选项：", .english: "Click the APIBypass icon in the menu bar to see the following options:"],
        "help_menu_status": [.chinese: "服务状态 - 显示当前服务是否运行及监听的端口", .english: "Server Status - Shows whether the server is running and the listening port"],
        "help_menu_bypass": [.chinese: "纯代理模式 - 切换是否 bypass API 格式转换", .english: "Bypass Mode - Toggle whether to bypass API format conversion"],
        "help_menu_configure": [.chinese: "配置... - 打开配置窗口，管理模型映射和提供商", .english: "Configure... - Open the config window to manage model mappings and providers"],
        "help_menu_settings": [.chinese: "设置... - 打开设置窗口，切换语言和修改端口", .english: "Settings... - Open the settings window to switch language and change port"],
        "help_menu_launcher": [.chinese: "启动 Claude Code - 打开启动器，配置环境变量后一键启动 Claude Code", .english: "Launch Claude Code - Open the launcher to configure environment variables and launch Claude Code"],
        "help_menu_control": [.chinese: "启动/停止服务 - 控制代理服务的启停", .english: "Start/Stop Server - Control the proxy server start and stop"],
        "help_menu_quit": [.chinese: "退出 - 关闭 APP", .english: "Quit - Close the app"],
        "help_menu_help": [.chinese: "帮助 - 打开本帮助窗口", .english: "Help - Open this help window"],

        // 帮助内容 - 模型映射
        "help_model_mapping_title": [.chinese: "模型映射", .english: "Model Mapping"],
        "help_model_mapping_desc": [.chinese: "模型映射允许您将客户端请求的模型名映射到上游提供商的实际模型名。例如，客户端请求「gpt-4」，实际可映射到「claude-sonnet-4-6」。", .english: "Model mapping allows you to map the model name requested by the client to the actual model name of the upstream provider. For example, the client requests \"gpt-4\", which can be mapped to \"claude-sonnet-4-6\"."],
        "help_model_mapping_fields": [.chinese: "每条映射规则包含：客户端模型名、实际模型名、API 接口类型（OpenAI / Anthropic / OpenAI Response API）、Base URL、API Key、推理模式覆盖等。", .english: "Each mapping rule includes: incoming model name, actual model name, API format (OpenAI / Anthropic / OpenAI Response API), Base URL, API Key, reasoning mode override, etc."],
"help_model_mapping_reasoning": [.chinese: "「更改默认推理模式」通过 enable_thinking 参数设置；如果模型提供商使用其他字段定义思考模式，请在「自定义参数」中自行添加。", .english: "Reasoning Mode Override is set via the enable_thinking parameter; if your provider uses a different field for thinking mode, add it in Custom Parameters."],

        // 帮助内容 - 参数注入
        "help_param_injection_title": [.chinese: "参数注入", .english: "Parameter Injection"],
        "help_param_injection_desc": [.chinese: "参数注入功能允许您在转发请求时自动添加或覆盖特定参数。支持注入温度（temperature）、最大Token数（max_tokens）、Top P、频率惩罚和存在惩罚。", .english: "Parameter injection allows you to automatically add or override specific parameters when forwarding requests. Supports injection of temperature, max_tokens, Top P, frequency penalty, and presence penalty."],
        "help_custom_params": [.chinese: "此外，您还可以通过「自定义参数」添加任意 JSON 字段，例如 enable_thinking、thinking 等。", .english: "Additionally, you can add any JSON fields via \"Custom Parameters\", such as enable_thinking, thinking, etc."],

        // 帮助内容 - 启动 Claude Code
        "help_launcher_title": [.chinese: "启动 Claude Code", .english: "Launch Claude Code"],
        "help_launcher_desc": [.chinese: "通过启动器可以一键启动 Claude Code 并自动注入必要的环境变量，包括 ANTHROPIC_API_KEY、CLAUDE_MODEL、ANTHROPIC_BASE_URL 等。", .english: "The launcher allows you to start Claude Code with one click and automatically inject necessary environment variables, including ANTHROPIC_API_KEY, CLAUDE_MODEL, ANTHROPIC_BASE_URL, etc."],
        "help_launcher_features": [.chinese: "支持选择终端应用、工作目录、手动添加额外环境变量，以及自动从钥匙串读取 API Key。", .english: "Supports selecting terminal application, working directory, manually adding extra environment variables, and automatically reading API Key from Keychain."],

        // 帮助内容 - 纯代理模式
        "help_bypass_title": [.chinese: "纯代理模式", .english: "Bypass Mode"],
        "help_bypass_desc": [.chinese: "开启纯代理模式后，APP 将完全透传上下游之间的请求和响应，不做任何 API 格式转换。适用于上游提供商原生支持客户端 API 格式的场景。", .english: "When Bypass Mode is enabled, the app will transparently pass all requests and responses between client and upstream without any API format conversion. Suitable when the upstream provider natively supports the client's API format."],
        "help_bypass_note": [.chinese: "注意：纯代理模式下，模型映射配置（参数注入、自定义参数、推理模式等）仍然生效。", .english: "Note: In Bypass Mode, model mapping configurations (parameter injection, custom parameters, reasoning mode, etc.) still take effect."],

        // 帮助内容 - 设置
        "help_settings_title": [.chinese: "设置", .english: "Settings"],
        "help_settings_desc": [.chinese: "在「设置」窗口中，您可以：", .english: "In the \"Settings\" window, you can:"],
        "help_settings_lang": [.chinese: "切换界面语言（中文/英文）", .english: "Switch interface language (Chinese/English)"],
        "help_settings_port": [.chinese: "修改服务监听端口（修改后需重启服务）", .english: "Change the server listening port (requires server restart)"],

        // 帮助内容 - 常见问题
        "help_faq_q1": [.chinese: "Q: 为什么请求返回 404？", .english: "Q: Why does the request return 404?"],
        "help_faq_a1": [.chinese: "A: 请检查模型映射中的「客户端模型名」是否与请求中的 model 字段匹配，且该配置已启用。", .english: "A: Please check if the \"Incoming Model\" in the model mapping matches the model field in the request, and ensure the configuration is enabled."],
        "help_faq_q2": [.chinese: "Q: 如何修改服务端口？", .english: "Q: How do I change the server port?"],
        "help_faq_a2": [.chinese: "A: 在「设置」窗口中修改端口，保存后停止并重新启动服务即可生效。", .english: "A: Change the port in the \"Settings\" window, then stop and restart the server to apply."],
        "help_faq_q3": [.chinese: "Q: 纯代理模式和普通模式有什么区别？", .english: "Q: What is the difference between Bypass Mode and normal mode?"],
        "help_faq_a3": [.chinese: "A: 普通模式下，APP 会在 OpenAI 和 Anthropic API 格式之间进行转换。纯代理模式则完全透传，不做任何转换。", .english: "A: In normal mode, the app converts between OpenAI and Anthropic API formats. Bypass Mode transparently passes through without any conversion."],

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
