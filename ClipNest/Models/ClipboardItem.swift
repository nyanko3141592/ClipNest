import Foundation

struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    let content: String
    let timestamp: Date

    var displayTitle: String {
        let trimmed = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if trimmed.count > 60 {
            return String(trimmed.prefix(60)) + "..."
        }
        return trimmed
    }

    init(content: String) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
    }
}
