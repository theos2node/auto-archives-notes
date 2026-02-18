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
        private let iso8601 = ISO8601DateFormatter()

        private let stopwords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by",
            "for", "from", "has", "have", "i", "if", "in", "into", "is", "it",
            "me", "my", "not", "of", "on", "or", "our", "so", "that", "the",
            "their", "then", "there", "this", "to", "up", "was", "we", "with", "you", "your"
        ]

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
            let area = normalizeArea(meta.area)
            let project = meta.project.trimmingCharacters(in: .whitespacesAndNewlines)
            let people = normalizePeople(meta.people)
            let dueAt = parseDueAt(meta.dueAtISO, kind: kind)
            let summary = normalizeSummary(meta.summary, correctedText: corrected, title: title)
            let actionItems = normalizeActionItems(meta.actionItems, kind: kind, title: title)
            let links = normalizeLinks(meta.links, correctedText: corrected)

            return NoteEnhancement(
                correctedText: corrected.isEmpty ? trimmed : corrected,
                title: title,
                emoji: emoji,
                tags: tags,
                kind: kind,
                status: status,
                priority: priority,
                area: area,
                project: project,
                people: people,
                dueAt: dueAt,
                summary: summary,
                actionItems: actionItems,
                links: links
            )
        }

        private func metadataPrompt(correctedText: String) -> String {
            iso8601.formatOptions = [.withInternetDateTime]
            let now = iso8601.string(from: Date())
            let tz = TimeZone.current.identifier

            return """
            You are organizing notes into a second-brain system. Do careful internal reasoning.
            Output only the requested fields.

            Context:
            - Current date/time: \(now)
            - Current timezone: \(tz)
            - If the note contains relative dates (today/tomorrow/next week), resolve them to an absolute ISO-8601 date/time using the context above.

            Based on the note text below, generate:
            - title: no more than 5 words (avoid leading articles like "the", "a", "an")
            - emoji: exactly 1 emoji that matches the note
            - tags: exactly 3 short tags, each starting with '#', based on the content (not generic)
            - kind: one of [idea, task, meeting, journal, reference]
            - status: one of [inbox, next, later, done]
            - priority: one of [p1, p2, p3] (if kind is task; otherwise use p3)
            - area: one of [work, personal, health, finance, learning, admin, other]
            - project: a short project name if clearly applicable, otherwise empty string (a project is a concrete outcome; area is ongoing)
            - people: 0-3 names if explicitly mentioned, otherwise []
            - summary: 1 sentence, <= 20 words, concrete and specific
            - actionItems: 0-7 short action items (imperative). If kind is task, ensure at least 1.
            - dueAtISO: deadline datetime in ISO-8601 if a deadline is explicitly present or strongly implied; otherwise empty string
            - links: 0-3 URLs found in the note, otherwise []

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

            let capped = dropLeadingStopwords(words).prefix(5).joined(separator: " ")
            if capped.isEmpty {
                // Very conservative fallback: first 5 words of corrected text.
                let fallbackWords = correctedText
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                    .map(String.init)
                let cappedFallback = dropLeadingStopwords(fallbackWords).prefix(5)
                return cappedFallback.isEmpty ? "Quick Note" : cappedFallback.joined(separator: " ")
            }
            return capped
        }

        private func dropLeadingStopwords(_ words: [String]) -> [String] {
            var i = 0
            while i < words.count {
                let w = words[i]
                    .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    .lowercased()
                if w.isEmpty || stopwords.contains(w) || w.count <= 2 {
                    i += 1
                    continue
                }
                break
            }
            return Array(words.dropFirst(i))
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

        private func normalizeArea(_ s: String) -> NoteArea {
            switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "work": return .work
            case "personal": return .personal
            case "health": return .health
            case "finance": return .finance
            case "learning": return .learning
            case "admin": return .admin
            default: return .other
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

        private func normalizeSummary(_ s: String, correctedText: String, title: String) -> String {
            let t = s
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if !t.isEmpty {
                let words = t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
                return words.prefix(20).joined(separator: " ")
            }

            let first = correctedText
                .split(whereSeparator: { ".!?".contains($0) || $0.isNewline })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { $0.count >= 10 }) ?? title
            let w = first.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
            return w.prefix(20).joined(separator: " ")
        }

        private func normalizeActionItems(_ items: [String], kind: NoteKind, title: String) -> [String] {
            var out: [String] = []
            for s0 in items {
                let s1 = s0
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                if s1.isEmpty { continue }
                if !out.contains(where: { $0.caseInsensitiveCompare(s1) == .orderedSame }) {
                    out.append(s1)
                }
                if out.count == 7 { break }
            }
            if out.isEmpty, kind == .task {
                out = [title.isEmpty ? "Follow up" : title]
            }
            return out
        }

        private func normalizeLinks(_ links: [String], correctedText: String) -> [String] {
            var out: [String] = []
            for l0 in links {
                let l = l0.trimmingCharacters(in: .whitespacesAndNewlines)
                if l.isEmpty { continue }
                if l.hasPrefix("http://") || l.hasPrefix("https://") {
                    if !out.contains(l) { out.append(l) }
                }
                if out.count == 3 { break }
            }

            if out.isEmpty {
                let pattern = #"https?://[^\s\)\]\}>"']+"#
                if let r = try? NSRegularExpression(pattern: pattern) {
                    let ns = correctedText as NSString
                    let matches = r.matches(in: correctedText, range: NSRange(location: 0, length: ns.length))
                    for m in matches {
                        let url = ns.substring(with: m.range)
                        if !out.contains(url) { out.append(url) }
                        if out.count == 3 { break }
                    }
                }
            }
            return out
        }

        private func parseDueAt(_ s: String, kind: NoteKind) -> Date? {
            if kind != .task { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }

            iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso8601.date(from: t) { return d }
            iso8601.formatOptions = [.withInternetDateTime]
            if let d = iso8601.date(from: t) { return d }

            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone.current
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: t)
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
    var area: String
    var project: String
    var people: [String]
    var summary: String
    var actionItems: [String]
    var dueAtISO: String
    var links: [String]
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct AppleModelUnavailableError: Error {
    let reason: SystemLanguageModel.Availability.UnavailableReason
}

#endif
