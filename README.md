# APIBypass

A lightweight macOS menu bar app that acts as a local LLM API proxy. Take control of model behavior even when your AI client doesn't expose those settings.

## Why APIBypass?

Many AI clients don't let you customize API request parameters (e.g., disable thinking mode, set temperature, adjust max_tokens). APIBypass runs a local proxy server that intercepts API calls from your client, injects your custom parameters, and forwards them to the real API endpoint.

### Use Cases

- **Closed-source clients**: Some apps call DeepSeek/Qwen3 models without letting you disable thinking mode. APIBypass injects `enable_thinking: false` to force it off.
- **Parameter injection**: Set temperature, top_p, and other parameters globally without modifying each client.
- **Model name mapping**: Map the model name your client requests to a different actual model — switch models without changing client config.
- **Multi-format support**: Works with both OpenAI Chat Completions and Anthropic Messages APIs.

## Features

- Runs in the macOS menu bar — stays out of your Dock
- Local proxy on `127.0.0.1:8390`
- OpenAI Chat Completions API (`/v1/chat/completions`)
- Anthropic Messages API (`/v1/messages`)
- Model name mapping (client request name → actual model)
- Parameter injection: temperature, max_tokens, top_p, frequency_penalty, presence_penalty
- Thinking mode control: toggle on/off for Anthropic (`thinking` parameter) and OpenAI-compatible APIs (`enable_thinking` parameter)
- Custom JSON fields — inject any parameter with any value type
- API Key stored securely in macOS Keychain
- Request logging for debugging

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode 16.0+ (or Command Line Tools only)

## Build & Run

```bash
git clone https://github.com/panando/APIBypass.git
cd APIBypass

# Run in debug mode
swift run

# Or build release binary
swift build -c release
.build/arm64-apple-macosx/release/APIBypass
```

On first launch, allow network connections when prompted.

## Package

### .app Bundle

```bash
swift build -c release

mkdir -p APIBypass.app/Contents/MacOS APIBypass.app/Contents/Resources
cp .build/arm64-apple-macosx/release/APIBypass APIBypass.app/Contents/MacOS/

cat > APIBypass.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>APIBypass</string>
	<key>CFBundleIdentifier</key>
	<string>com.apibypass.app</string>
	<key>CFBundleName</key>
	<string>APIBypass</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
</dict>
</plist>
PLIST

open APIBypass.app
```

### DMG

```bash
mkdir -p dmg_staging
cp -R APIBypass.app dmg_staging/
ln -s /Applications dmg_staging/Applications

hdiutil create -volname "APIBypass" \
  -srcfolder dmg_staging \
  -ov -format UDZO \
  APIBypass-1.0.0.dmg

rm -rf dmg_staging
```

## Usage

### 1. Start the Server

Click the APIBypass icon in the menu bar and select "启动服务" (Start Service). The indicator turns green when the server is running on `127.0.0.1:8390`.

### 2. Configure Mappings

Click "打开配置..." (Open Config) in the menu bar. Create a model mapping:

| Field | Description | Example |
|---|---|---|
| 配置名称 (Name) | A label for this mapping | `Qwen3 no thinking` |
| 客户端模型名 (Client Model) | The model name your client sends | `qwen3.6-plus` |
| 实际模型名 (Actual Model) | The real model to call upstream | `qwen3.6-plus` |
| API接口类型 (API Format) | OpenAI or Anthropic | `OpenAI` |
| Base URL | Upstream API endpoint | `https://api.example.com/v1` |
| API Key | Your upstream API key | Stored in Keychain |

### 3. Parameter Injection

- **Temperature / Max Tokens / Top P / Frequency Penalty / Presence Penalty**: Fill in a value to inject.
- **Thinking Mode**: Enable the master switch to configure:
  - Check "启用思考模式" → enable thinking
  - Uncheck → disable thinking
  - Turn off the master switch → don't touch, use API default
- **Custom Fields**: Inject arbitrary JSON key-value pairs. Values support strings, numbers, booleans, and objects.

### 4. Configure Your Client

Point your AI client to `http://127.0.0.1:8390/v1`. The API Key field can be anything — the proxy replaces it with your real key.

**Example (Cursor):**
```
OpenAI Base URL: http://127.0.0.1:8390/v1
Anthropic Base URL: http://127.0.0.1:8390/v1
```

### 5. Verify

Watch the terminal for `[APIBypass]` prefixed logs:
- Incoming request body
- Transformed request body (with injected parameters)
- Upstream API URL

## Project Structure

```
APIBypass/
├── APIBypassApp.swift          # App entry point
├── Core/
│   ├── ConfigManager.swift     # Config management (UserDefaults)
│   ├── HTTPServer.swift        # Hummingbird HTTP server
│   └── ProxyEngine.swift       # Request transform engine
├── Models/
│   ├── APIProvider.swift       # API provider enum
│   └── ModelMapping.swift      # Data models
├── Services/
│   ├── KeychainService.swift   # Secure Keychain storage
│   └── NetworkService.swift    # HTTP network service
├── UI/
│   ├── ConfigWindow.swift      # Config window + new mapping
│   ├── MenuBarView.swift       # Menu bar view
│   └── Views/
│       └── MappingDetailView.swift  # Mapping detail editor
└── Package.swift               # Swift Package manifest
```

## Tech Stack

- **SwiftUI** — macOS menu bar app
- **Hummingbird 2.0** — HTTP server framework
- **Keychain Services** — API key secure storage
- **UserDefaults** — Config persistence
- **async/await** — Async networking
- **ServiceLifecycle** — Service lifecycle management

## Privacy

- API Keys are stored in the system Keychain and never sent anywhere
- All traffic is processed locally — no third-party servers involved
- No telemetry or usage data collected

## License

MIT
