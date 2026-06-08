import AVFoundation
import Foundation

actor AudioRecorder {
    private var recorder: AVAudioRecorder?

    enum RecorderError: Error {
        case couldNotStartRecording
    }

    func startRecording(toOutputFile url: URL, delegate: AVAudioRecorderDelegate?) throws {
        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: recordSettings)
        recorder.delegate = delegate
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw RecorderError.couldNotStartRecording
        }

        self.recorder = recorder
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
    }
}
