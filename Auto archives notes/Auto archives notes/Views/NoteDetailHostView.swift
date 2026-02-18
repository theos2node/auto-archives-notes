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
        VStack(spacing: 0) {
            topBar
            if let note = notes.first(where: { $0.id == noteID }) {
                NoteDetailView(note: note)
            } else {
                Text("Note not found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                onGoToMenu?()
            } label: {
                Text("Main menu")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                onNewNote?()
            } label: {
                Text("New note")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: [.command])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.thinMaterial)
    }
}

