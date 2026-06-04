import Foundation
import Combine

@MainActor
final class FreeQuotaStore: ObservableObject {
    static let monthlyLimit = 100

    private static let monthKey = "freeQuota.currentMonth"
    private static let usedCountKey = "freeQuota.usedCount"

    @Published private(set) var monthIdentifier: String
    @Published private(set) var usedCount: Int

    init(date: Date = Date()) {
        let currentMonth = Self.monthIdentifier(for: date)
        let savedMonth = UserDefaults.standard.string(forKey: Self.monthKey)

        if savedMonth == currentMonth {
            monthIdentifier = currentMonth
            usedCount = UserDefaults.standard.integer(forKey: Self.usedCountKey)
        } else {
            monthIdentifier = currentMonth
            usedCount = 0
            persist()
        }
    }

    var remainingCount: Int {
        max(Self.monthlyLimit - usedCount, 0)
    }

    var isLimitReached: Bool {
        usedCount >= Self.monthlyLimit
    }

    func recordUsageIfNeeded(isPro: Bool, date: Date = Date()) {
        refreshMonthIfNeeded(date: date)
        guard !isPro else {
            return
        }

        usedCount = min(usedCount + 1, Self.monthlyLimit)
        persist()
    }

    func refreshMonthIfNeeded(date: Date = Date()) {
        let currentMonth = Self.monthIdentifier(for: date)
        guard currentMonth != monthIdentifier else {
            return
        }

        monthIdentifier = currentMonth
        usedCount = 0
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(monthIdentifier, forKey: Self.monthKey)
        UserDefaults.standard.set(usedCount, forKey: Self.usedCountKey)
    }

    private static func monthIdentifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
