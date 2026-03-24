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
    /// Custom SF Symbol name chosen by the user. nil means auto-detect.
    var icon: String?

    init(title: String, content: String, order: Int = 0, isPinned: Bool = false, icon: String? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.order = order
        self.isPinned = isPinned
        self.icon = icon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        order = try container.decode(Int.self, forKey: .order)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
    }

    /// Resolved icon: custom icon if set, otherwise auto-detected from content.
    var resolvedIcon: String {
        if let icon, !icon.isEmpty { return icon }
        return Self.autoDetectIcon(for: content)
    }

    static func autoDetectIcon(for content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Email address
        if trimmed.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil {
            return "envelope"
        }

        // URL / link
        if trimmed.range(of: #"^https?://"#, options: .regularExpression) != nil {
            return "link"
        }

        // Phone number
        if trimmed.range(of: #"^[\+]?[\d\s\-\(\)]{7,}$"#, options: .regularExpression) != nil {
            return "phone"
        }

        // File path
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return "folder"
        }

        // Code patterns
        if trimmed.contains("func ") || trimmed.contains("class ") || trimmed.contains("import ")
            || trimmed.contains("def ") || trimmed.contains("function ")
            || trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "chevron.left.forwardslash.chevron.right"
        }

        // Shell / terminal commands
        if trimmed.hasPrefix("$") || trimmed.hasPrefix("#!") || trimmed.hasPrefix("sudo ")
            || trimmed.hasPrefix("cd ") || trimmed.hasPrefix("git ") || trimmed.hasPrefix("npm ")
            || trimmed.hasPrefix("brew ") {
            return "terminal"
        }

        // Multi-line text
        if trimmed.contains("\n") {
            return "text.alignleft"
        }

        return "doc.text"
    }
}
