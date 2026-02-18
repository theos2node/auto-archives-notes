//
//  AppShellView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

enum AppRoute: Hashable {
    case composer
    case note(UUID)
}

struct AppShellView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    @State private var route: AppRoute? = .composer
    @State private var searchText: String = ""

    private let enhancer: NoteEnhancer = LocalHeuristicEnhancer(effort: .max)

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    route = .composer
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New note")
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }

    private var sidebar: some View {
        List(selection: $route) {
            Section {
                Label("New note", systemImage: "square.and.pencil")
                    .tag(AppRoute.composer)
            }

            Section("Notes") {
                ForEach(filteredNotes) { note in
                    NoteListRow(note: note)
                        .tag(AppRoute.note(note.id))
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
        .listStyle(.sidebar)
        .navigationTitle("Auto Archives")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search notes")
    }

    @ViewBuilder
    private var detail: some View {
        switch route {
        case .none, .some(.composer):
            ComposerView(enhancer: enhancer) {
                // Submit-and-forget: stay on composer. Sidebar list updates immediately.
                route = .composer
            }
            .background(PaperBackground())
        case .some(.note(let id)):
            if let note = notes.first(where: { $0.id == id }) {
                NoteDetailView(note: note)
                    .background(PaperBackground())
            } else {
                ComposerView(enhancer: enhancer) { route = .composer }
                    .background(PaperBackground())
            }
        }
    }

    private var filteredNotes: [Note] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return notes }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(q)
                || note.enhancedText.localizedCaseInsensitiveContains(q)
                || note.rawText.localizedCaseInsensitiveContains(q)
        }
    }

    @Environment(\.modelContext) private var modelContext

    private func delete(_ note: Note) {
        modelContext.delete(note)
        do { try modelContext.save() } catch { /* non-fatal */ }
        if case .note(let id) = route, id == note.id {
            route = .composer
        }
    }
}

