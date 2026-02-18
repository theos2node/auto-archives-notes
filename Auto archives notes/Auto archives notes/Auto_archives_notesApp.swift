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
        let fm = FileManager.default
        let schema = Schema([Note.self])

        // Use an explicit store location so we can recover gracefully if the schema changes during development.
        let storeURL: URL = {
            let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
            let dir = base.appendingPathComponent("AutoArchivesNotes", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("swiftdata.sqlite")
        }()

        func makeContainer(inMemory: Bool) throws -> ModelContainer {
            if inMemory {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: config)
            } else {
                let config = ModelConfiguration("AutoArchivesNotes", schema: schema, url: storeURL)
                return try ModelContainer(for: schema, configurations: config)
            }
        }

        do {
            return try makeContainer(inMemory: false)
        } catch {
            // Dev-time recovery: wipe the local store and retry. If it still fails, fall back to in-memory.
            let paths = [
                storeURL.path,
                storeURL.path + "-shm",
                storeURL.path + "-wal",
            ]
            for p in paths {
                try? fm.removeItem(atPath: p)
            }
            do {
                return try makeContainer(inMemory: false)
            } catch {
                return (try? makeContainer(inMemory: true)) ?? {
                    fatalError("Failed to create SwiftData container (persistent and in-memory): \(error)")
                }()
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
