import SwiftUI

struct ProfileEditorView: View {
    let profile: AppProfile
    @ObservedObject var mappingStore: MappingStore
    @State private var recordingShortcutForButton: Int?
    @State private var recordingShortcutForGesture: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text(profile.displayName)
                        .font(.title2.bold())
                    if profile.bundleId != "*" {
                        Text(profile.bundleId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Button Mappings
                Text("Button Mappings")
                    .font(.headline)

                ForEach(profile.buttons) { button in
                    HStack {
                        Text(button.label)
                            .frame(width: 120, alignment: .leading)
                        Spacer()
                        actionMenu(
                            current: button.action,
                            onSelect: { action in
                                var updated = profile
                                if let idx = updated.buttons.firstIndex(where: { $0.id == button.id }) {
                                    updated.buttons[idx].action = action
                                    mappingStore.updateProfile(updated)
                                }
                            },
                            onRecordShortcut: {
                                recordingShortcutForButton = button.id
                            }
                        )
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                // Gesture Button
                Text("Gesture Button")
                    .font(.headline)

                gestureRow("Tap", action: profile.gesture.tap, key: "tap")
                gestureRow("Swipe Up", action: profile.gesture.swipeUp, key: "swipeUp")
                gestureRow("Swipe Down", action: profile.gesture.swipeDown, key: "swipeDown")
                gestureRow("Swipe Left", action: profile.gesture.swipeLeft, key: "swipeLeft")
                gestureRow("Swipe Right", action: profile.gesture.swipeRight, key: "swipeRight")
            }
            .padding(20)
        }
        .sheet(item: shortcutBinding) { target in
            ShortcutRecorderView { combo in
                applyShortcut(combo, to: target)
            }
            .frame(width: 300, height: 150)
        }
    }

    // MARK: - Action Menu

    @ViewBuilder
    private func actionMenu(
        current: ButtonAction,
        onSelect: @escaping (ButtonAction) -> Void,
        onRecordShortcut: @escaping () -> Void
    ) -> some View {
        Menu {
            Button("Default") { onSelect(.passthrough) }
            Button("Disabled") { onSelect(.disabled) }

            Divider()

            Menu("System Actions") {
                ForEach(SystemAction.allCases, id: \.self) { action in
                    Button(action.displayName) { onSelect(.systemAction(action)) }
                }
            }

            Divider()

            Button("Keyboard Shortcut...") { onRecordShortcut() }
        } label: {
            Text(current.displayName)
                .frame(minWidth: 140, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Gesture Row

    @ViewBuilder
    private func gestureRow(_ label: String, action: ButtonAction, key: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            Spacer()
            actionMenu(
                current: action,
                onSelect: { newAction in
                    var updated = profile
                    switch key {
                    case "tap": updated.gesture.tap = newAction
                    case "swipeUp": updated.gesture.swipeUp = newAction
                    case "swipeDown": updated.gesture.swipeDown = newAction
                    case "swipeLeft": updated.gesture.swipeLeft = newAction
                    case "swipeRight": updated.gesture.swipeRight = newAction
                    default: break
                    }
                    mappingStore.updateProfile(updated)
                },
                onRecordShortcut: {
                    recordingShortcutForGesture = key
                }
            )
        }
        .padding(.vertical, 2)
    }

    // MARK: - Shortcut Sheet

    private var shortcutBinding: Binding<ShortcutTarget?> {
        Binding(
            get: {
                if let btn = recordingShortcutForButton {
                    return ShortcutTarget(id: "button-\(btn)", buttonId: btn, gestureKey: nil)
                }
                if let key = recordingShortcutForGesture {
                    return ShortcutTarget(id: "gesture-\(key)", buttonId: nil, gestureKey: key)
                }
                return nil
            },
            set: { _ in
                recordingShortcutForButton = nil
                recordingShortcutForGesture = nil
            }
        )
    }

    private func applyShortcut(_ combo: KeyCombo, to target: ShortcutTarget) {
        var updated = profile

        if let btnId = target.buttonId,
           let idx = updated.buttons.firstIndex(where: { $0.id == btnId }) {
            updated.buttons[idx].action = .keyboardShortcut(combo)
        } else if let key = target.gestureKey {
            let action = ButtonAction.keyboardShortcut(combo)
            switch key {
            case "tap": updated.gesture.tap = action
            case "swipeUp": updated.gesture.swipeUp = action
            case "swipeDown": updated.gesture.swipeDown = action
            case "swipeLeft": updated.gesture.swipeLeft = action
            case "swipeRight": updated.gesture.swipeRight = action
            default: break
            }
        }

        mappingStore.updateProfile(updated)
        recordingShortcutForButton = nil
        recordingShortcutForGesture = nil
    }
}

struct ShortcutTarget: Identifiable {
    let id: String
    let buttonId: Int?
    let gestureKey: String?
}
