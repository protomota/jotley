import Combine
import RevenueCat
import SwiftUI

/// Consumable purchases are a thank-you, never a feature entitlement.
@MainActor
final class TipJarStore: ObservableObject {
    @Published private(set) var products: [StoreProduct] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingID: String?
    @Published private(set) var message: String?
    @Published private(set) var hasTipped = false

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
        defer { purchasingID = nil }
        do {
            let result = try await Purchases.shared.purchase(product: product)
            guard !result.userCancelled else { return }
            guard result.transaction != nil else {
                message = "Your tip is still being confirmed by the App Store."
                return
            }
            hasTipped = true
            message = "Thank you for supporting development!"
        } catch {
            switch (error as NSError).code {
            case ErrorCode.purchaseCancelledError.rawValue:
                break
            case ErrorCode.paymentPendingError.rawValue:
                message = "Your tip is waiting for App Store approval. No further action is needed here."
            default:
                message = "The App Store couldn’t complete your tip. Please try again later."
            }
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
            Text("Leave an optional, one-time tip to support continued development. Every feature stays available whether or not you tip.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                if store.products.isEmpty && !store.isLoading {
                    Button("Try Again") { Task { await store.load(productIDs: productIDs) } }
                }
            }
            Text("Each tip is a separate purchase, with no subscription or feature unlock.")
                .font(.footnote).foregroundStyle(.secondary)
            Link("Privacy policy", destination: privacyURL).font(.footnote)
        }
        .padding(24)
        .frame(idealWidth: 440, maxWidth: 560)
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
