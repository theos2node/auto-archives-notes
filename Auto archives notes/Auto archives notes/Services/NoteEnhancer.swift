//
//  NoteEnhancer.swift
//  Auto archives notes
//
//  Abstraction over "enhancement" so we can swap in Apple's on-device foundation model API later.
//

import Foundation
import NaturalLanguage

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

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

enum EnhancementEffort: Sendable {
    case fast
    case max
}

final class LocalHeuristicEnhancer: NoteEnhancer {
    private let effort: EnhancementEffort

    private let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by",
        "for", "from", "has", "have", "i", "if", "in", "into", "is", "it",
        "me", "my", "not", "of", "on", "or", "our", "so", "that", "the",
        "their", "then", "there", "this", "to", "up", "was", "we", "with", "you", "your"
    ]

    init(effort: EnhancementEffort = .max) {
        self.effort = effort
    }

    func enhance(rawText: String) async throws -> NoteEnhancement {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NoteEnhancerError.emptyInput }

        // Multi-pass enhancement (local fallback). Replace with Apple's on-device foundation model call later.
        var corrected = normalizeWhitespace(in: trimmed)
        corrected = improveCasingAndPunctuation(in: corrected)
        if effort == .max {
            corrected = spellCorrect(corrected)
            corrected = improveCasingAndPunctuation(in: corrected)
            corrected = normalizeWhitespace(in: corrected)
            await Task.yield()
        }

        let title = makeTitle(from: corrected, fallbackRaw: trimmed)
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

    private func makeTitle(from s: String, fallbackRaw: String) -> String {
        // Prefer the first meaningful sentence/line, but avoid titles that are just stopwords ("The").
        let base = firstMeaningfulChunk(in: s) ?? firstMeaningfulChunk(in: fallbackRaw) ?? s

        let compact = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let words = tokenizeWords(compact)
        let trimmedLead = dropLeadingStopwords(words)

        var candidate: String
        if trimmedLead.count >= 3 {
            // Hard requirement: <= 5 words.
            candidate = trimmedLead.prefix(5).joined(separator: " ")
        } else {
            // Fallback: build a title from keywords.
            let keywords = topKeywords(in: s, limit: 4)
            if keywords.isEmpty {
                candidate = "Quick Note"
            } else {
                // Also keep <= 5 words here.
                candidate = keywords.prefix(5).joined(separator: " ").capitalized
            }
        }

        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty { candidate = "Quick Note" }
        candidate = candidate.prefix(60).trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate
    }

    private func firstMeaningfulChunk(in s: String) -> String? {
        // First non-empty line; if it's too short, fall back to first sentence-ish chunk.
        let lines = s
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let line = lines.first, line.count >= 8 {
            return line
        }

        let sentence = s
            .split(whereSeparator: { ".!?".contains($0) || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.count >= 8 })

        return sentence ?? lines.first
    }

    private func tokenizeWords(_ s: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = s
        var out: [String] = []
        tokenizer.enumerateTokens(in: s.startIndex..<s.endIndex) { range, _ in
            let w = String(s[range]).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if !w.isEmpty { out.append(w) }
            return true
        }
        return out
    }

    private func dropLeadingStopwords(_ words: [String]) -> [String] {
        var i = 0
        while i < words.count {
            let w = words[i].lowercased()
            if stopwords.contains(w) || w.count <= 2 {
                i += 1
                continue
            }
            break
        }
        return Array(words.dropFirst(i))
    }

    private func topKeywords(in s: String, limit: Int) -> [String] {
        // Prefer nouns and named entities; fall back to frequent non-stopwords.
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = s

        var freq: [String: Int] = [:]
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        // Nouns.
        tagger.enumerateTags(in: s.startIndex..<s.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            guard let tag, tag == .noun else { return true }
            let raw = String(s[range]).lowercased()
            let w = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if w.count < 4 { return true }
            if stopwords.contains(w) { return true }
            freq[w, default: 0] += 1
            return true
        }

        // Named entities (people/orgs/places).
        tagger.enumerateTags(in: s.startIndex..<s.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            guard let tag else { return true }
            if tag != .personalName && tag != .organizationName && tag != .placeName { return true }
            let raw = String(s[range]).lowercased()
            let w = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if w.count < 3 { return true }
            freq[w, default: 0] += 2
            return true
        }

        if freq.isEmpty {
            let fallback = makeTags(from: s).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            return Array(fallback.prefix(limit))
        }

        let sorted = freq.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            return a.key < b.key
        }
        return Array(sorted.prefix(limit).map(\.key))
    }

    private func makeTags(from s: String) -> [String] {
        var out: [String] = []

        // Prefer semantic keywords first.
        let keywords = topKeywords(in: s, limit: 10)
        for k in keywords {
            let t = "#\(k.lowercased())"
            if !out.contains(t) { out.append(t) }
        }

        if out.count < 6 {
            // Fall back to frequency-based words.
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

            for w in sorted {
                let t = "#\(w)"
                if !out.contains(t) { out.append(t) }
                if out.count >= 12 { break }
            }
        }

        if out.isEmpty { out = ["#inbox", "#note", "#thought"] }
        if out.count == 1 { out.append("#inbox") }
        if out.count == 2 { out.append("#thought") }
        return out.prefix(12).map { $0 }
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

    private func spellCorrect(_ s: String) -> String {
        #if os(macOS)
        return spellCorrectWithNSSpellChecker(s)
        #elseif os(iOS) || os(visionOS)
        return spellCorrectWithUITextChecker(s)
        #else
        return s
        #endif
    }

    #if os(macOS)
    private func spellCorrectWithNSSpellChecker(_ s: String) -> String {
        // Conservative spelling correction: only replace when the first guess differs.
        let ns = s as NSString
        let checker = NSSpellChecker.shared
        var replacements: [(NSRange, String)] = []

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords]) { substring, range, _, _ in
            guard let substring else { return }
            if range.length < 4 { return }
            let lowered = substring.lowercased()
            if self.stopwords.contains(lowered) { return }

            let misspelledRange = checker.checkSpelling(of: substring, startingAt: 0)
            if misspelledRange.location == NSNotFound { return }
            let guesses = checker.guesses(forWordRange: misspelledRange, in: substring, language: "en_US", inSpellDocumentWithTag: 0) ?? []
            guard let replacement = guesses.first, replacement.lowercased() != lowered else { return }
            replacements.append((range, replacement))
        }

        if replacements.isEmpty { return s }
        replacements.sort { $0.0.location > $1.0.location }
        let mut = NSMutableString(string: s)
        for (range, replacement) in replacements {
            mut.replaceCharacters(in: range, with: replacement)
        }
        return mut as String
    }
    #endif

    #if os(iOS) || os(visionOS)
    private func spellCorrectWithUITextChecker(_ s: String) -> String {
        let ns = s as NSString
        let checker = UITextChecker()
        var replacements: [(NSRange, String)] = []

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords]) { substring, range, _, _ in
            guard let substring else { return }
            if range.length < 4 { return }
            let lowered = substring.lowercased()
            if self.stopwords.contains(lowered) { return }

            let miss = checker.rangeOfMisspelledWord(in: substring, range: NSRange(location: 0, length: (substring as NSString).length), startingAt: 0, wrap: false, language: "en_US")
            if miss.location == NSNotFound { return }
            let guesses = checker.guesses(forWordRange: miss, in: substring, language: "en_US") ?? []
            guard let replacement = guesses.first, replacement.lowercased() != lowered else { return }
            replacements.append((range, replacement))
        }

        if replacements.isEmpty { return s }
        replacements.sort { $0.0.location > $1.0.location }
        let mut = NSMutableString(string: s)
        for (range, replacement) in replacements {
            mut.replaceCharacters(in: range, with: replacement)
        }
        return mut as String
    }
    #endif

    private func improveCasingAndPunctuation(in s: String) -> String {
        var out = s

        // Fix common spacing before punctuation.
        out = out.replacingOccurrences(of: " ,", with: ",")
        out = out.replacingOccurrences(of: " .", with: ".")
        out = out.replacingOccurrences(of: " !", with: "!")
        out = out.replacingOccurrences(of: " ?", with: "?")
        out = out.replacingOccurrences(of: " ;", with: ";")
        out = out.replacingOccurrences(of: " :", with: ":")

        // Normalize " i " -> " I " when it's a standalone word.
        out = out.replacingOccurrences(of: #"\bi\b"#, with: "I", options: [.regularExpression])

        // Capitalize the first letter of the text and letters after sentence endings.
        let chars = Array(out)
        var rebuilt: [Character] = []
        rebuilt.reserveCapacity(chars.count)

        var shouldCapitalize = true
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if shouldCapitalize {
                if c == " " || c == "\t" || c == "\n" || c == "\r" {
                    rebuilt.append(c)
                    i += 1
                    continue
                }
                if let scalar = c.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
                    rebuilt.append(Character(String(c).uppercased()))
                    shouldCapitalize = false
                    i += 1
                    continue
                }
                rebuilt.append(c)
                i += 1
                continue
            }

            rebuilt.append(c)
            if c == "." || c == "!" || c == "?" || c == "\n" {
                shouldCapitalize = true
            }
            i += 1
        }

        out = String(rebuilt)
        out = out.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: [.regularExpression])
        return out
    }
}
