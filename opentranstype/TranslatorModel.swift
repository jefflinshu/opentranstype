import Foundation
import Combine
import NaturalLanguage
import Translation

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var isEnabled = true
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var statusText = "正在监听输入"
    @Published var selectedLanguage = TranslationLanguage.supported[0] {
        didSet {
            requestTranslation(for: sourceText)
        }
    }
    @Published var requestID = 0

    private var lastRequestedText = ""
    private var translationTask: Task<Void, Never>?
    private let translationDebounce: Duration = .milliseconds(350)

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
        sourceText = text

        guard isEnabled else {
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translatedText = ""
            statusText = "输入内容后自动翻译"
            translationTask?.cancel()
            translationTask = nil
            lastRequestedText = ""
            return
        }

        requestTranslation(for: text)
    }

    func requestTranslation(for text: String, force: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty, force || trimmed != lastRequestedText else {
            return
        }

        lastRequestedText = trimmed
        translatedText = ""
        statusText = "等待输入"
        requestID += 1
        let currentRequestID = requestID
        DiagnosticLog.write("translation requested id=\(currentRequestID), length=\(trimmed.count), target=\(selectedLanguage.name)")

        guard let sourceLanguage = detectedSourceLanguage(for: trimmed) else {
            statusText = "无法识别语言"
            DiagnosticLog.write("translation skipped, source language unresolved")
            return
        }

        if sourceLanguage.id == selectedLanguage.id {
            translationTask?.cancel()
            translationTask = nil
            translatedText = ""
            statusText = "已是目标语言"
            DiagnosticLog.write("translation skipped same language=\(sourceLanguage.id), length=\(trimmed.count)")
            return
        }

        let targetLanguage = selectedLanguage.language
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: translationDebounce)
                await self?.beginTranslationIfCurrent(requestID: currentRequestID)

                let availability: LanguageAvailability
                if #available(macOS 26.4, *) {
                    availability = LanguageAvailability(preferredStrategy: .lowLatency)
                } else {
                    availability = LanguageAvailability()
                }

                let status = await availability.status(from: sourceLanguage.language, to: targetLanguage)
                DiagnosticLog.write("translation availability id=\(currentRequestID), source=\(sourceLanguage.id), target=\(selectedLanguage.id), status=\(status)")
                switch status {
                case .installed:
                    break
                case .supported:
                    await self?.markLanguagePackUnavailable(requestID: currentRequestID, sourceID: sourceLanguage.id)
                    return
                case .unsupported:
                    await self?.markUnsupportedLanguagePair(requestID: currentRequestID, sourceID: sourceLanguage.id)
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
                await self?.finishTranslation(requestID: currentRequestID, result: response.targetText)
            } catch is CancellationError {
                DiagnosticLog.write("translation cancelled id=\(currentRequestID)")
            } catch {
                await self?.failTranslation(requestID: currentRequestID, error)
            }
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.resetIfStillTranslating(requestID: currentRequestID)
        }
    }

    func finishTranslation(requestID: Int, result: String) {
        guard requestID == self.requestID else {
            DiagnosticLog.write("translation ignored stale id=\(requestID), current=\(self.requestID)")
            return
        }

        translatedText = result
        statusText = "按 ↓ 覆盖原文"
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

        statusText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "正在监听输入" : "等待输入"
        DiagnosticLog.write("translation timed out id=\(requestID)")
    }

    func forceTranslation(for text: String) {
        sourceText = text
        requestTranslation(for: text, force: true)
    }

    private func detectedSourceLanguage(for text: String) -> (id: String, language: Locale.Language)? {
        if text.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            return ("zh-Hans", Locale.Language(identifier: "zh-Hans"))
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            return nil
        }

        return (language.rawValue, Locale.Language(identifier: language.rawValue))
    }
}
