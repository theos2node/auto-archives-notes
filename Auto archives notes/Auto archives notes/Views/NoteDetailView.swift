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

