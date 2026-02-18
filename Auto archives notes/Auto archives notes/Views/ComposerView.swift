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

    @State private var rawText: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @FocusState private var isEditorFocused: Bool
    private let minimumProcessingTime: Duration = .seconds(3)

    var body: some View {
        VStack(spacing: 0) {
            editor
            bottomBar
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
        .padding(18)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                onGoToMenu?()
            } label: {
                Text("Main menu")
            }
            .buttonStyle(.bordered)

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
        .padding(.vertical, 14)
        .background(.thinMaterial)
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

        // Immediately return the user to the main menu, while enhancement continues in the background.
        onSubmitted?()

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
