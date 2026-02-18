//
//  ComposerView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct ComposerView: View {
    @Environment(\.modelContext) private var modelContext

    let enhancer: NoteEnhancer
    var onSubmitted: (() -> Void)?

    @State private var rawText: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @FocusState private var isEditorFocused: Bool
    private let minimumProcessingTime: Duration = .seconds(1.5)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                editor
                footer
            }

            if isSubmitting {
                processingOverlay
                    .transition(.opacity)
            }
        }
        .onAppear { isEditorFocused = true }
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Capture")
                .font(.system(.title2, design: .rounded).weight(.semibold))

            Text("Type anything. No title. No structure.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                submit()
            } label: {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Submit")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $rawText)
                .focused($isEditorFocused)
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(.clear)
                .disabled(isSubmitting)

            if rawText.isEmpty {
                Text("Write a thought, an idea, a to-do, anything…")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 22)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isSubmitting {
                Text("Thinking harder (max effort)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Cmd+Enter to submit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !rawText.isEmpty {
                Button("Clear") { rawText = "" }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    private var processingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)

            Text("Enhancing your note…")
                .font(.system(.headline, design: .rounded))

            Text("Give it a minute. I’d rather be good than fast.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
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
        let note = Note(
            isEnhancing: true,
            enhancementError: nil,
            rawText: input,
            title: "",
            emoji: "",
            tags: [],
            enhancedText: "Enhancing with on-device intelligence…\n\nGive it a minute."
        )
        modelContext.insert(note)
        do { try modelContext.save() } catch { /* non-fatal */ }

        Task { @MainActor in
            let clock = ContinuousClock()
            let startedAt = clock.now
            do {
                let enhancement = try await enhancer.enhance(rawText: input)
                let elapsed = clock.now - startedAt
                if elapsed < minimumProcessingTime {
                    try? await Task.sleep(for: minimumProcessingTime - elapsed)
                }

                note.title = enhancement.title
                note.emoji = enhancement.emoji
                note.tags = enhancement.tags
                note.enhancedText = enhancement.correctedText
                note.isEnhancing = false
                note.enhancementError = nil
                do { try modelContext.save() } catch { /* non-fatal */ }

                isSubmitting = false
                isEditorFocused = true
                onSubmitted?()
            } catch {
                // Keep the raw note, but mark it failed and show original.
                note.isEnhancing = false
                note.enhancementError = String(describing: error)
                note.enhancedText = note.rawText
                do { try modelContext.save() } catch { /* non-fatal */ }

                isSubmitting = false
                isEditorFocused = true
                errorMessage = String(describing: error)
            }
        }
    }
}
