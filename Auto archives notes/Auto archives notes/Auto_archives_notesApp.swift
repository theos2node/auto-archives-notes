//
//  Auto_archives_notesApp.swift
//  Auto archives notes
//
//  Created by Théo on 2/17/26.
//

import SwiftUI
import SwiftData

@main
struct Auto_archives_notesApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Note.self)
        } catch {
            // This should never fail in normal operation; crash early so the issue is obvious during development.
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
