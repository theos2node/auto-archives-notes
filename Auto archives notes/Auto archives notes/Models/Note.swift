//
//  Note.swift
//  Auto archives notes
//
//  Core persisted note model. Keep it simple and cross-platform.
//

import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    // Capture
    var rawText: String

    // Enriched by enhancer (on-device model later).
    var title: String
    var emoji: String
    var tagsCSV: String
    var enhancedText: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawText: String,
        title: String,
        emoji: String,
        tags: [String],
        enhancedText: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.title = title
        self.emoji = emoji
        self.tagsCSV = tags.joined(separator: ",")
        self.enhancedText = enhancedText
    }

    var tags: [String] {
        get {
            tagsCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsCSV = newValue.joined(separator: ",")
        }
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled" : t
    }

    var displayEmoji: String {
        let e = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? "📝" : e
    }
}

