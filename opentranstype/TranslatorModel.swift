import Foundation
import Combine
import NaturalLanguage
import Translation

@MainActor
final class TranslatorModel: ObservableObject {
    private static let selectedLanguageIDKey = "selectedLanguageID"
    private static let maximumTranslatableTextLength = 2_000

    private let historyStore: TranslationHistoryStore?

    @Published var isEnabled = true
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var statusText = "正在监听输入"
    @Published var selectedLanguage: TranslationLanguage {
        didSet {
            guard selectedLanguage != oldValue else {
                return
            }

            UserDefaults.standard.set(selectedLanguage.id, forKey: Self.selectedLanguageIDKey)
            DiagnosticLog.write("target language changed from=\(oldValue.id) to=\(selectedLanguage.id)")
            requestTranslation(for: sourceText)
        }
    }
    @Published var requestID = 0

    private var lastRequestedText = ""
    private var translationTask: Task<Void, Never>?
    private let translationDebounce: Duration = .milliseconds(350)
    private let translationTimeout: Duration = .seconds(8)
    private let sameLanguageConfidenceThreshold = 0.72

    init(historyStore: TranslationHistoryStore? = nil) {
        self.historyStore = historyStore

        if let savedLanguageID = UserDefaults.standard.string(forKey: Self.selectedLanguageIDKey),
           let savedLanguage = TranslationLanguage.language(withID: savedLanguageID) {
            selectedLanguage = savedLanguage
            DiagnosticLog.write("target language restored id=\(savedLanguage.id)")
        } else {
            selectedLanguage = TranslationLanguage.defaultTarget
            DiagnosticLog.write("target language default id=\(selectedLanguage.id)")
        }
    }

