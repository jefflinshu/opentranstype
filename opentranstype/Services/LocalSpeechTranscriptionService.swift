import AVFoundation
import Foundation

@MainActor
final class LocalSpeechTranscriptionService: NSObject, AVAudioRecorderDelegate {
    private var whisperContext: WhisperContext?
    private var loadedModelURL: URL?
    private let recorder = AudioRecorder()
    private var recordedFile: URL?

    private static let noiseTokens: Set<String> = [
        "[BLANK_AUDIO]",
        "[SILENCE]",
        "(silence)",
        "[Music]",
        "[MUSIC]",
        "(Music)",
        "(music)",
        "[noise]",
        "[NOISE]",
        "(noise)"
    ]

    private(set) var isRecording = false

    func prepareModel(at modelURL: URL) async throws {
        guard loadedModelURL != modelURL || whisperContext == nil else {
            return
        }

        whisperContext = try WhisperContext.createContext(path: modelURL.path)
        loadedModelURL = modelURL
        DiagnosticLog.write("local speech model loaded path=\(modelURL.path)")
    }

    func startRecording() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw LocalSpeechError.microphonePermissionDenied
        }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("transtype_voice_input.wav")
        try? FileManager.default.removeItem(at: fileURL)
        recordedFile = fileURL
        try await recorder.startRecording(toOutputFile: fileURL, delegate: self)
        isRecording = true
        DiagnosticLog.write("local voice recording started")
    }

    func stopRecordingAndTranscribe(language: String? = nil, initialPrompt: String? = nil) async -> String? {
        await recorder.stopRecording()
        isRecording = false

        guard let recordedFile,
              let whisperContext else {
            return nil
        }

        do {
            let samples = try decodeWaveFile(recordedFile)
            let peak = samples.map { abs($0) }.max() ?? 0
            DiagnosticLog.write("local voice decoded samples=\(samples.count), peak=\(peak)")
            await whisperContext.fullTranscribe(samples: samples, language: language, initialPrompt: initialPrompt)
            let rawText = await whisperContext.getTranscription()
            let cleanedText = Self.clean(rawText)
            DiagnosticLog.write("local voice transcription length=\(cleanedText?.count ?? 0)")
            return cleanedText
        } catch {
            DiagnosticLog.write("local voice transcription failed error=\(error.localizedDescription)")
            return nil
        }
    }

    private static func clean(_ rawText: String) -> String? {
        var result = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty,
              !noiseTokens.contains(result) else {
            return nil
        }

        for token in noiseTokens {
            result = result.replacingOccurrences(of: token, with: "")
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            Task { @MainActor in
                DiagnosticLog.write("local voice recording encode error=\(error.localizedDescription)")
            }
        }
    }
}

enum LocalSpeechError: LocalizedError {
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return String(localized: "Microphone access denied")
        }
    }
}
