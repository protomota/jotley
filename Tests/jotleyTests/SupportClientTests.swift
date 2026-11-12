import XCTest
@testable import jotley

final class SupportClientTests: XCTestCase {
    func testConversationAPIResponseDecodesWithoutChangingTheAppleContact() throws {
        let json = #"{"user":{"id":"11111111-1111-4111-8111-111111111111","email":"customer@private.icloud.com","isStaff":false},"tickets":[{"id":"ticket","reference":"JT-0123456789AB","subject":"Connect Claude","topic":"MCP setup","status":"open","purchase":{"id":"purchase","provider":"app_store","status":"paid"}}],"purchases":[{"id":"purchase","provider":"app_store","status":"paid"}]}"#
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let account = try decoder.decode(JotleySupportAccount.self, from: Data(json.utf8))
        XCTAssertEqual(account.user.email, "customer@private.icloud.com")
        XCTAssertFalse(account.user.isStaff)
        XCTAssertEqual(account.tickets.first?.purchase.id, account.purchases.first?.id)
    }
    func testMessageTransportPreservesHumanRoleAndMultilineText() throws {
        let json = #"{"id":"message","ticket_id":"ticket","sender_role":"support","body":"Hi, I’m Brad.\nLet’s connect Jotley.","created_at":"2026-11-10T12:00:00.123Z"}"#
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let message = try decoder.decode(JotleySupportMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.ticketId, "ticket")
        XCTAssertEqual(message.senderRole, "support")
        XCTAssertTrue(message.body.contains("\n"))
    }
    @MainActor func testAppleNonceMeetsTheServerContractAndIsUnique() {
        let values = (0..<100).map { _ in JotleySupportStore.nonce() }
        XCTAssertEqual(Set(values).count, values.count)
        for value in values {
            XCTAssertEqual(value.count, 64)
            XCTAssertTrue(value.allSatisfy { $0.isHexDigit && !$0.isUppercase })
            XCTAssertEqual(JotleySupportStore.hashedNonce(value).count, 64)
            XCTAssertNotEqual(JotleySupportStore.hashedNonce(value), value)
        }
    }
}
