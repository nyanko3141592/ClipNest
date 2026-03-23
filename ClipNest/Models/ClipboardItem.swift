import Foundation

struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    let content: String
    let timestamp: Date
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let imageFileName: String?

    var isImage: Bool { imageFileName != nil }

    var displayTitle: String {
        if isImage { return "[Image]" }
        let trimmed = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if trimmed.count > 15 {
            return String(trimmed.prefix(15)) + "..."
        }
        return trimmed
    }

    init(content: String, sourceAppName: String? = nil, sourceAppBundleID: String? = nil) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.imageFileName = nil
    }

    init(imageFileName: String, sourceAppName: String? = nil, sourceAppBundleID: String? = nil) {
        self.id = UUID()
        self.content = ""
        self.timestamp = Date()
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.imageFileName = imageFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourceAppBundleID = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleID)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
    }
}
