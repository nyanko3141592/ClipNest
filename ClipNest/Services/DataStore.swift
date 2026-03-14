import Foundation

struct SnippetData: Codable {
    var folders: [SnippetFolder]
    var snippets: [Snippet]
}

enum ImportMode {
    case merge
    case replace
}

final class DataStore: ObservableObject {
    @Published var history: [ClipboardItem] = []
    @Published var rootFolders: [SnippetFolder] = []
    @Published var rootSnippets: [Snippet] = []

    var maxHistoryCount: Int {
        let val = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        return val > 0 ? val : 30
    }

    private let historyURL: URL
    private let snippetsURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClipNest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        historyURL = dir.appendingPathComponent("history.json")
        snippetsURL = dir.appendingPathComponent("snippets.json")
        load()
    }

    // MARK: - History

    func addHistoryItem(_ item: ClipboardItem) {
        DispatchQueue.main.async { [self] in
            history.removeAll { $0.content == item.content }
            history.insert(item, at: 0)
            if history.count > maxHistoryCount {
                history = Array(history.prefix(maxHistoryCount))
            }
            save(history, to: historyURL)
        }
    }

    func clearHistory() {
        history.removeAll()
        save(history, to: historyURL)
    }

    // MARK: - Folders

    func addFolder(title: String, parentID: UUID? = nil) {
        let folder = SnippetFolder(title: title, order: rootFolders.count)
        if let parentID {
            mutateFolder(id: parentID) { parent in
                var f = folder
                f.order = parent.subfolders.count
                parent.subfolders.append(f)
            }
        } else {
            rootFolders.append(folder)
        }
        saveSnippets()
    }

    func deleteFolder(id: UUID) {
        removeFolder(from: &rootFolders, id: id)
        saveSnippets()
    }

    func renameFolder(id: UUID, title: String) {
        mutateFolder(id: id) { $0.title = title }
        saveSnippets()
    }

    // MARK: - Snippets

    @discardableResult
    func addSnippet(title: String, content: String, folderID: UUID? = nil) -> UUID {
        let snippet = Snippet(title: title, content: content)
        if let folderID {
            mutateFolder(id: folderID) { folder in
                var s = snippet
                s.order = folder.snippets.count
                folder.snippets.append(s)
            }
        } else {
            var s = snippet
            s.order = rootSnippets.count
            rootSnippets.append(s)
        }
        saveSnippets()
        return snippet.id
    }

    func updateSnippet(id: UUID, title: String, content: String) {
        if let i = rootSnippets.firstIndex(where: { $0.id == id }) {
            rootSnippets[i].title = title
            rootSnippets[i].content = content
        } else {
            mutateSnippet(in: &rootFolders, id: id) { snippet in
                snippet.title = title
                snippet.content = content
            }
        }
        saveSnippets()
    }

    func deleteSnippet(id: UUID, fromFolder folderID: UUID? = nil) {
        if let folderID {
            mutateFolder(id: folderID) { folder in
                folder.snippets.removeAll { $0.id == id }
            }
        } else {
            rootSnippets.removeAll { $0.id == id }
        }
        saveSnippets()
    }

    func renameSnippet(id: UUID, title: String) {
        if let i = rootSnippets.firstIndex(where: { $0.id == id }) {
            rootSnippets[i].title = title
        } else {
            mutateSnippet(in: &rootFolders, id: id) { $0.title = title }
        }
        saveSnippets()
    }

    // MARK: - Find

    func findFolder(id: UUID?) -> SnippetFolder? {
        guard let id else { return nil }
        return Self.findFolder(in: rootFolders, id: id)
    }

    func findSnippet(id: UUID?) -> Snippet? {
        guard let id else { return nil }
        if let s = rootSnippets.first(where: { $0.id == id }) { return s }
        return Self.findSnippet(in: rootFolders, id: id)
    }

    /// Returns the parent folder ID, or nil if the snippet is at root level.
    func findParentFolderID(ofSnippet snippetID: UUID) -> UUID? {
        Self.findParentFolderID(in: rootFolders, snippetID: snippetID)
    }

    func isRootSnippet(id: UUID) -> Bool {
        rootSnippets.contains { $0.id == id }
    }

    // MARK: - Import / Export

    func exportSnippetsData() -> Data? {
        let data = SnippetData(folders: rootFolders, snippets: rootSnippets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(data)
    }

    func importSnippets(from url: URL, mode: ImportMode) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let imported = try decoder.decode(SnippetData.self, from: data)

        switch mode {
        case .replace:
            rootFolders = imported.folders
            rootSnippets = imported.snippets
        case .merge:
            let existingFolderIDs = Set(allFolderIDs(in: rootFolders))
            let existingSnippetIDs = Set(allSnippetIDs(in: rootFolders) + rootSnippets.map(\.id))
            for folder in imported.folders where !existingFolderIDs.contains(folder.id) {
                var f = folder
                f.order = rootFolders.count
                rootFolders.append(f)
            }
            for snippet in imported.snippets where !existingSnippetIDs.contains(snippet.id) {
                var s = snippet
                s.order = rootSnippets.count
                rootSnippets.append(s)
            }
        }
        saveSnippets()
    }

    private func allFolderIDs(in folders: [SnippetFolder]) -> [UUID] {
        folders.flatMap { [$0.id] + allFolderIDs(in: $0.subfolders) }
    }

    private func allSnippetIDs(in folders: [SnippetFolder]) -> [UUID] {
        folders.flatMap { $0.snippets.map(\.id) + allSnippetIDs(in: $0.subfolders) }
    }

    // MARK: - Private

    func saveSnippets() {
        let data = SnippetData(folders: rootFolders, snippets: rootSnippets)
        save(data, to: snippetsURL)
    }

    private func mutateFolder(id: UUID, mutation: (inout SnippetFolder) -> Void) {
        Self.mutateFolder(in: &rootFolders, id: id, mutation: mutation)
    }

    private static func mutateFolder(in folders: inout [SnippetFolder], id: UUID, mutation: (inout SnippetFolder) -> Void) {
        for i in folders.indices {
            if folders[i].id == id {
                mutation(&folders[i])
                return
            }
            mutateFolder(in: &folders[i].subfolders, id: id, mutation: mutation)
        }
    }

    private func mutateSnippet(in folders: inout [SnippetFolder], id: UUID, mutation: (inout Snippet) -> Void) {
        for i in folders.indices {
            for j in folders[i].snippets.indices {
                if folders[i].snippets[j].id == id {
                    mutation(&folders[i].snippets[j])
                    return
                }
            }
            mutateSnippet(in: &folders[i].subfolders, id: id, mutation: mutation)
        }
    }

    private func removeFolder(from folders: inout [SnippetFolder], id: UUID) {
        folders.removeAll { $0.id == id }
        for i in folders.indices {
            removeFolder(from: &folders[i].subfolders, id: id)
        }
    }

    private static func findFolder(in folders: [SnippetFolder], id: UUID) -> SnippetFolder? {
        for folder in folders {
            if folder.id == id { return folder }
            if let found = findFolder(in: folder.subfolders, id: id) { return found }
        }
        return nil
    }

    private static func findSnippet(in folders: [SnippetFolder], id: UUID) -> Snippet? {
        for folder in folders {
            if let snippet = folder.snippets.first(where: { $0.id == id }) { return snippet }
            if let found = findSnippet(in: folder.subfolders, id: id) { return found }
        }
        return nil
    }

    private static func findParentFolderID(in folders: [SnippetFolder], snippetID: UUID) -> UUID? {
        for folder in folders {
            if folder.snippets.contains(where: { $0.id == snippetID }) { return folder.id }
            if let found = findParentFolderID(in: folder.subfolders, snippetID: snippetID) { return found }
        }
        return nil
    }

    private func save<T: Encodable>(_ data: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let json = try? encoder.encode(data) {
            try? json.write(to: url)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: historyURL),
           let items = try? decoder.decode([ClipboardItem].self, from: data) {
            history = items
        }
        if let data = try? Data(contentsOf: snippetsURL) {
            // Try new format first, fall back to legacy [SnippetFolder]
            if let snippetData = try? decoder.decode(SnippetData.self, from: data) {
                rootFolders = snippetData.folders
                rootSnippets = snippetData.snippets
            } else if let folders = try? decoder.decode([SnippetFolder].self, from: data) {
                rootFolders = folders
            }
        }
    }
}
