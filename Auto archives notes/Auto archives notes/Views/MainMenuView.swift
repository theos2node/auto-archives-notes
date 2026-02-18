//
//  MainMenuView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct MainMenuView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var onNewNote: (() -> Void)?
    var onOpenNote: ((UUID) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if notes.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(PaperBackground())
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Notes")
                .font(.system(.title2, design: .rounded).weight(.semibold))

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

    private var list: some View {
        List {
            ForEach(notes) { note in
                Button {
                    onOpenNote?(note.id)
                } label: {
                    NoteListRow(note: note)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        delete(note)
                    } label: {
                        Text("Delete")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing here yet.")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("Capture a thought, submit it, forget it.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    @Environment(\.modelContext) private var modelContext

    private func delete(_ note: Note) {
        modelContext.delete(note)
        do { try modelContext.save() } catch { /* non-fatal */ }
    }
}

