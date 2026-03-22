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
    var isPinned: Bool

    init(title: String, content: String, order: Int = 0, isPinned: Bool = false) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.order = order
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        order = try container.decode(Int.self, forKey: .order)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}
