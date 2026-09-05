import Foundation
import Observation
import TerseKit

/// Observable, live state for a specific Terse agent.
@MainActor
@Observable
public final class TerseAgentObserver {
    public enum Status: Equatable {
        case connecting
        case connected
        case unavailable
    }

    public let agentID: String
    public private(set) var messages: [Message] = []
    public private(set) var connectedUsers: [ConnectedUser] = []
    package private(set) var promptLock: PromptLockResponse?
    package private(set) var promptDraft: PromptDraftResponse?
    public private(set) var isGenerating = false
    public private(set) var generationError: String?
    public private(set) var status: Status = .connecting

    private let agent: TerseAgent
    private var eventHandlers: [UUID: (Event) -> Void] = [:]

    init(agent: TerseAgent) {
        self.agent = agent
        agentID = agent.id
    }

    /// Observes the agent until the calling task is cancelled.
    ///
    /// The initial presence snapshot is followed by live event updates. A
    /// dropped event stream reconnects automatically after a short delay.
    public func observe() async {
        while !Task.isCancelled {
            status = .connecting

            do {
                for try await event in agent.events() {
                    guard !Task.isCancelled else { return }
                    receive(event)
                }

                guard !Task.isCancelled else { return }
                status = .unavailable
            } catch {
                guard !Task.isCancelled else { return }
                status = .unavailable
            }

            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func receive(_ event: Event) {
        status = .connected

        switch event {
        case .history(let history):
            messages = history
            isGenerating = history.contains { $0.status == .streaming }

        case .connectedUsers(let users):
            connectedUsers = users

        case .promptLockChanged(let lock):
            promptLock = lock

        case .promptDraftChanged(let draft):
            promptDraft = draft

        case let .generationStarted(generationID, prompt, user, createdAt, attachments):
            guard !messages.contains(where: { $0.id == generationID }) else { return }
            generationError = nil
            isGenerating = true
            promptLock = nil
            promptDraft = nil
            messages.append(
                Message(
                    role: .user,
                    author: user.name,
                    text: prompt,
                    createdAt: createdAt,
                    attachments: attachments
                )
            )
            messages.append(
                Message(
                    id: generationID,
                    role: .assistant,
                    text: "",
                    createdAt: createdAt,
                    status: .streaming
                )
            )

        case let .reasoningDelta(generationID, delta):
            guard let message = message(generationID) else { return }
            updateAssistant(
                generationID,
                text: message.text,
                reasoning: message.reasoning + delta,
                status: .streaming
            )

        case let .textDelta(generationID, delta):
            guard let message = message(generationID) else { return }
            updateAssistant(
                generationID,
                text: message.text + delta,
                status: .streaming
            )

        case let .generationCompleted(generationID, text, reasoning):
            updateAssistant(
                generationID,
                text: text,
                reasoning: reasoning,
                status: .complete
            )
            isGenerating = false

        case let .generationFailed(generationID, message):
            if let current = self.message(generationID) {
                updateAssistant(
                    generationID,
                    text: current.text.isEmpty ? "Request failed." : current.text,
                    status: .failed
                )
            }
            generationError = message
            isGenerating = false
        }

        for handler in eventHandlers.values {
            handler(event)
        }
    }

    package func addEventHandler(_ handler: @escaping (Event) -> Void) -> UUID {
        let id = UUID()
        eventHandlers[id] = handler
        return id
    }

    package func removeEventHandler(_ id: UUID) {
        eventHandlers[id] = nil
    }

    private func message(_ id: UUID) -> Message? {
        messages.first { $0.id == id }
    }

    private func updateAssistant(
        _ id: UUID,
        text: String,
        reasoning: String? = nil,
        status: Message.Status
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let current = messages[index]
        messages[index] = Message(
            id: current.id,
            role: current.role,
            author: current.author,
            text: text,
            reasoning: reasoning ?? current.reasoning,
            createdAt: current.createdAt,
            status: status,
            attachments: current.attachments
        )
    }
}

public extension TerseAgent {
    @MainActor
    func observe() -> TerseAgentObserver {
        TerseAgentObserver(agent: self)
    }
}
