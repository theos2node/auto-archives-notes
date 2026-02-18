//
//  BestAvailableNoteEnhancer.swift
//  Auto archives notes
//

import Foundation

final class BestAvailableNoteEnhancer: NoteEnhancer, @unchecked Sendable {
    private let fallback: NoteEnhancer

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private let apple = AppleFoundationModelsEnhancer()
    #endif

    init(fallback: NoteEnhancer) {
        self.fallback = fallback
    }

    func enhance(rawText: String) async throws -> NoteEnhancement {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            do {
                return try await apple.enhance(rawText: rawText)
            } catch {
                // If Apple model isn't available or fails, fall back to heuristics.
                return try await fallback.enhance(rawText: rawText)
            }
        }
        #endif

        return try await fallback.enhance(rawText: rawText)
    }
}
