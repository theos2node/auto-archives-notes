//
//  RootView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var selectedNoteID: UUID?

    // Swap this implementation later with Apple's on-device foundation model enhancer.
    private let enhancer: NoteEnhancer = LocalHeuristicEnhancer()

    var body: some View {
        NavigationSplitView {
            NotesDashboardView(selectedNoteID: $selectedNoteID)
        } detail: {
            if let id = selectedNoteID, let note = notes.first(where: { $0.id == id }) {
                NoteDetailView(note: note)
            } else {
                NewNoteView(enhancer: enhancer) { created in
                    // Submit-and-forget: keep the editor open for the next thought.
                    // The new note will appear immediately in the list.
                    selectedNoteID = nil
                }
            }
        }
    }
}
