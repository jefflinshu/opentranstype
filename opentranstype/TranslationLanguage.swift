import Foundation

struct TranslationLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let language: Locale.Language

    static let supported: [TranslationLanguage] = [
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

    static func language(withID id: String) -> TranslationLanguage? {
        supported.first { $0.id == id }
    }

    static var defaultTarget: TranslationLanguage {
        return language(withID: "en") ?? supported[0]
    }
}
