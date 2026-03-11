import SwiftUI
import Carbon

struct SettingsView: View {
    @AppStorage("maxHistoryCount") private var maxHistoryCount = 30
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode = 9       // V
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers = 768 // Cmd+Shift
    @State private var isRecording = false

    private var shortcutDisplay: String {
        HotkeyManager.displayString(keyCode: UInt32(hotkeyKeyCode), carbonModifiers: UInt32(hotkeyModifiers))
    }

    var body: some View {
        Form {
            LabeledContent("Global Shortcut") {
                HStack(spacing: 8) {
                    Text(isRecording ? "Press shortcut..." : shortcutDisplay)
                        .frame(minWidth: 80)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                        )

                    Button(isRecording ? "Cancel" : "Record") {
                        isRecording.toggle()
                    }

                    if !isRecording {
                        Button("Clear") {
                            hotkeyKeyCode = -1
                            hotkeyModifiers = 0
                            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .background(
                    ShortcutCaptureView(isRecording: $isRecording) { keyCode, modifiers in
                        hotkeyKeyCode = Int(keyCode)
                        hotkeyModifiers = Int(modifiers)
                        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                    }
                    .frame(width: 0, height: 0)
                )
            }

            Picker("Max History Items", selection: $maxHistoryCount) {
                Text("10").tag(10)
                Text("20").tag(20)
                Text("30").tag(30)
                Text("50").tag(50)
                Text("100").tag(100)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 150)
    }
}

// MARK: - Key capture via NSView

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = { keyCode, mods in
            onCapture(keyCode, mods)
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.isActive = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyCaptureNSView: NSView {
    var isActive = false
    var onCapture: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isActive else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.isEmpty else { return }
        let carbonMods = HotkeyManager.carbonModifiers(from: flags)
        onCapture?(UInt32(event.keyCode), carbonMods)
    }
}
