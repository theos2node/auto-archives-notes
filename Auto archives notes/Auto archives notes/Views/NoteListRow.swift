//
//  NoteListRow.swift
//  Auto archives notes
//

import SwiftUI

struct NoteListRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 10) {
            Text(note.displayEmoji)
                .font(.system(size: 16))
                .frame(width: 24, alignment: .leading)

            Text(note.displayTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.86))
                .lineLimit(1)
        }
    }
}
