import Foundation
import Combine
import NaturalLanguage
import Translation

@MainActor
final class TranslatorModel: ObservableObject {
    private static let selectedLanguageIDKey = "selectedLanguageID"
    private static let maximumTranslatableTextLength = 2_000

    private let historyStore: TranslationHistoryStore?
    private let languageCatalog: TranslationLanguageCatalog

    @Published var isEnabled = true
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var statusText = String(localized: "Listening for input")
    @Published var isUpgradeRequired = false
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
    private let translationDebounce: Duration = .milliseconds(550)
    private let translationTimeout: Duration = .seconds(8)
    private let sameLanguageConfidenceThreshold = 0.72

    init(
        historyStore: TranslationHistoryStore? = nil,
        languageCatalog: TranslationLanguageCatalog? = nil
    ) {
        let languageCatalog = languageCatalog ?? .shared
        self.historyStore = historyStore
        self.languageCatalog = languageCatalog
        languageCatalog.loadIfNeeded()

        if let savedLanguageID = UserDefaults.standard.string(forKey: Self.selectedLanguageIDKey),
           let savedLanguage = languageCatalog.language(withID: savedLanguageID) {
            selectedLanguage = savedLanguage
            DiagnosticLog.write("target language restored id=\(savedLanguage.id)")
        } else {
            selectedLanguage = languageCatalog.defaultTarget
            DiagnosticLog.write("target language default id=\(selectedLanguage.id)")
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.languageCatalog.refresh()
            self.reconcileSelectedLanguage()
        }
    }

