//
//  NoteDetailView.swift
//  Auto archives notes
//

import SwiftUI

struct NoteDetailView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBanner

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
}
