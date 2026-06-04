import Foundation
import Combine
import StoreKit

@MainActor
final class ProManager: ObservableObject {
    enum ProductID: String, CaseIterable {
        case month = "transtypePro.month"
        case year = "transtypePro.year"
        case lifetime = "transtypePro.lifetime"

        var entitlementRank: Int {
            switch self {
            case .month:
                return 1
            case .year:
                return 2
            case .lifetime:
                return 3
            }
        }
    }

    static let shared = ProManager()

    private static let cachedIsProKey = "proManager.cachedIsPro"
    private static let cachedProTypeKey = "proManager.cachedProType"

    @Published private(set) var isPro: Bool
    @Published private(set) var proType: String

    var activeProductID: ProductID? {
        ProductID(rawValue: proType)
    }

    private init() {
        let defaults = UserDefaults.standard
        isPro = defaults.bool(forKey: Self.cachedIsProKey)
        proType = defaults.string(forKey: Self.cachedProTypeKey) ?? ""

        Task {
            await refreshProState()
        }
    }

    func refreshProState() async {
        var highestEntitlement: StoreKit.Transaction?
        var highestRank = 0

        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               let productID = ProductID(rawValue: transaction.productID),
               productID.entitlementRank > highestRank {
                highestEntitlement = transaction
                highestRank = productID.entitlementRank
            }
        }

        if let transaction = highestEntitlement {
            isPro = true
            proType = transaction.productID
        } else {
            isPro = false
            proType = ""
        }

        persistCachedProState()
    }

    func finalizeVerifiedTransaction(_ transaction: StoreKit.Transaction) async {
        await refreshProState()
        await transaction.finish()
    }

    private func persistCachedProState() {
        let defaults = UserDefaults.standard
        defaults.set(isPro, forKey: Self.cachedIsProKey)
        defaults.set(proType, forKey: Self.cachedProTypeKey)
    }
}