    var canApplyTranslation: Bool {
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func enable() {
        isEnabled = true
        statusText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "正在监听输入" : statusText
    }

    func disable() {
        isEnabled = false
        sourceText = ""
        translatedText = ""
        statusText = "已暂停"
        translationTask?.cancel()
        translationTask = nil
        lastRequestedText = ""
        requestID += 1
    }

    func updateSourceText(_ text: String) {
        guard isEnabled else {
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceText = trimmed

        guard !trimmed.isEmpty else {
            translatedText = ""
            statusText = "输入内容后自动翻译"
            translationTask?.cancel()
            translationTask = nil
            lastRequestedText = ""
            return
        }

        requestTranslation(for: trimmed)
    }

    func requestTranslation(for text: String, force: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty, force || trimmed != lastRequestedText else {
            return
        }

        guard trimmed.count <= Self.maximumTranslatableTextLength else {
            sourceText = trimmed
            translatedText = ""
            statusText = "文本过长"
            translationTask?.cancel()
            translationTask = nil
            lastRequestedText = trimmed
            requestID += 1
            DiagnosticLog.write("translation ignored too long, length=\(trimmed.count)")
            return
        }

        lastRequestedText = trimmed
        translatedText = ""
        requestID += 1
        let currentRequestID = requestID
        DiagnosticLog.write("translation requested id=\(currentRequestID), length=\(trimmed.count), target=\(selectedLanguage.name)")

        guard isReadyForTranslation(trimmed, force: force) else {
            translationTask?.cancel()
            translationTask = nil
            statusText = "继续输入"
            DiagnosticLog.write("translation skipped short text id=\(currentRequestID), length=\(trimmed.count)")
            return
        }

        statusText = "等待输入"

        guard let sourceLanguage = detectedSourceLanguage(for: trimmed) else {
            statusText = "继续输入"
            DiagnosticLog.write("translation skipped, source language unresolved")
            return
        }

        if sourceLanguage.id == selectedLanguage.id {
            translationTask?.cancel()
            translationTask = nil
            translatedText = ""
            if sourceLanguage.confidence >= sameLanguageConfidenceThreshold {
                statusText = "已是目标语言"
                DiagnosticLog.write("translation skipped same language=\(sourceLanguage.id), confidence=\(sourceLanguage.confidence), length=\(trimmed.count)")
            } else {
                statusText = "继续输入"
                DiagnosticLog.write("translation skipped uncertain same language=\(sourceLanguage.id), confidence=\(sourceLanguage.confidence), length=\(trimmed.count)")
            }
            return
        }

        let targetLanguage = selectedLanguage.language
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            do {
                guard let self else {
                    return
                }

                try await Task.sleep(for: self.translationDebounce)
                self.beginTranslationIfCurrent(requestID: currentRequestID)

                let availability: LanguageAvailability
                if #available(macOS 26.4, *) {
                    availability = LanguageAvailability(preferredStrategy: .lowLatency)
                } else {
                    availability = LanguageAvailability()
                }

                let status = await availability.status(from: sourceLanguage.language, to: targetLanguage)
                DiagnosticLog.write("translation availability id=\(currentRequestID), source=\(sourceLanguage.id), target=\(self.selectedLanguage.id), status=\(status)")
                switch status {
                case .installed:
                    break
                case .supported:
                    self.markLanguagePackUnavailable(requestID: currentRequestID, sourceID: sourceLanguage.id)
                    return
                case .unsupported:
                    self.markUnsupportedLanguagePair(requestID: currentRequestID, sourceID: sourceLanguage.id)
                    return
                @unknown default:
                    self.markUnsupportedLanguagePair(requestID: currentRequestID, sourceID: sourceLanguage.id)
                    return
                }

                let session: TranslationSession
                if #available(macOS 26.4, *) {
                    session = TranslationSession(
                        installedSource: sourceLanguage.language,
                        target: targetLanguage,
                        preferredStrategy: .lowLatency
                    )
                } else {
                    session = TranslationSession(installedSource: sourceLanguage.language, target: targetLanguage)
                }

                let response = try await session.translate(trimmed)
                self.finishTranslation(requestID: currentRequestID, result: response.targetText)
            } catch is CancellationError {
                DiagnosticLog.write("translation cancelled id=\(currentRequestID)")
            } catch {
                self?.failTranslation(requestID: currentRequestID, error)
            }
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: self.translationTimeout)
            self.resetIfStillTranslating(requestID: currentRequestID)
        }
    }

    func finishTranslation(requestID: Int, result: String) {
        guard requestID == self.requestID else {
            DiagnosticLog.write("translation ignored stale id=\(requestID), current=\(self.requestID)")
            return
        }

        translatedText = result
        statusText = "按 ↓ 覆盖原文"
        historyStore?.recordTranslation(sourceText: sourceText, translatedText: result, targetLanguage: selectedLanguage)
        DiagnosticLog.write("translation finished id=\(requestID), resultLength=\(result.count)")
    }

    func beginTranslationIfCurrent(requestID: Int) {
        guard requestID == self.requestID,
              translatedText.isEmpty else {
            return
        }

        statusText = "翻译中..."
    }

    func markLanguagePackUnavailable(requestID: Int, sourceID: String) {
        guard requestID == self.requestID else {
            return
        }

        translatedText = ""
        statusText = "语言包未就绪"
        DiagnosticLog.write("translation language pack unavailable id=\(requestID), source=\(sourceID), target=\(selectedLanguage.id)")
    }

    func markUnsupportedLanguagePair(requestID: Int, sourceID: String) {
        guard requestID == self.requestID else {
            return
        }

        translatedText = ""
        statusText = "不支持该语言对"
        DiagnosticLog.write("translation unsupported pair id=\(requestID), source=\(sourceID), target=\(selectedLanguage.id)")
    }

    func failTranslation(requestID: Int, _ error: Error) {
        guard requestID == self.requestID else {
            DiagnosticLog.write("translation failure ignored stale id=\(requestID), current=\(self.requestID)")
            return
        }

        translatedText = ""
        let nsError = error as NSError
        statusText = nsError.domain == "Translation.TranslationError" ? "暂时无法翻译" : "翻译失败，稍后重试"
        DiagnosticLog.write("translation failed: \(error.localizedDescription), domain=\(nsError.domain), code=\(nsError.code)")
    }

    func resetIfStillTranslating(requestID: Int) {
        guard requestID == self.requestID,
              translatedText.isEmpty,
              statusText == "翻译中..." else {
            return
        }

        statusText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "正在监听输入" : "翻译超时"
        translationTask?.cancel()
        translationTask = nil
        DiagnosticLog.write("translation timed out id=\(requestID)")
    }

    func forceTranslation(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceText = trimmed
        requestTranslation(for: trimmed, force: true)
    }

    private func detectedSourceLanguage(for text: String) -> (id: String, language: Locale.Language, confidence: Double)? {
        if text.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            return ("zh-Hans", Locale.Language(identifier: "zh-Hans"), 1)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            return nil
        }

        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        return (language.rawValue, Locale.Language(identifier: language.rawValue), confidence)
    }

    private func isReadyForTranslation(_ text: String, force: Bool) -> Bool {
        let hanCharacters = text
            .matches(of: /\p{Han}/)
            .count
        if hanCharacters > 0 {
            return force ? hanCharacters >= 1 : hanCharacters >= 2
        }

        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        if force {
            return letters >= 2 || text.count >= 4
        }

        return letters >= 4 || text.count >= 6
    }
}
