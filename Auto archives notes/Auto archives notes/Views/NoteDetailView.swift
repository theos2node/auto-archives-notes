//
//  NoteDetailView.swift
//  Auto archives notes
//

import SwiftUI

struct NoteDetailView: View {
    let note: Note

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if note.isEnhancing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Enhancing…")
                            .font(.system(.headline, design: .rounded))
                        Spacer()
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                } else if let err = note.enhancementError, !err.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enhancement failed")
                            .font(.system(.headline, design: .rounded))
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(note.displayEmoji)
                        .font(.system(size: 34))
                    Text(note.displayTitle)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .textSelection(.enabled)
                    Spacer()
                }

                if !note.tags.isEmpty {
                    Text(note.tags.prefix(3).joined(separator: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Divider()

                Text(note.enhancedText)
                    .font(.system(.body, design: .rounded))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if note.rawText != note.enhancedText {
                    Divider()
                    DisclosureGroup("Original") {
                        Text(note.rawText)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
        }
        .navigationTitle(note.displayTitle)
    }
}
