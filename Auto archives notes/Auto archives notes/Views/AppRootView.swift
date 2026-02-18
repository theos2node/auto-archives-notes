//
//  AppRootView.swift
//  Auto archives notes
//

import SwiftUI

enum AppScreen: Hashable {
    case composer
    case menu
    case detail(UUID)
}

struct AppRootView: View {
    @State private var screen: AppScreen = .composer

    private let enhancer: NoteEnhancer = BestAvailableNoteEnhancer(
        fallback: LocalHeuristicEnhancer(effort: .max)
    )

    var body: some View {
        switch screen {
        case .composer:
            ComposerView(
                enhancer: enhancer,
                onGoToMenu: { screen = .menu },
                onSubmitted: { screen = .menu }
            )
            .background(PaperBackground())

        case .menu:
            MainMenuView(
                onNewNote: { screen = .composer },
                onOpenNote: { id in screen = .detail(id) }
            )

        case .detail(let id):
            NoteDetailHostView(
                noteID: id,
                onGoToMenu: { screen = .menu },
                onNewNote: { screen = .composer }
            )
            .background(PaperBackground())
        }
    }
}
