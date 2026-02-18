//
//  MainMenuView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MainMenuView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var onNewNote: (() -> Void)?
    var onTranscript: (() -> Void)?
    var onOpenNote: ((UUID) -> Void)?

    @State private var view: MenuView = .inbox
    @State private var searchText: String = ""
    @State private var isExporting = false
    @State private var exportDocument = NotesExportDocument()
    @State private var exportError: String?

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
                                Divider().opacity(0.55)
                                    .padding(.leading, 54)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultExportFilename()
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { isPresented in
                if !isPresented { exportError = nil }
            }
        ), actions: {
            Button("OK", role: .cancel) { exportError = nil }
        }, message: {
            Text(exportError ?? "")
        })
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Notes")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(NotionStyle.textPrimary)

                Spacer()

                searchField

                Button {
                    onTranscript?()
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(NotionPillButtonStyle(prominent: false))
                .help("Transcript")

                Button {
                    let data = makeExportData(notes: notes)
                    if data.isEmpty {
                        exportError = "Unable to create export data."
                        return
                    }
                    exportDocument = NotesExportDocument(data: data)
                    isExporting = true
                } label: {
                    Text("Export")
                }
                .buttonStyle(NotionPillButtonStyle(prominent: false))
                .help("Export notes as JSON")

                Button {
                    onNewNote?()
                } label: {
                    Text("New note")
                }
                .buttonStyle(NotionPillButtonStyle(prominent: true))
                .keyboardShortcut("n", modifiers: [.command])
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MenuView.allCases, id: \.self) { v in
                        Button {
                            view = v
                        } label: {
                            Text(v.label)
                        }
                        .buttonStyle(NotionPillButtonStyle(prominent: view == v))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NotionStyle.textSecondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NotionStyle.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NotionStyle.line, lineWidth: 1)
        )
        .frame(width: 260)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing here yet.")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(NotionStyle.textPrimary)
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

    private func makeExportData(notes: [Note]) -> Data {
        let payload = NotesExportPayload(notes: notes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(payload)) ?? Data()
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "auto-archives-notes-\(formatter.string(from: Date()))"
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
                    .foregroundStyle(NotionStyle.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    NotionChip(text: note.kind.rawValue.capitalized)
                    NotionChip(text: note.status.rawValue.capitalized)
                    NotionChip(text: note.area.rawValue.capitalized)
                    if note.kind == .task {
                        NotionChip(text: note.priority.rawValue.uppercased())
                    }
                    if note.kind == .task, let due = note.dueAt {
                        NotionChip(text: due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                }

                Text(snippet)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(NotionStyle.textSecondary)
                    .lineLimit(2)
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

    private var snippet: String {
        if note.isEnhancing { return "Running on-device models…" }
        if let err = note.enhancementError, !err.isEmpty { return "Needs review" }
        let s = note.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { return compactLine(s) }
        let t = note.enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return compactLine(t) }
        return note.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func compactLine(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if t.count <= 140 { return t }
        return String(t.prefix(140)) + "…"
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
