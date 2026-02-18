//
//  SpeechTranscriber.swift
//  Auto archives notes
//

import Foundation
import AVFoundation
import Speech
import SwiftUI
import Combine

@MainActor
final class SpeechTranscriber: ObservableObject {
    enum TranscriberError: Error, LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case audioEngineFailure

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition or microphone permission not granted."
            case .recognizerUnavailable:
                return "Speech recognizer is unavailable on this device."
            case .audioEngineFailure:
                return "Audio engine failed to start."
            }
        }
    }

    @Published var isRecording: Bool = false
    @Published var liveText: String = ""
    @Published var finalText: String = ""
    @Published var lastError: String?

    var transcript: String {
        let a = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()

    // Roll the request periodically to avoid very long single-request sessions.
    private var rollingTask: Task<Void, Never>?
    private let rollInterval: Duration = .seconds(50)

    func reset() {
        liveText = ""
        finalText = ""
        lastError = nil
    }

    func start() async {
        if isRecording { return }
        lastError = nil

        do {
            try await ensurePermissions()
            try startEngine()
            isRecording = true
            startRolling()
        } catch {
            isRecording = false
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            stopEngine()
        }
    }

    func stop() {
        if !isRecording { return }
        rollingTask?.cancel()
        rollingTask = nil

        // Flush live into final.
        let live = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty {
            if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finalText = live
            } else {
                finalText += " " + live
            }
        }
        liveText = ""

        isRecording = false
        stopEngine()
    }

    private func ensurePermissions() async throws {
        let micOK = await requestMicPermission()
        guard micOK else { throw TranscriberError.notAuthorized }

        let speechOK = await requestSpeechPermission()
        guard speechOK else { throw TranscriberError.notAuthorized }

        guard recognizer?.isAvailable == true else { throw TranscriberError.recognizerUnavailable }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    private func startEngine() throws {
        // Clean up any previous run.
        stopEngine()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation

        if recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }

        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw TranscriberError.audioEngineFailure
        }

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.liveText = result.bestTranscription.formattedString
                if result.isFinal {
                    self.commitSegment()
                }
            }
            if let error {
                // Don't hard-fail if we're actively recording; store error and try to roll.
                self.lastError = error.localizedDescription
            }
        }
    }

    private func stopEngine() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func commitSegment() {
        let seg = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        if seg.isEmpty { return }
        if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalText = seg
        } else {
            finalText += " " + seg
        }
        liveText = ""
    }

    private func startRolling() {
        rollingTask?.cancel()
        rollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: rollInterval)
                if Task.isCancelled { break }
                if !self.isRecording { break }

                // Roll the request/task to keep the session healthy.
                self.commitSegment()
                do {
                    try self.rollRecognitionRequest()
                } catch {
                    self.lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                }
            }
        }
    }

    private func rollRecognitionRequest() throws {
        // Swap to a new request while keeping the audio engine tap running.
        task?.cancel()
        task = nil
        request?.endAudio()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        if recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.liveText = result.bestTranscription.formattedString
                if result.isFinal {
                    self.commitSegment()
                }
            }
            if let error {
                self.lastError = error.localizedDescription
            }
        }
    }
}
