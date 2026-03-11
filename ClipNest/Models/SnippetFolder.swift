import Foundation

struct SnippetFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var snippets: [Snippet]
    var subfolders: [SnippetFolder]
    var order: Int

    var childrenOrNil: [SnippetFolder]? {
        subfolders.isEmpty ? nil : subfolders
    }

    init(title: String, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.snippets = []
        self.subfolders = []
        self.order = order
    }
}

struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var order: Int

    init(title: String, content: String, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.order = order
    }
}
