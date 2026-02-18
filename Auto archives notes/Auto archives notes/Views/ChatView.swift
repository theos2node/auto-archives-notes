//
//  ChatView.swift
//  Auto archives notes
//

import SwiftUI
import SwiftData

private struct ChatTurn: Identifiable, Sendable {
    var id = UUID()
    var question: String
    var answer: String
    var matchedNoteIDs: [UUID]
    var createdAt: Date = Date()
}

struct ChatView: View {
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    var onGoToMenu: (() -> Void)?
    var onOpenNote: ((UUID) -> Void)?
    var onNewNote: (() -> Void)?

    @State private var turns: [ChatTurn] = []
    @State private var draft: String = ""
    @State private var isThinking: Bool = false
    @State private var errorMessage: String?

    @FocusState private var isInputFocused: Bool

    private let assistant = NoteChatAssistant()

    var body: some View {
        NotionPage(topBar: AnyView(topBar)) {
            NotionCard {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)

                    Divider().opacity(0.65)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                if turns.isEmpty {
                                    empty
                                        .padding(.top, 14)
                                }

                                ForEach(turns) { turn in
                                    chatTurn(turn)
                                        .id(turn.id)
                                }

                                if isThinking {
                                    HStack(spacing: 10) {
                                        ProgressView().controlSize(.small)
                                        Text("Thinking…")
                                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                            .foregroundStyle(Color.black.opacity(0.8))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(NotionStyle.fillSubtleHover, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }

                                Color.clear.frame(height: 4).id("bottom")
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: turns.count) { _, _ in
                            withAnimation(.snappy(duration: 0.18)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }

                    Divider().opacity(0.65)

                    composer
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                }
            }
            .padding(.top, 8)
        }
        .onAppear { isInputFocused = true }
        .alert("Chat error", isPresented: Binding(
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
                onNewNote?()
            } label: {
                Text("New note")
            }
            .buttonStyle(NotionPillButtonStyle(prominent: true))
            .keyboardShortcut("n", modifiers: [.command])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chat")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(NotionStyle.textPrimary)
            Text("Ask questions, retrieve notes, and get grounded answers based on what you wrote.")
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(NotionStyle.textSecondary)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try:")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.8))
            VStack(alignment: .leading, spacing: 6) {
                Text("• What are my open tasks for project X?")
                Text("• What did I say about Y?")
                Text("• Summarize my notes about onboarding.")
            }
            .font(.system(.subheadline, design: .default))
            .foregroundStyle(Color.black.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(NotionStyle.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chatTurn(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // User
            HStack {
                Spacer()
                Text(turn.question)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .lineSpacing(3)
                    .foregroundStyle(NotionStyle.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: 560, alignment: .trailing)
            }

            // Assistant
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.black.opacity(0.55))
                    Text("Answer")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.8))
                    Spacer()
                    Text(turn.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(NotionStyle.textSecondary)
                }

                Text(turn.answer)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .lineSpacing(3)
                    .foregroundStyle(NotionStyle.textPrimary)
                    .textSelection(.enabled)

                if !turn.matchedNoteIDs.isEmpty {
                    Divider().opacity(0.55)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Matches")
                            .font(.caption)
                            .foregroundStyle(NotionStyle.textSecondary)

                        ForEach(matchedNotes(for: turn.matchedNoteIDs)) { note in
                            Button {
                                onOpenNote?(note.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(note.displayEmoji)
                                        .frame(width: 24, alignment: .leading)
                                    Text(note.displayTitle)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(NotionStyle.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(note.kind.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(NotionStyle.textSecondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(NotionStyle.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(NotionStyle.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func matchedNotes(for ids: [UUID]) -> [Note] {
        var byID: [UUID: Note] = [:]
        byID.reserveCapacity(min(notes.count, 200))
        for n in notes { byID[n.id] = n }
        return ids.compactMap { byID[$0] }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask your notes…", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .disabled(isThinking)
                .onSubmit { send() }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(NotionStyle.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(NotionStyle.line, lineWidth: 1)
                )

            Button {
                send()
            } label: {
                if isThinking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Send")
                }
            }
            .buttonStyle(NotionPillButtonStyle(prominent: true))
            .disabled(isThinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty || isThinking { return }

        draft = ""
        isInputFocused = false
        isThinking = true
        errorMessage = nil

        Task {
            let resp = await assistant.respond(question: q, notes: notes)
            await MainActor.run {
                turns.append(ChatTurn(question: q, answer: resp.answer, matchedNoteIDs: resp.matchedNoteIDs))
                isThinking = false
                isInputFocused = true
            }
        }
    }
}
