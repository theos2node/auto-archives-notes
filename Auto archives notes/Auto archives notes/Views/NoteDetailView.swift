//
//  NoteDetailView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct NoteDetailView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBanner

            properties

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(note.displayEmoji)
                    .font(.system(size: 36))

                Text(note.displayTitle)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .textSelection(.enabled)

                Spacer()
            }

            if !note.tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 999, style: .continuous))
                            .foregroundStyle(Color.black.opacity(0.65))
                    }
                    Spacer()
                }
            }

            Divider().opacity(0.7)

            Text(note.enhancedText)
                .font(.system(size: 16, weight: .regular, design: .default))
                .lineSpacing(4)
                .foregroundStyle(Color.black.opacity(0.86))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if note.rawText != note.enhancedText {
                Divider().opacity(0.7)
                DisclosureGroup("Original") {
                    Text(note.rawText)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .lineSpacing(3)
                        .foregroundStyle(NotionStyle.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Properties")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.75))
                Spacer()
            }

            HStack(spacing: 12) {
                propertyPicker("Kind", selection: Binding(
                    get: { note.kind },
                    set: { note.kind = $0 }
                ), all: NoteKind.allCases) { $0.rawValue.capitalized }

                propertyPicker("Status", selection: Binding(
                    get: { note.status },
                    set: { note.status = $0 }
                ), all: NoteStatus.allCases) { $0.rawValue.uppercased() }

                propertyPicker("Priority", selection: Binding(
                    get: { note.priority },
                    set: { note.priority = $0 }
                ), all: NotePriority.allCases) { $0.rawValue.uppercased() }

                Spacer()
            }

            HStack(spacing: 12) {
                propertyField("Project", text: Binding(
                    get: { note.project },
                    set: { note.project = $0 }
                ))

                propertyField("People", text: Binding(
                    get: { note.people.joined(separator: ", ") },
                    set: { note.people = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                ))

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: note.kind) { _, _ in persist() }
        .onChange(of: note.status) { _, _ in persist() }
        .onChange(of: note.priority) { _, _ in persist() }
        .onChange(of: note.project) { _, _ in persist() }
        .onChange(of: note.peopleCSV) { _, _ in persist() }
    }

    private func propertyPicker<T: Hashable>(
        _ label: String,
        selection: Binding<T>,
        all: [T],
        title: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(NotionStyle.textSecondary)
            Picker(label, selection: selection) {
                ForEach(all, id: \.self) { v in
                    Text(title(v)).tag(v)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func propertyField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(NotionStyle.textSecondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if note.isEnhancing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Enhancing…")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let err = note.enhancementError, !err.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enhancement failed")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
                Text(err)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(NotionStyle.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @Environment(\.modelContext) private var modelContext
    private func persist() {
        do { try modelContext.save() } catch { /* non-fatal */ }
    }
}
