//
//  NoteEnhancer.swift
//  Auto archives notes
//
//  Abstraction over "enhancement" so we can swap in Apple's on-device foundation model API later.
//

import Foundation
import NaturalLanguage

struct NoteEnhancement {
    var correctedText: String
    var title: String
    var emoji: String
    var tags: [String]
}

protocol NoteEnhancer {
    func enhance(rawText: String) async throws -> NoteEnhancement
}

enum NoteEnhancerError: Error {
    case emptyInput
}

final class LocalHeuristicEnhancer: NoteEnhancer {
    private let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by",
        "for", "from", "has", "have", "i", "if", "in", "into", "is", "it",
        "me", "my", "not", "of", "on", "or", "our", "so", "that", "the",
        "their", "then", "there", "this", "to", "up", "was", "we", "with", "you", "your"
    ]

    func enhance(rawText: String) async throws -> NoteEnhancement {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NoteEnhancerError.emptyInput }

        // Minimal "correction" without relying on private APIs.
        // We'll replace this with Apple's on-device foundation model call.
        let corrected = normalizeWhitespace(in: trimmed)

        let title = makeTitle(from: corrected)
        let tags = makeTags(from: corrected)
        let emoji = pickEmoji(title: title, tags: tags)

        return NoteEnhancement(
            correctedText: corrected,
            title: title,
            emoji: emoji,
            tags: Array(tags.prefix(3))
        )
    }

    private func normalizeWhitespace(in s: String) -> String {
        // Collapse 3+ blank lines into 2; trim trailing spaces per-line.
        let lines = s
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { String($0).replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }

        var out: [String] = []
        var blankRun = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blankRun += 1
                if blankRun <= 2 { out.append("") }
            } else {
                blankRun = 0
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    private func makeTitle(from s: String) -> String {
        // First non-empty line; fall back to first sentence; hard truncate.
        let firstLine = s
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        let base = (firstLine ?? s).trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = base.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if compact.count <= 48 { return compact }
        let idx = compact.index(compact.startIndex, offsetBy: 48)
        return String(compact[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeTags(from s: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = s

        var freq: [String: Int] = [:]
        tokenizer.enumerateTokens(in: s.startIndex..<s.endIndex) { range, _ in
            let w0 = String(s[range]).lowercased()
            let w = w0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if w.count < 4 { return true }
            if stopwords.contains(w) { return true }
            freq[w, default: 0] += 1
            return true
        }

        let sorted = freq
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return a.key < b.key
            }
            .map(\.key)

        // Light normalization: prefer short, human tags.
        return sorted.prefix(12).map { "#\($0)" }
    }

    private func pickEmoji(title: String, tags: [String]) -> String {
        let hay = ([title] + tags).joined(separator: " ").lowercased()

        // Extremely simple mapping for now.
        if hay.contains("todo") || hay.contains("#todo") || hay.contains("task") { return "✅" }
        if hay.contains("idea") || hay.contains("brain") { return "💡" }
        if hay.contains("meeting") { return "🗓️" }
        if hay.contains("shopping") || hay.contains("grocer") { return "🛒" }
        if hay.contains("work") || hay.contains("project") { return "🧩" }
        if hay.contains("health") || hay.contains("gym") { return "🏃‍♂️" }
        return "📝"
    }
}

