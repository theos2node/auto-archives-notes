//
//  ContentView.swift
//  Auto archives notes
//
//  Created by Théo on 2/17/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedSection: SidebarSection = .allNotes
    @State private var selectedNoteID: UUID?
    @State private var workingTitle = ""
    @State private var workingBody = ""
    @State private var hasAnimatedIn = false
    @State private var pendingShortcutTitleNoteIDs: Set<UUID> = []
    @State private var titleBatchQueue: [UUID] = []
    @State private var isShowingShortcutInstallAlert = false
    @State private var shortcutInstallAlertMessage = ""
    @State private var shortcutCallbackTimeoutTask: Task<Void, Never>?
    @State private var clipboardPendingNoteID: UUID?
    @State private var lastClipboardSnapshot: String = ""

    @State private var notes: [NoteItem] = NoteItem.samples

    private static let titleShortcutName = "Notes, Meta Data Workflow201"
    private static let titleShortcutInstallURLString = "https://www.icloud.com/shortcuts/00826f09550d431998ceef65e08381e1"
    private static let shortcutCallbackTimeoutNanos: UInt64 = 15_000_000_000
    private static let titleGenerationPrompt = """
    Generate metadata for this note and return strict JSON only.

    JSON schema:
    {"title":"3-5 word title","summary":"one sentence summary"}

    Rules:
    - The title must be 3 to 5 words and specific.
    - No trailing punctuation in title.
    - Return only valid JSON, no markdown.

    NOTE:
    """

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.96),
                    Color(red: 0.95, green: 0.95, blue: 0.93)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 18) {
                sidebar
                    .frame(width: 316)
                    .opacity(hasAnimatedIn ? 1 : 0)
                    .offset(x: hasAnimatedIn ? 0 : -26)

                noteEditor
                    .opacity(hasAnimatedIn ? 1 : 0)
                    .offset(y: hasAnimatedIn ? 0 : 18)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .animation(.easeOut(duration: 0.58), value: hasAnimatedIn)
        }
        .onAppear {
            if selectedNoteID == nil {
                selectedNoteID = notes.first?.id
                workingTitle = notes.first?.title ?? ""
                workingBody = notes.first?.body ?? ""
            }

            guard !hasAnimatedIn else { return }
            hasAnimatedIn = true
        }
        .onChange(of: workingTitle) { _, _ in
            syncSelectedNote()
        }
        .onChange(of: workingBody) { _, _ in
            syncSelectedNote()
        }
        .onOpenURL { url in
            handleShortcutCallbackURL(url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                attemptClipboardFallbackIfNeeded()
            }
        }
        .alert("Shortcut Required", isPresented: $isShowingShortcutInstallAlert) {
            if let installURL = shortcutInstallURL {
                Button("Install") {
                    openURL(installURL)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(shortcutInstallAlertMessage)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notebook")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.86))
                    Text("Minimal notes for iPad")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.45))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        runTitleShortcutForAllEligibleNotes()
                    } label: {
                        ZStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(Color.black.opacity(0.75))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isBatchTitleShortcutInProgress)
                    .overlay(alignment: .topTrailing) {
                        if shouldShowBatchShortcutBadge {
                            Circle()
                                .fill(Color.red.opacity(0.95))
                                .frame(width: 9, height: 9)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .help("Generate titles for untitled notes (Shortcuts + ChatGPT)")

                    Button {
                        createNewNote()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        SectionChip(section: section, isSelected: selectedSection == section)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(notes) { note in
                        Button {
                            selectedNoteID = note.id
                            workingTitle = note.title
                            workingBody = note.body
                        } label: {
                            NoteCard(note: note, isSelected: selectedNoteID == note.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        )
    }

    private var noteEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 9, height: 9)
                Text("Draft")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.4))

                Spacer()

                Text("Edited today")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()
                .overlay(Color.black.opacity(0.08))

            VStack(alignment: .leading, spacing: 14) {
                TextField("Untitled", text: $workingTitle)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(Color.black.opacity(0.86))

                HStack(spacing: 8) {
                    Label("Private", systemImage: "lock")
                    Label("Notes", systemImage: "number")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.42))
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            Divider()
                .overlay(Color.black.opacity(0.08))
                .padding(.top, 18)

            TextEditor(text: $workingBody)
                .scrollContentBackground(.hidden)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.77))
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 30, x: 0, y: 15)
    }

    private func createNewNote() {
        let newNote = NoteItem(
            title: "Untitled",
            body: "",
            shortDate: Self.shortDateFormatter.string(from: Date())
        )

        notes.insert(newNote, at: 0)
        selectedNoteID = newNote.id
        workingTitle = newNote.title
        workingBody = newNote.body
        selectedSection = .allNotes
    }

    private func syncSelectedNote() {
        guard let selectedNoteID else { return }
        guard let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        notes[index].title = workingTitle
        notes[index].body = workingBody
    }

    private var isBatchTitleShortcutInProgress: Bool {
        !pendingShortcutTitleNoteIDs.isEmpty || !titleBatchQueue.isEmpty
    }

    private var shouldShowBatchShortcutBadge: Bool {
        !eligibleUntitledNoteIDs.isEmpty && !isBatchTitleShortcutInProgress
    }

    private var eligibleUntitledNoteIDs: [UUID] {
        notes
            .filter { note in
                shouldOfferTitleGeneration(title: note.title, body: note.body)
                    && !pendingShortcutTitleNoteIDs.contains(note.id)
            }
            .map(\.id)
    }

    private func shouldOfferTitleGeneration(title: String, body: String) -> Bool {
        guard isPlaceholderTitle(title) else { return false }
        return body.trimmingCharacters(in: .whitespacesAndNewlines).count >= 1
    }

    private func runTitleShortcutForAllEligibleNotes() {
        let candidates = eligibleUntitledNoteIDs
        guard !candidates.isEmpty else {
            shortcutInstallAlertMessage = "No untitled notes with text are ready yet."
            isShowingShortcutInstallAlert = true
            return
        }
        titleBatchQueue = candidates
        runTitleShortcutForNextInBatch()
    }

    private func runTitleShortcutForNextInBatch() {
        guard pendingShortcutTitleNoteIDs.isEmpty else { return }
        guard let noteID = titleBatchQueue.first else { return }
        runTitleShortcut(for: noteID)
    }

    private func runTitleShortcut(for noteID: UUID) {
        guard !pendingShortcutTitleNoteIDs.contains(noteID) else { return }
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }

        let note = notes[index]
        guard shouldOfferTitleGeneration(title: note.title, body: note.body) else {
            finishBatchAttempt(for: noteID, continueBatch: true)
            return
        }

        let bodySnapshot = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortcutInput = makeShortcutInput(noteBody: bodySnapshot)
        guard let callbackURL = makeShortcutCallbackURL(noteID: noteID, status: "success") else {
            finishBatchAttempt(for: noteID, continueBatch: true)
            return
        }
        guard let cancelURL = makeShortcutCallbackURL(noteID: noteID, status: "cancel") else {
            finishBatchAttempt(for: noteID, continueBatch: true)
            return
        }
        guard let errorURL = makeShortcutCallbackURL(noteID: noteID, status: "error") else {
            finishBatchAttempt(for: noteID, continueBatch: true)
            return
        }

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: Self.titleShortcutName),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: shortcutInput),
            URLQueryItem(name: "x-success", value: callbackURL.absoluteString),
            URLQueryItem(name: "x-cancel", value: cancelURL.absoluteString),
            URLQueryItem(name: "x-error", value: errorURL.absoluteString)
        ]

        guard let url = components.url else {
            finishBatchAttempt(for: noteID, continueBatch: true)
            return
        }

        pendingShortcutTitleNoteIDs.insert(noteID)
        clipboardPendingNoteID = noteID
        lastClipboardSnapshot = currentClipboardString() ?? ""
        scheduleShortcutTimeout(for: noteID)
        openURL(url) { accepted in
            if !accepted {
                handleShortcutMissingInstall(
                    detail: "Could not open Shortcuts. Please install or enable Shortcuts support."
                )
            }
        }
    }

    private func makeShortcutCallbackURL(noteID: UUID, status: String) -> URL? {
        var components = URLComponents()
        components.scheme = "autoarchivesnotes"
        components.host = "title-callback"
        components.queryItems = [
            URLQueryItem(name: "noteID", value: noteID.uuidString),
            URLQueryItem(name: "status", value: status)
        ]
        return components.url
    }

    private func handleShortcutCallbackURL(_ url: URL) {
        guard url.scheme?.lowercased() == "autoarchivesnotes" else { return }
        guard url.host == "title-callback" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        let noteIDValue = valueForQueryItem(named: "noteID", in: components)
        guard
            let noteIDValue,
            let noteID = UUID(uuidString: noteIDValue)
        else { return }

        let status = valueForQueryItem(named: "status", in: components)?.lowercased() ?? "success"
        if status == "error" {
            let errorMessage = valueForQueryItem(named: "errorMessage", in: components)
            if shouldPromptForInstall(fromErrorMessage: errorMessage) {
                handleShortcutMissingInstall(detail: errorMessage)
                return
            }
            completePendingShortcut(for: noteID)
            return
        }
        guard status == "success" else {
            completePendingShortcut(for: noteID)
            return
        }

        let result = valueForQueryItem(named: "result", in: components)
        if applyShortcutResult(noteID: noteID, rawResult: result) {
            completePendingShortcut(for: noteID)
            return
        }

        attemptClipboardFallbackIfNeeded()
        if pendingShortcutTitleNoteIDs.contains(noteID) {
            // Some shortcut flows populate clipboard slightly after callback delivery.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard pendingShortcutTitleNoteIDs.contains(noteID) else { return }
                attemptClipboardFallbackIfNeeded()
            }
        }
    }

    private func valueForQueryItem(named name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func makeShortcutInput(noteBody: String) -> String {
        Self.titleGenerationPrompt + "\n" + noteBody
    }

    private func finishBatchAttempt(for noteID: UUID, continueBatch: Bool) {
        if let i = titleBatchQueue.firstIndex(of: noteID) {
            titleBatchQueue.remove(at: i)
        }
        pendingShortcutTitleNoteIDs.remove(noteID)
        if clipboardPendingNoteID == noteID {
            clipboardPendingNoteID = nil
        }
        if continueBatch {
            runTitleShortcutForNextInBatch()
        }
    }

    private func completePendingShortcut(for noteID: UUID) {
        shortcutCallbackTimeoutTask?.cancel()
        shortcutCallbackTimeoutTask = nil
        finishBatchAttempt(for: noteID, continueBatch: true)
    }

    private var shortcutInstallURL: URL? {
        let trimmed = Self.titleShortcutInstallURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private func shouldPromptForInstall(fromErrorMessage errorMessage: String?) -> Bool {
        let text = (errorMessage ?? "").lowercased()
        if text.isEmpty { return true }
        if text.contains("not found") { return true }
        if text.contains("could not find") { return true }
        if text.contains("no shortcut") { return true }
        if text.contains("isn't a shortcut") { return true }
        return false
    }

    private func handleShortcutMissingInstall(detail: String?) {
        shortcutCallbackTimeoutTask?.cancel()
        shortcutCallbackTimeoutTask = nil
        pendingShortcutTitleNoteIDs.removeAll()
        titleBatchQueue.removeAll()
        clipboardPendingNoteID = nil

        if shortcutInstallURL != nil {
            shortcutInstallAlertMessage = "You need to install the '\(Self.titleShortcutName)' shortcut before using this feature."
        } else {
            shortcutInstallAlertMessage = "You need the '\(Self.titleShortcutName)' shortcut for this feature. Set the iCloud install link in code first."
        }

        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shortcutInstallAlertMessage += "\n\n\(detail)"
        }

        isShowingShortcutInstallAlert = true
    }

    private func scheduleShortcutTimeout(for noteID: UUID) {
        shortcutCallbackTimeoutTask?.cancel()
        shortcutCallbackTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: Self.shortcutCallbackTimeoutNanos)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard pendingShortcutTitleNoteIDs.contains(noteID) else { return }
                finishBatchAttempt(for: noteID, continueBatch: true)
                shortcutInstallAlertMessage = "Shortcuts did not return usable metadata. Ensure '\(Self.titleShortcutName)' outputs JSON text and also copies it to clipboard."
                isShowingShortcutInstallAlert = true
            }
        }
    }

    private func attemptClipboardFallbackIfNeeded() {
        guard let noteID = clipboardPendingNoteID else { return }
        guard pendingShortcutTitleNoteIDs.contains(noteID) else { return }
        guard let latest = currentClipboardString() else { return }

        let normalizedLatest = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLatest.isEmpty else { return }
        guard normalizedLatest != lastClipboardSnapshot else { return }

        if applyShortcutResult(noteID: noteID, rawResult: normalizedLatest) {
            shortcutCallbackTimeoutTask?.cancel()
            shortcutCallbackTimeoutTask = nil
            finishBatchAttempt(for: noteID, continueBatch: true)
        }
    }

    private func currentClipboardString() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }

    private struct ShortcutMetadataPayload: Decodable {
        var title: String?
        var summary: String?
    }

    private func parseShortcutPayload(from raw: String?) -> ShortcutMetadataPayload? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let jsonString = extractJSONObject(from: trimmed) ?? trimmed
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ShortcutMetadataPayload.self, from: data)
    }

    private func applyShortcutResult(noteID: UUID, rawResult: String?) -> Bool {
        let payload = parseShortcutPayload(from: rawResult)
        let candidateTitle = payload?.title ?? rawResult

        guard
            let normalized = normalizeGeneratedTitle(candidateTitle),
            let index = notes.firstIndex(where: { $0.id == noteID }),
            isPlaceholderTitle(notes[index].title)
        else {
            return false
        }

        notes[index].title = normalized
        if let summary = normalizeGeneratedSummary(payload?.summary) {
            let updatedBody = mergeSummary(summary, into: notes[index].body)
            notes[index].body = updatedBody
            if selectedNoteID == noteID {
                workingBody = updatedBody
            }
        }
        if selectedNoteID == noteID, isPlaceholderTitle(workingTitle) {
            workingTitle = normalized
        }
        return true
    }

    private func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{") else { return nil }
        var depth = 0
        var cursor = start

        while cursor < raw.endIndex {
            let ch = raw[cursor]
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let end = raw.index(after: cursor)
                    return String(raw[start..<end])
                }
            }
            cursor = raw.index(after: cursor)
        }
        return nil
    }

    private func normalizeGeneratedSummary(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
        return cleaned.count >= 8 ? cleaned : nil
    }

    private func mergeSummary(_ summary: String, into body: String) -> String {
        let existing = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryLine = "Summary: \(summary)"
        if existing.localizedCaseInsensitiveContains(summary) { return body }
        if existing.isEmpty { return summaryLine }
        return existing + "\n\n" + summaryLine
    }

    private func normalizeGeneratedTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`.,:;!?"))

        let words = cleaned
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        guard words.count >= 3 else { return nil }

        let normalized = words.prefix(5).joined(separator: " ")

        if let first = normalized.first, first.isLetter, String(first) == String(first).lowercased() {
            return String(first).uppercased() + normalized.dropFirst()
        }
        return normalized.isEmpty ? nil : normalized
    }

    private func isPlaceholderTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("Untitled") == .orderedSame
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private enum SidebarSection: CaseIterable {
    case allNotes
    case today
    case starred
    case archived

    var label: String {
        switch self {
        case .allNotes: return "All Notes"
        case .today: return "Today"
        case .starred: return "Starred"
        case .archived: return "Archived"
        }
    }

    var icon: String {
        switch self {
        case .allNotes: return "square.grid.2x2"
        case .today: return "calendar"
        case .starred: return "star"
        case .archived: return "archivebox"
        }
    }
}

private struct NoteItem: Identifiable {
    let id: UUID
    var title: String
    var body: String
    var shortDate: String

    init(id: UUID = UUID(), title: String, body: String, shortDate: String) {
        self.id = id
        self.title = title
        self.body = body
        self.shortDate = shortDate
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var preview: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No additional text yet." : trimmed
    }

    static let samples: [NoteItem] = [
        NoteItem(
            title: "Studio Notes",
            body: """
            Clean structure wins:

            - Keep each idea in one paragraph.
            - Prefer short headlines over decorative labels.
            - Use whitespace as a rhythm tool.

            iPad pass:
            build around focus mode and remove secondary UI noise.
            """,
            shortDate: "Feb 24"
        ),
        NoteItem(
            title: "Reading List",
            body: """
            Reading queue:

            1. Interface writing systems
            2. Better typography on tablets
            3. Productive meeting notes

            Tag each with: skim, deep, or archive.
            """,
            shortDate: "Feb 23"
        ),
        NoteItem(
            title: "Weekly Plan",
            body: """
            Monday to Friday:

            Morning: focused work blocks
            Midday: review and triage
            Afternoon: collaboration and edits

            Keep one open slot daily for unplanned work.
            """,
            shortDate: "Feb 22"
        )
    ]
}

#Preview {
    ContentView()
}

private struct SectionChip: View {
    let section: SidebarSection
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18)
            Text(section.label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.82) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(isSelected ? 0.08 : 0), lineWidth: 1)
        )
        .foregroundStyle(Color.black.opacity(isSelected ? 0.85 : 0.55))
    }
}

private struct NoteCard: View {
    let note: NoteItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.displayTitle)
                    .lineLimit(1)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.88))
                Spacer()
                Text(note.shortDate)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.4))
            }
            Text(note.preview)
                .lineLimit(2)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.52))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.black.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }
}
