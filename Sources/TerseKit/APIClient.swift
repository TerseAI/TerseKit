import Foundation

// This is the boundary between the Client and the Backend
enum APIClient {
    static func connectUser(
        name: String,
        agentID: String,
        transport: APITransport
    ) async throws -> ConnectUserResponse {
        var request = request(
            agentID: agentID,
            action: "connections",
            transport: transport
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ConnectUserRequest(name: name))
        return try await decode(ConnectUserResponse.self, from: request, transport: transport)
    }

    static func disconnectUser(
        connectionID: String,
        agentID: String,
        transport: APITransport
    ) async throws {
        var request = request(
            agentID: agentID,
            action: "connections/\(encoded(connectionID))",
            transport: transport
        )
        request.httpMethod = "DELETE"
        _ = try await data(for: request, transport: transport)
    }

    static func heartbeat(
        connectionID: String,
        agentID: String,
        transport: APITransport
    ) async throws {
        var request = request(
            agentID: agentID,
            action: "connections/\(encoded(connectionID))",
            transport: transport
        )
        request.httpMethod = "PUT"
        _ = try await data(for: request, transport: transport)
    }

    static func activeUsers(
        agentID: String,
        transport: APITransport
    ) async throws -> [ConnectUserResponse] {
        let request = request(
            agentID: agentID,
            action: "users",
            transport: transport
        )
        let response = try await decode(ListUsersResponse.self, from: request, transport: transport)
        return response.users
    }

    static func events(
        agentID: String,
        transport: APITransport
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let descriptor = try await presence(
                        agentID: agentID,
                        transport: transport
                    )
                    guard
                        let url = URL(string: descriptor.url),
                        let scheme = url.scheme?.lowercased(),
                        ["ws", "wss"].contains(scheme)
                    else {
                        throw TerseAPIError(
                            status: 0,
                            message: "The gateway returned an invalid presence URL."
                        )
                    }

                    let socket = transport.session.webSocketTask(with: url)
                    socket.resume()

                    try await withTaskCancellationHandler {
                        while !Task.isCancelled {
                            let message = try await socket.receive()
                            let data: Data
                            switch message {
                            case .data(let value):
                                data = value
                            case .string(let value):
                                data = Data(value.utf8)
                            @unknown default:
                                continue
                            }

                            let response = try JSONDecoder().decode(
                                SocketEventResponse.self,
                                from: data
                            )
                            if let event = response.event {
                                continuation.yield(event)
                            }
                        }
                    } onCancel: {
                        socket.cancel(with: .goingAway, reason: nil)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func uploadImage(
        _ imageData: Data,
        name: String,
        mimeType: String,
        agentID: String,
        transport: APITransport
    ) async throws -> ImageAttachmentResponse {
        guard imageData.count <= 5 * 1024 * 1024 else {
            throw TerseAPIError(status: 413, message: "Images must be 5 MB or smaller.")
        }

        let boundary = "TerseBoundary-\(UUID().uuidString)"
        let safeName = name
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data(
                "Content-Disposition: form-data; name=\"image\"; filename=\"\(safeName)\"\r\n".utf8
            )
        )
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = request(
            agentID: agentID,
            action: "attachments",
            transport: transport
        )
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        return try await decode(ImageAttachmentResponse.self, from: request, transport: transport)
    }

    static func clearHistory(
        agentID: String,
        transport: APITransport
    ) async throws {
        var request = request(
            agentID: agentID,
            action: "history",
            transport: transport
        )
        request.httpMethod = "DELETE"
        _ = try await data(for: request, transport: transport)
    }

    static func acquirePromptLock(
        connectionID: String,
        lockID: String,
        startedAt: Double,
        agentID: String,
        transport: APITransport
    ) async throws -> PromptLockResponse {
        var request = request(
            agentID: agentID,
            action: "composer-lock/\(encoded(connectionID))",
            transport: transport
        )
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PromptLockRequest(lockId: lockID, startedAt: startedAt)
        )
        return try await decode(PromptLockResponse.self, from: request, transport: transport)
    }

    static func releasePromptLock(
        connectionID: String,
        lockID: String,
        agentID: String,
        transport: APITransport
    ) async throws {
        var request = request(
            agentID: agentID,
            action: "composer-lock/\(encoded(connectionID))",
            transport: transport
        )
        request.httpMethod = "DELETE"
        request.url?.append(queryItems: [URLQueryItem(name: "lease_id", value: lockID)])
        _ = try await data(for: request, transport: transport)
    }

    static func updatePromptDraft(
        connectionID: String,
        lockID: String,
        text: String,
        sequence: Int,
        attachments: [ImageAttachmentResponse]?,
        agentID: String,
        transport: APITransport
    ) async throws -> PromptDraftResponse {
        var request = request(
            agentID: agentID,
            action: "composer-draft/\(encoded(connectionID))",
            transport: transport
        )
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PromptDraftRequest(
                lockId: lockID,
                sequence: sequence,
                text: text,
                attachmentIds: attachments?.map(\.id)
            )
        )
        return try await decode(PromptDraftResponse.self, from: request, transport: transport)
    }

    static func sendPrompt(
        _ prompt: String,
        connectionID: String,
        promptLockID: String,
        attachments: [ImageAttachmentResponse],
        agentID: String,
        transport: APITransport
    ) async throws {
        var request = request(
            agentID: agentID,
            action: "prompts",
            transport: transport
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PromptRequest(
                prompt: prompt,
                connectionId: connectionID,
                promptLockId: promptLockID,
                attachmentIds: attachments.map(\.id)
            )
        )
        _ = try await data(for: request, transport: transport)
    }

    private static func presence(
        agentID: String,
        transport: APITransport
    ) async throws -> PresenceResponse {
        let request = request(
            agentID: agentID,
            action: "presence",
            transport: transport
        )
        return try await decode(PresenceResponse.self, from: request, transport: transport)
    }

    private static func request(
        agentID: String,
        action: String,
        transport: APITransport
    ) -> URLRequest {
        let encodedAgentID = encoded(agentID)
        let url = URL(
            string: "/v1/agents/\(encodedAgentID)/\(action)",
            relativeTo: transport.baseURL
        )!.absoluteURL
        return URLRequest(url: url)
    }

    private static func data(
        for request: URLRequest,
        transport: APITransport
    ) async throws -> Data {
        let (data, response) = try await transport.session.data(for: request)
        try validate(response, data: data)
        return data
    }

    private static func decode<Response: Decodable>(
        _ type: Response.Type,
        from request: URLRequest,
        transport: APITransport
    ) async throws -> Response {
        let data = try await data(for: request, transport: transport)
        return try JSONDecoder().decode(type, from: data)
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TerseAPIError(status: 0, message: "The gateway returned an invalid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw apiError(status: http.statusCode, data: data)
        }
    }

    private static func apiError(status: Int, data: Data) -> TerseAPIError {
        let response = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
        return TerseAPIError(
            status: status,
            message: response?.error.message ?? "Request failed with status \(status).",
            code: response?.error.code ?? "request_failed"
        )
    }

    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
