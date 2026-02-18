//
//  NoteListRow.swift
//  Auto archives notes
//

import SwiftUI

struct NoteListRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.quaternary)
                Text(note.displayEmoji)
                    .font(.system(size: 14))
            }
            .frame(width: 24, height: 24)

            Text(note.displayTitle)
                .font(.system(.body, design: .rounded))
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

