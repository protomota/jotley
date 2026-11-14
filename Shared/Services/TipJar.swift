import Combine
import Foundation
import RevenueCat
import SwiftUI
import StoreKit

/// Explain failures without exposing receipts, account identifiers or error userInfo.
struct TipPurchaseFailure {
    static let purchaseErrorDomain = ErrorCode.errorDomain
    let message: String
    let diagnostic: String

    init(_ error: Error) {
        let failure = error as NSError
        let code = failure.domain == Self.purchaseErrorDomain ? ErrorCode(rawValue: failure.code) : nil
        switch code {
        case .some(.purchaseCancelledError):
            message = "The App Store cancelled this purchase. If you didn’t cancel, Apple Account sign-in may not have finished."
        case .some(.paymentPendingError):
            message = "Your tip is waiting for App Store approval. No further action is needed here."
        case .some(.purchaseNotAllowedError):
            message = "The App Store isn’t allowing purchases on this device. Check your App Store purchase restrictions."
        case .some(.networkError):
            message = "Your tip couldn’t be confirmed because of a connection problem. Check the App Store result before trying again."
        case .some(.storeProblemError):
            message = "Apple couldn’t finish the purchase. If its sign-in popup keeps returning, close it and check your App Store sign-in before trying again."
        default:
            message = "Your tip couldn’t be confirmed. Check the App Store result before trying again."
        }
        let safeDomains: Set<String> = [Self.purchaseErrorDomain, "SKErrorDomain", "StoreKit.StoreKitError",
                                        "ASDErrorDomain", "AMSErrorDomain", "NSURLErrorDomain", "NSCocoaErrorDomain"]
        var chain: [String] = []
        var current: NSError? = failure
        for _ in 0..<5 {
            guard let item = current else { break }
            let domain = safeDomains.contains(item.domain) ? item.domain : "OtherError"
            chain.append("\(domain):\(item.code)")
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        diagnostic = chain.joined(separator: " → ")
    }
}

/// Consumable purchases are a thank-you, never a feature entitlement.
@MainActor
final class TipJarStore: ObservableObject {
    @Published private(set) var products: [StoreProduct] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingID: String?
    @Published private(set) var message: String?
    @Published private(set) var hasTipped = false
    @Published private(set) var purchaseDiagnostic: String?
    @Published private(set) var hasSupportedDevelopment: Bool
    private let preferences: UserDefaults
    private static let supportKey = "nativeTips.hasSupportedDevelopment.v1"

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        hasSupportedDevelopment = preferences.bool(forKey: Self.supportKey)
        #if DEBUG && targetEnvironment(simulator)
        // UI previews only; never manufacture or record a StoreKit transaction.
        if let preview = ProcessInfo.processInfo.environment["PROTOMOTA_TEST_TIP_STATE"] {
            hasSupportedDevelopment = preview == "current" || preview == "previous"
            hasTipped = preview == "current"
        }
        #endif
    }

    private static var configuredKey: String?

    func load(productIDs: [String]) async {
        guard !isLoading, purchasingID == nil else { return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
              key.hasPrefix("appl_"), !key.contains("$(") else {
            products = []
            message = "Tips aren’t available right now. Please try again later."
            return
        }
        if !Purchases.isConfigured {
            // Earlier editions used accounts. Keep their cached identities out of optional tips.
            let suiteName = (Bundle.main.bundleIdentifier ?? "com.protomota") + ".nativeTips.v1"
            guard let tipPreferences = UserDefaults(suiteName: suiteName) else {
                message = "Tips aren’t available right now. Please try again later."
                return
            }
            Purchases.logLevel = .error
            Purchases.configure(with: Configuration.Builder(withAPIKey: key)
                .with(userDefaults: tipPreferences)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .with(automaticDeviceIdentifierCollectionEnabled: false)
                .with(diagnosticsEnabled: false))
            Self.configuredKey = key
        }
        guard Self.configuredKey == key else {
            products = []
            message = "Tips aren’t available right now. Please try again later."
            return
        }
        let fetched = await Purchases.shared.products(productIDs)
        guard !Task.isCancelled else { return }
        // Only the expected consumables can appear, in the intended tier order.
        products = productIDs.compactMap { id in
            fetched.first { $0.productIdentifier == id && $0.productType == .consumable }
        }
        if products.isEmpty {
            message = "Tips aren’t available right now. Please try again later."
        }
        // Recover an interrupted optional tip, without touching support purchases.
        for await verification in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = verification,
                  productIDs.contains(transaction.productID) else { continue }
            do {
                guard try await Purchases.shared.recordPurchase(.success(verification)) != nil else { continue }
                JotleySupporterStore.shared.recordVerifiedPurchase(id: String(transaction.id), kind: .tip)
                hasTipped = true; hasSupportedDevelopment = true
                preferences.set(true, forKey: Self.supportKey)
                await transaction.finish()
            } catch {
                message = "A previous tip is waiting for confirmation. Please try again later."
            }
        }
    }

