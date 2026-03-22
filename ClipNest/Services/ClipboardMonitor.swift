import AppKit

final class ClipboardMonitor {
    private let dataStore: DataStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var isPaused = false

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        lastChangeCount = NSPasteboard.general.changeCount
        isPaused = false
    }

    private func check() {
        guard !isPaused else { return }
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let string = NSPasteboard.general.string(forType: .string),
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if dataStore.history.first?.content == string { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let appName = frontmost?.localizedName
        let bundleID = frontmost?.bundleIdentifier
        dataStore.addHistoryItem(ClipboardItem(content: string, sourceAppName: appName, sourceAppBundleID: bundleID))

        if UserDefaults.standard.bool(forKey: "playCopySound") {
            NSSound(named: "Tink")?.play()
        }
    }
}
