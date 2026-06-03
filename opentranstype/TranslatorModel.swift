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
            if isEnabled, !trimmed.isEmpty {
                DiagnosticLog.write("translation skipped duplicate, length=\(trimmed.count)")
            }
            return
        }

        lastRequestedText = trimmed
        translatedText = ""
        statusText = "翻译中..."
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
            } catch {
                await self?.failTranslation(error)
            }
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

    func failTranslation(_ error: Error) {
        translatedText = ""
        let nsError = error as NSError
        statusText = nsError.domain == "Translation.TranslationError" ? "需安装\(selectedLanguage.name)语言包" : "翻译失败，稍后重试"
        DiagnosticLog.write("translation failed: \(error.localizedDescription), domain=\(nsError.domain), code=\(nsError.code)")
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
