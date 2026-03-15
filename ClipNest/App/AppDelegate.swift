import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var clipboardMonitor: ClipboardMonitor!
    private(set) var dataStore = DataStore()
    private var snippetWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hotkeyManager = HotkeyManager()
    private var cursorMenuWindow: NSWindow?
    private var previousApp: NSRunningApplication?
    private var searchField: NSSearchField?
    private var currentFilterText = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "ClipNest")
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        clipboardMonitor = ClipboardMonitor(dataStore: dataStore)
        clipboardMonitor.start()

        requestAccessibilityIfNeeded()
        registerHotKey()
        hotkeyManager.onHotKey = { [weak self] in
            self?.showMenuAtCursor()
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

    // MARK: - Cursor Menu

    @objc private func statusItemClicked() {
        showMenuAtCursor()
    }

    private func showMenuAtCursor() {
        previousApp = NSWorkspace.shared.frontmostApplication

        let mouseLocation = NSEvent.mouseLocation
        let menu = NSMenu()
        menu.delegate = self
        buildMenu(menu)

        let window = NSWindow(
            contentRect: NSRect(x: mouseLocation.x - 1, y: mouseLocation.y - 1, width: 2, height: 2),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .popUpMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()

        cursorMenuWindow = window

        menu.popUp(positioning: nil, at: NSPoint(x: 1, y: 1), in: window.contentView)

        window.orderOut(nil)
        cursorMenuWindow = nil
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        if previousApp == nil {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        menu.removeAllItems()
        buildMenu(menu)
    }

    // MARK: - Menu Construction

    private func buildMenu(_ menu: NSMenu) {
        // Search field
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Search..."
        field.target = self
        field.action = #selector(searchFieldChanged(_:))
        field.stringValue = currentFilterText
        searchField = field
        let searchItem = NSMenuItem()
        searchItem.view = field
        menu.addItem(searchItem)
        menu.addItem(.separator())

        let isFiltering = !currentFilterText.isEmpty

        // Pinned section
        let pinned = dataStore.pinnedSnippets
        let filteredPinned = isFiltering ? pinned.filter { matchesFilter($0) } : pinned
        if !filteredPinned.isEmpty {
            let header = NSMenuItem(title: "Pinned", action: nil, keyEquivalent: "")
            header.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
            header.isEnabled = false
            menu.addItem(header)
            for snippet in filteredPinned {
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

        // Snippets
        let folders = dataStore.rootFolders
        let rootSnippets = dataStore.rootSnippets
        if !folders.isEmpty || !rootSnippets.isEmpty {
            for folder in folders {
                if isFiltering && !folderHasMatchingSnippets(folder) { continue }
                menu.addItem(buildFolderMenuItem(folder))
            }
            for snippet in rootSnippets.sorted(by: { $0.order < $1.order }) {
                if isFiltering && !matchesFilter(snippet) { continue }
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
                if isFiltering && !clip.content.localizedCaseInsensitiveContains(currentFilterText) {
                    continue
                }
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
        let isFiltering = !currentFilterText.isEmpty

        for subfolder in folder.subfolders.sorted(by: { $0.order < $1.order }) {
            if isFiltering && !folderHasMatchingSnippets(subfolder) { continue }
            submenu.addItem(buildFolderMenuItem(subfolder))
        }

        if !folder.subfolders.isEmpty && !folder.snippets.isEmpty {
            submenu.addItem(.separator())
        }

        for snippet in folder.snippets.sorted(by: { $0.order < $1.order }) {
            if isFiltering && !matchesFilter(snippet) { continue }
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
        let expanded = expandPlaceholders(in: text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(expanded, forType: .string)

        let autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
        guard autoPaste else {
            clipboardMonitor.resume()
            previousApp = nil
            return
        }

        // Reactivate the previously focused app before pasting
        if let app = previousApp {
            app.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.simulatePaste()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.clipboardMonitor.resume()
                self?.previousApp = nil
            }
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
        activateApp()
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
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
        }
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Placeholder Expansion

    private func expandPlaceholders(in text: String) -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        var result = text

        dateFormatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{{date}}", with: dateFormatter.string(from: now))

        dateFormatter.dateFormat = "HH:mm"
        result = result.replacingOccurrences(of: "{{time}}", with: dateFormatter.string(from: now))

        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        result = result.replacingOccurrences(of: "{{datetime}}", with: dateFormatter.string(from: now))

        if result.contains("{{clipboard}}") {
            let current = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{{clipboard}}", with: current)
        }

        return result
    }

    // MARK: - Search

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        currentFilterText = sender.stringValue
        guard let menu = sender.enclosingMenuItem?.menu else { return }
        menu.removeAllItems()
        buildMenu(menu)
        // Restore focus to the search field after rebuild
        DispatchQueue.main.async { [weak self] in
            self?.searchField?.becomeFirstResponder()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        currentFilterText = ""
    }

    private func matchesFilter(_ snippet: Snippet) -> Bool {
        snippet.title.localizedCaseInsensitiveContains(currentFilterText) ||
        snippet.content.localizedCaseInsensitiveContains(currentFilterText)
    }

    private func folderHasMatchingSnippets(_ folder: SnippetFolder) -> Bool {
        if folder.snippets.contains(where: { matchesFilter($0) }) { return true }
        return folder.subfolders.contains(where: { folderHasMatchingSnippets($0) })
    }
}
