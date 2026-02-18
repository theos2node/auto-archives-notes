//
//  NoteDetailHostView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct NoteDetailHostView: View {
    let noteID: UUID
    var onGoToMenu: (() -> Void)?
    var onNewNote: (() -> Void)?

    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var body: some View {
        NotionPage(topBar: AnyView(topBar)) {
            NotionCard {
                if let note = notes.first(where: { $0.id == noteID }) {
                    NoteDetailView(note: note)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                } else {
                    Text("Note not found.")
                        .foregroundStyle(NotionStyle.textSecondary)
                        .padding(26)
                }
            }
            .padding(.top, 8)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                onGoToMenu?()
            } label: {
                Text("Main menu")
            }
            .buttonStyle(NotionPillButtonStyle(prominent: false))

            Spacer()

            Button {
                onNewNote?()
            } label: {
                Text("New note")
            }
            .buttonStyle(NotionPillButtonStyle(prominent: true))
            .keyboardShortcut("n", modifiers: [.command])
        }
    }
}
