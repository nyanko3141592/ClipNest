import AppKit

final class PopupPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {

    enum Row {
        case header(String, String?)
        case folder(String, UUID, Int, Bool)
        case snippet(String, String, Int)
        case historyItem(String, Int, appName: String?, bundleID: String?)
        case separator

        var isSelectable: Bool {
            switch self {
            case .header, .separator: return false
            default: return true
            }
        }
    }

    var onSelectContent: ((String) -> Void)?
    var onSelectHistory: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var rows: [Row] = []
    private var expandedFolders: Set<UUID> = []
    private weak var dataStore: DataStore?
    private var clickMonitor: Any?
    private var firstHistoryRow: Int?
    private var iconCache: [String: NSImage] = [:]

    override init(contentRect: NSRect, styleMask s: NSWindow.StyleMask, backing b: NSWindow.BackingStoreType, defer d: Bool) {
        super.init(contentRect: contentRect, styleMask: s, backing: b, defer: d)
    }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 340),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        isReleasedWhenClosed = false
        isMovable = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear

        let visual = NSVisualEffectView(frame: .zero)
        visual.material = .menu
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 6
        visual.layer?.masksToBounds = true
        visual.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 340))
        contentView = wrapper
        wrapper.addSubview(visual)

        NSLayoutConstraint.activate([
            visual.topAnchor.constraint(equalTo: wrapper.topAnchor),
            visual.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            visual.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            visual.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = 236
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.action = #selector(tableClicked)
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: visual.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visual.bottomAnchor, constant: -4),
        ])
    }

    // MARK: - Show / Hide

    func showAt(_ point: NSPoint, dataStore: DataStore) {
        self.dataStore = dataStore
        rebuildRows()
        tableView.reloadData()

        let panelSize = frame.size
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let scr = screen.visibleFrame

        var x = point.x
        var y = point.y - panelSize.height
        if x + panelSize.width > scr.maxX { x = scr.maxX - panelSize.width }
        if x < scr.minX { x = scr.minX }
        if y < scr.minY { y = scr.minY }
        if y + panelSize.height > scr.maxY { y = scr.maxY - panelSize.height }

        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let idx = self.firstHistoryRow, idx < self.rows.count {
                self.tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                self.tableView.scrollRowToVisible(idx)
            } else {
                self.selectFirstSelectable()
            }
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        orderOut(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    override var canBecomeKey: Bool { true }
    override func resignKey() { super.resignKey(); dismiss() }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if let chars = event.charactersIgnoringModifiers,
           let digit = chars.first?.wholeNumberValue,
           digit >= 1, digit <= 9 {
            activateNthSelectable(digit)
            return
        }
        switch event.keyCode {
        case 53: dismiss()
        case 36, 76: activateSelectedRow()
        case 125: selectNext()
        case 126: selectPrevious()
        case 124: toggleSelectedFolder(expand: true)
        case 123: toggleSelectedFolder(expand: false)
        default: break
        }
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .separator:
            let box = NSBox()
            box.boxType = .separator
            return box
        case .header(let title, let icon):
            return makeHeader(title, icon: icon)
        case .folder(let title, _, let depth, let expanded):
            let arrow = expanded ? "▾" : "▸"
            return makeCell("\(arrow) \(title)", depth: depth, icon: expanded ? "folder.fill" : "folder", dim: false)
        case .snippet(let title, _, let depth):
            return makeCell(title, depth: depth, icon: nil, dim: false)
        case .historyItem(let title, _, let appName, let bundleID):
            let selectableIndex = selectableIndexForRow(row)
            return makeHistoryCell(title, appName: appName, bundleID: bundleID, number: selectableIndex)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].isSelectable
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .separator = rows[row] { return 6 }
        if case .header = rows[row] { return 18 }
        if case .historyItem = rows[row] { return 26 }
        return 22
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CompactRowView()
    }

    // MARK: - Cells

    private func makeHeader(_ title: String, icon: String?) -> NSView {
        let h = NSStackView()
        h.orientation = .horizontal
        h.spacing = 3
        h.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        if let icon, let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .medium)) {
            let iv = NSImageView(image: img)
            iv.contentTintColor = .tertiaryLabelColor
            iv.setContentHuggingPriority(.required, for: .horizontal)
            h.addArrangedSubview(iv)
        }
        let l = NSTextField(labelWithString: title.uppercased())
        l.font = .systemFont(ofSize: 9, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        h.addArrangedSubview(l)
        return h
    }

    private func makeCell(_ title: String, depth: Int, icon: String?, dim: Bool) -> NSView {
        let h = NSStackView()
        h.orientation = .horizontal
        h.spacing = 4
        h.edgeInsets = NSEdgeInsets(top: 0, left: CGFloat(8 + depth * 12), bottom: 0, right: 6)
        if let icon, let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular)) {
            let iv = NSImageView(image: img)
            iv.contentTintColor = .secondaryLabelColor
            iv.setContentHuggingPriority(.required, for: .horizontal)
            iv.widthAnchor.constraint(equalToConstant: 14).isActive = true
            h.addArrangedSubview(iv)
        }
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 12)
        l.textColor = dim ? .secondaryLabelColor : .labelColor
        l.lineBreakMode = .byTruncatingTail
        h.addArrangedSubview(l)
        return h
    }

    private func makeHistoryCell(_ title: String, appName: String?, bundleID: String?, number: Int?) -> NSView {
        let h = NSStackView()
        h.orientation = .horizontal
        h.spacing = 4
        h.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)

        // Number indicator (1-9)
        if let number, number <= 9 {
            let numLabel = NSTextField(labelWithString: "\(number)")
            numLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            numLabel.textColor = .tertiaryLabelColor
            numLabel.alignment = .center
            numLabel.setContentHuggingPriority(.required, for: .horizontal)
            numLabel.widthAnchor.constraint(equalToConstant: 12).isActive = true
            h.addArrangedSubview(numLabel)
        } else {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.required, for: .horizontal)
            spacer.widthAnchor.constraint(equalToConstant: 12).isActive = true
            h.addArrangedSubview(spacer)
        }

        // App icon
        if let bundleID, let icon = appIcon(for: bundleID) {
            let iv = NSImageView(image: icon)
            iv.setContentHuggingPriority(.required, for: .horizontal)
            iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
            h.addArrangedSubview(iv)
        }

        // Text
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabelColor
        l.lineBreakMode = .byTruncatingTail
        h.addArrangedSubview(l)

        return h
    }

    // MARK: - App Icon Cache

    private func appIcon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        iconCache[bundleID] = icon
        return icon
    }

    // MARK: - Click

    @objc private func tableClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count else { return }
        activateRow(row)
    }

    // MARK: - Build rows

    private func rebuildRows() {
        guard let ds = dataStore else { rows = []; return }
        var result: [Row] = []
        firstHistoryRow = nil

        let pinned = ds.pinnedSnippets
        if !pinned.isEmpty {
            result.append(.header("Pinned", "pin.fill"))
            for s in pinned { result.append(.snippet(s.title, s.content, 0)) }
            result.append(.separator)
        }

        let folders = ds.rootFolders
        let rootSnippets = ds.rootSnippets
        if !folders.isEmpty || !rootSnippets.isEmpty {
            for f in folders.sorted(by: { $0.order < $1.order }) {
                addFolderRows(f, depth: 0, into: &result)
            }
            for s in rootSnippets.sorted(by: { $0.order < $1.order }) {
                result.append(.snippet(s.title, s.content, 0))
            }
            result.append(.separator)
        }

        let history = ds.history
        let all = Array(history.prefix(ds.maxHistoryCount).enumerated())
        if !all.isEmpty {
            result.append(.header("History", "clock"))
            firstHistoryRow = result.count
            for (i, clip) in all {
                result.append(.historyItem(clip.displayTitle, i, appName: clip.sourceAppName, bundleID: clip.sourceAppBundleID))
            }
        }

        rows = result
    }

    private func addFolderRows(_ folder: SnippetFolder, depth: Int, into result: inout [Row]) {
        let expanded = expandedFolders.contains(folder.id)
        result.append(.folder(folder.title, folder.id, depth, expanded))
        guard expanded else { return }
        for sub in folder.subfolders.sorted(by: { $0.order < $1.order }) {
            addFolderRows(sub, depth: depth + 1, into: &result)
        }
        for s in folder.snippets.sorted(by: { $0.order < $1.order }) {
            result.append(.snippet(s.title, s.content, depth + 1))
        }
    }

    // MARK: - Selection

    private func selectFirstSelectable() {
        for i in 0..<rows.count where rows[i].isSelectable {
            tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            tableView.scrollRowToVisible(i)
            return
        }
    }

    private func selectNext() {
        for i in (tableView.selectedRow + 1)..<rows.count where rows[i].isSelectable {
            tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            tableView.scrollRowToVisible(i)
            return
        }
    }

    private func selectPrevious() {
        let cur = tableView.selectedRow
        guard cur > 0 else { return }
        for i in stride(from: cur - 1, through: 0, by: -1) where rows[i].isSelectable {
            tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            tableView.scrollRowToVisible(i)
            return
        }
    }

    private func activateSelectedRow() {
        let r = tableView.selectedRow
        guard r >= 0 else { return }
        activateRow(r)
    }

    private func activateNthSelectable(_ n: Int) {
        var count = 0
        for i in 0..<rows.count where rows[i].isSelectable {
            count += 1
            if count == n {
                activateRow(i)
                return
            }
        }
    }

    /// Returns the 1-based selectable index for a given row, or nil if not selectable.
    private func selectableIndexForRow(_ row: Int) -> Int? {
        guard rows[row].isSelectable else { return nil }
        var count = 0
        for i in 0...row where rows[i].isSelectable {
            count += 1
        }
        return count
    }

    private func activateRow(_ row: Int) {
        guard row >= 0, row < rows.count else { return }
        switch rows[row] {
        case .snippet(_, let content, _):
            dismiss(); onSelectContent?(content)
        case .historyItem(_, let index, _, _):
            dismiss(); onSelectHistory?(index)
        case .folder(_, let id, _, let expanded):
            if expanded { expandedFolders.remove(id) } else { expandedFolders.insert(id) }
            rebuildRows()
            tableView.reloadData()
            if row < rows.count {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        default: break
        }
    }

    private func toggleSelectedFolder(expand: Bool) {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count,
              case .folder(_, let id, _, let cur) = rows[row],
              expand != cur else { return }
        if expand { expandedFolders.insert(id) } else { expandedFolders.remove(id) }
        rebuildRows()
        tableView.reloadData()
        if row < rows.count {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }
}

private class CompactRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }
}
