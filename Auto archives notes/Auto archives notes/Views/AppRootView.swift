//
//  AppRootView.swift
//  Auto archives notes
//

import SwiftUI

enum AppScreen: Hashable {
    case composer(transcript: Bool)
    case menu
    case chat
    case detail(UUID)
}

struct AppRootView: View {
    @State private var screen: AppScreen = .composer(transcript: false)

    private let enhancer: NoteEnhancer = BestAvailableNoteEnhancer(
        fallback: LocalHeuristicEnhancer(effort: .max)
    )

    var body: some View {
        ZStack {
            switch screen {
            case .composer(let transcript):
                ComposerView(
                    enhancer: enhancer,
                    onGoToMenu: { screen = .menu },
                    onSubmitted: { screen = .menu },
                    startRecordingOnAppear: transcript
                )
                .transition(.opacity)

            case .menu:
                MainMenuView(
                    onNewNote: { screen = .composer(transcript: false) },
                    onTranscript: { screen = .composer(transcript: true) },
                    onChat: { screen = .chat },
                    onOpenNote: { id in screen = .detail(id) }
                )
                .transition(.opacity)

            case .chat:
                ChatView(
                    onGoToMenu: { screen = .menu },
                    onOpenNote: { id in screen = .detail(id) },
                    onNewNote: { screen = .composer(transcript: false) }
                )
                .transition(.opacity)

            case .detail(let id):
                NoteDetailHostView(
                    noteID: id,
                    onGoToMenu: { screen = .menu },
                    onNewNote: { screen = .composer(transcript: false) }
                )
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: screen)
        .preferredColorScheme(.light)
    }
}
