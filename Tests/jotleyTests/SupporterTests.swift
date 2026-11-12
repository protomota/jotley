import XCTest
@testable import jotley

final class SupporterTests: XCTestCase {
    @MainActor func testVerifiedSupportAndTipsSharePersistentBadgeAndDeduplicateCelebrations() {
        let suite = "JotleySupporterTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = JotleySupporterStore(defaults: defaults)
        XCTAssertFalse(store.isSupporter)
        store.recognizeSupportPurchases([
            .init(id: "pending", provider: "stripe", status: "pending", used: nil),
            .init(id: "refunded", provider: "app_store", status: "refunded", used: nil)])
        XCTAssertFalse(store.isSupporter)
        XCTAssertNil(store.celebration)
        store.recognizeSupportPurchases([.init(id: "verified-ticket", provider: "app_store", status: "paid", used: false)])
        XCTAssertTrue(store.isSupporter)
        let first = store.celebration?.id
        XCTAssertNotNil(first)
        store.recognizeSupportPurchases([.init(id: "verified-ticket", provider: "app_store", status: "paid", used: true)])
        XCTAssertEqual(store.celebration?.id, first)
        let reopened = JotleySupporterStore(defaults: defaults)
        XCTAssertTrue(reopened.isSupporter)
        reopened.recordVerifiedPurchase(id: "verified-ticket", kind: .support)
        XCTAssertNil(reopened.celebration)
        reopened.recordVerifiedPurchase(id: "second-ticket", kind: .support)
        XCTAssertNotNil(reopened.celebration)
        let second = reopened.celebration!.id
        reopened.endCelebration(first!)
        XCTAssertEqual(reopened.celebration?.id, second)
        reopened.endCelebration(second)
        XCTAssertNil(reopened.celebration)
        reopened.recordVerifiedPurchase(id: "confirmed-tip", kind: .tip)
        XCTAssertEqual(reopened.celebration?.kind, .tip)
        let otherWindow = JotleySupporterStore(defaults: defaults)
        otherWindow.recordVerifiedPurchase(id: "confirmed-tip", kind: .tip)
        XCTAssertNil(otherWindow.celebration)
    }

    @MainActor func testPreviousTippersKeepTheirBadgeWithoutReplayingConfetti() {
        let suite = "JotleyPreviousSupporterTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "nativeTips.hasSupportedDevelopment.v1")
        let store = JotleySupporterStore(defaults: defaults)
        XCTAssertTrue(store.isSupporter)
        XCTAssertNil(store.celebration)
    }
}
