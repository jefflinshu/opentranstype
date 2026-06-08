import Foundation
import whisper

enum WhisperError: Error {
    case couldNotInitializeContext
}

actor WhisperContext {
    private var context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func fullTranscribe(samples: [Float], language: String? = nil, initialPrompt: String? = nil) {
        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        let lang = language ?? "auto"

        func run(langPtr: UnsafePointer<CChar>, promptPtr: UnsafePointer<CChar>?) {
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_realtime = false
            params.print_progress = false
            params.print_timestamps = false
            params.print_special = false
            params.translate = false
            params.language = langPtr
            params.n_threads = Int32(maxThreads)
            params.offset_ms = 0
            params.no_context = true
            params.single_segment = false
            params.initial_prompt = promptPtr

            whisper_reset_timings(context)
            samples.withUnsafeBufferPointer { buffer in
                if whisper_full(context, params, buffer.baseAddress, Int32(buffer.count)) != 0 {
                    DiagnosticLog.write("whisper transcription failed")
                }
            }
        }

        let effectivePrompt = initialPrompt.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }

        lang.withCString { langPtr in
            if let effectivePrompt {
                effectivePrompt.withCString {
                    run(langPtr: langPtr, promptPtr: $0)
                }
            } else {
                run(langPtr: langPtr, promptPtr: nil)
            }
        }
    }

    func getTranscription() -> String {
        var transcription = ""
        for index in 0..<whisper_full_n_segments(context) {
            transcription += String(cString: whisper_full_get_segment_text(context, index))
        }
        return transcription
    }

    static func createContext(path: String) throws -> WhisperContext {
        var params = whisper_context_default_params()
        params.flash_attn = false

        guard let context = whisper_init_from_file_with_params(path, params) else {
            DiagnosticLog.write("whisper model load failed path=\(path)")
            throw WhisperError.couldNotInitializeContext
        }

        return WhisperContext(context: context)
    }
}
