import AppKit
import Combine
import Foundation

struct LocalSpeechModel: Identifiable, Equatable {
    let id: String
    let name: String
    let size: String
    let detail: String
    let filename: String
    let url: URL

    static let available: [LocalSpeechModel] = [
        LocalSpeechModel(
            id: "tiny-en",
            name: "Whisper tiny.en",
            size: "75 MB",
            detail: "English, fastest",
            filename: "ggml-tiny.en.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!
        ),
        LocalSpeechModel(
            id: "base-en",
            name: "Whisper base.en",
            size: "142 MB",
            detail: "English, balanced",
            filename: "ggml-base.en.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!
        ),
        LocalSpeechModel(
            id: "small-en",
            name: "Whisper small.en",
            size: "466 MB",
            detail: "English, better accuracy",
            filename: "ggml-small.en.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!
        ),
        LocalSpeechModel(
            id: "large-v3-turbo-q5",
            name: "Whisper large-v3-turbo q5",
            size: "547 MB",
            detail: "Multilingual, quantized",
            filename: "ggml-large-v3-turbo-q5_0.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
        ),
        LocalSpeechModel(
            id: "large-v3-turbo",
            name: "Whisper large-v3-turbo",
            size: "1.5 GB",
            detail: "Multilingual, best local quality",
            filename: "ggml-large-v3-turbo.bin",
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!
        )
    ]
}

@MainActor
final class LocalSpeechModelManager: ObservableObject {
    private static let selectedModelFilenameKey = "selectedLocalSpeechModelFilename"

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("com.curisaas.opentranstype/speech-models", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    @Published private(set) var downloadedFilenames: Set<String> = []
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published var selectedModelFilename: String? {
        didSet {
            UserDefaults.standard.set(selectedModelFilename, forKey: Self.selectedModelFilenameKey)
        }
    }

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    init() {
        selectedModelFilename = UserDefaults.standard.string(forKey: Self.selectedModelFilenameKey)
        refreshDownloadedModels()
    }

    var selectedModel: LocalSpeechModel? {
        guard let selectedModelFilename else {
            return nil
        }

        return LocalSpeechModel.available.first { $0.filename == selectedModelFilename }
    }

    var selectedModelURL: URL? {
        guard let selectedModel else {
            return nil
        }

        let url = fileURL(for: selectedModel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fileURL(for model: LocalSpeechModel) -> URL {
        Self.modelsDirectory.appendingPathComponent(model.filename)
    }

    func isDownloaded(_ model: LocalSpeechModel) -> Bool {
        downloadedFilenames.contains(model.filename)
    }

    func select(_ model: LocalSpeechModel) {
        guard isDownloaded(model) else {
            return
        }

        selectedModelFilename = model.filename
        DiagnosticLog.write("local speech model selected filename=\(model.filename)")
    }

    func download(_ model: LocalSpeechModel) {
        cancelDownload()
        downloadingModelID = model.id

        let task = URLSession.shared.downloadTask(with: model.url) { [weak self] temporaryURL, response, error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.downloadingModelID = nil
                self.downloadProgress.removeValue(forKey: model.id)
                self.progressObservation = nil

                if let error {
                    DiagnosticLog.write("local speech model download failed model=\(model.id), error=\(error.localizedDescription)")
                    return
                }

                guard let temporaryURL,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    DiagnosticLog.write("local speech model download bad response model=\(model.id)")
                    return
                }

                do {
                    let destinationURL = self.fileURL(for: model)
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }

                    try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
                    self.downloadedFilenames.insert(model.filename)
                    self.selectedModelFilename = model.filename
                    DiagnosticLog.write("local speech model downloaded filename=\(model.filename)")
                } catch {
                    DiagnosticLog.write("local speech model save failed model=\(model.id), error=\(error.localizedDescription)")
                }
            }
        }

        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.downloadProgress[model.id] = progress.fractionCompleted
            }
        }

        downloadTask = task
        task.resume()
        DiagnosticLog.write("local speech model download started model=\(model.id)")
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadingModelID = nil
        downloadProgress.removeAll()
        progressObservation = nil
    }

    func delete(_ model: LocalSpeechModel) {
        try? FileManager.default.removeItem(at: fileURL(for: model))
        downloadedFilenames.remove(model.filename)

        if selectedModelFilename == model.filename {
            selectedModelFilename = nil
        }

        DiagnosticLog.write("local speech model deleted filename=\(model.filename)")
    }

    func openModelsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.modelsDirectory])
    }

    private func refreshDownloadedModels() {
        downloadedFilenames = Set(
            LocalSpeechModel.available
                .filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
                .map(\.filename)
        )

        if let selectedModelFilename,
           !downloadedFilenames.contains(selectedModelFilename) {
            self.selectedModelFilename = nil
        }
    }
}
