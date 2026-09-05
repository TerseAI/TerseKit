import Foundation

/// A configured Terse client with at most one active agent connection.
public final class Terse {
    public private(set) var connection: Connection?

    private let transport: APITransport
    private var isConnecting = false

    private init(transport: APITransport) {
        self.transport = transport
    }
    
    /// Connect to the Backend
    public static func connect(
        apiKey: String,
        baseURL: URL = URL(string: "http://127.0.0.1:8790")!,
        session: URLSession = .shared
    ) -> Terse {
        Terse(
            transport: APITransport(
                apiKey: apiKey,
                baseURL: baseURL,
                session: session
            )
        )
    }

    /// Fetch and Agent. This let's you listen to an Agent with a specific ID
    public func agent(_ id: String) -> TerseAgent {
        TerseAgent(
            id: id,
            transport: transport
        )
    }
    
    /// Connects a user to an agent. One Terse instance supports one active connection at a time.
    public func connect(name: String, to agent: TerseAgent) async throws -> Connection {
        guard connection == nil, !isConnecting else {
            throw TerseAPIError(
                status: 0,
                message: "This Terse instance is already connected to an agent.",
                code: "client_already_connected"
            )
        }

        isConnecting = true
        defer { isConnecting = false }

        let user = try await APIClient.connectUser(
            name: name,
            agentID: agent.id,
            transport: transport
        )
        
        let connection = Connection(user: user, agent: agent, transport: transport)
        self.connection = connection
        
        return connection
    }

    /// Disconnect the Active connection.
    public func disconnect() async throws {
        guard let connection else {
            throw notConnectedError()
        }
        try await APIClient.disconnectUser(
            connectionID: connection.user.connectionId,
            agentID: connection.agent.id,
            transport: transport
        )

        connection.stopHeartbeat()
        self.connection = nil
    }

    private func notConnectedError() -> TerseAPIError {
        TerseAPIError(
            status: 0,
            message: "Connect this Terse instance to the agent first.",
            code: "client_not_connected"
        )
    }
}
