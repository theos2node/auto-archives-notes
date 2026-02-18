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
        NotionPage(topBar: AnyView(topBar)) {
            if notes.isEmpty {
                NotionCard { emptyState.padding(26) }
                    .padding(.top, 8)
            } else {
                NotionCard {
                    VStack(spacing: 0) {
                        ForEach(notes) { note in
                            NotionMenuRow(note: note) {
                                onOpenNote?(note.id)
                            } onDelete: {
                                delete(note)
                            }

                            if note.id != notes.last?.id {
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
        HStack(spacing: 10) {
            Text("Notes")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.86))

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
}

private struct NotionMenuRow: View {
    let note: Note
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

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

                if note.isEnhancing {
                    Text("Enhancing…")
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)
                } else if let err = note.enhancementError, !err.isEmpty {
                    Text("Needs review")
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.55))
                } else {
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)
                }
            }

            Spacer()

            if note.isEnhancing {
                ProgressView().controlSize(.small)
            }

            Button {
                onDelete()
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
    }
}
