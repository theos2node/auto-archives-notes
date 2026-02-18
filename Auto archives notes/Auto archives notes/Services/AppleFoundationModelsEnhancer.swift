//
//  AppleFoundationModelsEnhancer.swift
//  Auto archives notes
//
//  Uses Apple's on-device SystemLanguageModel via FoundationModels (macOS/iOS/visionOS 26+).
//  Falls back to throwing if the system model is unavailable; callers can decide to fall back to heuristics.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
final class AppleFoundationModelsEnhancer: NoteEnhancer, @unchecked Sendable {
    actor Runner {
        private var session: LanguageModelSession?

        private func getOrCreateSession() -> LanguageModelSession {
            if let session { return session }

            let model = SystemLanguageModel(
                useCase: .general,
                guardrails: .permissiveContentTransformations
            )

            let s = LanguageModelSession(model: model, tools: []) {
                """
                You are an expert writing and information organizer.
                Your job is to improve a user's note without changing its meaning.
                Be precise, keep formatting and line breaks when they carry meaning.
                """
            }

            #if compiler(>=5.3) && $NonescapableTypes
            s.prewarm()
            #endif

            session = s
            return s
        }

        private func ensureAvailable(_ model: SystemLanguageModel) throws {
            switch model.availability {
            case .available:
                return
            case .unavailable(let reason):
                throw AppleModelUnavailableError(reason: reason)
            }
        }

        func enhance(rawText: String) async throws -> NoteEnhancement {
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw NoteEnhancerError.emptyInput }

            // Check system availability before we start any work.
            let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
            try ensureAvailable(model)

            let s = getOrCreateSession()

            var opts = GenerationOptions()
            opts.sampling = .greedy
            opts.temperature = nil
            opts.maximumResponseTokens = 900

            // Pass 1: rewrite/correct the note.
            let correctedPrompt = """
            Rewrite the note below for clarity and correctness.
            Requirements:
            - Preserve meaning and intent.
            - Fix grammar, spelling, punctuation, casing.
            - Keep paragraphs and bullet-like lines.
            - Do not add new facts.
            - Output ONLY the corrected note text.

            NOTE:
            \(trimmed)
            """

            let corrected = try await s.respond(to: correctedPrompt, options: opts).content
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Pass 2: generate compact metadata (title, emoji, tags).
            let taggingModel = SystemLanguageModel(useCase: .contentTagging, guardrails: .permissiveContentTransformations)
            try ensureAvailable(taggingModel)
            let taggingSession = LanguageModelSession(model: taggingModel, tools: []) {
                """
                You generate accurate, structured classifications and metadata for notes.
                Be concrete. Prefer specific tags over generic ones.
                """
            }

            opts.maximumResponseTokens = 500
            let meta = try await taggingSession.respond(
                to: metadataPrompt(correctedText: corrected),
                generating: NoteMetadata.self,
                options: opts
            ).content

            let title = normalizeTitle(meta.title, correctedText: corrected)
            let emoji = normalizeEmoji(meta.emoji)
            let tags = await normalizeTags(meta.tags, correctedText: corrected)
            let kind = normalizeKind(meta.kind)
            let status = normalizeStatus(meta.status, kind: kind)
            let priority = normalizePriority(meta.priority, kind: kind)
            let project = meta.project.trimmingCharacters(in: .whitespacesAndNewlines)
            let people = normalizePeople(meta.people)

            return NoteEnhancement(
                correctedText: corrected.isEmpty ? trimmed : corrected,
                title: title,
                emoji: emoji,
                tags: tags,
                kind: kind,
                status: status,
                priority: priority,
                project: project,
                people: people
            )
        }

        private func metadataPrompt(correctedText: String) -> String {
            """
            Based on the note text below, generate:
            - title: no more than 5 words
            - emoji: exactly 1 emoji that matches the note
            - tags: exactly 3 short tags, each starting with '#', based on the content (not generic)
            - kind: one of [idea, task, meeting, journal, reference]
            - status: one of [inbox, next, later, done]
            - priority: one of [p1, p2, p3] (if kind is task; otherwise use p3)
            - project: a short project name if clearly applicable, otherwise empty string
            - people: 0-3 names if explicitly mentioned, otherwise []

            NOTE:
            \(correctedText)
            """
        }

        private func normalizeTitle(_ s: String, correctedText: String) -> String {
            let compact = s
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

            let words = compact
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map(String.init)

            let capped = words.prefix(5).joined(separator: " ")
            if capped.isEmpty {
                // Very conservative fallback: first 5 words of corrected text.
                let fallbackWords = correctedText
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                    .map(String.init)
                    .prefix(5)
                return fallbackWords.isEmpty ? "Quick Note" : fallbackWords.joined(separator: " ")
            }
            return capped
        }

        private func normalizeEmoji(_ s: String) -> String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "📝" }
            // Keep first scalar cluster; don't try to be perfect about emoji detection.
            return String(trimmed.prefix(2))
        }

        private func normalizeKind(_ s: String) -> NoteKind {
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "task": return .task
            case "meeting": return .meeting
            case "journal": return .journal
            case "reference": return .reference
            default: return .idea
            }
        }

        private func normalizeStatus(_ s: String, kind: NoteKind) -> NoteStatus {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch v {
            case "done": return .done
            case "later": return .later
            case "next": return .next
            case "inbox": return .inbox
            default:
                // Tasks default to next; others to inbox.
                return kind == .task ? .next : .inbox
            }
        }

        private func normalizePriority(_ s: String, kind: NoteKind) -> NotePriority {
            if kind != .task { return .p3 }
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "p1": return .p1
            case "p2": return .p2
            default: return .p3
            }
        }

        private func normalizePeople(_ people: [String]) -> [String] {
            var out: [String] = []
            for p in people {
                let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                if !out.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                    out.append(t)
                }
                if out.count == 3 { break }
            }
            return out
        }

        private func normalizeTags(_ tags: [String], correctedText: String) async -> [String] {
            var out: [String] = []
            for t0 in tags {
                let t1 = t0.trimmingCharacters(in: .whitespacesAndNewlines)
                if t1.isEmpty { continue }
                let t2 = t1.hasPrefix("#") ? t1 : "#\(t1)"
                let t = t2.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                if t.count < 2 { continue }
                if !out.contains(t.lowercased()) {
                    out.append(t)
                }
                if out.count == 3 { break }
            }

            if out.count < 3 {
                // Fallback: use heuristic keywords from the corrected text.
                let fallback = LocalHeuristicEnhancer(effort: .fast)
                let f = (try? await fallback.enhance(rawText: correctedText))?.tags ?? []
                for t in f {
                    let t2 = t.hasPrefix("#") ? t : "#\(t)"
                    if !out.contains(t2.lowercased()) { out.append(t2) }
                    if out.count == 3 { break }
                }
            }

            while out.count < 3 { out.append("#note") }
            return Array(out.prefix(3))
        }
    }

    private let runner = Runner()

    func enhance(rawText: String) async throws -> NoteEnhancement {
        try await runner.enhance(rawText: rawText)
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
struct NoteMetadata {
    var title: String
    var emoji: String
    var tags: [String]
    var kind: String
    var status: String
    var priority: String
    var project: String
    var people: [String]
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct AppleModelUnavailableError: Error {
    let reason: SystemLanguageModel.Availability.UnavailableReason
}

#endif
