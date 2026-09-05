import Foundation
import XCTest
@testable import TerseKit
@testable import TerseUI

final class TerseKitTests: XCTestCase {
    func testTerseConfigurationHoldsConnectionParameters() {
        let configuration = Terse.Configuration(
            baseURL: URL(string: "http://127.0.0.1:8790")!
        )

        XCTAssertEqual(configuration.baseURL.absoluteString, "http://127.0.0.1:8790")
    }

    func testTerseConnectsWithNamedConfiguration() {
        let terse = Terse.connect(.development)

        XCTAssertEqual(terse.agent("research-agent").id, "research-agent")
    }

    func testTerseResolvesAgent() {
        let terse = Terse.connect()

        XCTAssertEqual(terse.agent("research-agent").id, "research-agent")
    }

    @MainActor
    func testAgentObserverAppliesConnectedUserEvents() {
        let observer = Terse.connect()
            .agent("research-agent")
            .observe()
        let user = ConnectUserResponse(
            connectionId: "connection-1",
            name: "Sam",
            connectedAt: 42
        )

        observer.receive(.connectedUsers([user]))

        XCTAssertEqual(observer.agentID, "research-agent")
        XCTAssertEqual(observer.connectedUsers, [user])
        XCTAssertEqual(observer.status, .connected)
    }

    @MainActor
    func testAgentObserverAppliesStreamingEvents() {
        let observer = Terse.connect()
            .agent("research-agent")
            .observe()
        let generationID = UUID()
        let user = ConnectUserResponse(
            connectionId: "connection-1",
            name: "Sam",
            connectedAt: 42
        )

        observer.receive(
            .generationStarted(
                generationID: generationID,
                prompt: "Hello",
                user: user,
                createdAt: .now,
                attachments: []
            )
        )
        observer.receive(.reasoningDelta(generationID: generationID, delta: "Thinking"))
        observer.receive(.textDelta(generationID: generationID, delta: "Hi"))

        XCTAssertTrue(observer.isGenerating)
        XCTAssertEqual(observer.messages.map(\.text), ["Hello", "Hi"])
        XCTAssertEqual(observer.messages.last?.reasoning, "Thinking")

        observer.receive(
            .generationCompleted(
                generationID: generationID,
                text: "Hi there",
                reasoning: "Done"
            )
        )

        XCTAssertFalse(observer.isGenerating)
        XCTAssertEqual(observer.messages.last?.text, "Hi there")
        XCTAssertEqual(observer.messages.last?.reasoning, "Done")
    }

    func testMessageUsesRoleDefaultAuthor() {
        let userMessage = Message(role: .user, text: "Hello")
        let assistantMessage = Message(role: .assistant, text: "Hi")

        XCTAssertEqual(userMessage.author, "You")
        XCTAssertEqual(assistantMessage.author, "Cloud Agent")
    }

    func testPromptDraftDecodesWithoutAttachments() throws {
        let data = Data(
            #"{"leaseId":null,"sequence":3,"text":"Shared prompt","updatedAt":42}"#.utf8
        )

        let draft = try JSONDecoder().decode(PromptDraftResponse.self, from: data)

        XCTAssertEqual(draft.sequence, 3)
        XCTAssertEqual(draft.text, "Shared prompt")
        XCTAssertTrue(draft.attachments.isEmpty)
    }

    func testSocketEventDecodesAssociatedResponse() throws {
        let data = Data(
            #"{"type":"connected_users","users":[{"connectionId":"abc","name":"Sam","connectedAt":42}]}"#.utf8
        )

        let response = try JSONDecoder().decode(SocketEventResponse.self, from: data)

        guard case .connectedUsers(let users) = response else {
            return XCTFail("Expected a connected-users response")
        }
        XCTAssertEqual(users.first?.connectionId, "abc")
        XCTAssertEqual(users.first?.name, "Sam")
    }

    func testSocketEventPreservesUnknownEventType() throws {
        let data = Data(#"{"type":"future_event"}"#.utf8)

        let response = try JSONDecoder().decode(SocketEventResponse.self, from: data)

        guard case .unknown(let type) = response else {
            return XCTFail("Expected an unknown response")
        }
        XCTAssertEqual(type, "future_event")
        XCTAssertNil(response.event)
    }

    func testAPIErrorUsesServerMessage() {
        let error = TerseAPIError(status: 409, message: "Prompt locked", code: "locked")

        XCTAssertEqual(error.errorDescription, "Prompt locked")
    }
}

private extension Terse.Configuration {
    static let development = Self(
        baseURL: URL(string: "http://127.0.0.1:8790")!
    )
}
