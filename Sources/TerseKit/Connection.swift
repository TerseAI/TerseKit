//
//  Connection.swift
//  TerseSwift
//
//  Created by Thomas Karatzas on 9/4/26.
//
import Foundation

public typealias ConnectedUser = ConnectUserResponse

public final class Connection {
    public let user: ConnectedUser
    public let agent: TerseAgent
    private let transport: APITransport
    private var heartbeatTask: Task<Void, Never>?
    
    internal init(user: ConnectedUser, agent: TerseAgent, transport: APITransport) {
        self.user = user
        self.agent = agent
        self.transport = transport
        resetHeartbeatTimer()
    }

    deinit {
        heartbeatTask?.cancel()
    }
    
    public func uploadImage(
        _ data: Data,
        name: String,
        mimeType: String
    ) async throws -> ImageAttachmentResponse {
        try await APIClient.uploadImage(
            data,
            name: name,
            mimeType: mimeType,
            agentID: agent.id,
            transport: transport
        )
    }

    public func clearHistory() async throws {
        try await APIClient.clearHistory(
            agentID: agent.id,
            transport: transport
        )
    }

    package func acquirePromptLock(
        lockID: String = UUID().uuidString,
        startedAt: Double = Date().timeIntervalSince1970 * 1_000
    ) async throws -> PromptLockResponse {
        resetHeartbeatTimer()
        let lock = try await APIClient.acquirePromptLock(
            connectionID: user.connectionId,
            lockID: lockID,
            startedAt: startedAt,
            agentID: agent.id,
            transport: transport
        )
        guard lock.lockId == lockID else { throw PromptLockedError(lock: lock) }
        return lock
    }

    package func releasePromptLock(lockID: String) async throws {
        resetHeartbeatTimer()
        try await APIClient.releasePromptLock(
            connectionID: user.connectionId,
            lockID: lockID,
            agentID: agent.id,
            transport: transport
        )
    }

    package func updatePromptDraft(
        lockID: String,
        text: String,
        sequence: Int,
        attachments: [ImageAttachmentResponse]? = nil
    ) async throws -> PromptDraftResponse {
        resetHeartbeatTimer()
        return try await APIClient.updatePromptDraft(
            connectionID: user.connectionId,
            lockID: lockID,
            text: text,
            sequence: sequence,
            attachments: attachments,
            agentID: agent.id,
            transport: transport
        )
    }

    public func sendPrompt(
        _ prompt: String,
        attachments: [ImageAttachmentResponse] = []
    ) async throws {
        let lock = try await acquirePromptLock()
        try await sendPrompt(
            prompt,
            promptLockID: lock.lockId,
            attachments: attachments
        )
    }

    package func sendPrompt(
        _ prompt: String,
        promptLockID: String,
        attachments: [ImageAttachmentResponse]
    ) async throws {
        do {
            resetHeartbeatTimer()
            try await APIClient.sendPrompt(
                prompt,
                connectionID: user.connectionId,
                promptLockID: promptLockID,
                attachments: attachments,
                agentID: agent.id,
                transport: transport
            )
        } catch {
            try? await releasePromptLock(lockID: promptLockID)
            throw error
        }
    }

    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // Heartbeat is necessary here to let the Durable Object know the client is Idle, but should still be connected.
    private func resetHeartbeatTimer() {
        heartbeatTask?.cancel()

        let connectionID = user.connectionId
        let agentID = agent.id
        let transport = transport
        heartbeatTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    try await APIClient.heartbeat(
                        connectionID: connectionID,
                        agentID: agentID,
                        transport: transport
                    )
                } catch is CancellationError {
                    return
                } catch {
                    // Retry after the next idle interval.
                }
            }
        }
    }
}
