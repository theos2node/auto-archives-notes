//
//  ComposerView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct ComposerView: View {
    @Environment(\.modelContext) private var modelContext

    let enhancer: NoteEnhancer
    var onGoToMenu: (() -> Void)?
    var onSubmitted: (() -> Void)?
    var startRecordingOnAppear: Bool = false

    @State private var rawText: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @FocusState private var isEditorFocused: Bool
    private let minimumProcessingTime: Duration = .seconds(3)

    @StateObject private var transcriber = SpeechTranscriber()

    var body: some View {
        NotionPage(topBar: AnyView(topBar)) {
            NotionCard {
                editor
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)

                Divider().opacity(0.65)

                HStack(spacing: 10) {
                    Text("Cmd+Enter to submit")
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)
                    Spacer()
                    if isSubmitting {
                        Text("Enhancing in background…")
                            .font(.caption)
                            .foregroundStyle(NotionStyle.textSecondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .padding(.top, 8)
        }
        .onAppear {
            if startRecordingOnAppear {
                Task { await toggleRecording() }
            } else {
                // Ensure focus lands inside the TextEditor after the view is on-screen.
                Task { @MainActor in isEditorFocused = true }
            }
        }
        .alert("Submit failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        ), actions: {
            Button("OK", role: .cancel) { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                onGoToMenu?()
            } label: {
                Text("Main menu")
            }
            .buttonStyle(NotionPillButtonStyle(prominent: false))

            Spacer()

            Button {
                Task { await toggleRecording() }
            } label: {
                Image(systemName: transcriber.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(transcriber.isRecording ? Color.white : Color.black.opacity(0.88))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(transcriber.isRecording ? Color.red.opacity(0.9) : Color.black.opacity(0.06))
                    )
            }
            .disabled(isSubmitting || transcriber.isTranscribing)
            .help(transcriber.isRecording ? "Stop recording and transcribe" : "Start recording")

            Button {
                submit()
            } label: {
                if isSubmitting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Submitting")
                    }
                } else {
                    Text("Submit")
                }
            }
            .buttonStyle(NotionPillButtonStyle(prominent: true))
            .disabled(
                isSubmitting
                    || transcriber.isRecording
                    || transcriber.isTranscribing
                    || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var editor: some View {
        Group {
            if transcriber.isRecording {
                recordingDisplay
            } else if transcriber.isTranscribing {
                transcribingDisplay
            } else {
                typingEditor
            }
        }
    }

    private var typingEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $rawText)
                .focused($isEditorFocused)
                .font(.system(size: 16, weight: .regular, design: .default))
                .scrollContentBackground(.hidden)
                .background(.clear)
                .disabled(isSubmitting)

            if rawText.isEmpty {
                Text("Type anything…")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundStyle(NotionStyle.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
            }
        }
    }

    private var transcriptDisplay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Transcribing…")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                if let err = transcriber.lastError, !err.isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NotionStyle.fillSubtleHover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            ScrollView {
                Text(transcriber.transcript.isEmpty ? "Processing recording…" : transcriber.transcript)
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .lineSpacing(4)
                    .foregroundStyle(transcriber.transcript.isEmpty ? NotionStyle.textSecondary : NotionStyle.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 280)
        }
    }

    private var recordingDisplay: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 10, height: 10)
                Text("Recording…")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
                Spacer()
                Text(formatTime(transcriber.recordingSeconds))
                    .font(.caption)
                    .foregroundStyle(NotionStyle.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NotionStyle.fillSubtleHover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Tap the microphone again to stop and transcribe.")
                .font(.system(size: 16, weight: .regular, design: .default))
                .lineSpacing(4)
                .foregroundStyle(NotionStyle.textPrimary)
        }
        .frame(minHeight: 280, alignment: .top)
    }

    private var transcribingDisplay: some View {
        transcriptDisplay
    }

    private func toggleRecording() async {
        if transcriber.isTranscribing { return }

        if transcriber.isRecording {
            isEditorFocused = false
            let existing = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let t = try await transcriber.stopRecordingAndTranscribe()
                let newText = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newText.isEmpty {
                    if existing.isEmpty {
                        rawText = newText
                    } else {
                        rawText = existing + "\n\n" + newText
                    }
                }
                isEditorFocused = true
            } catch {
                errorMessage = transcriber.lastError ?? (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                isEditorFocused = true
            }
            return
        }

        // Start recording.
        isEditorFocused = false
        transcriber.reset()
        await transcriber.startRecording()

        if !transcriber.isRecording, let err = transcriber.lastError, !err.isEmpty {
            errorMessage = err
            isEditorFocused = true
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    private func submit() {
        if isSubmitting { return }
        let input = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return }

        isSubmitting = true
        errorMessage = nil
        rawText = ""
        isEditorFocused = false

        // Create immediately so the dashboard updates, then patch it once enhancement completes.
        let noteID = UUID()
        let note = Note(
            id: noteID,
            isEnhancing: true,
            enhancementError: nil,
            rawText: input,
            title: "",
            emoji: "",
            tags: [],
            enhancedText: "Enhancing with on-device intelligence…\n\nGive it a minute.",
            kind: .idea,
            status: .inbox,
            priority: .p3,
            area: .other,
            project: "",
            people: [],
            dueAt: nil,
            summary: "",
            actionItems: [],
            links: []
        )
        modelContext.insert(note)
        do { try modelContext.save() } catch { /* non-fatal */ }

        // Immediately return the user to the main menu, while enhancement continues in the background.
        onSubmitted?()

        Task {
            let clock = ContinuousClock()
            let startedAt = clock.now
            do {
                let enhancement = try await enhancer.enhance(rawText: input)
                let elapsed = clock.now - startedAt
                if elapsed < minimumProcessingTime {
                    try? await Task.sleep(for: minimumProcessingTime - elapsed)
                }

                await MainActor.run {
                    do {
                        let fetch = FetchDescriptor<Note>(
                            predicate: #Predicate { $0.id == noteID }
                        )
                        if let note = try modelContext.fetch(fetch).first {
                            note.title = enhancement.title
                            note.emoji = enhancement.emoji
                            note.tags = enhancement.tags
                            note.enhancedText = enhancement.correctedText
                            note.kind = enhancement.kind
                            note.status = enhancement.status
                            note.priority = enhancement.priority
                            note.area = enhancement.area
                            note.project = enhancement.project
                            note.people = enhancement.people
                            note.dueAt = enhancement.dueAt
                            note.summary = enhancement.summary
                            note.actionItems = enhancement.actionItems
                            note.links = enhancement.links
                            note.isEnhancing = false
                            note.enhancementError = nil
                            try? modelContext.save()
                        }
                    } catch {
                        // If fetch fails, just ignore; note remains in enhancing state.
                    }
                }

                await MainActor.run {
                    isSubmitting = false
                    isEditorFocused = true
                }
            } catch {
                await MainActor.run {
                    // Keep the raw note, but mark it failed and show original.
                    do {
                        let fetch = FetchDescriptor<Note>(
                            predicate: #Predicate { $0.id == noteID }
                        )
                        if let note = try modelContext.fetch(fetch).first {
                            note.isEnhancing = false
                            note.enhancementError = String(describing: error)
                            note.enhancedText = note.rawText
                            try? modelContext.save()
                        }
                    } catch {
                        // ignore
                    }

                    isSubmitting = false
                    isEditorFocused = true
                    errorMessage = String(describing: error)
                }
            }
        }
    }
}
