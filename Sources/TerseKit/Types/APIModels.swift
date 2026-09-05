//
//  APIModels.swift
//  TerseSwift
//
//  Created by Thomas Karatzas on 9/4/26.
//
import Foundation

// MARK: - Errors

struct APIErrorResponse: Codable {
    let error: Detail

    struct Detail: Codable {
        let code: String?
        let message: String
    }
}

// MARK: - Connections

struct ConnectUserRequest: Codable {
    let name: String
}

public struct ConnectUserResponse: Codable, Hashable, Sendable {
    public let connectionId: String
    public let name: String
    public let connectedAt: Double
}

struct ListUsersResponse: Codable {
    let users: [ConnectUserResponse]
}

// MARK: - Event Socket

struct EventSocketResponse: Codable {
    let url: String
    let expiresAt: Double
}

// MARK: - Prompt Lock

struct PromptLockRequest: Codable {
    let lockId: String
    let startedAt: Double

    private enum CodingKeys: String, CodingKey {
        case lockId = "leaseId"
        case startedAt
    }
}

public struct PromptLockResponse: Codable, Hashable, Sendable {
    package let lockId: String
    public let startedAt: Double
    public let user: ConnectUserResponse
    public let expiresAt: Double

    private enum CodingKeys: String, CodingKey {
        case lockId = "leaseId"
        case startedAt
        case user
        case expiresAt
    }
}

// MARK: - Prompt Draft

struct PromptDraftRequest: Codable {
    let lockId: String
    let sequence: Int
    let text: String
    let attachmentIds: [String]?

    private enum CodingKeys: String, CodingKey {
        case lockId = "leaseId"
        case sequence
        case text
        case attachmentIds
    }
}

public struct PromptDraftResponse: Codable, Hashable, Sendable {
    package let lockId: String?
    public let sequence: Int
    public let text: String
    public let attachments: [ImageAttachmentResponse]
    public let updatedAt: Double

