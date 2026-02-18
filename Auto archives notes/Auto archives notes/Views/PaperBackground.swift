//
//  PaperBackground.swift
//  Auto archives notes
//

import SwiftUI

struct PaperBackground: View {
    var body: some View {
        ZStack {
            Group {
                #if os(macOS)
                Color(.textBackgroundColor)
                #else
                Color(.systemBackground)
                #endif
            }
            .ignoresSafeArea()

            // Subtle paper tint.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.03),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
