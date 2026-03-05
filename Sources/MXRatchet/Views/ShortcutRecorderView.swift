import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    var onRecord: (KeyCombo) -> Void

    @State private var recording = false
    @State private var recorded: KeyCombo?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Record Shortcut")
                .font(.headline)

            Text(recording ? "Press a key combination..." : (recorded?.displayName ?? "Click to start recording"))
                .font(.title3)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(recording ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(recording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                )
                .onTapGesture { recording = true }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if recorded != nil {
                    Button("Clear") {
                        recorded = nil
                        recording = true
                    }
                }
                Button("Done") {
                    if let combo = recorded {
                        onRecord(combo)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(recorded == nil)
            }
        }
        .padding(20)
        .background(KeyCaptureView(isActive: $recording, onCapture: { combo in
            recorded = combo
            recording = false
        }))
    }
}

// MARK: - Key Capture NSView

struct KeyCaptureView: NSViewRepresentable {
    @Binding var isActive: Bool
    var onCapture: (KeyCombo) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isCapturing = isActive
        nsView.onCapture = { combo in
            onCapture(combo)
            isActive = false
        }
        if isActive {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }
}

class KeyCaptureNSView: NSView {
    var isCapturing = false
    var onCapture: ((KeyCombo) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { return }
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]) != [] ||
              event.keyCode >= 96 /* F-keys */ else {
            // Require at least one modifier (or F-key)
            return
        }

        let combo = KeyCombo(
            keyCode: event.keyCode,
            modifiers: UInt64(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue),
            displayName: buildDisplayName(keyCode: event.keyCode, modifiers: event.modifierFlags)
        )
        onCapture?(combo)
    }

    private func buildDisplayName(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option)  { parts.append("\u{2325}") }
        if modifiers.contains(.shift)   { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    private func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "\u{21A9}",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "\u{21E5}", 49: "Space",
            50: "`", 51: "\u{232B}", 53: "\u{238B}",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14", 109: "F10",
            111: "F12", 113: "F15", 118: "F4", 120: "F2", 122: "F1",
            123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }
}
