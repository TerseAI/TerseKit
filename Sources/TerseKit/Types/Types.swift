import Foundation

public struct Message: Identifiable, Hashable, Sendable {
    public enum Role: Sendable {
        case user
        case assistant
    }

    public enum Status: Sendable {
        case streaming
        case complete
        case failed
    }

    public let id: UUID
    public let role: Role
    public let author: String
    public let text: String
    public let reasoning: String
    public let createdAt: Date
    public let status: Status
    public let attachments: [ImageAttachmentResponse]

    public init(
        id: UUID = UUID(),
        role: Role,
        author: String? = nil,
        text: String,
        reasoning: String = "",
        createdAt: Date = .now,
        status: Status = .complete,
        attachments: [ImageAttachmentResponse] = []
    ) {
        self.id = id
        self.role = role
        self.author = author ?? (role == .assistant ? "Cloud Agent" : "You")
        self.text = text
        self.reasoning = reasoning
        self.createdAt = createdAt
        self.status = status
        self.attachments = attachments
    }
}

public enum Event: Sendable {
    case history([Message])
    case connectedUsers([ConnectUserResponse])
    case promptLockChanged(PromptLockResponse?)
    case promptDraftChanged(PromptDraftResponse)
    case generationStarted(
        generationID: UUID,
        prompt: String,
        user: ConnectUserResponse,
        createdAt: Date,
        attachments: [ImageAttachmentResponse]
    )
    case reasoningDelta(generationID: UUID, delta: String)
    case textDelta(generationID: UUID, delta: String)
    case generationCompleted(generationID: UUID, text: String, reasoning: String?)
    case generationFailed(generationID: UUID, message: String)
}

public struct TerseAPIError: LocalizedError, Sendable {
    public let status: Int
    public let code: String
    public let message: String
    public var errorDescription: String? { message }

    public init(status: Int, message: String, code: String = "request_failed") {
        self.status = status
        self.code = code
        self.message = message
    }
}

public struct PromptLockedError: LocalizedError, Sendable {
    public let lock: PromptLockResponse
    public var errorDescription: String? { "\(lock.user.name) is editing the prompt." }
}

struct APITransport {
    let apiKey: String
    let baseURL: URL
    let session: URLSession
}
