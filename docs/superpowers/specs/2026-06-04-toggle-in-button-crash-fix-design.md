# Toggle-in-Button Crash Fix Design

**Date**: 2026-06-04
**Component**: MappingCardView.swift
**Priority**: Critical (crash fix)

## Problem

EXC_BAD_ACCESS crash during SwiftUI view updates when clicking Toggle controls in MappingCardView. Root cause: Toggle nested inside Button causes conflicting state modifications during SwiftUI's layout phase.

**Crash Pattern**:
- User clicks Toggle in mapping card header
- Both Toggle and Button receive the event
- SwiftUI's update cycle enters inconsistent state
- Memory corruption → EXC_BAD_ACCESS (SIGBUS)

**Affected Code**: `APIBypass/UI/Views/MappingCardView.swift:78-121`

## Solution

Restructure the view hierarchy to separate Toggle from Button's hit area.

### Implementation

**Before** (lines 78-121):
```swift
Button(action: { ... }) {
    HStack(spacing: 12) {
        Toggle("", isOn: $isEnabled)  // ← Nested inside Button
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
```

**After**:
```swift
HStack(spacing: 12) {
    Toggle("", isOn: $isEnabled)  // ← Moved outside Button
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
.padding(.horizontal, 12)
.padding(.vertical, 10)
```

### Key Changes

1. **Toggle extraction**: Toggle moved outside Button into parent HStack
2. **Spacing preservation**: Outer HStack spacing: 12 maintains visual spacing
3. **Padding adjustment**: Padding moved to outer HStack to maintain card dimensions
4. **No logic changes**: All callbacks, state bindings, and business logic unchanged

## Visual Impact

**Before**: `[Toggle] [●] [Name/Model → Model] [spacer] [chevron]`
**After**: `[Toggle] [●] [Name/Model → Model] [spacer] [chevron]`

Layout remains visually identical. Spacing between Toggle and Circle remains 12pt.

## Verification

**Manual Testing**:
1. Build and run application
2. Open mapping list, expand any mapping card
3. Rapidly click Toggle switch 10+ times
4. Verify:
   - Toggle state toggles correctly
   - No crashes occur
   - Card collapse/expand still works via Button
   - Visual layout matches original

**Success Criteria**:
- No EXC_BAD_ACCESS crashes during Toggle interaction
- All existing functionality preserved
- Visual layout unchanged

## Risk Assessment

**Low Risk**:
- Single file modification
- View structure change only, no logic changes
- Minimal code diff (~5 lines added)

**Potential Issues**:
- May need vertical alignment adjustment for Toggle
- Button contentShape may need refinement

## Files Modified

- `APIBypass/UI/Views/MappingCardView.swift` (lines 78-121)