    package init(
        lockId: String?,
        sequence: Int,
        text: String,
        attachments: [ImageAttachmentResponse] = [],
        updatedAt: Double
    ) {
        self.lockId = lockId
        self.sequence = sequence
        self.text = text
        self.attachments = attachments
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case lockId = "leaseId"
        case sequence
        case text
        case attachments
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lockId = try values.decodeIfPresent(String.self, forKey: .lockId)
        sequence = try values.decode(Int.self, forKey: .sequence)
        text = try values.decode(String.self, forKey: .text)
        attachments = try values.decodeIfPresent([ImageAttachmentResponse].self, forKey: .attachments) ?? []
        updatedAt = try values.decode(Double.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(lockId, forKey: .lockId)
        try values.encode(sequence, forKey: .sequence)
        try values.encode(text, forKey: .text)
        try values.encode(attachments, forKey: .attachments)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Attachments

public struct ImageAttachmentResponse: Codable, Hashable, Sendable {
    public let id: String
    public let type: String
    public let name: String
    public let mimeType: String
    public let size: Int
    public let url: String
}

// MARK: - Prompts

struct PromptRequest: Codable {
    let prompt: String
    let connectionId: String
    let promptLockId: String
    let attachmentIds: [String]

    private enum CodingKeys: String, CodingKey {
        case prompt
        case connectionId
        case promptLockId = "composerLeaseId"
        case attachmentIds
    }
}

// MARK: - Realtime Events

enum SocketEventResponse: Decodable {
    case history([ChatMessageResponse])
    case connectedUsers([ConnectUserResponse])
    case promptLock(PromptLockResponse?)
    case promptDraft(PromptDraftResponse)
    case generationStarted(
        generationID: UUID,
        prompt: String,
        user: ConnectUserResponse,
        createdAt: Double,
        attachments: [ImageAttachmentResponse]
    )
    case textDelta(generationID: UUID, delta: String)
    case reasoningDelta(generationID: UUID, delta: String)
    case generationCompleted(generationID: UUID, text: String, reasoning: String?)
    case generationFailed(generationID: UUID, message: String)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case messages
        case users
        case lock
        case draft
        case generationId
        case prompt
        case user
        case createdAt
        case attachments
        case delta
        case text
        case reasoning
        case message
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let type = try values.decode(String.self, forKey: .type)

        switch type {
        case "history":
            self = .history(
                try values.decodeIfPresent([ChatMessageResponse].self, forKey: .messages) ?? []
            )
        case "connected_users":
            self = .connectedUsers(
                try values.decodeIfPresent([ConnectUserResponse].self, forKey: .users) ?? []
            )
        case "composer_lock":
            self = .promptLock(
                try values.decodeIfPresent(PromptLockResponse.self, forKey: .lock)
            )
        case "composer_draft":
            self = .promptDraft(
                try values.decode(PromptDraftResponse.self, forKey: .draft)
            )
        case "generation_started":
            self = .generationStarted(
                generationID: try values.decode(UUID.self, forKey: .generationId),
                prompt: try values.decode(String.self, forKey: .prompt),
                user: try values.decode(ConnectUserResponse.self, forKey: .user),
                createdAt: try values.decode(Double.self, forKey: .createdAt),
                attachments: try values.decodeIfPresent(
                    [ImageAttachmentResponse].self,
                    forKey: .attachments
                ) ?? []
            )
        case "text_delta":
            self = .textDelta(
                generationID: try values.decode(UUID.self, forKey: .generationId),
                delta: try values.decode(String.self, forKey: .delta)
            )
        case "reasoning_delta":
            self = .reasoningDelta(
                generationID: try values.decode(UUID.self, forKey: .generationId),
                delta: try values.decode(String.self, forKey: .delta)
            )
        case "generation_completed":
            self = .generationCompleted(
                generationID: try values.decode(UUID.self, forKey: .generationId),
                text: try values.decode(String.self, forKey: .text),
                reasoning: try values.decodeIfPresent(String.self, forKey: .reasoning)
            )
        case "generation_failed":
            self = .generationFailed(
                generationID: try values.decode(UUID.self, forKey: .generationId),
                message: try values.decode(String.self, forKey: .message)
            )
        default:
            self = .unknown(type)
        }
    }

    var event: Event? {
        switch self {
        case .history(let messages):
            .history(messages.map(\.value))
        case .connectedUsers(let users):
            .connectedUsers(users)
        case .promptLock(let lock):
            .promptLockChanged(lock)
        case .promptDraft(let draft):
            .promptDraftChanged(draft)
        case let .generationStarted(generationID, prompt, user, createdAt, attachments):
            .generationStarted(
                generationID: generationID,
                prompt: prompt,
                user: user,
                createdAt: Date(timeIntervalSince1970: createdAt / 1_000),
                attachments: attachments
            )
        case let .textDelta(generationID, delta):
            .textDelta(generationID: generationID, delta: delta)
        case let .reasoningDelta(generationID, delta):
            .reasoningDelta(generationID: generationID, delta: delta)
        case let .generationCompleted(generationID, text, reasoning):
            .generationCompleted(generationID: generationID, text: text, reasoning: reasoning)
        case let .generationFailed(generationID, message):
            .generationFailed(generationID: generationID, message: message)
        case .unknown:
            nil
        }
    }
}

struct ChatMessageResponse: Codable {
    let id: UUID
    let role: String
    let author: String
    let text: String
    let reasoning: String?
    let createdAt: Double
    let status: String
    let attachments: [ImageAttachmentResponse]?

    var value: Message {
        let messageStatus: Message.Status
        switch status {
        case "streaming": messageStatus = .streaming
        case "failed": messageStatus = .failed
        default: messageStatus = .complete
        }

        return Message(
            id: id,
            role: role == "assistant" ? .assistant : .user,
            author: author,
            text: text,
            reasoning: reasoning ?? "",
            createdAt: Date(timeIntervalSince1970: createdAt / 1_000),
            status: messageStatus,
            attachments: attachments ?? []
        )
    }
}
