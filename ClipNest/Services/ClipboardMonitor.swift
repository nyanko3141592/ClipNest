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

        let pb = NSPasteboard.general
        let frontmost = NSWorkspace.shared.frontmostApplication
        let appName = frontmost?.localizedName
        let bundleID = frontmost?.bundleIdentifier

        // Check for text first
        if let string = pb.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if dataStore.history.first?.content == string { return }
            dataStore.addHistoryItem(ClipboardItem(content: string, sourceAppName: appName, sourceAppBundleID: bundleID))
            playCopySoundIfEnabled()
            return
        }

        // Check for image
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in imageTypes {
            if let imgData = pb.data(forType: type) {
                guard let bitmapRep = NSBitmapImageRep(data: imgData),
                      let pngData = bitmapRep.representation(using: .png, properties: [:]) else { continue }
                if let fileName = dataStore.saveImageData(pngData) {
                    dataStore.addHistoryItem(ClipboardItem(imageFileName: fileName, sourceAppName: appName, sourceAppBundleID: bundleID))
                    playCopySoundIfEnabled()
                }
                return
            }
        }
    }

    private func playCopySoundIfEnabled() {
        if UserDefaults.standard.bool(forKey: "playCopySound") {
            NSSound(named: "Tink")?.play()
        }
    }
}
