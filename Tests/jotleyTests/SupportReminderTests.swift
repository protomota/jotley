import XCTest
@testable import jotley

final class SupportReminderTests: XCTestCase {
    private typealias Rules = JotleySupportReminderRules
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func testWaitsForFiveSuccessfulSummaries() {
        XCTAssertFalse(Rules.isDue(completed: 4, clicked: [], lastPresented: nil, now: start))
        XCTAssertTrue(Rules.isDue(completed: 5, clicked: [], lastPresented: nil, now: start))
    }

    func testReturnsAtMostOnceEverySevenDays() {
        XCTAssertFalse(Rules.isDue(completed: 50, clicked: [],
                                   lastPresented: start, now: start.addingTimeInterval(6 * day + 23 * 3600)))
        XCTAssertTrue(Rules.isDue(completed: 50, clicked: [],
                                  lastPresented: start, now: start.addingTimeInterval(7 * day)))
    }

    func testOneClickDoesNotStopTheReminder() {
        for action in Rules.requiredActions {
            XCTAssertTrue(Rules.isDue(completed: 5, clicked: [action], lastPresented: nil, now: start))
        }
        let threeOfFour = Rules.requiredActions.subtracting(["apps"]).union(["review"])
        XCTAssertTrue(Rules.isDue(completed: 5, clicked: threeOfFour, lastPresented: nil, now: start))
    }

    func testStopsOnceEveryActionIsChecked() {
        XCTAssertEqual(Rules.requiredActions, ["feedback", "share", "support", "apps"])
        XCTAssertTrue(Rules.allClicked(Rules.requiredActions))
        XCTAssertFalse(Rules.isDue(completed: 99, clicked: Rules.requiredActions.union(["review"]),
                                   lastPresented: nil, now: start))
    }

    func testOnlyEveryCheckmarkStopsTheReminder() {
        XCTAssertTrue(Rules.isDue(completed: 99, clicked: [],
                                  lastPresented: start, now: start.addingTimeInterval(365 * day)))
    }

    func testDontShowAgainStopsTheReminderForGood() {
        XCTAssertFalse(Rules.isDue(completed: 99, clicked: [], lastPresented: nil, now: start, dontShowAgain: true))
        XCTAssertFalse(Rules.isDue(completed: 99, clicked: [], lastPresented: start,
                                   now: start.addingTimeInterval(365 * day), dontShowAgain: true))
    }

    func testNativeReviewOnlyInProductionAppStoreBuilds() {
        XCTAssertTrue(Rules.allowsNativeReview(completed: 5, alreadyRequested: false, clickedReview: false,
                                               isProductionAppStore: true))
        XCTAssertFalse(Rules.allowsNativeReview(completed: 5, alreadyRequested: false, clickedReview: false,
                                                isProductionAppStore: false))
        XCTAssertFalse(Rules.allowsNativeReview(completed: 4, alreadyRequested: false, clickedReview: false,
                                                isProductionAppStore: true))
        XCTAssertFalse(Rules.allowsNativeReview(completed: 9, alreadyRequested: true, clickedReview: false,
                                                isProductionAppStore: true))
        XCTAssertFalse(Rules.allowsNativeReview(completed: 9, alreadyRequested: false, clickedReview: true,
                                                isProductionAppStore: true))
    }
}
