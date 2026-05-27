# Provider Config UI Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the configuration UI so model mappings are nested inside provider detail pages as expandable cards with inline editing, drag-sorting, and enable/disable toggles. Add copy-provider feature.

**Architecture:** Keep NavigationSplitView but sidebar shows only providers. ProviderDetailView embeds a list of MappingCard views (each expandable for inline editing). ConfigManager gets moveProvider/moveMapping methods. Existing MappingDetailView editing logic is extracted into reusable MappingEditForm component.

**Tech Stack:** SwiftUI, Swift 6, macOS 14+

---

## File Structure

| Operation | File | Responsibility |
|-----------|------|----------------|
| Modify | `APIBypass/UI/ConfigWindow.swift` | Remove mapping section from sidebar; provider-only list with `.onMove`; copy context menu |
| Modify | `APIBypass/Core/ConfigManager.swift` | Add `moveProvider(from:to:)`, `moveMapping(providerId:from:to:)` |
| Create | `APIBypass/UI/Views/MappingEditForm.swift` | Reusable inline editing form (extracted from MappingDetailView logic) |
| Create | `APIBypass/UI/Views/MappingCardView.swift` | Expandable card with header (toggle + name + models) and inline edit form |
| Modify | `APIBypass/UI/Views/ProviderDetailView.swift` | Embed mapping cards list with drag-sort, add-mapping button, orphan mappings section |
| Modify | `APIBypass/UI/Views/MappingDetailView.swift` | Refactor to use `MappingEditForm` internally (reuse same component) |
| Modify | `APIBypass/Core/LocalizationManager.swift` | Add i18n keys for copy provider, collapse/expand, unsaved changes on collapse |

---

### Task 1: ConfigManager — Add Sorting Methods

**Files:**
- Modify: `APIBypass/Core/ConfigManager.swift`

- [ ] **Step 1: Add move methods**

Add after existing CRUD methods:

```swift
// MARK: - Reordering

func moveProvider(from source: IndexSet, to destination: Int) {
    providers.move(fromOffsets: source, toOffset: destination)
    saveProviders()
}

func moveMapping(providerId: UUID, from source: IndexSet, to destination: Int) {
    // Get all mappings for this provider
    let providerMappings = mappings.enumerated().filter { $0.element.providerConfigId == providerId }
    let indices = providerMappings.map { $0.offset }

    // Map local indices to global indices
    let globalSource = IndexSet(source.compactMap { idx in
        indices[safe: idx]
    })

    // We need a more robust approach: re-order within the global array
    var providerSpecificMappings = mappings.filter { $0.providerConfigId == providerId }
    providerSpecificMappings.move(fromOffsets: source, toOffset: destination)

    // Rebuild mappings array: non-provider mappings stay in place, provider ones get reordered
    var otherMappings = mappings.filter { $0.providerConfigId != providerId }
    var result: [ModelMapping] = []

    // Insert provider-specific mappings back into their original approximate position
    // Find insertion point: right after the last mapping that appeared before the first provider mapping
    let firstProviderMappingIndex = mappings.firstIndex { $0.providerConfigId == providerId }
    if let insertIndex = firstProviderMappingIndex {
        let splitIndex = min(insertIndex, otherMappings.count)
        result.append(contentsOf: otherMappings.prefix(splitIndex))
        result.append(contentsOf: providerSpecificMappings)
        result.append(contentsOf: otherMappings.suffix(max(0, otherMappings.count - splitIndex)))
    } else {
        result = otherMappings + providerSpecificMappings
    }

    mappings = result
    save()
}
```

Actually, a simpler approach for moveMapping: since all mappings for the same provider are stored consecutively (they are added one by one), we can just work with the filtered array and rebuild. But to keep it simple and correct, let's use a direct approach:

```swift
func moveMapping(providerId: UUID, from source: IndexSet, to destination: Int) {
    // Separate mappings into two groups: for this provider and others
    var providerMappings = mappings.filter { $0.providerConfigId == providerId }
    let otherMappings = mappings.filter { $0.providerConfigId != providerId }

    // Reorder within the provider group
    providerMappings.move(fromOffsets: source, toOffset: destination)

    // Find where to insert the provider mappings back
    // We keep them in the same relative position as before
    if let firstIndex = mappings.firstIndex(where: { $0.providerConfigId == providerId }) {
        let prefixCount = firstIndex
        var result = Array(mappings.prefix(prefixCount))
        // Remove provider mappings from prefix
        result.removeAll { $0.providerConfigId == providerId }
        result.append(contentsOf: providerMappings)
        result.append(contentsOf: mappings.suffix(from: prefixCount).filter { $0.providerConfigId != providerId })
        mappings = result
    } else {
        mappings = otherMappings + providerMappings
    }
    save()
}
```

