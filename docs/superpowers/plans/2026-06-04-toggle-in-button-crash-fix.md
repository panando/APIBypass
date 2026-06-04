# Toggle-in-Button Crash Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix EXC_BAD_ACCESS crash caused by Toggle nested inside Button in MappingCardView.swift

**Architecture:** Extract Toggle from Button's view hierarchy while preserving visual layout and all functionality. Toggle becomes sibling to Button in outer HStack container.

**Tech Stack:** SwiftUI, macOS App

---

### Task 1: Refactor MappingCardView Header Structure

**Files:**
- Modify: `APIBypass/UI/Views/MappingCardView.swift:78-121`

- [ ] **Step 1: Read the current implementation**

Read the file to understand the exact current structure:
```bash
# Verify the current code structure at lines 78-121
```

- [ ] **Step 2: Replace Button-enclosed Toggle with separated structure**

Replace lines 78-121 with the refactored structure:

```swift
HStack(spacing: 12) {
    Toggle("", isOn: $isEnabled)
        .toggleStyle(.switch)
        .labelsHidden()
        .onChange(of: isEnabled) { _, newValue in
            if originalMapping != nil {
                quickSaveEnabled(newValue)
            }
        }

    Button(action: {
        if isExpanded && hasChanges {
            showUnsavedAlert = true
        } else {
            let newValue = !isExpanded
            if newValue {
                loadMappingData()
            }
            isExpanded = newValue
        }
    }) {
        HStack(spacing: 12) {
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
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
.padding(.horizontal, 12)
.padding(.vertical, 10)
```

**Key changes from original:**
1. Toggle moved outside Button into parent HStack
2. Outer HStack has spacing: 12 to maintain spacing between Toggle and Circle
3. Padding moved from Button to outer HStack
4. Button action and all callbacks remain unchanged

- [ ] **Step 3: Build the project**

Run: `xcodebuild -scheme APIBypass -configuration Debug build`
Expected: Build succeeds with no errors

- [ ] **Step 4: Manual smoke test**

1. Run the application in Xcode or via: `open build/Release/APIBypass.app`
2. Open the mapping list view
3. Expand any mapping card
4. Click the Toggle switch 10+ times rapidly
5. Verify:
   - Toggle state changes correctly
   - No crash occurs
   - Card can still expand/collapse by clicking the card body
   - Visual layout appears unchanged

- [ ] **Step 5: Commit the fix**

```bash
git add APIBypass/UI/Views/MappingCardView.swift
git commit -m "fix: move Toggle outside Button to prevent crash

EXC_BAD_ACCESS occurred when Toggle was nested inside Button.
Both controls responded to the same click event, causing
conflicting state modifications during SwiftUI's layout phase.

Changes:
- Move Toggle to parent HStack, outside Button's hit area
- Preserve visual layout with spacing: 12
- All callbacks and functionality unchanged"
```

---

## Verification Checklist

After completing all tasks:

- [ ] Application builds without errors
- [ ] Toggle clicks no longer cause crashes
- [ ] Card expand/collapse still works via Button
- [ ] Visual layout matches original design
- [ ] All Toggle state changes save correctly via quickSaveEnabled()
