# APIBypass

macOS 菜单栏应用，作为大模型 API 的本地代理服务。

## 功能

- 支持 OpenAI 和 Anthropic 两种 API 格式
- 按模型名称映射，自动注入自定义参数
- 关闭/开启 Claude 思考模式
- 自定义 temperature、max_tokens 等参数
- API Key 加密存储在 Keychain
- 流式响应支持

## 使用方法

1. 启动应用后，点击菜单栏图标选择"打开配置"
2. 添加模型映射配置：
   - 客户端模型名：你的软件请求的模型名（如 `gpt-4`）
   - 实际模型名：要调用的真实模型（如 `claude-sonnet-4-6`）
   - API 地址：上游 API 地址
   - API Key：加密存储
3. 在客户端软件中设置：
   - Base URL: `http://localhost:8390`
   - Model: 你配置的客户端模型名

## 端口

默认端口: 8390

## 系统要求

- macOS 14.0+
- Swift 5.9+
