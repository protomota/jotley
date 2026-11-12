import Combine
import CryptoKit
import Foundation

/// A cosmetic thank-you, never a note feature entitlement or payment credit.
@MainActor final class JotleySupporterStore: ObservableObject {
    static let shared = JotleySupporterStore()
    enum Kind: String { case tip, support }
    struct Celebration: Identifiable {
        let id = UUID()
        let kind: Kind
        let startedAt = Date()
    }
    @Published private(set) var isSupporter: Bool
    @Published private(set) var celebration: Celebration?
    private let defaults: UserDefaults
    private var recognized: Set<String>
    private static let badgeKey = "jotley.supporter.v1"
    private static let recognizedKey = "jotley.supporter.recognizedPurchases.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isSupporter = defaults.bool(forKey: Self.badgeKey) || defaults.bool(forKey: "nativeTips.hasSupportedDevelopment.v1")
        recognized = Set(defaults.stringArray(forKey: Self.recognizedKey) ?? [])
        if isSupporter { defaults.set(true, forKey: Self.badgeKey) }
    }

    /// Call only after Apple/RevenueCat confirms a tip or the authenticated
    /// support API returns an owned, paid purchase. Polling/retries are deduped.
    func recordVerifiedPurchase(id: String, kind: Kind) {
        guard !id.isEmpty else { return }
        let key = SHA256.hash(data: Data((kind.rawValue + ":" + id).utf8)).map { String(format: "%02x", $0) }.joined()
        // Another window may already have thanked this purchase.
        recognized.formUnion(defaults.stringArray(forKey: Self.recognizedKey) ?? [])
        isSupporter = true
        defaults.set(true, forKey: Self.badgeKey)
        guard recognized.insert(key).inserted else { return }
        defaults.set(recognized.sorted(), forKey: Self.recognizedKey)
        celebration = Celebration(kind: kind)
    }

    func recognizeSupportPurchases(_ purchases: [JotleySupportPurchase]) {
        for purchase in purchases where purchase.status == "paid" && ["app_store", "stripe"].contains(purchase.provider) {
            recordVerifiedPurchase(id: purchase.id, kind: .support)
        }
    }

    func endCelebration(_ id: UUID) {
        if celebration?.id == id { celebration = nil }
    }
}
