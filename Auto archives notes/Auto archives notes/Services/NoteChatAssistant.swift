//
//  NoteChatAssistant.swift
//  Auto archives notes
//
//  On-device "chat with your notes" helper.
//  Uses FoundationModels when available, otherwise falls back to heuristic retrieval + templated response.
//

import Foundation

struct NoteSearchResult: Sendable {
    var noteID: UUID
    var score: Double
}

struct NoteChatResponse: Sendable {
    var answer: String
    var matchedNoteIDs: [UUID]
}

final class NoteChatAssistant: @unchecked Sendable {
    func respond(question: String, notes: [Note]) async -> NoteChatResponse {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return NoteChatResponse(answer: "Ask a question about your notes.", matchedNoteIDs: [])
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            do {
                return try await AppleNotesChat().respond(question: q, notes: notes)
            } catch {
                let fallback = heuristicRespond(question: q, notes: notes)
                return NoteChatResponse(
                    answer: fallback.answer + "\n\n(Using fallback search: \(String(describing: error)))",
                    matchedNoteIDs: fallback.matchedNoteIDs
                )
            }
        }
        #endif

        return heuristicRespond(question: q, notes: notes)
    }

    private func heuristicRespond(question: String, notes: [Note]) -> NoteChatResponse {
        let keywords = tokenize(question)
        let results = scoreNotes(keywords: keywords, notes: notes).prefix(8)
        let ids = results.map(\.noteID)

        if ids.isEmpty {
            return NoteChatResponse(
                answer: "I couldn't find anything obvious. Try using a few concrete keywords (project name, person, tag, or a phrase).",
                matchedNoteIDs: []
            )
        }

        let titles = notes
            .filter { ids.contains($0.id) }
            .prefix(5)
            .map { "\($0.displayEmoji) \($0.displayTitle)" }
            .joined(separator: "\n")

        return NoteChatResponse(
            answer: "Here are the closest matches I found:\n" + titles,
            matchedNoteIDs: Array(ids)
        )
    }

    private func tokenize(_ s: String) -> [String] {
        let cleaned = s
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s#]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.split(separator: " ").map(String.init).filter { $0.count >= 3 }
    }

    private func scoreNotes(keywords: [String], notes: [Note]) -> [NoteSearchResult] {
        if keywords.isEmpty { return [] }

        func score(hay: String) -> Double {
            let h = hay.lowercased()
            var s: Double = 0
            for k in keywords {
                if h.contains(k) { s += 1 }
            }
            return s
        }

        var out: [NoteSearchResult] = []
        out.reserveCapacity(notes.count)
        for n in notes {
            var s = 0.0
            s += 5.0 * score(hay: n.displayTitle)
            s += 4.0 * score(hay: n.tagsCSV)
            s += 3.0 * score(hay: n.summary)
            s += 2.5 * score(hay: n.actionItemsText)
            s += 2.0 * score(hay: n.project)
            s += 1.5 * score(hay: n.peopleCSV)
            s += 1.0 * score(hay: n.enhancedText)
            s += 0.7 * score(hay: n.rawText)

            if s > 0 {
                out.append(NoteSearchResult(noteID: n.id, score: s))
            }
        }

        return out.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.noteID.uuidString < b.noteID.uuidString
        }
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
fileprivate final class AppleNotesChat: @unchecked Sendable {
    private let iso8601 = ISO8601DateFormatter()

    func respond(question: String, notes: [Note]) async throws -> NoteChatResponse {
        let intent = try await interpret(question: question)
        let ranked = rank(notes: notes, intent: intent, rawQuestion: question)

        if ranked.isEmpty {
            return NoteChatResponse(
                answer: "I couldn't find a matching note. Try asking with a tag, project name, or a distinctive phrase.",
                matchedNoteIDs: []
            )
        }

        let top = Array(ranked.prefix(max(3, min(12, intent.limit))))
        let answer = try await answer(question: question, intent: intent, candidates: top, allNotes: notes)

        return answer
    }

    private func interpret(question: String) async throws -> NoteQueryIntent {
        let model = SystemLanguageModel(useCase: .contentTagging, guardrails: .permissiveContentTransformations)
        if case .unavailable(let reason) = model.availability {
            throw AppleModelUnavailableError(reason: reason)
        }

        let s = LanguageModelSession(model: model, tools: []) {
            """
            You convert a natural-language question about a personal notes database into a structured retrieval intent.
            Be conservative: only add filters if the user explicitly implies them.
            """
        }

        var opts = GenerationOptions()
        opts.sampling = .greedy
        opts.temperature = nil
        opts.maximumResponseTokens = 450

        iso8601.formatOptions = [.withInternetDateTime]
        let now = iso8601.string(from: Date())
        let tz = TimeZone.current.identifier

        let prompt = """
        Context:
        - Current date/time: \(now)
        - Current timezone: \(tz)

        Task:
        Turn the user's question into a retrieval intent.

        Output fields:
        - keywords: 3-10 content words or tags (no stopwords)
        - kind: one of [any, idea, task, meeting, journal, reference]
        - status: one of [any, inbox, next, later, done]
        - area: one of [any, work, personal, health, finance, learning, admin, other]
        - project: short string or empty
        - people: 0-3 names or []
        - includeDone: true/false (default false unless explicitly asked)
        - dueBeforeISO: ISO-8601 datetime/date or empty
        - dueAfterISO: ISO-8601 datetime/date or empty
        - limit: integer 3-12

        User question:
        \(question)
        """

        let intent = try await AppleModelCallQueue.shared.withLock {
            try await s.respond(to: prompt, generating: NoteQueryIntent.self, options: opts).content
        }
        return intent.normalized()
    }

    private func rank(notes: [Note], intent: NoteQueryIntent, rawQuestion: String) -> [NoteSearchResult] {
        let keywords = (intent.keywords + tokenize(rawQuestion)).deduped().prefix(12)
        if keywords.isEmpty { return [] }

        func contains(_ hay: String, _ needle: String) -> Bool {
            hay.localizedCaseInsensitiveContains(needle)
        }

        func score(hay: String) -> Double {
            var s: Double = 0
            for k in keywords {
                if contains(hay, k) { s += 1 }
            }
            return s
        }

        var out: [NoteSearchResult] = []
        out.reserveCapacity(notes.count)
        for n in notes {
            if let k = intent.kindFilter, n.kind != k { continue }
            if let a = intent.areaFilter, n.area != a { continue }
            if let st = intent.statusFilter {
                if n.status != st { continue }
            } else if intent.includeDone == false, n.status == .done {
                // Default: hide done tasks unless explicitly requested.
                continue
            }

            if !intent.project.isEmpty, !contains(n.project, intent.project) {
                continue
            }

            if !intent.people.isEmpty {
                let people = n.peopleCSV
                let anyHit = intent.people.contains(where: { contains(people, $0) })
                if !anyHit { continue }
            }

            if intent.kindFilter == .task {
                if let dBefore = intent.dueBefore, let due = n.dueAt {
                    if due > dBefore { continue }
                }
                if let dAfter = intent.dueAfter, let due = n.dueAt {
                    if due < dAfter { continue }
                }
            }

            var s = 0.0
            s += 6.0 * score(hay: n.displayTitle)
            s += 5.0 * score(hay: n.tagsCSV)
            s += 3.0 * score(hay: n.summary)
            s += 2.6 * score(hay: n.actionItemsText)
            s += 2.2 * score(hay: n.project)
            s += 1.7 * score(hay: n.peopleCSV)
            s += 1.1 * score(hay: n.enhancedText)
            s += 0.6 * score(hay: n.rawText)
            if n.pinned { s += 0.7 }
            if n.isEnhancing { s -= 2.0 }

            if s > 0.01 {
                out.append(NoteSearchResult(noteID: n.id, score: s))
            }
        }

        return out.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.noteID.uuidString < b.noteID.uuidString
        }
    }

    private func answer(question: String, intent: NoteQueryIntent, candidates: [NoteSearchResult], allNotes: [Note]) async throws -> NoteChatResponse {
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        if case .unavailable(let reason) = model.availability {
            throw AppleModelUnavailableError(reason: reason)
        }

        let session = LanguageModelSession(model: model, tools: []) {
            """
            You are a notes assistant. Answer based only on the retrieved notes provided.
            If the notes do not contain enough evidence, say so and ask a clarifying question.
            Keep the answer concise and actionable.
            """
        }

        var opts = GenerationOptions()
        opts.sampling = .greedy
        opts.temperature = nil
        opts.maximumResponseTokens = 700

        let rendered = renderCandidates(candidates: candidates, allNotes: allNotes)
        let prompt = """
        User question:
        \(question)

        Retrieval intent:
        - kind: \(intent.kindRaw)
        - status: \(intent.statusRaw)
        - area: \(intent.areaRaw)
        - project: \(intent.project.isEmpty ? "(none)" : intent.project)
        - people: \(intent.people.isEmpty ? "[]" : intent.people.joined(separator: ", "))
        - includeDone: \(intent.includeDone)

        Retrieved notes (use only these):
        \(rendered)

        Provide:
        - answer: a short response
        - indices: 0-6 integers referencing the notes you used (by index)
        """

        let content = try await AppleModelCallQueue.shared.withLock {
            try await session.respond(to: prompt, generating: ChatAnswer.self, options: opts).content
        }
        let answerText = content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let used = content.indices
            .map { max(0, min($0, candidates.count - 1)) }
            .deduped()

        let usedIDs: [UUID]
        if used.isEmpty {
            usedIDs = candidates.prefix(6).map(\.noteID)
        } else {
            usedIDs = used.map { candidates[$0].noteID }
        }

        return NoteChatResponse(
            answer: answerText.isEmpty ? "Here are the most relevant notes I found." : answerText,
            matchedNoteIDs: usedIDs
        )
    }

    private func renderCandidates(candidates: [NoteSearchResult], allNotes: [Note]) -> String {
        var byID: [UUID: Note] = [:]
        byID.reserveCapacity(allNotes.count)
        for n in allNotes { byID[n.id] = n }

        func clip(_ s: String, max: Int) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count <= max { return t }
            let idx = t.index(t.startIndex, offsetBy: max)
            return String(t[..<idx]) + "…"
        }

        var lines: [String] = []
        for (i, r) in candidates.enumerated() {
            guard let n = byID[r.noteID] else { continue }
            let due = n.dueAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            let dueStr = due.isEmpty ? "" : " due \(due)"
            let info = "\(n.kind.rawValue)/\(n.status.rawValue)/\(n.area.rawValue)\(dueStr)"
            let snippet = clip(n.summary.isEmpty ? n.enhancedText : n.summary, max: 180)
            lines.append("[\(i)] \(n.displayEmoji) \(n.displayTitle) (\(info)) tags: \(n.tags.prefix(3).joined(separator: " ")) | \(snippet)")
        }
        return lines.joined(separator: "\n")
    }

    private func tokenize(_ s: String) -> [String] {
        let cleaned = s
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s#]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.split(separator: " ").map(String.init).filter { $0.count >= 3 }
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
fileprivate struct NoteQueryIntent {
    var keywords: [String]
    var kind: String
    var status: String
    var area: String
    var project: String
    var people: [String]
    var includeDone: Bool
    var dueBeforeISO: String
    var dueAfterISO: String
    var limit: Int

    var kindRaw: String { kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var statusRaw: String { status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var areaRaw: String { area.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var kindEnum: NoteKindOrAny { NoteKindOrAny(rawValue: kindRaw) ?? .any }
    var statusEnum: NoteStatusOrAny { NoteStatusOrAny(rawValue: statusRaw) ?? .any }
    var areaEnum: NoteAreaOrAny { NoteAreaOrAny(rawValue: areaRaw) ?? .any }

    var kindFilter: NoteKind? {
        switch kindEnum {
        case .idea: return .idea
        case .task: return .task
        case .meeting: return .meeting
        case .journal: return .journal
        case .reference: return .reference
        case .any: return nil
        }
    }

    var statusFilter: NoteStatus? {
        switch statusEnum {
        case .inbox: return .inbox
        case .next: return .next
        case .later: return .later
        case .done: return .done
        case .any: return nil
        }
    }

    var areaFilter: NoteArea? {
        switch areaEnum {
        case .work: return .work
        case .personal: return .personal
        case .health: return .health
        case .finance: return .finance
        case .learning: return .learning
        case .admin: return .admin
        case .other: return .other
        case .any: return nil
        }
    }

    var dueBefore: Date? { Self.parseISO(dueBeforeISO) }
    var dueAfter: Date? { Self.parseISO(dueAfterISO) }

    func normalized() -> NoteQueryIntent {
        var c = self
        c.keywords = c.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        c.project = c.project.trimmingCharacters(in: .whitespacesAndNewlines)
        c.people = c.people
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
            .map { $0 }
        c.limit = max(3, min(12, c.limit))
        return c
    }

    private static func parseISO(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: t) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: t) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: t)
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
fileprivate struct ChatAnswer {
    var answer: String
    var indices: [Int]
}

fileprivate enum NoteKindOrAny: String, Sendable {
    case any
    case idea
    case task
    case meeting
    case journal
    case reference
}

fileprivate enum NoteStatusOrAny: String, Sendable {
    case any
    case inbox
    case next
    case later
    case done
}

fileprivate enum NoteAreaOrAny: String, Sendable {
    case any
    case work
    case personal
    case health
    case finance
    case learning
    case admin
    case other
}

fileprivate extension Array where Element: Hashable {
    func deduped() -> [Element] {
        var seen = Set<Element>()
        var out: [Element] = []
        out.reserveCapacity(self.count)
        for x in self {
            if seen.contains(x) { continue }
            seen.insert(x)
            out.append(x)
        }
        return out
    }
}

#endif