Let's go with the simplest robust implementation:

```swift
func moveProvider(from source: IndexSet, to destination: Int) {
    providers.move(fromOffsets: source, toOffset: destination)
    saveProviders()
}

func moveMapping(providerId: UUID, from source: IndexSet, to destination: Int) {
    // Extract provider mappings with original indices
    let providerMappingIndices = mappings.enumerated()
        .filter { $0.element.providerConfigId == providerId }
        .map { $0.offset }

    guard !providerMappingIndices.isEmpty else { return }

    // Map local source to global source
    var globalSource = IndexSet()
    for localIndex in source {
        if localIndex < providerMappingIndices.count {
            globalSource.insert(providerMappingIndices[localIndex])
        }
    }

    // Compute global destination: position after providerMappingIndices[destination] or at end
    let globalDestination: Int
    if destination < providerMappingIndices.count {
        globalDestination = providerMappingIndices[destination]
    } else {
        globalDestination = (providerMappingIndices.last ?? 0) + 1
    }

    mappings.move(fromOffsets: globalSource, toOffset: globalDestination)
    save()
}
```

- [ ] **Step 2: Verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/Core/ConfigManager.swift
git commit -m "feat: add provider and mapping reordering methods"
```

---

### Task 2: Create MappingEditForm Reusable Component

**Files:**
- Create: `APIBypass/UI/Views/MappingEditForm.swift`

- [ ] **Step 1: Extract inline editing form**

This view encapsulates all the editing fields from MappingDetailView, but takes bindings instead of managing its own state. This allows it to be used both in MappingDetailView and inside MappingCardView.

```swift
import SwiftUI

struct MappingEditForm: View {
    @ObservedObject var configManager: ConfigManager
    let keychain: KeychainService

    // Basic info bindings
    @Binding var name: String
    @Binding var incomingModel: String
    @Binding var actualModel: String
    @Binding var selectedProviderId: UUID?
    @Binding var isEnabled: Bool

    // Parameter bindings
    @Binding var temperature: String
    @Binding var maxTokens: String
    @Binding var topP: String
    @Binding var frequencyPenalty: String
    @Binding var presencePenalty: String

    // Thinking bindings
    @Binding var thinkingOverrideEnabled: Bool
    @Binding var thinkingEnabled: Bool
    @Binding var thinkingBudget: String

    // Custom fields
    @Binding var customFields: [CustomField]
    @Binding var customFieldsEnabled: Bool

