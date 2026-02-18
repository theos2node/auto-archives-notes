//
//  NewNoteView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

struct NewNoteView: View {
    @Environment(\.modelContext) private var modelContext

    let enhancer: NoteEnhancer

    @State private var rawText: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var onSubmitted: ((Note) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            editor
            bottomBar
        }
        .navigationTitle("New")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Submit")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(isSubmitting || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Submit failed", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "")
        })
    }

    private var editor: some View {
        TextEditor(text: $rawText)
            .font(.system(.body, design: .rounded))
            .padding(16)
            .overlay(alignment: .topLeading) {
                if rawText.isEmpty {
                    Text("Type anything…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 24)
                }
            }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if isSubmitting {
                Text("Enhancing with on-device intelligence…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Cmd+Enter to submit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                    onSubmitted?(note)
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

