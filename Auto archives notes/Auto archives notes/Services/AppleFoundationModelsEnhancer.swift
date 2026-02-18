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
        private let iso8601 = ISO8601DateFormatter()

        private let stopwords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by",
            "for", "from", "has", "have", "i", "if", "in", "into", "is", "it",
            "me", "my", "not", "of", "on", "or", "our", "so", "that", "the",
            "their", "then", "there", "this", "to", "up", "was", "we", "with", "you", "your"
        ]

        private func makeGeneralSession() -> LanguageModelSession {
            // Fresh session per enhancement run to avoid cross-note context bleed.
            let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
            let s = LanguageModelSession(model: model, tools: []) {
                """
                You are an expert writing and information organizer.
                Your job is to improve a user's note without changing its meaning.
                Be precise, keep formatting and line breaks when they carry meaning.
                """
            }
            return s
        }

        private func makeTaggingSession() -> LanguageModelSession {
            // Fresh session per enhancement run to avoid cross-note context bleed.
            let model = SystemLanguageModel(useCase: .contentTagging, guardrails: .permissiveContentTransformations)
            let s = LanguageModelSession(model: model, tools: []) {
                """
                You are a careful classifier for a personal notes database.
                Follow constraints exactly. Output only what is requested.
                """
            }
            return s
        }

        private func options(maxTokens: Int) -> GenerationOptions {
            var opts = GenerationOptions()
            opts.sampling = .greedy
            opts.temperature = nil
            opts.maximumResponseTokens = maxTokens
            return opts
        }

        private func callString(_ s: LanguageModelSession, _ prompt: String, maxTokens: Int) async throws -> String {
            let opts = options(maxTokens: maxTokens)
            let content = try await AppleModelCallQueue.shared.withLock {
                try await s.respond(to: prompt, options: opts).content
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private struct ExtractedJSON: Decodable, Sendable {
            var title: String?
            var emoji: String?
            var tags: [String]?
            var kind: String?
            var status: String?
            var priority: String?
            var area: String?
            var project: String?
            var people: [String]?
            var dueAt: String?
            var summary: String?
            var actionItems: [String]?
        }

        private func extractJSONObject(from raw: String) -> String? {
            // The model may (rarely) wrap JSON with extra text. Grab the first balanced {...}.
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start = s.firstIndex(of: "{") else { return nil }

            var depth = 0
            var i = start
            while i < s.endIndex {
                let ch = s[i]
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = s.index(after: i)
                        return String(s[start..<end])
                    }
                }
                i = s.index(after: i)
            }
            return nil
        }

        private func decodeExtractedJSON(_ raw: String) -> ExtractedJSON? {
            let jsonString = extractJSONObject(from: raw) ?? raw
            guard let data = jsonString.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ExtractedJSON.self, from: data)
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
            let tagModel = SystemLanguageModel(useCase: .contentTagging, guardrails: .permissiveContentTransformations)
            try ensureAvailable(tagModel)

            let general = makeGeneralSession()
            let tagging = makeTaggingSession()

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

            let corrected = try await callString(general, correctedPrompt, maxTokens: 900)
            let correctedOrTrimmed = corrected.isEmpty ? trimmed : corrected

            // Pass 2: extract structured fields in one shot.
            // This reduces queued calls dramatically (important for slow on-device models).
            iso8601.formatOptions = [.withInternetDateTime]
            let now = iso8601.string(from: Date())
            let tz = TimeZone.current.identifier

            let extractPrompt = """
            Extract structured fields from the note below.
            Output STRICT JSON only (no markdown, no commentary), matching this schema:
            {
              "title": string,                  // 3-5 words
              "emoji": string,                  // exactly 1 emoji
              "tags": [string, string, string], // exactly 3, each starts with '#'
              "kind": "idea"|"task"|"meeting"|"journal"|"reference",
              "status": "inbox"|"next"|"later"|"done",
              "priority": "p1"|"p2"|"p3",       // if kind != task, use "p3"
              "area": "work"|"personal"|"health"|"finance"|"learning"|"admin"|"other",
              "project": string,                // 1-4 words or empty
              "people": [string],               // 0-3 names
              "dueAt": string,                  // ISO-8601 or empty (resolve relative dates using now/tz)
              "summary": string,                // 1 sentence, <= 20 words
              "actionItems": [string]           // 0-7 items, imperative; if kind is task, at least 1
            }

            Resolve relative dates using:
            - Current date/time: \(now)
            - Timezone: \(tz)

            NOTE:
            \(correctedOrTrimmed)
            """

            let extractedRaw = (try? await callString(tagging, extractPrompt, maxTokens: 420)) ?? ""
            let extracted = decodeExtractedJSON(extractedRaw)

            let titleRaw = extracted?.title ?? ""
            let title = normalizeTitle(titleRaw, correctedText: correctedOrTrimmed)

            let emojiRaw = extracted?.emoji ?? ""
            let emoji = normalizeEmoji(emojiRaw)

            let tagsIn = extracted?.tags ?? []
            let tags = await normalizeTags(tagsIn, correctedText: correctedOrTrimmed)

            let kind = normalizeKind(extracted?.kind ?? "")
            let status = normalizeStatus(extracted?.status ?? "", kind: kind)
            let priority = normalizePriority(extracted?.priority ?? "", kind: kind)
            let area = normalizeArea(extracted?.area ?? "")

            let project = (extracted?.project ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let people = normalizePeople(extracted?.people ?? [])

            let summary = normalizeSummary(extracted?.summary ?? "", correctedText: correctedOrTrimmed, title: title)
            let actionItems = normalizeActionItems(extracted?.actionItems ?? [], kind: kind, title: title)

            let dueAt = parseDueAt(extracted?.dueAt ?? "", kind: kind)

            // Prefer deterministic link extraction to avoid hallucinations.
            let links = normalizeLinks([], correctedText: correctedOrTrimmed)

            return NoteEnhancement(
                correctedText: correctedOrTrimmed,
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

        private func titlePrompt(noteText: String) -> String {
            """
            Generate a short, specific title for this note.
            Requirements:
            - 3-5 words
            Output ONLY the title text.

            NOTE:
            \(noteText)
            """
        }

        private func emojiPrompt(noteText: String) -> String {
            """
            Pick exactly 1 emoji that best represents this note.
            Output ONLY the emoji.

            NOTE:
            \(noteText)
            """
        }

        private func tagsPrompt(noteText: String) -> String {
            """
            Generate exactly 3 short, specific tags for this note.
            Requirements:
            - Each tag must start with '#'
            - Avoid generic tags like #note #misc #thought
            Output ONLY the 3 tags separated by spaces.

            NOTE:
            \(noteText)
            """
        }

        private func kindPrompt(noteText: String) -> String {
            """
            Classify this note as exactly one kind: idea, task, meeting, journal, reference.
            Definitions:
            - idea: concepts, strategies, possibilities
            - task: an action to do
            - meeting: agenda, notes, follow-ups
            - journal: personal reflection, feelings
            - reference: factual info, how-to, links
            Output ONLY one word.

            NOTE:
            \(noteText)
            """
        }

        private func statusPrompt(noteText: String, kind: NoteKind) -> String {
            """
            Choose a status for this note: inbox, next, later, done.
            Rules:
            - If kind is task: choose next/later/done (default to next).
            - Otherwise: choose inbox unless clearly done/archived.
            Output ONLY one word.

            Kind: \(kind.rawValue)
            NOTE:
            \(noteText)
            """
        }

        private func priorityPrompt(noteText: String) -> String {
            """
            For a task note, choose priority: p1, p2, or p3.
            p1 = urgent/important, p2 = important, p3 = minor.
            Output ONLY one of: p1, p2, p3.

            NOTE:
            \(noteText)
            """
        }

        private func areaPrompt(noteText: String) -> String {
            """
            Classify the life area for this note: work, personal, health, finance, learning, admin, other.
            Output ONLY one word.

            NOTE:
            \(noteText)
            """
        }

        private func projectPrompt(noteText: String) -> String {
            """
            If this note clearly belongs to a specific project (a concrete outcome with a name),
            output that project name in 1-4 words.
            If not, output an empty string.
            Output ONLY the project name or empty string.

            NOTE:
            \(noteText)
            """
        }

        private func peoplePrompt(noteText: String) -> String {
            """
            Extract up to 3 people names explicitly mentioned in the note.
            If none, output an empty string.
            Output ONLY the names, one per line (no bullets, no numbering).

            NOTE:
            \(noteText)
            """
        }

        private func summaryPrompt(noteText: String) -> String {
            """
            Write a 1-sentence summary of the note.
            Requirements:
            - <= 20 words
            - Concrete and specific
            Output ONLY the sentence.

            NOTE:
            \(noteText)
            """
        }

        private func actionItemsPrompt(noteText: String, kind: NoteKind) -> String {
            """
            Extract action items from the note.
            Requirements:
            - Output 0-7 items, each on its own line
            - Imperative verb form
            - No bullets, no numbering
            - If kind is task, output at least 1 item
            Output ONLY the lines.

            Kind: \(kind.rawValue)
            NOTE:
            \(noteText)
            """
        }

        private func dueAtPrompt(noteText: String) -> String {
            iso8601.formatOptions = [.withInternetDateTime]
            let now = iso8601.string(from: Date())
            let tz = TimeZone.current.identifier

            return """
            Extract a due date/time for this task if a deadline is explicitly present or strongly implied.
            Requirements:
            - If there is a deadline, output it as ISO-8601 (date or datetime).
            - Resolve relative dates (today/tomorrow/next week) using:
              - Current date/time: \(now)
              - Timezone: \(tz)
            - If no deadline, output an empty string.
            Output ONLY the ISO-8601 string or empty string.

            NOTE:
            \(noteText)
            """
        }

        private func parseTags(from raw: String) -> [String] {
            let cleaned = raw
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return cleaned
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map(String.init)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:")) }
                .filter { $0.hasPrefix("#") }
        }

        private func parseList(from raw: String) -> [String] {
            let cleaned = raw
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned.isEmpty { return [] }

            var out: [String] = []

            let lines = cleaned
                .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { String($0) }

            for line0 in lines {
                var line = line0.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }

                // Strip common list markers.
                line = line.replacingOccurrences(
                    of: #"^\s*([-*•]\s+|\d+[\.\)]\s+)"#,
                    with: "",
                    options: .regularExpression
                )
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }

                // If a single line contains a few comma-separated values, split them.
                if lines.count == 1, line.contains(",") {
                    for part in line.split(separator: ",") {
                        let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty { continue }
                        out.append(t)
                    }
                } else {
                    out.append(line)
                }
            }

            return out
        }

        private func extractWords(_ s: String) -> [String] {
            s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map { String($0).trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
                .filter { !$0.isEmpty }
        }

        private func normalizeTitle(_ s: String, correctedText: String) -> String {
            let compact = s
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

            let words = extractWords(compact)
            var picked: [String] = []
            for w in dropLeadingStopwords(words) {
                if picked.count == 5 { break }
                picked.append(w)
            }

            if picked.count < 3 {
                let fallbackWords = extractWords(correctedText)
                let meaningful = dropLeadingStopwords(fallbackWords)
                let fillers = meaningful + fallbackWords
                for w in fillers {
                    if picked.count >= 3 { break }
                    if picked.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) { continue }
                    picked.append(w)
                    if picked.count == 5 { break }
                }
            }

            if picked.count < 3 {
                return "Quick Note Capture"
            }

            var capped = picked.prefix(5).joined(separator: " ")
            capped = capped.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’"))
            capped = capped.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?\n\t"))

            // Make titles consistent: capitalize the first letter if it is alphabetic.
            if let first = capped.first, first.isLetter, String(first) == String(first).lowercased() {
                capped = String(first).uppercased() + capped.dropFirst()
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

            // Pick the first emoji-looking grapheme cluster; reject plain text like "ti".
            for ch in trimmed {
                if ch.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
                    return String(ch)
                }
            }
            return "📝"
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
struct AppleModelUnavailableError: Error {
    let reason: SystemLanguageModel.Availability.UnavailableReason
}

#endif
