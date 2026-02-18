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

            header

            properties

            aiOutputs

            Divider().opacity(0.7)

            Text(note.enhancedText)
                .font(.system(size: 16, weight: .regular, design: .default))
                .lineSpacing(4)
                .foregroundStyle(NotionStyle.textPrimary)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(note.displayEmoji)
                    .font(.system(size: 36))

                Text(note.displayTitle)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(NotionStyle.textPrimary)
                    .textSelection(.enabled)

                Spacer()
            }

            if !note.tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        NotionChip(text: tag)
                    }
                    Spacer()
                }
            }
        }
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Properties")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.75))

            VStack(spacing: 0) {
                rowDividerless {
                    propertyRow("Kind") {
                        Picker("", selection: Binding(
                            get: { note.kind },
                            set: { note.kind = $0 }
                        )) {
                            ForEach(NoteKind.allCases, id: \.self) { v in
                                Text(v.rawValue.capitalized).tag(v)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                Divider().opacity(0.55)

                rowDividerless {
                    propertyRow("Status") {
                        Picker("", selection: Binding(
                            get: { note.status },
                            set: { note.status = $0 }
                        )) {
                            ForEach(NoteStatus.allCases, id: \.self) { v in
                                Text(v.rawValue.capitalized).tag(v)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                Divider().opacity(0.55)

                rowDividerless {
                    propertyRow("Area") {
                        Picker("", selection: Binding(
                            get: { note.area },
                            set: { note.area = $0 }
                        )) {
                            ForEach(NoteArea.allCases, id: \.self) { v in
                                Text(v.rawValue.capitalized).tag(v)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                if note.kind == .task {
                    Divider().opacity(0.55)

                    rowDividerless {
                        propertyRow("Priority") {
                            Picker("", selection: Binding(
                                get: { note.priority },
                                set: { note.priority = $0 }
                            )) {
                                ForEach(NotePriority.allCases, id: \.self) { v in
                                    Text(v.rawValue.uppercased()).tag(v)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }

                if note.kind == .task {
                    Divider().opacity(0.55)

                    rowDividerless {
                        propertyRow("Due") {
                            HStack(spacing: 10) {
                                Toggle("Has due date", isOn: Binding(
                                    get: { note.dueAt != nil },
                                    set: { has in
                                        note.dueAt = has ? (note.dueAt ?? Date()) : nil
                                    }
                                ))
                                .labelsHidden()

                                if note.dueAt != nil {
                                    DatePicker(
                                        "",
                                        selection: Binding(
                                            get: { note.dueAt ?? Date() },
                                            set: { note.dueAt = $0 }
                                        ),
                                        displayedComponents: [.date]
                                    )
                                    .labelsHidden()
                                } else {
                                    Text("None")
                                        .foregroundStyle(NotionStyle.textSecondary)
                                }

                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                Divider().opacity(0.55)

                rowDividerless {
                    propertyRow("Project") {
                        inlineField("", text: Binding(
                            get: { note.project },
                            set: { note.project = $0 }
                        ))
                    }
                }

                Divider().opacity(0.55)

                rowDividerless {
                    propertyRow("People") {
                        inlineField("Comma-separated", text: Binding(
                            get: { note.people.joined(separator: ", ") },
                            set: { note.people = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                        ))
                    }
                }

                Divider().opacity(0.55)

                rowDividerless {
                    propertyRow("Links") {
                        inlineField("Comma-separated URLs", text: Binding(
                            get: { note.linksCSV },
                            set: { note.linksCSV = $0 }
                        ))
                    }
                }

                Divider().opacity(0.55)

                rowDividerless {
                    propertyRow("Pinned") {
                        Toggle("Pinned", isOn: Binding(
                            get: { note.pinned },
                            set: { note.pinned = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NotionStyle.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NotionStyle.line, lineWidth: 1)
            )
        }
        .onChange(of: note.kind) { _, _ in persist() }
        .onChange(of: note.status) { _, _ in persist() }
        .onChange(of: note.priority) { _, _ in persist() }
        .onChange(of: note.areaRaw) { _, _ in persist() }
        .onChange(of: note.project) { _, _ in persist() }
        .onChange(of: note.peopleCSV) { _, _ in persist() }
        .onChange(of: note.dueAt) { _, _ in persist() }
        .onChange(of: note.linksCSV) { _, _ in persist() }
        .onChange(of: note.pinned) { _, _ in persist() }
    }

    private func propertyRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(NotionStyle.textSecondary)
                .frame(width: 86, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }

    private func rowDividerless<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 2)
    }

    private func inlineField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NotionStyle.line, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var aiOutputs: some View {
        let summary = note.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = note.actionItems

        if summary.isEmpty && items.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 10) {
                if !summary.isEmpty {
                    callout(title: "Summary", systemImage: "sparkles") {
                        Text(summary)
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .lineSpacing(3)
                            .foregroundStyle(NotionStyle.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !items.isEmpty {
                    callout(title: "Action items", systemImage: "checklist") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(items.prefix(8), id: \.self) { item in
                                Text("• \(item)")
                                    .font(.system(size: 15, weight: .regular, design: .default))
                                    .foregroundStyle(NotionStyle.textPrimary)
                                    .textSelection(.enabled)
                            }
                            if items.count > 8 {
                                Text("…and \(items.count - 8) more")
                                    .font(.caption)
                                    .foregroundStyle(NotionStyle.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func callout<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(NotionStyle.textSecondary)
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
            }
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NotionStyle.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(NotionStyle.line, lineWidth: 1)
        )
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
            .background(NotionStyle.fillSubtleHover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .background(NotionStyle.fillSubtleHover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @Environment(\.modelContext) private var modelContext
    private func persist() {
        do { try modelContext.save() } catch { /* non-fatal */ }
    }
}
