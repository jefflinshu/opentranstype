import Combine
import Foundation
import Translation

struct TranslationLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let language: Locale.Language

    nonisolated init(id: String, name: String, shortName: String, language: Locale.Language) {
        let normalizedLanguage = Locale.Language(identifier: language.maximalIdentifier)
        self.id = normalizedLanguage.maximalIdentifier
        self.name = name
        self.shortName = shortName
        self.language = normalizedLanguage
    }

    nonisolated init(language: Locale.Language) {
        let normalizedLanguage = Locale.Language(identifier: language.maximalIdentifier)
        let identifier = normalizedLanguage.maximalIdentifier
        self.id = identifier
        self.language = normalizedLanguage
        self.name = Self.displayName(for: normalizedLanguage)
        self.shortName = Self.shortName(for: normalizedLanguage)
    }

    nonisolated static let fallbackSupported: [TranslationLanguage] = [
        .init(id: "en", name: "English", shortName: "EN", language: Locale.Language(identifier: "en")),
        .init(id: "zh-Hans", name: "简体中文", shortName: "简", language: Locale.Language(identifier: "zh-Hans")),
        .init(id: "zh-Hant", name: "繁體中文", shortName: "繁", language: Locale.Language(identifier: "zh-Hant")),
        .init(id: "ja", name: "日本語", shortName: "日", language: Locale.Language(identifier: "ja")),
        .init(id: "ko", name: "한국어", shortName: "한", language: Locale.Language(identifier: "ko")),
        .init(id: "fr", name: "Français", shortName: "FR", language: Locale.Language(identifier: "fr")),
        .init(id: "de", name: "Deutsch", shortName: "DE", language: Locale.Language(identifier: "de")),
        .init(id: "es", name: "Español", shortName: "ES", language: Locale.Language(identifier: "es")),
        .init(id: "it", name: "Italiano", shortName: "IT", language: Locale.Language(identifier: "it")),
        .init(id: "pt", name: "Português", shortName: "PT", language: Locale.Language(identifier: "pt")),
        .init(id: "ru", name: "Русский", shortName: "RU", language: Locale.Language(identifier: "ru")),
        .init(id: "ar", name: "العربية", shortName: "AR", language: Locale.Language(identifier: "ar"))
    ]

    nonisolated static func language(withID id: String, from languages: [TranslationLanguage]) -> TranslationLanguage? {
        let resolvedID = legacyLanguageAlias[id] ?? id

        if let exact = languages.first(where: { $0.id == resolvedID || $0.language.maximalIdentifier == resolvedID }) {
            return exact
        }

        let requestedLanguage = Locale.Language(identifier: resolvedID)
        if let exactLanguage = languages.first(where: {
            $0.language.maximalIdentifier == requestedLanguage.maximalIdentifier
        }) {
            return exactLanguage
        }

        let requestedCode = requestedLanguage.languageCode?.identifier
        let requestedScript = requestedLanguage.script?.identifier
        return languages.first {
            let candidate = $0.language
            let candidateCode = candidate.languageCode?.identifier
            let candidateScript = candidate.script?.identifier
            guard candidateCode == requestedCode else {
                return false
            }

            if let requestedScript {
                return candidateScript == requestedScript
            }

            return true
        }
    }

    nonisolated static func defaultTarget(from languages: [TranslationLanguage]) -> TranslationLanguage {
        language(withID: "en", from: languages) ?? languages.first ?? fallbackSupported[0]
    }

    nonisolated static func systemLanguages(from supportedLanguages: [Locale.Language]) -> [TranslationLanguage] {
        let mapped = supportedLanguages
            .map { TranslationLanguage(language: $0) }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

        return mapped.isEmpty ? fallbackSupported : mapped
    }

    nonisolated private static let legacyLanguageAlias: [String: String] = [
        "en": "en-Latn-US",
        "zh-Hans": "zh-Hans-CN",
        "zh-Hant": "zh-Hant-TW",
        "ja": "ja-Jpan-JP",
        "ko": "ko-Kore-KR",
        "fr": "fr-Latn-FR",
        "de": "de-Latn-DE",
        "es": "es-Latn-ES",
        "it": "it-Latn-IT",
        "pt": "pt-Latn-BR",
        "ru": "ru-Cyrl-RU",
        "ar": "ar-Arab-AE"
    ]

    nonisolated private static func displayName(for language: Locale.Language) -> String {
        let locale = Locale.autoupdatingCurrent
        let englishLocale = Locale(identifier: "en")
        let identifier = language.maximalIdentifier

        return locale.localizedString(forIdentifier: identifier)
            ?? englishLocale.localizedString(forIdentifier: identifier)
            ?? identifier
    }

    nonisolated private static func shortName(for language: Locale.Language) -> String {
        let identifier = language.maximalIdentifier

        switch identifier {
        case let value where value.hasPrefix("zh-Hans"):
            return "简"
        case let value where value.hasPrefix("zh-Hant"):
            return "繁"
        case let value where value.hasPrefix("ja"):
            return "日"
        case let value where value.hasPrefix("ko"):
            return "한"
        default:
            break
        }

        if let code = language.languageCode?.identifier {
            return String(code.prefix(2)).uppercased()
        }

        return String(identifier.prefix(2)).uppercased()
    }
}

@MainActor
final class TranslationLanguageCatalog: ObservableObject {
    static let shared = TranslationLanguageCatalog()

    @Published private(set) var supportedLanguages = TranslationLanguage.fallbackSupported
    // ids of languages whose translation pack is installed (checked against a sample source).
    @Published private(set) var installedLanguageIDs: Set<String> = []

    private var isLoading = false
    private var didAttemptLoad = false

    func loadIfNeeded() {
        guard !didAttemptLoad else {
            return
        }

        didAttemptLoad = true
        Task {
            await refresh()
        }
    }

    func refresh() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        let availability = LanguageAvailability()
        let languages = await availability.supportedLanguages
        let mappedLanguages = TranslationLanguage.systemLanguages(from: languages)

        guard !mappedLanguages.isEmpty else {
            return
        }

        supportedLanguages = mappedLanguages
        await refreshInstalledLanguages(availability: availability)
    }

    /// Determines which target languages already have an installed pack, by checking each
    /// against a representative source language (English, or Chinese for English itself).
    func refreshInstalledLanguages(availability: LanguageAvailability? = nil) async {
        let availability = availability ?? LanguageAvailability()
        var installed: Set<String> = []

        for language in supportedLanguages {
            let source = Self.sampleSource(for: language.language)
            let status = await availability.status(from: source, to: language.language)
            if status == .installed {
                installed.insert(language.id)
            }
        }

        installedLanguageIDs = installed
    }

    var installedLanguages: [TranslationLanguage] {
        supportedLanguages.filter { installedLanguageIDs.contains($0.id) }
    }

    nonisolated private static func sampleSource(for language: Locale.Language) -> Locale.Language {
        if language.languageCode?.identifier == "en" {
            return Locale.Language(identifier: "zh-Hans")
        }

        return Locale.Language(identifier: "en")
    }

    func language(withID id: String) -> TranslationLanguage? {
        TranslationLanguage.language(withID: id, from: supportedLanguages)
            ?? TranslationLanguage.language(withID: id, from: TranslationLanguage.fallbackSupported)
    }

    var defaultTarget: TranslationLanguage {
        TranslationLanguage.defaultTarget(from: supportedLanguages)
    }
}
