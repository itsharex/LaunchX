import AppKit
import Foundation

struct SearchResult: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let icon: NSImage
    let isDirectory: Bool

    init(id: UUID = UUID(), name: String, path: String, icon: NSImage, isDirectory: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.icon = icon
        self.isDirectory = isDirectory
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
