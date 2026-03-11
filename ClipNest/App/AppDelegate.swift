import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var clipboardMonitor: ClipboardMonitor!
    private(set) var dataStore = DataStore()
    private var snippetWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "ClipNest")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        clipboardMonitor = ClipboardMonitor(dataStore: dataStore)
        clipboardMonitor.start()

        requestAccessibilityIfNeeded()
        registerHotKey()
        hotkeyManager.onHotKey = { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(registerHotKey),
            name: .hotkeyChanged, object: nil
        )
    }

    private func requestAccessibilityIfNeeded() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        if !trusted {
            NSLog("[ClipNest] Accessibility permission not granted yet")
        }
    }

    @objc private func registerHotKey() {
        let keyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let modifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        if keyCode >= 0 && modifiers > 0 {
            hotkeyManager.register(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
        } else {
            hotkeyManager.unregister()
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(menu)
    }

    // MARK: - Menu Construction

    private func buildMenu(_ menu: NSMenu) {
        // Snippets first
        let folders = dataStore.rootFolders
        let rootSnippets = dataStore.rootSnippets
        if !folders.isEmpty || !rootSnippets.isEmpty {
            for folder in folders {
                menu.addItem(buildFolderMenuItem(folder))
            }
            for snippet in rootSnippets.sorted(by: { $0.order < $1.order }) {
                let item = NSMenuItem(
                    title: snippet.title,
                    action: #selector(handleSnippetItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = snippet.content
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // History as submenu
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        let historyMenu = NSMenu()
        let history = dataStore.history
        if history.isEmpty {
            let empty = NSMenuItem(title: "No History", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            for (i, clip) in history.prefix(dataStore.maxHistoryCount).enumerated() {
                let item = NSMenuItem(
                    title: clip.displayTitle,
                    action: #selector(handleHistoryItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = i
                historyMenu.addItem(item)
            }
            historyMenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            historyMenu.addItem(clearItem)
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        menu.addItem(.separator())

        let editItem = NSMenuItem(title: "Edit Snippets...", action: #selector(openSnippetEditor), keyEquivalent: "e")
        editItem.target = self
        editItem.keyEquivalentModifierMask = .command
        menu.addItem(editItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit ClipNest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
    }

    private func buildFolderMenuItem(_ folder: SnippetFolder) -> NSMenuItem {
        let item = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let submenu = NSMenu()

        for subfolder in folder.subfolders.sorted(by: { $0.order < $1.order }) {
            submenu.addItem(buildFolderMenuItem(subfolder))
        }

        if !folder.subfolders.isEmpty && !folder.snippets.isEmpty {
            submenu.addItem(.separator())
        }

        for snippet in folder.snippets.sorted(by: { $0.order < $1.order }) {
            let snippetItem = NSMenuItem(
                title: snippet.title,
                action: #selector(handleSnippetItem(_:)),
                keyEquivalent: ""
            )
            snippetItem.target = self
            snippetItem.representedObject = snippet.content
            submenu.addItem(snippetItem)
        }

        if submenu.items.isEmpty {
            let empty = NSMenuItem(title: "(Empty)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func handleHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < dataStore.history.count else { return }
        copyToPasteboard(dataStore.history[index].content)
    }

    @objc private func handleSnippetItem(_ sender: NSMenuItem) {
        guard let content = sender.representedObject as? String else { return }
        copyToPasteboard(content)
    }

    private func copyToPasteboard(_ text: String) {
        clipboardMonitor.pause()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.simulatePaste()
            self?.clipboardMonitor.resume()
        }
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)   // V
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    @objc private func clearHistory() {
        dataStore.clearHistory()
    }

    @objc private func openSnippetEditor() {
        if let window = snippetWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            let view = SnippetEditorView(dataStore: dataStore)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "Edit Snippets"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.setFrameAutosaveName("SnippetEditor")
            snippetWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        activateApp()
    }

    @objc private func openSettings() {
        NSLog("[ClipNest] openSettings called")
        activateApp()
        if let window = settingsWindow, window.isVisible {
            NSLog("[ClipNest] reusing existing settings window")
            window.makeKeyAndOrderFront(nil)
        } else {
            NSLog("[ClipNest] creating new settings window")
            let view = SettingsView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 150),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "ClipNest Settings"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.level = .floating
            settingsWindow = window
            window.makeKeyAndOrderFront(nil)
            NSLog("[ClipNest] settings window frame: \(window.frame)")
        }
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
