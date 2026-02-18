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
                    // After submit: show the newly created note on macOS/iPad;
                    // user can immediately confirm the title/emoji/tags.
                    selectedNoteID = created.id
                }
            }
        }
    }
}

