import Combine
import Foundation
import RevenueCat
import SwiftUI

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
                .with(storeKitVersion: .storeKit2)
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
    }

    func purchase(_ product: StoreProduct) async {
        guard purchasingID == nil, products.contains(where: { $0.productIdentifier == product.productIdentifier }) else { return }
        purchasingID = product.productIdentifier
        message = nil
        purchaseDiagnostic = nil
        defer { purchasingID = nil }
        do {
            let result = try await Purchases.shared.purchase(product: product)
            guard !result.userCancelled else {
                let cancelled = TipPurchaseFailure(ErrorCode.purchaseCancelledError)
                message = cancelled.message
                purchaseDiagnostic = cancelled.diagnostic
                return
            }
            guard result.transaction != nil else {
                message = "Your tip is still being confirmed by the App Store."
                return
            }
            hasTipped = true
            hasSupportedDevelopment = true
            preferences.set(true, forKey: Self.supportKey)
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
    var accent: Color = .purple
    var onTipCompleted: () -> Void = {}
    @StateObject private var store = TipJarStore()
    @Environment(\.dismiss) private var dismiss
    private var productIDs: [String] {
        ["small", "medium", "large"].map { productPrefix + "." + $0 }
    }

    private var showsCurrentSuccess: Bool {
        store.hasTipped && store.purchasingID == nil && store.message == nil
    }

    private var successConfirmation: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(showsCurrentSuccess ? "Tip completed" : "Thank you for your support")
                    .font(.title3.bold())
                    .accessibilityIdentifier("tipJarSuccessTitle")
                Text(showsCurrentSuccess
                     ? "Thank you for supporting development. You’re all set—no further action is needed."
                     : "Your previous tip was received. You can leave another tip whenever you’d like.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tipJarSuccessDetail")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.3)))
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
                    .disabled(store.purchasingID != nil)
                    .accessibilityIdentifier("tipJarDone")
            }
            if store.hasSupportedDevelopment {
                successConfirmation
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.hasSupportedDevelopment {
                        Text("Leave another tip (optional)")
                            .font(.headline)
                    } else {
                        Text("Leave an optional, one-time tip to support continued development. Every feature stays available whether or not you tip.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if store.isLoading {
                        ProgressView("Loading tips…")
                    }
                    ForEach(store.products, id: \.productIdentifier) { product in
                        Button {
                            Task { await store.purchase(product) }
                        } label: {
                            HStack(spacing: 16) {
                                Text(product.localizedTitle)
                                Spacer()
                                if store.purchasingID == product.productIdentifier {
                                    ProgressView()
                                } else {
                                    Text(product.localizedPriceString).fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.purchasingID != nil)
                        .accessibilityIdentifier("tipJarProduct-" + product.productIdentifier)
                    }
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
                    Text("Each tip is a separate purchase, with no subscription or feature unlock.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Privacy policy", destination: privacyURL).font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("tipJarContent")
        }
        .padding(24)
        .frame(idealWidth: 440, maxWidth: 560)
        .frame(idealHeight: 540, maxHeight: 650)
        .tint(accent)
        .interactiveDismissDisabled(store.purchasingID != nil)
        .task { await store.load(productIDs: productIDs) }
        .onDisappear { if store.hasTipped { onTipCompleted() } }
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
