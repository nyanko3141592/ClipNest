import AppKit
import SwiftUI

// MARK: - MenuSearchField

private class MenuSearchField: NSSearchField {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, Numpad Enter
            onReturn?()
        case 125: // Down Arrow — resign so menu handles navigation
            window?.makeFirstResponder(nil)
        default:
            super.keyDown(with: event)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var clipboardMonitor: ClipboardMonitor!
    private(set) var dataStore = DataStore()
    private var snippetWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hotkeyManager = HotkeyManager()
    private var previousApp: NSRunningApplication?
    private var searchField: NSSearchField?
    private var currentFilterText = ""
    private var mainMenu = NSMenu()
    private var popupPanel: PopupPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "hotkeyKeyCode": 9,        // V
            "hotkeyModifiers": 2048,   // optionKey
            "autoPaste": true,
            "playCopySound": true,
            "maxHistoryCount": 30,
        ])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "ClipNest")
        }

        mainMenu.delegate = self
        statusItem.menu = mainMenu

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

    // MARK: - Show Panel at Cursor

    private func showMenuAtCursor() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if popupPanel == nil {
            let panel = PopupPanel()
            panel.onSelectContent = { [weak self] content in
                self?.copyToPasteboard(content)
            }
            panel.onSelectHistory = { [weak self] index in
                guard let self = self, index < self.dataStore.history.count else { return }
                let item = self.dataStore.history[index]
                if item.isImage {
                    self.copyImageToPasteboard(item)
                } else {
                    self.copyToPasteboard(item.content)
                }
            }
            popupPanel = panel
        }

        let mouseLocation = NSEvent.mouseLocation
        popupPanel?.showAt(mouseLocation, dataStore: dataStore)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        if previousApp == nil {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        menu.removeAllItems()
        buildMenu(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        currentFilterText = ""
    }

    // MARK: - Menu Construction

    private func buildMenu(_ menu: NSMenu) {
        // Search field
        let field = MenuSearchField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Search..."
        field.target = self
        field.action = #selector(searchFieldChanged(_:))
        field.stringValue = currentFilterText
        field.onReturn = { [weak self] in
            self?.selectFirstActionableItem(in: menu)
        }
        searchField = field
        let searchItem = NSMenuItem()
        searchItem.view = field
        menu.addItem(searchItem)
        menu.addItem(.separator())

        let isFiltering = !currentFilterText.isEmpty
        var shortcutIndex = 1

        // Pinned section
        let pinned = dataStore.pinnedSnippets
        let filteredPinned = isFiltering ? pinned.filter { matchesFilter($0) } : pinned
        if !filteredPinned.isEmpty {
            let header = NSMenuItem(title: "Pinned", action: nil, keyEquivalent: "")
            header.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
            header.isEnabled = false
            menu.addItem(header)
            for snippet in filteredPinned {
                menu.addItem(makeSnippetMenuItem(snippet, shortcutIndex: &shortcutIndex))
            }
            menu.addItem(.separator())
        }

        // Snippets
        let folders = dataStore.rootFolders
        let rootSnippets = dataStore.rootSnippets
        if !folders.isEmpty || !rootSnippets.isEmpty {
            if isFiltering {
                // Flat list with folder path prefix
                addFilteredSnippets(folders: folders, rootSnippets: rootSnippets, to: menu, shortcutIndex: &shortcutIndex)
            } else {
                // Folder submenus — →/← for keyboard navigation
                for folder in folders.sorted(by: { $0.order < $1.order }) {
                    menu.addItem(buildFolderMenuItem(folder, shortcutIndex: &shortcutIndex))
                }
                for snippet in rootSnippets.sorted(by: { $0.order < $1.order }) {
                    menu.addItem(makeSnippetMenuItem(snippet, shortcutIndex: &shortcutIndex))
                }
            }
            menu.addItem(.separator())
        }

        // History — recent inline, older in submenu
        let history = dataStore.history
        let recentCount = DataStore.recentHistoryCount
        let allIndexed = Array(history.prefix(dataStore.maxHistoryCount).enumerated())
        let filteredHistory = isFiltering
            ? allIndexed.filter { $0.element.isImage ? "[Image]".localizedCaseInsensitiveContains(currentFilterText) : $0.element.content.localizedCaseInsensitiveContains(currentFilterText) }
            : allIndexed

        if !filteredHistory.isEmpty {
            let recentItems = filteredHistory.prefix(recentCount)
            let olderItems = filteredHistory.dropFirst(recentCount)

            let headerTitle = isFiltering ? "History" : "History (recent \(recentItems.count))"
            let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
            header.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            header.isEnabled = false
            menu.addItem(header)

            for (i, clip) in recentItems {
                let item = NSMenuItem(
                    title: clip.displayTitle,
                    action: #selector(handleHistoryItem(_:)),
                    keyEquivalent: shortcutIndex <= 9 ? "\(shortcutIndex)" : ""
                )
                if shortcutIndex <= 9 {
                    item.keyEquivalentModifierMask = .command
                    shortcutIndex += 1
                }
                item.target = self
                item.tag = i
                menu.addItem(item)
            }

            // Older history in submenu — → to open
            if !olderItems.isEmpty {
                let moreItem = NSMenuItem(title: "More... (\(olderItems.count))", action: nil, keyEquivalent: "")
                moreItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
                let moreMenu = NSMenu()
                for (i, clip) in olderItems {
                    let item = NSMenuItem(
                        title: clip.displayTitle,
                        action: #selector(handleHistoryItem(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.tag = i
                    moreMenu.addItem(item)
                }
                moreItem.submenu = moreMenu
                menu.addItem(moreItem)
            }

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
            menu.addItem(.separator())
        }

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

    // MARK: - Folder submenu (→ open, ← close)

    private func buildFolderMenuItem(_ folder: SnippetFolder, shortcutIndex: inout Int) -> NSMenuItem {
        let item = NSMenuItem(title: folder.title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let submenu = NSMenu()

        for subfolder in folder.subfolders.sorted(by: { $0.order < $1.order }) {
            submenu.addItem(buildFolderMenuItem(subfolder, shortcutIndex: &shortcutIndex))
        }

        if !folder.subfolders.isEmpty && !folder.snippets.isEmpty {
            submenu.addItem(.separator())
        }

        for snippet in folder.snippets.sorted(by: { $0.order < $1.order }) {
            submenu.addItem(makeSnippetMenuItem(snippet, shortcutIndex: &shortcutIndex))
        }

        if submenu.items.isEmpty {
            let empty = NSMenuItem(title: "(Empty)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        item.submenu = submenu
        return item
    }

    // MARK: - Filtered flat list (search mode)

    private func addFilteredSnippets(folders: [SnippetFolder], rootSnippets: [Snippet], to menu: NSMenu, shortcutIndex: inout Int) {
        collectMatchingSnippets(from: folders, path: "", to: menu, shortcutIndex: &shortcutIndex)

        for snippet in rootSnippets.sorted(by: { $0.order < $1.order }) {
            if !matchesFilter(snippet) { continue }
            menu.addItem(makeSnippetMenuItem(snippet, shortcutIndex: &shortcutIndex))
        }
    }

    private func collectMatchingSnippets(from folders: [SnippetFolder], path: String, to menu: NSMenu, shortcutIndex: inout Int) {
        for folder in folders.sorted(by: { $0.order < $1.order }) {
            let folderPath = path.isEmpty ? folder.title : "\(path)/\(folder.title)"
            for snippet in folder.snippets.sorted(by: { $0.order < $1.order }) {
                if !matchesFilter(snippet) { continue }
                menu.addItem(makeSnippetMenuItem(snippet, title: "\(folderPath) › \(snippet.title)", shortcutIndex: &shortcutIndex))
            }
            collectMatchingSnippets(from: folder.subfolders, path: folderPath, to: menu, shortcutIndex: &shortcutIndex)
        }
    }

    // MARK: - Actions

    @objc private func handleHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < dataStore.history.count else { return }
        let item = dataStore.history[index]
        if item.isImage {
            copyImageToPasteboard(item)
        } else {
            copyToPasteboard(item.content)
        }
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

    private func copyImageToPasteboard(_ item: ClipboardItem) {
        guard let fileName = item.imageFileName else { return }
        let fileURL = dataStore.imageURL(for: fileName)
        guard let imageData = try? Data(contentsOf: fileURL) else { return }

        clipboardMonitor.pause()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(imageData, forType: .png)

        let autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
        guard autoPaste else {
            clipboardMonitor.resume()
            previousApp = nil
            return
        }

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
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
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
        activateApp()
        if let window = snippetWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = NSHostingController(rootView: SnippetEditorView(dataStore: dataStore))
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.title = "Edit Snippets"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.center()
        window.setFrameAutosaveName("SnippetEditor")
        snippetWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        activateApp()
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.title = "ClipNest Settings"
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
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

    private func selectFirstActionableItem(in menu: NSMenu) {
        for item in menu.items {
            if item.isSeparatorItem || !item.isEnabled || item.view != nil { continue }
            if let content = item.representedObject as? String {
                menu.cancelTracking()
                copyToPasteboard(content)
                return
            }
            if item.action == #selector(handleHistoryItem(_:)) {
                let index = item.tag
                guard index < dataStore.history.count else { continue }
                let historyItem = dataStore.history[index]
                menu.cancelTracking()
                if historyItem.isImage {
                    copyImageToPasteboard(historyItem)
                } else {
                    copyToPasteboard(historyItem.content)
                }
                return
            }
        }
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        currentFilterText = sender.stringValue
        guard let menu = sender.enclosingMenuItem?.menu else { return }
        menu.removeAllItems()
        buildMenu(menu)
        DispatchQueue.main.async { [weak self] in
            self?.searchField?.becomeFirstResponder()
        }
    }

    private func makeSnippetMenuItem(_ snippet: Snippet, title: String? = nil, shortcutIndex: inout Int) -> NSMenuItem {
        let item = NSMenuItem(
            title: title ?? snippet.title,
            action: #selector(handleSnippetItem(_:)),
            keyEquivalent: shortcutIndex <= 9 ? "\(shortcutIndex)" : ""
        )
        if shortcutIndex <= 9 {
            item.keyEquivalentModifierMask = .command
            shortcutIndex += 1
        }
        item.target = self
        item.representedObject = snippet.content
        item.image = NSImage(systemSymbolName: snippet.resolvedIcon, accessibilityDescription: nil)
        return item
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