    @State private var showNewProviderSheet = false
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 12) {
            // Basic Info
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("basic_info"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text(L10n.t("config_name"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("config_name_placeholder"), text: $name)
                    }
                    HStack {
                        Text(L10n.t("incoming_model"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("incoming_model_field"), text: $incomingModel)
                    }
                    HStack {
                        Text(L10n.t("actual_model"))
                            .frame(width: 100, alignment: .trailing)
                        TextField(L10n.t("actual_model_field"), text: $actualModel)
                    }
                    HStack {
                        Text(L10n.t("provider"))
                            .frame(width: 100, alignment: .trailing)
                        Picker("", selection: $selectedProviderId) {
                            ForEach(configManager.providers) { provider in
                                Text(provider.name).tag(provider.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            showNewProviderSheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }

                    if let pid = selectedProviderId,
                       configManager.findProvider(for: pid) == nil {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(L10n.t("provider_deleted_warning"))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.leading, 108)
                    }

                    if let pid = selectedProviderId,
                       let provider = configManager.findProvider(for: pid) {
                        HStack {
                            Text("")
                                .frame(width: 100, alignment: .trailing)
                            Text("\(provider.apiProvider.rawValue) · \(provider.baseURL.host ?? provider.baseURL.absoluteString)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

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
                }

                Text(L10n.t("reasoning_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text(L10n.t("enable_thinking"))
                        Spacer()
                        Toggle("", isOn: $thinkingEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!thinkingOverrideEnabled)
                    }
                    if thinkingEnabled,
                       let pid = selectedProviderId,
                       let provider = configManager.findProvider(for: pid),
                       provider.apiProvider == .anthropic {
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
                }
                .opacity(thinkingOverrideEnabled ? 1.0 : 0.4)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Parameter Injection
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("param_injection"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text("Temperature")
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("temp_placeholder"), text: $temperature)
                    }
                    HStack {
                        Text("Max Tokens")
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("max_tokens_placeholder"), text: $maxTokens)
                    }
                    HStack {
                        Text("Top P")
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("top_p_placeholder"), text: $topP)
                    }
                    HStack {
                        Text("Frequency Penalty")
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("freq_penalty_placeholder"), text: $frequencyPenalty)
                    }
                    HStack {
                        Text("Presence Penalty")
                            .frame(width: 120, alignment: .trailing)
                        TextField(L10n.t("pres_penalty_placeholder"), text: $presencePenalty)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Custom Parameters
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.t("custom_params"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: $customFieldsEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                VStack(spacing: 8) {
                    HStack {
                        Button(action: {
                            customFields.append(CustomField(key: "", value: ""))
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                Text(L10n.t("add_field"))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!customFieldsEnabled)
                        Spacer()
                    }

                    if customFields.isEmpty {
                        Text(L10n.t("add_custom_hint"))
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(customFields.indices, id: \.self) { index in
                                HStack {
                                    TextField(L10n.t("field_name_placeholder"), text: $customFields[index].key)
                                        .frame(idealWidth: 140, maxWidth: .infinity)
                                        .disabled(!customFieldsEnabled)
                                    TextField(L10n.t("field_value_placeholder"), text: $customFields[index].value)
                                        .frame(idealWidth: 210, maxWidth: .infinity)
                                        .disabled(!customFieldsEnabled)
                                    Button(action: {
                                        customFields.remove(at: index)
                                    }) {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!customFieldsEnabled)
                                }
                            }
                        }
                    }
                }
                .opacity(customFieldsEnabled ? 1.0 : 0.4)

                Text(L10n.t("custom_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (new file not yet referenced)

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/Views/MappingEditForm.swift
git commit -m "feat: add reusable MappingEditForm component"
```

---

### Task 3: Create MappingCardView

**Files:**
- Create: `APIBypass/UI/Views/MappingCardView.swift`

- [ ] **Step 1: Create expandable mapping card**

```swift
import SwiftUI

struct MappingCardView: View {
    @ObservedObject var configManager: ConfigManager
    let keychain: KeychainService
    let mapping: ModelMapping

    var onSave: (() -> Void)?
    var onDelete: (() -> Void)?

    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var isExpanded = false
    @State private var showUnsavedAlert = false

    // Form state (mirrors MappingDetailView)
    @State private var name: String = ""
    @State private var incomingModel: String = ""
    @State private var actualModel: String = ""
    @State private var selectedProviderId: UUID?
    @State private var isEnabled = true

    @State private var temperature = ""
    @State private var maxTokens = ""
    @State private var topP = ""
    @State private var frequencyPenalty = ""
    @State private var presencePenalty = ""
    @State private var thinkingEnabled = false
    @State private var thinkingBudget = ""
    @State private var thinkingOverrideEnabled = false

    @State private var customFields: [CustomField] = []
    @State private var customFieldsEnabled = false

    // Original state for change detection
    @State private var originalMapping: ModelMapping?

    private var hasChanges: Bool {
        guard let original = originalMapping else { return false }
        if name != original.name { return true }
        if incomingModel != original.incomingModel { return true }
        if actualModel != original.actualModel { return true }
        if selectedProviderId != original.providerConfigId { return true }
        if isEnabled != original.isEnabled { return true }

        let currentParams = buildParameters()
        if currentParams.temperature != original.parameters.temperature { return true }
        if currentParams.maxTokens != original.parameters.maxTokens { return true }
        if currentParams.topP != original.parameters.topP { return true }
        if currentParams.frequencyPenalty != original.parameters.frequencyPenalty { return true }
        if currentParams.presencePenalty != original.parameters.presencePenalty { return true }
        if currentParams.thinkingOverrideEnabled != original.parameters.thinkingOverrideEnabled { return true }
        if currentParams.customFieldsEnabled != original.parameters.customFieldsEnabled { return true }
        if currentParams.customFields != original.parameters.customFields { return true }

        if let currentThinking = currentParams.thinking,
           let originalThinking = original.parameters.thinking {
            if currentThinking.enabled != originalThinking.enabled { return true }
            if currentThinking.budgetTokens != originalThinking.budgetTokens { return true }
        } else if currentParams.thinking != nil || original.parameters.thinking != nil {
            return true
        }

        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header - always visible, clickable to expand/collapse
            Button(action: {
                if isExpanded && hasChanges {
                    showUnsavedAlert = true
                } else {
                    isExpanded.toggle()
                    if isExpanded {
                        loadMappingData()
                    }
                }
            }) {
                HStack(spacing: 12) {
                    Toggle("", isOn: $isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .onChange(of: isEnabled) { _, newValue in
                            if originalMapping != nil {
                                quickSaveEnabled(newValue)
                            }
                        }

                    Circle()
                        .fill(mapping.isEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mapping.name)
                            .font(.body)
                        Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                MappingEditForm(
                    configManager: configManager,
                    keychain: keychain,
                    name: $name,
                    incomingModel: $incomingModel,
                    actualModel: $actualModel,
                    selectedProviderId: $selectedProviderId,
                    isEnabled: $isEnabled,
                    temperature: $temperature,
                    maxTokens: $maxTokens,
                    topP: $topP,
                    frequencyPenalty: $frequencyPenalty,
                    presencePenalty: $presencePenalty,
                    thinkingOverrideEnabled: $thinkingOverrideEnabled,
                    thinkingEnabled: $thinkingEnabled,
                    thinkingBudget: $thinkingBudget,
                    customFields: $customFields,
                    customFieldsEnabled: $customFieldsEnabled
                )
                .padding(12)

                HStack {
                    Button(L10n.t("save")) {
                        saveChanges()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)

                    Button(L10n.t("cancel")) {
                        if hasChanges {
                            showUnsavedAlert = true
                        } else {
                            isExpanded = false
                        }
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(role: .destructive) {
                        onDelete?()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .alert(L10n.t("unsaved_changes"), isPresented: $showUnsavedAlert) {
            Button(L10n.t("save"), role: .none) {
                saveChanges()
                isExpanded = false
            }
            Button(L10n.t("discard_changes"), role: .destructive) {
                loadMappingData()
                isExpanded = false
            }
            Button(L10n.t("cancel"), role: .cancel) { }
        } message: {
            Text(L10n.t("unsaved_changes_msg"))
        }
        .onAppear {
            loadMappingData()
        }
    }

    private func loadMappingData() {
        guard let current = configManager.mappings.first(where: { $0.id == mapping.id }) else { return }

        name = current.name
        incomingModel = current.incomingModel
        actualModel = current.actualModel
        selectedProviderId = current.providerConfigId
        isEnabled = current.isEnabled

        temperature = current.parameters.temperature.map(String.init) ?? ""
        maxTokens = current.parameters.maxTokens.map(String.init) ?? ""
        topP = current.parameters.topP.map(String.init) ?? ""
        frequencyPenalty = current.parameters.frequencyPenalty.map(String.init) ?? ""
        presencePenalty = current.parameters.presencePenalty.map(String.init) ?? ""

        if let thinking = current.parameters.thinking {
            thinkingEnabled = thinking.enabled
            thinkingBudget = thinking.budgetTokens.map(String.init) ?? ""
        }
        thinkingOverrideEnabled = current.parameters.thinkingOverrideEnabled ?? false
        if current.parameters.thinkingOverrideEnabled == nil && current.parameters.thinking != nil {
            thinkingOverrideEnabled = true
        }

        if let fields = current.parameters.customFields, !fields.isEmpty {
            customFields = fields.map { CustomField(key: $0.key, value: $0.value) }
        } else {
            customFields = []
        }
        customFieldsEnabled = current.parameters.customFieldsEnabled ?? false
        if current.parameters.customFieldsEnabled == nil && current.parameters.customFields != nil {
            customFieldsEnabled = true
        }

        originalMapping = current
    }

    private func quickSaveEnabled(_ enabled: Bool) {
        guard var current = configManager.mappings.first(where: { $0.id == mapping.id }) else { return }
        current.isEnabled = enabled
        configManager.update(current)
        onSave?()
    }

    private func saveChanges() {
        guard var current = configManager.mappings.first(where: { $0.id == mapping.id }),
              let providerId = selectedProviderId else { return }

        current.name = name
        current.incomingModel = incomingModel
        current.actualModel = actualModel
        current.providerConfigId = providerId
        current.isEnabled = isEnabled
        current.parameters = buildParameters()

        configManager.update(current)
        originalMapping = current
        onSave?()
    }

    private func buildParameters() -> InjectedParameters {
        let temp = Double(temperature)
        let tokens = Int(maxTokens)
        let topPValue = Double(topP)
        let freqPenalty = Double(frequencyPenalty)
        let presPenalty = Double(presencePenalty)

        let thinking = ThinkingConfig(
            enabled: thinkingEnabled,
            budgetTokens: thinkingEnabled ? Int(thinkingBudget) : nil
        )

        let customFieldsDict: [String: String]? = customFields.isEmpty
            ? nil
            : Dictionary(uniqueKeysWithValues: customFields.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) })

        return InjectedParameters(
            temperature: temp,
            maxTokens: tokens,
            topP: topPValue,
            frequencyPenalty: freqPenalty,
            presencePenalty: presPenalty,
            thinking: thinking,
            thinkingOverrideEnabled: thinkingOverrideEnabled,
            customFields: customFieldsDict,
            customFieldsEnabled: customFields.isEmpty ? nil : customFieldsEnabled
        )
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED (may need to check for errors in the new file)

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/Views/MappingCardView.swift
git commit -m "feat: add MappingCardView with expandable inline editing"
```

---

### Task 4: Refactor ProviderDetailView

**Files:**
- Modify: `APIBypass/UI/Views/ProviderDetailView.swift`

- [ ] **Step 1: Rewrite ProviderDetailView to embed mapping cards**

Keep the provider info editing section at top, replace the read-only related mappings section with an editable card list. Add drag-sorting and add-mapping button.

```swift
import SwiftUI

struct ProviderDetailView: View {
    @ObservedObject var configManager: ConfigManager
    let providerId: UUID
    let keychain: KeychainService

    var onHasChangesChange: ((Bool) -> Void)?
    var onSave: (() -> Void)?
    var forceResetTrigger: Int = 0
    var saveTrigger: Int = 0

    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var name: String = ""
    @State private var apiProvider: APIProvider = .openai
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var showSaveConfirmation = false

    @State private var originalName: String = ""
    @State private var originalApiProvider: APIProvider = .openai
    @State private var originalBaseURL: String = ""
    @State private var originalApiKey: String = ""
    @State private var lastResetTrigger = 0
    @State private var lastSaveTrigger = 0

    // Mapping creation sheet
    @State private var showNewMappingSheet = false

    private var hasChanges: Bool {
        name != originalName
            || apiProvider != originalApiProvider
            || baseURL != originalBaseURL
            || apiKey != originalApiKey
    }

    private var relatedMappings: [ModelMapping] {
        configManager.mappingsForProvider(providerId)
    }

    private var orphanMappings: [ModelMapping] {
        configManager.mappings.filter {
            configManager.findProvider(for: $0.providerConfigId) == nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Provider Info Section
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("provider_info"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text(L10n.t("provider_name"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("provider_name_placeholder"), text: $name)
                        }
                        HStack {
                            Text(L10n.t("api_provider"))
                                .frame(width: 100, alignment: .trailing)
                            Picker("", selection: $apiProvider) {
                                Text("OpenAI").tag(APIProvider.openai)
                                Text("Anthropic").tag(APIProvider.anthropic)
                            }
                            .pickerStyle(.menu)
                            .onChange(of: apiProvider) { _, newValue in
                                if baseURL.isEmpty || baseURL == APIProvider.openai.defaultBaseURL.absoluteString || baseURL == APIProvider.anthropic.defaultBaseURL.absoluteString {
                                    baseURL = newValue.defaultBaseURL.absoluteString
                                }
                            }
                        }
                        HStack {
                            Text(L10n.t("base_url"))
                                .frame(width: 100, alignment: .trailing)
                            TextField(L10n.t("base_url_placeholder"), text: $baseURL)
                        }
                        HStack {
                            Text(L10n.t("api_key"))
                                .frame(width: 100, alignment: .trailing)
                            SecureField(L10n.t("api_key_placeholder"), text: $apiKey)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Model Mappings Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.t("related_mappings"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showNewMappingSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text(L10n.t("add_mapping"))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if relatedMappings.isEmpty {
                        Text(L10n.t("select_or_create_hint"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(relatedMappings) { mapping in
                                MappingCardView(
                                    configManager: configManager,
                                    keychain: keychain,
                                    mapping: mapping,
                                    onSave: {
                                        onSave?()
                                    },
                                    onDelete: {
                                        configManager.delete(mapping.id)
                                    }
                                )
                            }
                            .onMove { source, destination in
                                configManager.moveMapping(providerId: providerId, from: source, to: destination)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Orphan mappings (if any provider is missing)
                if !orphanMappings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("未分类映射")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(orphanMappings) { mapping in
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text(mapping.name)
                                    .font(.body)
                                Text("\(mapping.incomingModel) → \(mapping.actualModel)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding()
        }
        .toolbar {
            Spacer()
            Button(action: {
                saveChanges()
            }) {
                Text(L10n.t("save"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hasChanges ? Color.accentColor : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(hasChanges ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .foregroundColor(hasChanges ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!hasChanges)
        }
        .onAppear {
            loadProviderData()
        }
        .onChange(of: hasChanges) { _, newValue in
            onHasChangesChange?(newValue)
        }
        .onChange(of: forceResetTrigger) { _, newValue in
            if newValue != lastResetTrigger {
                lastResetTrigger = newValue
                loadProviderData()
            }
        }
        .onChange(of: saveTrigger) { _, newValue in
            if newValue != lastSaveTrigger && hasChanges {
                lastSaveTrigger = newValue
                saveChanges()
            }
        }
        .alert(L10n.t("saved"), isPresented: $showSaveConfirmation) {
            Button(L10n.t("ok"), role: .cancel) {
                loadOriginalData()
            }
        }
        .sheet(isPresented: $showNewMappingSheet) {
            NewMappingView(configManager: configManager, keychain: keychain)
        }
    }

    private func loadProviderData() {
        guard let provider = configManager.findProvider(for: providerId) else { return }
        name = provider.name
        apiProvider = provider.apiProvider
        baseURL = provider.baseURL.absoluteString

        if let key = try? keychain.retrieve(forKey: providerId.uuidString) {
            apiKey = key
        }

        loadOriginalData()
    }

    private func loadOriginalData() {
        originalName = name
        originalApiProvider = apiProvider
        originalBaseURL = baseURL
        originalApiKey = apiKey
        onHasChangesChange?(false)
    }

    private func saveChanges() {
        guard let provider = configManager.findProvider(for: providerId) else { return }

        let updatedProvider = ProviderConfig(
            id: provider.id,
            name: name,
            apiProvider: apiProvider,
            baseURL: URL(string: baseURL) ?? apiProvider.defaultBaseURL
        )

        configManager.updateProvider(updatedProvider)

        if !apiKey.isEmpty {
            try? keychain.save(apiKey, forKey: providerId.uuidString)
        }

        onSave?()
        showSaveConfirmation = true
    }

    func discardChanges() {
        loadProviderData()
    }
}
```

- [ ] **Step 2: Verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/Views/ProviderDetailView.swift
git commit -m "feat: restructure ProviderDetailView with embedded mapping cards"
```

---

### Task 5: Refactor ConfigWindow Sidebar

**Files:**
- Modify: `APIBypass/UI/ConfigWindow.swift`

- [ ] **Step 1: Remove mapping section, add drag-sort and copy provider**

Key changes:
1. Remove `mappingSection` and `selectedMappingId` related logic
2. Keep only provider section in sidebar with `.onMove`
3. Add "Copy Provider" context menu item
4. Update `SelectionTarget` to only handle providers
5. Update `deleteSelected()` to only handle providers
6. Remove mapping-related alert states
7. Update detailView to only show ProviderDetailView or empty state

Simplified `ConfigWindow`:

```swift
import SwiftUI

struct ConfigWindow: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedProviderId: UUID?
    @State private var showNewProviderSheet = false
    @State private var showDeleteProviderConfirmation = false
    @State private var providerToDelete: ProviderConfig?

    // Change tracking
    @State private var currentHasChanges = false
    @State private var pendingProviderId: UUID?
    @State private var showSwitchConfirmation = false
    @State private var forceResetTrigger = 0
    @State private var saveAndSwitchTrigger = 0

    @ObservedObject private var l10n = LocalizationManager.shared
    private let keychain = KeychainService.shared

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailView
        }
        .sheet(isPresented: $showNewProviderSheet) {
            NewProviderView(configManager: configManager, keychain: keychain) { newProvider in
                selectedProviderId = newProvider.id
            }
        }
        .onAppear {
            let providerIds = configManager.providers.map { $0.id.uuidString }
            keychain.preloadKeys(for: providerIds)
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack {
            providerList
            bottomToolbar
        }
        .navigationTitle("APIBypass")
        .alert(L10n.t("confirm_delete_provider"), isPresented: $showDeleteProviderConfirmation) {
            Button(L10n.t("cancel"), role: .cancel) {
                providerToDelete = nil
            }
            Button(L10n.t("delete"), role: .destructive) {
                if let provider = providerToDelete {
                    configManager.deleteProvider(provider.id)
                    try? keychain.delete(forKey: provider.id.uuidString)
                    if selectedProviderId == provider.id {
                        selectedProviderId = nil
                    }
                }
                providerToDelete = nil
            }
        } message: {
            if let provider = providerToDelete {
                let count = configManager.mappingsForProvider(provider.id).count
                if count > 0 {
                    Text("\(L10n.t("confirm_delete_provider_msg"))「\(provider.name)」\(L10n.t("confirm_delete_provider_hint_prefix"))\(count)\(L10n.t("confirm_delete_provider_hint_suffix"))")
                } else {
                    Text("\(L10n.t("confirm_delete_msg"))「\(provider.name)」\(L10n.t("confirm_delete_hint"))")
                }
            } else {
                Text(L10n.t("confirm_delete_generic"))
            }
        }
        .alert(L10n.t("unsaved_changes"), isPresented: $showSwitchConfirmation) {
            Button(L10n.t("cancel"), role: .cancel) {
                pendingProviderId = nil
            }
            Button(L10n.t("discard_changes"), role: .destructive) {
                if let pid = pendingProviderId {
                    currentHasChanges = false
                    selectedProviderId = pid
                    forceResetTrigger += 1
                }
                pendingProviderId = nil
            }
            Button(L10n.t("save_and_switch")) {
                if let pid = pendingProviderId {
                    saveAndSwitchTrigger += 1
                }
                pendingProviderId = nil
            }
        } message: {
            Text(L10n.t("unsaved_changes_msg"))
        }
    }

    @ViewBuilder
    private var providerList: some View {
        List(selection: $selectedProviderId) {
            Section(L10n.t("providers")) {
                ForEach(configManager.providers) { provider in
                    providerRow(provider)
                }
                .onMove { source, destination in
                    configManager.moveProvider(from: source, to: destination)
                }
            }
        }
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private func providerRow(_ provider: ProviderConfig) -> some View {
        HStack {
            Image(systemName: provider.apiProvider == .openai ? "building.2" : "brain")
                .foregroundColor(.accentColor)
                .frame(width: 16)
            VStack(alignment: .leading) {
                Text(provider.name)
                    .font(.headline)
                Text(provider.baseURL.host ?? provider.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .tag(provider.id)
        .contextMenu {
            Button {
                copyProvider(provider)
            } label: {
                Label(L10n.t("copy_config"), systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                providerToDelete = provider
                showDeleteProviderConfirmation = true
            } label: {
                Label(L10n.t("delete_provider"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var bottomToolbar: some View {
        HStack {
            Button {
                showNewProviderSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help(L10n.t("add_provider"))

            Spacer()

            Button {
                deleteSelected()
            } label: {
                Image(systemName: "minus")
            }
            .help(L10n.t("delete_selected"))
            .disabled(selectedProviderId == nil)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func deleteSelected() {
        if let pid = selectedProviderId,
           let provider = configManager.findProvider(for: pid) {
            providerToDelete = provider
            showDeleteProviderConfirmation = true
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let pid = selectedProviderId,
           configManager.findProvider(for: pid) != nil {
            ProviderDetailView(
                configManager: configManager,
                providerId: pid,
                keychain: keychain,
                onHasChangesChange: { hasChanges in
                    currentHasChanges = hasChanges
                },
                onSave: {
                    currentHasChanges = false
                },
                forceResetTrigger: forceResetTrigger,
                saveTrigger: saveAndSwitchTrigger
            )
            .id(pid)
        } else {
            emptyStateView
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(L10n.t("select_or_create"))
                .font(.title2)
                .foregroundColor(.secondary)
            Text(L10n.t("select_or_create_hint"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showNewProviderSheet = true
            } label: {
                Label(L10n.t("create_provider"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func copyProvider(_ provider: ProviderConfig) {
        let newProvider = ProviderConfig(
            name: provider.name + " 副本",
            apiProvider: provider.apiProvider,
            baseURL: provider.baseURL
        )

        configManager.addProvider(newProvider)

        // Copy API key
        if let apiKey = try? keychain.retrieve(forKey: provider.id.uuidString) {
            try? keychain.save(apiKey, forKey: newProvider.id.uuidString)
        }

        // Copy all mappings
        let mappingsToCopy = configManager.mappingsForProvider(provider.id)
        for mapping in mappingsToCopy {
            let newMapping = ModelMapping(
                name: mapping.name,
                incomingModel: mapping.incomingModel,
                actualModel: mapping.actualModel,
                providerConfigId: newProvider.id,
                parameters: mapping.parameters,
                isEnabled: mapping.isEnabled
            )
            configManager.add(newMapping)
        }

        selectedProviderId = newProvider.id
    }
}
```

Note: Need to handle selection change with unsaved changes. Since we use `List(selection: $selectedProviderId)` directly, we need a custom Binding:

```swift
private var providerList: some View {
    List(selection: Binding<UUID?>(
        get: { selectedProviderId },
        set: { newId in
            if currentHasChanges && newId != selectedProviderId {
                pendingProviderId = newId
                showSwitchConfirmation = true
            } else {
                selectedProviderId = newId
            }
        }
    )) {
        Section(L10n.t("providers")) {
            ForEach(configManager.providers) { provider in
                providerRow(provider)
            }
            .onMove { source, destination in
                configManager.moveProvider(from: source, to: destination)
            }
        }
    }
    .frame(minWidth: 220)
}
```

- [ ] **Step 2: Verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add APIBypass/UI/ConfigWindow.swift
git commit -m "feat: simplify sidebar to provider-only with drag-sort and copy"
```

---

### Task 6: Update Localization

**Files:**
- Modify: `APIBypass/Core/LocalizationManager.swift`

- [ ] **Step 1: Add new i18n keys**

Add these keys to `L10n.dict`:

```swift
"copy_provider": [.chinese: "复制提供商", .english: "Copy Provider"],
"expand": [.chinese: "展开", .english: "Expand"],
"collapse": [.chinese: "收起", .english: "Collapse"],
"add_mapping": [.chinese: "添加映射", .english: "Add Mapping"],
```

Note: `copy_config` key already exists and can be reused for "Copy Provider" context menu, or add a specific key.

Update `copy_config` to be generic enough or add `copy_provider`.

- [ ] **Step 2: Commit**

```bash
git add APIBypass/Core/LocalizationManager.swift
git commit -m "feat: add i18n keys for UI improvements"
```

---

### Task 7: Cleanup and Verification

- [ ] **Step 1: Full build**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Manual verification checklist**

1. Sidebar shows only providers, no mapping section
2. Provider rows can be drag-sorted
3. Right-click provider shows "Copy" and "Delete" options
4. Copying a provider creates one with " 副本" suffix, same API key, and copied mappings
5. Selecting a provider shows detail page with provider info + mapping cards
6. Mapping cards show toggle, name, and model mapping
7. Toggle changes save immediately
8. Clicking card header expands to show edit form
9. Edit form has all fields (name, models, provider, params, thinking, custom)
10. Changes in expanded form require clicking Save
11. Collapsing with unsaved changes shows confirmation alert
12. Mapping cards can be drag-sorted within the provider
13. "+ 添加映射" button opens new mapping sheet
14. Deleting a provider shows count of affected mappings

- [ ] **Step 3: Update version**

Update `SettingsView.swift` version to `0.5.0`.
Update `RELEASE_NOTES.md` with v0.5.0 notes.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "release: v0.5.0 - provider config UI improvements"
```
