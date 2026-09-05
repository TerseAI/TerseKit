import Foundation

/// A lightweight handle to one shared, multi-user agent. Use this to listen to events from a particular Agent.
public struct TerseAgent {
    public let id: String
    private let transport: APITransport

    init(
        id: String,
        transport: APITransport
    ) {
        self.id = id
        self.transport = transport
    }

    public func activeUsers() async throws -> [ConnectUserResponse] {
        try await APIClient.activeUsers(
            agentID: id,
            transport: transport
        )
    }

    public func events() -> AsyncThrowingStream<Event, Error> {
        APIClient.events(
            agentID: id,
            transport: transport
        )
    }
}
