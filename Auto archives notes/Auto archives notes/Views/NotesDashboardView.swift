//
//  NotesDashboardView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct NotesDashboardView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    @Binding var selectedNoteID: UUID?

    var body: some View {
        List(selection: $selectedNoteID) {
            Section {
                Button {
                    selectedNoteID = nil
                } label: {
                    Label("New note", systemImage: "square.and.pencil")
                }
                .tag(UUID?.none)
            }

            Section("Notes") {
                ForEach(notes) { note in
                    NoteRowView(note: note)
                        .tag(Optional(note.id))
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(note)
                            } label: {
                                Text("Delete")
                            }
                        }
                }
            }
        }
        .navigationTitle("Notes")
    }

    @Environment(\.modelContext) private var modelContext

    private func delete(_ note: Note) {
        modelContext.delete(note)
        do { try modelContext.save() } catch { /* non-fatal */ }
        if selectedNoteID == note.id { selectedNoteID = nil }
    }
}

