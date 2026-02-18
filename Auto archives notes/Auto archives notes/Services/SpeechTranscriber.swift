//
//  SpeechTranscriber.swift
//  Auto archives notes
//
//  Record audio to a file, then transcribe the file using Apple's Speech framework.
//  This avoids the fragility of live/streaming dictation sessions.
//

import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
final class SpeechTranscriber: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum TranscriberError: Error, LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case recordingFailed
        case missingRecording
        case transcriptionFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition or microphone permission not granted."
            case .recognizerUnavailable:
                return "Speech recognizer is unavailable on this device."
            case .recordingFailed:
                return "Failed to start audio recording."
            case .missingRecording:
                return "No audio recording found to transcribe."
            case .transcriptionFailed:
                return "Transcription failed."
            }
        }
    }

    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var recordingSeconds: TimeInterval = 0
    @Published var liveText: String = ""
    @Published var finalText: String = ""
    @Published var lastError: String?

    var transcript: String {
        let a = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return liveText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recorder: AVAudioRecorder?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()
    private var audioURL: URL?
    private var startedAt: Date?
    private var clockTask: Task<Void, Never>?

    func reset() {
        cancel()
        isRecording = false
        isTranscribing = false
        recordingSeconds = 0
        liveText = ""
        finalText = ""
        lastError = nil
        audioURL = nil
        startedAt = nil
    }

    func startRecording() async {
        if isRecording || isTranscribing { return }
        lastError = nil
        liveText = ""
        finalText = ""

        do {
            try await ensureMicPermission()
            try startRecorder()
            isRecording = true
            startedAt = Date()
            startClock()
        } catch {
            isRecording = false
            stopClock()
            stopRecorder()
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    func stopRecordingAndTranscribe() async throws -> String {
        if !isRecording { throw TranscriberError.missingRecording }

        stopClock()
        stopRecorder()
        isRecording = false

        guard let url = audioURL else { throw TranscriberError.missingRecording }

        isTranscribing = true
        lastError = nil
        liveText = ""
        finalText = ""

        do {
            try await ensureSpeechPermission()
            let text = try await transcribeFile(at: url)
            finalText = text
            liveText = ""
            isTranscribing = false
            cleanupRecording()
            return text
        } catch {
            isTranscribing = false
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            cleanupRecording()
            throw error
        }
    }

    func cancel() {
        stopClock()

        recognitionTask?.cancel()
        recognitionTask = nil

        stopRecorder()

        isRecording = false
        isTranscribing = false
    }

    // MARK: - Permissions

    private func ensureMicPermission() async throws {
        let ok = await requestMicPermission()
        if !ok { throw TranscriberError.notAuthorized }
    }

    private func ensureSpeechPermission() async throws {
        let ok = await requestSpeechPermission()
        if !ok { throw TranscriberError.notAuthorized }
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

    // MARK: - Recording

    private func startRecorder() throws {
        stopRecorder()

        #if os(iOS) || os(visionOS)
        try activateAudioSession()
        #endif

        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("dictation-\(UUID().uuidString).m4a")
        audioURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self
        r.isMeteringEnabled = false
        r.prepareToRecord()
        if !r.record() {
            throw TranscriberError.recordingFailed
        }
        recorder = r
    }

    private func stopRecorder() {
        recorder?.stop()
        recorder = nil

        #if os(iOS) || os(visionOS)
        deactivateAudioSession()
        #endif
    }

    private func cleanupRecording() {
        guard let url = audioURL else { return }
        audioURL = nil
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Transcription

    private func transcribeFile(at url: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriberError.recognizerUnavailable
        }

        return try await withCheckedThrowingContinuation { cont in
            var finished = false

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            recognitionTask?.cancel()
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    let partial = result.bestTranscription.formattedString
                    Task { @MainActor in
                        // During file transcription, bestTranscription is the full transcript so far.
                        self.liveText = partial
                        if result.isFinal {
                            self.finalText = partial
                            self.liveText = ""
                        }
                    }

                    if result.isFinal, !finished {
                        finished = true
                        cont.resume(returning: partial.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                if let error, !finished {
                    finished = true
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Clock

    private func startClock() {
        stopClock()
        clockTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { break }
                if !self.isRecording { break }
                let elapsed = Date().timeIntervalSince(self.startedAt ?? Date())
                await MainActor.run {
                    self.recordingSeconds = max(0, elapsed)
                }
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    // MARK: - iOS/visionOS audio session

    #if os(iOS) || os(visionOS)
    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [])
        try session.setActive(true, options: [])
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [])
    }
    #endif
}
