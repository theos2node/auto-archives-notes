import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

protocol NoteTitleGenerating: Sendable {
    func generateTitle(from body: String) async -> String?
}

final class BestAvailableNoteTitleGenerator: NoteTitleGenerating, @unchecked Sendable {
    private let fallback: NoteTitleGenerating

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private let apple = AppleFoundationModelTitleGenerator()
    #endif

    init(fallback: NoteTitleGenerating = LocalHeuristicTitleGenerator()) {
        self.fallback = fallback
    }

    func generateTitle(from body: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            if let title = await apple.generateTitle(from: body) {
                return title
            }
        }
        #endif

        return await fallback.generateTitle(from: body)
    }
}

final class LocalHeuristicTitleGenerator: NoteTitleGenerating, @unchecked Sendable {
    private let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by",
        "for", "from", "has", "have", "i", "if", "in", "into", "is", "it",
        "its", "me", "my", "need", "needs", "not", "of", "on", "or", "our",
        "so", "that", "the", "their", "then", "there", "this", "to", "up",
        "was", "we", "with", "you", "your"
    ]

    func generateTitle(from body: String) async -> String? {
        let cleanedBody = body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
        guard !cleanedBody.isEmpty else { return nil }

        if let sentenceTitle = sentenceBasedTitle(from: cleanedBody) {
            return sentenceTitle
        }

        let words = tokenize(cleanedBody)
        guard words.count >= 3 else { return nil }

        return keywordBasedTitle(from: words, body: cleanedBody)
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }
    }

    private func sentenceBasedTitle(from body: String) -> String? {
        let parts = body
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let bodyLower = body.lowercased()
        var bestTitle: String?
        var bestScore = Int.min

        for part in parts {
            let tokens = trimEdgeStopwords(tokenize(part))
            guard tokens.count >= 3 else { continue }

            let limited = Array(tokens.prefix(5))
            guard let candidate = normalizeTitle(from: limited.joined(separator: " "), body: body, rejectBodyPrefix: true) else {
                continue
            }

            let meaningfulCount = limited.filter(isMeaningfulWord).count
            var score = meaningfulCount * 4 - abs(limited.count - 4)

            if bodyLower.hasPrefix(part.lowercased()) {
                score -= 3
            }

            if score > bestScore {
                bestScore = score
                bestTitle = candidate
            }
        }

        return bestTitle
    }

    private func keywordBasedTitle(from words: [String], body: String) -> String? {
        var counts: [String: Int] = [:]
        var firstIndex: [String: Int] = [:]

        for (index, rawWord) in words.enumerated() {
            let word = rawWord.lowercased()
            guard isMeaningfulWord(word) else { continue }

            counts[word, default: 0] += 1
            if firstIndex[word] == nil {
                firstIndex[word] = index
            }
        }

        let ranked = counts.keys.sorted { lhs, rhs in
            let leftCount = counts[lhs] ?? 0
            let rightCount = counts[rhs] ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            return (firstIndex[lhs] ?? .max) < (firstIndex[rhs] ?? .max)
        }

        guard ranked.count >= 3 else { return nil }
        let preferredCount = min(5, ranked.count >= 4 ? 4 : 3)
        let rawTitle = ranked.prefix(preferredCount).joined(separator: " ")
        return normalizeTitle(from: rawTitle, body: body, rejectBodyPrefix: true)
    }

    private func trimEdgeStopwords(_ words: [String]) -> [String] {
        guard !words.isEmpty else { return [] }

        var start = 0
        var end = words.count - 1

        while start <= end, !isMeaningfulWord(words[start]) {
            start += 1
        }
        while end >= start, !isMeaningfulWord(words[end]) {
            end -= 1
        }

        guard start <= end else { return [] }
        return Array(words[start...end])
    }

    private func isMeaningfulWord(_ raw: String) -> Bool {
        let word = raw.lowercased()
        guard word.count >= 3 else { return false }
        guard !stopwords.contains(word) else { return false }
        guard word.rangeOfCharacter(from: .letters) != nil else { return false }
        return true
    }

    private func normalizeTitle(from raw: String, body: String, rejectBodyPrefix: Bool) -> String? {
        var cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,:;!?"))

        guard !cleaned.isEmpty else { return nil }

        let words = cleaned
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        guard words.count >= 3 else { return nil }

        cleaned = words.prefix(5).joined(separator: " ")

        if rejectBodyPrefix, body.lowercased().hasPrefix(cleaned.lowercased()) {
            return nil
        }

        if let first = cleaned.first, first.isLetter, String(first) == String(first).lowercased() {
            cleaned = String(first).uppercased() + cleaned.dropFirst()
        }

        return cleaned.isEmpty ? nil : cleaned
    }
}

#if canImport(FoundationModels)

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
private struct GeneratedNoteTitle {
    @Guide(description: "A specific note title in 3 to 5 words, based on the full note, without copying the opening phrase verbatim.")
    var title: String
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
final class AppleFoundationModelTitleGenerator: NoteTitleGenerating, @unchecked Sendable {
    actor Runner {
        func generateTitle(from body: String) async -> String? {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 24 else { return nil }

            let model = SystemLanguageModel(useCase: .contentTagging, guardrails: .permissiveContentTransformations)
            guard case .available = model.availability else { return nil }

            let session = LanguageModelSession(model: model, tools: []) {
                """
                You create precise note titles.
                Respond with plain text only.
                """
            }

            let options: GenerationOptions = {
                var configured = GenerationOptions()
                configured.maximumResponseTokens = 24
                return configured
            }()

            let prompt = """
            Generate a title for this note.
            Focus on what the note is actually about.

            NOTE:
            \(trimmed)
            """

            do {
                let structured = try await AppleTitleModelCallQueue.shared.withLock {
                    try await session.respond(to: prompt, generating: GeneratedNoteTitle.self, options: options).content
                }
                return normalize(structured.title, sourceBody: trimmed)
            } catch {
                return nil
            }
        }

        private func normalize(_ raw: String, sourceBody: String) -> String? {
            let compact = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))

            guard !compact.isEmpty else { return nil }

            let words = compact
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .map(String.init)

            guard words.count >= 3 else { return nil }

            var title = words.prefix(5).joined(separator: " ")
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!? "))
            guard !sourceBody.lowercased().hasPrefix(title.lowercased()) else { return nil }
            guard !looksLikePromptMetadata(title, sourceBody: sourceBody) else { return nil }

            if let first = title.first, first.isLetter, String(first) == String(first).lowercased() {
                title = String(first).uppercased() + title.dropFirst()
            }

            return title.isEmpty ? nil : title
        }

        private func looksLikePromptMetadata(_ title: String, sourceBody: String) -> Bool {
            let titleTokens = Set(
                title.lowercased()
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map(String.init)
            )
            if titleTokens.isEmpty { return false }

            let sourceLower = sourceBody.lowercased()
            let suspicious = [
                "title", "word", "words", "specific", "specificity",
                "requirement", "requirements", "context", "opening", "phrase"
            ]

            for token in suspicious where titleTokens.contains(token) {
                if !sourceLower.contains(token) {
                    return true
                }
            }
            return false
        }
    }

    private let runner = Runner()

    func generateTitle(from body: String) async -> String? {
        await runner.generateTitle(from: body)
    }
}

actor AppleTitleModelCallQueue {
    static let shared = AppleTitleModelCallQueue()

    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !running {
            running = true
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            running = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}

#endif
