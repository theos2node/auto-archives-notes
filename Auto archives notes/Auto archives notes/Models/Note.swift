//
//  Note.swift
//  Auto archives notes
//
//  Core persisted note model. Keep it simple and cross-platform.
//

import Foundation
import SwiftData

enum NoteKind: String, CaseIterable, Sendable {
    case idea
    case task
    case meeting
    case journal
    case reference
}

enum NoteStatus: String, CaseIterable, Sendable {
    case inbox
    case next
    case later
    case done
}

enum NotePriority: String, CaseIterable, Sendable {
    case p1
    case p2
    case p3
}

enum NoteArea: String, CaseIterable, Sendable {
    case work
    case personal
    case health
    case finance
    case learning
    case admin
    case other
}

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var isEnhancing: Bool
    var enhancementError: String?
    var pinned: Bool

    // Capture
    var rawText: String

    // Enriched by enhancer (on-device model later).
    var title: String
    var emoji: String
    var tagsCSV: String
    var enhancedText: String

    // Classification (Notion-like properties).
    var kindRaw: String
    var statusRaw: String
    var priorityRaw: String
    var areaRaw: String
    var project: String
    var peopleCSV: String

    // Structured extraction.
    var dueAt: Date?
    var summary: String
    var actionItemsText: String
    var linksCSV: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isEnhancing: Bool = false,
        enhancementError: String? = nil,
        pinned: Bool = false,
        rawText: String,
        title: String,
        emoji: String,
        tags: [String],
        enhancedText: String,
        kind: NoteKind = .idea,
        status: NoteStatus = .inbox,
        priority: NotePriority = .p3,
        area: NoteArea = .other,
        project: String = "",
        people: [String] = [],
        dueAt: Date? = nil,
        summary: String = "",
        actionItems: [String] = [],
        links: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.isEnhancing = isEnhancing
        self.enhancementError = enhancementError
        self.pinned = pinned
        self.rawText = rawText
        self.title = title
        self.emoji = emoji
        self.tagsCSV = tags.joined(separator: ",")
        self.enhancedText = enhancedText
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.areaRaw = area.rawValue
        self.project = project
        self.peopleCSV = people.joined(separator: ",")
        self.dueAt = dueAt
        self.summary = summary
        self.actionItemsText = actionItems.joined(separator: "\n")
        self.linksCSV = links.joined(separator: ",")
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
        if isEnhancing {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let fallback = fallbackTitleFromText(rawText)
            return fallback.isEmpty ? "Enhancing…" : fallback
        }
        if enhancementError != nil { return displayTitleOr("Needs review") }
        return displayTitleOr("Untitled")
    }

    private func displayTitleOr(_ fallback: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }

    private func fallbackTitleFromText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let cleaned = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let words = cleaned.split(separator: " ")
        let prefix = words.prefix(5)
        return prefix.joined(separator: " ")
    }

    var displayEmoji: String {
        if isEnhancing {
            let e = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? "⏳" : e
        }
        if enhancementError != nil { return "⚠️" }
        let e = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? "📝" : e
    }

    var kind: NoteKind {
        get { NoteKind(rawValue: kindRaw) ?? .idea }
        set { kindRaw = newValue.rawValue }
    }

    var status: NoteStatus {
        get { NoteStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    var priority: NotePriority {
        get { NotePriority(rawValue: priorityRaw) ?? .p3 }
        set { priorityRaw = newValue.rawValue }
    }

    var area: NoteArea {
        get { NoteArea(rawValue: areaRaw) ?? .other }
        set { areaRaw = newValue.rawValue }
    }

    var people: [String] {
        get {
            peopleCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            peopleCSV = newValue.joined(separator: ",")
        }
    }

    var actionItems: [String] {
        get {
            actionItemsText
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            actionItemsText = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    var links: [String] {
        get {
            linksCSV
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            linksCSV = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }
}
