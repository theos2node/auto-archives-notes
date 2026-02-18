//
//  MainMenuView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct MainMenuView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var onNewNote: (() -> Void)?
    var onTranscript: (() -> Void)?
    var onChat: (() -> Void)?
    var onOpenNote: ((UUID) -> Void)?

    @State private var view: MenuView = .inbox
    @State private var searchText: String = ""

    var body: some View {
        NotionPage(topBar: AnyView(topBar)) {
            if notes.isEmpty {
                NotionCard { emptyState.padding(26) }
                    .padding(.top, 8)
            } else {
                NotionCard {
                    VStack(spacing: 0) {
                        ForEach(filteredNotes) { note in
                            NotionMenuRow(note: note) {
                                onOpenNote?(note.id)
                            } onDelete: {
                                delete(note)
                            }

                            if note.id != filteredNotes.last?.id {
                                Divider().opacity(0.6)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Notes")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.86))

                Spacer()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                Button {
                    onTranscript?()
                } label: {
                    Image(systemName: "mic")
                }
                .buttonStyle(NotionPillButtonStyle(prominent: false))
                .help("Transcript")

                Button {
                    onChat?()
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .buttonStyle(NotionPillButtonStyle(prominent: false))
                .help("Chat")

                Button {
                    onNewNote?()
                } label: {
                    Text("New note")
                }
                .buttonStyle(NotionPillButtonStyle(prominent: true))
                .keyboardShortcut("n", modifiers: [.command])
            }

            HStack(spacing: 8) {
                ForEach(MenuView.allCases, id: \.self) { v in
                    Button {
                        view = v
                    } label: {
                        Text(v.label)
                    }
                    .buttonStyle(NotionPillButtonStyle(prominent: view == v))
                }
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing here yet.")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("Capture a thought, submit it, forget it.")
                .foregroundStyle(NotionStyle.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @Environment(\.modelContext) private var modelContext

    private func delete(_ note: Note) {
        modelContext.delete(note)
        do { try modelContext.save() } catch { /* non-fatal */ }
    }

    private var filteredNotes: [Note] {
        let base = notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.createdAt > b.createdAt
        }

        let filteredByView: [Note]
        switch view {
        case .inbox:
            filteredByView = base.filter { $0.status == .inbox }
        case .tasks:
            filteredByView = base.filter { $0.kind == .task && $0.status != .done }
        case .ideas:
            filteredByView = base.filter { $0.kind == .idea }
        case .meetings:
            filteredByView = base.filter { $0.kind == .meeting }
        case .done:
            filteredByView = base.filter { $0.status == .done }
        case .all:
            filteredByView = base
        case .pinned:
            filteredByView = base.filter { $0.pinned }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return filteredByView }

        return filteredByView.filter { note in
            note.displayTitle.localizedCaseInsensitiveContains(q)
                || note.enhancedText.localizedCaseInsensitiveContains(q)
                || note.tagsCSV.localizedCaseInsensitiveContains(q)
                || note.project.localizedCaseInsensitiveContains(q)
                || note.peopleCSV.localizedCaseInsensitiveContains(q)
                || note.summary.localizedCaseInsensitiveContains(q)
                || note.actionItemsText.localizedCaseInsensitiveContains(q)
                || note.linksCSV.localizedCaseInsensitiveContains(q)
        }
    }
}

private struct NotionMenuRow: View {
    let note: Note
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            Text(note.displayEmoji)
                .font(.system(size: 18))
                .frame(width: 26, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(note.kind.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)

                    Text(note.area.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)

                    Text(note.status.rawValue.uppercased())
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)

                    if note.kind == .task {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(NotionStyle.textSecondary)
                        Text(note.priority.rawValue.uppercased())
                            .font(.caption)
                            .foregroundStyle(NotionStyle.textSecondary)
                    }

                    if note.kind == .task, let due = note.dueAt {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(NotionStyle.textSecondary)
                        Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(NotionStyle.textSecondary)
                    }
                }

                if note.isEnhancing {
                    Text("Enhancing…")
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)
                } else if let err = note.enhancementError, !err.isEmpty {
                    Text("Needs review")
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.55))
                } else if !note.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note.summary)
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(1)
                } else {
                    HStack(spacing: 8) {
                        if note.pinned {
                            Text("Pinned")
                                .font(.caption)
                                .foregroundStyle(Color.black.opacity(0.55))
                        }
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(NotionStyle.textSecondary)
                        if !note.project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(NotionStyle.textSecondary)
                            Text(note.project)
                                .font(.caption)
                                .foregroundStyle(NotionStyle.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            if note.isEnhancing {
                ProgressView().controlSize(.small)
            }

            Button {
                togglePin()
            } label: {
                Image(systemName: note.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(note.pinned ? 0.55 : 0.35))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)

            if note.kind == .task {
                Button {
                    toggleDone()
                } label: {
                    Image(systemName: note.status == .done ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(note.status == .done ? 0.55 : 0.35))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .opacity(hovered ? 1 : 0)
            }

            Button {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NotionRowBackground(isHovered: hovered))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovered = $0 }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @Environment(\.modelContext) private var modelContext

    private func togglePin() {
        note.pinned.toggle()
        do { try modelContext.save() } catch { /* non-fatal */ }
    }

    private func toggleDone() {
        if note.status == .done {
            note.status = .inbox
        } else {
            note.status = .done
        }
        do { try modelContext.save() } catch { /* non-fatal */ }
    }
}

private enum MenuView: CaseIterable {
    case inbox
    case tasks
    case ideas
    case meetings
    case pinned
    case done
    case all

    var label: String {
        switch self {
        case .inbox: return "Inbox"
        case .tasks: return "Tasks"
        case .ideas: return "Ideas"
        case .meetings: return "Meetings"
        case .pinned: return "Pinned"
        case .done: return "Done"
        case .all: return "All"
        }
    }
}
