//
//  NoteRowView.swift
//  Auto archives notes
//

import SwiftUI

struct NoteRowView: View {
    let note: Note

    var body: some View {
        HStack(spacing: 10) {
            Text(note.displayEmoji)
                .font(.system(size: 18))
                .frame(width: 28, alignment: .center)
                .accessibilityLabel("Emoji")

            Text(note.displayTitle)
                .font(.system(.body, design: .rounded))
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
