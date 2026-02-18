//
//  NotesExportDocument.swift
//  Auto archives notes
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct NotesExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NotesExportPayload: Encodable {
    let exportedAt: Date
    let app: String
    let count: Int
    let notes: [NotesExportNote]

    init(notes: [Note]) {
        self.exportedAt = Date()
        self.app = "Auto archives notes"
        self.count = notes.count
        self.notes = notes.map { NotesExportNote(note: $0) }
    }
}

struct NotesExportNote: Encodable {
    let id: String
    let createdAt: Date
    let pinned: Bool
    let isEnhancing: Bool
    let enhancementError: String?

    let title: String
    let emoji: String
    let tags: [String]

    let rawText: String
    let enhancedText: String

    let kind: String
    let status: String
    let priority: String
    let area: String
    let project: String
    let people: [String]

    let dueAt: Date?
    let summary: String
    let actionItems: [String]
    let links: [String]

    init(note: Note) {
        self.id = note.id.uuidString
        self.createdAt = note.createdAt
        self.pinned = note.pinned
        self.isEnhancing = note.isEnhancing
        self.enhancementError = note.enhancementError

        self.title = note.title
        self.emoji = note.emoji
        self.tags = note.tags

        self.rawText = note.rawText
        self.enhancedText = note.enhancedText

        self.kind = note.kind.rawValue
        self.status = note.status.rawValue
        self.priority = note.priority.rawValue
        self.area = note.area.rawValue
        self.project = note.project
        self.people = note.people

        self.dueAt = note.dueAt
        self.summary = note.summary
        self.actionItems = note.actionItems
        self.links = note.links
    }
}
