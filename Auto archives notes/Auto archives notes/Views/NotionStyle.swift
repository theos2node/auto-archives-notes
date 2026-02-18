//
//  NotionStyle.swift
//  Auto archives notes
//

import SwiftUI

enum NotionStyle {
    // Notion-ish neutrals (light mode).
    static let canvas = Color(red: 0.969, green: 0.965, blue: 0.957) // ~ #F7F6F4
    static let page = Color.white
    static let line = Color.black.opacity(0.08)

    static let fillSubtle = Color.black.opacity(0.035)
    static let fillSubtleHover = Color.black.opacity(0.045)
    static let fillChip = Color.black.opacity(0.055)

    static let textPrimary = Color.black.opacity(0.86)
    static let textSecondary = Color.black.opacity(0.55)

    static let pageMaxWidth: CGFloat = 820
}

struct NotionCanvas<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            NotionStyle.canvas.ignoresSafeArea()
            content
        }
    }
}

struct NotionPage<Content: View>: View {
    let topBar: AnyView?
    @ViewBuilder var content: Content

    init(topBar: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.topBar = topBar
        self.content = content()
    }

    var body: some View {
        NotionCanvas {
            VStack(spacing: 0) {
                if let topBar {
                    topBar
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                } else {
                    Spacer().frame(height: 10)
                }

                ScrollView {
                    VStack {
                        content
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

struct NotionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: NotionStyle.pageMaxWidth, alignment: .leading)
        .background(NotionStyle.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(NotionStyle.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

struct NotionPillButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(prominent ? Color.black.opacity(configuration.isPressed ? 0.9 : 0.85) : Color.black.opacity(configuration.isPressed ? 0.065 : 0.045))
            )
            .foregroundStyle(prominent ? Color.white : Color.black.opacity(0.88))
    }
}

struct NotionRowBackground: View {
    let isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isHovered ? NotionStyle.fillSubtleHover : Color.clear)
    }
}

struct NotionChip: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.5))
            }
            Text(text)
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(NotionStyle.fillChip, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .strokeBorder(NotionStyle.line, lineWidth: 1)
        )
        .foregroundStyle(Color.black.opacity(0.68))
    }
}