    func purchase(_ product: StoreProduct) async {
        guard purchasingID == nil, products.contains(where: { $0.productIdentifier == product.productIdentifier }) else { return }
        purchasingID = product.productIdentifier
        message = nil
        purchaseDiagnostic = nil
        defer { purchasingID = nil }
        do {
            guard let nativeProduct = try await StoreKit.Product.products(for: [product.productIdentifier]).first,
                  nativeProduct.type == .consumable else {
                message = "This tip is unavailable right now. Please try again later."
                return
            }
            let result = try await nativeProduct.purchase()
            switch result {
            case .userCancelled:
                let cancelled = TipPurchaseFailure(ErrorCode.purchaseCancelledError)
                message = cancelled.message
                purchaseDiagnostic = cancelled.diagnostic
                return
            case .pending:
                message = "Your tip is waiting for App Store approval."
                return
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == product.productIdentifier else {
                    message = "Apple could not verify this tip. Please try again later."
                    return
                }
                // RevenueCat records only this optional tip. The app owns finishing
                // so it cannot prematurely finish a separate paid support ticket.
                guard try await Purchases.shared.recordPurchase(result) != nil else {
                    message = "Your tip is waiting for confirmation. Please try again later."
                    return
                }
                JotleySupporterStore.shared.recordVerifiedPurchase(id: String(transaction.id), kind: .tip)
                hasTipped = true
                hasSupportedDevelopment = true
                preferences.set(true, forKey: Self.supportKey)
                await transaction.finish()
            @unknown default:
                message = "Apple could not confirm this tip. Please try again later."
                return
            }
            message = nil
        } catch {
            let failure = TipPurchaseFailure(error)
            message = failure.message
            purchaseDiagnostic = failure.diagnostic
        }
    }
}

struct TipJarView: View {
    let appName: String
    let productPrefix: String
    let privacyURL: URL
    var onTipCompleted: () -> Void = {}
    @StateObject private var store = TipJarStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewCelebration: JotleySupporterStore.Celebration?

    private var accent: Color { ThemeManager.shared.currentThemeColor.color(in: colorScheme) }
    private var productIDs: [String] {
        ["small", "medium", "large"].map { productPrefix + "." + $0 }
    }

    private var showsCurrentSuccess: Bool {
        store.hasTipped && store.purchasingID == nil && store.message == nil
    }

