import SwiftUI
import StoreKit

struct PaywallView: View {
    private enum ProductLoadState {
        case loading
        case loaded
        case failed
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var proManager: ProManager
    var onClose: (() -> Void)?

    @State private var availableProducts: [Product] = []
    @State private var productLoadState: ProductLoadState = .loading
    @State private var isPurchasing = false
    @State private var purchaseAlert: PaywallAlert?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                    .padding(.bottom, 2)

                VStack(alignment: .leading, spacing: 16) {
                    featureGrid
                    planSection
                    footerActions
                }
            }
            .padding(22)
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 620)
        .task {
            await loadProducts()
            await proManager.refreshProState()
        }
        .alert(item: $purchaseAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(String(localized: "OK")))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.49, green: 0.52, blue: 1.0), Color(red: 0.31, green: 0.34, blue: 0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Transtype Pro")
                        .font(.title.weight(.semibold))

                    Text("Keep translation flowing across every macOS writing surface.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close"))
            }
        }
        .padding(16)
        .liquidGlassPanel(cornerRadius: 18)
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            PaywallFeatureCard(iconName: "infinity", title: "Unlimited translations", subtitle: "Translate without daily caps.")
            PaywallFeatureCard(iconName: "clock.arrow.circlepath", title: "Full local history", subtitle: "Keep recent writing context available.")
            PaywallFeatureCard(iconName: "arrow.down.doc.fill", title: "One-click replace", subtitle: "Apply translated text in place.")
            PaywallFeatureCard(iconName: "globe", title: "Language workflow", subtitle: "Manage target languages and packs.")
        }
    }

    private var planSection: some View {
        VStack(spacing: 12) {
            ForEach(visiblePlans) { plan in
                Button {
                    Task {
                        await purchaseProduct(plan.productID)
                    }
                } label: {
                    PaywallOptionCard(
                        title: plan.title,
                        subtitle: planSubtitle(for: plan),
                        highlight: plan.isHighlighted,
                        highlightLabel: plan.isHighlighted ? String(localized: "Best Value") : ""
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchaseDisabled(for: plan.productID))
            }

            if visiblePlans.isEmpty {
                ContentUnavailableView(
                    "Transtype Pro is active",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Your current App Store account already has the highest Transtype Pro entitlement.")
                )
                .padding(.vertical, 16)
            }

            Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var footerActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Button(String(localized: "Restore Purchases")) {
                    Task {
                        await restorePurchases()
                    }
                }

                Button(String(localized: "Terms of Service")) {
                    openURL(URL(string: "https://curisaas.com/transtype/terms")!)
                }

                Button(String(localized: "Privacy Policy")) {
                    openURL(URL(string: "https://curisaas.com/transtype/privacy")!)
                }
            }
            .buttonStyle(.link)
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
    }

    private var visiblePlans: [PaywallPlan] {
        PaywallPlan.availableOptions(for: proManager.activeProductID)
    }

    private var missingProductSubtitle: String {
        switch productLoadState {
        case .loading:
            return String(localized: "Loading...")
        case .loaded, .failed:
            return String(localized: "Price shown after App Store connection")
        }
    }

    private func planSubtitle(for plan: PaywallPlan) -> String {
        guard availableProducts.count == ProManager.ProductID.allCases.count else {
            return plan.fallbackSubtitle
        }

        guard let product = product(for: plan.productID) else {
            return plan.fallbackSubtitle
        }

        guard let subscription = product.subscription else {
            return String.localizedStringWithFormat(
                String(localized: "One-time purchase for %@"),
                product.displayPrice
            )
        }

        return String.localizedStringWithFormat(
            String(localized: "%@ per %@"),
            product.displayPrice,
            localizedPeriodUnit(subscription.subscriptionPeriod.unit)
        )
    }

    private func localizedPeriodUnit(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day:
            return String(localized: "day")
        case .week:
            return String(localized: "week")
        case .month:
            return String(localized: "month")
        case .year:
            return String(localized: "year")
        @unknown default:
            return ""
        }
    }

    @MainActor
    private func loadProducts() async {
        productLoadState = .loading

        do {
            let products = try await Product.products(for: ProManager.ProductID.allCases.map(\.rawValue))
            availableProducts = products.sorted { lhs, rhs in
                productSortIndex(lhs.id) < productSortIndex(rhs.id)
            }
            productLoadState = .loaded
        } catch {
            availableProducts = []
            productLoadState = .failed
            presentAlert(
                title: String(localized: "Store Unavailable"),
                message: String(localized: "Unable to fetch product information.")
            )
        }
    }

    @MainActor
    private func purchaseProduct(_ productID: ProManager.ProductID) async {
        guard !isPurchasing,
              let product = product(for: productID) else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await proManager.finalizeVerifiedTransaction(transaction)
                    presentAlert(
                        title: String(localized: "Purchase Complete"),
                        message: String(localized: "Transtype Pro is now active.")
                    )
                case .unverified(_, let verificationError):
                    presentAlert(
                        title: String(localized: "Purchase Couldn’t Be Verified"),
                        message: verificationError.localizedDescription
                    )
                }
            case .userCancelled:
                break
            case .pending:
                presentAlert(
                    title: String(localized: "Purchase Pending"),
                    message: String(localized: "This purchase is pending approval. Transtype will unlock Pro automatically when StoreKit confirms it.")
                )
            @unknown default:
                presentAlert(
                    title: String(localized: "Purchase Error"),
                    message: String(localized: "An unexpected StoreKit result occurred.")
                )
            }
        } catch {
            presentAlert(
                title: String(localized: "Purchase Error"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func restorePurchases() async {
        do {
            try await AppStore.sync()
            await proManager.refreshProState()

            if proManager.isPro {
                presentAlert(
                    title: String(localized: "Purchases Restored"),
                    message: String(localized: "Your Transtype Pro access is available on this device.")
                )
            } else {
                presentAlert(
                    title: String(localized: "Nothing to Restore"),
                    message: String(localized: "No active Transtype Pro purchases were found for this App Store account.")
                )
            }
        } catch {
            presentAlert(
                title: String(localized: "Restore Failed"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func product(for productID: ProManager.ProductID) -> Product? {
        availableProducts.first(where: { $0.id == productID.rawValue })
    }

    @MainActor
    private func isPurchaseDisabled(for productID: ProManager.ProductID) -> Bool {
        isPurchasing
    }

    private func productSortIndex(_ productID: String) -> Int {
        ProManager.ProductID.allCases.firstIndex { $0.rawValue == productID } ?? Int.max
    }

    @MainActor
    private func presentAlert(title: String, message: String) {
        purchaseAlert = PaywallAlert(title: title, message: message)
    }
}

private enum PaywallPlan: String, CaseIterable, Identifiable {
    case monthly
    case yearly
    case lifetime

    var id: String { rawValue }

    var productID: ProManager.ProductID {
        switch self {
        case .monthly:
            return .month
        case .yearly:
            return .year
        case .lifetime:
            return .lifetime
        }
    }

    var title: String {
        switch self {
        case .monthly:
            return String(localized: "Monthly Plan")
        case .yearly:
            return String(localized: "Yearly Plan")
        case .lifetime:
            return String(localized: "Lifetime")
        }
    }

    var isHighlighted: Bool {
        self == .yearly
    }

    var fallbackSubtitle: String {
        switch self {
        case .monthly:
            return "US$1.99 per month"
        case .yearly:
            return "US$9.99 per year"
        case .lifetime:
            return "One-time purchase for US$19.99"
        }
    }

    static func availableOptions(for activeProductID: ProManager.ProductID?) -> [PaywallPlan] {
        switch activeProductID {
        case .none:
            return [.monthly, .yearly, .lifetime]
        case .month:
            return [.yearly, .lifetime]
        case .year:
            return [.lifetime]
        case .lifetime:
            return []
        }
    }
}

private struct PaywallFeatureCard: View {
    let iconName: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(14)
        .liquidGlassPanel(cornerRadius: 12)
    }
}

private struct PaywallOptionCard: View {
    let title: String
    let subtitle: String
    let highlight: Bool
    let highlightLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if highlight {
                Text(highlightLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue, in: Capsule())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(highlight ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: highlight ? 2 : 1)
        )
    }
}

private struct PaywallAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
