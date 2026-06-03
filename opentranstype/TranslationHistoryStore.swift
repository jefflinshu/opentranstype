import Foundation
import Combine

struct TranslationRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let sourceText: String
    let translatedText: String
    let targetLanguageID: String
    let targetLanguageName: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceText: String,
        translatedText: String,
        targetLanguage: TranslationLanguage
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.targetLanguageID = targetLanguage.id
        self.targetLanguageName = targetLanguage.name
    }
}

struct TranslationStats {
    let recordCount: Int
    let sourceCharacterCount: Int
    let translatedCharacterCount: Int
    let averageSourceLength: Int
    let latestTargetLanguage: String
}

@MainActor
final class TranslationHistoryStore: ObservableObject {
    private static let recordsKey = "translationHistoryRecords"
    private static let maximumRecordCount = 300
    private static let liveInputMergeInterval: TimeInterval = 120
    private static let saveQueue = DispatchQueue(label: "com.curisaas.opentranstype.translation-history")
    private static let ignoredSourceTexts: Set<String> = [
        "Require follow-up changes"
    ]

    @Published private(set) var records: [TranslationRecord] = []

    init() {
        records = Self.loadRecords()
    }

    var stats: TranslationStats {
        let sourceCharacterCount = records.reduce(0) { $0 + $1.sourceText.count }
        let translatedCharacterCount = records.reduce(0) { $0 + $1.translatedText.count }
        let averageSourceLength = records.isEmpty ? 0 : sourceCharacterCount / records.count
        let latestTargetLanguage = records.first?.targetLanguageName ?? "尚未选择"

        return TranslationStats(
            recordCount: records.count,
            sourceCharacterCount: sourceCharacterCount,
            translatedCharacterCount: translatedCharacterCount,
            averageSourceLength: averageSourceLength,
            latestTargetLanguage: latestTargetLanguage
        )
    }

    func recordTranslation(sourceText: String, translatedText: String, targetLanguage: TranslationLanguage) {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !trimmedTranslation.isEmpty else {
            return
        }
        guard !Self.shouldIgnoreSourceText(trimmedSource) else {
            return
        }

        let record = TranslationRecord(
            sourceText: trimmedSource,
            translatedText: trimmedTranslation,
            targetLanguage: targetLanguage
        )

        if shouldReplaceLatestRecord(with: record) {
            records[0] = record
            saveRecords()
            return
        }

        records.insert(record, at: 0)
        if records.count > Self.maximumRecordCount {
            records.removeLast(records.count - Self.maximumRecordCount)
        }
        saveRecords()
    }

    func clear() {
        records.removeAll()
        saveRecords()
    }

    private func saveRecords() {
        let records = records
        let recordsKey = Self.recordsKey

        Self.saveQueue.async {
            guard let data = try? JSONEncoder().encode(records) else {
                return
            }

            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    private func shouldReplaceLatestRecord(with record: TranslationRecord) -> Bool {
        guard let latestRecord = records.first,
              latestRecord.targetLanguageID == record.targetLanguageID,
              record.createdAt.timeIntervalSince(latestRecord.createdAt) <= Self.liveInputMergeInterval else {
            return false
        }

        return latestRecord.sourceText.hasPrefix(record.sourceText)
            || record.sourceText.hasPrefix(latestRecord.sourceText)
    }

    private static func shouldIgnoreSourceText(_ sourceText: String) -> Bool {
        ignoredSourceTexts.contains(normalizedText(sourceText))
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    private static func loadRecords() -> [TranslationRecord] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([TranslationRecord].self, from: data) else {
            return []
        }

        return records
            .filter { !shouldIgnoreSourceText($0.sourceText) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