    private var successConfirmation: some View {
        VStack(spacing: 10) {
            JotleySupporterEmblem()
            Text("Jotley Supporter")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("jotleySupporterBadge")
            VStack(spacing: 5) {
                Text(showsCurrentSuccess ? "Tip completed" : "Thank you for your support")
                    .font(.title3.bold())
                    .accessibilityIdentifier("tipJarSuccessTitle")
                Text(showsCurrentSuccess
                     ? "Thank you for supporting development. You’re all set—no further action is needed."
                     : "Your previous tip was received. You can leave another tip whenever you’d like.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tipJarSuccessDetail")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tipJarSuccess")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Support \(appName)", systemImage: "heart")
                    .font(.title2.bold())
                Spacer(minLength: 16)
                Button("Done") { dismiss() }
                    .jotleyDismissButtonStyle()
                    .disabled(store.purchasingID != nil)
                    .accessibilityIdentifier("tipJarDone")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.hasSupportedDevelopment {
                        successConfirmation
                    } else {
                        JotleySupporterBadge()
                    }
                    if store.hasSupportedDevelopment {
                        Text("Leave another tip (optional)")
                            .font(.headline)
                    } else {
                        Text("Leave an optional, one-time tip to support continued development. All note-taking features are free.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    tipChoices
                    if let message = store.message {
                        Text(message)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("tipJarStatus")
                        if let diagnostic = store.purchaseDiagnostic {
                            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                            ShareLink(item: "Jotley \(version) (\(build)) purchase: \(diagnostic)") {
                                Label("Share purchase diagnostic", systemImage: "square.and.arrow.up")
                            }
                            .font(.footnote)
                            .accessibilityIdentifier("tipJarShareDiagnostic")
                        }
                        if store.products.isEmpty && !store.isLoading {
                            Button("Try Again") { Task { await store.load(productIDs: productIDs) } }
                        }
                    }
                    Text("Each tip is a separate purchase, with no subscription or paid note-taking upgrade.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Privacy policy", destination: privacyURL).font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("tipJarContent")
        }
        .padding(24)
        .frame(idealWidth: 440, maxWidth: 560)
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #else
        .frame(idealHeight: 540, maxHeight: 650)
        #endif
        .tint(Color.themeActionText)
        .jotleySupporterCelebration(.tip, previewEvent: previewCelebration)
        .interactiveDismissDisabled(store.purchasingID != nil)
        .task {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["JOTLEY_TIP_DESIGN_PREVIEW"] != nil {
                if store.hasTipped { previewCelebration = .init(kind: .tip) }
                return
            }
            #endif
            await store.load(productIDs: productIDs)
        }
        .onChange(of: store.hasTipped) { _, completed in if completed { onTipCompleted() } }
    }

    @ViewBuilder private var tipChoices: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["JOTLEY_TIP_DESIGN_PREVIEW"] != nil {
            ForEach(0..<3) { index in
                tipLabel(["Small Tip", "Medium Tip", "Large Tip"][index],
                         price: ["$0.99", "$2.99", "$5.99"][index])
            }
        } else {
            storeTipChoices
        }
        #else
        storeTipChoices
        #endif
    }

    @ViewBuilder private var storeTipChoices: some View {
        if store.isLoading { ProgressView("Loading tips…") }
        ForEach(store.products, id: \.productIdentifier) { product in
            Button {
                Task { await store.purchase(product) }
            } label: {
                tipLabel(product.localizedTitle, price: product.localizedPriceString,
                         purchasing: store.purchasingID == product.productIdentifier)
            }
            .buttonStyle(.plain)
            .disabled(store.purchasingID != nil)
            .accessibilityIdentifier("tipJarProduct-" + product.productIdentifier)
        }
    }

    private func tipLabel(_ title: String, price: String, purchasing: Bool = false) -> some View {
        HStack(spacing: 16) {
            Text(title).fontWeight(.medium)
            Spacer(minLength: 0)
            if purchasing { ProgressView() } else { Text(price).monospacedDigit().fontWeight(.semibold) }
        }
        .modifier(TipRowSurface(accent: accent))
    }
}

private struct TipRowSurface: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        content
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(.background.secondary, in: shape)
            .overlay(shape.strokeBorder(accent, lineWidth: 1))
            .contentShape(shape)
    }
}

/// Keep presentation local so cancelling never records a completed tip.
struct NativeTipButton<Label: View>: View {
    let appName: String
    let productPrefix: String
    let privacyURL: URL
    let onTipCompleted: () -> Void
    let label: Label
    @State private var isPresented = false

    init(appName: String, productPrefix: String, privacyURL: URL,
         onTipCompleted: @escaping () -> Void = {}, @ViewBuilder label: () -> Label) {
        self.appName = appName
        self.productPrefix = productPrefix
        self.privacyURL = privacyURL
        self.onTipCompleted = onTipCompleted
        self.label = label()
    }

    var body: some View {
        Button { isPresented = true } label: { label }
            .sheet(isPresented: $isPresented) {
                TipJarView(appName: appName, productPrefix: productPrefix,
                           privacyURL: privacyURL, onTipCompleted: onTipCompleted)
            }
    }
}

struct JotleyTipButton<Label: View>: View {
    let label: Label
    init(@ViewBuilder label: () -> Label) { self.label = label() }
    var body: some View {
        NativeTipButton(appName: "Jotley", productPrefix: "com.protomota.jotley.tip",
                        privacyURL: URL(string: "https://jotley.ai/privacy")!,
                        onTipCompleted: { JotleyEngagement.shared.recordClick(.tip) }) { label }
    }
}
