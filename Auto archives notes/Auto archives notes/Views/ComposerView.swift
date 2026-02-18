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

    var body: some View {
        VStack(spacing: 0) {
            header
            editor
            footer
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

    private func submit() {
        if isSubmitting { return }
        let input = rawText

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let enhancement = try await enhancer.enhance(rawText: input)
                let note = Note(
                    rawText: input,
                    title: enhancement.title,
                    emoji: enhancement.emoji,
                    tags: enhancement.tags,
                    enhancedText: enhancement.correctedText
                )
                modelContext.insert(note)
                try modelContext.save()

                await MainActor.run {
                    rawText = ""
                    isSubmitting = false
                    isEditorFocused = true
                    onSubmitted?()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = String(describing: error)
                }
            }
        }
    }
}