    var canApplyTranslation: Bool {
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func enable() {
        isEnabled = true
        if !isUpgradeRequired {
            statusText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Listening for input") : statusText
        }
    }

    func disable() {
        isEnabled = false
        sourceText = ""
        translatedText = ""
        isUpgradeRequired = false
        statusText = String(localized: "Paused")
        translationTask?.cancel()
        translationTask = nil
        lastRequestedText = ""
        requestID += 1
    }

    func markUpgradeRequired() {
        isEnabled = true
        isUpgradeRequired = true
        translatedText = ""
        statusText = String(localized: "Free limit reached. Upgrade to continue.")
        translationTask?.cancel()
        translationTask = nil
        requestID += 1
    }

    func clearUpgradeRequiredIfNeeded() {
        guard isUpgradeRequired else {
            return
        }

        isUpgradeRequired = false
        statusText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Listening for input")
            : String(localized: "Ready")
    }

    func updateSourceText(_ text: String) {
        guard isEnabled, !isUpgradeRequired else {
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceText = trimmed

        guard !trimmed.isEmpty else {
            translatedText = ""
            statusText = String(localized: "Start typing to translate")
            translationTask?.cancel()
            translationTask = nil
            lastRequestedText = ""
            return
        }

        requestTranslation(for: trimmed)
    }

    func requestTranslation(for text: String, force: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !isUpgradeRequired, !trimmed.isEmpty, force || trimmed != lastRequestedText else {
            return
        }

        guard trimmed.count <= Self.maximumTranslatableTextLength else {
            sourceText = trimmed
            translatedText = ""
            statusText = String(localized: "Text too long")
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
            statusText = String(localized: "Keep typing")
            DiagnosticLog.write("translation skipped short text id=\(currentRequestID), length=\(trimmed.count)")
            return
        }

        statusText = String(localized: "Waiting for input")
        let targetLanguage = selectedLanguage.language
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            do {
                guard let self else {
                    return
                }

                try await Task.sleep(for: self.translationDebounce)

                guard currentRequestID == self.requestID else {
                    DiagnosticLog.write("translation preflight ignored stale id=\(currentRequestID), current=\(self.requestID)")
                    return
                }

                guard let sourceLanguage = self.detectedSourceLanguage(for: trimmed) else {
                    self.markSourceLanguageUnresolved(requestID: currentRequestID)
                    return
                }

                if sourceLanguage.id == self.selectedLanguage.id {
                    self.skipSameLanguageTranslation(
                        requestID: currentRequestID,
                        sourceID: sourceLanguage.id,
                        confidence: sourceLanguage.confidence,
                        length: trimmed.count
                    )
                    return
                }

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
        statusText = String(localized: "Press ↓ to replace text")
        DiagnosticLog.write("translation finished id=\(requestID), resultLength=\(result.count)")
    }

    func markSourceLanguageUnresolved(requestID: Int) {
        guard requestID == self.requestID else {
            return
        }

        statusText = String(localized: "Keep typing")
        DiagnosticLog.write("translation skipped, source language unresolved")
    }

    func skipSameLanguageTranslation(requestID: Int, sourceID: String, confidence: Double, length: Int) {
        guard requestID == self.requestID else {
            return
        }

        translationTask?.cancel()
        translationTask = nil
        translatedText = ""
        if confidence >= sameLanguageConfidenceThreshold {
            statusText = String(localized: "Already in target language")
            DiagnosticLog.write("translation skipped same language=\(sourceID), confidence=\(confidence), length=\(length)")
        } else {
            statusText = String(localized: "Keep typing")
            DiagnosticLog.write("translation skipped uncertain same language=\(sourceID), confidence=\(confidence), length=\(length)")
        }
    }

    func recordAppliedTranslation() {
        historyStore?.recordTranslation(sourceText: sourceText, translatedText: translatedText, targetLanguage: selectedLanguage)
        DiagnosticLog.write("translation history recorded on apply, sourceLength=\(sourceText.count), resultLength=\(translatedText.count)")
    }

    func beginTranslationIfCurrent(requestID: Int) {
        guard requestID == self.requestID,
              translatedText.isEmpty else {
            return
        }

        statusText = String(localized: "Translating...")
    }

    func markLanguagePackUnavailable(requestID: Int, sourceID: String) {
        guard requestID == self.requestID else {
            return
        }

        translatedText = ""
        statusText = String(localized: "Language pack not ready")
        DiagnosticLog.write("translation language pack unavailable id=\(requestID), source=\(sourceID), target=\(selectedLanguage.id)")
    }

    func markUnsupportedLanguagePair(requestID: Int, sourceID: String) {
        guard requestID == self.requestID else {
            return
        }

        translatedText = ""
        statusText = String(localized: "Language pair not supported")
        DiagnosticLog.write("translation unsupported pair id=\(requestID), source=\(sourceID), target=\(selectedLanguage.id)")
    }

    func failTranslation(requestID: Int, _ error: Error) {
        guard requestID == self.requestID else {
            DiagnosticLog.write("translation failure ignored stale id=\(requestID), current=\(self.requestID)")
            return
        }

        translatedText = ""
        let nsError = error as NSError
        statusText = nsError.domain == "Translation.TranslationError"
            ? String(localized: "Translation unavailable right now")
            : String(localized: "Translation failed. Try again later")
        DiagnosticLog.write("translation failed: \(error.localizedDescription), domain=\(nsError.domain), code=\(nsError.code)")
    }

    func resetIfStillTranslating(requestID: Int) {
        guard requestID == self.requestID,
              translatedText.isEmpty,
              statusText == String(localized: "Translating...") else {
            return
        }

        statusText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Listening for input")
            : String(localized: "Translation timed out")
        translationTask?.cancel()
        translationTask = nil
        DiagnosticLog.write("translation timed out id=\(requestID)")
    }

    private func reconcileSelectedLanguage() {
        let supportedLanguages = languageCatalog.supportedLanguages
        guard !supportedLanguages.contains(selectedLanguage) else {
            return
        }

        let resolvedLanguage = languageCatalog.language(withID: selectedLanguage.id) ?? languageCatalog.defaultTarget
        guard resolvedLanguage != selectedLanguage else {
            return
        }

        selectedLanguage = resolvedLanguage
        DiagnosticLog.write("target language reconciled id=\(resolvedLanguage.id)")
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
